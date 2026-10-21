import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum R2Secret {
    public static func accessSecret(tokenValue: String) -> String {
        Digests.sha256Hex(Data(tokenValue.utf8))
    }
}

public enum R2Names {
    public static let bucketRead = "Workers R2 Storage Bucket Item Read"
    public static let bucketWrite = "Workers R2 Storage Bucket Item Write"

    public static func token(email: String) -> String { "grails · \(email)" }

    public static func resource(accountID: String, bucket: String, jurisdiction: String = "default") -> String {
        "com.cloudflare.edge.r2.bucket.\(accountID)_\(jurisdiction)_\(bucket)"
    }
}

public struct MemberToken: Equatable, Sendable {
    public var id: String
    public var name: String
    public var accessKeyId: String
    public var secretAccessKey: String

    public init(id: String, name: String, accessKeyId: String, secretAccessKey: String) {
        self.id = id
        self.name = name
        self.accessKeyId = accessKeyId
        self.secretAccessKey = secretAccessKey
    }
}

extension MemberToken: CustomStringConvertible {
    public var description: String { "MemberToken(id: \(id), name: \(name), secretAccessKey: <redacted>)" }
}

public struct CloudflareR2: Sendable {
    public var accountID: String
    public var perform: @Sendable (URLRequest) async throws -> (Int, Data)

    public init(accountID: String, apiToken: String, session: URLSession = HTTPTransport.uncached) {
        self.accountID = accountID
        let transport = HTTPTransport(session: session)
        self.perform = { request in
            var signed = request
            signed.setValue("Bearer \(apiToken)", forHTTPHeaderField: "Authorization")
            let (data, response) = try await transport.data(for: signed)
            return (response.statusCode, data)
        }
    }

    public init(accountID: String, perform: @escaping @Sendable (URLRequest) async throws -> (Int, Data)) {
        self.accountID = accountID
        self.perform = perform
    }

    public func createMemberToken(email: String, bucket: String) async throws -> MemberToken {
        let groupsURL = URL(string: "https://api.cloudflare.com/client/v4/accounts/\(accountID)/tokens/permission_groups")!
        let (groupStatus, groupData) = try await perform(URLRequest(url: groupsURL))
        guard groupStatus == 200, let groupJSON = try? JSONSerialization.jsonObject(with: groupData) as? [String: Any],
              let result = groupJSON["result"] as? [[String: Any]] else { throw S3Error.badResponse }
        let wanted = [R2Names.bucketRead, R2Names.bucketWrite]
        let ids = wanted.compactMap { name in result.first { $0["name"] as? String == name }?["id"] as? String }
        guard ids.count == wanted.count else { throw S3Error.badResponse }
        var request = URLRequest(url: URL(string: "https://api.cloudflare.com/client/v4/accounts/\(accountID)/tokens")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "name": R2Names.token(email: email),
            "policies": [[
                "effect": "allow",
                "resources": [R2Names.resource(accountID: accountID, bucket: bucket): "*"],
                "permission_groups": ids.map { ["id": $0] },
            ]],
        ]
        // The Cloudflare API accepts expires_on. This token is the member's lasting bucket key, so an invite-window expiry would lock them out the day after they join.
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (status, data) = try await perform(request)
        guard status == 200, let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let created = json["result"] as? [String: Any],
              let id = created["id"] as? String,
              let value = created["value"] as? String else { throw S3Error.badResponse }
        return MemberToken(id: id, name: R2Names.token(email: email), accessKeyId: id, secretAccessKey: R2Secret.accessSecret(tokenValue: value))
    }

    public func deleteToken(id: String) async throws {
        var request = URLRequest(url: URL(string: "https://api.cloudflare.com/client/v4/accounts/\(accountID)/tokens/\(id)")!)
        request.httpMethod = "DELETE"
        let (status, _) = try await perform(request)
        guard (200..<300).contains(status) else { throw S3Error.status(status, "") }
    }
}

/// Some revoke markers could not be applied. Their markers stay in the bucket, so the next pass retries them.
public struct TokenRevocationFailure: Error, Equatable, Sendable {
    /// Invites whose token was deleted in this pass.
    public var revoked: [String]
    /// Invites whose token delete failed. Those teammates still have access.
    public var failed: [String]
}

