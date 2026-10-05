import Foundation

/// Someone the owner means to have in the library: what they typed (an email or a name), when the invite went out, and which Grails
/// name ("handle") is theirs once they turn up. Handles are free text people choose for themselves, so a match is only ever a guess
/// from the name; the owner can link or unlink one by hand.
public struct Teammate: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var contact: String
    /// The handle the owner linked to this person (wins over any guess).
    public var handle: String?
    /// Handles the owner said are not this person.
    public var notHandles: [String]
    public var invitedAt: Date?
    public var addedAt: Date

    public init(id: String = UUID().uuidString, contact: String, handle: String? = nil, notHandles: [String] = [], invitedAt: Date? = nil, addedAt: Date = Date()) {
        self.id = id; self.contact = contact; self.handle = handle; self.notHandles = notHandles; self.invitedAt = invitedAt; self.addedAt = addedAt
    }

    public var email: String? { Self.looksLikeEmail(contact) ? contact.lowercased() : nil }

    public static func looksLikeEmail(_ s: String) -> Bool {
        let parts = s.split(separator: "@", omittingEmptySubsequences: false)
        guard parts.count == 2, !parts[0].isEmpty, parts[1].contains("."), !parts[1].hasPrefix("."), !parts[1].hasSuffix(".") else { return false }
        return !s.contains(where: { $0.isWhitespace || "<>,;\"".contains($0) })
    }

    /// Handles this person would plausibly pick, from their email or name: `ana.lopez@studio.com` → ana.lopez, ana-lopez, analopez, ana.
    public var likelyHandles: Set<String> { Self.likelyHandles(for: contact) }

    public static func likelyHandles(for contact: String) -> Set<String> {
        var base = contact
        if looksLikeEmail(contact) {
            base = String(contact.split(separator: "@")[0])
            if let plus = base.firstIndex(of: "+") { base = String(base[..<plus]) }
        }
        let words = base.lowercased().split(whereSeparator: { " ._-".contains($0) }).map { Handle.normalize(String($0)) }.filter { !$0.isEmpty }
        guard !words.isEmpty else { return [] }
        var out: Set<String> = [Handle.normalize(base), words.joined(separator: "."), words.joined(separator: "-"), words.joined(separator: "_"), words.joined()]
        if words[0].count >= 3 { out.insert(words[0]) }
        if words.count >= 2 { out.insert(String(words[0].prefix(1)) + words[words.count - 1]) }
        return out.filter { !$0.isEmpty }
    }
}

/// Someone Grails has seen in the library: they opened it (a `.members` record) or added something (`addedBy`).
public struct SeenPerson: Equatable, Hashable, Sendable {
    public var handle: String
    public var items: Int
    public var opened: Bool
    public init(handle: String, items: Int = 0, opened: Bool = false) { self.handle = handle; self.items = items; self.opened = opened }

    /// Presence records and contributor counts folded into one list, one entry per handle.
    public static func merge(members: [MemberRecord], contributors: [(who: String, count: Int)]) -> [SeenPerson] {
        var byKey: [String: SeenPerson] = [:]
        var order: [String] = []
        func key(_ h: String) -> String { Handle.normalize(h).isEmpty ? h.lowercased() : Handle.normalize(h) }
        for c in contributors where !c.who.isEmpty {
            let k = key(c.who)
            if byKey[k] == nil { order.append(k); byKey[k] = SeenPerson(handle: c.who) }
            byKey[k]!.items += c.count
        }
        for m in members where !m.handle.isEmpty {
            let k = key(m.handle)
            if byKey[k] == nil { order.append(k); byKey[k] = SeenPerson(handle: m.handle) }
            byKey[k]!.opened = true
        }
        return order.compactMap { byKey[$0] }
    }
}

/// The owner's checklist for one library.
public struct InviteList: Codable, Equatable, Sendable {
    public var libraryID: String
    public var teammates: [Teammate]

    public init(libraryID: String, teammates: [Teammate] = []) { self.libraryID = libraryID; self.teammates = teammates }

    /// Adds what was typed or pasted, split at commas, semicolons and lines: each part's email address if it has one (a pasted
    /// "Ana <ana@studio.com>" gives the address), or else the part as a name. People already on the list are skipped. Returns who was added.
    @discardableResult
    public mutating func add(_ text: String, now: Date = Date()) -> [Teammate] {
        var entries: [String] = []
        for part in text.split(whereSeparator: { ",;\n".contains($0) }) {
            let emails = part.split(whereSeparator: { " \t<>()\"".contains($0) }).map(String.init).filter(Teammate.looksLikeEmail)
            let name = part.trimmingCharacters(in: .whitespaces)
            entries += emails.isEmpty ? (name.isEmpty ? [] : [name]) : emails
        }
        var added: [Teammate] = []
        for entry in entries {
            let contact = String(entry.prefix(120))
            guard !teammates.contains(where: { $0.contact.lowercased() == contact.lowercased() }) else { continue }
            let t = Teammate(contact: contact, addedAt: now)
            teammates.append(t)
            added.append(t)
        }
        return added
    }

