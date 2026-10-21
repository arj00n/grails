import Foundation
import XCTest
import GrailsSync

/// Talks to a real S3-compatible bucket when the environment is set. MinIO in `Scripts/s3-integration.sh` uses the local
/// user `grailstest`. A Cloudflare R2 run uses the same four variables and a `_test/` prefix that this test deletes.
final class S3IntegrationTests: XCTestCase {
    func testPutGetListAndConditionalCreate() async throws {
        let env = ProcessInfo.processInfo.environment
        let endpoint = env["GRAILS_S3_ENDPOINT"] ?? ""
        let bucket = env["GRAILS_S3_BUCKET"] ?? ""
        let keyID = env["GRAILS_S3_KEY_ID"] ?? ""
        let secret = env["GRAILS_S3_SECRET"] ?? ""
        guard !endpoint.isEmpty, !bucket.isEmpty, !keyID.isEmpty, !secret.isEmpty, let url = URL(string: endpoint) else {
            if env["GRAILS_S3_REQUIRED"] == "1" {
                XCTFail("GRAILS_S3_ENDPOINT, GRAILS_S3_BUCKET, GRAILS_S3_KEY_ID and GRAILS_S3_SECRET are required")
            }
            throw XCTSkip("Set GRAILS_S3_ENDPOINT, GRAILS_S3_BUCKET, GRAILS_S3_KEY_ID and GRAILS_S3_SECRET")
        }
        let prefix = "_test/\(UUID().uuidString)/"
        let client = S3Client(
            location: S3Location(endpoint: url, bucket: bucket, region: env["GRAILS_S3_REGION"] ?? "us-east-1", keyPrefix: prefix),
            credentials: S3Credentials(accessKeyId: keyID, secretAccessKey: secret)
        )
        do {
            try? await client.createBucket()
            let body = Data("grails-sync".utf8)
            let etag = try await client.put("notes/hello.txt", body: body, contentType: "text/plain", ifMatch: nil, ifNoneMatch: "*")
            let got = try await client.get("notes/hello.txt")
            XCTAssertEqual(got.body, body)
            XCTAssertEqual(got.etag, etag)
            let listed = try await client.list(prefix: "notes/")
            XCTAssertEqual(listed.map(\.key), ["notes/hello.txt"])
            do {
                _ = try await client.put("notes/hello.txt", body: Data("again".utf8), contentType: "text/plain", ifMatch: nil, ifNoneMatch: "*")
                XCTFail("second create")
            } catch S3Error.preconditionFailed {}
            try await client.delete("notes/hello.txt")
            let after = try await client.list(prefix: "")
            XCTAssertTrue(after.isEmpty)
        } catch {
            await Self.wipe(client)
            throw error
        }
        await Self.wipe(client)
    }

