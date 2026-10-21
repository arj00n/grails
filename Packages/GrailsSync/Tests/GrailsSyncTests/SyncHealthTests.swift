import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import XCTest
@testable import GrailsSync

final class SyncHealthTests: XCTestCase {
    func testStatusStaysQuietUntilFailuresRepeatOrRunLongAndClearsOnSuccess() {
        var health = SyncHealth.clean
        health = health.next(.failed(0.030))
        XCTAssertFalse(health.showing)
        XCTAssertEqual(health.streak, 1)
        health = health.next(.failed(1.4))
        XCTAssertFalse(health.showing)
        health = health.next(.failed(30))
        XCTAssertTrue(health.showing)
        XCTAssertEqual(health.streak, 3)
        health = health.next(.success)
        XCTAssertEqual(health, .clean)

        var once = SyncHealth.clean.next(.failed(119))
        XCTAssertFalse(once.showing)
        once = SyncHealth.clean.next(.failed(120))
        XCTAssertTrue(once.showing)
        once = once.next(.failed(0.011))
        XCTAssertTrue(once.showing)
        XCTAssertEqual(once.next(.success), .clean)

        var offline = SyncHealth.clean.next(.offline)
        offline = offline.next(.cancelled)
        XCTAssertEqual(offline, .clean)
        let latched = SyncHealth(streak: 3, showing: true).next(.offline)
        XCTAssertTrue(latched.showing)
    }

    func testOfflineIsNotSyncFailingAndARevokedLibraryStaysDisconnected() {
        let healthy = SyncHealth.clean
        XCTAssertNil(SyncHealth.banner(revoked: false, connected: true, shared: true, reachable: true, health: healthy))
        XCTAssertEqual(
            SyncHealth.banner(revoked: false, connected: true, shared: true, reachable: false, health: SyncHealth(streak: 3, showing: true)),
            .offline
        )
        XCTAssertEqual(SyncHealth.Banner.offline.label, "Offline")
        XCTAssertEqual(
            SyncHealth.banner(revoked: false, connected: true, shared: true, reachable: true, health: SyncHealth(streak: 3, showing: true)),
            .failing
        )
        XCTAssertEqual(SyncHealth.Banner.failing.label, "Sync failing")
        XCTAssertEqual(
            SyncHealth.banner(revoked: true, connected: false, shared: true, reachable: false, health: healthy),
            .disconnected
        )
        XCTAssertNil(SyncHealth.banner(revoked: false, connected: false, shared: false, reachable: false, health: healthy))
    }

    func testSleepAndPathChangesCancelThePassAndWakeStartsAnother() {
        XCTAssertEqual(SyncInterrupt.response(.willSleep), .init(cancel: true, fresh: false, reachable: nil))
        XCTAssertEqual(SyncInterrupt.response(.didWake), .init(cancel: true, fresh: true, reachable: nil))
        XCTAssertEqual(SyncInterrupt.response(.pathUnsatisfied), .init(cancel: true, fresh: false, reachable: false))
        XCTAssertEqual(SyncInterrupt.response(.pathSatisfied), .init(cancel: true, fresh: true, reachable: true))
    }

    func testFailureLogNamesTheStepAndDropsSignedUrls() {
        let body = "https://bucket.example/library.json?X-Amz-Signature=secretvalue&X-Amz-Credential=AKIASECRET"
        let line = SyncFailureLog.line(step: .get, error: S3Error.status(500, body), milliseconds: 1400)
        XCTAssertTrue(line.contains("poll failed"))
        XCTAssertTrue(line.contains("step=get"))
        XCTAssertTrue(line.contains("ms=1400"))
        XCTAssertTrue(line.contains("domain=S3Error"))
        XCTAssertTrue(line.contains("code=500"))
        XCTAssertFalse(line.contains("secretvalue"))
        XCTAssertFalse(line.contains("AKIASECRET"))
        XCTAssertFalse(line.contains("https://"))
        let stalled = SyncFailureLog.line(step: .put, error: TransferStall(), milliseconds: 90_000)
        XCTAssertTrue(stalled.contains("step=put"))
        XCTAssertTrue(stalled.contains("reason=stalled"))
        XCTAssertFalse(stalled.contains("\n"))
    }

    func testCancelOnSleepStopsAHungPass() async throws {
        let root = try TestLibrary.makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let (_, signed) = try TestLibrary.owner()
        try TestLibrary.writeLibrary(signed, root: root)
        let store = SleepingStore()
        let engine = BucketSyncEngine(store: store, root: root, merger: ClosureMerger { _, local, _ in local }, appVersion: "0.3.11")
        let pass = Task { try await engine.syncOnce() }
        let ready = Date()
        while await !store.began() {
            if Date().timeIntervalSince(ready) > 5 { return XCTFail("the pass never reached the request") }
            await Task.yield()
        }
        let started = Date()
        await engine.cancelInFlight()
        do {
            _ = try await pass.value
            XCTFail("the hung pass should stop")
        } catch is CancellationError {}
        XCTAssertLessThan(Date().timeIntervalSince(started), 2)
    }

    func testAQuietTransferIsStaleAndBytesResetTheClock() {
        let delegate = TransferDelegate(stall: 90, now: { Date(timeIntervalSince1970: 1_000) })
        delegate.note(1, at: 1_000)
        XCTAssertFalse(delegate.staleIDs(at: 1_060).contains(1))
        XCTAssertTrue(delegate.staleIDs(at: 1_090).contains(1))
        delegate.note(1, at: 1_089)
        XCTAssertFalse(delegate.staleIDs(at: 1_090).contains(1))
    }

    func testAStalledTransferFailsWithoutWaitingForTheResourceCap() async throws {
        let delegate = TransferDelegate(stall: 0.4, now: Date.init)
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StallProbe.self]
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 30
        let session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        delegate.start(session: session, every: .milliseconds(50), tolerance: .milliseconds(10))
        let transport = HTTPTransport(session: session)
        var request = URLRequest(url: URL(string: "http://grails-stall.test/file")!)
        request.timeoutInterval = 30
        let started = Date()
        do {
            _ = try await transport.data(for: request)
            XCTFail("a transfer with no bytes should fail")
        } catch is TransferStall {
            XCTAssertLessThan(Date().timeIntervalSince(started), 3)
        }
    }
}

private actor SleepingStore: ObjectStore {
    private var started = false

    func began() -> Bool { started }

    func list(prefix: String) async throws -> [ObjectHead] { [] }

    func get(_ key: String) async throws -> ObjectGet {
        started = true
        try await Task.sleep(for: .seconds(30))
        return ObjectGet(body: Data(), etag: "slept")
    }

    func put(_ key: String, body: Data, contentType: String, ifMatch: String?, ifNoneMatch: String?) async throws -> String { "slept" }

    func delete(_ key: String) async throws {}
}

private final class StallProbe: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == "grails-stall.test"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let url = request.url ?? URL(string: "http://grails-stall.test/")!
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: [:])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data([1]))
    }

    override func stopLoading() {}
}
