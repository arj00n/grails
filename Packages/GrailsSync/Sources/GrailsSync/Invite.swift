import Crypto
import Foundation
import GrailsEndpoints

public enum InviteLifetime {
    public static let `default`: TimeInterval = 24 * 60 * 60
}

public enum InviteCrypto {
    public static let iterations = 210_000
    /// The PBKDF2 counts an invite or recovery file may carry. The count comes from the blob, so 0 would crash the derivation and 0xFFFFFFFF would hang it.
    public static let acceptedIterations = 100_000...2_000_000

    /// Reads the big-endian count from a blob header and rejects one outside `acceptedIterations`.
    static func readIterations(_ data: Data, at index: Int) -> Int? {
        guard index >= 0, data.count >= index + 4 else { return nil }
        let start = data.startIndex + index
        let bytes = [UInt8](data[start..<(start + 4)])
        let count = Int((UInt32(bytes[0]) << 24) | (UInt32(bytes[1]) << 16) | (UInt32(bytes[2]) << 8) | UInt32(bytes[3]))
        return acceptedIterations.contains(count) ? count : nil
    }
}

public struct JoinLink: Equatable, Sendable {
    public var id: String
    public var blob: String
    /// Set when the sealed blob also lives at `<site>/i/<shortID>` so a redeem can delete it.
    public var shortID: String?

    public init(id: String, blob: String, shortID: String? = nil) {
        self.id = id
        self.blob = blob
        self.shortID = shortID
    }

    public var url: URL {
        if blob.isEmpty, let shortID, InviteRelay.isShortID(shortID) {
            return URL(string: "grails://i/\(shortID)")!
        }
        if InviteBlob.isCompact(blob) {
            var components = URLComponents()
            components.scheme = "grails"
            components.host = "j"
            components.path = "/" + blob
            if let shortID, InviteRelay.isShortID(shortID) {
                components.queryItems = [URLQueryItem(name: "s", value: shortID)]
            }
            return components.url ?? URL(string: "grails://j/\(blob)")!
        }
        var components = URLComponents()
        components.scheme = "grails"
        components.host = "join"
        var items = [URLQueryItem(name: "id", value: id), URLQueryItem(name: "blob", value: blob)]
        if let shortID, InviteRelay.isShortID(shortID) {
            items.append(URLQueryItem(name: "s", value: shortID))
        }
        components.queryItems = items
        return components.url ?? URL(string: "grails://join")!
    }

    public func webURL(page: URL) -> URL {
        let base = page.absoluteString.split(separator: "#").first.map(String.init) ?? page.absoluteString
        if InviteBlob.isCompact(blob) {
            return URL(string: base + "#j=" + blob) ?? page
        }
        return URL(string: base + "#id=" + id + "&blob=" + blob) ?? page
    }

    public static func parse(_ url: URL) -> JoinLink? {
        if url.scheme?.lowercased() == "grails", url.host?.lowercased() == "i" {
            let id = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            guard InviteRelay.isShortID(id) else { return nil }
            return JoinLink(id: id, blob: "", shortID: id)
        }
        if let short = InviteRelay.shortID(in: url) {
            return JoinLink(id: short, blob: "", shortID: short)
        }
        if ["http", "https"].contains(url.scheme?.lowercased() ?? ""), let fragment = url.fragment, !fragment.isEmpty {
            if let token = fragmentValue(fragment, name: "j"), let link = compact(token) { return link }
            if let inner = URL(string: "grails://join?" + fragment), let link = parse(inner) { return link }
            return nil
        }
        if url.scheme?.lowercased() == "grails", url.host?.lowercased() == "j" {
            let path = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            let token = path.removingPercentEncoding ?? path
            guard var link = compact(token) else { return nil }
            if let short = queryValue(url, name: "s") { link.shortID = short }
            return link
        }
        guard url.scheme?.lowercased() == "grails", url.host?.lowercased() == "join",
              let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
              let id = items.first(where: { $0.name == "id" })?.value, !id.isEmpty,
              let blob = items.first(where: { $0.name == "blob" })?.value, !blob.isEmpty else { return nil }
        var link = JoinLink(id: id, blob: blob)
        if let short = items.first(where: { $0.name == "s" })?.value, InviteRelay.isShortID(short) {
            link.shortID = short
        }
        return link
    }

