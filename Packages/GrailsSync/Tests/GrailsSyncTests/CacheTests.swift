import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import XCTest
import GrailsSync

final class CacheTests: XCTestCase {
    func testS3RequestsFailInsteadOfHanging() {
        let config = HTTPTransport.uncached.configuration
        XCTAssertEqual(config.timeoutIntervalForRequest, 60)
        XCTAssertLessThanOrEqual(config.timeoutIntervalForResource, 40 * 60)
    }

    func testTransportIgnoresTheURLCache() async throws {
        let session = HTTPTransport.uncached
        XCTAssertNil(session.configuration.urlCache)
        XCTAssertEqual(session.configuration.requestCachePolicy, .reloadIgnoringLocalCacheData)
        XCTAssertTrue(HTTPTransport().session === HTTPTransport.uncached)

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [CachePolicyProbe.self]
        #if canImport(FoundationNetworking)
        config.urlCache = URLCache(memoryCapacity: 1024 * 1024, diskCapacity: 0, diskPath: nil)
        #else
        config.urlCache = URLCache(memoryCapacity: 1024 * 1024, diskCapacity: 0, directory: nil)
        #endif
        config.requestCachePolicy = .returnCacheDataElseLoad
        config.timeoutIntervalForRequest = 3
        config.timeoutIntervalForResource = 3
        let transport = HTTPTransport(session: URLSession(configuration: config))
        var request = URLRequest(url: URL(string: "http://grails-cache-probe.test/library.json")!)
        request.cachePolicy = .returnCacheDataElseLoad
        probeBox.reset()
        _ = try await transport.data(for: request)
        XCTAssertEqual(probeBox.policy, .reloadIgnoringLocalCacheData)
    }

    func testSweepDeletesTheStaleCacheOncePerVersion() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("grails-cache-\(UUID().uuidString)", isDirectory: true)
        let dir = root.appendingPathComponent(URLCacheSweep.bundleID, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let db = dir.appendingPathComponent("Cache.db")
        let wal = dir.appendingPathComponent("Cache.db-wal")
        try Data("stale".utf8).write(to: db)
        try Data("wal".utf8).write(to: wal)
        let suite = "xyz.arjoon.grails.cache-sweep.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        XCTAssertTrue(URLCacheSweep.clearOnce(cachesDirectory: root, version: "0.4", build: "12", defaults: defaults))
        XCTAssertFalse(FileManager.default.fileExists(atPath: db.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: wal.path))
        XCTAssertEqual(defaults.string(forKey: URLCacheSweep.defaultsKey), "0.4 (12)")

        try Data("again".utf8).write(to: db)
        XCTAssertFalse(URLCacheSweep.clearOnce(cachesDirectory: root, version: "0.4", build: "12", defaults: defaults))
        XCTAssertTrue(FileManager.default.fileExists(atPath: db.path))

        XCTAssertTrue(URLCacheSweep.clearOnce(cachesDirectory: root, version: "0.4", build: "13", defaults: defaults))
        XCTAssertFalse(FileManager.default.fileExists(atPath: db.path))
    }
}

private let probeBox = CachePolicyProbeBox()

private final class CachePolicyProbe: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == "grails-cache-probe.test"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        probeBox.policy = request.cachePolicy
        let url = request.url ?? URL(string: "http://grails-cache-probe.test/")!
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: [:])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data())
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private final class CachePolicyProbeBox: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: URLRequest.CachePolicy?

    var policy: URLRequest.CachePolicy? {
        get { lock.lock(); defer { lock.unlock() }; return stored }
        set { lock.lock(); stored = newValue; lock.unlock() }
    }

    func reset() { policy = nil }
}
