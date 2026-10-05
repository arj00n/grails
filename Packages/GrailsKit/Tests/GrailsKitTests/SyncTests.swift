import Foundation
import Testing
@testable import GrailsKit

final class PathBox: @unchecked Sendable {
    private let lock = NSLock()
    private var all: [String] = []
    func add(_ p: [String]) { lock.lock(); all += p; lock.unlock() }
    var paths: [String] { lock.lock(); defer { lock.unlock() }; return all }
}

@Suite(.serialized) struct WatcherTests {
    @Test func reportsFilesWrittenUnderTheLibrary() async throws {
        let root = TestSupport.tempDir("watch").resolvingSymlinksInPath()
        let box = PathBox()
        let watcher = LibraryWatcher(root: root, latency: 0.1) { box.add($0) }
        watcher.start()
        try await Task.sleep(for: .milliseconds(400))
        let folder = root.appendingPathComponent("items/ABC")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try AtomicFile.write(Data("{}".utf8), to: folder.appendingPathComponent("item.json"))
        var seen = false
        for _ in 0..<40 where !seen {
            try await Task.sleep(for: .milliseconds(100))
            seen = box.paths.contains { $0.hasSuffix("items/ABC/item.json") }
        }
        watcher.stop()
        #expect(seen)
        let countAfterStop = box.paths.count
        try Data("x".utf8).write(to: root.appendingPathComponent("later.txt"))
        try await Task.sleep(for: .milliseconds(500))
        #expect(box.paths.count == countAfterStop)       // stopped means stopped
    }
}

@Suite struct ExternalChangeTests {
    /// Writes what another Mac's sync would drop into our folder.
    func remoteWrite(_ item: Item, in root: URL) throws {
        try AtomicFile.writeJSON(item, to: root.appendingPathComponent("items/\(item.id)/item.json"))
    }

    @Test func picksUpAddsEditsAndRemovalsFromReportedPathsOnly() async throws {
        let (store, root) = try TestSupport.newStore()
        let mine = try await store.addItem(fileAt: TestSupport.makePNG(in: TestSupport.tempDir(), name: "m")).item
        let untouched = try await store.addItem(fileAt: TestSupport.makePNG(in: TestSupport.tempDir(), name: "u", rgb: (0, 1, 0))).item

        // our own write is recognised and costs nothing
        let own = try await store.applyExternalChanges(paths: [root.appendingPathComponent("items/\(mine.id)/item.json").path, root.appendingPathComponent("items/\(mine.id)/thumb.jpg").path])
        #expect(own.isEmpty)

        // a teammate adds an item, edits ours, and deletes the other
        let theirs = TestSupport.item("from ben", tags: ["new"], addedBy: "ben")
        try remoteWrite(theirs, in: root)
        var edited = mine; edited.tags = ["edited"]; edited.updatedAt = .grailsNow
        try await Task.sleep(for: .milliseconds(20))
        try remoteWrite(edited, in: root)
        try FileManager.default.removeItem(at: root.appendingPathComponent("items/\(untouched.id)"))

        let paths = [theirs.id, mine.id, untouched.id].map { root.appendingPathComponent("items/\($0)/item.json").path } + [root.appendingPathComponent("items/\(theirs.id)/.item.json.tmp-1").path]
        let s = try await store.applyExternalChanges(paths: paths)
        #expect(s.added == 1 && s.updated == 1 && s.removed == 1 && !s.collectionsChanged)
        #expect(try await store.index.query(ItemQuery(text: "edited")).map(\.id) == [mine.id])
        #expect(try await store.index.query(ItemQuery(text: "new")).map(\.id) == [theirs.id])
        #expect(try await store.index.count(ItemQuery()) == 2)
        #expect(try await store.applyExternalChanges(paths: paths).isEmpty)          // idempotent
    }

    @Test func mergesConflictCopiesAndReportsCollectionChanges() async throws {
        let (store, root) = try TestSupport.newStore()
        let base = TestSupport.item("shared", tags: ["a"], addedBy: "ana")
        try remoteWrite(base, in: root)
        try await store.applyExternalChanges(paths: [root.appendingPathComponent("items/\(base.id)").path])
        var ben = base; ben.tags = ["a", "b"]; ben.updatedAt = base.updatedAt.addingTimeInterval(5)
        try AtomicFile.writeJSON(ben, to: root.appendingPathComponent("items/\(base.id)/item (1).json"))
        var s = try await store.applyExternalChanges(paths: [root.appendingPathComponent("items/\(base.id)/item (1).json").path])
        #expect(s.conflictsMerged == 1)
        #expect(try await store.item(id: base.id)?.tags == ["a", "b"])

        let c = GrailsCollection(name: "From Ben", updatedBy: "ben")
        try AtomicFile.writeJSON(c, to: root.appendingPathComponent("collections/\(c.id).json"))
        s = try await store.applyExternalChanges(paths: [root.appendingPathComponent("collections/\(c.id).json").path])
        #expect(s.collectionsChanged)
        #expect(try await store.index.collections().map(\.name) == ["From Ben"])
        let again = try await store.applyExternalChanges(paths: [root.appendingPathComponent("collections/\(c.id).json").path])
        #expect(again.collectionsChanged == false)
    }

