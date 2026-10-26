import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import XCTest
@testable import GrailsSync
import GrailsEndpoints

/// The site these tests expect: `swift test` has no `GrailsSiteURL` key, so `GrailsEndpoints.site` is the official one.
private let site = GrailsEndpoints.officialSite.absoluteString

final class InviteTests: XCTestCase {
    private let secret = "SECRET-VALUE-do-not-leak-9f3a"
    private let code = "042817"

    func testIdOnlyLinkRoundTripsAndLeavesTheBlobLinkAlone() throws {
        let id = "abcdefghijkl"
        let url = URL(string: "grails://i/\(id)")!
        let parsed = try XCTUnwrap(JoinLink.parse(url))
        XCTAssertEqual(parsed.id, id)
        XCTAssertEqual(parsed.shortID, id)
        XCTAssertEqual(parsed.blob, "")
        XCTAssertEqual(parsed.url.absoluteString, "grails://i/\(id)")
        XCTAssertEqual(InviteRelay.shortID(in: url), id)
        XCTAssertEqual(InviteRelay.shortID(in: "please open grails://i/\(id) thanks"), id)
        XCTAssertNil(JoinLink.parse(URL(string: "grails://i/short")!))
        XCTAssertNil(InviteRelay.shortID(in: URL(string: "grails://i/bad id")!))

        let issued = try issue()
        let blob = try XCTUnwrap(JoinLink.parse(issued.link.url))
        XCTAssertEqual(blob.id, issued.id)
        XCTAssertFalse(blob.blob.isEmpty)
        XCTAssertEqual(blob.url.host, "j")
        XCTAssertNotEqual(blob.url.absoluteString, parsed.url.absoluteString)
    }

    func testLaunchInviteWaitsForTheLibraryChoiceThenClosesOnboarding() {
        XCTAssertEqual(
            FirstRunInvite.disposition(onboardingVisible: false, libraryChoicePending: true, libraryOpen: false),
            .holdUntilLibraryChoice
        )
        XCTAssertEqual(
            FirstRunInvite.disposition(onboardingVisible: true, libraryChoicePending: false, libraryOpen: false),
            .start(closeOnboardingOnSuccess: true)
        )
        XCTAssertEqual(
            FirstRunInvite.disposition(onboardingVisible: true, libraryChoicePending: true, libraryOpen: false),
            .start(closeOnboardingOnSuccess: true)
        )
        XCTAssertEqual(
            FirstRunInvite.disposition(onboardingVisible: false, libraryChoicePending: false, libraryOpen: true),
            .start(closeOnboardingOnSuccess: false)
        )
    }

    func testLinkCarriesNoSecretOrCode() throws {
        let issued = try issue()
        let absolute = issued.link.url.absoluteString
        XCTAssertFalse(absolute.contains(secret))
        XCTAssertFalse(absolute.contains(code))
        XCTAssertEqual(issued.link.url.scheme, "grails")
        XCTAssertEqual(issued.link.url.host, "j")
        XCTAssertFalse(String(describing: issued).contains(secret))
        XCTAssertFalse(String(describing: issued).contains(code))
        XCTAssertFalse(String(describing: issued.payload).contains(secret))
        let page = GrailsEndpoints.officialSite.appendingPathComponent("open")
        let web = issued.link.webURL(page: page)
        XCTAssertNil(web.query)
        XCTAssertFalse(web.absoluteString.contains(secret))
        XCTAssertEqual(JoinLink.parse(web)?.id, issued.id)
        let message = BucketInviteMessage.make(library: "Studio", link: issued.link.url, from: "Arjun")
        XCTAssertFalse(message.body.contains(secret))
        XCTAssertFalse(message.body.contains(code))
        XCTAssertTrue(message.body.contains("xattr -d com.apple.quarantine /Applications/Grails.app"))
        XCTAssertTrue(message.body.contains("Always Allow"))
        XCTAssertEqual(BucketInviteMessage.quarantine, "xattr -d com.apple.quarantine /Applications/Grails.app")
        XCTAssertTrue(message.body.contains("The join code comes separately."))
        XCTAssertFalse(message.body.contains("open#lib"))
        XCTAssertFalse(message.body.contains("Shared drive"))
        XCTAssertTrue(message.body.contains("grails://j/"))
        XCTAssertFalse(message.body.contains("grails://join?"))
        XCTAssertEqual(JoinLink.find(in: message.body)?.id, issued.id)
        XCTAssertEqual(PastedLibraryLink.classify(message.body), .join)
        XCTAssertEqual(PastedLibraryLink.classify(web.absoluteString), .join)
        XCTAssertEqual(PastedLibraryLink.classify("\(site)/open#lib=01ABC&name=Studio"), .folder)
        XCTAssertEqual(PastedLibraryLink.classify("grails://open?lib=01ABC"), .folder)
        XCTAssertEqual(PastedLibraryLink.classify("hello"), .unknown)
        XCTAssertEqual(JoinLink.find(in: "please open \(web.absoluteString) thanks")?.id, issued.id)
        XCTAssertNil(JoinLink.find(in: code))
        let exp = Date(timeIntervalSince1970: issued.metadata.exp)
        let share = InviteShare.make(library: "Studio", link: issued.link.url, code: code, from: "Arjun", expires: exp, email: issued.metadata.email, role: .member)
        XCTAssertFalse(share.message.contains(code))
        XCTAssertFalse(share.message.contains(secret))
        XCTAssertTrue(share.message.contains(BucketInviteMessage.quarantine))
        XCTAssertEqual(BucketInviteMessage.site, site)
        XCTAssertTrue(share.message.contains("1. Install Grails: \(site)"))
        XCTAssertFalse(share.message.contains("open#lib"))
        XCTAssertEqual(share.code, code)
        XCTAssertEqual(InviteShare.expiry(exp, timeZone: TimeZone(secondsFromGMT: 0)!, now: exp.addingTimeInterval(-86_400)), "Expires tomorrow, 10:13 PM")
        XCTAssertTrue(InviteShare.channelNote.contains("different"))
    }

    func testExpiryReadsAsAShortDay() {
        let zone = TimeZone(secondsFromGMT: 0)!
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let anchor = calendar.date(from: DateComponents(timeZone: zone, year: 2026, month: 10, day: 14, hour: 12))!
        let today = calendar.date(from: DateComponents(timeZone: zone, year: 2026, month: 10, day: 14, hour: 16, minute: 2))!
        let tomorrow = calendar.date(from: DateComponents(timeZone: zone, year: 2026, month: 10, day: 15, hour: 4, minute: 2))!
        let soon = calendar.date(from: DateComponents(timeZone: zone, year: 2026, month: 10, day: 16, hour: 4, minute: 2))!
        let later = calendar.date(from: DateComponents(timeZone: zone, year: 2023, month: 11, day: 15, hour: 22, minute: 13))!
        XCTAssertEqual(InviteShare.expiry(today, timeZone: zone, now: anchor), "Expires today, 4:02 PM")
        XCTAssertEqual(InviteShare.expiry(tomorrow, timeZone: zone, now: anchor), "Expires tomorrow, 4:02 AM")
        XCTAssertEqual(InviteShare.expiry(soon, timeZone: zone, now: anchor), "Expires Friday, 4:02 AM")
        XCTAssertEqual(InviteShare.expiry(later, timeZone: zone, now: anchor), "Expires 15 Nov, 10:13 PM")
    }

