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
            try c.encode(isoString(date))
        }
        return try encoder.encode(value)
    }

    /// ISO-8601 with millisecond fraction, built from integer milliseconds. (The stock formatter truncates,
    /// which can shift a value by 1 ms on a round trip.)
    static func isoString(_ date: Date) -> String {
        let ms = Int64((date.timeIntervalSince1970 * 1000).rounded())
        let seconds = ms >= 0 ? ms / 1000 : (ms - 999) / 1000
        let frac = ms - seconds * 1000
        let base = Date(timeIntervalSince1970: Double(seconds)).formatted(whole)   // yyyy-MM-ddTHH:mm:ssZ
        return String(base.dropLast()) + String(format: ".%03dZ", Int(frac))
    }

    /// Compact (no pretty-printing) for big, machine-edited files such as canvas boards.
    public static func encodeCompact<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var c = encoder.singleValueContainer()
            try c.encode(isoString(date))
        }
        return try encoder.encode(value)
    }

    public static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let c = try decoder.singleValueContainer()
            let s = try c.decode(String.self)
            if let d = try? fractional.parse(s) { return d.roundedToMilliseconds }
            if let d = try? whole.parse(s) { return d.roundedToMilliseconds }
            throw DecodingError.dataCorruptedError(in: c, debugDescription: "Bad ISO8601 date: \(s)")
        }
        return try decoder.decode(type, from: data)
    }
}

extension Date {
    /// Now, truncated to whole milliseconds so values survive a JSON round trip unchanged.
    public static var stashNow: Date { Date().roundedToMilliseconds }

    /// Snaps to the nearest millisecond using one canonical computation, so a date written as ISO-8601 text and
    /// read back is bit-for-bit equal to the original (plain parsing can differ by a floating-point ulp).
    public var roundedToMilliseconds: Date { Date(timeIntervalSince1970: (timeIntervalSince1970 * 1000).rounded() / 1000) }
}
