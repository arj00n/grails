import Foundation
import XCTest
import GrailsSync

final class TeamTests: XCTestCase {
    func testStampPutsTheOwnerDeviceKeyOnTheOwnerRow() throws {
        let owner = DeviceKey()
        let body = TeamBody(generation: 5, ownerEmail: "ada@example.com", ownerPublicKey: owner.publicKey, members: [
            TeamMember(email: "ada@example.com", role: .owner),
            TeamMember(email: "bea@example.com", role: .member, publicKey: "bea-key"),
        ])
        let stamped = TeamKeys.stamp(body, devices: ["bea@example.com": "bea-key"])
        XCTAssertEqual(stamped.members.first { $0.role == .owner }?.publicKey, owner.publicKey)
        XCTAssertEqual(stamped.members.first { $0.role == .member }?.publicKey, "bea-key")
        let signed = try TeamDocument.sign(stamped, key: owner)
        XCTAssertEqual(TeamDocument.parse(signed.canonical)?.members.first { $0.role == .owner }?.publicKey, owner.publicKey)
        XCTAssertTrue(DeviceKey.verify(signature: signed.signature, publicKey: owner.publicKey, data: Data(signed.canonical.utf8)))

        let untouched = TeamBody(generation: 5, ownerEmail: "ada@example.com", ownerPublicKey: owner.publicKey, members: [
            TeamMember(email: "ada@example.com", role: .owner),
            TeamMember(email: "bea@example.com", role: .member),
        ])
        let previous = try TeamDocument.sign(untouched, key: owner)
        XCTAssertFalse(previous.canonical.contains("\"publicKey\""))
        let trusted = TeamDirectory.accept(signed: previous, trusted: nil, devices: [:])
        XCTAssertEqual(trusted?.body.generation, 5)
        XCTAssertNil(trusted?.body.members.first { $0.role == .owner }?.publicKey)
    }

    func testCanonicalRoundTrip() throws {
        let body = TeamBody(
            generation: 1,
            ownerEmail: "Arjun@Studio.com",
            ownerPublicKey: "pub",
            members: [TeamMember(email: "Arjun@Studio.com", role: .owner)]
        )
        let canonical = try TeamDocument.canonical(body)
        XCTAssertEqual(
            canonical,
            #"{"adminsMayDemoteAdmins":false,"capGB":9,"formatVersion":1,"generation":1,"maxFileMB":200,"members":[{"email":"arjun@studio.com","role":"owner"}],"minAppVersion":"0.3.5","ownerEmail":"arjun@studio.com","ownerPublicKey":"pub","uploadMBPerMinute":500}"#
        )
        let parsed = TeamDocument.parse(canonical)
        XCTAssertEqual(parsed?.ownerEmail, "arjun@studio.com")
        XCTAssertEqual(parsed?.capGB, 9)
        XCTAssertEqual(parsed?.maxFileMB, 200)
        XCTAssertEqual(parsed?.formatVersion, 1)
        XCTAssertEqual(parsed?.minAppVersion, "0.3.5")
        XCTAssertTrue(TeamDocument.valid(parsed!))
    }

    func testUnsignedRoleChangeIsIgnored() throws {
        let (owner, signed) = try TestLibrary.owner()
        let trusted = TeamDirectory.accept(signed: signed, trusted: nil, devices: [:])
        XCTAssertEqual(trusted?.body.role(of: owner.publicKey), nil)
        var tampered = signed
        tampered.canonical = tampered.canonical.replacingOccurrences(of: "\"role\":\"owner\"", with: "\"role\":\"member\"")
        XCTAssertNil(TeamDirectory.accept(signed: tampered, trusted: trusted, devices: [:]))
        XCTAssertEqual(trusted?.body.members.first?.role, .owner)
    }

    func testMemberCannotGrantThemselvesAdmin() throws {
        let owner = DeviceKey()
        let member = DeviceKey()
        let start = TeamBody(generation: 1, ownerEmail: "o@studio.com", ownerPublicKey: owner.publicKey, members: [
            TeamMember(email: "o@studio.com", role: .owner),
            TeamMember(email: "m@studio.com", role: .member),
        ])
        let trusted = TeamDirectory.accept(signed: try TeamDocument.sign(start, key: owner), trusted: nil, devices: [:])
        var promoted = start
        promoted.generation = 2
        promoted.members = [
            TeamMember(email: "o@studio.com", role: .owner),
            TeamMember(email: "m@studio.com", role: .admin),
        ]
        let signed = try TeamDocument.sign(promoted, key: member)
        XCTAssertNil(TeamDirectory.accept(signed: signed, trusted: trusted, devices: ["m@studio.com": member.publicKey]))
    }

