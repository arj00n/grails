import Foundation
import XCTest
@testable import GrailsSync

final class SyncTests: XCTestCase {
    func testThumbnailsSortFirst() {
        let plan = SyncPlanner.plan(
            local: [
                LocalObject(key: "items/b/original.jpg", bytes: 20, digest: "b"),
                LocalObject(key: "items/a/thumb.jpg", bytes: 10, digest: "a"),
                LocalObject(key: "items/a/original.jpg", bytes: 30, digest: "c"),
            ],
            remote: [],
            manifest: [:],
            capBytes: 9_000_000_000,
            maxFileBytes: 200_000_000,
            rateRemaining: 500_000_000
        )
        XCTAssertEqual(plan.uploads.map(\.key), ["items/a/thumb.jpg", "items/a/original.jpg", "items/b/original.jpg"])
        XCTAssertEqual(plan.uploads.first?.ifNoneMatch, "*")
    }

    func testFullBucketPausesUploadsIncludingReplacements() {
        let remote = [ObjectHead(key: "items/a/original.jpg", etag: "e", size: 100)]
        let manifest = ["items/a/original.jpg": ManifestEntry(etag: "e", digest: "old", size: 100)]
        let plan = SyncPlanner.plan(
            local: [LocalObject(key: "items/a/original.jpg", bytes: 100, digest: "new")],
            remote: remote,
            manifest: manifest,
            capBytes: 100,
            maxFileBytes: 200,
            rateRemaining: 500
        )
        XCTAssertEqual(plan.paused, ["items/a/original.jpg"])
        XCTAssertTrue(plan.uploads.isEmpty)
        XCTAssertEqual(StoragePolicy.notice(used: 8, cap: 10, role: .admin), .warning(used: 8, cap: 10))
        XCTAssertEqual(StoragePolicy.notice(used: 8, cap: 10, role: .member), .none)
        XCTAssertEqual(StoragePolicy.notice(used: 10, cap: 10, role: .member), .full(used: 10, cap: 10))
        XCTAssertEqual(Capacity.level(used: 7, cap: 10), .ok)
    }

    func testFileSizeAndRateLimit() {
        let plan = SyncPlanner.plan(
            local: [
                LocalObject(key: "big.bin", bytes: 201, digest: "big"),
                LocalObject(key: "a.bin", bytes: 40, digest: "a"),
                LocalObject(key: "b.bin", bytes: 30, digest: "b"),
            ],
            remote: [],
            manifest: [:],
            capBytes: 1_000,
            maxFileBytes: 200,
            rateRemaining: 50
        )
        XCTAssertEqual(plan.tooLarge, ["big.bin"])
        XCTAssertEqual(plan.uploads.map(\.key), ["a.bin"])
        XCTAssertEqual(plan.rateLimited, ["b.bin"])
    }

    func testAProfilePhotoCountsTowardTheCapAndTheRate() {
        let photo = LocalObject(key: ".members/m-ada.avatar.jpg", bytes: 40_000, digest: "photo")
        let item = LocalObject(key: "items/a/item.json", bytes: 20_000, digest: "item")
        let capped = SyncPlanner.plan(
            local: [photo, item],
            remote: [],
            manifest: [:],
            capBytes: 50_000,
            maxFileBytes: 200_000_000,
            rateRemaining: 500_000_000
        )
        XCTAssertEqual(capped.uploads.map(\.key), [".members/m-ada.avatar.jpg"])
        XCTAssertEqual(capped.paused, ["items/a/item.json"])
        let limited = SyncPlanner.plan(
            local: [photo, item],
            remote: [],
            manifest: [:],
            capBytes: 9_000_000_000,
            maxFileBytes: 200_000_000,
            rateRemaining: 40_000
        )
        XCTAssertEqual(limited.uploads.map(\.key), [".members/m-ada.avatar.jpg"])
        XCTAssertEqual(limited.rateLimited, ["items/a/item.json"])
        let over = SyncPlanner.plan(
            local: [LocalObject(key: ".members/m-ada.avatar.jpg", bytes: 200_000_001, digest: "raw")],
            remote: [],
            manifest: [:],
            capBytes: 9_000_000_000,
            maxFileBytes: Int64(TeamBody.defaultMaxFileMB) * 1_000_000,
            rateRemaining: 500_000_000
        )
        XCTAssertEqual(over.tooLarge, [".members/m-ada.avatar.jpg"])
    }