    private static func compact(_ token: String) -> JoinLink? {
        guard let id = InviteBlob.id(in: token) else { return nil }
        return JoinLink(id: id, blob: token)
    }

    private static func queryValue(_ url: URL, name: String) -> String? {
        guard let value = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == name })?.value,
              InviteRelay.isShortID(value) else { return nil }
        return value
    }

    private static func fragmentValue(_ fragment: String, name: String) -> String? {
        for part in fragment.split(separator: "&") {
            let pieces = part.split(separator: "=", maxSplits: 1).map(String.init)
            guard pieces.count == 2, pieces[0] == name else { continue }
            let value = pieces[1].removingPercentEncoding ?? pieces[1]
            if !value.isEmpty { return value }
        }
        return nil
    }

    /// Pulls a join link out of a pasted message. The code is not in the link.
    public static func find(in text: String) -> JoinLink? {
        for part in text.split(whereSeparator: \.isWhitespace) {
            let trimmed = part.trimmingCharacters(in: CharacterSet(charactersIn: "<>\"'.,"))
            if let url = URL(string: trimmed), let join = parse(url) { return join }
        }
        return nil
    }
}

/// Where a bucket invite goes when it arrives at launch or during first-run onboarding.
public enum FirstRunInvite {
    public enum Disposition: Equatable, Sendable {
        /// The app has not chosen a library yet. Keep the link until that choice, or a cold-launch URL is dropped.
        case holdUntilLibraryChoice
        case start(closeOnboardingOnSuccess: Bool)
    }

    /// `libraryChoicePending` stays true until a library is open or first-run onboarding is on screen.
    public static func disposition(onboardingVisible: Bool, libraryChoicePending: Bool, libraryOpen: Bool) -> Disposition {
        if libraryChoicePending, !onboardingVisible, !libraryOpen {
            return .holdUntilLibraryChoice
        }
        let firstRun = onboardingVisible || (libraryChoicePending && !libraryOpen)
        return .start(closeOnboardingOnSuccess: firstRun)
    }
}

/// A pasted invite. A join link wins over a folder link, because both can sit on `/open#`.
public enum PastedLibraryLink: Equatable, Sendable {
    case join
    case folder
    case unknown

    public static func classify(_ text: String) -> PastedLibraryLink {
        if JoinLink.find(in: text) != nil { return .join }
        if text.contains("grails://open") || text.contains("#lib=") { return .folder }
        return .unknown
    }
}

public struct InvitePayload: Equatable, Sendable, Codable {
    public var endpoint: String
    public var region: String
    public var bucket: String
    public var accessKeyId: String
    public var secretAccessKey: String
    public var email: String
    public var libraryId: String
    public var libraryName: String
    public var adminName: String
    public var ownerPublicKey: String
    public var exp: TimeInterval

    public init(endpoint: String, region: String, bucket: String, accessKeyId: String, secretAccessKey: String, email: String, libraryId: String, libraryName: String, adminName: String, ownerPublicKey: String, exp: TimeInterval) {
        self.endpoint = endpoint
        self.region = region
        self.bucket = bucket
        self.accessKeyId = accessKeyId
        self.secretAccessKey = secretAccessKey
        self.email = email
        self.libraryId = libraryId
        self.libraryName = libraryName
        self.adminName = adminName
        self.ownerPublicKey = ownerPublicKey
        self.exp = exp
    }
}

extension InvitePayload: CustomStringConvertible {
    public var description: String { "InvitePayload(email: \(email), bucket: \(bucket), secretAccessKey: <redacted>)" }
}

public enum InviteBlob {
    private static let iterationsFlag: UInt8 = 1 << 0
    private static let compressedFlag: UInt8 = 1 << 1
    private static let idPackedFlag: UInt8 = 1 << 2
    private static let idULIDFlag: UInt8 = 1 << 3
    private static let idUpperFlag: UInt8 = 1 << 4