    func testAdminCannotDemoteAnotherAdminUnlessAllowed() throws {
        let owner = DeviceKey()
        let admin = DeviceKey()
        let other = DeviceKey()
        let start = TeamBody(generation: 1, ownerEmail: "o@studio.com", ownerPublicKey: owner.publicKey, members: [
            TeamMember(email: "o@studio.com", role: .owner),
            TeamMember(email: "a@studio.com", role: .admin),
            TeamMember(email: "b@studio.com", role: .admin),
        ])
        let trusted = TeamDirectory.accept(signed: try TeamDocument.sign(start, key: owner), trusted: nil, devices: [:])
        var demoted = start
        demoted.generation = 2
        demoted.members = [
            TeamMember(email: "o@studio.com", role: .owner),
            TeamMember(email: "a@studio.com", role: .admin),
            TeamMember(email: "b@studio.com", role: .member),
        ]
        let devices = ["a@studio.com": admin.publicKey, "b@studio.com": other.publicKey]
        XCTAssertNil(TeamDirectory.accept(signed: try TeamDocument.sign(demoted, key: admin), trusted: trusted, devices: devices))
        var allowed = start
        allowed.adminsMayDemoteAdmins = true
        allowed.generation = 2
        let opened = TeamDirectory.accept(signed: try TeamDocument.sign(allowed, key: owner), trusted: trusted, devices: devices)
        var after = demoted
        after.adminsMayDemoteAdmins = true
        after.generation = 3
        let accepted = TeamDirectory.accept(signed: try TeamDocument.sign(after, key: admin), trusted: opened, devices: devices)
        XCTAssertEqual(accepted?.body.role(of: "b@studio.com"), .member)
    }

    func testAdminCannotRemoveTheOwner() throws {
        let owner = DeviceKey()
        let admin = DeviceKey()
        let start = TeamBody(generation: 1, ownerEmail: "o@studio.com", ownerPublicKey: owner.publicKey, members: [
            TeamMember(email: "o@studio.com", role: .owner),
            TeamMember(email: "a@studio.com", role: .admin),
        ])
        let trusted = TeamDirectory.accept(signed: try TeamDocument.sign(start, key: owner), trusted: nil, devices: [:])
        var stripped = start
        stripped.generation = 2
        stripped.members = [TeamMember(email: "a@studio.com", role: .owner)]
        stripped.ownerEmail = "a@studio.com"
        stripped.ownerPublicKey = admin.publicKey
        XCTAssertNil(TeamDirectory.accept(signed: try TeamDocument.sign(stripped, key: admin), trusted: trusted, devices: ["a@studio.com": admin.publicKey]))
        XCTAssertFalse(TeamPermissions.canRemove(.admin, target: .owner, adminsMayDemoteAdmins: true))
        XCTAssertFalse(TeamPermissions.canDeleteLibrary(.admin))
        XCTAssertTrue(TeamPermissions.canDeleteLibrary(.owner))
    }

    func testOwnerTransferRequiresTheNewDevice() throws {
        let owner = DeviceKey()
        let next = DeviceKey()
        let start = TeamBody(generation: 1, ownerEmail: "o@studio.com", ownerPublicKey: owner.publicKey, members: [
            TeamMember(email: "o@studio.com", role: .owner),
            TeamMember(email: "n@studio.com", role: .admin),
        ])
        let trusted = TeamDirectory.accept(signed: try TeamDocument.sign(start, key: owner), trusted: nil, devices: [:])
        var moved = start
        moved.generation = 2
        moved.ownerEmail = "n@studio.com"
        moved.ownerPublicKey = next.publicKey
        moved.members = [
            TeamMember(email: "o@studio.com", role: .admin),
            TeamMember(email: "n@studio.com", role: .owner),
        ]
        XCTAssertNil(TeamDirectory.accept(signed: try TeamDocument.sign(moved, key: owner), trusted: trusted, devices: [:]))
        let accepted = TeamDirectory.accept(signed: try TeamDocument.sign(moved, key: owner), trusted: trusted, devices: ["n@studio.com": next.publicKey])
        XCTAssertEqual(accepted?.body.ownerEmail, "n@studio.com")
        XCTAssertEqual(accepted?.pinnedOwnerKey, next.publicKey)
    }

