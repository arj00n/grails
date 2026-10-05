import Foundation
import Testing
@testable import StashKit

@Suite struct OrganizeTests {
    func store(withItems n: Int) async throws -> (LibraryStore, [Item], URL) {
        let (store, root) = try TestSupport.newStore()
        let items = (0..<n).map { TestSupport.item("item\($0)", tags: $0 == 0 ? ["Food"] : []) }
        try await TestSupport.seed(store, items)
        return (store, items, root)
    }

    @Test func addRemoveTagsAreCaseInsensitiveAndDeduped() async throws {
        let (store, items, _) = try await store(withItems: 3)
        let ids = items.map(\.id)
        try await store.addTags(["food", "Hero", " hero "], to: ids)
        #expect(try await store.item(id: items[0].id)?.tags == ["Food", "Hero"])   // kept first spelling
        #expect(try await store.item(id: items[1].id)?.tags == ["food", "Hero"])
        try await store.removeTags(["FOOD"], from: ids)
        #expect(try await store.item(id: items[0].id)?.tags == ["Hero"])
        #expect(try await store.index.tagCounts().map(\.tag) == ["Hero"])
    }

    @Test func renameAndMergeTags() async throws {
        let (store, items, _) = try await store(withItems: 4)
        try await store.addTags(["wip"], to: [items[1].id, items[2].id])
        try await store.addTags(["draft"], to: [items[2].id, items[3].id])
        try await store.setTagColor("#FF8800", for: "wip")

        #expect(try await store.renameTag("wip", to: "draft") == 2)       // merge into existing tag
        #expect(try await store.item(id: items[2].id)?.tags == ["draft"])   // not duplicated
        #expect(try await store.item(id: items[1].id)?.tags == ["draft"])
        #expect(try await store.index.tagCounts().first { $0.tag == "draft" }?.count == 3)
        #expect(await store.tagMetadata()["draft"]?.color == "#FF8800")      // colour moved with the rename
        #expect(await store.tagMetadata()["wip"] == nil)

        #expect(try await store.deleteTag("draft") == 3)
        #expect(try await store.index.tagCounts().map(\.tag) == ["Food"])
    }

    @Test func tagRenameReportsProgress() async throws {
        let (store, items, _) = try await store(withItems: 60)
        try await store.addTags(["bulk"], to: items.map(\.id))
        final class Box: @unchecked Sendable { var calls: [(Int, Int)] = []; let lock = NSLock() }
        let box = Box()
        try await store.renameTag("bulk", to: "bulk2") { done, total in box.lock.lock(); box.calls.append((done, total)); box.lock.unlock() }
        #expect(box.calls.last?.0 == 60 && box.calls.last?.1 == 60)
        #expect(box.calls.count >= 3)
    }

    @Test func collectionLifecycleRenameArchiveCover() async throws {
        let (store, items, _) = try await store(withItems: 2)
        let c = try await store.createCollection(name: "Packaging")
        try await store.renameCollection(id: c.id, to: "Packaging 2")
        try await store.archiveCollection(id: c.id, true)
        try await store.setCover(itemId: items[0].id, for: c.id)
        let read = try #require(await store.readCollection(id: c.id))
        #expect(read.name == "Packaging 2" && read.archived && read.coverItemId == items[0].id)
        #expect(try await store.index.collections().first?.archived == true)
    }

    @Test func nestingMovingAndCycleProtection() async throws {
        let (store, _, _) = try await store(withItems: 0)
        let folder = try await store.createCollection(name: "Campaigns", kind: "folder")
        let a = try await store.createCollection(name: "Diwali", parentId: folder.id)
        let b = try await store.createCollection(name: "Holi", parentId: folder.id)
        let sub = try await store.createCollection(name: "Sub", kind: "folder", parentId: folder.id)
        #expect(try await store.collectionTree(rootedAt: folder.id) == [folder.id, a.id, b.id, sub.id])

        try await store.moveCollection(id: b.id, toParent: folder.id, after: nil)        // to the front
        #expect(try await store.index.collections().filter { $0.parentId == folder.id }.map(\.name) == ["Holi", "Diwali", "Sub"])
        try await store.moveCollection(id: a.id, toParent: sub.id)
        #expect(try await store.collectionTree(rootedAt: sub.id) == [sub.id, a.id])
        try await store.moveCollection(id: folder.id, toParent: sub.id)                   // folder into its own descendant: ignored
        #expect(try await store.readCollection(id: folder.id)?.parentId == nil)
        try await store.moveCollection(id: a.id, toParent: nil, after: folder.id)
        #expect(try await store.index.collections().filter { $0.parentId == nil }.map(\.name) == ["Campaigns", "Diwali"])
    }

