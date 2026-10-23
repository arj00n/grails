import Crypto
import Foundation

/// Written on the old bucket after a copy. `bucket` is that bucket, so clients still pointed at it stop. `endpoint` is where the library went. No API token.
public struct MoveNotice: Equatable, Sendable, Codable {
    public var endpoint: String
    public var bucket: String
    public var region: String
    public var at: Date

    public static let key = "move.json"
    public static let prompt = "This library has moved. Ask the owner to invite you again."

    public init(endpoint: String, bucket: String, region: String, at: Date) {
        self.endpoint = endpoint
        self.bucket = bucket
        self.region = region
        self.at = at
    }

    public static func read(from store: any ObjectStore) async throws -> MoveNotice? {
        let got: ObjectGet
        do {
            got = try await store.get(key)
        } catch let error as S3Error where error == .notFound {
            return nil
        }
        return try JSONDecoder().decode(MoveNotice.self, from: got.body)
    }
}

public enum MoveError: Error, Equatable {
    case checksum(String)
    case notAllowed
    case notFrozen
}

public enum LibraryMover {
    /// Copies every object except the freeze marker. Each object is read back and checked. The source is left in place.
    /// A pass that finds nothing new stops the copy. A source that keeps changing gets one last copy of the bytes just read.
    public static func copy(from source: any ObjectStore, to destination: any ObjectStore) async throws {
        var settled: [String: Data] = [:]
        for _ in 0..<4 {
            let pass = try await copyPass(from: source, to: destination, settled: settled)
            settled = pass.settled
            if pass.stable { return }
        }
        _ = try await copyPass(from: source, to: destination, settled: settled)
    }

    private static func copyPass(from source: any ObjectStore, to destination: any ObjectStore, settled: [String: Data]) async throws -> (stable: Bool, settled: [String: Data]) {
        var settled = settled
        let heads = try await source.list(prefix: "")
        var moved = false
        for head in heads where head.key != MoveNotice.key {
            let got = try await source.get(head.key)
            let digest = Digests.sha256(got.body)
            if settled[head.key] == digest { continue }
            moved = true
            _ = try await destination.put(head.key, body: got.body, contentType: S3Client.contentType(head.key), ifMatch: nil, ifNoneMatch: nil)
            let back = try await destination.get(head.key)
            guard Digests.sha256(back.body) == digest else { throw MoveError.checksum(head.key) }
            let again = try await source.get(head.key)
            if Digests.sha256(again.body) == digest {
                settled[head.key] = digest
            } else {
                settled[head.key] = nil
            }
        }
        return (!moved, settled)
    }

    public static func freeze(_ store: any ObjectStore, notice: MoveNotice) async throws {
        let body = try JSONEncoder().encode(notice)
        _ = try await store.put(MoveNotice.key, body: body, contentType: "application/json", ifMatch: nil, ifNoneMatch: nil)
    }

    /// The old bucket stays until the owner deletes it, and only after the freeze marker is there.
    public static func deleteSource(store: any ObjectStore, role: LibraryRole) async throws {
        guard TeamPermissions.canDeleteLibrary(role) else { throw MoveError.notAllowed }
        guard try await MoveNotice.read(from: store) != nil else { throw MoveError.notFrozen }
        let heads = try await store.list(prefix: "")
        for head in heads { try await store.delete(head.key) }
    }
}

public enum OwnershipTransfer {
    /// The new owner must already be an admin with a registered device key. Generation stays put. The caller signs the next one.
    public static func propose(body: TeamBody, adminEmail: String, devicePublicKey: String) -> TeamBody? {
        let email = TeamEmail.normalize(adminEmail)
        guard !devicePublicKey.isEmpty, body.role(of: email) == .admin else { return nil }
        var next = body
        next.ownerEmail = email
        next.ownerPublicKey = devicePublicKey
        next.members = body.members.map { member in
            if member.email == email { return TeamMember(email: email, role: .owner) }
            if member.role == .owner { return TeamMember(email: member.email, role: .admin) }
            return member
        }
        return next
    }

    public static func needsToken(role: LibraryRole, cloudflareSaved: Bool) -> Bool {
        role == .owner && !cloudflareSaved
    }
}

/// Addresses that still need a key on the new account. The owner already entered theirs. Secrets are not pushed.
public enum MemberCutover {
    public static func emails(in body: TeamBody) -> [String] {
        body.members.map(\.email).filter { $0 != TeamEmail.normalize(body.ownerEmail) }.sorted()
    }
}

public enum RecoveryError: Error, Equatable {
    case wrongPassword
    case malformed
}

/// Password-encrypted backup of the device signing key. Importing it restores the key. It does not change the roster.
public enum RecoveryFile {
    public static func seal(privateKey: Data, password: String, iterations: Int = InviteCrypto.iterations) throws -> Data {
        let salt = Data((0..<16).map { _ in UInt8.random(in: 0...255) })
        let nonceBytes = Data((0..<12).map { _ in UInt8.random(in: 0...255) })
        let key = SymmetricKey(data: Digests.pbkdf2SHA256(password: Data(password.utf8), salt: salt, iterations: iterations))
        let nonce = try AES.GCM.Nonce(data: nonceBytes)
        let sealed = try AES.GCM.seal(privateKey, using: key, nonce: nonce)
        guard let combined = sealed.combined else { throw RecoveryError.malformed }
        var file = Data("R1".utf8)
        var count = UInt32(iterations).bigEndian
        withUnsafeBytes(of: &count) { file.append(contentsOf: $0) }
        file.append(salt)
        file.append(combined)
        return file
    }

    public static func open(_ file: Data, password: String) throws -> Data {
        guard file.count > 2 + 4 + 16 + 12 + 16, file.prefix(2) == Data("R1".utf8) else { throw RecoveryError.malformed }
        guard let iterations = InviteCrypto.readIterations(file, at: 2) else { throw RecoveryError.malformed }
        let salt = file.subdata(in: 6..<22)
        let combined = file.subdata(in: 22..<file.count)
        let key = SymmetricKey(data: Digests.pbkdf2SHA256(password: Data(password.utf8), salt: salt, iterations: iterations))
        let box = try AES.GCM.SealedBox(combined: combined)
        do { return try AES.GCM.open(box, using: key) } catch { throw RecoveryError.wrongPassword }
    }
}
