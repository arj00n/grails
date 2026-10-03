import Foundation

/// The one place that decides how Stash reads and writes JSON on disk.
/// Sorted keys + pretty printing keep files diff-friendly and byte-stable across rewrites.
public enum StashJSON {
    private static let fractional = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
    private static let whole = Date.ISO8601FormatStyle()

    public static func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var c = encoder.singleValueContainer()
            try c.encode(date.formatted(fractional))
        }
        return try encoder.encode(value)
    }

    public static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let c = try decoder.singleValueContainer()
            let s = try c.decode(String.self)
            if let d = try? fractional.parse(s) { return d }
            if let d = try? whole.parse(s) { return d }
            throw DecodingError.dataCorruptedError(in: c, debugDescription: "Bad ISO8601 date: \(s)")
        }
        return try decoder.decode(type, from: data)
    }
}

extension Date {
    /// Now, truncated to whole milliseconds so values survive a JSON round trip unchanged.
    public static var stashNow: Date { Date(timeIntervalSince1970: (Date().timeIntervalSince1970 * 1000).rounded() / 1000) }
}
