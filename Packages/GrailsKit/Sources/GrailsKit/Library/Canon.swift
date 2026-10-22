import Foundation

/// The team's lasting set of best references. People add items to it.
///
/// On disk it is an ordinary collection. The app shows it as Holy Grail.
/// Older libraries name that collection "Baseline". Libraries saved while the
/// feature was called Canon store the name "Canon". A collection file may also
/// carry a `baseline` field (a flag, or the note for why it works).
/// Both stored names still load as Holy Grail. A new file is still named "Canon",
/// because an older build only treats "Canon" and "Baseline" as this set.
/// The `baseline` key is left as written. A new key would be ignored by those builds.
public enum Canon {
    public static let title = "Holy Grail"
    /// Written into a new collection file. Older builds still match this name.
    public static let name = "Canon"
    /// Collection name older libraries still have on disk and in the bucket.
    public static let legacyStoredName = "Baseline"

    public static func matches(_ storedName: String) -> Bool {
        storedName.caseInsensitiveCompare(name) == .orderedSame
            || storedName.caseInsensitiveCompare(legacyStoredName) == .orderedSame
    }

    /// What the app shows. A collection stored as "Canon" or "Baseline" reads as Holy Grail.
    public static func displayName(forStored storedName: String) -> String {
        matches(storedName) ? title : storedName
    }

    /// The collection this library already uses, preferring one stored as "Canon".
    /// A folder is only used when nothing else matches, so an old library that filed Holy Grail as a folder still opens.
    public static func collection(in collections: [GrailsCollection]) -> GrailsCollection? {
        let hits = collections.filter(\.isCanon)
        let sets = hits.filter { $0.kind != "folder" }
        let pool = sets.isEmpty ? hits : sets
        if let current = pool.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) { return current }
        return pool.first
    }

    public struct Offer: Equatable, Sendable {
        public let adding: [String]
        public var shown: Bool { !adding.isEmpty }
        init(adding: [String]) { self.adding = adding }
    }

    public static func offer(selected: [String], alreadyIn: Set<String>) -> Offer {
        Offer(adding: selected.filter { !alreadyIn.contains($0) })
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
    /// True when this collection is the team's Holy Grail set, including one stored under an older name.
    public var isCanon: Bool { Canon.matches(name) || Canon.legacyFlag(extras["baseline"]) }

    /// The name people see. "Canon" and "Baseline" read as Holy Grail. The file is not rewritten.
    public var displayName: String { Canon.displayName(forStored: name) }
}
