import Foundation
import XCTest
import GrailsSync

final class BackupTests: XCTestCase {
    func testSnapshotsAddVersionsAndNeverDelete() async throws {
        let destination = MemorySnapshots()
        let first = Data("v1".utf8)
        let live = [ObjectHead(key: "items/a/item.json", etag: Digests.sha256Hex(first), size: 2)]
        let added = try await LibrarySnapshot.run(live: live, read: { _ in first }, destination: destination, existing: [], day: "2026-10-11")
        XCTAssertEqual(added.added, ["snapshots/2026-10-11/items/a/item.json"])
        let existing = try await destination.list(prefix: "snapshots/")
        let again = try await LibrarySnapshot.run(live: live, read: { _ in first }, destination: destination, existing: existing, day: "2026-10-12")
        XCTAssertTrue(again.added.isEmpty)
        XCTAssertEqual(again.skipped, ["items/a/item.json"])
        let changed = Data("v2".utf8)
        let next = [ObjectHead(key: "items/a/item.json", etag: Digests.sha256Hex(changed), size: 2)]
        let third = try await LibrarySnapshot.run(live: next, read: { _ in changed }, destination: destination, existing: existing, day: "2026-10-12")
        XCTAssertEqual(third.added, ["snapshots/2026-10-12/items/a/item.json"])
        let keys = await destination.keys()
        XCTAssertEqual(keys, [
            "snapshots/2026-10-11/items/a/item.json",
            "snapshots/2026-10-12/items/a/item.json",
        ])
        let kept = await destination.body("snapshots/2026-10-11/items/a/item.json")
        XCTAssertEqual(kept, first)
        XCTAssertFalse(TeamPermissions.canConfigureBackup(.admin))
        XCTAssertTrue(TeamPermissions.canConfigureBackup(.owner))
    }

    /// A later snapshot must keep a second key whose bytes match something already stored.
    func testIdenticalBytesUnderTwoKeysBothRestore() async throws {
        let destination = MemorySnapshots()
        let body = Data("same-photo".utf8)
        let etag = Digests.sha256Hex(body)
        let first = [ObjectHead(key: ".members/a.avatar.jpg", etag: etag, size: Int64(body.count))]
        _ = try await LibrarySnapshot.run(live: first, read: { _ in body }, destination: destination, existing: [], day: "2026-10-15")
        let existing = try await destination.list(prefix: "snapshots/")
        let both = first + [ObjectHead(key: ".members/b.avatar.jpg", etag: etag, size: Int64(body.count))]
        let report = try await LibrarySnapshot.run(live: both, read: { _ in body }, destination: destination, existing: existing, day: "2026-10-16")
        XCTAssertEqual(report.skipped, [".members/a.avatar.jpg"])
        XCTAssertEqual(report.added, ["snapshots/2026-10-16/.members/b.avatar.jpg"])
        let heads = try await destination.list(prefix: "snapshots/")
        let written = RestoreBox()
        let restored = try await LibrarySnapshot.restoreDay("2026-10-16", snapshot: heads, read: { key in
            let stored = await destination.body(key)
            return try XCTUnwrap(stored)
        }, write: { key, data in
            await written.set(key, data)
        })
        XCTAssertEqual(restored, [".members/a.avatar.jpg", ".members/b.avatar.jpg"])
        let left = await written.get(".members/a.avatar.jpg")
        let right = await written.get(".members/b.avatar.jpg")
        XCTAssertEqual(left, body)
        XCTAssertEqual(right, body)
    }

    func testARevertedFileIsSnapshottedAgain() async throws {
        let destination = MemorySnapshots()
        let v1 = Data("v1".utf8)
        let v2 = Data("v2".utf8)
        let e1 = Digests.sha256Hex(v1)
        let e2 = Digests.sha256Hex(v2)
        _ = try await LibrarySnapshot.run(live: [ObjectHead(key: "items/a/item.json", etag: e1, size: 2)], read: { _ in v1 }, destination: destination, existing: [], day: "2026-10-14")
        var existing = try await destination.list(prefix: "snapshots/")
        _ = try await LibrarySnapshot.run(live: [ObjectHead(key: "items/a/item.json", etag: e2, size: 2)], read: { _ in v2 }, destination: destination, existing: existing, day: "2026-10-15")
        existing = try await destination.list(prefix: "snapshots/")
        let report = try await LibrarySnapshot.run(live: [ObjectHead(key: "items/a/item.json", etag: e1, size: 2)], read: { _ in v1 }, destination: destination, existing: existing, day: "2026-10-16")
        XCTAssertEqual(report.added, ["snapshots/2026-10-16/items/a/item.json"])
        let heads = try await destination.list(prefix: "snapshots/")
        let written = RestoreBox()
        _ = try await LibrarySnapshot.restoreDay("2026-10-16", snapshot: heads, read: { key in
            let stored = await destination.body(key)
            return try XCTUnwrap(stored)
        }, write: { key, data in
            await written.set(key, data)
        })
        let body = await written.get("items/a/item.json")
        XCTAssertEqual(body, v1)
    }

