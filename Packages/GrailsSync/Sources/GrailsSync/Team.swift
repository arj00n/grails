import Crypto
import Foundation

public enum LibraryRole: String, Codable, Equatable, Sendable {
    case owner, admin, member
}

public enum TeamRoster {
    /// Drops a member. The owner stays.
    public static func removing(_ email: String, from members: [TeamMember]) -> [TeamMember] {
        let address = TeamEmail.normalize(email)
        return members.filter { !(TeamEmail.normalize($0.email) == address && $0.role != .owner) }
    }

    public static func setting(_ role: LibraryRole, email: String, in members: [TeamMember]) -> [TeamMember] {
        let address = TeamEmail.normalize(email)
        return members.map { member in
            TeamEmail.normalize(member.email) == address ? TeamMember(email: member.email, role: role, publicKey: member.publicKey) : member
        }
    }

    /// A failed write puts the previous roster back.
    public static func restored(_ previous: [TeamMember], failed: Bool, next: [TeamMember]) -> [TeamMember] {
        failed ? previous : next
    }
}

public struct TeamMember: Equatable, Sendable, Codable {
    public var email: String
    public var role: LibraryRole
    /// Device key published by an owner or admin signature. Empty on rosters signed before 0.3.10.
    public var publicKey: String?

    public init(email: String, role: LibraryRole, publicKey: String? = nil) {
        self.email = email
        self.role = role
        self.publicKey = publicKey.flatMap { $0.isEmpty ? nil : $0 }
    }
}

public struct TeamBody: Equatable, Sendable, Codable {
    public var generation: Int
    public var ownerEmail: String
    public var ownerPublicKey: String
    public var adminsMayDemoteAdmins: Bool
    public var capGB: Int
    public var maxFileMB: Int
    public var uploadMBPerMinute: Int
    public var formatVersion: Int
    public var minAppVersion: String
    public var members: [TeamMember]

    public static let defaultCapGB = 9
    public static let defaultMaxFileMB = 200
    public static let defaultUploadMBPerMinute = 500
    public static let defaultFormatVersion = 1
    public static let defaultMinAppVersion = "0.3.5"

    public var capBytes: Int64 { Int64(capGB) * 1_000_000_000 }
    public var maxFileBytes: Int64 { Int64(maxFileMB) * 1_000_000 }
    public var uploadBytesPerMinute: Int64 { Int64(uploadMBPerMinute) * 1_000_000 }

    public init(generation: Int, ownerEmail: String, ownerPublicKey: String, adminsMayDemoteAdmins: Bool = false, capGB: Int = defaultCapGB, maxFileMB: Int = defaultMaxFileMB, uploadMBPerMinute: Int = defaultUploadMBPerMinute, formatVersion: Int = defaultFormatVersion, minAppVersion: String = defaultMinAppVersion, members: [TeamMember]) {
        self.generation = generation
        self.ownerEmail = ownerEmail
        self.ownerPublicKey = ownerPublicKey
        self.adminsMayDemoteAdmins = adminsMayDemoteAdmins
        self.capGB = capGB
        self.maxFileMB = maxFileMB
        self.uploadMBPerMinute = uploadMBPerMinute
        self.formatVersion = formatVersion
        self.minAppVersion = minAppVersion
        self.members = members
    }

    public func role(of email: String) -> LibraryRole? {
        let needle = TeamEmail.normalize(email)
        return members.first { TeamEmail.normalize($0.email) == needle }?.role
    }
}

/// Who the person at this Mac is, from the verified roster. The device key wins over the email typed into the bucket form.
public enum TeamIdentity {
    /// Nil when this email is not on the roster. A missing row is not a member.
    public static func role(email: String, devicePublicKey: String, team: TeamBody) -> LibraryRole? {
        if !devicePublicKey.isEmpty, devicePublicKey == team.ownerPublicKey { return .owner }
        if let listed = team.role(of: email) { return listed }
        if !email.isEmpty, TeamEmail.normalize(email) == TeamEmail.normalize(team.ownerEmail) { return .owner }
        return nil
    }
}

