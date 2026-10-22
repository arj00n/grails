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
        XCTAssertEqual(first.uploaded, ["library.json", "items/a/thumb.jpg"])
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
        XCTAssertEqual(SyncFeedback.progressLine(done: 2, total: 8), "2 of 8 items")
        XCTAssertEqual(SyncFeedback.progressLine(done: 3, total: 176, estimate: "about 4 min"), "3 of 176 items · about 4 min left")
        XCTAssertEqual(SyncFeedback.progressLine(done: 3, total: 176, estimate: "less than a minute"), "3 of 176 items · less than a minute left")
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
        let report = try await engine.syncOnce(onProgress: { steps.add($0) })
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
        let report = try await engine.syncOnce(onProgress: { progress in
            if progress.done == 0, progress.bytesDone == 0 { try? await Task.sleep(for: .milliseconds(30)) }
            steps.add(progress)
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
        let first = try await engine.syncOnce(onProgress: { firstSteps.add($0) })
        XCTAssertEqual(SyncItems.ids(in: first.downloaded).count, 4)
        XCTAssertFalse(firstSteps.values.isEmpty)

        // The on-disk manifest from the previous build: weak tags with the inner quote left in place.
        var stale = await engine.currentManifest()
        for (key, entry) in stale.entries {
            stale.entries[key] = ManifestEntry(etag: "W/\"\(entry.etag)", digest: entry.digest, size: entry.size)
        }
        let relaunch = BucketSyncEngine(store: store, root: root, merger: ClosureMerger { _, local, _ in local }, manifest: stale, appVersion: "0.3.5", cursorURL: cursor)
        let secondSteps = ProgressBox()
        let second = try await relaunch.syncOnce(onProgress: { secondSteps.add($0) })
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

    func testADownloadDoesNotReplaceANewerLocalEdit() async throws {
        let root = try TestLibrary.makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let (_, signed) = try TestLibrary.owner()
        try TestLibrary.writeLibrary(signed, root: root)
        let key = "items/a/thumb.jpg"
        let url = try nested(root, key)
        let baseline = Data("baseline".utf8)
        let remoteBody = Data("remote-bytes".utf8)
        let edited = Data("local-edit".utf8)
        try baseline.write(to: url)
        let store = MemoryObjectStore()
        await store.seed(key, body: remoteBody, etag: "remote-etag")
        var manifest = SyncManifest()
        manifest.entries[key] = ManifestEntry(etag: "old-etag", digest: Digests.sha256Hex(baseline), size: Int64(baseline.count))
        let wrapped = EditOnGet(inner: store, url: url, key: key, edited: edited)
        let engine = BucketSyncEngine(store: wrapped, root: root, merger: ClosureMerger { _, local, _ in local }, manifest: manifest, appVersion: "0.3.5")
        _ = try await engine.syncOnce()
        let onDisk = try Data(contentsOf: url)
        let inBucket = await store.body(key)
        XCTAssertEqual(onDisk, edited)
        XCTAssertEqual(inBucket, edited)
    }

    func testUploadKeepsNewerBucketBytesAndSendsANewerLocalFile() async throws {
        let root = try TestLibrary.makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let older = Date(timeIntervalSince1970: 1_700_000_000)
        let newer = Date(timeIntervalSince1970: 1_700_000_100)
        let remoteNewer = Data("remote-newer".utf8)
        let remoteUnknown = Data("remote-unknown".utf8)
        let remoteOlder = Data("remote-older".utf8)
        let localFresh = Data("local-fresh".utf8)
        let onlyLocal = Data("only-local".utf8)
        try writeUpload(root, "items/a/remote-newer.jpg", Data("local-stale".utf8), modified: older)
        try writeUpload(root, "items/b/remote-unknown.jpg", Data("local-guess".utf8), modified: newer)
        try writeUpload(root, "items/c/local-newer.jpg", localFresh, modified: newer)
        try writeUpload(root, "items/d/only-local.jpg", onlyLocal, modified: newer)
        let store = MemoryObjectStore()
        await store.seed("items/a/remote-newer.jpg", body: remoteNewer, etag: "etag-a", modified: newer)
        await store.seed("items/b/remote-unknown.jpg", body: remoteUnknown, etag: "etag-b", modified: nil)
        await store.seed("items/c/local-newer.jpg", body: remoteOlder, etag: "etag-c", modified: older)
        let sent = try await LibraryUploader.upload(root: root, store: store)
        let keptNewer = await store.body("items/a/remote-newer.jpg")
        let keptUnknown = await store.body("items/b/remote-unknown.jpg")
        let sentFresh = await store.body("items/c/local-newer.jpg")
        let sentOnly = await store.body("items/d/only-local.jpg")
        XCTAssertEqual(keptNewer, remoteNewer)
        XCTAssertEqual(keptUnknown, remoteUnknown)
        XCTAssertEqual(sentFresh, localFresh)
        XCTAssertEqual(sentOnly, onlyLocal)
        XCTAssertFalse(sent.contains("items/a/remote-newer.jpg"))
        XCTAssertFalse(sent.contains("items/b/remote-unknown.jpg"))
        XCTAssertTrue(sent.contains("items/c/local-newer.jpg"))
        XCTAssertTrue(sent.contains("items/d/only-local.jpg"))
    }

    func testListReadsLastModified() throws {
        let xml = """
        <ListBucketResult>
          <IsTruncated>false</IsTruncated>
          <Contents>
            <Key>items/a/original.jpg</Key>
            <LastModified>2024-06-01T12:30:45.000Z</LastModified>
            <ETag>&quot;abc&quot;</ETag>
            <Size>11</Size>
          </Contents>
          <Contents>
            <Key>items/b/original.jpg</Key>
            <LastModified>2024-06-02T08:00:00Z</LastModified>
            <ETag>"def"</ETag>
            <Size>2</Size>
          </Contents>
        </ListBucketResult>
        """
        let page = try ListBucketXML.parse(Data(xml.utf8))
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        XCTAssertEqual(page.objects.map(\.key), ["items/a/original.jpg", "items/b/original.jpg"])
        XCTAssertEqual(page.objects[0].modified, fractional.date(from: "2024-06-01T12:30:45.000Z"))
        XCTAssertEqual(page.objects[1].modified, plain.date(from: "2024-06-02T08:00:00Z"))
    }

    func testItemsSortTogetherWithTheThumbFirst() {
        let keys = [
            "items/b/thumb.jpg",
            "items/a/original.jpg",
            "items/a/thumb.jpg",
            "items/b/original.jpg",
            "items/a/item.json",
            ".members/ada@example.com.json",
            "library.json",
        ]
        XCTAssertEqual(SyncRank.sort(keys), [
            ".members/ada@example.com.json",
            "library.json",
            "items/a/thumb.jpg",
            "items/a/item.json",
            "items/a/original.jpg",
            "items/b/thumb.jpg",
            "items/b/original.jpg",
        ])
        let scheduled = SyncDownload.schedule(SyncRank.sort(keys))
        XCTAssertEqual(scheduled.serial, [".members/ada@example.com.json", "library.json"])
        XCTAssertEqual(scheduled.parallel.first, "items/a/thumb.jpg")
        XCTAssertTrue((4...8).contains(SyncDownload.width))
    }

    func testDownloadsOverlapWithoutTheRosterAndTheCountMovesBeforeTheEnd() async throws {
        let root = try TestLibrary.makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let (_, signed) = try TestLibrary.owner()
        try TestLibrary.writeLibrary(signed, root: root)
        let inner = MemoryObjectStore()
        let library = try Data(contentsOf: root.appendingPathComponent("library.json"))
        await inner.seed("library.json", body: library)
        let member = ".members/ada@example.com.json"
        await inner.seed(member, body: Data("{\"email\":\"ada@example.com\"}".utf8))
        var itemKeys: [String] = []
        for name in ["a", "b", "c", "d"] {
            for file in ["thumb.jpg", "item.json", "original.jpg"] {
                let key = "items/\(name)/\(file)"
                itemKeys.append(key)
                await inner.seed(key, body: Data("\(name)-\(file)".utf8))
            }
        }
        let crowd = CrowdStore(inner: inner)
        let engine = BucketSyncEngine(store: crowd, root: root, merger: ClosureMerger { _, local, _ in local }, appVersion: "0.3.5")
        let steps = ProgressBox()
        let report = try await engine.syncOnce(onProgress: { steps.add($0) })
        XCTAssertEqual(SyncItems.ids(in: report.downloaded).count, 4)
        XCTAssertTrue(report.downloaded.contains(member))
        let snap = await crowd.snapshot()
        XCTAssertTrue(snap.violations.isEmpty, snap.violations.joined(separator: ","))
        XCTAssertEqual(snap.maxParallel, SyncDownload.width)
        let itemStarts = snap.started.filter { itemKeys.contains($0) }
        let expected = SyncRank.sort(itemKeys)
        XCTAssertEqual(Set(itemStarts.prefix(SyncDownload.width)), Set(expected.prefix(SyncDownload.width)))
        let memberIndex = snap.started.firstIndex(of: member)
        let firstItem = snap.started.firstIndex(where: { itemKeys.contains($0) })
        XCTAssertNotNil(memberIndex)
        XCTAssertNotNil(firstItem)
        XCTAssertLessThan(memberIndex ?? 0, firstItem ?? 0)
        let total = steps.full.first?.total ?? 0
        XCTAssertGreaterThan(total, 1)
        XCTAssertTrue(steps.full.contains { $0.done > 0 && $0.done < total && $0.bytesDone < $0.bytesTotal })
    }

    func testManifestFlushesInBatchesAndOnFailure() async throws {
        XCTAssertFalse(SyncManifestFlush.shouldFlush(pending: 19, elapsed: 1.9, force: false))
        XCTAssertTrue(SyncManifestFlush.shouldFlush(pending: 20, elapsed: 0, force: false))
        XCTAssertTrue(SyncManifestFlush.shouldFlush(pending: 1, elapsed: 2, force: false))
        XCTAssertFalse(SyncManifestFlush.shouldFlush(pending: 0, elapsed: 9, force: true))
        XCTAssertTrue(SyncManifestFlush.shouldFlush(pending: 3, elapsed: 0, force: true))

        let root = try TestLibrary.makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let (_, signed) = try TestLibrary.owner()
        try TestLibrary.writeLibrary(signed, root: root)
        let store = MemoryObjectStore()
        let library = try Data(contentsOf: root.appendingPathComponent("library.json"))
        await store.seed("library.json", body: library)
        var keys: [String] = []
        for index in 0..<25 {
            let key = String(format: "items/n%02d/item.json", index)
            keys.append(key)
            await store.seed(key, body: Data("item-\(index)".utf8))
        }
        let engine = BucketSyncEngine(store: store, root: root, merger: ClosureMerger { _, local, _ in local }, appVersion: "0.3.5")
        let logs = LogBox()
        await engine.setPassLog { logs.add($0) }
        _ = try await engine.syncOnce()
        let saves = logs.values.filter { $0 == SyncPassLog.manifestSaved }
        XCTAssertEqual(saves.count, 2)
        let saved = try Self.readManifest(root)
        for key in keys { XCTAssertNotNil(saved.entries[key], key) }

        let failedRoot = try TestLibrary.makeRoot()
        defer { try? FileManager.default.removeItem(at: failedRoot) }
        try TestLibrary.writeLibrary(signed, root: failedRoot)
        let failing = MemoryObjectStore()
        let failedLibrary = try Data(contentsOf: failedRoot.appendingPathComponent("library.json"))
        await failing.seed("library.json", body: failedLibrary)
        let memberKeys = [".members/a.json", ".members/b.json", ".members/c.json"]
        for key in memberKeys {
            await failing.seed(key, body: Data(key.utf8))
        }
        let engine2 = BucketSyncEngine(store: FailGet(inner: failing, key: ".members/c.json"), root: failedRoot, merger: ClosureMerger { _, local, _ in local }, appVersion: "0.3.5")
        do {
            _ = try await engine2.syncOnce()
            XCTFail("the last member file should fail")
        } catch {
            XCTAssertFalse(SyncFailure.isCancellation(error))
        }
        let partial = try Self.readManifest(failedRoot)
        XCTAssertNotNil(partial.entries[".members/a.json"])
        XCTAssertNotNil(partial.entries[".members/b.json"])
        XCTAssertNil(partial.entries[".members/c.json"])
    }

    func testPaceStaysQuietUntilItHasMovedAndDoesNotFlicker() {
        var pace = SyncPace()
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let total: Int64 = 93_000_000
        func sample(_ bytes: Int64, _ seconds: TimeInterval, done: Int = 0) -> String {
            pace.label(SyncTransferProgress(done: done, total: 176, bytesDone: bytes, bytesTotal: total), at: start.addingTimeInterval(seconds))
        }
        XCTAssertEqual(sample(0, 0), SyncFeedback.preparing)
        XCTAssertEqual(sample(1_000, 1), SyncFeedback.preparing)
        XCTAssertEqual(sample(0, 6), SyncFeedback.preparing)
        XCTAssertEqual(sample(SyncPace.warmBytes, 2, done: 1), "1 of 176 items · about 1 min left")

        pace = SyncPace()
        XCTAssertEqual(sample(0, 0), SyncFeedback.preparing)
        XCTAssertEqual(sample(1_000, 5, done: 2), "2 of 176 items · about 7750 min left")

        pace = SyncPace()
        XCTAssertEqual(sample(0, 0), SyncFeedback.preparing)
        let settled = sample(3_000_000, 6, done: 3)
        XCTAssertEqual(settled, "3 of 176 items · about 3 min left")
        let blip = sample(5_150_289, 6, done: 4)
        XCTAssertEqual(blip, "4 of 176 items · about 3 min left")
        XCTAssertEqual(SyncPace.shownMinutes(previous: 3, seconds: 149), 3)
        XCTAssertEqual(SyncPace.shownMinutes(previous: 3, seconds: 120), 2)
        XCTAssertEqual(SyncPace.shownMinutes(previous: 3, seconds: 40), 0)
        XCTAssertEqual(SyncPace.bucket(59), 0)
        XCTAssertEqual(SyncPace.bucket(60), 1)
        XCTAssertEqual(SyncPace.bucket(89), 1)
        XCTAssertEqual(SyncPace.bucket(90), 2)
        XCTAssertFalse(SyncWatch.shouldReload(bulkSync: true))
        XCTAssertTrue(SyncWatch.shouldReload(bulkSync: false))
        XCTAssertFalse(SyncProgressVisibility.shown(total: 8, reachable: false))
        XCTAssertTrue(SyncProgressVisibility.shown(total: 8, reachable: true))
    }

    private static func readManifest(_ root: URL) throws -> SyncManifest {
        let data = try Data(contentsOf: root.appendingPathComponent(".grails-sync.json"))
        return try JSONDecoder().decode(SyncManifest.self, from: data)
    }

    private func writeUpload(_ root: URL, _ key: String, _ data: Data, modified: Date) throws {
        let url = try nested(root, key)
        try data.write(to: url)
        try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: url.path)
    }

    private func nested(_ root: URL, _ key: String) throws -> URL {
        let url = root.appendingPathComponent(key)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        return url
    }
}

