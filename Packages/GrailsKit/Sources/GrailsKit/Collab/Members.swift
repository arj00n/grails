import Foundation

/// "This person has opened the library": one small file per handle in `.members/`, written by their own Grails. Each person writes only
/// their own file, so two Macs never edit the same one. It lets the owner see someone has joined before they've added anything.
public struct MemberRecord: Codable, Equatable, Sendable {
    /// Stable member id. Empty on a presence file that has not been migrated yet. Never changes once set.
    public var id: String
    public var handle: String
    /// The name shown in the footer, Team tab, and item info. Older files omit it and mean the handle.
    public var name: String
    /// Handles this person used before the current name, so old `addedBy` strings still resolve.
    public var previousHandles: [String]
    public var firstSeen: Date
    public var lastSeen: Date
    /// SHA-256 of the profile photo.
    public var avatar: String?
    /// How their avatar is drawn. Kept in memory here and stored in `<id>.look.json`, not in this file.
    /// A 0.3.8 client rewrites the profile and drops keys it does not know. Older files may still carry it inline.
    /// With no look at all: a photo if there is one, otherwise the generated blob from the id.
    public var look: AvatarLook?
    public init(handle: String, firstSeen: Date, lastSeen: Date, name: String? = nil, avatar: String? = nil, id: String = "", previousHandles: [String] = [], look: AvatarLook? = nil) {
        self.id = id
        self.handle = handle
        self.name = name ?? handle
        self.previousHandles = previousHandles
        self.firstSeen = firstSeen
        self.lastSeen = lastSeen
        self.avatar = avatar
        self.look = look
    }

    enum CodingKeys: String, CodingKey { case id, handle, name, previousHandles, firstSeen, lastSeen, avatar, look }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? ""
        handle = try c.decode(String.self, forKey: .handle)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? handle
        previousHandles = try c.decodeIfPresent([String].self, forKey: .previousHandles) ?? []
        firstSeen = try c.decode(Date.self, forKey: .firstSeen)
        lastSeen = try c.decode(Date.self, forKey: .lastSeen)
        avatar = try c.decodeIfPresent(String.self, forKey: .avatar)
        // a look written by a newer or broken client never costs the whole profile
        look = (try? c.decodeIfPresent(AvatarLook.self, forKey: .look)) ?? nil
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        if !id.isEmpty { try c.encode(id, forKey: .id) }
        try c.encode(handle, forKey: .handle)
        try c.encode(name, forKey: .name)
        if !previousHandles.isEmpty { try c.encode(previousHandles, forKey: .previousHandles) }
        try c.encode(firstSeen, forKey: .firstSeen)
        try c.encode(lastSeen, forKey: .lastSeen)
        try c.encodeIfPresent(avatar, forKey: .avatar)
    }
}

public enum MemberNameError: Error, Equatable {
    case taken
}

public enum Members {
    public static func folder(_ layout: LibraryLayout) -> URL { layout.root.appendingPathComponent(".members", isDirectory: true) }

    static func fileName(_ handle: String) -> String? {
        let n = Handle.normalize(handle)
        return n.isEmpty ? nil : n + ".json"
    }

    /// Notes that `handle` opened the library. Writes at most once a day per person (`minInterval`), so a shared drive isn't
    /// churned by every launch. A new display name writes immediately. A person who already has a stable profile is updated there, not copied into a second file. Returns whether it wrote.
    @discardableResult
    public static func record(handle: String, in layout: LibraryLayout, now: Date = Date(), minInterval: TimeInterval = 86_400, name: String? = nil) throws -> Bool {
        guard fileName(handle) != nil else { return false }
        let shown = display(name) ?? handle
        if var existing = profile(matching: handle, in: layout), !existing.id.isEmpty {
            let nameChanged = existing.name != shown
            guard now.timeIntervalSince(existing.lastSeen) >= minInterval || nameChanged else { return false }
            if nameChanged { existing.previousHandles = aliases(existing.previousHandles, adding: existing.name, existing.handle) }
            existing.name = shown
            existing.handle = Handle.normalize(shown).isEmpty ? existing.handle : Handle.normalize(shown)
            existing.lastSeen = now
            try write(existing, in: layout)
            return true
        }
        let url = folder(layout).appendingPathComponent(fileName(handle)!)
        var record = MemberRecord(handle: handle, firstSeen: now, lastSeen: now, name: shown)
        if let data = try? Data(contentsOf: url), let old = try? GrailsJSON.decode(MemberRecord.self, from: data) {
            let nameChanged = old.name != shown
            guard now.timeIntervalSince(old.lastSeen) >= minInterval || old.handle != handle || nameChanged else { return false }
            record.firstSeen = old.firstSeen
            record.avatar = old.avatar
            record.look = loadLook(beside: url) ?? old.look
            record.id = old.id
            record.previousHandles = old.previousHandles
            if nameChanged { record.previousHandles = aliases(record.previousHandles, adding: old.name, old.handle) }
        }
        try write(record, in: layout)
        return true
    }