public enum TeamKeys {
    /// Copies device keys this Mac already trusts onto the roster the owner or an admin is about to sign.
    /// The owner has no `.members` file. Their device key is `ownerPublicKey`.
    public static func stamp(_ body: TeamBody, devices: [String: String]) -> TeamBody {
        var next = body
        let owner = TeamEmail.normalize(body.ownerEmail)
        next.members = body.members.map { member in
            let email = TeamEmail.normalize(member.email)
            let known = devices[email]
            var key = (known?.isEmpty == false) ? known : member.publicKey
            if email == owner, key == nil || key?.isEmpty == true, !body.ownerPublicKey.isEmpty {
                key = body.ownerPublicKey
            }
            return TeamMember(email: member.email, role: member.role, publicKey: key)
        }
        return next
    }
}

/// Member and Admin are both shown. Admin is only enabled when this person may grant it.
public enum InviteRoles {
    public static let choices: [LibraryRole] = [.member, .admin]
    public static let adminLocked = "Only the owner can invite an admin."

    public static func allows(_ role: LibraryRole, actor: LibraryRole, adminsMayGrantAdmin: Bool) -> Bool {
        TeamPermissions.canInviteRole(actor, role: role, adminsMayGrantAdmin: adminsMayGrantAdmin)
    }

    public static func adminHelp(actor: LibraryRole, adminsMayGrantAdmin: Bool) -> String? {
        allows(.admin, actor: actor, adminsMayGrantAdmin: adminsMayGrantAdmin) ? nil : adminLocked
    }
}