/// Writes a newer local copy while the download is in flight, then returns the bucket bytes.
private actor EditOnGet: ObjectStore {
    private let inner: MemoryObjectStore
    private let url: URL
    private let key: String
    private let edited: Data
    private var did = false

    init(inner: MemoryObjectStore, url: URL, key: String, edited: Data) {
        self.inner = inner
        self.url = url
        self.key = key
        self.edited = edited
    }

    func list(prefix: String) async throws -> [ObjectHead] { try await inner.list(prefix: prefix) }

    func get(_ key: String) async throws -> ObjectGet {
        if key == self.key, !did {
            did = true
            try edited.write(to: url)
        }
        return try await inner.get(key)
    }

    func put(_ key: String, body: Data, contentType: String, ifMatch: String?, ifNoneMatch: String?) async throws -> String {
        try await inner.put(key, body: body, contentType: contentType, ifMatch: ifMatch, ifNoneMatch: ifNoneMatch)
    }

    func delete(_ key: String) async throws { try await inner.delete(key) }
}

/// Holds parallel reads until `SyncDownload.width` of them are inside `get`, so the test can see the overlap.
private actor CrowdStore: ObjectStore {
    private let inner: MemoryObjectStore
    private var current = Set<String>()
    private var parallelFlight = 0
    private var maxParallel = 0
    private var release = false
    private var started: [String] = []
    private var violations: [String] = []

    init(inner: MemoryObjectStore) { self.inner = inner }

    struct Snapshot: Sendable {
        var started: [String]
        var maxParallel: Int
        var violations: [String]
    }

    func snapshot() -> Snapshot { Snapshot(started: started, maxParallel: maxParallel, violations: violations) }

    func list(prefix: String) async throws -> [ObjectHead] { try await inner.list(prefix: prefix) }

    func get(_ key: String) async throws -> ObjectGet {
        let serial = SyncDownload.isSerial(key)
        let crowd = key.hasPrefix("items/")
        current.insert(key)
        started.append(key)
        if serial, current.count > 1 { violations.append(key) }
        if crowd, current.contains(where: SyncDownload.isSerial) { violations.append(key) }
        if crowd {
            parallelFlight += 1
            if parallelFlight > maxParallel { maxParallel = parallelFlight }
            if parallelFlight >= SyncDownload.width { release = true }
            let deadline = Date().addingTimeInterval(1)
            while !release, Date() < deadline {
                try await Task.sleep(for: .milliseconds(5))
            }
            try await Task.sleep(for: .milliseconds(15))
            parallelFlight -= 1
        }
        current.remove(key)
        return try await inner.get(key)
    }

    func put(_ key: String, body: Data, contentType: String, ifMatch: String?, ifNoneMatch: String?) async throws -> String {
        try await inner.put(key, body: body, contentType: contentType, ifMatch: ifMatch, ifNoneMatch: ifNoneMatch)
    }

    func delete(_ key: String) async throws { try await inner.delete(key) }
}

private actor FailGet: ObjectStore {
    private let inner: MemoryObjectStore
    private let key: String

    init(inner: MemoryObjectStore, key: String) {
        self.inner = inner
        self.key = key
    }

    func list(prefix: String) async throws -> [ObjectHead] { try await inner.list(prefix: prefix) }

    func get(_ key: String) async throws -> ObjectGet {
        if key == self.key { throw S3Error.status(500, "fail") }
        return try await inner.get(key)
    }

    func put(_ key: String, body: Data, contentType: String, ifMatch: String?, ifNoneMatch: String?) async throws -> String {
        try await inner.put(key, body: body, contentType: contentType, ifMatch: ifMatch, ifNoneMatch: ifNoneMatch)
    }

    func delete(_ key: String) async throws { try await inner.delete(key) }
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
    private var events: [SyncTransferProgress] = []
    func add(_ progress: SyncTransferProgress) {
        lock.lock()
        steps.append((progress.done, progress.total))
        events.append(progress)
        lock.unlock()
    }
    var values: [(Int, Int)] {
        lock.lock()
        defer { lock.unlock() }
        return steps
    }
    var full: [SyncTransferProgress] {
        lock.lock()
        defer { lock.unlock() }
        return events
    }
}
