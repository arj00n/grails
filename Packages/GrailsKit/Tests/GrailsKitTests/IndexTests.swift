import Foundation
import Testing
@testable import GrailsKit

@Suite struct IndexTests {
    @Test func rebuildFromDiskReproducesIdenticalResults() async throws {
        let (store, root) = try TestSupport.newStore()
        let dir = TestSupport.tempDir()
        let coll = try await store.createCollection(name: "Refs")
        for i in 0..<12 {
            let item = try await store.addItem(
                fileAt: TestSupport.makePNG(in: dir, name: "i\(i)", rgb: (Double(i) / 12, 0.2, 0.7)),
                name: "Dish \(i)", tags: i % 2 == 0 ? ["curry", "warm"] : ["dessert"], collectionIds: i < 5 ? [coll.id] : []
            ).item
            if i == 3 { _ = try await store.updateItem(id: item.id) { $0.liked = true; $0.note = "hero shot" } }
        }
        try await store.softDelete(ids: [try #require(try await store.index.query(ItemQuery(text: "Dish 11")).first).id])

        func snapshot(_ index: LibraryIndex) async throws -> [String] {
            var results: [String] = []
            for text in ["curry", "dessert", "hero", "dis", "warm curry", "zzz"] {
                results.append("\(text): " + (try await index.query(ItemQuery(text: text)).map(\.id).joined(separator: ",")))
            }
            var liked = ItemQuery(); liked.likedOnly = true
            results.append("liked: " + (try await index.query(liked).map(\.id).joined(separator: ",")))
            var c = ItemQuery(); c.collectionId = coll.id
            results.append("coll: " + (try await index.query(c).map(\.id).joined(separator: ",")))
            var trash = ItemQuery(); trash.deleted = true
            results.append("trash: " + (try await index.query(trash).map(\.id).joined(separator: ",")))
            results.append("tags: " + (try await index.tagCounts().map { "\($0.tag)=\($0.count)" }.joined(separator: ",")))
            return results
        }

        let before = try await snapshot(store.index)
        let fresh = try LibraryIndex(path: nil)
        let failures = try await fresh.rebuild(from: LibraryLayout(root: root))
        #expect(failures.isEmpty)
        #expect(try await snapshot(fresh) == before)
        #expect(try await fresh.collections().map(\.name) == ["Refs"])
    }

    @Test func discardsCorruptIndexFileAndFlagsReset() throws {
        let dir = TestSupport.tempDir()
        let path = dir.appendingPathComponent("bad.sqlite")
        try Data("this is not sqlite".utf8).write(to: path)
        let index = try LibraryIndex(path: path)
        #expect(index.wasReset)
    }

    @Test func rescanPicksUpExternalEditsAdditionsAndRemovals() async throws {
        let (store, root) = try TestSupport.newStore()
        let dir = TestSupport.tempDir()
        let a = try await store.addItem(fileAt: TestSupport.makePNG(in: dir, name: "a", rgb: (1, 0, 0))).item
        let b = try await store.addItem(fileAt: TestSupport.makePNG(in: dir, name: "b", rgb: (0, 1, 0))).item

        // Another Mac edits `a`, deletes `b`, and adds `c` through the synced folder.
        var edited = a
        edited.tags = ["from-ben"]
        edited.updatedAt = .grailsNow
        try await Task.sleep(for: .milliseconds(20))
        try AtomicFile.writeJSON(edited, to: root.appendingPathComponent("items/\(a.id)/item.json"))
        try FileManager.default.removeItem(at: root.appendingPathComponent("items/\(b.id)"))
        let c = Item(kind: .image, name: "c", addedBy: "ben")
        try AtomicFile.writeJSON(c, to: root.appendingPathComponent("items/\(c.id)/item.json"))

        let result = try await store.rescan()
        #expect(result.added == 1 && result.updated == 1 && result.removed == 1)
        #expect(try await store.index.query(ItemQuery(text: "from-ben")).map(\.id) == [a.id])
        #expect(try await store.index.count(ItemQuery()) == 2)
        #expect(try await store.rescan() == RescanResult())
    }

    @Test func corruptItemFileIsReportedNotFatal() async throws {
        let (store, root) = try TestSupport.newStore()
        let good = Item(kind: .image, name: "good", addedBy: "x")
        try AtomicFile.writeJSON(good, to: root.appendingPathComponent("items/\(good.id)/item.json"))
        let badId = ULID().string
        try FileManager.default.createDirectory(at: root.appendingPathComponent("items/\(badId)"), withIntermediateDirectories: true)
        try Data("{ half written".utf8).write(to: root.appendingPathComponent("items/\(badId)/item.json"))
        let result = try await store.rescan()
        #expect(result.added == 1)
        #expect(result.failures.count == 1)
    }

    @Test func conflictCopiesMergeToUnionOfTagsAndCollections() async throws {
        let (store, root) = try TestSupport.newStore()
        let base = Item(kind: .image, name: "shared", tags: ["base"], collections: ["C1": "a"], addedBy: "ana")
        let folder = root.appendingPathComponent("items/\(base.id)")
        try AtomicFile.writeJSON(base, to: folder.appendingPathComponent("item.json"))

        var ben = base; ben.tags = ["base", "ben-tag"]; ben.collections["C2"] = "b"; ben.updatedAt = base.updatedAt.addingTimeInterval(10); ben.updatedBy = "ben"; ben.liked = true
        var cara = base; cara.tags = ["base", "cara-tag", "BEN-TAG"]; cara.updatedAt = base.updatedAt.addingTimeInterval(5); cara.updatedBy = "cara"; cara.note = "from cara"
        try AtomicFile.writeJSON(ben, to: folder.appendingPathComponent("item (1).json"))
        try AtomicFile.writeJSON(cara, to: folder.appendingPathComponent("item (Cara's conflicted copy 2026-10-03).json"))

        let result = try await store.rescan()
        #expect(result.conflictsMerged == 2)
        let merged = try #require(try await store.item(id: base.id))
        #expect(Set(merged.tags.map { $0.lowercased() }) == ["base", "ben-tag", "cara-tag"])
        #expect(merged.tags.count == 3)
        #expect(merged.collections.keys.sorted() == ["C1", "C2"])
        #expect(merged.liked && merged.updatedBy == "ben" && merged.note == "from cara")
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path) == ["item.json"])
        #expect(try await store.index.query(ItemQuery(text: "cara")).map(\.id) == [base.id])
    }

