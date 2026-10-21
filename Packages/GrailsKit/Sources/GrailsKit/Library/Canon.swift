import Foundation

/// The team's lasting set of best references. People promote items into it.
///
/// On disk it is an ordinary collection. Older libraries name that collection "Baseline",
/// and a collection file may also carry a `baseline` field (a flag, or the note for why it works).
/// Both still load as Canon. The stored name and the `baseline` key are left as written.
public enum Canon {
    public static let name = "Canon"
    /// Collection name older libraries still have on disk and in the bucket.
    public static let legacyStoredName = "Baseline"

    public static func matches(_ storedName: String) -> Bool {
        storedName.caseInsensitiveCompare(name) == .orderedSame
            || storedName.caseInsensitiveCompare(legacyStoredName) == .orderedSame
    }

    /// What the app shows. A collection stored as "Baseline" reads as Canon.
    public static func displayName(forStored storedName: String) -> String {
        storedName.caseInsensitiveCompare(legacyStoredName) == .orderedSame ? name : storedName
    }

    /// The collection this library already uses, preferring one stored under the current name.
    /// A folder is only used when nothing else matches, so an old library that filed Canon as a folder still opens.
    public static func collection(in collections: [GrailsCollection]) -> GrailsCollection? {
        let hits = collections.filter(\.isCanon)
        let sets = hits.filter { $0.kind != "folder" }
        let pool = sets.isEmpty ? hits : sets
        if let current = pool.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) { return current }
        return pool.first
    }

    /// A `baseline` JSON value that marks the collection. Absent, false, and empty do not.
    static func legacyFlag(_ value: JSONValue?) -> Bool {
        switch value {
        case .bool(let on): return on
        case .int(let n): return n != 0
        case .double(let n): return n != 0
        case .string(let s):
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return !t.isEmpty && t != "false" && t != "0"
        case .array(let values): return !values.isEmpty
        case .object(let fields): return !fields.isEmpty
        default: return false
        }
    }
}

extension GrailsCollection {
    /// True when this collection is the team's Canon set, including one stored the old way.
    public var isCanon: Bool { Canon.matches(name) || Canon.legacyFlag(extras["baseline"]) }

    /// The name people see. A collection stored as "Baseline" reads as Canon. The file is not rewritten.
    public var displayName: String { Canon.displayName(forStored: name) }
}