    @Test func addedByCountsAndFilter() async throws {
        let (store, root) = try TestSupport.newStore()
        for (i, who) in ["ana", "ana", "ben", "cara", "ana"].enumerated() { try remoteWrite(TestSupport.item("i\(i)", addedBy: who), in: root) }
        try await store.rescan()
        #expect(try await store.index.addedByCounts().map { "\($0.who)=\($0.count)" } == ["ana=3", "ben=1", "cara=1"])
        var q = ItemQuery(); q.addedBy = "ben"
        #expect(try await store.index.query(q).map(\.name) == ["i2"])
    }

    @Test func datalessFlagDetection() throws {
        #expect(FileAvailability.isDataless(flags: 0x4000_0000))
        #expect(FileAvailability.isDataless(flags: 0x4000_0001))
        #expect(!FileAvailability.isDataless(flags: 0x0000_0020))
        let f = TestSupport.tempDir().appendingPathComponent("a.txt")
        try Data("x".utf8).write(to: f)
        #expect(FileAvailability.of(f) == .local)
        #expect(FileAvailability.of(f.deletingLastPathComponent().appendingPathComponent("missing")) == .local)
    }
}

@Suite struct TransferTests {
    @Test func copyCollectionTreeKeepsStructureTagsAndDedupes() async throws {
        let (a, _) = try TestSupport.newStore(handle: "ana")
        let (b, bRoot) = try TestSupport.newStore(handle: "ben")
        let dir = TestSupport.tempDir()
        let folder = try await a.createCollection(name: "Campaign", kind: "folder")
        let sub = try await a.createCollection(name: "Diwali", parentId: folder.id)
        let i1 = try await a.addItem(fileAt: TestSupport.makePNG(in: dir, name: "1", rgb: (1, 0, 0)), tags: ["red"], collectionIds: [sub.id]).item
        let i2 = try await a.addItem(fileAt: TestSupport.makePNG(in: dir, name: "2", rgb: (0, 1, 0)), collectionIds: [sub.id, folder.id]).item
        // b already has the second picture (same bytes) in its Inbox
        let existing = try await b.addItem(fileAt: TestSupport.makePNG(in: dir, name: "2b", rgb: (0, 1, 0))).item

        let r = try await LibraryTransfer.transferCollection(id: folder.id, from: a, to: b, move: false)
        #expect(r.copiedItems == 1 && r.reusedItems == 1 && r.collections == 2)

        let cols = try await b.index.collections()
        let newFolder = try #require(cols.first { $0.name == "Campaign" })
        let newSub = try #require(cols.first { $0.name == "Diwali" })
        #expect(newFolder.parentId == nil && newSub.parentId == newFolder.id)
        #expect(newFolder.id != folder.id)                                          // fresh ids in the destination
        #expect(Set(try await b.index.itemIds(inCollection: newSub.id)) == [i1.id, existing.id])
        let copied = try #require(try await b.item(id: i1.id))
        #expect(copied.tags == ["red"] && copied.updatedBy == "ben" && copied.addedBy == "ana")
        #expect(FileManager.default.fileExists(atPath: bRoot.appendingPathComponent("items/\(i1.id)/original.png").path))
        #expect(FileManager.default.fileExists(atPath: bRoot.appendingPathComponent("items/\(i1.id)/thumb.jpg").path))
        let reused = try await b.item(id: existing.id)
        #expect(reused?.collections.keys.contains(newSub.id) == true)
        // source untouched
        let aCollections = try await a.index.collections().count, aItems = try await a.index.count(ItemQuery())
        #expect(aCollections == 2 && aItems == 2)
        _ = i2
    }

    @Test func moveTrashesOnlyItemsThatLivedOnlyInThatCollection() async throws {
        let (a, _) = try TestSupport.newStore()
        let (b, _) = try TestSupport.newStore()
        let dir = TestSupport.tempDir()
        let moving = try await a.createCollection(name: "Moving"), staying = try await a.createCollection(name: "Staying")
        let only = try await a.addItem(fileAt: TestSupport.makePNG(in: dir, name: "o", rgb: (1, 0, 0)), collectionIds: [moving.id]).item
        let shared = try await a.addItem(fileAt: TestSupport.makePNG(in: dir, name: "s", rgb: (0, 0, 1)), collectionIds: [moving.id, staying.id]).item

        let r = try await LibraryTransfer.transferCollection(id: moving.id, from: a, to: b, move: true)
        #expect(r.copiedItems == 2 && r.trashedInSource == 1)
        #expect(try await a.index.collections().map(\.name) == ["Staying"])
        #expect(try await a.item(id: only.id)?.deletedAt != nil)
        let still = try #require(try await a.item(id: shared.id))
        #expect(still.deletedAt == nil && still.collections.keys.sorted() == [staying.id])
        #expect(try await b.index.count(ItemQuery()) == 2)
    }
}