    @Test func collectionConflictCopyNewestWins() async throws {
        let (store, root) = try TestSupport.newStore()
        let c = try await store.createCollection(name: "Old name")
        var renamed = c; renamed.name = "New name"; renamed.updatedAt = c.updatedAt.addingTimeInterval(30)
        try AtomicFile.writeJSON(renamed, to: root.appendingPathComponent("collections/\(c.id) (1).json"))
        let result = try await store.rescan()
        #expect(result.conflictsMerged == 1)
        #expect(try await store.index.collections().map(\.name) == ["New name"])
    }

    @Test func dailySnapshotIsWrittenOnceAndPruned() async throws {
        let (store, root) = try TestSupport.newStore()
        _ = try await store.addItem(fileAt: TestSupport.makePNG(in: TestSupport.tempDir(), name: "s"))
        let day = Date(timeIntervalSince1970: 1_790_000_000)
        let first = try await store.snapshotIfNeeded(now: day)
        #expect(first != nil)
        #expect(try await store.snapshotIfNeeded(now: day) == nil)
        for i in 1...16 { _ = try await store.snapshotIfNeeded(now: day.addingTimeInterval(Double(i) * 86400)) }
        let names = try FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent(".snapshots").path)
        #expect(names.count == 14)
        let raw = try Data(contentsOf: root.appendingPathComponent(".snapshots/\(names.sorted().last!)"))
        let json = try (raw as NSData).decompressed(using: .lzfse) as Data
        let obj = try JSONDecoder().decode(JSONValue.self, from: json)
        guard case .object(let o) = obj, case .object(let files)? = o["files"] else { Issue.record("bad snapshot"); return }
        #expect(files.keys.contains("library.json") && files.keys.contains { $0.hasSuffix("item.json") })
    }

    @Test func openingALibraryIndexesExistingFiles() async throws {
        let (store, root) = try TestSupport.newStore()
        _ = try await store.addItem(fileAt: TestSupport.makePNG(in: TestSupport.tempDir(), name: "x"), tags: ["one"])
        let reopened = try await LibraryStore.open(at: root, index: try LibraryIndex(path: nil))
        #expect(try await reopened.index.count(ItemQuery()) == 1)
        await #expect(throws: GrailsError.self) { _ = try await LibraryStore.open(at: TestSupport.tempDir(), index: try LibraryIndex(path: nil)) }
    }
}
