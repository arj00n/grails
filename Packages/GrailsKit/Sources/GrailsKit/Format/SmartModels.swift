import Foundation

/// One condition of a smart folder, e.g. `{ field: "kind", op: "is", value: "video" }`.
public struct SmartRule: Codable, Hashable, Sendable {
    public var field: String
    public var op: String
    public var value: JSONValue

    public init(field: String, op: String, value: JSONValue = .null) {
        self.field = field; self.op = op; self.value = value
    }
}

/// `smart/<ULID>.json` — a saved query that re-evaluates against the index every time it's opened.
public struct SmartFolder: Codable, Hashable, Sendable, Identifiable {
    public var schema: Int
    public var id: String
    public var name: String
    /// "all" (AND) or "any" (OR)
    public var match: String
    public var rules: [SmartRule]
    public var order: String
    public var updatedAt: Date
    public var updatedBy: String
    public var extras: [String: JSONValue]

    public init(
        id: String = ULID().string, name: String, match: String = "all", rules: [SmartRule] = [],
        order: String = FractionalIndex.initial, updatedAt: Date = .grailsNow, updatedBy: String,
        extras: [String: JSONValue] = [:]
    ) {
        self.schema = GrailsKit.schemaVersion
        self.id = id; self.name = name; self.match = match; self.rules = rules; self.order = order
        self.updatedAt = updatedAt; self.updatedBy = updatedBy; self.extras = extras
    }

    enum CodingKeys: String, CodingKey, CaseIterable { case schema, id, name, match, rules, order, updatedAt, updatedBy }
    private static let known = Set(CodingKeys.allCases.map(\.rawValue))

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schema = try c.decodeIfPresent(Int.self, forKey: .schema) ?? 1
        id = try c.decode(String.self, forKey: .id)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        match = try c.decodeIfPresent(String.self, forKey: .match) ?? "all"
        rules = try c.decodeIfPresent([SmartRule].self, forKey: .rules) ?? []
        order = try c.decodeIfPresent(String.self, forKey: .order) ?? FractionalIndex.initial
        updatedAt = try c.decode(Date.self, forKey: .updatedAt)
        updatedBy = try c.decodeIfPresent(String.self, forKey: .updatedBy) ?? ""
        extras = try Extras.decode(from: decoder, known: Self.known)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(schema, forKey: .schema)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(match, forKey: .match)
        try c.encode(rules, forKey: .rules)
        try c.encode(order, forKey: .order)
        try c.encode(updatedAt, forKey: .updatedAt)
        try c.encode(updatedBy, forKey: .updatedBy)
        try Extras.encode(extras, known: Self.known, to: encoder)
    }
}

/// Per-tag presentation (`tags.json`). Tag *membership* lives on items; this file only holds colour and order.
public struct TagMeta: Codable, Hashable, Sendable {
    public var color: String?
    public var order: String?
    /// True when auto-tagging must not suggest this tag in this library (set when it proved too common to be useful,
    /// or when a person deleted the tag).
    public var noAuto: Bool?
    /// Set when this tag was merged into a similar one: new suggestions of it are written as that tag.
    public var mergedInto: String?
    public init(color: String? = nil, order: String? = nil, noAuto: Bool? = nil, mergedInto: String? = nil) {
        self.color = color; self.order = order; self.noAuto = noAuto; self.mergedInto = mergedInto
    }
    var isEmpty: Bool { color == nil && order == nil && noAuto != true && mergedInto == nil }
}

struct TagsFile: Codable {
    var schema = GrailsKit.schemaVersion
    /// keyed by lowercased tag name
    var tags: [String: TagMeta] = [:]
}
