import Foundation

/// Rewrites person references from display names onto stable member ids. Safe to run again: a token that is already an id is left alone.
public enum IdentityMigration {
    public struct Result: Equatable, Sendable {
        public var items = 0
        public var notes = 0
        public var collections = 0
        public var canvases = 0
        public var smartFolders = 0
        public var invites = 0
        public var profiles = 0
        public var backup: String?
        public var changed: Bool { items + notes + collections + canvases + smartFolders + invites + profiles > 0 }
    }

    /// `backupRoot` is outside the library. Nothing here writes to Drive. The signed team block in `library.json` is copied for the backup and not modified.
    public static func run(in layout: LibraryLayout, backupRoot: URL) throws -> Result {
        let ownerKey = ownerPublicKey(in: layout)
        let devices = deviceRecords(in: layout)
        var profiles = Members.profiles(in: layout)
        let groups = group(profiles: profiles, devices: devices, ownerKey: ownerKey, rosterEmails: rosterEmails(in: layout))
        var result = Result()
        let rewrites = groups.filter(\.needsWrite)
        let referencesNeedIds = libraryTokens(in: layout).contains { token in
            guard let id = resolve(token, profiles: profiles, devices: devices, ownerKey: ownerKey) else { return false }
            return id != token
        }
        guard !rewrites.isEmpty || referencesNeedIds else { return result }

        result.backup = try backup(layout, to: backupRoot).path
        for group in groups where group.needsWrite {
            try Members.adopt(name: group.name, previous: group.previous, email: group.email, memberId: group.id, in: layout, now: group.seen)
            result.profiles += 1
        }
        profiles = Members.profiles(in: layout)
        result.items = try rewriteItems(in: layout, profiles: profiles, devices: devices, ownerKey: ownerKey)
        result.notes = try rewriteNotes(in: layout, profiles: profiles, devices: devices, ownerKey: ownerKey)
        result.collections = try rewriteCollections(in: layout, profiles: profiles, devices: devices, ownerKey: ownerKey)
        result.canvases = try rewriteCanvases(in: layout, profiles: profiles, devices: devices, ownerKey: ownerKey)
        result.smartFolders = try rewriteSmartFolders(in: layout, profiles: profiles, devices: devices, ownerKey: ownerKey)
        result.invites = try rewriteInvites(in: layout, profiles: profiles, devices: devices, ownerKey: ownerKey)
        try stampDeviceIds(in: layout, devices: devices)
        return result
    }

    // MARK: Grouping

    private struct Group {
        var id: String
        var name: String
        var previous: String
        var email: String?
        var seen: Date
        var needsWrite: Bool
    }

    private struct Device {
        var file: String
        var email: String
        var publicKey: String
        var name: String
    }

    private static func group(profiles: [MemberRecord], devices: [Device], ownerKey: String?, rosterEmails: [String]) -> [Group] {
        var claimed = Set<String>()
        var groups: [Group] = []
        func take(_ profile: MemberRecord) { claimed.insert(profile.handle + "|" + profile.id) }

        if let ownerKey, !ownerKey.isEmpty {
            let otherKeys = devices.contains { $0.publicKey != ownerKey } || profiles.contains { !$0.id.isEmpty && $0.id != ownerKey }
            let related = profiles.filter { profile in
                profile.id == ownerKey || (profile.id.isEmpty && !otherKeys)
            }
            if !related.isEmpty || devices.contains(where: { $0.publicKey == ownerKey }) {
                let name = preferredName(related, fallback: devices.first { $0.publicKey == ownerKey }?.name ?? "")
                let previous = related.map(\.handle).first { Handle.normalize($0) != Handle.normalize(name) } ?? related.first?.handle ?? name
                groups.append(Group(id: ownerKey, name: name.isEmpty ? previous : name, previous: previous, email: devices.first { $0.publicKey == ownerKey }?.email, seen: related.map(\.lastSeen).max() ?? .grailsNow, needsWrite: related.contains { $0.id != ownerKey } || related.count > 1))
                related.forEach(take)
            }
        }
        for device in devices where !device.publicKey.isEmpty && !groups.contains(where: { $0.id == device.publicKey }) {
            let related = profiles.filter { profile in
                !claimed.contains(profile.handle + "|" + profile.id) && (profile.id == device.publicKey || matches(profile, device.name))
            }
            let name = preferredName(related, fallback: device.name)
            let previous = related.map(\.handle).first ?? device.name
            groups.append(Group(id: device.publicKey, name: name.isEmpty ? device.email : name, previous: previous, email: device.email, seen: .grailsNow, needsWrite: related.contains { $0.id != device.publicKey }))
            related.forEach(take)
        }
        for profile in profiles where !claimed.contains(profile.handle + "|" + profile.id) {
            let email = rosterMatch(profile, emails: rosterEmails)
            let id = profile.id.isEmpty ? MemberIdentity.deterministic(ownerKey: ownerKey, email: email, handle: profile.handle) : profile.id
            groups.append(Group(id: id, name: profile.name.isEmpty ? profile.handle : profile.name, previous: profile.handle, email: email, seen: profile.lastSeen, needsWrite: profile.id.isEmpty))
        }
        return groups
    }