    func testDeleteBecomesTrashWhenTheRemoteCopyIsUnchanged() {
        let plan = SyncPlanner.plan(
            local: [],
            remote: [ObjectHead(key: "items/a/item.json", etag: "e1", size: 10)],
            manifest: ["items/a/item.json": ManifestEntry(etag: "e1", digest: "d", size: 10)],
            capBytes: 1_000,
            maxFileBytes: 200,
            rateRemaining: 500
        )
        XCTAssertEqual(plan.trashes, ["items/a/item.json"])
        let changed = SyncPlanner.plan(
            local: [],
            remote: [ObjectHead(key: "items/a/item.json", etag: "e2", size: 10)],
            manifest: ["items/a/item.json": ManifestEntry(etag: "e1", digest: "d", size: 10)],
            capBytes: 1_000,
            maxFileBytes: 200,
            rateRemaining: 500
        )
        XCTAssertEqual(changed.downloads, ["items/a/item.json"])
        XCTAssertTrue(changed.trashes.isEmpty)
    }

    func testMemberFilesDownloadWhenOnlyTheBucketChanged() {
        let plan = SyncPlanner.plan(
            local: [LocalObject(key: ".members/ada@studio.com.json", bytes: 4, digest: "same")],
            remote: [ObjectHead(key: ".members/ada@studio.com.json", etag: "remote", size: 4)],
            manifest: [".members/ada@studio.com.json": ManifestEntry(etag: "old", digest: "same", size: 4)],
            capBytes: 1_000,
            maxFileBytes: 200,
            rateRemaining: 500
        )
        XCTAssertEqual(plan.downloads, [".members/ada@studio.com.json"])
        XCTAssertTrue(plan.uploads.isEmpty)
    }

    func testMemberNameEditUploadsWhenTheBucketCopyIsUnchanged() {
        let plan = SyncPlanner.plan(
            local: [LocalObject(key: ".members/ada@studio.com.json", bytes: 8, digest: "renamed")],
            remote: [ObjectHead(key: ".members/ada@studio.com.json", etag: "e1", size: 4)],
            manifest: [".members/ada@studio.com.json": ManifestEntry(etag: "e1", digest: "old", size: 4)],
            capBytes: 1_000,
            maxFileBytes: 200,
            rateRemaining: 500
        )
        XCTAssertEqual(plan.uploads.map(\.key), [".members/ada@studio.com.json"])
        XCTAssertTrue(plan.downloads.isEmpty)
    }

    func testSecondSyncUploadsNothing() async throws {
        let root = try TestLibrary.makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let (_, signed) = try TestLibrary.owner()
        try TestLibrary.writeLibrary(signed, root: root)
        try Data("thumb".utf8).write(to: nested(root, "items/a/thumb.jpg"))
        let store = MemoryObjectStore()
        let engine = BucketSyncEngine(store: store, root: root, merger: ClosureMerger { _, local, _ in local }, appVersion: "0.3.5")
        let first = try await engine.syncOnce(now: Date(timeIntervalSince1970: 1_700_000_000))
        XCTAssertEqual(first.uploaded, ["items/a/thumb.jpg", "library.json"])
        let second = try await engine.syncOnce(now: Date(timeIntervalSince1970: 1_700_000_010))
        XCTAssertTrue(second.uploaded.isEmpty)
        XCTAssertTrue(second.downloaded.isEmpty)
        XCTAssertNil(second.blocked)
    }