    public static func seal(_ payload: InvitePayload, code: String, id: String = "", iterations: Int = InviteCrypto.iterations) throws -> String {
        var plain = try InvitePlain.encode(payload)
        var flags: UInt8 = 0
        if let packed = RawDeflate.smaller(plain) {
            plain = packed
            flags |= compressedFlag
        }
        let salt = Data((0..<16).map { _ in UInt8.random(in: 0...255) })
        let nonceBytes = Data((0..<12).map { _ in UInt8.random(in: 0...255) })
        let key = SymmetricKey(data: Digests.pbkdf2SHA256(password: Data(code.utf8), salt: salt, iterations: iterations))
        let nonce = try AES.GCM.Nonce(data: nonceBytes)
        let sealed = try AES.GCM.seal(plain, using: key, nonce: nonce)
        guard let combined = sealed.combined else { throw RedeemError.malformed }
        var blob = Data("G2".utf8)
        var header = flags
        var idBytes = Data()
        if let packed = PackedID.pack(id) {
            header |= idPackedFlag
            if packed.kind == .ulid { header |= idULIDFlag }
            if packed.kind == .uuidUpper { header |= idUpperFlag }
            idBytes = packed.bytes
        } else {
            let utf = Data(id.utf8)
            guard utf.count <= 255 else { throw RedeemError.malformed }
            idBytes = Data([UInt8(utf.count)]) + utf
        }
        if iterations != InviteCrypto.iterations { header |= iterationsFlag }
        blob.append(header)
        blob.append(idBytes)
        if iterations != InviteCrypto.iterations {
            var count = UInt32(iterations).bigEndian
            withUnsafeBytes(of: &count) { blob.append(contentsOf: $0) }
        }
        blob.append(salt)
        blob.append(combined)
        return Base64URL.encode(blob)
    }

    /// The previous JSON seal. Old links still open. New links do not use it.
    static func sealLegacy(_ payload: InvitePayload, code: String, iterations: Int = InviteCrypto.iterations) throws -> String {
        let plain = try JSONEncoder().encode(payload)
        let salt = Data((0..<16).map { _ in UInt8.random(in: 0...255) })
        let nonceBytes = Data((0..<12).map { _ in UInt8.random(in: 0...255) })
        let key = SymmetricKey(data: Digests.pbkdf2SHA256(password: Data(code.utf8), salt: salt, iterations: iterations))
        let nonce = try AES.GCM.Nonce(data: nonceBytes)
        let sealed = try AES.GCM.seal(plain, using: key, nonce: nonce)
        guard let combined = sealed.combined else { throw RedeemError.malformed }
        var blob = Data("G1".utf8)
        var count = UInt32(iterations).bigEndian
        withUnsafeBytes(of: &count) { blob.append(contentsOf: $0) }
        blob.append(salt)
        blob.append(combined)
        return Base64URL.encode(blob)
    }

    public static func isCompact(_ blob: String) -> Bool {
        guard let data = Base64URL.decode(blob), data.count >= 2 else { return false }
        return data.prefix(2) == Data("G2".utf8)
    }

    /// True for a G1 or G2 seal. Plain JSON is not sealed, and must not be uploaded.
    public static func isSealed(_ blob: String) -> Bool {
        guard let data = Base64URL.decode(blob), data.count >= 2 else { return false }
        let magic = data.prefix(2)
        return magic == Data("G1".utf8) || magic == Data("G2".utf8)
    }

    /// The invite id carried in a compact blob. Nil for a legacy blob.
    public static func id(in blob: String) -> String? {
        guard let data = Base64URL.decode(blob) else { return nil }
        return headerID(data)
    }

    public static func open(_ blob: String, code: String) throws -> InvitePayload {
        guard let data = Base64URL.decode(blob), data.count > 2 else { throw RedeemError.malformed }
        if data.prefix(2) == Data("G1".utf8) { return try openLegacy(data, code: code) }
        if data.prefix(2) == Data("G2".utf8) { return try openCompact(data, code: code) }
        throw RedeemError.malformed
    }

    private static func headerID(_ data: Data) -> String? {
        guard data.count > 3, data.prefix(2) == Data("G2".utf8) else { return nil }
        let flags = data[data.startIndex + 2]
        var index = 3
        if flags & idPackedFlag != 0 {
            guard data.count >= index + 16 else { return nil }
            let bytes = data.subdata(in: index..<(index + 16))
            if flags & idULIDFlag != 0 { return PackedID.ulid(bytes) }
            return PackedID.uuid(bytes, upper: flags & idUpperFlag != 0)
        }
        guard data.count > index else { return nil }
        let count = Int(data[data.startIndex + index])
        index += 1
        guard data.count >= index + count else { return nil }
        return String(data: data.subdata(in: index..<(index + count)), encoding: .utf8)
    }

