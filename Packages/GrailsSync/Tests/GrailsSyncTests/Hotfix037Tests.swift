import Foundation
import XCTest
@testable import GrailsSync

final class Hotfix037Tests: XCTestCase {
    func testAFailedKeychainReadIsNotAnEmptyVault() {
        XCTAssertEqual(KeychainPolicy.load(bundle: .failed(-128), listing: .missing), .blocked)
        XCTAssertEqual(KeychainPolicy.load(bundle: .missing, listing: .failed(-25291)), .blocked)
        XCTAssertEqual(KeychainPolicy.load(bundle: .value(Data("not-json".utf8)), listing: .missing), .blocked)
        guard case .ready(let bundle, let persist) = KeychainPolicy.load(bundle: .missing, listing: .missing) else {
            return XCTFail("a missing item is an empty vault")
        }
        XCTAssertEqual(bundle, SecretBundle())
        XCTAssertFalse(persist)
        XCTAssertEqual(KeychainPolicy.store(updateStatus: KeychainPolicy.success), .updated)
        XCTAssertEqual(KeychainPolicy.store(updateStatus: KeychainPolicy.notFound), .add)
        XCTAssertEqual(KeychainPolicy.store(updateStatus: -128), .failed(-128))
    }

    func testAnInviteeTrustsTheOwnerKeyAndDoesNotPingPong() throws {
        let owner = DeviceKey()
        let member = DeviceKey()
        let body = TeamBody(generation: 4, ownerEmail: "o@studio.com", ownerPublicKey: owner.publicKey, minAppVersion: "0.3.7", members: [
            TeamMember(email: "o@studio.com", role: .owner),
            TeamMember(email: "m@studio.com", role: .member),
        ])
        let signed = try TeamDocument.sign(body, key: owner)
        let trusted = TeamDirectory.accept(signed: signed, trusted: nil, devices: [:])
        XCTAssertEqual(trusted?.body.generation, 4)
        XCTAssertEqual(trusted?.body.minAppVersion, "0.3.7")
        XCTAssertEqual(trusted?.pinnedOwnerKey, owner.publicKey)
        XCTAssertNil(TeamDirectory.accept(signed: try TeamDocument.sign(body, key: member), trusted: nil, devices: [:]))

        var newer = body
        newer.generation = 7
        newer.capGB = 12
        let caught = TeamDirectory.accept(signed: try TeamDocument.sign(newer, key: owner), trusted: trusted, devices: [:])
        XCTAssertEqual(caught?.body.generation, 7)
        XCTAssertNil(TeamDirectory.accept(signed: try TeamDocument.sign(body, key: owner), trusted: caught, devices: [:]))
        XCTAssertNil(TeamDirectory.accept(signed: try TeamDocument.sign(newer, key: member), trusted: trusted, devices: ["m@studio.com": member.publicKey]))
    }

    func testRestoreDayRebuildsTheLibraryAsOfThatDay() async throws {
        let earlyA = "snapshots/2026-10-11/items/a/item.json"
        let earlyB = "snapshots/2026-10-11/items/b/item.json"
        let earlyLibrary = "snapshots/2026-10-11/library.json"
        let laterA = "snapshots/2026-10-12/items/a/item.json"
        let futureB = "snapshots/2026-10-13/items/b/item.json"
        let heads = [earlyA, earlyB, earlyLibrary, laterA, futureB].map { ObjectHead(key: $0, etag: $0, size: 1) }
        let bodies = [
            earlyA: Data("old-a".utf8),
            earlyB: Data("bee".utf8),
            earlyLibrary: Data("lib".utf8),
            laterA: Data("new-a".utf8),
            futureB: Data("future".utf8),
        ]
        let written = RestoreBox()
        let restored = try await LibrarySnapshot.restoreDay("2026-10-12", snapshot: heads, read: { bodies[$0]! }, write: { key, data in
            await written.set(key, data)
        })
        XCTAssertEqual(restored, ["items/a/item.json", "items/b/item.json", "library.json"])
        let saved = await written.all()
        XCTAssertEqual(saved["items/a/item.json"], Data("new-a".utf8))
        XCTAssertEqual(saved["items/b/item.json"], Data("bee".utf8))
        XCTAssertEqual(saved["library.json"], Data("lib".utf8))
    }