    func testConflictPutsWithTheRemoteETag() async throws {
        let root = try TestLibrary.makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let (_, signed) = try TestLibrary.owner()
        try TestLibrary.writeLibrary(signed, root: root)
        let local = Data("local-item".utf8)
        try local.write(to: nested(root, "items/a/item.json"))
        let store = MemoryObjectStore()
        await store.seed("items/a/item.json", body: Data("remote-item".utf8), etag: "remote-etag")
        var manifest = SyncManifest()
        manifest.entries["items/a/item.json"] = ManifestEntry(etag: "old-etag", digest: "neither", size: 1)
        let engine = BucketSyncEngine(store: store, root: root, merger: ClosureMerger { _, local, remote in local + remote }, manifest: manifest, appVersion: "0.3.5")
        let report = try await engine.syncOnce()
        XCTAssertEqual(report.conflicts, ["items/a/item.json"])
        let put = await store.recordedPuts().first { $0.key == "items/a/item.json" }
        XCTAssertEqual(put?.ifMatch, "remote-etag")
        XCTAssertEqual(put?.body, Data("local-itemremote-item".utf8))
    }

    func testLocalDeleteMovesTheObjectToTrash() async throws {
        let root = try TestLibrary.makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let (_, signed) = try TestLibrary.owner()
        try TestLibrary.writeLibrary(signed, root: root)
        let store = MemoryObjectStore()
        let body = Data("gone".utf8)
        await store.seed("items/a/item.json", body: body, etag: "e1")
        var manifest = SyncManifest()
        manifest.entries["items/a/item.json"] = ManifestEntry(etag: "e1", digest: Digests.sha256Hex(body), size: Int64(body.count))
        let engine = BucketSyncEngine(store: store, root: root, merger: ClosureMerger { _, local, _ in local }, manifest: manifest, appVersion: "0.3.5")
        let report = try await engine.syncOnce()
        XCTAssertEqual(report.trashed, ["items/a/item.json"])
        let trashed = await store.body("trash/items/a/item.json")
        let live = await store.body("items/a/item.json")
        XCTAssertEqual(trashed, body)
        XCTAssertNil(live)
        let libraryBytes = await store.body("library.json")?.count ?? -1
        let saved = await engine.currentManifest()
        XCTAssertEqual(saved.usageBytes, Int64(libraryBytes))
    }

    func testOnlyAdminsEmptyTrash() async throws {
        let store = MemoryObjectStore()
        await store.seed("trash/items/a/item.json", body: Data("gone".utf8))
        do {
            _ = try await BucketTrash.empty(store: store, role: .member)
            XCTFail("member emptied trash")
        } catch SyncFailure.notAllowed {}
        let kept = await store.keys()
        XCTAssertEqual(kept, ["trash/items/a/item.json"])
        let removed = try await BucketTrash.empty(store: store, role: .admin)
        XCTAssertEqual(removed, ["trash/items/a/item.json"])
        let left = await store.keys()
        XCTAssertTrue(left.isEmpty)
    }