    private static func openCompact(_ data: Data, code: String) throws -> InvitePayload {
        guard data.count > 3 + 16 + 12 + 16 else { throw RedeemError.malformed }
        let flags = data[data.startIndex + 2]
        var index = 3
        if flags & idPackedFlag != 0 {
            index += 16
        } else {
            guard data.count > index else { throw RedeemError.malformed }
            let count = Int(data[data.startIndex + index])
            index += 1 + count
        }
        let iterations: Int
        if flags & iterationsFlag != 0 {
            guard let count = InviteCrypto.readIterations(data, at: index) else { throw RedeemError.malformed }
            iterations = count
            index += 4
        } else {
            iterations = InviteCrypto.iterations
        }
        guard data.count >= index + 16 + 12 + 16 else { throw RedeemError.malformed }
        let salt = data.subdata(in: index..<(index + 16))
        let combined = data.subdata(in: (index + 16)..<data.count)
        let plain = try unseal(combined, code: code, salt: salt, iterations: iterations)
        let bytes: Data
        if flags & compressedFlag != 0 {
            guard let inflated = RawDeflate.decompress(plain) else { throw RedeemError.malformed }
            bytes = inflated
        } else {
            bytes = plain
        }
        return try InvitePlain.decode(bytes)
    }

    private static func openLegacy(_ data: Data, code: String) throws -> InvitePayload {
        guard data.count > 2 + 4 + 16 + 12 + 16 else { throw RedeemError.malformed }
        guard let iterations = InviteCrypto.readIterations(data, at: 2) else { throw RedeemError.malformed }
        let salt = data.subdata(in: 6..<22)
        let combined = data.subdata(in: 22..<data.count)
        let plain = try unseal(combined, code: code, salt: salt, iterations: iterations)
        guard let payload = try? JSONDecoder().decode(InvitePayload.self, from: plain) else { throw RedeemError.malformed }
        return payload
    }

    private static func unseal(_ combined: Data, code: String, salt: Data, iterations: Int) throws -> Data {
        let key = SymmetricKey(data: Digests.pbkdf2SHA256(password: Data(code.utf8), salt: salt, iterations: iterations))
        let box = try AES.GCM.SealedBox(combined: combined)
        do { return try AES.GCM.open(box, using: key) } catch { throw RedeemError.wrongCode }
    }
}

public enum InviteCode {
    public static func generate(digits: [Int]) -> String {
        String(digits.prefix(6).map { Character(String($0 % 10)) })
    }

    public static func random() -> String {
        generate(digits: (0..<6).map { _ in Int.random(in: 0...9) })
    }

    public static func normalize(_ raw: String) -> String? {
        let digits = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard digits.count == 6, digits.allSatisfy(\.isNumber) else { return nil }
        return digits
    }
}

public struct JoinCodeGate: Equatable, Sendable, Codable {
    public static let limit = 5
    public private(set) var failures: Int

    public init(failures: Int = 0) { self.failures = min(max(failures, 0), Self.limit) }

    public var isLocked: Bool { failures >= Self.limit }

    public mutating func recordWrong() {
        if failures < Self.limit { failures += 1 }
    }
}

public struct DeviceRecord: Equatable, Sendable, Codable {
    public var email: String
    public var publicKey: String
    public var deviceName: String
    public var inviteId: String
    public var name: String
    /// Stable member id. The device public key when this record was written by a current Grails.
    public var memberId: String

    public init(email: String, publicKey: String, deviceName: String, inviteId: String, name: String = "", memberId: String = "") {
        self.email = email
        self.publicKey = publicKey
        self.deviceName = deviceName
        self.inviteId = inviteId
        self.name = name
        self.memberId = memberId.isEmpty ? publicKey : memberId
    }

    public static func key(email: String) -> String { ".members/\(TeamEmail.normalize(email)).json" }

