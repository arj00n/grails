import Foundation
import Testing
@testable import GrailsKit

@Suite struct CanonTests {
    /// Owners and admins toggle it; members see an item that's in it, and nothing for one that isn't.
    @Test func onlyThoseWhoMayPromoteCanToggleTheButton() {
        #expect(Canon.control(isIn: false, canPromote: true) == .add)
        #expect(Canon.control(isIn: true, canPromote: true) == .remove)
        #expect(Canon.control(isIn: true, canPromote: false) == .state)
        #expect(Canon.control(isIn: false, canPromote: false) == .hidden)
    }

    /// An older library names the collection Baseline and may set a `baseline` field.
    /// Opening it still presents that collection as Holy Grail, and the file is left alone.
    @Test func legacyBaselineLibraryLoadsAsCanon() async throws {
        let libraryID = "01ARZ3NDEKTSV4RRFFQ69G5FAX"
        let collectionID = "01ARZ3NDEKTSV4RRFFQ69G5FAV"
        let itemID = "01ARZ3NDEKTSV4RRFFQ69G5FAY"
        let root = TestSupport.tempDir().appendingPathComponent("Studio.grails", isDirectory: true)
        let layout = LibraryLayout(root: root)
        let fm = FileManager.default
        try fm.createDirectory(at: layout.collectionsDir, withIntermediateDirectories: true)
        try fm.createDirectory(at: layout.itemDir(itemID), withIntermediateDirectories: true)

        let library = """
        {
          "schema": 1,
          "id": "\(libraryID)",
          "name": "Studio",
          "createdAt": "2026-01-15T12:00:00.000Z"
        }
        """
        let collection = """
        {
          "schema": 1,
          "id": "\(collectionID)",
          "kind": "collection",
          "name": "Baseline",
          "order": "a0",
          "archived": false,
          "updatedAt": "2026-01-15T12:00:00.000Z",
          "updatedBy": "ada",
          "baseline": "Why it works: the crop leaves room for the headline"
        }
        """
        let item = """
        {
          "schema": 1,
          "id": "\(itemID)",
          "kind": "image",
          "name": "Poster crop",
          "note": "Why it works: the crop leaves room for the headline",
          "collections": { "\(collectionID)": "a0" },
          "addedAt": "2026-01-15T12:00:00.000Z",
          "addedBy": "ada",
          "updatedAt": "2026-01-15T12:00:00.000Z",
          "updatedBy": "ada"
        }
        """
        try library.write(to: layout.manifestURL, atomically: true, encoding: .utf8)
        let collectionURL = layout.collectionURL(collectionID)
        try collection.write(to: collectionURL, atomically: true, encoding: .utf8)
        try item.write(to: layout.itemJSON(itemID), atomically: true, encoding: .utf8)
        let before = try Data(contentsOf: collectionURL)

        let store = try await LibraryStore.open(at: root, index: try LibraryIndex(path: nil))
        let loaded = try await store.index.collections()
        let canon = Canon.collection(in: loaded)
        #expect(canon?.id == collectionID)
        #expect(canon?.name == "Baseline")
        #expect(canon?.displayName == "Holy Grail")
        #expect(canon?.isCanon == true)

        var query = ItemQuery()
        query.collectionId = collectionID
        #expect(try await store.index.query(query).map(\.name) == ["Poster crop"])
        #expect(try await store.item(id: itemID)?.note == "Why it works: the crop leaves room for the headline")

        let after = try Data(contentsOf: collectionURL)
        #expect(after == before)
        let raw = String(decoding: after, as: UTF8.self)
        #expect(raw.contains("\"name\": \"Baseline\""))
        #expect(raw.contains("\"baseline\""))
        #expect(!raw.contains("\"canon\""))

        let decoded = try GrailsJSON.decode(GrailsCollection.self, from: after)
        #expect(decoded.isCanon)
        #expect(decoded.displayName == "Holy Grail")
        #expect(decoded.extras["baseline"] == .string("Why it works: the crop leaves room for the headline"))
        let rewritten = String(decoding: try GrailsJSON.encode(decoded), as: UTF8.self)
        #expect(rewritten.contains("\"baseline\""))
        #expect(rewritten.contains("\"name\" : \"Baseline\""))
        #expect(!rewritten.contains("\"canon\""))
    }