public struct RevokeContext: Equatable, Sendable {
    public var pinnedOwnerKey: String?
    public var team: TeamBody?
    public var devices: [String: String]
    public var mintedTokenIDs: Set<String>

    public init(pinnedOwnerKey: String? = nil, team: TeamBody? = nil, devices: [String: String] = [:], mintedTokenIDs: Set<String> = []) {
        self.pinnedOwnerKey = pinnedOwnerKey
        self.team = team
        self.devices = devices
        self.mintedTokenIDs = mintedTokenIDs
    }
}

public enum TokenRevocation {
    public static func canonical(inviteId: String, tokenId: String, email: String) throws -> Data {
        let object: [String: Any] = [
            "email": TeamEmail.normalize(email),
            "inviteId": inviteId,
            "tokenId": tokenId,
        ]
        return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }

    public static func marker(inviteId: String, tokenId: String, email: String, signer: DeviceKey) throws -> Data {
        let signed = try canonical(inviteId: inviteId, tokenId: tokenId, email: email)
        let object: [String: Any] = [
            "email": TeamEmail.normalize(email),
            "inviteId": inviteId,
            "signature": try signer.sign(signed),
            "signerPublicKey": signer.publicKey,
            "tokenId": tokenId,
        ]
        return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }

    /// A signature from the pinned owner, or from an owner or admin key chained off that pin. The token id is not checked here.
    public static func verified(body: Data, context: RevokeContext) -> (inviteId: String, tokenId: String, email: String)? {
        guard let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
              let tokenId = json["tokenId"] as? String, !tokenId.isEmpty,
              let email = json["email"] as? String,
              let inviteId = json["inviteId"] as? String, !inviteId.isEmpty,
              let signature = json["signature"] as? String,
              let signer = json["signerPublicKey"] as? String,
              let bytes = try? canonical(inviteId: inviteId, tokenId: tokenId, email: email),
              DeviceKey.verify(signature: signature, publicKey: signer, data: bytes),
              mayRevoke(signer, context: context) else { return nil }
        return (inviteId, tokenId, TeamEmail.normalize(email))
    }

    /// Same as `verified`, and the token is one this Mac created.
    public static func authorize(body: Data, context: RevokeContext) -> (inviteId: String, tokenId: String, email: String)? {
        guard let note = verified(body: body, context: context), context.mintedTokenIDs.contains(note.tokenId) else { return nil }
        return note
    }

    public static func mayRevoke(_ signer: String, context: RevokeContext) -> Bool {
        if let pin = context.pinnedOwnerKey, !pin.isEmpty, signer == pin { return true }
        guard let team = context.team else { return false }
        if signer == team.ownerPublicKey { return true }
        guard let email = context.devices.first(where: { $0.value == signer })?.key else { return false }
        let role = team.role(of: email)
        return role == .owner || role == .admin
    }

    /// Applies revoke markers this Mac is allowed to act on. An unreadable or unsigned marker is ignored, so a stranger cannot fail the batch. A token delete that throws stays failed and the marker remains.
    public static func apply(store: any ObjectStore, context: RevokeContext, deleteToken: @Sendable (String) async throws -> Void) async throws -> [String] {
        let heads = try await store.list(prefix: "invites/")
        var done: [String] = []
        var failed: [String] = []
        for head in heads where head.key.hasSuffix(".revoke") {
            guard let body = try? await store.get(head.key).body,
                  let note = authorize(body: body, context: context) else { continue }
            do {
                try await deleteToken(note.tokenId)
            } catch {
                failed.append(note.inviteId)
                continue
            }
            for key in [InviteMetadata.objectKey(note.inviteId), InviteMetadata.redeemedKey(note.inviteId), head.key, DeviceRecord.key(email: note.email)] {
                try? await store.delete(key)
            }
            done.append(note.inviteId)
        }
        if !failed.isEmpty { throw TokenRevocationFailure(revoked: done.sorted(), failed: failed.sorted()) }
        return done.sorted()
    }
}
