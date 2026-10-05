import Foundation

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