    @Test func baselineFlagWithoutTheOldNameStillMarksCanon() throws {
        let json = """
        {
          "schema": 1, "id": "01ARZ3NDEKTSV4RRFFQ69G5FAV", "kind": "collection", "name": "References",
          "order": "a0", "updatedAt": "2026-01-15T12:00:00.000Z", "updatedBy": "ada", "baseline": true
        }
        """
        let collection = try GrailsJSON.decode(GrailsCollection.self, from: Data(json.utf8))
        #expect(collection.isCanon)
        #expect(collection.displayName == "References")
        let again = String(decoding: try GrailsJSON.encode(collection), as: UTF8.self)
        #expect(again.contains("\"baseline\" : true"))
        #expect(!again.contains("\"canon\""))
        #expect(!again.contains("Holy Grail"))
    }

    /// A library saved while the set was called Canon uses that stored name and no `baseline` field.
    /// Opening it presents the collection as Holy Grail and does not rewrite the file.
    @Test func canonLibraryLoadsAsHolyGrail() async throws {
        let libraryID = "01ARZ3NDEKTSV4RRFFQ69G5FAX"
        let collectionID = "01ARZ3NDEKTSV4RRFFQ69G5FAV"
        let itemID = "01ARZ3NDEKTSV4RRFFQ69G5FAY"
        let root = TestSupport.tempDir().appendingPathComponent("Studio.grails", isDirectory: true)
        let layout = LibraryLayout(root: root)
        let fm = FileManager.default
        try fm.createDirectory(at: layout.collectionsDir, withIntermediateDirectories: true)
        try fm.createDirectory(at: layout.itemDir(itemID), withIntermediateDirectories: true)

        let library = """
        {
          "schema": 1,
          "id": "\(libraryID)",
          "name": "Studio",
          "createdAt": "2026-01-15T12:00:00.000Z"
        }
        """
        let collection = """
        {
          "schema": 1,
          "id": "\(collectionID)",
          "kind": "collection",
          "name": "Canon",
          "order": "a0",
          "archived": false,
          "updatedAt": "2026-01-15T12:00:00.000Z",
          "updatedBy": "ada"
        }
        """
        let item = """
        {
          "schema": 1,
          "id": "\(itemID)",
          "kind": "image",
          "name": "Poster crop",
          "note": "Why it works: the crop leaves room for the headline",
          "collections": { "\(collectionID)": "a0" },
          "addedAt": "2026-01-15T12:00:00.000Z",
          "addedBy": "ada",
          "updatedAt": "2026-01-15T12:00:00.000Z",
          "updatedBy": "ada"
        }
        """
        try library.write(to: layout.manifestURL, atomically: true, encoding: .utf8)
        let collectionURL = layout.collectionURL(collectionID)
        try collection.write(to: collectionURL, atomically: true, encoding: .utf8)
        try item.write(to: layout.itemJSON(itemID), atomically: true, encoding: .utf8)
        let before = try Data(contentsOf: collectionURL)

        let store = try await LibraryStore.open(at: root, index: try LibraryIndex(path: nil))
        let loaded = try await store.index.collections()
        let holyGrail = Canon.collection(in: loaded)
        #expect(holyGrail?.id == collectionID)
        #expect(holyGrail?.name == "Canon")
        #expect(holyGrail?.displayName == "Holy Grail")
        #expect(holyGrail?.isCanon == true)

        var query = ItemQuery()
        query.collectionId = collectionID
        #expect(try await store.index.query(query).map(\.name) == ["Poster crop"])

        let after = try Data(contentsOf: collectionURL)
        #expect(after == before)
        let raw = String(decoding: after, as: UTF8.self)
        #expect(raw.contains("\"name\": \"Canon\""))
        #expect(!raw.contains("\"baseline\""))
        #expect(!raw.contains("Holy Grail"))

        let decoded = try GrailsJSON.decode(GrailsCollection.self, from: after)
        #expect(decoded.isCanon)
        #expect(decoded.displayName == "Holy Grail")
        #expect(decoded.extras["baseline"] == nil)
        let rewritten = String(decoding: try GrailsJSON.encode(decoded), as: UTF8.self)
        #expect(rewritten.contains("\"name\" : \"Canon\""))
        #expect(!rewritten.contains("\"baseline\""))
        #expect(!rewritten.contains("Holy Grail"))

        let listed = await LibraryCaptureService(store: { store }).collections().map(\.name)
        #expect(listed == ["Holy Grail"])
    }

