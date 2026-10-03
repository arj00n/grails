import Foundation

/// 26-character, lexicographically sortable id: 48-bit millisecond timestamp + 80 random bits.
public struct ULID: Hashable, Comparable, Sendable, CustomStringConvertible {
    private static let alphabet = Array("0123456789ABCDEFGHJKMNPQRSTVWXYZ")
    public let string: String

    public init(date: Date = Date()) {
        var ms = UInt64(max(0, date.timeIntervalSince1970) * 1000)
        var chars = [Character](repeating: "0", count: 26)
        for i in stride(from: 9, through: 0, by: -1) {
            chars[i] = Self.alphabet[Int(ms & 31)]
            ms >>= 5
        }
        for i in 10..<26 { chars[i] = Self.alphabet[Int.random(in: 0..<32)] }
        string = String(chars)
    }

    public init?(string: String) {
        guard Self.isValid(string) else { return nil }
        self.string = string
    }

    public static func isValid(_ s: String) -> Bool {
        s.count == 26 && s.allSatisfy { alphabet.contains($0) }
    }

    public var date: Date {
        var ms: UInt64 = 0
        for ch in string.prefix(10) { ms = ms << 5 | UInt64(Self.alphabet.firstIndex(of: ch) ?? 0) }
        return Date(timeIntervalSince1970: Double(ms) / 1000)
    }

    public var description: String { string }
    public static func < (a: ULID, b: ULID) -> Bool { a.string < b.string }
}