    enum CodingKeys: String, CodingKey { case email, publicKey, deviceName, inviteId, name, memberId }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        email = try c.decode(String.self, forKey: .email)
        publicKey = try c.decode(String.self, forKey: .publicKey)
        deviceName = try c.decode(String.self, forKey: .deviceName)
        inviteId = try c.decode(String.self, forKey: .inviteId)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        memberId = try c.decodeIfPresent(String.self, forKey: .memberId) ?? publicKey
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(email, forKey: .email)
        try c.encode(publicKey, forKey: .publicKey)
        try c.encode(deviceName, forKey: .deviceName)
        try c.encode(inviteId, forKey: .inviteId)
        try c.encode(name, forKey: .name)
        if !memberId.isEmpty { try c.encode(memberId, forKey: .memberId) }
    }
}

public enum MemberFile {
    public static func authorizedKey(for objectKey: String, team: TeamBody?) -> String? {
        let name = (objectKey as NSString).lastPathComponent
        guard name.hasSuffix(".json") else { return nil }
        let email = TeamEmail.normalize(String(name.dropLast(".json".count)))
        return team?.members.first { TeamEmail.normalize($0.email) == email }?.publicKey
    }

    /// A first file is learned as-is. A later file keeps the key this Mac already has unless the signed roster published the new one.
    public static func incoming(local: Data?, remote: Data, authorizedPublicKey: String?) -> Data {
        guard let local, !local.isEmpty else { return remote }
        return merge(local: local, remote: remote, authorizedPublicKey: authorizedPublicKey)
    }

    /// Keeps this Mac's display name and the device key it already stored.
    public static func merge(local: Data, remote: Data, authorizedPublicKey: String? = nil) -> Data {
        guard var left = try? JSONDecoder().decode(DeviceRecord.self, from: local) else { return local }
        guard let right = try? JSONDecoder().decode(DeviceRecord.self, from: remote) else { return local }
        if left.name.isEmpty { left.name = right.name }
        if left.memberId.isEmpty { left.memberId = right.memberId.isEmpty ? right.publicKey : right.memberId }
        if left.publicKey == right.publicKey || (authorizedPublicKey != nil && authorizedPublicKey == right.publicKey) {
            left.publicKey = right.publicKey
        }
        left.deviceName = right.deviceName
        left.inviteId = right.inviteId
        left.email = right.email
        return (try? JSONEncoder().encode(left)) ?? local
    }
}

public struct InviteMetadata: Equatable, Sendable, Codable {
    public var id: String
    public var email: String
    public var exp: TimeInterval
    public var tokenId: String
    public var deviceName: String?
    /// The sealed join blob, so an admin can copy the link again. The code is not stored.
    public var blob: String?
    /// Member id of the person who issued the invite. The invited address is still the email; this id does not change if they rename.
    public var inviterId: String?

    public init(id: String, email: String, exp: TimeInterval, tokenId: String, deviceName: String? = nil, blob: String? = nil, inviterId: String? = nil) {
        self.id = id
        self.email = email
        self.exp = exp
        self.tokenId = tokenId
        self.deviceName = deviceName
        self.blob = blob
        self.inviterId = inviterId
    }

    /// The bucket copy never carries the sealed blob. This Mac keeps that locally so Copy link still works.
    public func forBucket() -> InviteMetadata {
        var copy = self
        copy.blob = nil
        return copy
    }

    public static func objectKey(_ id: String) -> String { "invites/\(id).json" }
    public static func redeemedKey(_ id: String) -> String { "invites/\(id).redeemed" }
    public static func revokeKey(_ id: String) -> String { "invites/\(id).revoke" }
}

public struct IssuedInvite: Equatable, Sendable {
    public var id: String
    public var code: String
    public var link: JoinLink
    public var metadata: InviteMetadata
    public var signedTeam: SignedTeam
    public var payload: InvitePayload

    public init(id: String, code: String, link: JoinLink, metadata: InviteMetadata, signedTeam: SignedTeam, payload: InvitePayload) {
        self.id = id
        self.code = code
        self.link = link
        self.metadata = metadata
        self.signedTeam = signedTeam
        self.payload = payload
    }
}

extension IssuedInvite: CustomStringConvertible {
    public var description: String { "IssuedInvite(id: \(id), email: \(metadata.email), code: <redacted>, secret: <redacted>)" }
}