    private static func matches(_ profile: MemberRecord, _ name: String) -> Bool {
        let key = Handle.normalize(name)
        guard !key.isEmpty else { return false }
        return Handle.normalize(profile.handle) == key || Handle.normalize(profile.name) == key || profile.previousHandles.contains(key)
    }

    private static func preferredName(_ profiles: [MemberRecord], fallback: String) -> String {
        let dated = profiles.sorted { $0.lastSeen > $1.lastSeen }
        if let named = dated.first(where: { !$0.name.isEmpty && Handle.normalize($0.name) != Handle.normalize($0.handle) })?.name { return named }
        if let named = dated.first(where: { !$0.name.isEmpty })?.name { return named }
        return fallback
    }

    // MARK: Rewrite

    private static func resolve(_ token: String, profiles: [MemberRecord], devices: [Device], ownerKey: String?) -> String? {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if profiles.contains(where: { $0.id == trimmed }) { return trimmed }
        if devices.contains(where: { $0.publicKey == trimmed }) { return trimmed }
        if let ownerKey, ownerKey == trimmed { return ownerKey }
        if let profile = Members.profile(matching: trimmed, in: profiles) { return profile.id.isEmpty ? nil : profile.id }
        let key = Handle.normalize(trimmed)
        if let device = devices.first(where: { Handle.normalize($0.name) == key && !key.isEmpty }) { return device.publicKey }
        return nil
    }

    private static func rewrite(_ token: String, profiles: [MemberRecord], devices: [Device], ownerKey: String?) -> String {
        guard let id = resolve(token, profiles: profiles, devices: devices, ownerKey: ownerKey), id != token else { return token }
        return id
    }

    private static func rewriteItems(in layout: LibraryLayout, profiles: [MemberRecord], devices: [Device], ownerKey: String?) throws -> Int {
        var changed = 0
        for folder in ItemScanner.itemFolders(in: layout) {
            let url = folder.appendingPathComponent("item.json")
            guard let data = try? Data(contentsOf: url), var item = try? GrailsJSON.decode(Item.self, from: data) else { continue }
            let added = rewrite(item.addedBy, profiles: profiles, devices: devices, ownerKey: ownerKey)
            let updated = rewrite(item.updatedBy, profiles: profiles, devices: devices, ownerKey: ownerKey)
            guard added != item.addedBy || updated != item.updatedBy else { continue }
            item.addedBy = added
            item.updatedBy = updated
            try AtomicFile.writeJSON(item, to: url)
            changed += 1
        }
        return changed
    }

    private static func rewriteNotes(in layout: LibraryLayout, profiles: [MemberRecord], devices: [Device], ownerKey: String?) throws -> Int {
        var changed = 0
        for note in LibraryNotes.all(in: layout) {
            var next = note
            next.author = rewrite(note.author, profiles: profiles, devices: devices, ownerKey: ownerKey)
            next.mentions = note.mentions.map { rewrite($0, profiles: profiles, devices: devices, ownerKey: ownerKey) }
            guard next != note else { continue }
            try LibraryNotes.write(next, in: layout)
            changed += 1
        }
        return changed
    }

