import Foundation

/// Sync clients (Google Drive, Dropbox, iCloud) resolve simultaneous edits by writing a second file next to
/// the original: `item (1).json`, `item (Ana's conflicted copy 2026-10-03).json`, `item 2.json`.
/// We fold those back into the canonical file so no edit is lost.
public enum ConflictMerger {
    public static func isItemConflictCopy(_ name: String) -> Bool {
        guard name.hasSuffix(".json"), name != "item.json", !AtomicFile.isTemp(name), name.hasPrefix("item") else { return false }
        let rest = name.dropFirst(4)
        return rest.first.map { $0 == " " || $0 == "(" || $0 == "_" || $0 == "-" } ?? false
    }

    /// `<ULID> (1).json` → `<ULID>.json`; nil when `name` isn't a conflict copy.
    public static func canonicalCollectionName(forConflictCopy name: String) -> String? {
        guard name.hasSuffix(".json"), !AtomicFile.isTemp(name), name.count > 31 else { return nil }
        let id = String(name.prefix(26))
        guard ULID.isValid(id) else { return nil }
        return "\(id).json"
    }

    /// Folds conflict copies in an item folder into `item.json`. Returns the number of copies merged.
    @discardableResult
    public static func mergeItemConflicts(in folder: URL) throws -> Int {
        let fm = FileManager.default
        let names = try fm.contentsOfDirectory(atPath: folder.path)
        let copies = names.filter(isItemConflictCopy)
        guard !copies.isEmpty else { return 0 }

        let canonical = folder.appendingPathComponent("item.json")
        var merged: Item?
        var versions: [URL] = []
        if fm.fileExists(atPath: canonical.path) { versions.append(canonical) }
        versions.append(contentsOf: copies.sorted().map { folder.appendingPathComponent($0) })

        for url in versions {
            guard let item = try? StashJSON.decode(Item.self, from: Data(contentsOf: url)) else { continue }
            merged = merged.map { merge($0, item) } ?? item
        }
        guard let merged else { return 0 } // every version unreadable: leave the files for a human
        try AtomicFile.writeJSON(merged, to: canonical)
        for name in copies { try? fm.removeItem(at: folder.appendingPathComponent(name)) }
        return copies.count
    }

    /// Union of tags and collections, newest wins for everything else.
    public static func merge(_ a: Item, _ b: Item) -> Item {
        let (newer, older) = b.updatedAt > a.updatedAt ? (b, a) : (a, b)
        var out = newer
        var seen = Set(newer.tags.map { $0.lowercased() })
        for tag in older.tags where seen.insert(tag.lowercased()).inserted { out.tags.append(tag) }
        out.collections = older.collections.merging(newer.collections) { _, new in new }
        if out.palette.isEmpty { out.palette = older.palette }
        if out.ocrText.isEmpty { out.ocrText = older.ocrText }
        if out.note.isEmpty { out.note = older.note }
        out.extras = older.extras.merging(newer.extras) { _, new in new }
        if older.addedAt < newer.addedAt { out.addedAt = older.addedAt; out.addedBy = older.addedBy }
        out.updatedAt = max(a.updatedAt, b.updatedAt)
        return out
    }

    /// Collections are tiny and rarely edited concurrently: newest copy wins.
    @discardableResult
    public static func mergeCollectionConflicts(in dir: URL) throws -> Int {
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: dir.path) else { return 0 }
        var merged = 0
        for name in names {
            guard let canonicalName = canonicalCollectionName(forConflictCopy: name) else { continue }
            let copyURL = dir.appendingPathComponent(name)
            let canonicalURL = dir.appendingPathComponent(canonicalName)
            guard let copy = try? StashJSON.decode(StashCollection.self, from: Data(contentsOf: copyURL)) else { continue }
            if let current = try? StashJSON.decode(StashCollection.self, from: Data(contentsOf: canonicalURL)),
               current.updatedAt >= copy.updatedAt {
                // canonical already newest
            } else {
                try AtomicFile.writeJSON(copy, to: canonicalURL)
            }
            try? fm.removeItem(at: copyURL)
            merged += 1
        }
        return merged
    }
}
