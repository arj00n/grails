import Foundation
import Testing
@testable import GrailsKit

@Suite struct Hotfix037KitTests {
    @Test func aRenameMatchesTheMemberIdAndRefusesATeammatesName() throws {
        let (store, root) = try TestSupport.newStore()
        let members = root.appendingPathComponent(".members", isDirectory: true)
        try FileManager.default.createDirectory(at: members, withIntermediateDirectories: true)
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        try AtomicFile.writeJSON(MemberRecord(handle: "ada", firstSeen: now, lastSeen: now, name: "Ada", id: "id-ada"), to: members.appendingPathComponent("id-ada.json"))
        try AtomicFile.writeJSON(MemberRecord(handle: "cleo", firstSeen: now, lastSeen: now, name: "Cleo", id: "id-cleo"), to: members.appendingPathComponent("id-cleo.json"))
        #expect(throws: MemberNameError.taken) {
            try Members.adopt(name: "Cleo", previous: "Ada", memberId: "id-ada", in: store.layout)
        }
        let cleo = try #require(Members.profile(matching: "id-cleo", in: store.layout))
        #expect(cleo.name == "Cleo")
        #expect(FileManager.default.fileExists(atPath: members.appendingPathComponent("id-cleo.json").path))
        let kept = try Members.adopt(name: "Ada Chen", previous: "Ada", memberId: "id-ada", in: store.layout)
        #expect(kept == "id-ada")
        #expect(Members.profile(matching: "id-ada", in: store.layout)?.name == "Ada Chen")
        #expect(Members.profile(matching: "id-cleo", in: store.layout)?.id == "id-cleo")
    }

    @Test func theSamePersonGetsTheSameIdOnEveryMacAndTheBackupKeepsItemFiles() async throws {
        let first = MemberIdentity.deterministic(ownerKey: "owner-key", email: "Ada@Studio.com", handle: "ada")
        let again = MemberIdentity.deterministic(ownerKey: "owner-key", email: "ada@studio.com", handle: "someone-else")
        let byHandle = MemberIdentity.deterministic(ownerKey: "owner-key", email: nil, handle: "Ada")
        #expect(first == again)
        #expect(first != byHandle)

        let (store, root) = try TestSupport.newStore()
        let members = root.appendingPathComponent(".members", isDirectory: true)
        try FileManager.default.createDirectory(at: members, withIntermediateDirectories: true)
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        try AtomicFile.writeJSON(MemberRecord(handle: "cleo", firstSeen: now, lastSeen: now, name: "Cleo", id: ""), to: members.appendingPathComponent("cleo.json"))
        let item = TestSupport.item("Lamp", addedAt: now, addedBy: "cleo")
        try await TestSupport.seed(store, [item])
        let backupRoot = TestSupport.tempDir("identity-backup")
        let migrated = try await store.migrateIdentity(backupRoot: backupRoot)
        let backup = try #require(migrated.backup)
        #expect(FileManager.default.fileExists(atPath: backup + "/items/\(item.id)/item.json"))
        let backed = try Data(contentsOf: URL(fileURLWithPath: backup + "/items/\(item.id)/item.json"))
        #expect(String(decoding: backed, as: UTF8.self).contains("cleo"))
        let expected = MemberIdentity.deterministic(ownerKey: nil, email: nil, handle: "cleo")
        let profile = try #require(Members.profile(matching: expected, in: store.layout))
        #expect(profile.id == expected)
        #expect(profile.id == MemberIdentity.deterministic(ownerKey: nil, email: nil, handle: "cleo"))
        let rewritten = try #require(try await store.item(id: item.id))
        #expect(rewritten.addedBy == expected)
    }
}
