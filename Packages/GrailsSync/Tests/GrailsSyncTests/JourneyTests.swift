import Foundation
import XCTest
import GrailsSync

final class JourneyTests: XCTestCase {
    private let code = "042817"
    private let secret = "SECRET-VALUE-do-not-leak-9f3a"

    func testOwnerInviteJoinSyncAndRevoke() async throws {
        let store = GateStore()
        let ownerRoot = try TestLibrary.makeRoot()
        let memberRoot = try TestLibrary.makeRoot()
        defer {
            try? FileManager.default.removeItem(at: ownerRoot)
            try? FileManager.default.removeItem(at: memberRoot)
        }
        let (ownerKey, signed) = try TestLibrary.owner()
        try TestLibrary.writeLibrary(signed, root: ownerRoot)
        let owner = BucketSyncEngine(store: store, root: ownerRoot, merger: ClosureMerger { _, local, _ in local }, appVersion: "0.3.5")
        let created = try await owner.syncOnce(now: Date(timeIntervalSince1970: 1_700_000_000))
        XCTAssertTrue(created.uploaded.contains("library.json"))

        let token = try await mintedToken()
        XCTAssertEqual(token.name, "grails · ada@studio.com")
        let issued = try issue(owner: ownerKey, signed: signed, accessKeyId: token.accessKeyId, secret: token.secretAccessKey, tokenId: token.id)
        let meta = try JSONEncoder().encode(issued.metadata)
        _ = try await store.put(InviteMetadata.objectKey(issued.id), body: meta, contentType: "application/json", ifMatch: nil, ifNoneMatch: "*")

        var wrongEmail = JoinCodeGate()
        do {
            _ = try await InviteRedeemer.redeem(link: issued.link, code: code, confirmedEmail: "other@studio.com", device: DeviceKey(), deviceName: "Other", gate: &wrongEmail, store: store, now: Date(timeIntervalSince1970: 1_700_000_000))
            XCTFail("email")
        } catch RedeemError.emailMismatch {}
        let beforeRedeem = await store.storedKeys()
        XCTAssertFalse(beforeRedeem.contains(InviteMetadata.redeemedKey(issued.id)))

        let device = DeviceKey()
        var gate = JoinCodeGate()
        let redeemed = try await InviteRedeemer.redeem(link: issued.link, code: code, confirmedEmail: "Ada@Studio.com", device: device, deviceName: "Ada's Mac", gate: &gate, store: store, now: Date(timeIntervalSince1970: 1_700_000_000))
        XCTAssertEqual(redeemed.device.publicKey, device.publicKey)
        XCTAssertEqual(redeemed.device.email, "ada@studio.com")
        let bound = try JSONDecoder().decode(DeviceRecord.self, from: try await store.get(DeviceRecord.key(email: "ada@studio.com")).body)
        XCTAssertEqual(bound.publicKey, device.publicKey)

        try Data("from-owner".utf8).write(to: nested(ownerRoot, "items/a/note.txt"))
        let ownerPush = try await owner.syncOnce(now: Date(timeIntervalSince1970: 1_700_000_020))
        XCTAssertTrue(ownerPush.uploaded.contains("items/a/note.txt"))
        let member = BucketSyncEngine(store: store, root: memberRoot, merger: ClosureMerger { _, local, _ in local }, appVersion: "0.3.5")
        let memberPull = try await member.syncOnce(now: Date(timeIntervalSince1970: 1_700_000_030))
        XCTAssertTrue(memberPull.downloaded.contains("items/a/note.txt"))
        XCTAssertEqual(try Data(contentsOf: memberRoot.appendingPathComponent("items/a/note.txt")), Data("from-owner".utf8))

        try Data("from-member".utf8).write(to: nested(memberRoot, "items/b/note.txt"))
        let memberPush = try await member.syncOnce(now: Date(timeIntervalSince1970: 1_700_000_040))
        XCTAssertTrue(memberPush.uploaded.contains("items/b/note.txt"))
        let ownerPull = try await owner.syncOnce(now: Date(timeIntervalSince1970: 1_700_000_050))
        XCTAssertTrue(ownerPull.downloaded.contains("items/b/note.txt"))
        XCTAssertEqual(try Data(contentsOf: ownerRoot.appendingPathComponent("items/b/note.txt")), Data("from-member".utf8))
        XCTAssertEqual(SyncTiming.poll, .seconds(15))
        XCTAssertEqual(BucketSyncEngine.poll, .seconds(15))

        let marker = try TokenRevocation.marker(inviteId: issued.id, tokenId: token.id, email: "ada@studio.com", signer: ownerKey)
        _ = try await store.put(InviteMetadata.revokeKey(issued.id), body: marker, contentType: "application/json", ifMatch: nil, ifNoneMatch: nil)
        let box = RevokedTokenIDs()
        let context = RevokeContext(pinnedOwnerKey: ownerKey.publicKey, team: TeamDocument.parse(signed.canonical), mintedTokenIDs: [token.id])
        let revoked = try await TokenRevocation.apply(store: store, context: context) { id in await box.add(id) }
        XCTAssertEqual(revoked, [issued.id])
        let revokedIDs = await box.ids
        XCTAssertEqual(revokedIDs, [token.id])
        await store.close()
        try Data("after-revoke".utf8).write(to: nested(memberRoot, "items/c/note.txt"))
        let task = Task {
            await member.run { interval in
                XCTAssertEqual(interval, .seconds(15))
            }
        }
        await task.value
        let stopped = try await member.syncOnce()
        XCTAssertEqual(stopped.stopped, .revoked)
        let afterRevoke = await store.storedKeys()
        XCTAssertFalse(afterRevoke.contains("items/c/note.txt"))
        XCTAssertEqual(try Data(contentsOf: memberRoot.appendingPathComponent("items/c/note.txt")), Data("after-revoke".utf8))
    }

