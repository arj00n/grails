import Foundation
import Testing
@testable import GrailsKit

@Suite struct NoteTests {
    @Test func notesAreSeparateFilesAndStaySearchable() async throws {
        let (store, root) = try TestSupport.newStore(handle: "ana")
        let item = try await store.addItem(fileAt: TestSupport.makePNG(in: TestSupport.tempDir(), name: "poster"), name: "Poster").item
        let first = try await store.addNote(text: "try the red @ben", itemId: item.id, people: ["ben"])
        let second = try await store.addNote(text: "and the type", itemId: item.id, people: ["ben"])
        #expect(first.mentions == ["ben"])
        #expect(second.mentions.isEmpty)
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("notes/\(first.id).json").path))
        let thread = LibraryNotes.thread(item: try #require(try await store.item(id: item.id)), in: store.layout)
        #expect(thread.map(\.id) == [first.id, second.id])

        let found = try await store.index.query(ItemQuery(text: "red"))
        #expect(found.map(\.id) == [item.id])
        #expect(found.first?.noted == true)

        try await store.deleteNote(first.id)
        #expect(try await store.index.query(ItemQuery(text: "red")).isEmpty)
        #expect(try await store.index.query(ItemQuery(text: "type")).map(\.id) == [item.id])
        #expect(LibraryNotes.read(first.id, in: store.layout)?.deletedAt != nil)

        let undone = try await store.apply(ChangeSet(label: "Remove Note", notes: [first.id: first]))
        #expect(LibraryNotes.read(first.id, in: store.layout)?.deletedAt == nil)
        _ = try await store.apply(undone)
        #expect(LibraryNotes.read(first.id, in: store.layout)?.deletedAt != nil)
    }

    @Test func theOldNoteStaysTheFirstLine() async throws {
        let (store, _) = try TestSupport.newStore(handle: "ana")
        let item = try await store.addItem(fileAt: TestSupport.makePNG(in: TestSupport.tempDir(), name: "old"), name: "Old").item
        try await store.setNote("kept for older copies", ids: [item.id])
        let loaded = try #require(try await store.item(id: item.id))
        #expect(loaded.note == "kept for older copies")
        let thread = LibraryNotes.thread(item: loaded, in: store.layout)
        #expect(thread.count == 1 && thread[0].isLegacy && thread[0].text == "kept for older copies")
        #expect(try await store.index.query(ItemQuery(text: "older")).map(\.id) == [item.id])
    }

    @Test func aClusterNoteDoesNotRewriteTheCanvas() async throws {
        let (store, root) = try TestSupport.newStore(handle: "ana")
        let note = try await store.addNote(text: "move this up @ana", board: "library", clusterId: "cluster-1", people: ["ana"])
        #expect(note.mentions == ["ana"])
        #expect(LibraryNotes.thread(board: "library", cluster: "cluster-1", in: store.layout).map(\.id) == [note.id])
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("canvas/library.json").path))
        #expect(LibraryNotes.itemIds(mentioning: "ana", in: store.layout).isEmpty)
    }

    @Test func aTranscriptSitsUnderAVoiceNote() async throws {
        let (store, root) = try TestSupport.newStore(handle: "ana")
        let item = try await store.addItem(fileAt: TestSupport.makePNG(in: TestSupport.tempDir(), name: "clip"), name: "Clip").item
        let voice = root.appendingPathComponent("clip.m4a")
        try Data([0]).write(to: voice)
        let note = try await store.addNote(text: "caption", itemId: item.id, voiceFrom: voice, seconds: 2, people: ["ben"])
        let before = try #require(LibraryNotes.read(note.id, in: store.layout))
        try await store.fillTranscript(note.id, text: "the red one @ben", people: ["ben"])
        let saved = try #require(LibraryNotes.read(note.id, in: store.layout))
        #expect(saved.text == "caption\nthe red one @ben")
        #expect(saved.mentions == ["ben"])
        #expect(saved.voice && saved.at == before.at)
        #expect(try await store.index.query(ItemQuery(text: "red")).map(\.id) == [item.id])
        try await store.fillTranscript(note.id, text: "the red one @ben", people: ["ben"])
        #expect(LibraryNotes.read(note.id, in: store.layout)?.text == "caption\nthe red one @ben")
    }

    @Test func aRenamedDisplayNameShowsOnCommentsAndMentions() async throws {
        let (store, root) = try TestSupport.newStore(handle: "Ada Lovelace")
        let item = try await store.addItem(fileAt: TestSupport.makePNG(in: TestSupport.tempDir(), name: "poster"), name: "Poster").item
        let note = try await store.addNote(text: "see @ada-lovelace", itemId: item.id, people: ["Ada Lovelace"])
        #expect(note.author == "Ada Lovelace")
        #expect(note.mentions == ["ada-lovelace"])
        let members = root.appendingPathComponent(".members", isDirectory: true)
        try FileManager.default.createDirectory(at: members, withIntermediateDirectories: true)
        let device: [String: String] = [
            "deviceName": "Mac", "email": "ada@studio.com", "inviteId": "inv", "name": "Ada Lovelace", "publicKey": "pk",
        ]
        let deviceURL = members.appendingPathComponent("ada@studio.com.json")
        try JSONSerialization.data(withJSONObject: device, options: [.sortedKeys]).write(to: deviceURL)
        #expect(Members.displayName(for: "Ada Lovelace", in: store.layout) == "Ada Lovelace")
        #expect(Members.displayName(for: "ada-lovelace", in: store.layout) == "Ada Lovelace")
        try Members.adopt(name: "Ada Chen", previous: "Ada Lovelace", email: "ada@studio.com", in: store.layout)
        let profile = try #require(Members.profile(matching: "Ada Chen", in: store.layout))
        #expect(profile.id == "pk")
        #expect(profile.previousHandles.contains("ada-lovelace"))
        #expect(FileManager.default.fileExists(atPath: members.appendingPathComponent("pk.json").path))
        #expect(!FileManager.default.fileExists(atPath: members.appendingPathComponent("ada-chen.json").path))
        #expect(!FileManager.default.fileExists(atPath: members.appendingPathComponent("ada-lovelace.json").path))
        let updated = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: deviceURL)) as? [String: String])
        #expect(updated["name"] == "Ada Chen")
        #expect(updated["publicKey"] == "pk")
        #expect(updated["memberId"] == "pk")
        #expect(updated["email"] == "ada@studio.com")
        let saved = try #require(LibraryNotes.read(note.id, in: store.layout))
        #expect(saved.author == "Ada Lovelace")
        #expect(saved.mentions == ["ada-lovelace"])
        #expect(saved.text == "see @ada-lovelace")
        #expect(Members.displayName(for: saved.author, in: store.layout) == "Ada Chen")
        #expect(Members.displayName(for: "ada-lovelace", in: store.layout) == "Ada Chen")
        #expect(Members.displayName(for: "pk", in: store.layout) == "Ada Chen")
        await store.setUserHandle("Ada Chen")
        #expect(await store.knownHandles().contains("ada-chen"))
    }

    @Test func anUnknownAtIsNotAMention() {
        #expect(LibraryNotes.mentions(in: "ask @ben and @stranger", people: ["Ben"]) == ["ben"])
    }
}