    private static func rewriteCollections(in layout: LibraryLayout, profiles: [MemberRecord], devices: [Device], ownerKey: String?) throws -> Int {
        try rewriteUpdatedBy(in: layout.collectionsDir, profiles: profiles, devices: devices, ownerKey: ownerKey) { data in
            guard var collection = try? GrailsJSON.decode(GrailsCollection.self, from: data) else { return nil }
            let updated = rewrite(collection.updatedBy, profiles: profiles, devices: devices, ownerKey: ownerKey)
            guard updated != collection.updatedBy else { return nil }
            collection.updatedBy = updated
            return try GrailsJSON.encode(collection)
        }
    }

    private static func rewriteCanvases(in layout: LibraryLayout, profiles: [MemberRecord], devices: [Device], ownerKey: String?) throws -> Int {
        try rewriteUpdatedBy(in: layout.canvasDir, profiles: profiles, devices: devices, ownerKey: ownerKey) { data in
            guard var board = try? GrailsJSON.decode(CanvasBoard.self, from: data) else { return nil }
            let updated = rewrite(board.updatedBy, profiles: profiles, devices: devices, ownerKey: ownerKey)
            guard updated != board.updatedBy else { return nil }
            board.updatedBy = updated
            return try GrailsJSON.encode(board)
        }
    }

    private static func rewriteSmartFolders(in layout: LibraryLayout, profiles: [MemberRecord], devices: [Device], ownerKey: String?) throws -> Int {
        try rewriteUpdatedBy(in: layout.smartDir, profiles: profiles, devices: devices, ownerKey: ownerKey) { data in
            guard var folder = try? GrailsJSON.decode(SmartFolder.self, from: data) else { return nil }
            let updated = rewrite(folder.updatedBy, profiles: profiles, devices: devices, ownerKey: ownerKey)
            guard updated != folder.updatedBy else { return nil }
            folder.updatedBy = updated
            return try GrailsJSON.encode(folder)
        }
    }

    private static func rewriteUpdatedBy(in dir: URL, profiles: [MemberRecord], devices: [Device], ownerKey: String?, map: (Data) throws -> Data?) throws -> Int {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        var changed = 0
        for name in names where name.hasSuffix(".json") && !name.contains(" ") && !AtomicFile.isTemp(name) {
            let url = dir.appendingPathComponent(name)
            guard let data = try? Data(contentsOf: url), let next = try map(data) else { continue }
            try AtomicFile.write(next, to: url)
            changed += 1
        }
        return changed
    }

