import Foundation
import Testing
@testable import GrailsKit

@Suite struct IdentityTests {
    /// One person, two handles, and an owner key: the key becomes the member id, old handles stay aliases, and a later rename does not touch items.
    @Test func oldHandlesResolveToOneMemberAndARenameKeepsTheCounts() async throws {
        let ownerKey = "OwnerKey_abc123XYZ"
        let (store, root) = try TestSupport.newStore(handle: "ada")
        let early = Date(timeIntervalSince1970: 1_700_000_000)
        let later = early.addingTimeInterval(86_400)
        let members = root.appendingPathComponent(".members", isDirectory: true)
        try FileManager.default.createDirectory(at: members, withIntermediateDirectories: true)
        try AtomicFile.writeJSON(MemberRecord(handle: "ada", firstSeen: early, lastSeen: early), to: members.appendingPathComponent("ada.json"))
        try AtomicFile.writeJSON(MemberRecord(handle: "lovelace", firstSeen: early, lastSeen: later, name: "lovelace"), to: members.appendingPathComponent("lovelace.json"))
        try Data("photo".utf8).write(to: members.appendingPathComponent("lovelace.avatar.jpg"))

        let canonical = #"{"generation":4,"ownerEmail":"owner@studio.test","ownerPublicKey":"\#(ownerKey)","members":[{"email":"owner@studio.test","role":"owner"}]}"#
        let manifestURL = store.layout.manifestURL
        var manifest = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: manifestURL)) as? [String: Any])
        manifest["team"] = ["canonical": canonical, "signature": "sig", "signerPublicKey": ownerKey]
        let signed = try JSONSerialization.data(withJSONObject: manifest, options: [.sortedKeys])
        try signed.write(to: manifestURL)

        let kept = TestSupport.item("Kept", addedAt: early, addedBy: "ada")
        let recent = TestSupport.item("Recent", addedAt: later, addedBy: "lovelace")
        var trashed = TestSupport.item("Trashed", addedAt: early, addedBy: "ada")
        trashed.deletedAt = later
        let guest = TestSupport.item("Guest", addedAt: early, addedBy: "cleo")
        try await TestSupport.seed(store, [kept, recent, trashed, guest])

        try AtomicFile.writeJSON(GrailsCollection(name: "Refs", updatedAt: early, updatedBy: "ada"), to: store.layout.collectionsDir.appendingPathComponent("col.json"))
        try AtomicFile.writeJSON(CanvasBoard(key: "library", updatedAt: early, updatedBy: "lovelace"), to: store.layout.canvasDir.appendingPathComponent("library.json"))
        try AtomicFile.writeJSON(SmartFolder(name: "Videos", updatedAt: early, updatedBy: "ada"), to: store.layout.smartDir.appendingPathComponent("smart.json"))
        let invites = root.appendingPathComponent("invites", isDirectory: true)
        try FileManager.default.createDirectory(at: invites, withIntermediateDirectories: true)
        let invite = ["adminName": "lovelace", "email": "guest@studio.test", "id": "inv1"]
        try JSONSerialization.data(withJSONObject: invite, options: [.sortedKeys]).write(to: invites.appendingPathComponent("inv1.json"))

        let note = try await store.addNote(text: "see @ada", itemId: kept.id, people: ["ada"])
        let backupRoot = TestSupport.tempDir("identity-backup")
        let migrated = try await store.migrateIdentity(backupRoot: backupRoot)

        #expect(migrated.profiles == 1)
        #expect(migrated.items == 3)
        #expect(migrated.notes == 1)
        #expect(migrated.collections == 1)
        #expect(migrated.canvases == 1)
        #expect(migrated.smartFolders == 1)
        #expect(migrated.invites == 1)
        let backup = try #require(migrated.backup)
        #expect(FileManager.default.fileExists(atPath: backup + "/library.json"))
        #expect(FileManager.default.fileExists(atPath: backup + "/members/ada.json"))
        #expect(FileManager.default.fileExists(atPath: backup + "/members/lovelace.json"))
        #expect(try Data(contentsOf: manifestURL) == signed)

        let profile = try #require(Members.profile(matching: ownerKey, in: store.layout))
        #expect(profile.id == ownerKey)
        #expect(profile.name == "lovelace")
        #expect(profile.previousHandles.contains("ada"))
        #expect(profile.previousHandles.contains("lovelace"))
        #expect(FileManager.default.fileExists(atPath: members.appendingPathComponent(ownerKey + ".json").path))
        #expect(!FileManager.default.fileExists(atPath: members.appendingPathComponent("ada.json").path))
        #expect(!FileManager.default.fileExists(atPath: members.appendingPathComponent("lovelace.json").path))
        #expect(try Data(contentsOf: members.appendingPathComponent(ownerKey + ".avatar.jpg")) == Data("photo".utf8))
        #expect(!FileManager.default.fileExists(atPath: members.appendingPathComponent("lovelace.avatar.jpg").path))

        for id in [kept.id, recent.id, trashed.id] {
            let item = try #require(try await store.item(id: id))
            #expect(item.addedBy == ownerKey)
            #expect(item.updatedBy == ownerKey)
        }
        #expect(try await store.item(id: guest.id)?.addedBy == "cleo")
        let saved = try #require(LibraryNotes.read(note.id, in: store.layout))
        #expect(saved.author == ownerKey)
        #expect(saved.mentions == [ownerKey])
        #expect(saved.text == "see @ada")
        #expect(Members.displayName(for: "ada", in: store.layout) == "lovelace")
        #expect(Members.displayName(for: "lovelace", in: store.layout) == "lovelace")
        #expect(Members.displayName(for: ownerKey, in: store.layout) == "lovelace")

        let people = try await store.index.addedByCounts()

        let again = try await store.migrateIdentity(backupRoot: backupRoot)
        #expect(!again.changed)
        #expect(again.backup == nil)

        let itemURL = store.layout.itemJSON(kept.id)
        let beforeRename = try Data(contentsOf: itemURL)
        let noteBefore = try Data(contentsOf: store.layout.noteURL(note.id))
        try Members.adopt(name: "Ada Lovelace", previous: "lovelace", memberId: ownerKey, in: store.layout)
        #expect(try Data(contentsOf: itemURL) == beforeRename)
        #expect(try Data(contentsOf: store.layout.noteURL(note.id)) == noteBefore)
        let renamed = try #require(Members.profile(matching: "ada", in: store.layout))
        #expect(renamed.id == ownerKey)
        #expect(renamed.name == "Ada Lovelace")
        #expect(Members.displayName(for: "lovelace", in: store.layout) == "Ada Lovelace")
        #expect(Members.displayName(for: ownerKey, in: store.layout) == "Ada Lovelace")
        let after = try await store.index.addedByCounts()
        #expect(after.map(\.who) == people.map(\.who))
        #expect(after.map(\.count) == people.map(\.count))
    }
}
