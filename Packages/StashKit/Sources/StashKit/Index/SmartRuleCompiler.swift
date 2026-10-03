import Foundation
import GRDB

/// Turns a `SmartFolder` into a SQL `WHERE` fragment over the `items i` table. Unknown fields or operators never
/// widen a result: in an "all" folder they match nothing, in an "any" folder they're ignored.
enum SmartRuleCompiler {
    static let fields = [
        "kind", "name", "ext", "bytes", "width", "height", "aspect", "durationSec", "addedAt", "addedBy",
        "tags", "collections", "site", "liked", "hasNote", "color",
    ]

    static func compile(_ folder: SmartFolder, now: Date = Date()) -> (sql: String, args: StatementArguments) {
        var parts: [String] = []
        var args = StatementArguments()
        let any = folder.match == "any"
        for rule in folder.rules {
            if let (sql, a) = compile(rule, now: now) {
                parts.append("(\(sql))")
                args += a
            } else if !any {
                parts.append("0")
            }
        }
        if parts.isEmpty { return (any ? "0" : "1", args) }
        return (parts.joined(separator: any ? " OR " : " AND "), args)
    }

    private static func compile(_ r: SmartRule, now: Date) -> (String, StatementArguments)? {
        switch r.field {
        case "kind": return text("i.kind", r)
        case "ext": return text("i.ext", r, lowercase: true)
        case "name": return text("i.name", r)
        case "addedBy": return text("i.addedBy", r)
        case "site": return text("i.sourceSite", r)
        case "bytes": return number("i.bytes", r)
        case "width": return number("i.width", r)
        case "height": return number("i.height", r)
        case "durationSec": return number("i.durationSec", r)
        case "aspect": return number("(i.width * 1.0 / NULLIF(i.height, 0))", r)
        case "addedAt": return date("i.addedAt", r, now: now)
        case "liked": return bool("i.liked = 1", r)
        case "hasNote": return bool("i.note <> ''", r)
        case "tags": return membership(table: "item_tags", column: "tag", r)
        case "collections": return membership(table: "item_collections", column: "collectionId", r)
        case "color": return color(r)
        default: return nil
        }
    }

    private static func string(_ v: JSONValue) -> String? {
        switch v { case .string(let s): s; case .int(let i): String(i); case .double(let d): String(d); default: nil }
    }
    private static func double(_ v: JSONValue) -> Double? {
        switch v { case .int(let i): Double(i); case .double(let d): d; case .string(let s): Double(s); default: nil }
    }
    private static func like(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "%", with: "\\%").replacingOccurrences(of: "_", with: "\\_")
    }

    private static func text(_ col: String, _ r: SmartRule, lowercase: Bool = false) -> (String, StatementArguments)? {
        guard var v = string(r.value) else { return nil }
        if lowercase { v = v.lowercased() }
        switch r.op {
        case "is": return ("\(col) = ? COLLATE NOCASE", [v])
        case "isNot": return ("(\(col) IS NULL OR \(col) <> ? COLLATE NOCASE)", [v])
        case "contains": return ("\(col) LIKE ? ESCAPE '\\'", ["%\(like(v))%"])
        case "notContains": return ("(\(col) IS NULL OR \(col) NOT LIKE ? ESCAPE '\\')", ["%\(like(v))%"])
        case "startsWith": return ("\(col) LIKE ? ESCAPE '\\'", ["\(like(v))%"])
        default: return nil
        }
    }

    private static func number(_ col: String, _ r: SmartRule) -> (String, StatementArguments)? {
        guard let v = double(r.value) else { return nil }
        let op: String
        switch r.op {
        case "is": op = "="
        case "isNot": op = "<>"
        case "gt": op = ">"
        case "gte": op = ">="
        case "lt": op = "<"
        case "lte": op = "<="
        default: return nil
        }
        return ("\(col) \(op) ?", [v])
    }

    private static func date(_ col: String, _ r: SmartRule, now: Date) -> (String, StatementArguments)? {
        switch r.op {
        case "withinDays":
            guard let d = double(r.value) else { return nil }
            return ("\(col) >= ?", [now.timeIntervalSince1970 - d * 86400])
        case "olderThanDays":
            guard let d = double(r.value) else { return nil }
            return ("\(col) < ?", [now.timeIntervalSince1970 - d * 86400])
        case "before", "after":
            let t: Double?
            if let n = double(r.value) { t = n }
            else if let s = string(r.value), let d = try? Date.ISO8601FormatStyle().parse(s) { t = d.timeIntervalSince1970 }
            else { t = nil }
            guard let t else { return nil }
            return ("\(col) \(r.op == "before" ? "<" : ">=") ?", [t])
        default: return nil
        }
    }

    private static func bool(_ truth: String, _ r: SmartRule) -> (String, StatementArguments)? {
        guard case .bool(let want) = r.value, r.op == "is" else { return nil }
        return (want ? truth : "NOT (\(truth))", [])
    }

    private static func membership(table: String, column: String, _ r: SmartRule) -> (String, StatementArguments)? {
        let exists = "EXISTS (SELECT 1 FROM \(table) m WHERE m.itemId = i.id"
        switch r.op {
        case "has":
            guard let v = string(r.value) else { return nil }
            return ("\(exists) AND m.\(column) = ?)", [v])
        case "hasNot":
            guard let v = string(r.value) else { return nil }
            return ("NOT \(exists) AND m.\(column) = ?)", [v])
        case "notEmpty": return ("\(exists))", [])
        case "empty": return ("NOT \(exists))", [])
        default: return nil
        }
    }

    /// Palette colour within a Lab distance of a hex colour. Value: "#RRGGBB" or `{ "hex": …, "threshold": … }`.
    private static func color(_ r: SmartRule) -> (String, StatementArguments)? {
        guard r.op == "near" else { return nil }
        var hex: String?
        var threshold = 20.0
        switch r.value {
        case .string(let s): hex = s
        case .object(let o):
            hex = o["hex"].flatMap(string)
            if let t = o["threshold"].flatMap(double) { threshold = t }
        default: break
        }
        guard let hex, let lab = ColorMath.lab(fromHex: hex) else { return nil }
        return ("""
        EXISTS (SELECT 1 FROM palette p WHERE p.itemId = i.id AND p.l IS NOT NULL
          AND (p.l - ?) * (p.l - ?) + (p.a - ?) * (p.a - ?) + (p.b - ?) * (p.b - ?) < ?)
        """, [lab.l, lab.l, lab.a, lab.a, lab.b, lab.b, threshold * threshold])
    }
}
