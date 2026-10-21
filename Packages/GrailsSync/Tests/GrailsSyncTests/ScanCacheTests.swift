import XCTest
@testable import GrailsSync

final class ScanCacheTests: XCTestCase {
    /// Far enough ahead that every file written in the test counts as settled.
    private let later = Date().addingTimeInterval(60)

    func testAnUnchangedFileIsNotReadAgain() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try write("one", to: root, "items/a/item.json")
        try write("two", to: root, "items/b/item.json")
        var cache = ScanCache()
        let first = try LibraryScanner.scan(root: root, cache: &cache, now: later)
        XCTAssertEqual(cache.lastHashed.sorted(), ["items/a/item.json", "items/b/item.json"])
        let second = try LibraryScanner.scan(root: root, cache: &cache, now: later)
        XCTAssertEqual(cache.lastHashed, [])
        XCTAssertEqual(second, first)
    }

    func testAnEditedFileIsHashedAgain() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try write("one", to: root, "items/a/item.json")
        try write("two", to: root, "items/b/item.json")
        var cache = ScanCache()
        _ = try LibraryScanner.scan(root: root, cache: &cache, now: later)
        try write("edited", to: root, "items/a/item.json")
        let scanned = try LibraryScanner.scan(root: root, cache: &cache, now: later)
        XCTAssertEqual(cache.lastHashed, ["items/a/item.json"])
        XCTAssertEqual(scanned.first { $0.key == "items/a/item.json" }?.digest, Digests.sha256Hex(Data("edited".utf8)))
    }

    /// Same size and the content date put back: the attribute date (ctime) still moves, so the edit is not missed.
    func testASameSizeEditWithTheOldDateIsStillCaught() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = try write("aaaa", to: root, "items/a/item.json")
        let modified = try FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date
        var cache = ScanCache()
        _ = try LibraryScanner.scan(root: root, cache: &cache, now: later)
        Thread.sleep(forTimeInterval: 0.01)
        try Data("bbbb".utf8).write(to: url)
        try FileManager.default.setAttributes([.modificationDate: modified as Any], ofItemAtPath: url.path)
        let scanned = try LibraryScanner.scan(root: root, cache: &cache, now: later)
        XCTAssertEqual(cache.lastHashed, ["items/a/item.json"])
        XCTAssertEqual(scanned.first?.digest, Digests.sha256Hex(Data("bbbb".utf8)))
    }

    func testADeletedFileLeavesTheScanAndTheCache() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let gone = try write("one", to: root, "items/a/item.json")
        try write("two", to: root, "items/b/item.json")
        var cache = ScanCache()
        _ = try LibraryScanner.scan(root: root, cache: &cache, now: later)
        try FileManager.default.removeItem(at: gone)
        let scanned = try LibraryScanner.scan(root: root, cache: &cache, now: later)
        XCTAssertEqual(scanned.map(\.key), ["items/b/item.json"])
        XCTAssertEqual(cache.lastHashed, [])
        XCTAssertEqual(Set(cache.entries.keys), ["items/b/item.json"])
    }

    /// A file hashed inside the timestamp tick it was written in could change again without its stamp moving. It is read again until it settles.
    func testAFreshFileIsNotTrustedUntilItSettles() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try write("one", to: root, "items/a/item.json")
        var cache = ScanCache()
        _ = try LibraryScanner.scan(root: root, cache: &cache, now: Date())
        _ = try LibraryScanner.scan(root: root, cache: &cache, now: later)
        XCTAssertEqual(cache.lastHashed, ["items/a/item.json"])
        _ = try LibraryScanner.scan(root: root, cache: &cache, now: later)
        XCTAssertEqual(cache.lastHashed, [])
    }

    func testAFullScanIgnoresTheCache() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try write("one", to: root, "items/a/item.json")
        var cache = ScanCache()
        _ = try LibraryScanner.scan(root: root, cache: &cache, now: later)
        _ = try LibraryScanner.scan(root: root, cache: &cache, rehash: true, now: later)
        XCTAssertEqual(cache.lastHashed, ["items/a/item.json"])
    }

    func testTheCachedScanMatchesAFullScan() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try write("{}", to: root, "library.json")
        try write("one", to: root, "items/a/item.json")
        try write("skip", to: root, "items/a/.DS_Store")
        var cache = ScanCache()
        _ = try LibraryScanner.scan(root: root, cache: &cache, now: later)
        XCTAssertEqual(try LibraryScanner.scan(root: root, cache: &cache, now: later), try LibraryScanner.scan(root: root))
    }

    func testTheEngineUploadsAnEditAndADeleteBetweenPolls() async throws {
        let root = try TestLibrary.makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let (_, signed) = try TestLibrary.owner()
        try TestLibrary.writeLibrary(signed, root: root)
        try write("first", to: root, "items/a/item.json")
        try write("stays", to: root, "items/b/item.json")
        let store = MemoryObjectStore()
        let engine = BucketSyncEngine(store: store, root: root, merger: ClosureMerger { _, local, _ in local }, appVersion: "0.3.5")
        _ = try await engine.syncOnce(now: Date(timeIntervalSince1970: 1_700_000_000))
        try write("second", to: root, "items/a/item.json")
        try FileManager.default.removeItem(at: root.appendingPathComponent("items/b/item.json"))
        let report = try await engine.syncOnce(now: Date(timeIntervalSince1970: 1_700_000_100))
        XCTAssertEqual(report.uploaded, ["items/a/item.json"])
        XCTAssertEqual(report.trashed, ["items/b/item.json"])
        let body = await store.body("items/a/item.json")
        XCTAssertEqual(body, Data("second".utf8))
    }

    private func makeRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("grails-scan-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    @discardableResult
    private func write(_ text: String, to root: URL, _ key: String) throws -> URL {
        let url = root.appendingPathComponent(key)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
        return url
    }
}
