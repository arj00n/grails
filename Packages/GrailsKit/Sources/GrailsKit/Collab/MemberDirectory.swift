import Foundation

/// The people in one library, held in memory. Avatars read this instead of `.members` on every tile.
/// `revision` changes when the name, the look, or the photo changes, and that is the cache key.
public struct MemberDirectory: Equatable, Sendable {
    public struct Portrait: Equatable, Sendable {
        public var memberID: String
        public var name: String
        public var look: AvatarLook?
        /// Digest plus the photo file's name and modification time. Empty when there is no photo.
        public var photoStamp: String
        public var stable: Bool
        /// Every token an item might store in `addedBy` for this person.
        public var tokens: Set<String>

        public var usesPhoto: Bool {
            if let look { return look.usesPhoto }
            return !photoStamp.isEmpty
        }

        public var revision: String {
            let mode = look == nil ? "legacy" : (usesPhoto ? "photo" : "blob")
            let tint = look?.tint.map(String.init) ?? "-"
            let character = look?.character.map(String.init) ?? "-"
            return [memberID, name, mode, tint, character, photoStamp].joined(separator: "\u{1f}")
        }
    }

    /// What to draw for one person. `revision` is the member id plus the look and the photo.
    public struct ResolvedAvatar: Equatable, Sendable {
        public var memberID: String
        public var name: String
        public var usesPhoto: Bool
        public var tint: Int?
        public var character: Int?
        public var revision: String
    }

    /// One cache lookup. `reused` is true when this member's revision was already stored.
    public struct Lookup: Equatable, Sendable {
        public var avatar: ResolvedAvatar
        public var reused: Bool
    }

    /// An item and the person who added it. The cache resolves one avatar per item.
    public struct Attribution: Equatable, Sendable {
        public var id: String
        public var addedBy: String

        public init(id: String, addedBy: String) {
            self.id = id
            self.addedBy = addedBy
        }
    }

    private var portraits: [Portrait]

    public init() {
        portraits = []
    }

    public init(records: [MemberRecord], photoStamps: [String: String] = [:]) {
        var byID: [String: Portrait] = [:]
        for record in records {
            let id = Self.memberID(of: record)
            guard !id.isEmpty else { continue }
            let portrait = Portrait(
                memberID: id,
                name: Self.shownName(record),
                look: record.look,
                photoStamp: photoStamps[id] ?? record.avatar ?? "",
                stable: !record.id.isEmpty,
                tokens: Self.tokens(of: record, memberID: id)
            )
            if let existing = byID[id], existing.stable, !portrait.stable { continue }
            byID[id] = portrait
        }
        portraits = byID.values.sorted { $0.memberID < $1.memberID }
    }

    public static func load(in layout: LibraryLayout) -> MemberDirectory {
        let records = Members.profiles(in: layout)
        var stamps: [String: String] = [:]
        for record in records {
            let id = memberID(of: record)
            guard !id.isEmpty else { continue }
            stamps[id] = photoStamp(for: record, in: layout)
        }
        return MemberDirectory(records: records, photoStamps: stamps)
    }

    /// True when a watcher path is a member profile or the photo beside it.
    public static func pathsTouchMembers(_ paths: [String], root: URL) -> Bool {
        let folder = root.appendingPathComponent(".members").path
        return paths.contains { $0 == folder || $0.hasPrefix(folder + "/") }
    }

    public func portrait(matching token: String) -> Portrait? {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let key = Handle.normalize(trimmed)
        let matches = portraits.filter { portrait in
            if portrait.memberID == trimmed || portrait.tokens.contains(trimmed) { return true }
            if !key.isEmpty, portrait.memberID == key || portrait.tokens.contains(key) { return true }
            return false
        }
        return matches.first { $0.memberID == trimmed }
            ?? matches.first { !key.isEmpty && $0.memberID == key }
            ?? matches.first { $0.stable }
            ?? matches.first
    }