    func testLinkReuseIsRejected() async throws {
        let issued = try issue()
        let store = MemoryObjectStore()
        let first = DeviceKey()
        var gate = JoinCodeGate()
        _ = try await InviteRedeemer.redeem(link: issued.link, code: code, confirmedEmail: issued.payload.email, device: first, deviceName: "Ada's Mac", gate: &gate, store: store, now: Date(timeIntervalSince1970: 1_700_000_000))
        var again = JoinCodeGate()
        do {
            _ = try await InviteRedeemer.redeem(link: issued.link, code: code, confirmedEmail: issued.payload.email, device: DeviceKey(), deviceName: "Other Mac", gate: &again, store: store, now: Date(timeIntervalSince1970: 1_700_000_100))
            XCTFail("reused")
        } catch RedeemError.otherDevice {}
        try await store.delete(DeviceRecord.key(email: issued.payload.email))
        var markerOnly = JoinCodeGate()
        do {
            _ = try await InviteRedeemer.redeem(link: issued.link, code: code, confirmedEmail: issued.payload.email, device: DeviceKey(), deviceName: "Third Mac", gate: &markerOnly, store: store, now: Date(timeIntervalSince1970: 1_700_000_200))
            XCTFail("marker")
        } catch RedeemError.alreadyRedeemed {}
        let marker = try await store.get(InviteMetadata.redeemedKey(issued.id))
        let record = try JSONDecoder().decode(DeviceRecord.self, from: marker.body)
        XCTAssertEqual(record.publicKey, first.publicKey)
    }

    func testFiveWrongCodesLock() async throws {
        let issued = try issue()
        let store = MemoryObjectStore()
        var gate = JoinCodeGate()
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        for attempt in 1...5 {
            do {
                _ = try await InviteRedeemer.redeem(link: issued.link, code: "00000\(attempt)", confirmedEmail: issued.payload.email, device: DeviceKey(), deviceName: "Mac", gate: &gate, store: store, now: now)
                XCTFail("accepted")
            } catch let error as RedeemError {
                XCTAssertEqual(error, attempt == 5 ? .locked : .wrongCode)
            }
        }
        XCTAssertTrue(gate.isLocked)
        do {
            _ = try await InviteRedeemer.redeem(link: issued.link, code: code, confirmedEmail: issued.payload.email, device: DeviceKey(), deviceName: "Mac", gate: &gate, store: store, now: now)
            XCTFail("locked")
        } catch RedeemError.locked {}
        let lockedCounts = await store.counts()
        XCTAssertEqual(lockedCounts.puts, 0)
    }