    func testInviteGateBlocksTheOwnerMembersAndDuplicates() {
        let members = ["m@studio.com", "o@studio.com"]
        let pending = ["p@studio.com"]
        XCTAssertEqual(InviteGate.block(email: "", actorEmail: "a@studio.com", ownerEmail: "o@studio.com", members: members, pending: pending), .invalid)
        XCTAssertNil(InviteGate.shown(.invalid, email: "  "))
        XCTAssertEqual(InviteGate.block(email: "nope", actorEmail: "a@studio.com", ownerEmail: "o@studio.com", members: members, pending: pending), .invalid)
        XCTAssertEqual(InviteGate.shown(.invalid, email: "nope"), "Check the email")
        XCTAssertEqual(InviteGate.block(email: "A@studio.com", actorEmail: "a@studio.com", ownerEmail: "o@studio.com", members: members, pending: pending), .yourself)
        XCTAssertEqual(InviteGate.block(email: "O@studio.com", actorEmail: "a@studio.com", ownerEmail: "o@studio.com", members: members, pending: pending), .owner)
        XCTAssertEqual(InviteGate.message(.owner), "That's the owner's email")
        XCTAssertEqual(InviteGate.block(email: "P@studio.com", actorEmail: "a@studio.com", ownerEmail: "o@studio.com", members: members, pending: pending), .pending)
        XCTAssertEqual(InviteGate.block(email: "M@studio.com", actorEmail: "a@studio.com", ownerEmail: "o@studio.com", members: members, pending: pending), .member)
        XCTAssertNil(InviteGate.block(email: "new@studio.com", actorEmail: "a@studio.com", ownerEmail: "o@studio.com", members: members, pending: pending))
    }

