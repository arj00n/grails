import Foundation
import Testing
@testable import GrailsKit

@Suite struct PlacementTests {
    private func node(_ id: String, _ name: String, kind: String = "collection", parent: String? = nil, order: String = "a", archived: Bool = false) -> GrailsCollection {
        GrailsCollection(id: id, kind: kind, name: name, parentId: parent, order: order, archived: archived, updatedBy: "ada")
    }

    @Test func movePaletteListsFoldersIndentedUnderTheirParent() {
        let rows = ItemPlacement.destinations([
            node("loose", "Loose", order: "c"),
            node("diwali", "Diwali", parent: "campaigns", order: "b"),
            node("spring", "Spring", kind: "folder", parent: "campaigns", order: "d"),
            node("campaigns", "Campaigns", kind: "folder", order: "a"),
            node("old", "Old", kind: "folder", order: "e", archived: true),
        ], query: "", openCollection: nil)

        #expect(rows.map(\.label) == ["Campaigns", "Campaigns / Diwali", "Campaigns / Spring", "Loose"])
        #expect(rows.map(\.kind) == ["folder", "collection", "folder", "collection"])
        #expect(rows.map(\.depth) == [0, 1, 1, 0])
        #expect(!rows.contains { $0.id == "old" })
    }

    @Test func movePaletteSearchFindsAFolderAndFlattens() {
        let rows = ItemPlacement.destinations([
            node("campaigns", "Campaigns", kind: "folder", order: "a"),
            node("spring", "Spring", kind: "folder", parent: "campaigns", order: "b"),
        ], query: "spr", openCollection: nil)

        #expect(rows.map(\.id) == ["spring"])
        #expect(rows.map(\.label) == ["Campaigns / Spring"])
        #expect(rows.map(\.depth) == [0])
    }

    @Test func movePaletteKeepsChildrenWhenTheOpenCollectionIsHidden() {
        let rows = ItemPlacement.destinations([
            node("campaigns", "Campaigns", kind: "folder", order: "a"),
            node("diwali", "Diwali", parent: "campaigns", order: "b"),
        ], query: "", openCollection: "campaigns")

        #expect(rows.map(\.id) == ["diwali"])
        #expect(rows.map(\.label) == ["Campaigns / Diwali"])
        #expect(rows.map(\.depth) == [0])
    }

    @Test func inspectorAddToFolderUsesTheSameActionAsMove() {
        let filed = ItemPlacement.action(ids: ["item"], openCollection: "diwali", target: "spring")
        #expect(filed.from == "diwali")
        #expect(filed.target == "spring")
        #expect(filed.isMove)
        #expect(filed.ids == ["item"])

        let add = ItemPlacement.action(ids: ["item"], openCollection: nil, target: "spring")
        #expect(add.from == nil)
        #expect(!add.isMove)
    }

    @Test func folderDropAcceptsItemIdsWhenTheFileIsMissing() {
        #expect(ItemPlacement.acceptsItemDrop(kind: "folder", itemIDs: ["item-1"]))
        #expect(ItemPlacement.acceptsItemDrop(kind: "collection", itemIDs: ["item-1"]))
        #expect(!ItemPlacement.acceptsItemDrop(kind: "folder", itemIDs: []))
    }

    @Test func addToFolderWritesTheSameMembershipAsACollection() async throws {
        let (store, root) = try TestSupport.newStore()
        defer { try? FileManager.default.removeItem(at: root) }
        let item = TestSupport.item("poster")
        try await TestSupport.seed(store, [item])
        let folder = try await store.createCollection(name: "Campaigns")
        let collection = try await store.createCollection(name: "Diwali", parentId: folder.id)
        try await store.add(ids: [item.id], toCollection: collection.id)

        let add = ItemPlacement.action(ids: [item.id], openCollection: nil, target: folder.id)
        try await store.add(ids: add.ids, toCollection: add.target)
        #expect(try await store.item(id: item.id)?.collections[folder.id] != nil)
        #expect(try await store.item(id: item.id)?.collections[collection.id] != nil)

        let move = ItemPlacement.action(ids: [item.id], openCollection: collection.id, target: folder.id)
        if let from = move.from {
            try await store.move(ids: move.ids, from: from, to: move.target)
        }
        #expect(try await store.item(id: item.id)?.collections[collection.id] == nil)
        #expect(try await store.item(id: item.id)?.collections[folder.id] != nil)
    }
}