    private static func rewriteInvites(in layout: LibraryLayout, profiles: [MemberRecord], devices: [Device], ownerKey: String?) throws -> Int {
        let dir = layout.root.appendingPathComponent("invites", isDirectory: true)
        let names = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        var changed = 0
        for name in names where name.hasSuffix(".json") {
            let url = dir.appendingPathComponent(name)
            guard let data = try? Data(contentsOf: url),
                  var object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { continue }
            if let existing = object["inviterId"] as? String, !existing.isEmpty { continue }
            let token = (object["adminName"] as? String) ?? ownerKey ?? ""
            guard let id = resolve(token, profiles: profiles, devices: devices, ownerKey: ownerKey) ?? ownerKey, !id.isEmpty else { continue }
            object["inviterId"] = id
            guard let next = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) else { continue }
            try next.write(to: url, options: .atomic)
            changed += 1
        }
        return changed
    }

    private static func stampDeviceIds(in layout: LibraryLayout, devices: [Device]) throws {
        for device in devices where !device.publicKey.isEmpty {
            let url = Members.folder(layout).appendingPathComponent(device.file)
            guard let data = try? Data(contentsOf: url),
                  var object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { continue }
            if object["memberId"] as? String == device.publicKey { continue }
            object["memberId"] = device.publicKey
            guard let next = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) else { continue }
            try next.write(to: url, options: .atomic)
        }
    }

    // MARK: Read

    private static func ownerPublicKey(in layout: LibraryLayout) -> String? {
        guard let data = try? Data(contentsOf: layout.manifestURL),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let team = object["team"] as? [String: Any],
              let canonical = team["canonical"] as? String,
              let body = canonical.data(using: .utf8),
              let parsed = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
              let key = parsed["ownerPublicKey"] as? String, !key.isEmpty else { return nil }
        return key
    }

    /// Emails on the owner-signed roster. The same list on every Mac, so a profile with no device key still gets one id.
    private static func rosterEmails(in layout: LibraryLayout) -> [String] {
        guard let data = try? Data(contentsOf: layout.manifestURL),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let team = object["team"] as? [String: Any],
              let canonical = team["canonical"] as? String,
              let body = canonical.data(using: .utf8),
              let parsed = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
              let members = parsed["members"] as? [[String: Any]] else { return [] }
        return members.compactMap { ($0["email"] as? String)?.lowercased() }
    }

    private static func rosterMatch(_ profile: MemberRecord, emails: [String]) -> String? {
        let handle = Handle.normalize(profile.handle)
        let name = Handle.normalize(profile.name)
        for email in emails {
            let local = Handle.normalize(email.split(separator: "@").first.map(String.init) ?? "")
            if !local.isEmpty, local == handle || local == name { return email }
        }
        return nil
    }

    private static func deviceRecords(in layout: LibraryLayout) -> [Device] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: Members.folder(layout).path)) ?? []
        return names.compactMap { name in
            guard name.hasSuffix(".json"), !name.contains(" ") else { return nil }
            guard let data = try? Data(contentsOf: Members.folder(layout).appendingPathComponent(name)),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let email = object["email"] as? String,
                  let key = object["publicKey"] as? String, !key.isEmpty else { return nil }
            return Device(file: name, email: email, publicKey: key, name: (object["name"] as? String) ?? "")
        }
    }

    private static func libraryTokens(in layout: LibraryLayout) -> [String] {
        var tokens: [String] = []
        for folder in ItemScanner.itemFolders(in: layout) {
            guard let data = try? Data(contentsOf: folder.appendingPathComponent("item.json")),
                  let item = try? GrailsJSON.decode(Item.self, from: data) else { continue }
            tokens.append(item.addedBy)
            tokens.append(item.updatedBy)
        }
        return tokens
    }

    private static func backup(_ layout: LibraryLayout, to root: URL) throws -> URL {
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let dest = root.appendingPathComponent("identity-\(stamp)", isDirectory: true)
        try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: layout.manifestURL.path) {
            try FileManager.default.copyItem(at: layout.manifestURL, to: dest.appendingPathComponent("library.json"))
        }
        let members = dest.appendingPathComponent("members", isDirectory: true)
        try FileManager.default.createDirectory(at: members, withIntermediateDirectories: true)
        let src = Members.folder(layout)
        if FileManager.default.fileExists(atPath: src.path) {
            for file in (try? FileManager.default.contentsOfDirectory(at: src, includingPropertiesForKeys: nil)) ?? [] {
                try FileManager.default.copyItem(at: file, to: members.appendingPathComponent(file.lastPathComponent))
            }
        }
        let items = dest.appendingPathComponent("items", isDirectory: true)
        for folder in ItemScanner.itemFolders(in: layout) {
            let file = folder.appendingPathComponent("item.json")
            guard FileManager.default.fileExists(atPath: file.path) else { continue }
            let slot = items.appendingPathComponent(folder.lastPathComponent, isDirectory: true)
            try FileManager.default.createDirectory(at: slot, withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: file, to: slot.appendingPathComponent("item.json"))
        }
        return dest
    }
}

private extension Members {
    static func profile(matching token: String, in profiles: [MemberRecord]) -> MemberRecord? {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = Handle.normalize(trimmed)
        return profiles.first { record in
            if !record.id.isEmpty, record.id == trimmed { return true }
            if !key.isEmpty, Handle.normalize(record.handle) == key || Handle.normalize(record.name) == key || record.previousHandles.contains(key) { return true }
            return false
        }
    }
}