    /// A new set is still stored as Canon. An older build only treats Canon and Baseline as this collection.
    @Test func newSetIsStoredUnderTheNameOlderAppsStillRead() async throws {
        let (store, _) = try TestSupport.newStore()
        let created = try await store.createCollection(name: Canon.name)
        #expect(created.name == "Canon")
        #expect(created.displayName == "Holy Grail")
        let raw = String(decoding: try Data(contentsOf: store.layout.collectionURL(created.id)), as: UTF8.self)
        #expect(raw.contains("\"name\" : \"Canon\""))
        #expect(!raw.contains("Holy Grail"))
        #expect(!raw.contains("\"baseline\""))
    }

    @Test func offerHidesASelectionAlreadyInTheSet() {
        let offer = Canon.offer(selected: ["a"], alreadyIn: ["a"])
        #expect(offer.adding == [])
        #expect(offer.removing == ["a"])
        #expect(offer.shown == false)
    }

    @Test func offerShowsASelectionWhenTheSetIsEmpty() {
        let offer = Canon.offer(selected: ["a"], alreadyIn: [])
        #expect(offer.adding == ["a"])
        #expect(offer.removing == [])
        #expect(offer.shown == true)
    }

    @Test func offerKeepsSelectedOrderWithoutIdsAlreadyIn() {
        let offer = Canon.offer(selected: ["a", "b", "c"], alreadyIn: ["b"])
        #expect(offer.adding == ["a", "c"])
        #expect(offer.removing == ["b"])
        #expect(offer.shown == true)
    }

    @Test func removingFromHolyGrailLeavesTheItemAndUndoRestoresItsOrder() async throws {
        let (store, _) = try TestSupport.newStore()
        let holyGrail = try await store.createCollection(name: Canon.name)
        let inside = TestSupport.item("inside")
        let outside = TestSupport.item("outside")
        try await TestSupport.seed(store, [inside, outside])
        try await store.add(ids: [inside.id], toCollection: holyGrail.id)
        let orderKey = try await store.item(id: inside.id)?.collections[holyGrail.id]
        #expect(orderKey != nil)

        let (_, undo) = try await store.recording(label: "Remove from Holy Grail") {
            try await store.remove(ids: [inside.id], fromCollection: holyGrail.id)
        }
        let removed = try await store.item(id: inside.id)
        #expect(removed?.deletedAt == nil)
        #expect(removed?.collections[holyGrail.id] == nil)
        let untouched = try await store.item(id: outside.id)
        #expect(untouched?.deletedAt == nil)
        #expect(untouched?.collections[holyGrail.id] == nil)
        #expect(try await store.index.itemIds(inCollection: holyGrail.id).isEmpty)

        _ = try await store.apply(undo)
        let restored = try await store.item(id: inside.id)
        #expect(restored?.deletedAt == nil)
        #expect(restored?.collections[holyGrail.id] == orderKey)
        #expect(try await store.index.itemIds(inCollection: holyGrail.id) == [inside.id])
    }
}