    func testBackupRestoresProfilesLooksPhotosItemsAndRoles() async throws {
        let live = try openLive()
        let stamp = String(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(8)).lowercased()
        let library = client(bucket: "grails-lib-\(stamp)", live: live)
        let backup = client(bucket: "grails-bak-\(stamp)", live: live)
        do {
            try await ensureBucket(library)
            try await ensureBucket(backup)
            let (owner, signed) = try TestLibrary.owner(email: "ada@example.com")
            let libraryJSON = try TeamFile.write(signed, into: Data(#"{"name":"Studio"}"#.utf8))
            let profile = Data(#"{"firstSeen":"2023-11-14T22:13:20.000Z","handle":"ada","id":"m-ada","lastSeen":"2023-11-14T22:13:20.000Z","name":"Ada"}"#.utf8)
            let look = Data(#"{"character":99,"photo":false,"tint":4}"#.utf8)
            let photo = Data("same-photo-bytes".utf8)
            let item = Data(#"{"id":"a","title":"Sketch"}"#.utf8)
            var expected: [String: Data] = [
                "library.json": libraryJSON,
                ".members/m-ada.json": profile,
                ".members/m-ada.look.json": look,
                ".members/m-ada.avatar.jpg": photo,
                "items/a/item.json": item,
            ]
            for (key, body) in expected {
                _ = try await library.put(key, body: body, contentType: S3Client.contentType(key), ifMatch: nil, ifNoneMatch: nil)
            }
            let first = try await library.list(prefix: "")
            _ = try await LibrarySnapshot.run(live: first, read: { try await library.get($0).body }, destination: backup, existing: [], day: "2026-10-16")
            expected[".members/m-bea.avatar.jpg"] = photo
            _ = try await library.put(".members/m-bea.avatar.jpg", body: photo, contentType: "image/jpeg", ifMatch: nil, ifNoneMatch: nil)
            let secondLive = try await library.list(prefix: "")
            let existing = try await backup.list(prefix: "snapshots/")
            let report = try await LibrarySnapshot.run(live: secondLive, read: { try await library.get($0).body }, destination: backup, existing: existing, day: "2026-10-17")
            XCTAssertTrue(report.added.contains("snapshots/2026-10-17/.members/m-bea.avatar.jpg"))
            await Self.wipe(library)
            let snaps = try await backup.list(prefix: "snapshots/")
            let restored = try await LibrarySnapshot.restoreDay("2026-10-17", snapshot: snaps, read: { try await backup.get($0).body }, write: { key, body in
                _ = try await library.put(key, body: body, contentType: S3Client.contentType(key), ifMatch: nil, ifNoneMatch: nil)
            })
            XCTAssertEqual(restored.sorted(), expected.keys.sorted())
            for (key, body) in expected {
                let got = try await library.get(key)
                XCTAssertEqual(got.body, body, key)
            }
            let savedLibrary = try await library.get("library.json")
            let saved = try JSONSerialization.jsonObject(with: savedLibrary.body) as? [String: Any]
            let team = try XCTUnwrap(saved?["team"] as? [String: Any])
            let canonical = try XCTUnwrap(team["canonical"] as? String)
            let signature = try XCTUnwrap(team["signature"] as? String)
            let signer = try XCTUnwrap(team["signerPublicKey"] as? String)
            XCTAssertTrue(DeviceKey.verify(signature: signature, publicKey: signer, data: Data(canonical.utf8)))
            XCTAssertEqual(TeamDocument.parse(canonical)?.role(of: "ada@example.com"), .owner)
            XCTAssertEqual(owner.publicKey, signer)
        } catch {
            await Self.wipe(library)
            await Self.wipe(backup)
            throw error
        }
        await Self.wipe(library)
        await Self.wipe(backup)
    }

    func testAnOlderCredentialStillSyncsAndInvitesAreSingleUse() async throws {
        let live = try openLive()
        let stamp = String(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(8)).lowercased()
        let bucket = "grails-inv-\(stamp)"
        let endpoint = live.endpoint.absoluteString
        let access = """
        {"accessKeyId":"\(live.keyID)","bucket":"\(bucket)","email":"ada@example.com","endpoint":"\(endpoint)","region":"\(live.region)","secretAccessKey":"\(live.secret)"}
        """
        let bundleJSON = """
        {"libraries":{"lib-1":{"access":"\(Data(access.utf8).base64EncodedString())"}}}
        """
        let bundle = try JSONDecoder().decode(SecretBundle.self, from: Data(bundleJSON.utf8))
        let stored = try XCTUnwrap(bundle.libraries["lib-1"]?.access)
        let fields = try XCTUnwrap(try JSONSerialization.jsonObject(with: stored) as? [String: String])
        let session = S3Client(
            location: S3Location(endpoint: live.endpoint, bucket: bucket, region: live.region),
            credentials: S3Credentials(accessKeyId: try XCTUnwrap(fields["accessKeyId"]), secretAccessKey: try XCTUnwrap(fields["secretAccessKey"]))
        )
        do {
            try await ensureBucket(session)
            let marker = Data("session-ok".utf8)
            _ = try await session.put("notes/session.txt", body: marker, contentType: "text/plain", ifMatch: nil, ifNoneMatch: "*")
            let got = try await session.get("notes/session.txt")
            XCTAssertEqual(got.body, marker)

            let (owner, signed) = try TestLibrary.owner(email: "owner@example.com")
            let team = try XCTUnwrap(TeamDocument.parse(signed.canonical))
            let now = Date(timeIntervalSince1970: 1_700_000_000)
            let issued = try InviteIssuer.issue(
                email: "ada@example.com", libraryId: "lib", libraryName: "Studio", adminName: "Owner",
                endpoint: endpoint, region: live.region, bucket: bucket,
                accessKeyId: live.keyID, secretAccessKey: live.secret, tokenId: "tok",
                ownerPublicKey: owner.publicKey, team: team, signer: owner,
                now: now, code: "042817", id: "inv-live", iterations: InviteCrypto.acceptedIterations.lowerBound
            )
            _ = try await session.put(InviteMetadata.objectKey(issued.id), body: try JSONEncoder().encode(issued.metadata), contentType: "application/json", ifMatch: nil, ifNoneMatch: "*")
            var gate = JoinCodeGate()
            let mac = DeviceKey()
            let redeemed = try await InviteRedeemer.redeem(link: issued.link, code: "042817", confirmedEmail: "ada@example.com", device: mac, deviceName: "Ada's Mac", gate: &gate, store: session, now: now)
            XCTAssertEqual(redeemed.device.publicKey, mac.publicKey)
            XCTAssertEqual(InviteCode.normalize("042817")?.count, 6)
            var second = JoinCodeGate()
            do {
                _ = try await InviteRedeemer.redeem(link: issued.link, code: "042817", confirmedEmail: "ada@example.com", device: DeviceKey(), deviceName: "Other Mac", gate: &second, store: session, now: now)
                XCTFail("used invite")
            } catch RedeemError.otherDevice {}
            try await session.delete(DeviceRecord.key(email: "ada@example.com"))
            do {
                _ = try await InviteRedeemer.redeem(link: issued.link, code: "042817", confirmedEmail: "ada@example.com", device: DeviceKey(), deviceName: "Other Mac", gate: &second, store: session, now: now)
                XCTFail("redeemed invite")
            } catch RedeemError.alreadyRedeemed {}

            let expired = try InviteIssuer.issue(
                email: "bea@example.com", libraryId: "lib", libraryName: "Studio", adminName: "Owner",
                endpoint: endpoint, region: live.region, bucket: bucket,
                accessKeyId: live.keyID, secretAccessKey: live.secret, tokenId: "tok-2",
                ownerPublicKey: owner.publicKey, team: team, signer: owner,
                now: Date(timeIntervalSince1970: 1_000), code: "111111", id: "inv-old", iterations: InviteCrypto.acceptedIterations.lowerBound
            )
            var late = JoinCodeGate()
            do {
                _ = try await InviteRedeemer.redeem(link: expired.link, code: "111111", confirmedEmail: "bea@example.com", device: DeviceKey(), deviceName: "Bea's Mac", gate: &late, store: session, now: Date())
                XCTFail("expired invite")
            } catch RedeemError.expired {}
            let redeemedKeys = try await session.list(prefix: InviteMetadata.redeemedKey(expired.id))
            XCTAssertTrue(redeemedKeys.isEmpty)
        } catch {
            await Self.wipe(session)
            throw error
        }
        await Self.wipe(session)
    }

    private struct LiveEnv {
        var endpoint: URL
        var region: String
        var keyID: String
        var secret: String
    }

    private func openLive() throws -> LiveEnv {
        let env = ProcessInfo.processInfo.environment
        let endpoint = env["GRAILS_S3_ENDPOINT"] ?? ""
        let keyID = env["GRAILS_S3_KEY_ID"] ?? ""
        let secret = env["GRAILS_S3_SECRET"] ?? ""
        guard !endpoint.isEmpty, !keyID.isEmpty, !secret.isEmpty, let url = URL(string: endpoint) else {
            if env["GRAILS_S3_REQUIRED"] == "1" {
                XCTFail("GRAILS_S3_ENDPOINT, GRAILS_S3_KEY_ID and GRAILS_S3_SECRET are required")
            }
            throw XCTSkip("Set GRAILS_S3_ENDPOINT, GRAILS_S3_KEY_ID and GRAILS_S3_SECRET")
        }
        return LiveEnv(endpoint: url, region: env["GRAILS_S3_REGION"] ?? "us-east-1", keyID: keyID, secret: secret)
    }

    private func client(bucket: String, live: LiveEnv) -> S3Client {
        S3Client(
            location: S3Location(endpoint: live.endpoint, bucket: bucket, region: live.region),
            credentials: S3Credentials(accessKeyId: live.keyID, secretAccessKey: live.secret)
        )
    }

    private func ensureBucket(_ client: S3Client) async throws {
        do {
            try await client.createBucket()
        } catch let S3Error.status(code, _) where code == 409 {
        }
    }

    private static func wipe(_ client: S3Client) async {
        guard let heads = try? await client.list(prefix: "") else { return }
        for head in heads { try? await client.delete(head.key) }
    }
}