    public mutating func remove(_ id: String) { teammates.removeAll { $0.id == id } }

    public mutating func markInvited(_ ids: [String], at date: Date = Date()) {
        for i in teammates.indices where ids.contains(teammates[i].id) { teammates[i].invitedAt = date }
    }

    /// Links a handle to a person (taking it off anyone else), or with nil unlinks: the guessed handle is then remembered as "not them".
    public mutating func link(_ id: String, handle: String?, unlinking current: String? = nil) {
        guard let i = teammates.firstIndex(where: { $0.id == id }) else { return }
        if let handle {
            for j in teammates.indices where j != i && teammates[j].handle == handle { teammates[j].handle = nil }
            teammates[i].handle = handle
            teammates[i].notHandles.removeAll { $0 == handle }
        } else {
            if let current, !teammates[i].notHandles.contains(current) { teammates[i].notHandles.append(current) }
            teammates[i].handle = nil
        }
    }

    public struct Row: Equatable, Identifiable, Sendable {
        public enum Status: Equatable, Sendable { case notInvited, invited, joined }
        public var teammate: Teammate
        public var status: Status
        /// The handle they joined as.
        public var handle: String?
        /// Matched by name, not linked by the owner.
        public var guessed: Bool
        public var seen: SeenPerson?
        public var id: String { teammate.id }
    }

    public struct Roster: Equatable, Sendable {
        public var rows: [Row]
        /// People in the library who aren't on the list (and aren't the owner): they joined some other way, or under another name.
        public var others: [SeenPerson]
        public var joinedCount: Int { rows.filter { $0.status == .joined }.count }
    }

    /// The checklist against who has actually turned up. A person is Joined when their linked handle has been seen, or, with no link,
    /// when exactly one handle seen fits their email or name and fits no one else on the list.
    public func roster(seen: [SeenPerson], ownHandle: String) -> Roster {
        let own = Handle.normalize(ownHandle)
        func key(_ h: String) -> String { Handle.normalize(h).isEmpty ? h.lowercased() : Handle.normalize(h) }
        let people = seen.filter { key($0.handle) != own || own.isEmpty }
        var byKey: [String: SeenPerson] = [:]
        for p in people { byKey[key(p.handle)] = p }
        var claimed = Set<String>()
        var matched: [String: (SeenPerson, Bool)] = [:]
        for t in teammates {
            if let h = t.handle, let p = byKey[key(h)] { matched[t.id] = (p, false); claimed.insert(key(h)) }
        }
        for h in teammates.compactMap(\.handle) { claimed.insert(key(h)) }
        let open = teammates.filter { $0.handle == nil }
        var fits: [String: [String]] = [:]      // seen key → teammate ids it could be
        var options: [String: [String]] = [:]   // teammate id → seen keys
        for t in open {
            let blocked = Set(t.notHandles.map(key))
            let keys = t.likelyHandles.filter { byKey[$0] != nil && !claimed.contains($0) && !blocked.contains($0) }
            options[t.id] = Array(keys)
            for k in keys { fits[k, default: []].append(t.id) }
        }
        for t in open {
            guard let keys = options[t.id], keys.count == 1, let k = keys.first, fits[k]?.count == 1, let p = byKey[k] else { continue }
            matched[t.id] = (p, true)
            claimed.insert(k)
        }
        let rows = teammates.map { t -> Row in
            if let (p, guessed) = matched[t.id] { return Row(teammate: t, status: .joined, handle: p.handle, guessed: guessed, seen: p) }
            return Row(teammate: t, status: t.invitedAt == nil ? .notInvited : .invited, handle: nil, guessed: false, seen: nil)
        }
        let others = people.filter { !claimed.contains(key($0.handle)) }
        return Roster(rows: rows, others: others)
    }
}

/// The checklist is kept in this Mac's preferences, per library: it holds the owner's own notes about people (email addresses), which
/// shouldn't sit in a folder every member, and every future member, can read. It survives relaunch; it doesn't follow the owner to
/// another Mac.
public enum InviteStore {
    static func key(_ libraryID: String) -> String { "collab.invites.\(libraryID)" }

    public static func load(libraryID: String, defaults: UserDefaults = .standard) -> InviteList {
        defaults.data(forKey: key(libraryID)).flatMap { try? JSONDecoder().decode(InviteList.self, from: $0) } ?? InviteList(libraryID: libraryID)
    }

    public static func save(_ list: InviteList, defaults: UserDefaults = .standard) {
        guard !list.libraryID.isEmpty, let data = try? JSONEncoder().encode(list) else { return }
        defaults.set(data, forKey: key(list.libraryID))
    }
}
