import Foundation

/// Order keys for sortable lists. Inserting between two neighbours produces a new key without
/// touching either, so reordering rewrites one item file instead of a whole list (fewer sync conflicts).
/// Keys are opaque base-62 strings compared bytewise; callers must never parse them.
public enum FractionalIndex {
    private static let digits = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz".utf8)
    private static let base = 62

    public static var initial: String { between(nil, nil) }
    public static func after(_ a: String?) -> String { between(a, nil) }
    public static func before(_ b: String?) -> String { between(nil, b) }

    /// A key strictly between `a` and `b` (either may be nil for "no bound"). Requires a < b.
    public static func between(_ a: String?, _ b: String?) -> String {
        let aDigits = (a ?? "").utf8.map(value)
        let bDigits = b.map { $0.utf8.map(value) }
        if let bDigits, a != nil { precondition(aDigits.lexicographicallyPrecedes(bDigits), "a must sort before b") }
        return String(decoding: mid(aDigits, bDigits).map { digits[$0] }, as: UTF8.self)
    }

    private static func value(_ byte: UInt8) -> Int { digits.firstIndex(of: byte) ?? 0 }

    private static func mid(_ a: [Int], _ b: [Int]?) -> [Int] {
        if let b {
            var n = 0
            while n < b.count, (n < a.count ? a[n] : 0) == b[n] { n += 1 }
            if n > 0 { return Array(b[..<n]) + mid(Array(a.dropFirst(n)), Array(b.dropFirst(n))) }
        }
        let da = a.first ?? 0
        let db = b?.first ?? base
        if db - da > 1 { return [(da + db + 1) / 2] }
        if let b, b.count > 1 { return [b[0]] }
        return [da] + mid(Array(a.dropFirst()), nil)
    }
}