    /// Tokens whose avatar changed. A grid refreshes those tiles and leaves the rest.
    public func changedTokens(from previous: MemberDirectory) -> Set<String> {
        let older = Dictionary(previous.portraits.map { ($0.memberID, $0) }, uniquingKeysWith: { a, _ in a })
        let newer = Dictionary(portraits.map { ($0.memberID, $0) }, uniquingKeysWith: { a, _ in a })
        var tokens = Set<String>()
        for (id, portrait) in newer {
            guard older[id]?.revision != portrait.revision else { continue }
            tokens.formUnion(portrait.tokens)
            if let before = older[id] { tokens.formUnion(before.tokens) }
        }
        for (id, portrait) in older where newer[id] == nil {
            tokens.formUnion(portrait.tokens)
        }
        return tokens
    }

    public static func lists(_ token: String, in tokens: Set<String>) -> Bool {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        if tokens.contains(trimmed) { return true }
        let key = Handle.normalize(trimmed)
        return !key.isEmpty && tokens.contains(key)
    }

    static func memberID(of record: MemberRecord) -> String {
        let id = record.id.trimmingCharacters(in: .whitespacesAndNewlines)
        if !id.isEmpty { return id }
        return Handle.normalize(record.handle)
    }

    private static func shownName(_ record: MemberRecord) -> String {
        let stored = record.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return stored.isEmpty ? record.handle : stored
    }

    private static func tokens(of record: MemberRecord, memberID: String) -> Set<String> {
        var tokens: Set<String> = [memberID]
        func add(_ raw: String) {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            tokens.insert(trimmed)
            let key = Handle.normalize(trimmed)
            if !key.isEmpty { tokens.insert(key) }
        }
        add(record.handle)
        add(record.name)
        if !record.id.isEmpty { add(record.id) }
        for previous in record.previousHandles { add(previous) }
        return tokens
    }

    /// Digest, file name, and modification time. A new photo is a new stamp even at the same path.
    static func photoStamp(for record: MemberRecord, in layout: LibraryLayout) -> String {
        let digest = record.avatar ?? ""
        let urls = [
            AvatarStore.memberPhotoURL(id: record.id, in: layout),
            AvatarStore.fileURL(handle: record.handle, in: layout),
        ].compactMap { $0 }
        for url in urls where FileManager.default.fileExists(atPath: url.path) {
            let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
            let modified = (attrs?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
            return "\(digest)|\(url.lastPathComponent)|\(modified)"
        }
        return digest
    }
}

/// Resolved avatars keyed by member id. A new look or photo misses that one entry and leaves the others.
public struct MemberAvatarCache: Sendable {
    private var stored: [String: MemberDirectory.ResolvedAvatar] = [:]

    public init() {}

    public mutating func avatar(for token: String, in directory: MemberDirectory) -> MemberDirectory.Lookup? {
        guard let portrait = directory.portrait(matching: token) else { return nil }
        if let hit = stored[portrait.memberID], hit.revision == portrait.revision {
            return MemberDirectory.Lookup(avatar: hit, reused: true)
        }
        let resolved = Self.resolve(portrait)
        stored[portrait.memberID] = resolved
        return MemberDirectory.Lookup(avatar: resolved, reused: false)
    }

    public mutating func avatars(
        for items: [MemberDirectory.Attribution], in directory: MemberDirectory
    ) -> [String: MemberDirectory.ResolvedAvatar] {
        var out: [String: MemberDirectory.ResolvedAvatar] = [:]
        for item in items {
            if let lookup = avatar(for: item.addedBy, in: directory) {
                out[item.id] = lookup.avatar
            }
        }
        return out
    }

    private static func resolve(_ portrait: MemberDirectory.Portrait) -> MemberDirectory.ResolvedAvatar {
        MemberDirectory.ResolvedAvatar(
            memberID: portrait.memberID,
            name: portrait.name,
            usesPhoto: portrait.usesPhoto,
            tint: portrait.look?.tint,
            character: portrait.look?.character,
            revision: portrait.revision
        )
    }
}
