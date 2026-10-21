import Foundation

/// Which device key belongs to which person. The email is the object name, and only if the owner-signed roster lists that person.
/// An email written inside some other member file does not count.
public enum DeviceBindings {
    public struct File: Equatable, Sendable {
        public var filename: String
        public var email: String
        public var publicKey: String

        public init(filename: String, email: String, publicKey: String) {
            self.filename = filename
            self.email = email
            self.publicKey = publicKey
        }
    }

    public static func read(root: URL) -> [File] {
        let folder = root.appendingPathComponent(".members")
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        var files: [File] = []
        for name in names where name.hasSuffix(".json") {
            guard let data = try? Data(contentsOf: folder.appendingPathComponent(name)),
                  let record = try? JSONDecoder().decode(DeviceRecord.self, from: data) else { continue }
            files.append(File(filename: name, email: record.email, publicKey: record.publicKey))
        }
        return files
    }

    /// `known` is the key this Mac already stored for that email. A file replaces it only when the signed roster publishes the new key.
    public static func map(files: [File], roster: TeamBody?, known: [String: String] = [:]) -> [String: String] {
        guard let roster else { return [:] }
        let allowed = Set(roster.members.map { TeamEmail.normalize($0.email) })
        var out: [String: String] = [:]
        for file in files {
            guard file.filename.hasSuffix(".json") else { continue }
            let fromName = TeamEmail.normalize(String(file.filename.dropLast(".json".count)))
            guard fromName.contains("@"), allowed.contains(fromName) else { continue }
            guard TeamEmail.normalize(file.email) == fromName, !file.publicKey.isEmpty else { continue }
            if fromName == TeamEmail.normalize(roster.ownerEmail) {
                guard file.publicKey == roster.ownerPublicKey else { continue }
                out[fromName] = roster.ownerPublicKey
                continue
            }
            if let pinned = known[fromName], !pinned.isEmpty, pinned != file.publicKey {
                let published = roster.members.first { TeamEmail.normalize($0.email) == fromName }?.publicKey
                out[fromName] = published == file.publicKey ? file.publicKey : pinned
                continue
            }
            out[fromName] = file.publicKey
        }
        return out
    }
}
