import Foundation

/// Lossless JSON value, used to preserve fields this version of Stash does not know about.
public enum JSONValue: Codable, Hashable, Sendable {
    case null
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let v = try? c.decode(Bool.self) { self = .bool(v) }
        else if let v = try? c.decode(Int.self) { self = .int(v) }
        else if let v = try? c.decode(Double.self) { self = .double(v) }
        else if let v = try? c.decode(String.self) { self = .string(v) }
        else if let v = try? c.decode([JSONValue].self) { self = .array(v) }
        else if let v = try? c.decode([String: JSONValue].self) { self = .object(v) }
        else { throw DecodingError.dataCorruptedError(in: c, debugDescription: "Unsupported JSON value") }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null: try c.encodeNil()
        case .bool(let v): try c.encode(v)
        case .int(let v): try c.encode(v)
        case .double(let v): try c.encode(v)
        case .string(let v): try c.encode(v)
        case .array(let v): try c.encode(v)
        case .object(let v): try c.encode(v)
        }
    }
}

/// Dynamic coding key, used to read and write fields outside a type's known `CodingKeys`.
struct AnyKey: CodingKey {
    var stringValue: String
    var intValue: Int? { nil }
    init(_ string: String) { stringValue = string }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { nil }
}

enum Extras {
    static func decode(from decoder: Decoder, known: Set<String>) throws -> [String: JSONValue] {
        let all = try decoder.container(keyedBy: AnyKey.self)
        var out: [String: JSONValue] = [:]
        for key in all.allKeys where !known.contains(key.stringValue) {
            out[key.stringValue] = try all.decode(JSONValue.self, forKey: key)
        }
        return out
    }

    static func encode(_ extras: [String: JSONValue], known: Set<String>, to encoder: Encoder) throws {
        var all = encoder.container(keyedBy: AnyKey.self)
        for (key, value) in extras where !known.contains(key) {
            try all.encode(value, forKey: AnyKey(key))
        }
    }
}