    func testOlderAppRefusesToSync() async throws {
        let root = try TestLibrary.makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let (owner, signed) = try TestLibrary.owner()
        try TestLibrary.writeLibrary(signed, root: root)
        var raised = TeamDocument.parse(signed.canonical)!
        raised.generation = 2
        raised.minAppVersion = "9.0.0"
        let remote = try TeamFile.write(try TeamDocument.sign(raised, key: owner), into: Data(#"{"name":"Studio"}"#.utf8))
        let store = MemoryObjectStore()
        await store.seed("library.json", body: remote)
        await store.seed("items/a/original.jpg", body: Data("secret-bytes".utf8))
        let engine = BucketSyncEngine(store: store, root: root, merger: ClosureMerger { _, local, _ in local }, appVersion: "0.3.5")
        let report = try await engine.syncOnce()
        XCTAssertEqual(report.blocked?.title, "Update Grails")
        XCTAssertEqual(report.blocked?.minAppVersion, "9.0.0")
        XCTAssertEqual(report.blocked?.appVersion, "0.3.5")
        let counts = await store.counts()
        XCTAssertEqual(counts.lists, 0)
        XCTAssertEqual(counts.puts, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("items/a/original.jpg").path))
    }

    func testVersionCompare() {
        XCTAssertEqual(AppVersion.compare("0.3.10", "0.3.9"), .orderedDescending)
        XCTAssertEqual(AppVersion.compare("0.3.5", "0.3.5"), .orderedSame)
        XCTAssertEqual(AppVersion.compare("0.3.4", "0.3.5"), .orderedAscending)
        XCTAssertTrue(AppVersion.allowsSync(app: "0.3.5", minimum: "0.3.5"))
        XCTAssertFalse(AppVersion.allowsSync(app: "0.3.5", minimum: "0.4.0"))
        let notice = UpdateNotice(minAppVersion: "0.4.0", appVersion: "0.3.5")
        XCTAssertEqual(notice.title, "Update Grails")
    }

    func testPollInterval() {
        XCTAssertEqual(SyncTiming.poll, .seconds(15))
    }

    /// In the background the poll slows down and every wake may be coalesced; in front it is the usual poll.
    func testPollBacksOffInTheBackground() {
        XCTAssertEqual(SyncTiming.pause(appActive: true), SyncTiming.poll)
        XCTAssertEqual(SyncTiming.pause(appActive: false), SyncTiming.backgroundPoll)
        XCTAssertGreaterThanOrEqual(SyncTiming.backgroundPoll, SyncTiming.poll * 4)
        XCTAssertGreaterThan(SyncTiming.tolerance, .zero)
        XCTAssertLessThan(SyncTiming.tolerance, SyncTiming.poll)
    }

    func testScanThroughASymlinkedRootKeepsLibraryKeys() throws {
        let real = FileManager.default.temporaryDirectory.appendingPathComponent("grails-real-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: real, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: real) }
        let link = FileManager.default.temporaryDirectory.appendingPathComponent("grails-link-\(UUID().uuidString)")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)
        defer { try? FileManager.default.removeItem(at: link) }
        try Data("{}".utf8).write(to: real.appendingPathComponent("library.json"))
        let item = real.appendingPathComponent("items/a/item.json")
        try FileManager.default.createDirectory(at: item.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: item)
        let scanned = try LibraryScanner.scan(root: link)
        XCTAssertEqual(scanned.map(\.key), ["items/a/item.json", "library.json"])
        XCTAssertEqual(LibraryScanner.relativeKey(of: real.appendingPathComponent("library.json"), root: link), "library.json")
        XCTAssertEqual(LibraryScanner.relativeKey(of: item, root: link), "items/a/item.json")
    }

    func testAShortSyncStaysQuietAndABulkSyncNamesTheBar() {
        XCTAssertEqual(SyncFeedback.arrival(count: 0), .silent)
        XCTAssertEqual(SyncFeedback.arrival(count: 1), .subtle("1 item"))
        XCTAssertEqual(SyncFeedback.arrival(count: 3), .subtle("3 items"))
        XCTAssertEqual(SyncFeedback.arrival(count: 4), .summary("Synced 4 items"))
        XCTAssertFalse(SyncFeedback.showsProgress(total: 3))
        XCTAssertTrue(SyncFeedback.showsProgress(total: 4))
        XCTAssertEqual(SyncFeedback.progressLine(done: 2, total: 8), "Syncing 2 of 8 items")
        XCTAssertEqual(SyncItems.ids(in: ["items/a/item.json", "items/a/original.jpg", "library.json", "items/b/item.json"]), ["a", "b"])
    }

    func testBulkDownloadReportsEachItemOnce() async throws {
        let root = try TestLibrary.makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let (_, signed) = try TestLibrary.owner()
        try TestLibrary.writeLibrary(signed, root: root)
        let store = MemoryObjectStore()
        let library = try Data(contentsOf: root.appendingPathComponent("library.json"))
        await store.seed("library.json", body: library)
        for name in ["a", "b", "c", "d"] {
            await store.seed("items/\(name)/item.json", body: Data(name.utf8))
            await store.seed("items/\(name)/original.jpg", body: Data("img".utf8))
        }
        let engine = BucketSyncEngine(store: store, root: root, merger: ClosureMerger { _, local, _ in local }, appVersion: "0.3.5")
        let steps = ProgressBox()
        let report = try await engine.syncOnce(onProgress: { done, total in steps.add(done, total) })
        XCTAssertEqual(SyncItems.ids(in: report.downloaded).count, 4)
        let recorded = steps.values
        XCTAssertEqual(recorded.first?.1, 4)
        XCTAssertEqual(recorded.last?.0, 4)
        XCTAssertTrue(recorded.contains { $0.0 == 0 && $0.1 == 4 })
    }

    func testPassLogNamesTransfersAndProgressStaysInOrder() async throws {
        let root = try TestLibrary.makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let (_, signed) = try TestLibrary.owner()
        try TestLibrary.writeLibrary(signed, root: root)
        let store = MemoryObjectStore()
        let library = try Data(contentsOf: root.appendingPathComponent("library.json"))
        await store.seed("library.json", body: library)
        for name in ["a", "b", "c", "d"] {
            await store.seed("items/\(name)/item.json", body: Data(name.utf8))
            await store.seed("items/\(name)/original.jpg", body: Data("img".utf8))
        }
        let engine = BucketSyncEngine(store: store, root: root, merger: ClosureMerger { _, local, _ in local }, appVersion: "0.3.5")
        let logs = LogBox()
        await engine.setPassLog { logs.add($0) }
        let steps = ProgressBox()
        let report = try await engine.syncOnce(onProgress: { done, total in
            if done == 0 { try? await Task.sleep(for: .milliseconds(30)) }
            steps.add(done, total)
        })
        XCTAssertEqual(SyncItems.ids(in: report.downloaded).count, 4)
        let dones = steps.values.map(\.0)
        XCTAssertEqual(dones, dones.sorted())
        XCTAssertEqual(dones.first, 0)
        XCTAssertEqual(dones.last, 4)
        XCTAssertEqual(logs.values.first, SyncPassLog.started(downloads: 8, uploads: 0))
        XCTAssertTrue(logs.values.contains(SyncPassLog.progress(done: 0, total: 4)))
        XCTAssertTrue(logs.values.contains(SyncPassLog.progress(done: 4, total: 4)))
    }

    func testWeakOrQuotedETagIsNotAChange() {
        let hash = "abc123abc123abc123abc123abc123ab"
        let local = [LocalObject(key: "items/a/item.json", bytes: 4, digest: "same")]
        let manifest = ["items/a/item.json": ManifestEntry(etag: "W/\"\(hash)", digest: "same", size: 4)]
        let forms = [hash, "\"\(hash)\"", "W/\"\(hash)\"", "&quot;\(hash)&quot;", "W/&quot;\(hash)&quot;", "W/\"\(hash)"]
        for etag in forms {
            let plan = SyncPlanner.plan(
                local: local,
                remote: [ObjectHead(key: "items/a/item.json", etag: etag, size: 4)],
                manifest: manifest,
                capBytes: 1_000,
                maxFileBytes: 200,
                rateRemaining: 500
            )
            XCTAssertTrue(plan.downloads.isEmpty, etag)
            XCTAssertTrue(plan.uploads.isEmpty, etag)
            XCTAssertTrue(plan.conflicts.isEmpty, etag)
        }
        XCTAssertEqual(ETags.canonical("W/\"\(hash)"), hash)
        XCTAssertEqual(ETags.canonical("&quot;\(hash)&quot;"), hash)
    }

    func testTransfersAreInFlightOnlyWhileBytesMove() async throws {
        let root = try TestLibrary.makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let (_, signed) = try TestLibrary.owner()
        try TestLibrary.writeLibrary(signed, root: root)
        let store = MemoryObjectStore()
        let library = try Data(contentsOf: root.appendingPathComponent("library.json"))
        await store.seed("library.json", body: library)
        await store.seed("items/a/item.json", body: Data("a".utf8))
        let engine = BucketSyncEngine(store: store, root: root, merger: ClosureMerger { _, local, _ in local }, appVersion: "0.3.5")
        let flight = TransferBox()
        let first = try await engine.syncOnce(onTransfers: { flight.add($0) })
        XCTAssertFalse(first.downloaded.isEmpty)
        XCTAssertEqual(flight.snapshot, [true, false])

        let second = TransferBox()
        let idle = try await engine.syncOnce(onTransfers: { second.add($0) })
        XCTAssertTrue(idle.downloaded.isEmpty)
        XCTAssertTrue(idle.uploaded.isEmpty)
        XCTAssertTrue(idle.conflicts.isEmpty)
        XCTAssertTrue(second.snapshot.isEmpty, "a poll that moves nothing never enters Syncing")
    }

    func testSecondSyncWithNoRemoteChangesTransfersNothingAndShowsNoBar() async throws {
        let root = try TestLibrary.makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let (_, signed) = try TestLibrary.owner()
        try TestLibrary.writeLibrary(signed, root: root)
        let store = MemoryObjectStore()
        let library = try Data(contentsOf: root.appendingPathComponent("library.json"))
        await store.seed("library.json", body: library)
        for name in ["a", "b", "c", "d"] {
            await store.seed("items/\(name)/item.json", body: Data(name.utf8))
            await store.seed("items/\(name)/original.jpg", body: Data("img".utf8))
        }
        let cursor = root.deletingLastPathComponent().appendingPathComponent("cursor-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: cursor) }
        let engine = BucketSyncEngine(store: store, root: root, merger: ClosureMerger { _, local, _ in local }, appVersion: "0.3.5", cursorURL: cursor)
        let firstSteps = ProgressBox()
        let first = try await engine.syncOnce(onProgress: { done, total in firstSteps.add(done, total) })
        XCTAssertEqual(SyncItems.ids(in: first.downloaded).count, 4)
        XCTAssertFalse(firstSteps.values.isEmpty)

        // The on-disk manifest from the previous build: weak tags with the inner quote left in place.
        var stale = await engine.currentManifest()
        for (key, entry) in stale.entries {
            stale.entries[key] = ManifestEntry(etag: "W/\"\(entry.etag)", digest: entry.digest, size: entry.size)
        }
        let relaunch = BucketSyncEngine(store: store, root: root, merger: ClosureMerger { _, local, _ in local }, manifest: stale, appVersion: "0.3.5", cursorURL: cursor)
        let secondSteps = ProgressBox()
        let second = try await relaunch.syncOnce(onProgress: { done, total in secondSteps.add(done, total) })
        XCTAssertTrue(second.downloaded.isEmpty)
        XCTAssertTrue(second.uploaded.isEmpty)
        XCTAssertTrue(second.conflicts.isEmpty)
        XCTAssertTrue(secondSteps.values.isEmpty, "a sync that transfers nothing does not show the bar")

        let saved = SyncCursor.read(cursor)
        let stored = saved?.entries["items/a/item.json"]?.etag ?? ""
        XCTAssertFalse(stored.isEmpty)
        XCTAssertFalse(stored.contains("W/"))
        XCTAssertFalse(stored.contains("\""))
        let loaded = SyncCursor.load(cursor: cursor, libraryCopy: root.appendingPathComponent("missing.json"))
        XCTAssertEqual(loaded.entries["items/a/item.json"]?.etag, stored)
    }

    private func nested(_ root: URL, _ key: String) throws -> URL {
        let url = root.appendingPathComponent(key)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        return url
    }
}

private final class TransferBox: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [Bool] = []
    func add(_ busy: Bool) {
        lock.lock()
        values.append(busy)
        lock.unlock()
    }
    var snapshot: [Bool] {
        lock.lock()
        defer { lock.unlock() }
        return values
    }
}

private final class LogBox: @unchecked Sendable {
    private let lock = NSLock()
    private var lines: [String] = []
    func add(_ line: String) {
        lock.lock()
        lines.append(line)
        lock.unlock()
    }
    var values: [String] {
        lock.lock()
        defer { lock.unlock() }
        return lines
    }
}

private final class ProgressBox: @unchecked Sendable {
    private let lock = NSLock()
    private var steps: [(Int, Int)] = []
    func add(_ done: Int, _ total: Int) {
        lock.lock()
        steps.append((done, total))
        lock.unlock()
    }
    var values: [(Int, Int)] {
        lock.lock()
        defer { lock.unlock() }
        return steps
    }
}