    /// Changes the display name. The member id stays, items and notes are not rewritten, and the old handle remains an alias.
    /// A rename looks up the member by id. Matching another person's handle does not take their profile.
    @discardableResult
    public static func adopt(name: String, previous: String, email: String? = nil, memberId: String? = nil, in layout: LibraryLayout, now: Date = Date()) throws -> String {
        let shown = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !shown.isEmpty, fileName(shown) != nil else { return memberId ?? "" }
        let prior = previous.trimmingCharacters(in: .whitespacesAndNewlines)
        let proposed = memberId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        var profile: MemberRecord
        if !proposed.isEmpty {
            profile = profiles(in: layout).first { $0.id == proposed }
                ?? MemberRecord(handle: Handle.normalize(prior).isEmpty ? Handle.normalize(shown) : Handle.normalize(prior), firstSeen: now, lastSeen: now, name: shown, id: proposed)
            profile.id = proposed
        } else {
            profile = Self.profile(matching: prior, in: layout) ?? Self.profile(matchingEmail: email, in: layout) ?? MemberRecord(handle: Handle.normalize(prior).isEmpty ? Handle.normalize(shown) : Handle.normalize(prior), firstSeen: now, lastSeen: now, name: shown)
            if profile.id.isEmpty {
                profile.id = deviceKey(email: email, in: layout) ?? ULID().string
            }
        }
        let shownKey = Handle.normalize(shown)
        if profiles(in: layout).contains(where: { other in
            other.id != profile.id && !other.id.isEmpty && (Handle.normalize(other.name) == shownKey || Handle.normalize(other.handle) == shownKey)
        }) {
            throw MemberNameError.taken
        }
        let carried = photoData(for: profile, also: [prior, shown, profile.handle, profile.name], in: layout)
        if profile.avatar == nil, let carried { profile.avatar = AvatarStore.digest(of: carried) }
        profile.previousHandles = aliases(profile.previousHandles, adding: prior, profile.handle, profile.name, shown)
        profile.name = shown
        profile.handle = Handle.normalize(shown)
        profile.lastSeen = now
        if profile.firstSeen == .distantPast { profile.firstSeen = now }
        try write(profile, in: layout)
        if let carried, let url = AvatarStore.memberPhotoURL(id: profile.id, in: layout) {
            try AtomicFile.write(carried, to: url)
        }
        removeLegacyProfiles(absorbedBy: profile, in: layout)
        stampDeviceName(shown, previous: prior, email: email, memberId: profile.id, in: layout)
        return profile.id
    }

