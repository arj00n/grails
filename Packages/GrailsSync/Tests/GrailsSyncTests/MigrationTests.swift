import Foundation
import XCTest
import GrailsSync

final class MigrationTests: XCTestCase {
    func testCopyLeavesTheSourceAndResumes() async throws {
        let root = try TestLibrary.makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let first = try write(root, "items/a/original.jpg", Data("aaa".utf8))
        let second = try write(root, "items/b/original.jpg", Data("bbb".utf8))
        let hidden = root.appendingPathComponent(".DS_Store")
        try Data("local-only".utf8).write(to: hidden)
        let before = try fingerprint(root)
        let store = MemoryObjectStore()

        let partial = try await LibraryMigration.copy(root: root, store: store, limit: 1)
        XCTAssertEqual(partial.copied, 1)
        XCTAssertEqual(partial.total, 2)
        XCTAssertEqual(partial.remaining.count, 1)
        XCTAssertFalse(partial.finished)
        XCTAssertEqual(try fingerprint(root), before)
        let partialCounts = await store.counts()
        XCTAssertEqual(partialCounts.deletes, 0)

        let done = try await LibraryMigration.copy(root: root, store: store, limit: 10)
        XCTAssertEqual(done.copied, 2)
        XCTAssertEqual(done.total, 2)
        XCTAssertTrue(done.remaining.isEmpty)
        XCTAssertTrue(done.finished)
        let firstBody = await store.body(first.key)
        let secondBody = await store.body(second.key)
        XCTAssertEqual(firstBody, Data("aaa".utf8))
        XCTAssertEqual(secondBody, Data("bbb".utf8))
        XCTAssertEqual(try fingerprint(root), before)
        XCTAssertEqual(try Data(contentsOf: hidden), Data("local-only".utf8))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent(LibraryMigration.ledgerKey).path))
        let doneCounts = await store.counts()
        XCTAssertEqual(doneCounts.deletes, 0)

        let puts = await store.recordedPuts().filter { $0.key == first.key || $0.key == second.key }
        XCTAssertEqual(puts.count, 2)
        let again = try await LibraryMigration.copy(root: root, store: store)
        XCTAssertTrue(again.finished)
        XCTAssertEqual(again.copied, 2)
        let filePuts = await store.recordedPuts().filter { $0.key == first.key || $0.key == second.key }
        XCTAssertEqual(filePuts.count, 2)
        XCTAssertEqual(try fingerprint(root), before)
    }

    func testCopyKeepsAnEditThatLandsDuringTheBatch() async throws {
        let root = try TestLibrary.makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try write(root, "items/a/original.jpg", Data("aaa".utf8))
        try write(root, "items/b/original.jpg", Data("bbb".utf8))
        let inner = MemoryObjectStore()
        let store = EditDuringCopy(inner: inner, root: root)
        let edited = Data("edited-during-copy".utf8)

        var progress = try await LibraryMigration.copy(root: root, store: store, limit: 8)
        var rounds = 0
        while !progress.finished, rounds < 6 {
            progress = try await LibraryMigration.copy(root: root, store: store, limit: 8)
            rounds += 1
        }

        let copiedA = await inner.body("items/a/original.jpg")
        let copiedB = await inner.body("items/b/original.jpg")
        XCTAssertTrue(progress.finished)
        XCTAssertEqual(copiedA, edited)
        XCTAssertEqual(copiedB, Data("bbb".utf8))
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("items/a/original.jpg")), edited)
    }

    func testMergeKeepsTheDestinationLibrary() async throws {
        let root = try TestLibrary.makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let same = Data("same-picture".utf8)
        let firstNew = Data("new-a".utf8)
        let secondNew = Data("new-b".utf8)
        let sameHash = Digests.sha256Hex(same)
        let firstHash = Digests.sha256Hex(firstNew)
        let secondHash = Digests.sha256Hex(secondNew)
        let store = MemoryObjectStore()
        let library = Data("{\"createdAt\":\"2019-05-01T00:00:00.000Z\",\"id\":\"LIBDEST\",\"name\":\"Studio Library\",\"schema\":1}".utf8)
        let destCollection = Data("{\"id\":\"COLDEST\",\"name\":\"Studio\",\"updatedAt\":\"2019-05-01T00:00:00.000Z\",\"updatedBy\":\"dest-user\"}".utf8)
        let destItem = Data("{\"addedAt\":\"2019-06-01T00:00:00.000Z\",\"addedBy\":\"dest-user\",\"id\":\"ITEMDEST\",\"sha256\":\"\(sameHash)\"}".utf8)
        let destTags = Data("{\"schema\":1,\"tags\":{\"minimal\":{\"color\":\"#f00\"}}}".utf8)
        let destCanvas = Data("""
        {
          "clusters" : [
            {
              "at" : 10,
              "id" : "DESTCL",
              "items" : [
                "ITEMDEST"
              ],
              "title" : "Kept"
            }
          ],
          "updatedAt" : "2019-01-01T00:00:00.000Z",
          "updatedBy" : "dest-user"
        }
        """.utf8)
        let destMember = Data("{\"handle\":\"ada\",\"lastSeen\":\"2019-01-01T00:00:00.000Z\"}".utf8)
        await store.seed("library.json", body: library)
        await store.seed("collections/COLDEST.json", body: destCollection)
        await store.seed("items/ITEMDEST/item.json", body: destItem)
        await store.seed("tags.json", body: destTags)
        await store.seed("canvas/library.json", body: destCanvas)
        await store.seed(".members/ada.json", body: destMember)

        try write(root, "library.json", Data("{\"id\":\"LIBSRC\",\"name\":\"Team Library\"}".utf8))
        try write(root, "collections/COLSRC.json", Data("{\"id\":\"COLSRC\",\"name\":\"studio\",\"updatedAt\":\"2020-01-01T00:00:00.000Z\",\"updatedBy\":\"ada\"}".utf8))
        try write(root, "collections/COLDEST.json", Data("{\"id\":\"COLDEST\",\"name\":\"Notes\",\"updatedAt\":\"2021-01-01T00:00:00.000Z\",\"updatedBy\":\"ada\"}".utf8))
        try write(root, "tags.json", Data("{\"schema\":1,\"tags\":{\"minimal\":{\"noAuto\":true},\"poster\":{\"noAuto\":true}}}".utf8))
        try write(root, "items/DUPITEM/item.json", itemJSON(id: "DUPITEM", hash: sameHash, addedAt: "2020-01-02T03:04:05.006Z"))
        try write(root, "items/DUPITEM/original.jpg", same)
        try write(root, "items/NEWAAAA/item.json", itemJSON(id: "NEWAAAA", hash: firstHash, addedAt: "2020-01-02T03:04:05.006Z"))
        try write(root, "items/NEWAAAA/original.jpg", firstNew)
        try write(root, "items/NEWBBBB/item.json", itemJSON(id: "NEWBBBB", hash: secondHash, addedAt: "2020-04-04T00:00:00.000Z"))
        try write(root, "items/NEWBBBB/original.jpg", secondNew)
        try write(root, "items/BADITEM/item.json", itemJSON(id: "BADITEM", hash: String(repeating: "ab", count: 32), addedAt: "2020-05-05T00:00:00.000Z"))
        try write(root, "items/BADITEM/original.jpg", Data("not-that".utf8))
        try write(root, "notes/NOTE1.json", Data("{\"at\":\"2020-02-02T00:00:00.000Z\",\"author\":\"ada\",\"id\":\"NOTE1\",\"itemId\":\"DUPITEM\",\"text\":\"hello\"}".utf8))
        try write(root, "canvas/library.json", Data("""
        {
          "clusters" : [
            {
              "at" : 20,
              "id" : "SRCCL",
              "items" : [
                "DUPITEM",
                "NEWAAAA"
              ],
              "title" : "Diwali"
            }
          ],
          "updatedAt" : "2020-03-03T00:00:00.000Z",
          "updatedBy" : "ada"
        }
        """.utf8))
        try write(root, "canvas/COLSRC.json", Data("{\"clusters\":[{\"id\":\"C2\",\"items\":[\"NEWBBBB\"]}],\"updatedBy\":\"ada\"}".utf8))
        try write(root, ".members/ada.json", Data("{\"handle\":\"ada\",\"lastSeen\":\"2024-01-01T00:00:00.000Z\"}".utf8))
        try write(root, ".members/teammate.json", Data("{\"handle\":\"teammate\"}".utf8))
        try write(root, ".snapshots/day.grailssnap", Data("local".utf8))
        let before = try fingerprint(root)

        let partial = try await LibraryMigration.copy(root: root, store: store, limit: 1)
        XCTAssertEqual(partial.merged, 1)
        XCTAssertEqual(partial.duplicates, 1)
        XCTAssertEqual(partial.failures.map(\.reason), ["content hash does not match original.jpg"])
        XCTAssertEqual(partial.remaining, ["NEWBBBB"])
        let partialNote = await store.body("notes/NOTE1.json")
        let partialCanvas = await store.body("canvas/library.json")
        let partialLibrary = await store.body("library.json")
        let partialDestItem = await store.body("items/ITEMDEST/item.json")
        XCTAssertNil(partialNote)
        XCTAssertEqual(partialCanvas, destCanvas)
        XCTAssertEqual(partialLibrary, library)
        XCTAssertEqual(partialDestItem, destItem)

        let done = try await LibraryMigration.copy(root: root, store: store, limit: 8)
        XCTAssertTrue(done.finished)
        XCTAssertEqual(done.merged, 2)
        XCTAssertEqual(done.duplicates, 1)
        XCTAssertEqual(done.skips.filter { $0.key == "items/DUPITEM" }.map(\.reason), ["duplicate of ITEMDEST"])
        XCTAssertTrue(done.skips.contains { $0.key == "library.json" && $0.reason == "kept the destination library" })
        XCTAssertTrue(done.skips.contains { $0.key == ".snapshots/day.grailssnap" })
        XCTAssertTrue(done.skips.contains { $0.key == ".members/ada.json" })
        XCTAssertFalse(done.rewrites.isEmpty)

        let uploadedBody = await store.body("items/NEWAAAA/item.json")
        let uploaded = try XCTUnwrap(uploadedBody)
        let uploadedText = try XCTUnwrap(String(data: uploaded, encoding: .utf8))
        XCTAssertTrue(uploadedText.contains("\"addedAt\" : \"2020-01-02T03:04:05.006Z\""))
        XCTAssertTrue(uploadedText.contains("\"addedBy\" : \"ada\""))
        XCTAssertTrue(uploadedText.contains("\"updatedBy\" : \"ada\""))
        XCTAssertTrue(uploadedText.contains("COLDEST"))
        XCTAssertFalse(uploadedText.contains("COLSRC"))
        let uploadedObject = try XCTUnwrap(JSONSerialization.jsonObject(with: uploaded) as? [String: Any])
        XCTAssertEqual(uploadedObject["tags"] as? [String], ["minimal", "poster"])
        let uploadedFile = await store.body("items/NEWAAAA/original.jpg")
        let duplicateItem = await store.body("items/DUPITEM/item.json")
        let badItem = await store.body("items/BADITEM/item.json")
        let keptLibrary = await store.body("library.json")
        let keptCollection = await store.body("collections/COLDEST.json")
        let keptItem = await store.body("items/ITEMDEST/item.json")
        let keptMember = await store.body(".members/ada.json")
        XCTAssertEqual(uploadedFile, firstNew)
        XCTAssertNil(duplicateItem)
        XCTAssertNil(badItem)
        XCTAssertEqual(keptLibrary, library)
        XCTAssertEqual(keptCollection, destCollection)
        XCTAssertEqual(keptItem, destItem)
        XCTAssertEqual(keptMember, destMember)
        let noteBody = await store.body("notes/NOTE1.json")
        let noteData = try XCTUnwrap(noteBody)
        let note = try XCTUnwrap(String(data: noteData, encoding: .utf8))
        XCTAssertTrue(note.contains("\"author\":\"ada\""))
        XCTAssertTrue(note.contains("2020-02-02T00:00:00.000Z"))
        XCTAssertTrue(note.contains("ITEMDEST"))
        XCTAssertFalse(note.contains("DUPITEM"))
        let canvasBody = await store.body("canvas/library.json")
        let canvasData = try XCTUnwrap(canvasBody)
        let canvas = try XCTUnwrap(String(data: canvasData, encoding: .utf8))
        XCTAssertTrue(canvas.contains("\"updatedBy\" : \"dest-user\""))
        XCTAssertTrue(canvas.contains("2019-01-01T00:00:00.000Z"))
        XCTAssertTrue(canvas.contains("DESTCL"))
        XCTAssertTrue(canvas.contains("SRCCL"))
        XCTAssertTrue(canvas.contains("Diwali"))
        XCTAssertTrue(canvas.contains("NEWAAAA"))
        XCTAssertFalse(canvas.contains("DUPITEM"))
        let collectionCanvas = await store.body("canvas/COLDEST.json")
        let sourceCanvas = await store.body("canvas/COLSRC.json")
        XCTAssertNotNil(collectionCanvas)
        XCTAssertNil(sourceCanvas)
        let tagsBody = await store.body("tags.json")
        let tagsData = try XCTUnwrap(tagsBody)
        let tags = try XCTUnwrap(JSONSerialization.jsonObject(with: tagsData) as? [String: Any])
        let table = try XCTUnwrap(tags["tags"] as? [String: Any])
        let minimal = try XCTUnwrap(table["minimal"] as? [String: Any])
        XCTAssertEqual(minimal["color"] as? String, "#f00")
        XCTAssertNil(minimal["noAuto"])
        let poster = try XCTUnwrap(table["poster"] as? [String: Any])
        XCTAssertEqual(poster["noAuto"] as? Bool, true)
        let collectionKeys = await store.keys().filter { $0.hasPrefix("collections/") }
        XCTAssertEqual(collectionKeys.count, 2)
        let notesCollection = collectionKeys.filter { $0 != "collections/COLDEST.json" }
        let notesFile = await store.body(notesCollection[0])
        let notesData = try XCTUnwrap(notesFile)
        let notesBody = try XCTUnwrap(String(data: notesData, encoding: .utf8))
        XCTAssertTrue(notesBody.contains("Notes"))
        XCTAssertTrue(notesBody.contains("2021-01-01T00:00:00.000Z"))
        XCTAssertTrue(notesBody.contains("ada"))
        let keys = await store.keys()
        XCTAssertFalse(keys.contains { $0.contains(".snapshots") })
        XCTAssertEqual(try fingerprint(root), before)
        let counts = await store.counts()
        XCTAssertEqual(counts.deletes, 0)

        _ = try await LibraryMigration.copy(root: root, store: store)
        let settled = await store.keys()
        let settledLibrary = await store.body("library.json")
        let settledCollection = await store.body("collections/COLDEST.json")
        XCTAssertEqual(settled, keys)
        XCTAssertEqual(settledLibrary, library)
        XCTAssertEqual(settledCollection, destCollection)
        XCTAssertEqual(try fingerprint(root), before)
    }

    private func itemJSON(id: String, hash: String, addedAt: String) -> Data {
        Data("""
        {
          "addedAt" : "\(addedAt)",
          "addedBy" : "ada",
          "collections" : {
            "COLSRC" : "a0"
          },
          "id" : "\(id)",
          "sha256" : "\(hash)",
          "tags" : [
            "Minimal",
            "poster"
          ],
          "updatedAt" : "\(addedAt)",
          "updatedBy" : "ada",
          "file" : "original.jpg"
        }
        """.utf8)
    }

    @discardableResult
    private func write(_ root: URL, _ key: String, _ data: Data) throws -> (key: String, data: Data) {
        let url = root.appendingPathComponent(key)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url)
        return (key, data)
    }

    private func fingerprint(_ root: URL) throws -> [String: Data] {
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey]) else { return [:] }
        var out: [String: Data] = [:]
        while let url = enumerator.nextObject() as? URL {
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), !isDir.boolValue else { continue }
            let relative = url.path.replacingOccurrences(of: root.path + "/", with: "")
            out[relative] = try Data(contentsOf: url)
        }
        return out
    }

    func testCleanETagDropsWeakAndQuotedForms() {
        XCTAssertEqual(S3Client.cleanETag("\"8e4225e1e3c79940ac8b524ddc993433\""), "8e4225e1e3c79940ac8b524ddc993433")
        XCTAssertEqual(S3Client.cleanETag("W/\"8e4225e1e3c79940ac8b524ddc993433\""), "8e4225e1e3c79940ac8b524ddc993433")
        XCTAssertEqual(S3Client.cleanETag("&quot;8e4225e1e3c79940ac8b524ddc993433&quot;"), "8e4225e1e3c79940ac8b524ddc993433")
    }
}

/// Rewrites `items/a` on disk the first time `items/b` is uploaded, once.
private actor EditDuringCopy: ObjectStore {
    private let inner: MemoryObjectStore
    private let root: URL
    private var flipped = false

    init(inner: MemoryObjectStore, root: URL) {
        self.inner = inner
        self.root = root
    }

    func list(prefix: String) async throws -> [ObjectHead] { try await inner.list(prefix: prefix) }

    func get(_ key: String) async throws -> ObjectGet { try await inner.get(key) }

    func put(_ key: String, body: Data, contentType: String, ifMatch: String?, ifNoneMatch: String?) async throws -> String {
        let etag = try await inner.put(key, body: body, contentType: contentType, ifMatch: ifMatch, ifNoneMatch: ifNoneMatch)
        if key == "items/b/original.jpg", !flipped {
            flipped = true
            try Data("edited-during-copy".utf8).write(to: root.appendingPathComponent("items/a/original.jpg"))
        }
        return etag
    }

    func delete(_ key: String) async throws { try await inner.delete(key) }
}