    func testOwnerRoleComesFromTheVerifiedTeam() throws {
        let owner = DeviceKey()
        let stranger = DeviceKey()
        var body = TeamBody(
            generation: 4,
            ownerEmail: "Ada@Example.com",
            ownerPublicKey: owner.publicKey,
            adminsMayDemoteAdmins: false,
            members: [TeamMember(email: "Ada@Example.com", role: .owner)]
        )
        XCTAssertEqual(body.role(of: "ada@example.com"), .owner)
        XCTAssertEqual(TeamIdentity.role(email: "other@example.com", devicePublicKey: owner.publicKey, team: body), .owner)
        XCTAssertEqual(TeamIdentity.role(email: "ada@example.com", devicePublicKey: stranger.publicKey, team: body), .owner)
        XCTAssertNil(TeamIdentity.role(email: "ada@studio.com", devicePublicKey: stranger.publicKey, team: body) as LibraryRole?)
        let signed = try TeamDocument.sign(body, key: owner)
        let trusted = try XCTUnwrap(TeamDirectory.accept(signed: signed, trusted: nil, devices: [:]))
        XCTAssertEqual(trusted.pinnedOwnerKey, owner.publicKey)
        XCTAssertEqual(trusted.body.generation, 4)
        XCTAssertNil(TeamDirectory.accept(signed: try TeamDocument.sign(body, key: stranger), trusted: nil, devices: [:]))
        let file = try TeamFile.write(signed, into: Data(#"{"id":"lib","name":"Studio"}"#.utf8))
        let verified = try XCTUnwrap(TeamFile.ownerSigned(file))
        XCTAssertFalse(verified.adminsMayDemoteAdmins)
        XCTAssertEqual(verified.role(of: "ada@example.com"), .owner)
        XCTAssertEqual(TeamIdentity.role(email: "not-the-form@example.com", devicePublicKey: owner.publicKey, team: verified), .owner)
        XCTAssertEqual(InviteRoles.choices, [.member, .admin])
        XCTAssertTrue(InviteRoles.allows(.admin, actor: .owner, adminsMayGrantAdmin: false))
        XCTAssertNil(InviteRoles.adminHelp(actor: .owner, adminsMayGrantAdmin: false))
        XCTAssertTrue(InviteRoles.allows(.member, actor: .admin, adminsMayGrantAdmin: false))
        XCTAssertFalse(InviteRoles.allows(.admin, actor: .admin, adminsMayGrantAdmin: false))
        XCTAssertEqual(InviteRoles.adminHelp(actor: .admin, adminsMayGrantAdmin: false), InviteRoles.adminLocked)
        var broken = signed
        // A 64-byte signature's last base64url character is padding. Flip the one before it, or A and B decode the same.
        var chars = Array(signed.signature)
        let index = max(0, chars.count - 2)
        chars[index] = chars[index] == "B" ? "A" : "B"
        broken.signature = String(chars)
        let tampered = try TeamFile.write(broken, into: Data(#"{"id":"lib"}"#.utf8))
        XCTAssertNil(TeamFile.ownerSigned(tampered))
        body.members = [TeamMember(email: "ada@studio.com", role: .admin)]
        let adminSigned = try TeamDocument.sign(body, key: stranger)
        XCTAssertNil(TeamFile.ownerSigned(try TeamFile.write(adminSigned, into: Data("{}".utf8))))
    }

    func testAdminCannotMintAnAdminUnlessAllowed() {
        XCTAssertEqual(TeamPermissions.invitableRoles(actor: .member, adminsMayGrantAdmin: true), [])
        XCTAssertEqual(TeamPermissions.invitableRoles(actor: .admin, adminsMayGrantAdmin: false), [.member])
        XCTAssertEqual(TeamPermissions.invitableRoles(actor: .admin, adminsMayGrantAdmin: true), [.member, .admin])
        XCTAssertEqual(TeamPermissions.invitableRoles(actor: .owner, adminsMayGrantAdmin: false), [.member, .admin])
        XCTAssertFalse(TeamPermissions.allows([.add(email: "n@studio.com", role: .admin)], actor: .admin, adminsMayDemoteAdmins: false))
        XCTAssertTrue(TeamPermissions.allows([.add(email: "n@studio.com", role: .admin)], actor: .admin, adminsMayDemoteAdmins: true))
        XCTAssertTrue(TeamPermissions.allows([.add(email: "n@studio.com", role: .member)], actor: .admin, adminsMayDemoteAdmins: false))
        XCTAssertFalse(TeamPermissions.allows([.add(email: "n@studio.com", role: .owner)], actor: .owner, adminsMayDemoteAdmins: true))
    }

    func testIssueGrantsTheRoleAndKeepsTheLink() throws {
        let issued = try issue(role: .admin)
        let body = TeamDocument.parse(issued.signedTeam.canonical)
        XCTAssertEqual(body?.role(of: "ada@studio.com"), .admin)
        XCTAssertEqual(issued.metadata.blob, issued.link.blob)
        let bucket = issued.metadata.forBucket()
        XCTAssertNil(bucket.blob)
        let bucketData = try JSONEncoder().encode(bucket)
        XCTAssertFalse(String(decoding: bucketData, as: UTF8.self).contains(issued.link.blob))
        let data = try JSONEncoder().encode(issued.metadata)
        let key = InviteMetadata.objectKey(issued.id)
        let listed = InviteList.parse(objects: [ObjectHead(key: key, etag: "e", size: Int64(data.count))], bodies: [key: data])
        XCTAssertEqual(listed.first?.state, .pending)
        XCTAssertEqual(listed.first?.blob, issued.link.blob)
        XCTAssertFalse(String(data: data, encoding: .utf8)?.contains(code) ?? true)
    }

    func testDoubleRedeemFailsAndKeepsTheFirstDevice() async throws {
        let issued = try issue()
        let store = MemoryObjectStore()
        let first = DeviceKey()
        var gate = JoinCodeGate()
        let redeemed = try await InviteRedeemer.redeem(link: issued.link, code: code, confirmedEmail: "Ada@Studio.com", device: first, deviceName: "Ada's Mac", gate: &gate, store: store, now: Date(timeIntervalSince1970: 1_700_000_000))
        XCTAssertEqual(redeemed.device.deviceName, "Ada's Mac")
        try await store.delete(DeviceRecord.key(email: issued.payload.email))
        var secondGate = JoinCodeGate()
        do {
            _ = try await InviteRedeemer.redeem(link: issued.link, code: code, confirmedEmail: issued.payload.email, device: DeviceKey(), deviceName: "Other Mac", gate: &secondGate, store: store, now: Date(timeIntervalSince1970: 1_700_000_100))
            XCTFail("second redeem")
        } catch RedeemError.alreadyRedeemed {}
        let marker = try await store.get(InviteMetadata.redeemedKey(issued.id))
        let record = try JSONDecoder().decode(DeviceRecord.self, from: marker.body)
        XCTAssertEqual(record.publicKey, first.publicKey)
        XCTAssertEqual(record.deviceName, "Ada's Mac")
        let puts = await store.recordedPuts().filter { $0.key == InviteMetadata.redeemedKey(issued.id) }
        XCTAssertEqual(puts.first?.ifNoneMatch, "*")
    }

    func testSameDeviceCanRetryAfterTheMarkerWins() async throws {
        let issued = try issue()
        let store = MemoryObjectStore()
        let device = DeviceKey()
        var gate = JoinCodeGate()
        _ = try await InviteRedeemer.redeem(link: issued.link, code: code, confirmedEmail: issued.payload.email, device: device, deviceName: "Ada's Mac", gate: &gate, store: store, now: Date(timeIntervalSince1970: 1_700_000_000))
        var retry = JoinCodeGate()
        let again = try await InviteRedeemer.redeem(link: issued.link, code: code, confirmedEmail: issued.payload.email, device: device, deviceName: "Ada's Mac", gate: &retry, store: store, now: Date(timeIntervalSince1970: 1_700_000_100))
        XCTAssertEqual(again.device.publicKey, device.publicKey)
    }

    func testExpiredInviteDoesNotRedeem() async throws {
        let issued = try issue()
        var payload = issued.payload
        payload.exp = 1_700_000_000
        let blob = try InviteBlob.seal(payload, code: code, iterations: InviteCrypto.acceptedIterations.lowerBound)
        let store = MemoryObjectStore()
        var gate = JoinCodeGate()
        do {
            _ = try await InviteRedeemer.redeem(link: JoinLink(id: issued.id, blob: blob), code: code, confirmedEmail: payload.email, device: DeviceKey(), deviceName: "Mac", gate: &gate, store: store, now: Date(timeIntervalSince1970: payload.exp + 1))
            XCTFail("expired")
        } catch RedeemError.expired {}
        XCTAssertEqual(gate.failures, 0)
        let counts = await store.counts()
        XCTAssertEqual(counts.puts, 0)
    }

    func testFiveWrongCodesLockTheInvite() async throws {
        let issued = try issue()
        let store = MemoryObjectStore()
        var gate = JoinCodeGate()
        for attempt in 1...5 {
            do {
                _ = try await InviteRedeemer.redeem(link: issued.link, code: "00000\(attempt)", confirmedEmail: issued.payload.email, device: DeviceKey(), deviceName: "Mac", gate: &gate, store: store, now: Date(timeIntervalSince1970: 1_700_000_000))
                XCTFail("wrong code")
            } catch let error as RedeemError {
                XCTAssertEqual(error, attempt == 5 ? .locked : .wrongCode)
            }
        }
        do {
            _ = try await InviteRedeemer.redeem(link: issued.link, code: code, confirmedEmail: issued.payload.email, device: DeviceKey(), deviceName: "Mac", gate: &gate, store: store, now: Date(timeIntervalSince1970: 1_700_000_000))
            XCTFail("locked code")
        } catch RedeemError.locked {}
        let counts = await store.counts()
        XCTAssertEqual(counts.puts, 0)
    }

    func testFourthFailureStillAllowsTheRightCode() async throws {
        let issued = try issue()
        let store = MemoryObjectStore()
        var gate = JoinCodeGate()
        for _ in 0..<4 {
            do {
                _ = try await InviteRedeemer.redeem(link: issued.link, code: "111111", confirmedEmail: issued.payload.email, device: DeviceKey(), deviceName: "Mac", gate: &gate, store: store, now: Date(timeIntervalSince1970: 1_700_000_000))
            } catch RedeemError.wrongCode {}
        }
        let device = DeviceKey()
        let redeemed = try await InviteRedeemer.redeem(link: issued.link, code: " 042817 ", confirmedEmail: issued.payload.email, device: device, deviceName: "Ada's Mac", gate: &gate, store: store, now: Date(timeIntervalSince1970: 1_700_000_000))
        XCTAssertEqual(redeemed.device.publicKey, device.publicKey)
        XCTAssertFalse(gate.isLocked)
    }

    func testSecondDeviceNeedsANewInvite() async throws {
        let issued = try issue()
        let store = MemoryObjectStore()
        let existing = DeviceRecord(email: issued.payload.email, publicKey: DeviceKey().publicKey, deviceName: "First", inviteId: "older")
        await store.seed(DeviceRecord.key(email: issued.payload.email), body: try JSONEncoder().encode(existing))
        var gate = JoinCodeGate()
        do {
            _ = try await InviteRedeemer.redeem(link: issued.link, code: code, confirmedEmail: issued.payload.email, device: DeviceKey(), deviceName: "Second", gate: &gate, store: store, now: Date(timeIntervalSince1970: 1_700_000_000))
            XCTFail("other device")
        } catch RedeemError.otherDevice {}
        let keys = await store.keys()
        XCTAssertFalse(keys.contains(InviteMetadata.redeemedKey(issued.id)))
    }

    func testAnUnsignedRevokeDoesNotDeleteTheToken() async throws {
        let store = MemoryObjectStore()
        let marker = Data(#"{"inviteId":"inv1","tokenId":"tok","email":"ada@studio.com"}"#.utf8)
        await store.seed(InviteMetadata.revokeKey("inv1"), body: marker)
        await store.seed("invites/noise.revoke", body: Data("not-json".utf8))
        await store.seed(DeviceRecord.key(email: "ada@studio.com"), body: Data(#"{"email":"ada@studio.com","publicKey":"real"}"#.utf8))
        let box = RevokedIds()
        let (owner, context) = try revokeContext(minted: ["tok"])
        _ = owner
        let done = try await TokenRevocation.apply(store: store, context: context) { id in await box.add(id) }
        XCTAssertEqual(done, [])
        let ids = await box.ids
        XCTAssertTrue(ids.isEmpty)
        let keys = await store.keys()
        XCTAssertTrue(keys.contains(DeviceRecord.key(email: "ada@studio.com")))
    }

    func testRevokeDeletesTheTokenAndMember() async throws {
        let store = MemoryObjectStore()
        let (owner, context) = try revokeContext(minted: ["tok"])
        let marker = try TokenRevocation.marker(inviteId: "inv1", tokenId: "tok", email: "ada@studio.com", signer: owner)
        await store.seed(InviteMetadata.revokeKey("inv1"), body: marker)
        await store.seed(InviteMetadata.objectKey("inv1"), body: Data("{}".utf8))
        await store.seed(DeviceRecord.key(email: "ada@studio.com"), body: Data("{}".utf8))
        let box = RevokedIds()
        let done = try await TokenRevocation.apply(store: store, context: context) { id in await box.add(id) }
        XCTAssertEqual(done, ["inv1"])
        let ids = await box.ids
        XCTAssertEqual(ids, ["tok"])
        let keys = await store.keys()
        XCTAssertFalse(keys.contains(DeviceRecord.key(email: "ada@studio.com")))
        XCTAssertFalse(keys.contains(InviteMetadata.revokeKey("inv1")))
        let stranger = DeviceKey()
        let other = try TokenRevocation.marker(inviteId: "inv2", tokenId: "tok", email: "ada@studio.com", signer: stranger)
        await store.seed(InviteMetadata.revokeKey("inv2"), body: other)
        await store.seed(DeviceRecord.key(email: "ada@studio.com"), body: Data(#"{"email":"ada@studio.com","publicKey":"real"}"#.utf8))
        let skipped = try await TokenRevocation.apply(store: store, context: context) { id in await box.add(id) }
        XCTAssertEqual(skipped, [])
        let kept = await store.keys()
        XCTAssertTrue(kept.contains(DeviceRecord.key(email: "ada@studio.com")))
    }

    func testASignedRevokeForATokenThisMacDidNotCreateIsLeftAlone() async throws {
        let store = MemoryObjectStore()
        let (owner, context) = try revokeContext(minted: [])
        let marker = try TokenRevocation.marker(inviteId: "inv1", tokenId: "tok", email: "ada@studio.com", signer: owner)
        await store.seed(InviteMetadata.revokeKey("inv1"), body: marker)
        await store.seed(DeviceRecord.key(email: "ada@studio.com"), body: Data("{}".utf8))
        let box = RevokedIds()
        let done = try await TokenRevocation.apply(store: store, context: context) { id in await box.add(id) }
        XCTAssertEqual(done, [])
        let ids = await box.ids
        XCTAssertTrue(ids.isEmpty)
        let keys = await store.keys()
        XCTAssertTrue(keys.contains(InviteMetadata.revokeKey("inv1")))
        XCTAssertTrue(keys.contains(DeviceRecord.key(email: "ada@studio.com")))
    }

    func testOneFailedTokenDeleteDoesNotBlockTheOthers() async throws {
        let store = MemoryObjectStore()
        let (owner, context) = try revokeContext(minted: ["tok1", "tok2", "tok3"])
        for (invite, token, email) in [("inv1", "tok1", "ada@studio.com"), ("inv2", "tok2", "bo@studio.com"), ("inv3", "tok3", "cy@studio.com")] {
            await store.seed(InviteMetadata.revokeKey(invite), body: try TokenRevocation.marker(inviteId: invite, tokenId: token, email: email, signer: owner))
            await store.seed(DeviceRecord.key(email: email), body: Data("{}".utf8))
        }
        let box = RevokedIds()
        do {
            _ = try await TokenRevocation.apply(store: store, context: context) { id in
                if id == "tok1" { throw S3Error.status(500, "") }
                await box.add(id)
            }
            XCTFail("a failed delete is reported")
        } catch let failure as TokenRevocationFailure {
            XCTAssertEqual(failure.failed, ["inv1"])
            XCTAssertEqual(failure.revoked, ["inv2", "inv3"])
        }
        let ids = await box.ids
        XCTAssertEqual(ids.sorted(), ["tok2", "tok3"])
        let keys = await store.keys()
        XCTAssertTrue(keys.contains(InviteMetadata.revokeKey("inv1")), "the failed marker stays for a retry")
        XCTAssertTrue(keys.contains(DeviceRecord.key(email: "ada@studio.com")))
        XCTAssertFalse(keys.contains(InviteMetadata.revokeKey("inv2")))
        XCTAssertFalse(keys.contains(DeviceRecord.key(email: "cy@studio.com")))
    }

    func testAnIterationCountOutsideTheRangeIsMalformedNotACrash() throws {
        let payload = try issue().payload
        let compact = try XCTUnwrap(Base64URL.decode(try InviteBlob.seal(payload, code: code, iterations: 150_000)))
        let legacy = try XCTUnwrap(Base64URL.decode(try InviteBlob.sealLegacy(payload, code: code, iterations: 150_000)))
        // G2, header, a zero-length id, then the count. G1, then the count.
        for (blob, offset) in [(compact, 4), (legacy, 2)] {
            XCTAssertEqual(blob.subdata(in: offset..<(offset + 4)), Data([0x00, 0x02, 0x49, 0xF0]))
            for count: UInt32 in [0, 1, 99_999, 2_000_001, 0xFFFF_FFFF] {
                var forged = blob
                withUnsafeBytes(of: count.bigEndian) { forged.replaceSubrange(offset..<(offset + 4), with: $0) }
                XCTAssertThrowsError(try InviteBlob.open(Base64URL.encode(forged), code: code), "\(count)") { error in
                    XCTAssertEqual(error as? RedeemError, .malformed)
                }
            }
        }
    }

    func testRedeemStoresTheDisplayNameOnTheMember() async throws {
        let issued = try issue()
        let store = MemoryObjectStore()
        var gate = JoinCodeGate()
        let redeemed = try await InviteRedeemer.redeem(
            link: issued.link, code: code, confirmedEmail: issued.payload.email, device: DeviceKey(),
            deviceName: "Ada's Mac", name: "  Ada Lovelace  ", gate: &gate, store: store,
            now: Date(timeIntervalSince1970: 1_700_000_000)
        )
        XCTAssertEqual(redeemed.device.name, "Ada Lovelace")
        XCTAssertEqual(redeemed.device.email, issued.payload.email)
        let stored = try JSONDecoder().decode(DeviceRecord.self, from: try await store.get(DeviceRecord.key(email: issued.payload.email)).body)
        XCTAssertEqual(stored.name, "Ada Lovelace")
        XCTAssertEqual(stored.publicKey, redeemed.device.publicKey)
    }

    func testMemberMergeKeepsTheLocalDisplayName() throws {
        let local = DeviceRecord(email: "ada@studio.com", publicKey: "local", deviceName: "Mac", inviteId: "a", name: "Ada Chen")
        let remote = DeviceRecord(email: "ada@studio.com", publicKey: "remote", deviceName: "Other", inviteId: "b", name: "Ada Lovelace")
        let merged = try JSONDecoder().decode(DeviceRecord.self, from: MemberFile.merge(local: JSONEncoder().encode(local), remote: JSONEncoder().encode(remote)))
        XCTAssertEqual(merged.name, "Ada Chen")
        XCTAssertEqual(merged.publicKey, "local")
        XCTAssertEqual(merged.deviceName, "Other")
        XCTAssertEqual(merged.inviteId, "b")
        let empty = DeviceRecord(email: "ada@studio.com", publicKey: "local", deviceName: "Mac", inviteId: "a")
        let filled = try JSONDecoder().decode(DeviceRecord.self, from: MemberFile.merge(local: JSONEncoder().encode(empty), remote: JSONEncoder().encode(remote)))
        XCTAssertEqual(filled.name, "Ada Lovelace")
        let authorized = try JSONDecoder().decode(DeviceRecord.self, from: MemberFile.merge(local: JSONEncoder().encode(local), remote: JSONEncoder().encode(remote), authorizedPublicKey: "remote"))
        XCTAssertEqual(authorized.publicKey, "remote")
    }

    func testTheOwnerSyncDropsBlobsAlreadyInTheBucket() async throws {
        let store = MemoryObjectStore()
        let issued = try issue()
        await store.seed(InviteMetadata.objectKey(issued.id), body: try JSONEncoder().encode(issued.metadata))
        let kept = try await InviteBlobs.strip(store: store)
        XCTAssertEqual(kept.map(\.blob), [issued.link.blob])
        let stored = try JSONDecoder().decode(InviteMetadata.self, from: try await store.get(InviteMetadata.objectKey(issued.id)).body)
        XCTAssertNil(stored.blob)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("invite-links-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try LocalInviteLinks.remember(id: issued.id, blob: kept[0].blob, directory: directory)
        XCTAssertEqual(LocalInviteLinks.recall(id: issued.id, directory: directory), issued.link.blob)
        XCTAssertNil(LocalInviteLinks.recall(id: "../\(issued.id)", directory: directory))
    }

    func testAnExistingSignedListKeepsWorkingAfterTheKeyPin() async throws {
        let owner = DeviceKey()
        let admin = DeviceKey()
        let start = TeamBody(generation: 1, ownerEmail: "o@studio.com", ownerPublicKey: owner.publicKey, members: [
            TeamMember(email: "o@studio.com", role: .owner),
            TeamMember(email: "a@studio.com", role: .admin),
        ])
        let signed = try TeamDocument.sign(start, key: owner)
        XCTAssertFalse(signed.canonical.contains("publicKey"))
        let trusted = try XCTUnwrap(TeamDirectory.accept(signed: signed, trusted: nil, devices: [:]))
        let root = try TestLibrary.makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try TestLibrary.writeLibrary(signed, root: root)
        let members = root.appendingPathComponent(".members", isDirectory: true)
        try FileManager.default.createDirectory(at: members, withIntermediateDirectories: true)
        let record = DeviceRecord(email: "a@studio.com", publicKey: admin.publicKey, deviceName: "Admin Mac", inviteId: "old")
        try JSONEncoder().encode(record).write(to: members.appendingPathComponent("a@studio.com.json"))
        var manifest = SyncManifest()
        manifest.store(trusted: trusted)
        XCTAssertNil(manifest.signingDeviceKeys)
        let store = MemoryObjectStore()
        await store.seed("library.json", body: try Data(contentsOf: root.appendingPathComponent("library.json")))
        let engine = BucketSyncEngine(store: store, root: root, merger: ClosureMerger { _, local, _ in local }, manifest: manifest, appVersion: "0.3.10")
        _ = try await engine.syncOnce(now: Date(timeIntervalSince1970: 1_700_000_000))
        let seeded = await engine.currentManifest()
        XCTAssertEqual(seeded.signingDeviceKeys?["a@studio.com"], admin.publicKey)
        var next = start
        next.generation = 2
        next.capGB = 10
        let accepted = TeamDirectory.accept(signed: try TeamDocument.sign(next, key: admin), trusted: trusted, devices: seeded.signingDeviceKeys ?? [:])
        XCTAssertEqual(accepted?.body.capGB, 10)
        let swapped = DeviceRecord(email: "a@studio.com", publicKey: DeviceKey().publicKey, deviceName: "Nope", inviteId: "x")
        try JSONEncoder().encode(swapped).write(to: members.appendingPathComponent("a@studio.com.json"))
        _ = try await engine.syncOnce(now: Date(timeIntervalSince1970: 1_700_000_100))
        let after = await engine.currentManifest()
        XCTAssertEqual(after.signingDeviceKeys?["a@studio.com"], admin.publicKey)
        var planted = start
        planted.generation = 3
        XCTAssertNil(TeamDirectory.accept(signed: try TeamDocument.sign(planted, key: DeviceKey()), trusted: accepted, devices: after.signingDeviceKeys ?? [:]))
        let stranger = DeviceKey()
        let foreign = TeamBody(generation: 1, ownerEmail: "e@studio.com", ownerPublicKey: stranger.publicKey, members: [TeamMember(email: "e@studio.com", role: .owner)])
        XCTAssertNil(TeamDirectory.accept(signed: try TeamDocument.sign(foreign, key: stranger), trusted: nil, devices: [:], inviteOwnerKey: owner.publicKey))
        XCTAssertEqual(TeamDirectory.accept(signed: signed, trusted: nil, devices: [:], inviteOwnerKey: owner.publicKey)?.pinnedOwnerKey, owner.publicKey)
        let known = DeviceBindings.map(files: [
            DeviceBindings.File(filename: "a@studio.com.json", email: "a@studio.com", publicKey: swapped.publicKey),
        ], roster: start, known: ["a@studio.com": admin.publicKey])
        XCTAssertEqual(known["a@studio.com"], admin.publicKey)
    }

    private func revokeContext(minted: Set<String>) throws -> (DeviceKey, RevokeContext) {
        let (owner, signed) = try TestLibrary.owner()
        let body = try XCTUnwrap(TeamDocument.parse(signed.canonical))
        return (owner, RevokeContext(pinnedOwnerKey: owner.publicKey, team: body, mintedTokenIDs: minted))
    }

    func testCloudflareTokenNameAndSecret() async throws {
        let api = CloudflareR2(accountID: "account") { request in
            let url = request.url!.absoluteString
            if url.hasSuffix("/permission_groups") {
                let body: [String: Any] = ["result": [
                    ["id": "read-id", "name": R2Names.bucketRead],
                    ["id": "write-id", "name": R2Names.bucketWrite],
                ]]
                return (200, try JSONSerialization.data(withJSONObject: body))
            }
            let json = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
            XCTAssertEqual(json["name"] as? String, "grails · ada@studio.com")
            let policies = json["policies"] as! [[String: Any]]
            let resources = policies[0]["resources"] as! [String: String]
            XCTAssertEqual(resources["com.cloudflare.edge.r2.bucket.account_default_grails"], "*")
            let created = ["result": ["id": "token-id", "value": "cf-token-value"]]
            return (200, try JSONSerialization.data(withJSONObject: created))
        }
        let token = try await api.createMemberToken(email: "ada@studio.com", bucket: "grails")
        XCTAssertEqual(token.name, "grails · ada@studio.com")
        XCTAssertEqual(token.accessKeyId, "token-id")
        XCTAssertEqual(token.secretAccessKey, "ea18fb75a99ff16fb3fd54b6bf9983daa6fa7b53e13720f2248b5b71c5bbcd55")
        XCTAssertFalse(String(describing: token).contains("cf-token-value"))
        XCTAssertFalse(String(describing: token).contains(token.secretAccessKey))
    }

    func testPresenterLandsOnCanonThenTips() {
        var presenter = JoinPresenter()
        XCTAssertEqual(presenter.screen, .code)
        presenter.unlocked(admin: "Arjun", library: "Studio", email: "ada@studio.com")
        XCTAssertEqual(presenter.screen, .welcome(admin: "Arjun", library: "Studio", email: "ada@studio.com"))
        presenter.progress(done: 1, total: 4, pendingKeys: ["items/a/thumb.jpg", "items/a/original.jpg"])
        XCTAssertEqual(presenter.screen, .syncing(done: 1, total: 4, phase: .thumbnails))
        presenter.finishedSync(collections: ["baseline"], role: .member, tipsSeen: false)
        XCTAssertEqual(presenter.landing, .canon)
        XCTAssertEqual(presenter.screen, .tip(0))
        presenter.nextTip(role: .member)
        presenter.nextTip(role: .member)
        presenter.nextTip(role: .member)
        XCTAssertEqual(presenter.screen, .library(.canon))
        XCTAssertEqual(FirstRunTips.lines, ["Paste or drop", "Figma and Chrome", "⌘K"])
        var admin = JoinPresenter()
        admin.finishedSync(collections: [], role: .admin, tipsSeen: true)
        XCTAssertEqual(admin.screen, .inviteTeammates)
        XCTAssertEqual(admin.landing, .all)
        admin.dismissInvite()
        XCTAssertEqual(admin.screen, .library(.all))
    }

    func testLegacyBaselineNameStillLandsOnCanon() {
        XCTAssertEqual(Landing.pick(collectionNames: ["baseline"]), .canon)
        XCTAssertEqual(Landing.pick(collectionNames: ["Baseline"]), .canon)
        XCTAssertEqual(Landing.pick(collectionNames: ["Canon"]), .canon)
        XCTAssertEqual(Landing.pick(collectionNames: ["Refs"]), .all)
        XCTAssertEqual(TeamPermissions.canPromoteToCanon(.admin), true)
        XCTAssertEqual(TeamPermissions.canPromoteToCanon(.owner), true)
        XCTAssertEqual(TeamPermissions.canPromoteToCanon(.member), false)
    }

    /// A folder or Drive library has no bucket, so the person who has it open can always add to Holy Grail.
    /// A team library still follows the role: the owner and admins add, members only see it.
    func testHolyGrailIsOpenToTheOwnerOfAFolderLibrary() {
        for role in [LibraryRole.owner, .admin, .member] {
            XCTAssertTrue(TeamPermissions.canPromoteToCanon(role, connected: false))
        }
        XCTAssertTrue(TeamPermissions.canPromoteToCanon(.owner, connected: true))
        XCTAssertTrue(TeamPermissions.canPromoteToCanon(.admin, connected: true))
        XCTAssertFalse(TeamPermissions.canPromoteToCanon(.member, connected: true))
    }

    func testCompactLinkRoundTripsAndLegacyStillOpens() async throws {
        let opened = try InviteBlob.open(try issue().link.blob, code: code)
        XCTAssertEqual(opened.email, "ada@studio.com")
        XCTAssertEqual(opened.secretAccessKey, secret)
        XCTAssertEqual(opened.endpoint, "https://example.r2.cloudflarestorage.com")
        XCTAssertEqual(opened.libraryName, "Studio")
        XCTAssertEqual(opened.region, "auto")
        var custom = opened
        custom.region = "wnam"
        custom.endpoint = "https://s3.amazonaws.com"
        let customBlob = try InviteBlob.seal(custom, code: code, id: "inv1", iterations: InviteCrypto.acceptedIterations.lowerBound)
        XCTAssertEqual(try InviteBlob.open(customBlob, code: code), custom)
        let page = GrailsEndpoints.officialSite.appendingPathComponent("open")
        let web = try issue().link.webURL(page: page)
        XCTAssertTrue(web.absoluteString.contains("#j="))
        XCTAssertEqual(JoinLink.parse(web)?.blob.isEmpty, false)

        let legacyPayload = try issue().payload
        let legacy = try InviteBlob.sealLegacy(legacyPayload, code: code, iterations: InviteCrypto.acceptedIterations.lowerBound)
        XCTAssertEqual(try InviteBlob.open(legacy, code: code), legacyPayload)
        let legacyLink = JoinLink(id: "inv1", blob: legacy)
        XCTAssertEqual(legacyLink.url.host, "join")
        XCTAssertEqual(JoinLink.parse(legacyLink.url)?.id, "inv1")
        XCTAssertEqual(JoinLink.parse(legacyLink.webURL(page: page))?.blob, legacy)
        let store = MemoryObjectStore()
        var gate = JoinCodeGate()
        let redeemed = try await InviteRedeemer.redeem(link: legacyLink, code: code, confirmedEmail: legacyPayload.email, device: DeviceKey(), deviceName: "Ada's Mac", gate: &gate, store: store, now: Date(timeIntervalSince1970: 1_700_000_000))
        XCTAssertEqual(redeemed.payload, legacyPayload)

        let ulid = "01ARZ3NDEKTSV4RRFFQ69G5FAV"
        XCTAssertEqual(PackedID.ulid(PackedID.pack(ulid)!.bytes), ulid)
        let uuid = "A1B2C3D4-E5F6-7890-ABCD-EF1234567890"
        let packedUUID = PackedID.pack(uuid)!
        XCTAssertEqual(PackedID.uuid(packedUUID.bytes, upper: true), uuid)
    }

    func testShortLinkIsShorterThanTheJSONSeal() throws {
        let (owner, _) = try TestLibrary.owner()
        let account = "a1b2c3d4e5f67890a1b2c3d4e5f67890"
        let payload = InvitePayload(
            endpoint: "https://\(account).r2.cloudflarestorage.com",
            region: "auto",
            bucket: "grails",
            accessKeyId: "0123456789abcdef0123456789abcdef",
            secretAccessKey: String(repeating: "ab", count: 32),
            email: "ada@studio.com",
            libraryId: "01ARZ3NDEKTSV4RRFFQ69G5FAV",
            libraryName: "Studio",
            adminName: "arjun@studio.com",
            ownerPublicKey: owner.publicKey,
            exp: 1_700_086_400
        )
        let id = "F81D4FAE-7DEC-11D0-A765-00A0C91E6BF6"
        let compact = try InviteBlob.seal(payload, code: code, id: id, iterations: InviteCrypto.acceptedIterations.lowerBound)
        let legacy = try InviteBlob.sealLegacy(payload, code: code, iterations: InviteCrypto.acceptedIterations.lowerBound)
        XCTAssertEqual(try InviteBlob.open(compact, code: code), payload)
        do {
            _ = try InviteBlob.open(compact, code: "000000")
            XCTFail("wrong code")
        } catch RedeemError.wrongCode {}
        XCTAssertEqual(InviteBlob.id(in: compact), id)
        let compactURL = JoinLink(id: id, blob: compact).url.absoluteString
        let legacyURL = JoinLink(id: id, blob: legacy).url.absoluteString
        let page = GrailsEndpoints.officialSite.appendingPathComponent("open")
        let compactWeb = JoinLink(id: id, blob: compact).webURL(page: page).absoluteString
        let legacyWeb = JoinLink(id: id, blob: legacy).webURL(page: page).absoluteString
        XCTAssertEqual(JoinLink.parse(URL(string: compactURL)!)?.id, id)
        XCTAssertEqual(try InviteBlob.open(JoinLink.parse(URL(string: compactWeb)!)!.blob, code: code), payload)
        XCTAssertFalse(compactURL.contains(code))
        XCTAssertFalse(compactURL.contains(payload.secretAccessKey))
        XCTAssertLessThan(compactURL.count, legacyURL.count)
        XCTAssertLessThan(compactWeb.count, legacyWeb.count)
        let shortID = "abcdefghijkl"
        let carried = JoinLink(id: id, blob: compact, shortID: shortID)
        let roundTrip = JoinLink.parse(carried.url)
        XCTAssertEqual(roundTrip?.shortID, shortID)
        XCTAssertEqual(try InviteBlob.open(roundTrip!.blob, code: code), payload)
        let shortURL = InviteRelay.link(id: shortID, origin: GrailsEndpoints.officialSite).absoluteString
        XCTAssertEqual(shortURL, "\(site)/i/\(shortID)")
        XCTAssertLessThan(shortURL.count, compactURL.count)
        XCTAssertEqual(PastedLibraryLink.classify(shortURL), .join)
        var flow = TeammateOnboarding()
        flow.submitLink(shortURL)
        XCTAssertEqual(flow.step, .link)
        XCTAssertEqual(flow.error, .malformed)
        print("INVITE_LINK legacy=\(legacyURL.count) compact=\(compactURL.count) legacyWeb=\(legacyWeb.count) compactWeb=\(compactWeb.count) short=\(shortURL.count)")
    }

    func testRelayPostsOnlyTheSealedBlob() async throws {
        let issued = try issue()
        let script = RelayScript()
        script.payload = Data(#"{"id":"abcdefghijkl","url":"https://evil.example/i/abcdefghijkl"}"#.utf8)
        let published = await InviteRelay.publish(blob: issued.link.blob, exp: issued.metadata.exp, id: issued.id, exchange: script.exchange)
        XCTAssertEqual(published?.url.absoluteString, "\(site)/i/abcdefghijkl")
        XCTAssertEqual(script.calls.count, 1)
        XCTAssertEqual(script.calls[0].method, "POST")
        XCTAssertEqual(script.calls[0].url, "\(site)/api/invite")
        let object = try JSONSerialization.jsonObject(with: script.calls[0].body) as? [String: Any]
        XCTAssertEqual(Set((object ?? [:]).keys), Set(["blob", "exp", "id"]))
        XCTAssertEqual(object?["blob"] as? String, issued.link.blob)
        XCTAssertEqual(object?["id"] as? String, issued.id)
        XCTAssertFalse((object?["blob"] as? String ?? "").contains(secret))
        XCTAssertEqual(try InviteBlob.open(issued.link.blob, code: code).secretAccessKey, secret)
        do {
            _ = try InviteBlob.open(issued.link.blob, code: "000000")
            XCTFail("wrong code")
        } catch RedeemError.wrongCode {}

        let refused = RelayScript()
        let json = #"{"secretAccessKey":"\#(secret)","code":"\#(code)"}"#
        let none = await InviteRelay.publish(blob: json, exp: issued.metadata.exp, id: issued.id, exchange: refused.exchange)
        XCTAssertNil(none)
        XCTAssertTrue(refused.calls.isEmpty)

        let down = RelayScript()
        down.status = 500
        let failed = await InviteRelay.publish(blob: issued.link.blob, exp: issued.metadata.exp, id: issued.id, exchange: down.exchange)
        XCTAssertNil(failed)

        let reader = RelayScript()
        reader.status = 200
        let stored = try JSONSerialization.data(withJSONObject: ["blob": issued.link.blob, "id": issued.id])
        reader.payload = stored
        let resolved = await InviteRelay.resolve(id: "abcdefghijkl", exchange: reader.exchange)
        XCTAssertEqual(resolved?.blob, issued.link.blob)
        XCTAssertEqual(resolved?.inviteID, issued.id)
        XCTAssertEqual(reader.calls[0].method, "GET")
        let joined = JoinLink(id: resolved!.inviteID, blob: resolved!.blob, shortID: "abcdefghijkl")
        XCTAssertEqual(JoinLink.parse(joined.url)?.shortID, "abcdefghijkl")
        let remover = RelayScript()
        await InviteRelay.remove(id: "abcdefghijkl", exchange: remover.exchange)
        XCTAssertEqual(remover.calls[0].method, "DELETE")
        XCTAssertEqual(remover.calls[0].url, "\(site)/api/invite/abcdefghijkl")
    }

    func testSiteComesFromInfoPlist() {
        XCTAssertEqual(GrailsEndpoints.site, GrailsEndpoints.officialSite)
        XCTAssertEqual(GrailsEndpoints.site(infoValue: nil), GrailsEndpoints.officialSite)
        XCTAssertEqual(GrailsEndpoints.site(infoValue: "https://grails.example.org/")?.absoluteString, "https://grails.example.org")
        XCTAssertNil(GrailsEndpoints.site(infoValue: ""))
        XCTAssertNil(GrailsEndpoints.site(infoValue: "$(GRAILS_SITE_URL)"))
        XCTAssertNil(GrailsEndpoints.site(infoValue: "http://grails.example.org"))
        XCTAssertEqual(GrailsEndpoints.linkPage?.absoluteString, "\(site)/open")
    }

    func testNoSiteSkipsTheRelayAndKeepsTheLongLink() async throws {
        let issued = try issue()
        let script = RelayScript()
        let published = await InviteRelay.publish(blob: issued.link.blob, exp: issued.metadata.exp, id: issued.id, origin: nil, exchange: script.exchange)
        XCTAssertNil(published)
        let resolved = await InviteRelay.resolve(id: "abcdefghijkl", origin: nil, exchange: script.exchange)
        XCTAssertNil(resolved)
        await InviteRelay.remove(id: "abcdefghijkl", origin: nil, exchange: script.exchange)
        XCTAssertTrue(script.calls.isEmpty)
        XCTAssertNil(InviteRelay.shortID(in: URL(string: "\(site)/i/abcdefghijkl")!, origin: nil))
        let message = BucketInviteMessage.make(library: "Studio", link: issued.link.url, from: "Ada", site: nil)
        XCTAssertFalse(message.body.contains("Install Grails"))
        XCTAssertTrue(message.body.contains("1. If macOS blocks it, run: \(BucketInviteMessage.quarantine)"))
        XCTAssertTrue(message.body.contains("2. Open this link: grails://j/"))
    }

    private func issue(role: LibraryRole = .member) throws -> IssuedInvite {
        let (owner, signed) = try TestLibrary.owner()
        let body = TeamDocument.parse(signed.canonical)!
        return try InviteIssuer.issue(
            email: "Ada@Studio.com",
            libraryId: "lib",
            libraryName: "Studio",
            adminName: "Arjun",
            endpoint: "https://example.r2.cloudflarestorage.com",
            region: "auto",
            bucket: "grails",
            accessKeyId: "access",
            secretAccessKey: secret,
            tokenId: "tok",
            ownerPublicKey: owner.publicKey,
            team: body,
            signer: owner,
            now: Date(timeIntervalSince1970: 1_700_000_000),
            code: code,
            id: "inv1",
            role: role,
            iterations: InviteCrypto.acceptedIterations.lowerBound
        )
    }

    func testRevokeDeletesTheInviteAndAFailedPutLeavesIt() async throws {
        let store = MemoryObjectStore()
        let invite = ListedInvite(id: "inv1", email: "bea@company.com", state: .pending, tokenId: "tok", blob: "blob", exp: 10)
        let body = try JSONEncoder().encode(InviteMetadata(id: "inv1", email: "bea@company.com", exp: 10, tokenId: "tok", blob: "blob"))
        await store.seed(InviteMetadata.objectKey(invite.id), body: body)
        try await InviteRevocation.commit(invite, store: store, signer: DeviceKey())
        let keys = await store.keys()
        XCTAssertTrue(keys.contains(InviteMetadata.revokeKey("inv1")))
        XCTAssertFalse(keys.contains(InviteMetadata.objectKey("inv1")))
        let heads = try await store.list(prefix: "invites/")
        var bodies: [String: Data] = [:]
        if let marker = await store.body(InviteMetadata.revokeKey("inv1")) {
            bodies[InviteMetadata.revokeKey("inv1")] = marker
        }
        XCTAssertTrue(InviteList.parse(objects: heads, bodies: bodies).isEmpty)

        let failing = RejectingStore()
        do {
            try await InviteRevocation.commit(invite, store: failing, signer: DeviceKey())
            XCTFail("put should fail")
        } catch {}
        let deleted = await failing.deletes
        XCTAssertTrue(deleted.isEmpty)
    }
}

private actor RejectingStore: ObjectStore {
    var deletes: [String] = []
    func list(prefix: String) async throws -> [ObjectHead] { [] }
    func get(_ key: String) async throws -> ObjectGet { throw S3Error.notFound }
    func put(_ key: String, body: Data, contentType: String, ifMatch: String?, ifNoneMatch: String?) async throws -> String {
        throw S3Error.status(500, "down")
    }
    func delete(_ key: String) async throws { deletes.append(key) }
}

private final class RelayScript: @unchecked Sendable {
    private let lock = NSLock()
    private(set) var calls: [(method: String, url: String, body: Data)] = []
    var status = 201
    var payload = Data()

    func exchange(_ request: URLRequest) async -> (Int, Data)? {
        record(request)
    }

    private func record(_ request: URLRequest) -> (Int, Data) {
        lock.lock()
        defer { lock.unlock() }
        calls.append((request.httpMethod ?? "GET", request.url?.absoluteString ?? "", request.httpBody ?? Data()))
        return (status, payload)
    }
}

private actor RevokedIds {
    private(set) var ids: [String] = []

    func add(_ id: String) { ids.append(id) }
}