    /// This Mac's own profile. On a team library only the owner's Mac may bind to the owner's profile: a member whose handle,
    /// or whose only profile on disk, is the owner's gets nil instead, and the caller keeps their own name.
    public static func ownProfile(handle: String, email: String?, devicePublicKey: String?, in layout: LibraryLayout) -> MemberRecord? {
        let all = profiles(in: layout)
        let owner = IdentityMigration.ownerPublicKey(in: layout)
        let isOwner = isOwnerMac(email: email, devicePublicKey: devicePublicKey, owner: owner, in: layout)
        let allowed = all.filter { isOwner || $0.id != owner }
        if isOwner, let owner, let mine = all.first(where: { $0.id == owner }) { return mine }
        let device = (devicePublicKey ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        for key in [deviceKey(email: email, in: layout) ?? "", device] where !key.isEmpty {
            if let mine = allowed.first(where: { $0.id == key }) { return mine }
        }
        if let mine = profile(matching: handle, in: allowed) { return mine }
        return all.count == 1 ? allowed.first : nil
    }

    /// 0.3.11 bound a member's Mac to the owner's profile. A rename there rewrote the owner's profile and stamped the owner's id
    /// on this member's device file. This puts the device file back on its own key, removes the local copy of the owner's profile
    /// so the next sync downloads the owner's own version, and returns the name this Mac should use. Only bucket libraries carry
    /// a signed team, so the removal never reaches a shared drive. Nil when this Mac is the owner or nothing was borrowed.
    @discardableResult
    public static func releaseBorrowedOwner(handle: String, email: String?, devicePublicKey: String?, in layout: LibraryLayout) -> String? {
        guard let owner = IdentityMigration.ownerPublicKey(in: layout),
              !isOwnerMac(email: email, devicePublicKey: devicePublicKey, owner: owner, in: layout) else { return nil }
        var wanted = (email ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let device = (devicePublicKey ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let dir = folder(layout)
        var stamped = false
        var ownName = ""
        let names = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        for file in names where file.hasSuffix(".json") && !file.contains(" ") && !AtomicFile.isTemp(file) {
            let url = dir.appendingPathComponent(file)
            guard let data = try? Data(contentsOf: url),
                  var object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                  let fileEmail = (object["email"] as? String)?.lowercased(),
                  let key = object["publicKey"] as? String, !key.isEmpty, key != owner else { continue }
            guard (!wanted.isEmpty && fileEmail == wanted) || (!device.isEmpty && key == device) else { continue }
            if wanted.isEmpty { wanted = fileEmail }
            ownName = ((object["name"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard (object["memberId"] as? String) == owner else { continue }
            object["memberId"] = key
            if let next = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) {
                try? next.write(to: url, options: .atomic)
                stamped = true
            }
        }
        let borrowedHandle = profile(matching: handle, in: layout)?.id == owner
        guard stamped || borrowedHandle else { return nil }
        let ownerName = profile(matching: owner, in: layout).map { Handle.normalize($0.name) }
        if stamped, let url = profileURL(id: owner, in: layout) {
            try? FileManager.default.removeItem(at: url)
        }
        if !ownName.isEmpty, stamped || Handle.normalize(ownName) != ownerName { return ownName }
        let local = wanted.split(separator: "@").first.map(String.init) ?? ""
        return local.isEmpty ? nil : local
    }

    private static func isOwnerMac(email: String?, devicePublicKey: String?, owner: String?, in layout: LibraryLayout) -> Bool {
        guard let owner else { return true }
        let device = (devicePublicKey ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !device.isEmpty { return device == owner }
        let wanted = (email ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return !wanted.isEmpty && wanted == IdentityMigration.ownerEmail(in: layout)
    }

    /// The name to show for a member id, a current name, or a previous handle.
    public static func displayName(for author: String, in layout: LibraryLayout) -> String {
        let trimmed = author.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return author }
        if let profile = profile(matching: trimmed, in: layout) {
            let stored = profile.name.trimmingCharacters(in: .whitespacesAndNewlines)
            return stored.isEmpty ? trimmed : stored
        }
        if let named = namedDevice(matching: trimmed, in: layout) { return named }
        return trimmed
    }

    /// Handles and display names found in `.members`, including device entries that are not presence records.
    public static func listedNames(in layout: LibraryLayout) -> [String] {
        var out: [String] = []
        for object in objects(in: layout) {
            if let handle = object["handle"] as? String, !handle.isEmpty { out.append(handle) }
            if let stored = object["name"] as? String, !stored.isEmpty { out.append(stored) }
        }
        return out
    }

    private static func display(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func objects(in layout: LibraryLayout) -> [[String: Any]] {
        let dir = folder(layout)
        let names = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        return names.compactMap { name in
            guard name.hasSuffix(".json"), !AtomicFile.isTemp(name), !name.contains(" ") else { return nil }
            guard let data = try? Data(contentsOf: dir.appendingPathComponent(name)) else { return nil }
            return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        }
    }

    /// Profiles with a stable id, plus legacy presence files that do not have one yet.
    public static func profiles(in layout: LibraryLayout) -> [MemberRecord] {
        records(in: layout)
    }

    public static func profile(matching token: String, in layout: LibraryLayout) -> MemberRecord? {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let key = Handle.normalize(trimmed)
        let matches = records(in: layout).filter { record in
            if !record.id.isEmpty, record.id == trimmed { return true }
            if !key.isEmpty, Handle.normalize(record.handle) == key || Handle.normalize(record.name) == key { return true }
            if !key.isEmpty, record.previousHandles.contains(key) { return true }
            return false
        }
        return matches.first { !$0.id.isEmpty } ?? matches.first
    }

    static func isSafeMemberId(_ id: String) -> Bool {
        !id.isEmpty && id.count <= 128 && id.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
    }

    static func profileURL(id: String, in layout: LibraryLayout) -> URL? {
        guard isSafeMemberId(id) else { return nil }
        return folder(layout).appendingPathComponent(id + ".json")
    }

    private static func records(in layout: LibraryLayout) -> [MemberRecord] {
        let dir = folder(layout)
        let names = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        return names.compactMap { loadRecord(named: $0, in: dir) }
    }

    /// Writes a profile back where it came from: the stable `<id>.json`, or the legacy handle file.
    static func save(_ record: MemberRecord, in layout: LibraryLayout) throws {
        try write(record, in: layout)
    }

    /// Sets this person's avatar choice on their own profile. A person with no profile yet gets a presence file holding it.
    /// `usesPhoto` decides what is drawn, so a photo removed on one Mac stops showing before the file itself has synced away.
    @discardableResult
    public static func setLook(_ look: AvatarLook, handle: String, in layout: LibraryLayout, now: Date = Date()) throws -> MemberRecord? {
        guard fileName(handle) != nil else { return nil }
        var record = profile(matching: handle, in: layout) ?? MemberRecord(handle: Handle.normalize(handle), firstSeen: now, lastSeen: now, name: handle)
        record.look = look
        record.lastSeen = now
        try FileManager.default.createDirectory(at: folder(layout), withIntermediateDirectories: true)
        try write(record, in: layout)
        return record
    }

    private static func write(_ record: MemberRecord, in layout: LibraryLayout) throws {
        let url: URL
        if let stable = profileURL(id: record.id, in: layout) {
            url = stable
        } else if let file = fileName(record.handle) {
            url = folder(layout).appendingPathComponent(file)
        } else {
            return
        }
        try AtomicFile.writeJSON(record, to: url)
        let lookFile = lookURL(beside: url)
        if let look = record.look {
            try AtomicFile.writeJSON(look, to: lookFile)
        } else if FileManager.default.fileExists(atPath: lookFile.path) {
            try? FileManager.default.removeItem(at: lookFile)
        }
    }

    static func lookURL(beside profile: URL) -> URL {
        let base = profile.deletingPathExtension().lastPathComponent
        return profile.deletingLastPathComponent().appendingPathComponent(base + ".look.json")
    }

    private static func loadLook(beside profile: URL) -> AvatarLook? {
        guard let data = try? Data(contentsOf: lookURL(beside: profile)) else { return nil }
        return try? GrailsJSON.decode(AvatarLook.self, from: data)
    }

    private static func loadRecord(named name: String, in dir: URL) -> MemberRecord? {
        guard name.hasSuffix(".json"), !name.hasSuffix(".look.json"), !AtomicFile.isTemp(name), !name.contains(" ") else { return nil }
        let url = dir.appendingPathComponent(name)
        guard let data = try? Data(contentsOf: url), var record = try? GrailsJSON.decode(MemberRecord.self, from: data) else { return nil }
        if let look = loadLook(beside: url) { record.look = look }
        return record
    }

    private static func aliases(_ existing: [String], adding tokens: String...) -> [String] {
        var out = existing
        for token in tokens {
            let key = Handle.normalize(token)
            guard !key.isEmpty, !out.contains(key) else { continue }
            out.append(key)
        }
        return out
    }

    /// A device file's display name, when `token` is that device's email, public key, member id, or current name.
    private static func namedDevice(matching token: String, in layout: LibraryLayout) -> String? {
        let wanted = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !wanted.isEmpty else { return nil }
        let email = wanted.lowercased()
        let nameKey = Handle.normalize(wanted)
        for object in objects(in: layout) {
            let fileEmail = (object["email"] as? String)?.lowercased()
            let publicKey = object["publicKey"] as? String
            let member = (object["memberId"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            let stored = (object["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let nameMatch = !nameKey.isEmpty && !stored.isEmpty && Handle.normalize(stored) == nameKey
            guard fileEmail == email || publicKey == wanted || member == wanted || nameMatch else { continue }
            if let member, member != wanted, let profile = profile(matching: member, in: layout) {
                let profileName = profile.name.trimmingCharacters(in: .whitespacesAndNewlines)
                if !profileName.isEmpty { return profileName }
            }
            if !stored.isEmpty { return stored }
        }
        return nil
    }

    private static func profile(matchingEmail email: String?, in layout: LibraryLayout) -> MemberRecord? {
        guard let key = deviceKey(email: email, in: layout) else { return nil }
        return profile(matching: key, in: layout)
    }

    private static func deviceKey(email: String?, in layout: LibraryLayout) -> String? {
        let wanted = (email ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !wanted.isEmpty else { return nil }
        for object in objects(in: layout) {
            guard let fileEmail = object["email"] as? String, fileEmail.lowercased() == wanted else { continue }
            let key = (object["memberId"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? (object["publicKey"] as? String)
            if let key, !key.isEmpty { return key }
        }
        return nil
    }

    private static func photoData(for profile: MemberRecord, also tokens: [String], in layout: LibraryLayout) -> Data? {
        var urls: [URL] = []
        if let stable = AvatarStore.memberPhotoURL(id: profile.id, in: layout) { urls.append(stable) }
        for token in tokens {
            if let url = AvatarStore.fileURL(handle: token, in: layout) { urls.append(url) }
        }
        for url in urls {
            if let data = try? Data(contentsOf: url), !data.isEmpty { return data }
        }
        return nil
    }

    private static func removeLegacyProfiles(absorbedBy profile: MemberRecord, in layout: LibraryLayout) {
        let dir = folder(layout)
        let keep = profileURL(id: profile.id, in: layout)?.lastPathComponent ?? fileName(profile.handle)
        let keptPhoto = memberPhotoName(profile.id)
        let names = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        for name in names where name.hasSuffix(".json") && name != keep && !name.contains(" ") {
            let url = dir.appendingPathComponent(name)
            guard let data = try? Data(contentsOf: url), let old = try? GrailsJSON.decode(MemberRecord.self, from: data) else { continue }
            let samePerson = !old.id.isEmpty && old.id == profile.id
            let legacyCopy = old.id.isEmpty && profile.previousHandles.contains(Handle.normalize(old.handle))
            guard samePerson || legacyCopy else { continue }
            try? FileManager.default.removeItem(at: url)
            try? FileManager.default.removeItem(at: lookURL(beside: url))
            if let photo = AvatarStore.fileURL(handle: old.handle, in: layout), photo.lastPathComponent != keptPhoto {
                try? FileManager.default.removeItem(at: photo)
            }
        }
    }

    private static func memberPhotoName(_ id: String) -> String? {
        guard isSafeMemberId(id) else { return nil }
        return id + ".avatar.jpg"
    }

    private static func stampDeviceName(_ display: String, previous: String, email: String?, memberId: String = "", in layout: LibraryLayout) {
        let dir = folder(layout)
        let names = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        let oldKey = Handle.normalize(previous)
        let wanted = (email ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        for file in names where file.hasSuffix(".json") && !file.contains(" ") && !AtomicFile.isTemp(file) {
            let url = dir.appendingPathComponent(file)
            guard let data = try? Data(contentsOf: url),
                  var object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                  let fileEmail = object["email"] as? String else { continue }
            let current = ((object["name"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let emailMatch = !wanted.isEmpty && fileEmail.lowercased() == wanted
            // with an email, only this person's own device file; a name can be shared with someone else's
            let nameMatch = wanted.isEmpty && !previous.isEmpty && (current == previous || Handle.normalize(current) == oldKey)
            guard emailMatch || nameMatch else { continue }
            var dirty = current != display
            if dirty { object["name"] = display }
            if !memberId.isEmpty, (object["memberId"] as? String) != memberId {
                object["memberId"] = memberId
                dirty = true
            }
            guard dirty, let next = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) else { continue }
            try? next.write(to: url, options: .atomic)
        }
    }

    /// Everyone who has opened the library with a version of Grails that records it. Reading a teammate's record can make the sync
    /// client fetch it (a few hundred bytes), so call this off the main thread.
    public static func all(in layout: LibraryLayout) -> [MemberRecord] {
        let dir = folder(layout)
        let names = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        return names.sorted().compactMap { loadRecord(named: $0, in: dir) }
    }
}