public enum TeamEmail {
    public static func normalize(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

public struct SignedTeam: Equatable, Sendable, Codable {
    public var canonical: String
    public var signature: String
    public var signerPublicKey: String

    public init(canonical: String, signature: String, signerPublicKey: String) {
        self.canonical = canonical
        self.signature = signature
        self.signerPublicKey = signerPublicKey
    }
}

public struct TrustedTeam: Equatable, Sendable {
    public var pinnedOwnerKey: String
    public var body: TeamBody
    public var signed: SignedTeam

    public init(pinnedOwnerKey: String, body: TeamBody, signed: SignedTeam) {
        self.pinnedOwnerKey = pinnedOwnerKey
        self.body = body
        self.signed = signed
    }
}

public struct DeviceKey: Equatable, Sendable {
    public var privateRaw: Data
    public var publicKey: String

    public init() {
        let key = Curve25519.Signing.PrivateKey()
        privateRaw = key.rawRepresentation
        publicKey = Base64URL.encode(key.publicKey.rawRepresentation)
    }

    public init(privateRaw: Data) throws {
        let key = try Curve25519.Signing.PrivateKey(rawRepresentation: privateRaw)
        self.privateRaw = privateRaw
        publicKey = Base64URL.encode(key.publicKey.rawRepresentation)
    }

    public func sign(_ data: Data) throws -> String {
        let key = try Curve25519.Signing.PrivateKey(rawRepresentation: privateRaw)
        return Base64URL.encode(try key.signature(for: data))
    }

    public static func verify(signature: String, publicKey: String, data: Data) -> Bool {
        guard let sig = Base64URL.decode(signature), let pub = Base64URL.decode(publicKey),
              let key = try? Curve25519.Signing.PublicKey(rawRepresentation: pub) else { return false }
        return key.isValidSignature(sig, for: data)
    }
}

extension DeviceKey: CustomStringConvertible {
    public var description: String { "DeviceKey(publicKey: \(publicKey), privateRaw: <redacted>)" }
}

public enum TeamChange: Equatable, Sendable {
    case add(email: String, role: LibraryRole)
    case remove(email: String, role: LibraryRole)
    case reRole(email: String, from: LibraryRole, to: LibraryRole)
    case limits
    case demoteFlag
    case formatGate
    case transfer
}

public enum TeamPermissions {
    public static func canInvite(_ role: LibraryRole) -> Bool { role != .member }

    /// Member is the default. An admin can mint another admin only when the owner has allowed it.
    public static func canInviteRole(_ actor: LibraryRole, role: LibraryRole, adminsMayGrantAdmin: Bool) -> Bool {
        switch role {
        case .owner: return false
        case .member: return actor != .member
        case .admin:
            if actor == .owner { return true }
            if actor == .admin { return adminsMayGrantAdmin }
            return false
        }
    }

    public static func invitableRoles(actor: LibraryRole, adminsMayGrantAdmin: Bool) -> [LibraryRole] {
        [.member, .admin].filter { canInviteRole(actor, role: $0, adminsMayGrantAdmin: adminsMayGrantAdmin) }
    }
    public static func canRevoke(_ role: LibraryRole) -> Bool { role != .member }
    public static func canSetLimits(_ role: LibraryRole) -> Bool { role != .member }
    public static func canPromoteToCanon(_ role: LibraryRole) -> Bool { role != .member }
    public static func canRunSpringCleaning(_ role: LibraryRole) -> Bool { role != .member }
    public static func canEmptyTrash(_ role: LibraryRole) -> Bool { role != .member }
    public static func canConfigureBackup(_ role: LibraryRole) -> Bool { role == .owner }
    public static func canTransfer(_ role: LibraryRole) -> Bool { role == .owner }
    public static func canDeleteLibrary(_ role: LibraryRole) -> Bool { role == .owner }
    public static func canEditDemoteFlag(_ role: LibraryRole) -> Bool { role == .owner }
    public static func canEditFormatGate(_ role: LibraryRole) -> Bool { role == .owner }
    public static func seesTeamControls(_ role: LibraryRole) -> Bool { role != .member }

    /// A person can change their own photo. An owner or admin can change anyone's.
    public static func canSetAvatar(actor: LibraryRole, isSelf: Bool) -> Bool {
        if isSelf { return true }
        return actor == .owner || actor == .admin
    }

    public static func canMakeAdmin(_ actor: LibraryRole, target: LibraryRole) -> Bool {
        actor != .member && target == .member
    }

    /// The owner cannot be removed. An admin can remove another admin only when the owner has allowed it.
    public static func canRemove(_ actor: LibraryRole, target: LibraryRole, adminsMayDemoteAdmins: Bool) -> Bool {
        if target == .owner || actor == .member { return false }
        if actor == .owner { return true }
        if target == .member { return true }
        return adminsMayDemoteAdmins
    }

    public static func allows(_ changes: [TeamChange], actor: LibraryRole, adminsMayDemoteAdmins: Bool) -> Bool {
        if changes.isEmpty { return true }
        if actor == .member { return false }
        for change in changes {
            switch change {
            case .add(_, let role):
                if !canInviteRole(actor, role: role, adminsMayGrantAdmin: adminsMayDemoteAdmins) { return false }
            case .remove(_, let role):
                if !canRemove(actor, target: role, adminsMayDemoteAdmins: adminsMayDemoteAdmins) { return false }
            case .reRole(_, let from, let to):
                if from == .owner || to == .owner {
                    if actor != .owner { return false }
                    continue
                }
                if from == .admin && to == .member && !canRemove(actor, target: .admin, adminsMayDemoteAdmins: adminsMayDemoteAdmins) { return false }
                if actor == .member { return false }
            case .limits:
                if !canSetLimits(actor) { return false }
            case .demoteFlag:
                if !canEditDemoteFlag(actor) { return false }
            case .formatGate:
                if !canEditFormatGate(actor) { return false }
            case .transfer:
                if !canTransfer(actor) { return false }
            }
        }
        return true
    }
}

public enum TeamDiff {
    public static func changes(from old: TeamBody, to new: TeamBody) -> [TeamChange] {
        var out: [TeamChange] = []
        if old.capGB != new.capGB || old.maxFileMB != new.maxFileMB || old.uploadMBPerMinute != new.uploadMBPerMinute { out.append(.limits) }
        if old.adminsMayDemoteAdmins != new.adminsMayDemoteAdmins { out.append(.demoteFlag) }
        if old.formatVersion != new.formatVersion || old.minAppVersion != new.minAppVersion { out.append(.formatGate) }
        if old.ownerEmail != new.ownerEmail || old.ownerPublicKey != new.ownerPublicKey { out.append(.transfer) }
        let before = Dictionary(uniqueKeysWithValues: old.members.map { ($0.email, $0.role) })
        let after = Dictionary(uniqueKeysWithValues: new.members.map { ($0.email, $0.role) })
        for (email, role) in after where before[email] == nil { out.append(.add(email: email, role: role)) }
        for (email, role) in before where after[email] == nil { out.append(.remove(email: email, role: role)) }
        for (email, role) in after where before[email] != nil && before[email] != role {
            out.append(.reRole(email: email, from: before[email]!, to: role))
        }
        return out
    }
}

public enum TeamDocument {
    public static func canonical(_ body: TeamBody) throws -> String {
        let members = body.members
            .map { TeamMember(email: TeamEmail.normalize($0.email), role: $0.role, publicKey: $0.publicKey) }
            .sorted { $0.email < $1.email }
            .map { member -> [String: Any] in
                var row: [String: Any] = ["email": member.email, "role": member.role.rawValue]
                if let key = member.publicKey, !key.isEmpty { row["publicKey"] = key }
                return row
            }
        let object: [String: Any] = [
            "adminsMayDemoteAdmins": body.adminsMayDemoteAdmins,
            "capGB": body.capGB,
            "formatVersion": body.formatVersion,
            "generation": body.generation,
            "maxFileMB": body.maxFileMB,
            "members": members,
            "minAppVersion": body.minAppVersion,
            "ownerEmail": TeamEmail.normalize(body.ownerEmail),
            "ownerPublicKey": body.ownerPublicKey,
            "uploadMBPerMinute": body.uploadMBPerMinute,
        ]
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        return String(decoding: data, as: UTF8.self)
    }

    public static func parse(_ canonical: String) -> TeamBody? {
        guard let data = canonical.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let generation = object["generation"] as? Int,
              let ownerEmail = object["ownerEmail"] as? String,
              let ownerPublicKey = object["ownerPublicKey"] as? String,
              let capGB = object["capGB"] as? Int,
              let maxFileMB = object["maxFileMB"] as? Int,
              let upload = object["uploadMBPerMinute"] as? Int,
              let formatVersion = object["formatVersion"] as? Int,
              let minAppVersion = object["minAppVersion"] as? String,
              let rawMembers = object["members"] as? [[String: Any]] else { return nil }
        let members = rawMembers.compactMap { row -> TeamMember? in
            guard let email = row["email"] as? String, let role = (row["role"] as? String).flatMap(LibraryRole.init(rawValue:)) else { return nil }
            return TeamMember(email: email, role: role, publicKey: row["publicKey"] as? String)
        }
        guard members.count == rawMembers.count else { return nil }
        return TeamBody(
            generation: generation,
            ownerEmail: ownerEmail,
            ownerPublicKey: ownerPublicKey,
            adminsMayDemoteAdmins: object["adminsMayDemoteAdmins"] as? Bool ?? false,
            capGB: capGB,
            maxFileMB: maxFileMB,
            uploadMBPerMinute: upload,
            formatVersion: formatVersion,
            minAppVersion: minAppVersion,
            members: members
        )
    }

    public static func sign(_ body: TeamBody, key: DeviceKey) throws -> SignedTeam {
        var normalized = body
        normalized.ownerEmail = TeamEmail.normalize(body.ownerEmail)
        normalized.members = body.members.map { TeamMember(email: TeamEmail.normalize($0.email), role: $0.role, publicKey: $0.publicKey) }
        let text = try canonical(normalized)
        return SignedTeam(canonical: text, signature: try key.sign(Data(text.utf8)), signerPublicKey: key.publicKey)
    }

    public static func valid(_ body: TeamBody) -> Bool {
        let owners = body.members.filter { $0.role == .owner }
        let emails = body.members.map(\.email)
        return body.generation >= 1
            && owners.count == 1
            && owners[0].email == body.ownerEmail
            && !body.ownerPublicKey.isEmpty
            && body.capGB >= 1
            && body.maxFileMB >= 1
            && body.uploadMBPerMinute >= 1
            && body.formatVersion >= 1
            && !body.minAppVersion.isEmpty
            && Set(emails).count == emails.count
            && emails.allSatisfy { $0.contains("@") }
    }
}

public enum TeamDirectory {
    /// Unsigned or unauthorized edits are ignored. The previous roster stays in force.
    public static func accept(signed: SignedTeam, trusted: TrustedTeam?, devices: [String: String], inviteOwnerKey: String? = nil) -> TrustedTeam? {
        guard let body = TeamDocument.parse(signed.canonical), TeamDocument.valid(body),
              DeviceKey.verify(signature: signed.signature, publicKey: signed.signerPublicKey, data: Data(signed.canonical.utf8))
        else { return nil }
        if trusted == nil {
            // A join pins the owner key from the invite. A library this Mac created has no pin yet and still adopts its own owner signature.
            if let pin = inviteOwnerKey, !pin.isEmpty {
                guard signed.signerPublicKey == pin, body.ownerPublicKey == pin else { return nil }
            } else {
                guard signed.signerPublicKey == body.ownerPublicKey else { return nil }
            }
            return TrustedTeam(pinnedOwnerKey: body.ownerPublicKey, body: body, signed: signed)
        }
        let trusted = trusted!
        guard body.generation > trusted.body.generation else { return nil }
        let ownerSigned = signed.signerPublicKey == trusted.pinnedOwnerKey
        if body.generation != trusted.body.generation + 1 {
            // The owner can catch up several generations. An admin cannot, and an older roster is never written back.
            guard ownerSigned else { return nil }
            if body.ownerPublicKey != trusted.body.ownerPublicKey || body.ownerEmail != trusted.body.ownerEmail {
                guard ownerKeyIsKnown(body, devices: devices) else { return nil }
            }
            return TrustedTeam(pinnedOwnerKey: body.ownerPublicKey, body: body, signed: signed)
        }
        let actor: LibraryRole
        if signed.signerPublicKey == trusted.pinnedOwnerKey {
            actor = .owner
        } else if let email = devices.first(where: { $0.value == signed.signerPublicKey })?.key,
                  trusted.body.role(of: email) == .admin {
            actor = .admin
        } else {
            return nil
        }
        if body.ownerPublicKey != trusted.body.ownerPublicKey || body.ownerEmail != trusted.body.ownerEmail {
            guard actor == .owner, ownerKeyIsKnown(body, devices: devices) else { return nil }
        }
        let changes = TeamDiff.changes(from: trusted.body, to: body)
        guard TeamPermissions.allows(changes, actor: actor, adminsMayDemoteAdmins: trusted.body.adminsMayDemoteAdmins) else { return nil }
        return TrustedTeam(pinnedOwnerKey: body.ownerPublicKey, body: body, signed: signed)
    }

    /// The new owner key is one this Mac already stored, or one the owner published on this signed list.
    private static func ownerKeyIsKnown(_ body: TeamBody, devices: [String: String]) -> Bool {
        let email = TeamEmail.normalize(body.ownerEmail)
        if devices[email] == body.ownerPublicKey { return true }
        return body.members.first { TeamEmail.normalize($0.email) == email }?.publicKey == body.ownerPublicKey
    }
}

public enum TeamFile {
    public static let field = "team"

    /// The roster in `library.json`, when the owner key signed that exact block. Generation is not required to be 1.
    public static func ownerSigned(_ data: Data) -> TeamBody? {
        guard let signed = read(data),
              let body = TeamDocument.parse(signed.canonical),
              TeamDocument.valid(body),
              signed.signerPublicKey == body.ownerPublicKey,
              DeviceKey.verify(signature: signed.signature, publicKey: signed.signerPublicKey, data: Data(signed.canonical.utf8))
        else { return nil }
        return body
    }

    public static func read(_ data: Data) -> SignedTeam? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let team = object[field] as? [String: Any],
              let canonical = team["canonical"] as? String,
              let signature = team["signature"] as? String,
              let signer = team["signerPublicKey"] as? String else { return nil }
        return SignedTeam(canonical: canonical, signature: signature, signerPublicKey: signer)
    }

    public static func write(_ signed: SignedTeam, into data: Data) throws -> Data {
        var object = (try JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
        object[field] = [
            "canonical": signed.canonical,
            "signature": signed.signature,
            "signerPublicKey": signed.signerPublicKey,
        ]
        if let body = TeamDocument.parse(signed.canonical) {
            object["formatVersion"] = body.formatVersion
            object["minAppVersion"] = body.minAppVersion
        }
        return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }

    /// Keeps a verified roster. A file whose role block does not verify is rewritten from the last trusted one.
    public static func reconcile(local: Data, remote: Data?, trusted: inout TrustedTeam?, devices: [String: String], inviteOwnerKey: String? = nil) throws -> Data {
        if let signed = read(local), let next = TeamDirectory.accept(signed: signed, trusted: trusted, devices: devices, inviteOwnerKey: inviteOwnerKey) {
            trusted = next
        }
        if let remote, let signed = read(remote), let next = TeamDirectory.accept(signed: signed, trusted: trusted, devices: devices, inviteOwnerKey: inviteOwnerKey) {
            trusted = next
        }
        guard let trusted else { return local }
        return try write(trusted.signed, into: local)
    }
}