public enum InviteIssuer {
    public static func issue(email: String, libraryId: String, libraryName: String, adminName: String, endpoint: String, region: String, bucket: String, accessKeyId: String, secretAccessKey: String, tokenId: String, ownerPublicKey: String, team: TeamBody, signer: DeviceKey, now: Date, code: String, id: String, role: LibraryRole = .member, iterations: Int = InviteCrypto.iterations) throws -> IssuedInvite {
        let exp = now.addingTimeInterval(InviteLifetime.default).timeIntervalSince1970
        let payload = InvitePayload(endpoint: endpoint, region: region, bucket: bucket, accessKeyId: accessKeyId, secretAccessKey: secretAccessKey, email: TeamEmail.normalize(email), libraryId: libraryId, libraryName: libraryName, adminName: adminName, ownerPublicKey: ownerPublicKey, exp: exp)
        let blob = try InviteBlob.seal(payload, code: code, id: id, iterations: iterations)
        var next = team
        next.generation += 1
        let normalized = TeamEmail.normalize(email)
        let granted: LibraryRole = role == .owner ? .member : role
        if next.role(of: normalized) == nil {
            next.members.append(TeamMember(email: normalized, role: granted))
        }
        let signed = try TeamDocument.sign(next, key: signer)
        let metadata = InviteMetadata(id: id, email: normalized, exp: exp, tokenId: tokenId, blob: blob, inviterId: signer.publicKey)
        return IssuedInvite(id: id, code: code, link: JoinLink(id: id, blob: blob), metadata: metadata, signedTeam: signed, payload: payload)
    }
}

public enum RedeemError: Error, Equatable {
    case locked
    case wrongCode
    case expired
    case emailMismatch
    case alreadyRedeemed
    case otherDevice
    case malformed
}

public struct RedeemedInvite: Equatable, Sendable {
    public var payload: InvitePayload
    public var device: DeviceRecord

    public init(payload: InvitePayload, device: DeviceRecord) {
        self.payload = payload
        self.device = device
    }
}

public enum InviteRedeemer {
    public static func redeem(link: JoinLink, code: String, confirmedEmail: String, device: DeviceKey, deviceName: String, name: String = "", gate: inout JoinCodeGate, store: any ObjectStore, now: Date) async throws -> RedeemedInvite {
        if gate.isLocked { throw RedeemError.locked }
        guard let normalizedCode = InviteCode.normalize(code) else {
            gate.recordWrong()
            throw gate.isLocked ? RedeemError.locked : RedeemError.wrongCode
        }
        let payload: InvitePayload
        do { payload = try InviteBlob.open(link.blob, code: normalizedCode) }
        catch let error as RedeemError {
            if error == .wrongCode {
                gate.recordWrong()
                throw gate.isLocked ? RedeemError.locked : RedeemError.wrongCode
            }
            throw error
        }
        if now.timeIntervalSince1970 > payload.exp { throw RedeemError.expired }
        guard TeamEmail.normalize(confirmedEmail) == payload.email else { throw RedeemError.emailMismatch }
        let memberKey = DeviceRecord.key(email: payload.email)
        if let existing = try? await store.get(memberKey),
           let record = try? JSONDecoder().decode(DeviceRecord.self, from: existing.body),
           record.publicKey != device.publicKey {
            throw RedeemError.otherDevice
        }
        let record = DeviceRecord(email: payload.email, publicKey: device.publicKey, deviceName: deviceName, inviteId: link.id, name: DisplayName.normalized(name) ?? "")
        let redeemed = try JSONEncoder().encode(record)
        // A second redeem loses the conditional create and does not keep the secret.
        do {
            _ = try await store.put(InviteMetadata.redeemedKey(link.id), body: redeemed, contentType: "application/json", ifMatch: nil, ifNoneMatch: "*")
        } catch S3Error.preconditionFailed {
            if let current = try? await store.get(InviteMetadata.redeemedKey(link.id)),
               let previous = try? JSONDecoder().decode(DeviceRecord.self, from: current.body),
               previous.publicKey == device.publicKey {
                // the winning device is retrying after a crash
            } else {
                throw RedeemError.alreadyRedeemed
            }
        }
        _ = try? await store.put(memberKey, body: try JSONEncoder().encode(record), contentType: "application/json", ifMatch: nil, ifNoneMatch: "*")
        return RedeemedInvite(payload: payload, device: record)
    }
}

public enum BucketInviteMessage {
    public static let quarantine = "xattr -d com.apple.quarantine /Applications/Grails.app"
    /// The install link in the message. Nil when the build has no site; the message then skips that step.
    public static var site: String? { GrailsEndpoints.site?.absoluteString }

