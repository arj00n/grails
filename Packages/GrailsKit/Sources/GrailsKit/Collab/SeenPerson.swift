import Foundation

/// Someone Grails has seen in the library: they opened it (a `.members` record) or added something (`addedBy`).
public struct SeenPerson: Equatable, Hashable, Sendable {
    public var handle: String
    public var items: Int
    public var opened: Bool
    public init(handle: String, items: Int = 0, opened: Bool = false) { self.handle = handle; self.items = items; self.opened = opened }

    /// Presence records and contributor counts folded into one list. A member id and that person's previous handles are one entry.
    public static func merge(members: [MemberRecord], contributors: [(who: String, count: Int)]) -> [SeenPerson] {
        var byKey: [String: SeenPerson] = [:]
        var order: [String] = []
        func key(_ token: String) -> String {
            let norm = Handle.normalize(token)
            for member in members {
                if !member.id.isEmpty, token == member.id { return member.id }
                if !norm.isEmpty, Handle.normalize(member.handle) == norm || Handle.normalize(member.name) == norm || member.previousHandles.contains(norm) {
                    return member.id.isEmpty ? norm : member.id
                }
            }
            return norm.isEmpty ? token.lowercased() : norm
        }
        func label(_ key: String, fallback: String) -> String {
            if let member = members.first(where: { ($0.id.isEmpty ? Handle.normalize($0.handle) : $0.id) == key }) {
                let name = member.name.trimmingCharacters(in: .whitespacesAndNewlines)
                return name.isEmpty ? member.handle : name
            }
            return fallback
        }
        for c in contributors where !c.who.isEmpty {
            let k = key(c.who)
            if byKey[k] == nil { order.append(k); byKey[k] = SeenPerson(handle: label(k, fallback: c.who)) }
            byKey[k]!.items += c.count
            byKey[k]!.handle = label(k, fallback: byKey[k]!.handle)
        }
        for m in members where !m.handle.isEmpty {
            let k = key(m.handle)
            if byKey[k] == nil { order.append(k); byKey[k] = SeenPerson(handle: label(k, fallback: m.handle)) }
            byKey[k]!.opened = true
            byKey[k]!.handle = label(k, fallback: byKey[k]!.handle)
        }
        return order.compactMap { byKey[$0] }
    }
}