    func testReplayIsRejectedAndTheOwnerCanCatchUp() throws {
        let (owner, signed) = try TestLibrary.owner()
        let trusted = TeamDirectory.accept(signed: signed, trusted: nil, devices: [:])
        XCTAssertNil(TeamDirectory.accept(signed: signed, trusted: trusted, devices: [:]))
        var jumped = TeamDocument.parse(signed.canonical)!
        jumped.generation = 3
        jumped.capGB = 12
        let caughtUp = TeamDirectory.accept(signed: try TeamDocument.sign(jumped, key: owner), trusted: trusted, devices: [:])
        XCTAssertEqual(caughtUp?.body.generation, 3)
        XCTAssertEqual(caughtUp?.body.capGB, 12)
        XCTAssertNil(TeamDirectory.accept(signed: signed, trusted: caughtUp, devices: [:]))
    }

    func testAdminCannotChangeTheFormatGate() throws {
        let owner = DeviceKey()
        let admin = DeviceKey()
        let start = TeamBody(generation: 1, ownerEmail: "o@studio.com", ownerPublicKey: owner.publicKey, members: [
            TeamMember(email: "o@studio.com", role: .owner),
            TeamMember(email: "a@studio.com", role: .admin),
        ])
        let trusted = TeamDirectory.accept(signed: try TeamDocument.sign(start, key: owner), trusted: nil, devices: [:])
        var raised = start
        raised.generation = 2
        raised.minAppVersion = "9.0.0"
        XCTAssertNil(TeamDirectory.accept(signed: try TeamDocument.sign(raised, key: admin), trusted: trusted, devices: ["a@studio.com": admin.publicKey]))
        let accepted = TeamDirectory.accept(signed: try TeamDocument.sign(raised, key: owner), trusted: trusted, devices: [:])
        XCTAssertEqual(accepted?.body.minAppVersion, "9.0.0")
        XCTAssertFalse(TeamPermissions.canEditFormatGate(.admin))
        XCTAssertTrue(TeamPermissions.canEditFormatGate(.owner))
        XCTAssertTrue(TeamPermissions.seesTeamControls(.admin))
        XCTAssertFalse(TeamPermissions.seesTeamControls(.member))
        XCTAssertTrue(TeamPermissions.canSetAvatar(actor: .member, isSelf: true))
        XCTAssertFalse(TeamPermissions.canSetAvatar(actor: .member, isSelf: false))
        XCTAssertTrue(TeamPermissions.canSetAvatar(actor: .admin, isSelf: false))
        XCTAssertTrue(TeamPermissions.canSetAvatar(actor: .owner, isSelf: false))
    }

    func testLibraryFilePublishesTheGate() throws {
        let (_, signed) = try TestLibrary.owner(minAppVersion: "0.3.5")
        let data = try TeamFile.write(signed, into: Data(#"{"name":"Studio"}"#.utf8))
        let object = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertEqual(object["formatVersion"] as? Int, 1)
        XCTAssertEqual(object["minAppVersion"] as? String, "0.3.5")
        XCTAssertNotNil(object["team"])
    }

    func testRemovingAMemberSignsTheRosterAndAFailurePutsThemBack() throws {
        let owner = DeviceKey()
        let start = TeamBody(generation: 2, ownerEmail: "o@studio.com", ownerPublicKey: owner.publicKey, members: [
            TeamMember(email: "o@studio.com", role: .owner),
            TeamMember(email: "cam@company.com", role: .member),
        ])
        let removed = TeamRoster.removing("cam@company.com", from: start.members)
        XCTAssertEqual(removed.map(\.email), ["o@studio.com"])
        XCTAssertEqual(TeamRoster.removing("o@studio.com", from: start.members).map(\.role), [.owner, .member])
        var next = start
        next.members = removed
        next.generation += 1
        let signed = try TeamDocument.sign(next, key: owner)
        let file = try TeamFile.write(signed, into: Data("{}".utf8))
        let read = try XCTUnwrap(TeamFile.ownerSigned(file))
        XCTAssertEqual(read.members.map(\.email), ["o@studio.com"])
        XCTAssertEqual(read.generation, 3)
        let failed = TeamRoster.restored(start.members, failed: true, next: removed)
        XCTAssertEqual(failed.map(\.email), ["o@studio.com", "cam@company.com"])
        XCTAssertFalse(DisplayName.canSave(draft: "  ", current: "Ada"))
        XCTAssertFalse(DisplayName.canSave(draft: "Ada", current: "Ada"))
        XCTAssertTrue(DisplayName.canSave(draft: " Ada Chen ", current: "Ada"))
    }
}