    public static func make(library: String, link: URL, from sender: String, site: String? = BucketInviteMessage.site) -> (subject: String, body: String) {
        var lines = ["Hi,", "", "\(sender) invited you to \(library) on Grails.", ""]
        var steps: [String] = []
        if let site { steps.append("Install Grails: \(site)") }
        steps.append("If macOS blocks it, run: \(quarantine)")
        steps.append("Open this link: \(link.absoluteString)")
        lines += steps.enumerated().map { "\($0.offset + 1). \($0.element)" }
        lines.append("macOS will ask for your login password once. Click Always Allow.")
        lines += ["", "The link works once and expires in 24 hours. The join code comes separately.", ""]
        if !sender.isEmpty { lines.append(sender) }
        return ("Join \(library) on Grails", lines.joined(separator: "\n"))
    }
}

public struct ListedInvite: Equatable, Sendable {
    public enum State: Equatable, Sendable { case pending, redeemed(deviceName: String) }
    public var id: String
    public var email: String
    public var state: State
    public var tokenId: String
    public var blob: String?
    public var exp: TimeInterval
}

public enum InviteRevocation {
    /// Writes the revoke marker and deletes the invite object. A failed put leaves the invite where it was.
    public static func commit(_ invite: ListedInvite, store: any ObjectStore, signer: DeviceKey) async throws {
        let marker = try TokenRevocation.marker(inviteId: invite.id, tokenId: invite.tokenId, email: invite.email, signer: signer)
        _ = try await store.put(InviteMetadata.revokeKey(invite.id), body: marker, contentType: "application/json", ifMatch: nil, ifNoneMatch: nil)
        try await store.delete(InviteMetadata.objectKey(invite.id))
    }
}

public enum InviteBlobs {
    public struct Kept: Equatable, Sendable {
        public var id: String
        public var blob: String
        public init(id: String, blob: String) { self.id = id; self.blob = blob }
    }

    /// Removes sealed blobs already stored under `invites/`. The caller keeps them locally first.
    public static func strip(store: any ObjectStore) async throws -> [Kept] {
        let heads = try await store.list(prefix: "invites/")
        var kept: [Kept] = []
        for head in heads where head.key.hasSuffix(".json") {
            let got = try await store.get(head.key)
            guard var object = try JSONSerialization.jsonObject(with: got.body) as? [String: Any],
                  let blob = object["blob"] as? String, !blob.isEmpty,
                  let id = object["id"] as? String, !id.isEmpty else { continue }
            kept.append(Kept(id: id, blob: blob))
            object.removeValue(forKey: "blob")
            let body = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
            _ = try await store.put(head.key, body: body, contentType: "application/json", ifMatch: got.etag, ifNoneMatch: nil)
        }
        return kept
    }
}

public enum LocalInviteLinks {
    public static func remember(id: String, blob: String, directory: URL) throws {
        guard safe(id), InviteBlob.isSealed(blob) else { return }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data(blob.utf8).write(to: directory.appendingPathComponent(id), options: .atomic)
    }

    public static func recall(id: String, directory: URL) -> String? {
        guard safe(id) else { return nil }
        guard let text = try? String(contentsOf: directory.appendingPathComponent(id), encoding: .utf8),
              InviteBlob.isSealed(text) else { return nil }
        return text
    }

    private static func safe(_ id: String) -> Bool {
        !id.isEmpty && !id.contains("/") && !id.contains("\\") && !id.contains("..")
    }
}