    @Test func folderShowsUnionOfItsCollections() async throws {
        let (store, items, _) = try await store(withItems: 4)
        let folder = try await store.createCollection(name: "F", kind: "folder")
        let a = try await store.createCollection(name: "A", parentId: folder.id)
        let b = try await store.createCollection(name: "B", parentId: folder.id)
        try await store.add(ids: [items[0].id, items[1].id], toCollection: a.id)
        try await store.add(ids: [items[1].id, items[2].id], toCollection: b.id)
        var q = ItemQuery(); q.collectionIds = try await store.collectionTree(rootedAt: folder.id); q.sort = .nameAsc
        #expect(try await store.index.query(q).map(\.name) == ["item0", "item1", "item2"])
    }

    @Test func addMoveRemoveItemsKeepsOrderKeys() async throws {
        let (store, items, _) = try await store(withItems: 3)
        let a = try await store.createCollection(name: "A"), b = try await store.createCollection(name: "B")
        try await store.add(ids: items.map(\.id), toCollection: a.id)
        let keys = try await items.asyncMap { try await store.item(id: $0.id)!.collections[a.id]! }
        #expect(keys == keys.sorted() && Set(keys).count == 3)
        try await store.add(ids: [items[0].id], toCollection: a.id)                       // already there: no change
        #expect(try await store.item(id: items[0].id)?.collections[a.id] == keys[0])

        try await store.move(ids: [items[0].id, items[1].id], from: a.id, to: b.id)
        #expect(try await store.index.itemIds(inCollection: a.id) == [items[2].id])
        #expect(Set(try await store.index.itemIds(inCollection: b.id)) == [items[0].id, items[1].id])

        try await store.setOrder(itemId: items[1].id, in: b.id, after: nil, before: try await store.item(id: items[0].id)?.collections[b.id])
        #expect(try await store.item(id: items[1].id)!.collections[b.id]! < store.item(id: items[0].id)!.collections[b.id]!)
    }

    @Test func duplicateAndDeleteCollection() async throws {
        let (store, items, _) = try await store(withItems: 2)
        let folder = try await store.createCollection(name: "F", kind: "folder")
        let child = try await store.createCollection(name: "Child", parentId: folder.id)
        try await store.add(ids: items.map(\.id), toCollection: child.id)

        let copy = try await store.duplicateCollection(id: folder.id)
        #expect(copy.name == "F copy")
        let copyChildren = try await store.index.collections().filter { $0.parentId == copy.id }
        #expect(copyChildren.map(\.name) == ["Child"])
        #expect(Set(try await store.index.itemIds(inCollection: copyChildren[0].id)) == Set(items.map(\.id)))
        #expect(Set(try await store.index.itemIds(inCollection: child.id)) == Set(items.map(\.id)))   // original untouched

        try await store.deleteCollection(id: folder.id)                                      // child moves up
        #expect(try await store.readCollection(id: child.id)?.parentId == nil)
        try await store.deleteCollection(id: child.id)
        #expect(try await store.item(id: items[0].id)?.collections[child.id] == nil)
        #expect(try await store.index.collections().map(\.name).sorted() == ["Child", "F copy"])
    }

    @Test func likeAndNoteBulkEdits() async throws {
        let (store, items, _) = try await store(withItems: 3)
        try await store.setLiked(true, ids: [items[0].id, items[2].id])
        try await store.setNote("hero", ids: [items[1].id])
        var liked = ItemQuery(); liked.likedOnly = true
        #expect(try await store.index.count(liked) == 2)
        #expect(try await store.index.query(ItemQuery(text: "hero")).map(\.id) == [items[1].id])
    }

    @Test func squareFilter() async throws {
        let (store, _) = try TestSupport.newStore()
        try await TestSupport.seed(store, [TestSupport.item("sq", w: 100, h: 102), TestSupport.item("wide", w: 200, h: 100), TestSupport.item("none", w: 0, h: 0)])
        var q = ItemQuery(); q.squareOnly = true
        #expect(try await store.index.query(q).map(\.name) == ["sq"])
    }
}