    func testTrashAndInvitesAreNotSnapshotted() async throws {
        let destination = MemorySnapshots()
        let live = [
            ObjectHead(key: "trash/items/a/item.json", etag: "t", size: 1),
            ObjectHead(key: "invites/inv1.json", etag: "i", size: 1),
            ObjectHead(key: MoveNotice.key, etag: "m", size: 1),
            ObjectHead(key: "library.json", etag: "l", size: 1),
        ]
        let report = try await LibrarySnapshot.run(live: live, read: { _ in Data("x".utf8) }, destination: destination, existing: [], day: "2026-10-12")
        XCTAssertEqual(report.added, ["snapshots/2026-10-12/library.json"])
    }

    func testRestoreByItemAndByDate() async throws {
        let day1 = "snapshots/2026-10-11/items/a/item.json"
        let day2 = "snapshots/2026-10-12/items/a/item.json"
        let heads = [
            ObjectHead(key: day1, etag: "1", size: 2),
            ObjectHead(key: day2, etag: "2", size: 2),
            ObjectHead(key: "snapshots/2026-10-12/library.json", etag: "l", size: 1),
        ]
        let bodies = [day1: Data("old".utf8), day2: Data("new".utf8), "snapshots/2026-10-12/library.json": Data("lib".utf8)]
        let written = RestoreBox()
        try await LibrarySnapshot.restoreItem(key: "items/a/item.json", day: nil, snapshot: heads, read: { bodies[$0]! }, write: { key, data in
            await written.set(key, data)
        })
        let latest = await written.get("items/a/item.json")
        XCTAssertEqual(latest, Data("new".utf8))
        try await LibrarySnapshot.restoreItem(key: "items/a/item.json", day: "2026-10-11", snapshot: heads, read: { bodies[$0]! }, write: { key, data in
            await written.set(key, data)
        })
        let older = await written.get("items/a/item.json")
        XCTAssertEqual(older, Data("old".utf8))
        await written.reset()
        let restored = try await LibrarySnapshot.restoreDay("2026-10-12", snapshot: heads, read: { bodies[$0]! }, write: { key, data in
            await written.set(key, data)
        })
        XCTAssertEqual(restored, ["items/a/item.json", "library.json"])
        let library = await written.get("library.json")
        XCTAssertEqual(library, Data("lib".utf8))
    }

    func testNightlyWindowOpensAtThreeUTC() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let two = calendar.date(from: DateComponents(year: 2026, month: 10, day: 12, hour: 2))!
        let three = calendar.date(from: DateComponents(year: 2026, month: 10, day: 12, hour: 3))!
        XCTAssertEqual(SnapshotSchedule.windowDay(two), "2026-10-11")
        XCTAssertEqual(SnapshotSchedule.windowDay(three), "2026-10-12")
        XCTAssertFalse(SnapshotSchedule.isDue(lastRunDay: "2026-10-11", now: two))
        XCTAssertTrue(SnapshotSchedule.isDue(lastRunDay: "2026-10-11", now: three))
        XCTAssertFalse(SnapshotSchedule.isDue(lastRunDay: "2026-10-12", now: three))
    }

    func testSpringCleaningListsLargestFilesAndTrash() {
        let plan = SpringCleaning.plan(objects: [
            ObjectHead(key: "items/a/thumb.jpg", etag: "t", size: 9_000),
            ObjectHead(key: "items/a/item.json", etag: "j", size: 8_000),
            ObjectHead(key: "items/a/original.jpg", etag: "o", size: 500),
            ObjectHead(key: "items/b/original.jpg", etag: "b", size: 900),
            ObjectHead(key: "trash/items/c/original.jpg", etag: "c", size: 9_999),
            ObjectHead(key: "invites/inv.json", etag: "i", size: 9_999),
        ])
        XCTAssertEqual(plan.largest.map(\.key), ["items/b/original.jpg", "items/a/original.jpg"])
        XCTAssertEqual(plan.trashKeys, ["trash/items/c/original.jpg"])
    }

    func testBackupConfigOmitsTheSecret() throws {
        let config = BackupConfig(endpoint: URL(string: "https://backup.example")!, bucket: "grails-backup", region: "auto")
        let data = try JSONEncoder().encode(config)
        let text = String(decoding: data, as: UTF8.self)
        XCTAssertFalse(text.contains("secret"))
        XCTAssertTrue(text.contains("grails-backup"))
    }
}

private actor RestoreBox {
    private var values: [String: Data] = [:]

    func set(_ key: String, _ data: Data) { values[key] = data }

    func get(_ key: String) -> Data? { values[key] }

    func reset() { values.removeAll() }
}