public enum InviteList {
    public static func parse(objects: [ObjectHead], bodies: [String: Data], trustedRevokeIDs: Set<String>? = nil) -> [ListedInvite] {
        var metas: [String: InviteMetadata] = [:]
        var redeemed: [String: DeviceRecord] = [:]
        var revoked = Set<String>()
        for head in objects where head.key.hasSuffix(".revoke") {
            let name = (head.key as NSString).lastPathComponent
            let id = String(name.dropLast(".revoke".count))
            if id.isEmpty { continue }
            if let trustedRevokeIDs {
                if trustedRevokeIDs.contains(id) { revoked.insert(id) }
            } else {
                revoked.insert(id)
            }
        }
        for head in objects {
            guard let data = bodies[head.key] else { continue }
            if head.key.hasSuffix(".json"), let meta = try? JSONDecoder().decode(InviteMetadata.self, from: data) {
                metas[meta.id] = meta
            } else if head.key.hasSuffix(".redeemed"), let record = try? JSONDecoder().decode(DeviceRecord.self, from: data) {
                let id = head.key.replacingOccurrences(of: "invites/", with: "").replacingOccurrences(of: ".redeemed", with: "")
                redeemed[id] = record
            }
        }
        return metas.keys.sorted().compactMap { id in
            guard !revoked.contains(id), let meta = metas[id] else { return nil }
            if let record = redeemed[id] {
                return ListedInvite(id: id, email: meta.email, state: .redeemed(deviceName: record.deviceName), tokenId: meta.tokenId, blob: meta.blob, exp: meta.exp)
            }
            return ListedInvite(id: id, email: meta.email, state: .pending, tokenId: meta.tokenId, blob: meta.blob, exp: meta.exp)
        }
    }
}

public enum InviteGate {
    public enum Block: Equatable, Sendable {
        case invalid, yourself, owner, pending, member
    }

    public static func block(email: String, actorEmail: String, ownerEmail: String, members: [String], pending: [String]) -> Block? {
        let address = TeamEmail.normalize(email)
        if address.isEmpty || !looksLikeEmail(address) { return .invalid }
        if address == TeamEmail.normalize(actorEmail) { return .yourself }
        if !ownerEmail.isEmpty, address == TeamEmail.normalize(ownerEmail) { return .owner }
        if pending.map(TeamEmail.normalize).contains(address) { return .pending }
        if members.map(TeamEmail.normalize).contains(address) { return .member }
        return nil
    }

    /// Empty stays quiet. Anything else names the block.
    public static func shown(_ block: Block?, email: String) -> String? {
        if email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return nil }
        guard let block else { return nil }
        return message(block)
    }

    public static func message(_ block: Block) -> String {
        switch block {
        case .invalid: "Check the email"
        case .yourself: "That's your email"
        case .owner: "That's the owner's email"
        case .pending: "Already invited"
        case .member: "Already on the team"
        }
    }

    private static func looksLikeEmail(_ address: String) -> Bool {
        let parts = address.split(separator: "@", omittingEmptySubsequences: false)
        guard parts.count == 2, !parts[0].isEmpty else { return false }
        return parts[1].contains(".")
    }
}

public struct InviteShare: Equatable, Sendable {
    public var email: String
    public var role: LibraryRole
    public var link: String
    public var message: String
    public var code: String
    public var expires: Date

    public static let channelNote = "Send the link and the code on different channels."

    public init(email: String, role: LibraryRole, link: String, message: String, code: String, expires: Date) {
        self.email = email
        self.role = role
        self.link = link
        self.message = message
        self.code = code
        self.expires = expires
    }

    public static func make(library: String, link: URL, code: String, from: String, expires: Date, email: String, role: LibraryRole) -> InviteShare {
        let text = BucketInviteMessage.make(library: library, link: link, from: from)
        return InviteShare(email: email, role: role, link: link.absoluteString, message: text.subject + "\n\n" + text.body, code: code, expires: expires)
    }

    /// Short enough to fit a person row: "Expires tomorrow, 4:02 AM".
    public static func expiry(_ date: Date, timeZone: TimeZone, now: Date = Date()) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let day: String
        if calendar.isDate(date, inSameDayAs: now) {
            day = "today"
        } else if let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)),
                  calendar.isDate(date, inSameDayAs: tomorrow) {
            day = "tomorrow"
        } else if let week = calendar.date(byAdding: .day, value: 7, to: calendar.startOfDay(for: now)),
                  date >= calendar.startOfDay(for: now), date < week {
            day = formatted(date, timeZone: timeZone, format: "EEEE")
        } else {
            day = formatted(date, timeZone: timeZone, format: "d MMM")
        }
        let time = formatted(date, timeZone: timeZone, format: "h:mm a")
        return "Expires \(day), \(time)"
    }

    private static func formatted(_ date: Date, timeZone: TimeZone, format: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = format
        return formatter.string(from: date)
            .replacingOccurrences(of: "\u{202F}", with: " ")
            .replacingOccurrences(of: "\u{00A0}", with: " ")
    }
}