    func testInviteExpiresAfterTwentyFourHours() async throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let issued = try issue(now: now)
        XCTAssertEqual(InviteLifetime.default, 24 * 60 * 60)
        XCTAssertEqual(issued.payload.exp, now.timeIntervalSince1970 + InviteLifetime.default)
        let store = MemoryObjectStore()
        var gate = JoinCodeGate()
        do {
            _ = try await InviteRedeemer.redeem(link: issued.link, code: code, confirmedEmail: issued.payload.email, device: DeviceKey(), deviceName: "Mac", gate: &gate, store: store, now: Date(timeIntervalSince1970: issued.payload.exp + 1))
            XCTFail("expired")
        } catch RedeemError.expired {}
        let expiredCounts = await store.counts()
        XCTAssertEqual(expiredCounts.puts, 0)
        var still = JoinCodeGate()
        let redeemed = try await InviteRedeemer.redeem(link: issued.link, code: code, confirmedEmail: issued.payload.email, device: DeviceKey(), deviceName: "Mac", gate: &still, store: store, now: Date(timeIntervalSince1970: issued.payload.exp))
        XCTAssertEqual(redeemed.payload.email, "ada@studio.com")
    }

    func testConcurrentEditsAreBothKept() async throws {
        let store = MemoryObjectStore()
        let ownerRoot = try TestLibrary.makeRoot()
        let memberRoot = try TestLibrary.makeRoot()
        defer {
            try? FileManager.default.removeItem(at: ownerRoot)
            try? FileManager.default.removeItem(at: memberRoot)
        }
        let (_, signed) = try TestLibrary.owner()
        try TestLibrary.writeLibrary(signed, root: ownerRoot)
        let merger = ClosureMerger { _, local, remote in unionMarks(local, remote) }
        let owner = BucketSyncEngine(store: store, root: ownerRoot, merger: merger, appVersion: "0.3.5")
        _ = try await owner.syncOnce()
        try Data(marks(["base"]).utf8).write(to: nested(ownerRoot, "items/a/item.json"))
        _ = try await owner.syncOnce()
        let member = BucketSyncEngine(store: store, root: memberRoot, merger: merger, appVersion: "0.3.5")
        _ = try await member.syncOnce()
        try Data(marks(["owner"]).utf8).write(to: ownerRoot.appendingPathComponent("items/a/item.json"))
        try Data(marks(["member"]).utf8).write(to: memberRoot.appendingPathComponent("items/a/item.json"))
        _ = try await owner.syncOnce()
        let merged = try await member.syncOnce()
        XCTAssertEqual(merged.conflicts, ["items/a/item.json"])
        let stored = await store.body("items/a/item.json")
        let body = try XCTUnwrap(stored)
        let kept = try XCTUnwrap(jsonMarks(body))
        XCTAssertTrue(kept.contains("owner"))
        XCTAssertTrue(kept.contains("member"))
        let onMember = try Data(contentsOf: memberRoot.appendingPathComponent("items/a/item.json"))
        XCTAssertEqual(jsonMarks(onMember), kept)
        _ = try await owner.syncOnce()
        let onOwner = try Data(contentsOf: ownerRoot.appendingPathComponent("items/a/item.json"))
        let ownerMarks = try XCTUnwrap(jsonMarks(onOwner))
        XCTAssertTrue(ownerMarks.contains("owner"))
        XCTAssertTrue(ownerMarks.contains("member"))
    }

    private func mintedToken() async throws -> MemberToken {
        let api = CloudflareR2(accountID: "account") { request in
            let url = request.url!.absoluteString
            if url.hasSuffix("/permission_groups") {
                let body: [String: Any] = ["result": [
                    ["id": "read-id", "name": R2Names.bucketRead],
                    ["id": "write-id", "name": R2Names.bucketWrite],
                ]]
                return (200, try JSONSerialization.data(withJSONObject: body))
            }
            let created = ["result": ["id": "token-id", "value": "cf-token-value"]]
            return (200, try JSONSerialization.data(withJSONObject: created))
        }
        return try await api.createMemberToken(email: "ada@studio.com", bucket: "grails")
    }

    private func issue(owner: DeviceKey? = nil, signed: SignedTeam? = nil, accessKeyId: String = "access", secret: String? = nil, tokenId: String = "tok", now: Date = Date(timeIntervalSince1970: 1_700_000_000)) throws -> IssuedInvite {
        let made = try TestLibrary.owner()
        let key = owner ?? made.0
        let team = signed ?? made.1
        let body = TeamDocument.parse(team.canonical)!
        return try InviteIssuer.issue(
            email: "Ada@Studio.com", libraryId: "lib", libraryName: "Studio", adminName: "Arjun",
            endpoint: "https://example.r2.cloudflarestorage.com", region: "auto", bucket: "grails",
            accessKeyId: accessKeyId, secretAccessKey: secret ?? self.secret, tokenId: tokenId,
            ownerPublicKey: key.publicKey, team: body, signer: key, now: now, code: code, id: "inv1", iterations: InviteCrypto.acceptedIterations.lowerBound
        )
    }
}

private func nested(_ root: URL, _ key: String) throws -> URL {
    let url = root.appendingPathComponent(key)
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    return url
}

private func marks(_ values: [String]) -> String {
    let data = try! JSONSerialization.data(withJSONObject: ["marks": values])
    return String(decoding: data, as: UTF8.self)
}

private func jsonMarks(_ data: Data) -> [String]? {
    let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    return object?["marks"] as? [String]
}

private func unionMarks(_ local: Data, _ remote: Data) -> Data {
    let combined = Set((jsonMarks(local) ?? []) + (jsonMarks(remote) ?? [])).sorted()
    return Data(marks(combined).utf8)
}

private actor RevokedTokenIDs {
    private(set) var ids: [String] = []
    func add(_ id: String) { ids.append(id) }
}

private actor GateStore: ObjectStore {
    private let inner = MemoryObjectStore()
    private var open = true

    func close() { open = false }

    func storedKeys() async -> [String] { await inner.keys() }

    func list(prefix: String) async throws -> [ObjectHead] {
        try allow()
        return try await inner.list(prefix: prefix)
    }

    func get(_ key: String) async throws -> ObjectGet {
        try allow()
        return try await inner.get(key)
    }

    func put(_ key: String, body: Data, contentType: String, ifMatch: String?, ifNoneMatch: String?) async throws -> String {
        try allow()
        return try await inner.put(key, body: body, contentType: contentType, ifMatch: ifMatch, ifNoneMatch: ifNoneMatch)
    }

    func delete(_ key: String) async throws {
        try allow()
        try await inner.delete(key)
    }

    private func allow() throws {
        if !open { throw S3Error.status(403, "revoked") }
    }
}
