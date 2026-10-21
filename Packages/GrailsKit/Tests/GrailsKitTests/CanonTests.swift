import Foundation
import Testing
@testable import GrailsKit

@Suite struct CanonTests {
    /// An older library names the collection Baseline and may set a `baseline` field.
    /// Opening it still presents that collection as Canon, and the file is left alone.
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
        #expect(canon?.displayName == "Canon")
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
        #expect(decoded.displayName == "Canon")
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
    }
}