@Suite struct UndoTests {
    @Test func undoAndRedoTagChange() async throws {
        let (store, root) = try TestSupport.newStore()
        let item = TestSupport.item("a", tags: ["keep"])
        try await TestSupport.seed(store, [item])
        let (_, undo) = try await store.recording(label: "Tag") { try await store.addTags(["new"], to: [item.id]) }
        #expect(try await store.item(id: item.id)?.tags == ["keep", "new"])
        #expect(undo.items.count == 1 && undo.label == "Tag")

        let redo = try await store.apply(undo)
        #expect(try await store.item(id: item.id)?.tags == ["keep"])
        #expect(try await store.index.query(ItemQuery(text: "new")).isEmpty)
        _ = try await store.apply(redo)
        #expect(try await store.item(id: item.id)?.tags == ["keep", "new"])
        #expect(try await store.index.query(ItemQuery(text: "new")).count == 1)
        _ = root
    }

    @Test func undoingAnAddMovesItToTrashAndRedoRestoresIt() async throws {
        let (store, _) = try TestSupport.newStore()
        let png = TestSupport.makePNG(in: TestSupport.tempDir(), name: "x")
        let (result, undo) = try await store.recording(label: "Add") { try await store.addItem(fileAt: png) }
        let id = result.item.id
        let redo = try await store.apply(undo)
        #expect(try await store.index.count(ItemQuery()) == 0)
        #expect(try await store.item(id: id)?.deletedAt != nil)
        _ = try await store.apply(redo)
        #expect(try await store.index.count(ItemQuery()) == 1)
    }

    @Test func undoCollectionCreationAndDeletion() async throws {
        let (store, _) = try TestSupport.newStore()
        let item = TestSupport.item("a")
        try await TestSupport.seed(store, [item])
        let (c, undoCreate) = try await store.recording(label: "New collection") { try await store.createCollection(name: "Temp") }
        let redoCreate = try await store.apply(undoCreate)
        #expect(try await store.index.collections().isEmpty)
        _ = try await store.apply(redoCreate)
        #expect(try await store.index.collections().map(\.id) == [c.id])

        try await store.add(ids: [item.id], toCollection: c.id)
        let (_, undoDelete) = try await store.recording(label: "Delete collection") { try await store.deleteCollection(id: c.id) }
        #expect(try await store.index.collections().isEmpty)
        #expect(try await store.item(id: item.id)?.collections.isEmpty == true)
        _ = try await store.apply(undoDelete)
        #expect(try await store.index.collections().map(\.id) == [c.id])
        #expect(try await store.item(id: item.id)?.collections.keys.contains(c.id) == true)
    }

    @Test func undoSmartFolderChanges() async throws {
        let (store, _) = try TestSupport.newStore()
        let (f, undo) = try await store.recording(label: "New smart folder") { try await store.createSmartFolder(name: "S", rules: []) }
        #expect(await store.smartFolders().count == 1)
        let redo = try await store.apply(undo)
        #expect(await store.smartFolders().isEmpty)
        _ = try await store.apply(redo)
        #expect(await store.smartFolders().map(\.id) == [f.id])
    }

    @Test func recordingCapturesOnlyFirstStatePerItem() async throws {
        let (store, _) = try TestSupport.newStore()
        let item = TestSupport.item("a")
        try await TestSupport.seed(store, [item])
        let (_, undo) = try await store.recording(label: "Two edits") {
            try await store.setLiked(true, ids: [item.id])
            try await store.setNote("n", ids: [item.id])
        }
        _ = try await store.apply(undo)
        let restored = try #require(try await store.item(id: item.id))
        #expect(!restored.liked && restored.note.isEmpty)
    }
}

extension Sequence {
    func asyncMap<T>(_ transform: (Element) async throws -> T) async rethrows -> [T] {
        var out: [T] = []
        for e in self { out.append(try await transform(e)) }
        return out
    }
}

@Suite struct StashLinkTests {
    @Test func linksRoundTrip() throws {
        let cases: [StashLink] = [
            .init(library: "01J9", name: "Swish Inspo"),
            .init(library: "01J9", name: "Swish & Co: refs", target: .collection("01JC"), canvas: true),
            .init(library: "01J9", target: .tag("street style")),
            .init(library: "01J9", target: .item("01JX")),
        ]
        for c in cases { #expect(StashLink(url: c.url) == c, "\(c.url)") }
        #expect(StashLink(text: "  \(cases[1].url.absoluteString)\n") == cases[1])
    }

    @Test func otherLinksAreNotOurs() {
        #expect(StashLink(text: "https://example.com/?lib=1") == nil)
        #expect(StashLink(text: "stash://open") == nil)
        #expect(StashLink(text: "stash://elsewhere?lib=1") == nil)
        #expect(StashLink(text: "not a link") == nil)
    }
}
