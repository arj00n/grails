import Foundation
import Testing
@testable import GrailsKit

/// A member's Mac must never take the owner's profile. 0.3.11 did, and a member's rename then renamed the owner on that Mac.
@Suite struct MemberBindingTests {
    let ownerKey = "OwnerKey_abc123XYZ"
    let memberKey = "MemberKey_def456UVW"
    let early = Date(timeIntervalSince1970: 1_700_000_000)

    private func teamLibrary() throws -> LibraryLayout {
        let (store, root) = try TestSupport.newStore(handle: "ada")
        let members = root.appendingPathComponent(".members", isDirectory: true)
        try FileManager.default.createDirectory(at: members, withIntermediateDirectories: true)
        try AtomicFile.writeJSON(MemberRecord(handle: "ada", firstSeen: early, lastSeen: early, name: "Ada", id: ownerKey), to: members.appendingPathComponent(ownerKey + ".json"))
        let device: [String: Any] = ["email": "cleo@studio.test", "publicKey": memberKey, "deviceName": "Cleo's Mac", "inviteId": "inv1", "name": "Cleo", "memberId": memberKey]
        try JSONSerialization.data(withJSONObject: device, options: [.sortedKeys]).write(to: members.appendingPathComponent("cleo@studio.test.json"))

        let canonical = #"{"generation":2,"ownerEmail":"ada@studio.test","ownerPublicKey":"\#(ownerKey)","members":[{"email":"ada@studio.test","role":"owner"},{"email":"cleo@studio.test","role":"member"}]}"#
        let manifestURL = store.layout.manifestURL
        var manifest = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: manifestURL)) as? [String: Any])
        manifest["team"] = ["canonical": canonical, "signature": "sig", "signerPublicKey": ownerKey]
        try JSONSerialization.data(withJSONObject: manifest, options: [.sortedKeys]).write(to: manifestURL)
        return store.layout
    }

    @Test func aNewMemberDoesNotBindToTheOwner() throws {
        let layout = try teamLibrary()
        #expect(Members.ownProfile(handle: "Cleo", email: "cleo@studio.test", devicePublicKey: memberKey, in: layout) == nil)
        #expect(Members.ownProfile(handle: "Ada", email: "cleo@studio.test", devicePublicKey: memberKey, in: layout) == nil)
        #expect(Members.ownProfile(handle: "Cleo", email: nil, devicePublicKey: memberKey, in: layout) == nil)
    }

    @Test func theOwnerStillBindsToTheirProfile() throws {
        let layout = try teamLibrary()
        #expect(Members.ownProfile(handle: "anything", email: nil, devicePublicKey: ownerKey, in: layout)?.id == ownerKey)
        #expect(Members.ownProfile(handle: "anything", email: "ada@studio.test", devicePublicKey: nil, in: layout)?.id == ownerKey)
    }

    @Test func aMemberRenameLeavesTheOwnerAlone() throws {
        let layout = try teamLibrary()
        let mine = Members.ownProfile(handle: "Cleo", email: "cleo@studio.test", devicePublicKey: memberKey, in: layout)
        let kept = try Members.adopt(name: "blah", previous: "Cleo", email: "cleo@studio.test", memberId: mine?.id, in: layout)
        #expect(kept == memberKey)
        #expect(Members.displayName(for: ownerKey, in: layout) == "Ada")
        #expect(Members.displayName(for: memberKey, in: layout) == "blah")
        #expect(Members.ownProfile(handle: "blah", email: "cleo@studio.test", devicePublicKey: memberKey, in: layout)?.id == memberKey)
    }

    @Test func aRenameStampsOnlyThisPersonsDeviceFile() throws {
        let layout = try teamLibrary()
        let members = Members.folder(layout)
        let other: [String: Any] = ["email": "dan@studio.test", "publicKey": "DanKey", "deviceName": "Dan's Mac", "inviteId": "inv2", "name": "Cleo", "memberId": "DanKey"]
        try JSONSerialization.data(withJSONObject: other, options: [.sortedKeys]).write(to: members.appendingPathComponent("dan@studio.test.json"))
        try Members.adopt(name: "blah", previous: "Cleo", email: "cleo@studio.test", memberId: memberKey, in: layout)
        let dan = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: members.appendingPathComponent("dan@studio.test.json"))) as? [String: Any])
        #expect(dan["name"] as? String == "Cleo")
        #expect(dan["memberId"] as? String == "DanKey")
    }

    /// What 0.3.11 left on a member's Mac after a rename: the owner's profile renamed and the owner's id on the member's device file.
    @Test func aBorrowedOwnerIsReleased() throws {
        let layout = try teamLibrary()
        let members = Members.folder(layout)
        try Members.adopt(name: "blah", previous: "Ada", email: "cleo@studio.test", memberId: ownerKey, in: layout)
        let deviceURL = members.appendingPathComponent("cleo@studio.test.json")
        var device = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: deviceURL)) as? [String: Any])
        device["memberId"] = ownerKey
        try JSONSerialization.data(withJSONObject: device, options: [.sortedKeys]).write(to: deviceURL)

        let name = Members.releaseBorrowedOwner(handle: "blah", email: "cleo@studio.test", devicePublicKey: memberKey, in: layout)
        #expect(name == "blah")
        let repaired = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: deviceURL)) as? [String: Any])
        #expect(repaired["memberId"] as? String == memberKey)
        #expect(!FileManager.default.fileExists(atPath: members.appendingPathComponent(ownerKey + ".json").path))
        #expect(Members.ownProfile(handle: "blah", email: "cleo@studio.test", devicePublicKey: memberKey, in: layout) == nil)
        #expect(Members.releaseBorrowedOwner(handle: "blah", email: "cleo@studio.test", devicePublicKey: memberKey, in: layout) == nil)
    }

    /// A member who never renamed was only shown the owner's name. Their own name comes back from their device file.
    @Test func aBorrowedNameIsGivenBack() throws {
        let layout = try teamLibrary()
        #expect(Members.releaseBorrowedOwner(handle: "Ada", email: nil, devicePublicKey: memberKey, in: layout) == "Cleo")
        #expect(FileManager.default.fileExists(atPath: Members.folder(layout).appendingPathComponent(ownerKey + ".json").path))
        #expect(Members.releaseBorrowedOwner(handle: "Ada", email: nil, devicePublicKey: ownerKey, in: layout) == nil)
    }
}