    func testAMidPassErrorKeepsTheItemsAlreadySynced() async throws {
        let root = try TestLibrary.makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let (_, signed) = try TestLibrary.owner()
        try TestLibrary.writeLibrary(signed, root: root)
        let store = MemoryObjectStore()
        let first = Data("aaa".utf8)
        let second = Data("bbb".utf8)
        await store.seed("items/a/item.json", body: first)
        await store.seed("items/b/item.json", body: second)
        let flaky = FailOnGet(inner: store, key: "items/b/item.json")
        let cursor = root.appendingPathComponent("cursor.json")
        let engine = BucketSyncEngine(store: flaky, root: root, merger: ClosureMerger { _, local, _ in local }, appVersion: "0.3.5", cursorURL: cursor)
        do {
            _ = try await engine.syncOnce()
            XCTFail("the second download should fail")
        } catch let error as S3Error {
            XCTAssertEqual(error, .status(500, "mid-pass"))
        }
        let manifest = try JSONDecoder().decode(SyncManifest.self, from: Data(contentsOf: root.appendingPathComponent(".grails-sync.json")))
        XCTAssertNotNil(manifest.entries["items/a/item.json"])
        XCTAssertNil(manifest.entries["items/b/item.json"])
        let cursorManifest = try JSONDecoder().decode(SyncManifest.self, from: Data(contentsOf: cursor))
        XCTAssertEqual(cursorManifest.entries["items/a/item.json"]?.etag, manifest.entries["items/a/item.json"]?.etag)
        let again = BucketSyncEngine(store: store, root: root, merger: ClosureMerger { _, local, _ in local }, manifest: manifest, appVersion: "0.3.5")
        let report = try await again.syncOnce()
        XCTAssertFalse(report.downloaded.contains("items/a/item.json"))
        XCTAssertFalse(report.conflicts.contains("items/a/item.json"))
        XCTAssertTrue(report.downloaded.contains("items/b/item.json"))
    }

    func testClockSkewIsRetriedAndRevocationIsNot() {
        let skew = S3Error.status(403, "<Code>RequestTimeTooSkewed</Code>")
        let signature = S3Error.status(403, "<Code>SignatureDoesNotMatch</Code>")
        let revoked = S3Error.status(403, "<Code>InvalidAccessKeyId</Code>")
        XCTAssertTrue(SyncFailure.isRetryableAuth(skew))
        XCTAssertFalse(SyncFailure.isRevoked(skew))
        XCTAssertTrue(SyncFailure.isRetryableAuth(signature))
        XCTAssertFalse(SyncFailure.isRevoked(signature))
        XCTAssertFalse(SyncFailure.isRetryableAuth(revoked))
        XCTAssertTrue(SyncFailure.isRevoked(revoked))
        XCTAssertFalse(SyncFailure.isRevoked(S3Error.status(500, "unavailable")))
        XCTAssertFalse(SyncFailure.retryMessage.isEmpty)
    }

    func testContinuationTokensAreSignedTheWayTheyAreSent() {
        let token = "abc+def/ghi="
        let query = AWSSigV4.canonicalQuery(items: [
            URLQueryItem(name: "list-type", value: "2"),
            URLQueryItem(name: "continuation-token", value: token),
        ])
        XCTAssertTrue(query.contains("continuation-token=abc%2Bdef%2Fghi%3D"))
        XCTAssertFalse(query.contains("+"))
        XCTAssertFalse(query.contains(" "))
    }

    func testDevicesBindToTheRosterNotToAnEmailInsideAMemberFile() throws {
        let owner = DeviceKey()
        let roster = TeamBody(generation: 2, ownerEmail: "o@studio.com", ownerPublicKey: owner.publicKey, members: [
            TeamMember(email: "o@studio.com", role: .owner),
            TeamMember(email: "admin@studio.com", role: .admin),
            TeamMember(email: "member@studio.com", role: .member),
        ])
        let bound = DeviceBindings.map(files: [
            DeviceBindings.File(filename: "admin@studio.com.json", email: "attacker@evil.com", publicKey: "attacker-key"),
            DeviceBindings.File(filename: "member@studio.com.json", email: "member@studio.com", publicKey: "member-key"),
            DeviceBindings.File(filename: "o@studio.com.json", email: "o@studio.com", publicKey: "not-the-owner"),
            DeviceBindings.File(filename: "stranger@evil.com.json", email: "stranger@evil.com", publicKey: "stranger-key"),
        ], roster: roster)
        XCTAssertEqual(bound, ["member@studio.com": "member-key"])
        XCTAssertNil(bound["admin@studio.com"])
        XCTAssertNil(bound["o@studio.com"])
    }