// MARK: Two Macs, one folder

@Suite(.serialized) struct TwoMacHarnessTests {
    struct Rng: RandomNumberGenerator {
        var s: UInt64
        mutating func next() -> UInt64 { s &+= 0x9E37_79B9_7F4A_7C15; var z = s; z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9; z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB; return z ^ (z >> 31) }
    }

    /// Both stores work on the same folder at once (as two Macs through a synced drive would): 500 random adds,
    /// tags, collection moves and likes each. Plain local files can't produce sync conflict copies, so concurrent edits
    /// to one item may lose an update, but nothing may ever be corrupt, half-written, or missing from either index.
    @Test func twoStoresHammeringOneFolderEndUpConsistent() async throws {
        let root = TestSupport.tempDir("twomac").appendingPathComponent("Shared.grails")
        let ana = try LibraryStore.create(at: root, name: "Shared", index: try LibraryIndex(path: nil), userHandle: "ana")
        let ben = try await LibraryStore.open(at: root, index: try LibraryIndex(path: nil), userHandle: "ben")
        let collection = try await ana.createCollection(name: "Shared collection")
        let images = TestSupport.tempDir("imgs")

        func work(_ store: LibraryStore, seed: UInt64, prefix: String) async throws -> [String] {
            var rng = Rng(s: seed)
            var mine: [String] = []
            for i in 0..<500 {
                let roll = Int.random(in: 0..<100, using: &rng)
                if roll < 40 || mine.isEmpty {
                    let r = Double(i % 20) / 20, g = Double((i / 20) % 20) / 20, b = prefix == "a" ? 0.1 : 0.9
                    let png = TestSupport.makePNG(in: images, name: "\(prefix)\(i)", width: 24, height: 24, rgb: (r, g, b))
                    mine.append(try await store.addItem(fileAt: png, name: "\(prefix)-\(i)").item.id)
                } else {
                    // act on any item either Mac has made, including the other's
                    let shared = try await store.index.query({ var q = ItemQuery(); q.limit = 50; q.sort = .random; return q }())
                    let id = shared.randomElement(using: &rng)?.id ?? mine.randomElement(using: &rng)!
                    switch roll {
                    case ..<60: try await store.addTags(["t\(Int.random(in: 0..<8, using: &rng))"], to: [id])
                    case ..<75: try await store.removeTags(["t\(Int.random(in: 0..<8, using: &rng))"], from: [id])
                    case ..<90: try await store.add(ids: [id], toCollection: collection.id)
                    default: try await store.setLiked(Bool.random(using: &rng), ids: [id])
                    }
                }
                if i % 40 == 0 { try await store.rescan() }       // the periodic safety-net rescan
            }
            return mine
        }

        async let a = work(ana, seed: 1, prefix: "a")
        async let b = work(ben, seed: 2, prefix: "b")
        let (anaItems, benItems) = try await (a, b)

        // settle: each Mac rescans after the other has finished
        try await ana.rescan(); try await ben.rescan()
        let r1 = try await ana.rescan(), r2 = try await ben.rescan()
        #expect(r1 == RescanResult() && r2 == RescanResult())

        // every item.json parses; no half-written temp files or conflict copies anywhere
        let fm = FileManager.default
        var invalid = 0, temps = 0, count = 0
        for folder in try fm.contentsOfDirectory(at: root.appendingPathComponent("items"), includingPropertiesForKeys: nil) {
            for name in try fm.contentsOfDirectory(atPath: folder.path) {
                if AtomicFile.isTemp(name) || ConflictMerger.isItemConflictCopy(name) { temps += 1 }
            }
            if (try? GrailsJSON.decode(Item.self, from: Data(contentsOf: folder.appendingPathComponent("item.json")))) == nil { invalid += 1 } else { count += 1 }
        }
        #expect(invalid == 0 && temps == 0)
        let expected = Set(anaItems + benItems)       // identical pictures dedupe, so compare unique ids
        #expect(count == expected.count)

        // both indexes agree, and contain everything either Mac added
        func snapshot(_ s: LibraryStore) async throws -> [String] {
            var q = ItemQuery(); q.limit = Int.max; q.sort = .addedAsc
            let rows = try await s.index.query(q)
            var out: [String] = []
            for row in rows {
                let tags = (try await s.item(id: row.id)?.tags ?? []).sorted().joined(separator: ",")
                out.append("\(row.id)|\(row.liked)|\(tags)")
            }
            return out
        }
        let sa = try await snapshot(ana), sb = try await snapshot(ben)
        #expect(sa == sb)
        #expect(sa.count == expected.count && sa.count > 300)
        #expect(Set(sa.map { String($0.prefix(26)) }) == expected)
        let tagsA = try await ana.index.tagCounts().map { "\($0.tag)=\($0.count)" }
        let tagsB = try await ben.index.tagCounts().map { "\($0.tag)=\($0.count)" }
        #expect(tagsA == tagsB)
    }
}