    func testRemoteKeysCannotEscapeTheLibrary() {
        let root = URL(fileURLWithPath: "/tmp/grails-library", isDirectory: true)
        XCTAssertNil(SyncPath.url(root: root, key: "../outside"))
        XCTAssertNil(SyncPath.url(root: root, key: "items/../../etc/passwd"))
        XCTAssertNil(SyncPath.url(root: root, key: "/abs/item.json"))
        XCTAssertNil(SyncPath.url(root: root, key: "items//item.json"))
        let kept = SyncPath.url(root: root, key: "items/a/item.json")
        XCTAssertEqual(kept?.lastPathComponent, "item.json")
        XCTAssertTrue(kept?.path.contains("grails-library/items/a/item.json") == true)
    }

    func testSyncPassesDoNotOverlapAndASwitchCancelsTheInFlightPass() async throws {
        let root = try TestLibrary.makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let (_, signed) = try TestLibrary.owner()
        try TestLibrary.writeLibrary(signed, root: root)
        let gate = PassGate()
        let engine = BucketSyncEngine(store: gate, root: root, merger: ClosureMerger { _, local, _ in local }, appVersion: "0.3.5")
        let first = Task { try await engine.syncOnce() }
        let started = Date()
        while await gate.getCount() < 1 {
            if Date().timeIntervalSince(started) > 5 { return XCTFail("the first pass never started") }
            await Task.yield()
        }
        let second = Task { try await engine.syncOnce() }
        try await Task.sleep(nanoseconds: 200_000_000)
        let during = await gate.getCount()
        XCTAssertEqual(during, 1)
        await gate.release()
        _ = try await first.value
        _ = try await second.value
        let finished = await gate.getCount()
        XCTAssertGreaterThanOrEqual(finished, 2)

        let cancelRoot = try TestLibrary.makeRoot()
        defer { try? FileManager.default.removeItem(at: cancelRoot) }
        try TestLibrary.writeLibrary(signed, root: cancelRoot)
        let cancelGate = PassGate()
        let switching = BucketSyncEngine(store: cancelGate, root: cancelRoot, merger: ClosureMerger { _, local, _ in local }, appVersion: "0.3.5")
        let inflight = Task { try await switching.syncOnce() }
        let cancelStarted = Date()
        while await cancelGate.getCount() < 1 {
            if Date().timeIntervalSince(cancelStarted) > 5 { return XCTFail("the pass never started") }
            await Task.yield()
        }
        await switching.cancelInFlight()
        await cancelGate.release()
        do {
            _ = try await inflight.value
            XCTFail("the in-flight pass should stop")
        } catch is CancellationError {}
    }
}

private actor FailOnGet: ObjectStore {
    let inner: MemoryObjectStore
    let key: String

    init(inner: MemoryObjectStore, key: String) {
        self.inner = inner
        self.key = key
    }

    func list(prefix: String) async throws -> [ObjectHead] { try await inner.list(prefix: prefix) }

    func get(_ key: String) async throws -> ObjectGet {
        if key == self.key { throw S3Error.status(500, "mid-pass") }
        return try await inner.get(key)
    }

    func put(_ key: String, body: Data, contentType: String, ifMatch: String?, ifNoneMatch: String?) async throws -> String {
        try await inner.put(key, body: body, contentType: contentType, ifMatch: ifMatch, ifNoneMatch: ifNoneMatch)
    }

    func delete(_ key: String) async throws { try await inner.delete(key) }
}

private actor PassGate: ObjectStore {
    private let inner = MemoryObjectStore()
    private var gets = 0
    private var released = false
    private var hold: CheckedContinuation<Void, Never>?

    func getCount() -> Int { gets }

    func release() {
        released = true
        hold?.resume()
        hold = nil
    }

    func list(prefix: String) async throws -> [ObjectHead] { try await inner.list(prefix: prefix) }

    func get(_ key: String) async throws -> ObjectGet {
        gets += 1
        if gets == 1 {
            await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                if released {
                    cont.resume()
                } else {
                    hold = cont
                }
            }
        }
        return try await inner.get(key)
    }

    func put(_ key: String, body: Data, contentType: String, ifMatch: String?, ifNoneMatch: String?) async throws -> String {
        try await inner.put(key, body: body, contentType: contentType, ifMatch: ifMatch, ifNoneMatch: ifNoneMatch)
    }

    func delete(_ key: String) async throws { try await inner.delete(key) }
}

private actor RestoreBox {
    private var saved: [String: Data] = [:]

    func set(_ key: String, _ data: Data) { saved[key] = data }

    func all() -> [String: Data] { saved }
}
