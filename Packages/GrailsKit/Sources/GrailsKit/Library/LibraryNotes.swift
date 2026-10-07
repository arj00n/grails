import Foundation

/// A note left on a creative or a cluster. Each one is its own file, written by one person.
public struct GrailsNote: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var itemId: String?
    public var board: String?
    public var clusterId: String?
    public var author: String
    public var at: Date
    public var text: String
    public var mentions: [String]
    public var voice: Bool
    public var seconds: Double?
    public var deletedAt: Date?

    public var isLegacy: Bool { id.hasPrefix("legacy:") }

    public init(id: String, itemId: String? = nil, board: String? = nil, clusterId: String? = nil, author: String, at: Date,
                text: String, mentions: [String] = [], voice: Bool = false, seconds: Double? = nil, deletedAt: Date? = nil) {
        self.id = id; self.itemId = itemId; self.board = board; self.clusterId = clusterId; self.author = author
        self.at = at; self.text = text; self.mentions = mentions; self.voice = voice; self.seconds = seconds; self.deletedAt = deletedAt
    }
}

/// Notes on disk. The creative's old single `note` string is still the first line of its thread, so a library
/// shared with an older Grails keeps that text.
public enum LibraryNotes {
    public static func read(_ id: String, in layout: LibraryLayout) -> GrailsNote? {
        guard let data = try? Data(contentsOf: layout.noteURL(id)) else { return nil }
        return try? GrailsJSON.decode(GrailsNote.self, from: data)
    }

    public static func write(_ note: GrailsNote, in layout: LibraryLayout) throws {
        try AtomicFile.writeJSON(note, to: layout.noteURL(note.id))
    }

    /// Live notes, oldest first. Tombstones stay on disk so a teammate's copy does not bring a deleted note back.
    public static func live(in layout: LibraryLayout) -> [GrailsNote] {
        all(in: layout).filter { $0.deletedAt == nil }.sorted { $0.at < $1.at }
    }

    public static func all(in layout: LibraryLayout) -> [GrailsNote] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: layout.notesDir.path)) ?? []
        return names.compactMap { name in
            guard name.hasSuffix(".json"), !AtomicFile.isTemp(name), !name.contains(" ") else { return nil }
            let id = String(name.dropLast(5))
            guard ULID.isValid(id) else { return nil }
            return read(id, in: layout)
        }
    }

    /// The creative's old note, then every note file on it.
    public static func thread(item: Item, in layout: LibraryLayout) -> [GrailsNote] {
        var out: [GrailsNote] = []
        let text = item.note.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty {
            out.append(GrailsNote(id: "legacy:\(item.id)", itemId: item.id, author: item.updatedBy, at: item.updatedAt, text: text))
        }
        out += live(in: layout).filter { $0.itemId == item.id }
        return out.sorted { $0.at < $1.at }
    }

    public static func thread(board: String, cluster: String, in layout: LibraryLayout) -> [GrailsNote] {
        live(in: layout).filter { $0.board == board && $0.clusterId == cluster }.sorted { $0.at < $1.at }
    }

    /// Note text on this creative, not including the old single note (that is already on the item).
    public static func extraText(itemId: String, in layout: LibraryLayout) -> String {
        live(in: layout).filter { $0.itemId == itemId }.map(\.text).filter { !$0.isEmpty }.joined(separator: "\n")
    }

    /// ponytail: one pass over the notes folder. Fine until a library has thousands of notes.
    public static func textsByItem(in layout: LibraryLayout) -> [String: String] {
        var buckets: [String: [String]] = [:]
        for note in live(in: layout) {
            guard let id = note.itemId, !note.text.isEmpty else { continue }
            buckets[id, default: []].append(note.text)
        }
        return buckets.mapValues { $0.joined(separator: "\n") }
    }

    public static func itemIds(mentioning handle: String, in layout: LibraryLayout) -> Set<String> {
        let who = Handle.normalize(handle)
        guard !who.isEmpty else { return [] }
        return Set(live(in: layout).filter { $0.mentions.contains(who) }.compactMap(\.itemId))
    }

    /// `@handle` tokens that name someone this library already knows. Unknown words are left as text.
    public static func mentions(in text: String, people: [String]) -> [String] {
        let known = Set(people.map { Handle.normalize($0) }.filter { !$0.isEmpty })
        guard !known.isEmpty else { return [] }
        var out: [String] = []
        var seen = Set<String>()
        var i = text.startIndex
        while i < text.endIndex {
            if text[i] == "@" {
                var end = text.index(after: i)
                while end < text.endIndex, isHandle(text[end]) { end = text.index(after: end) }
                let token = Handle.normalize(String(text[text.index(after: i)..<end]))
                if known.contains(token), seen.insert(token).inserted { out.append(token) }
                i = end
            } else {
                i = text.index(after: i)
            }
        }
        return out
    }

    /// `id (1).json` and Drive's conflict copies fold back into `id.json`. Newest edit wins.
    @discardableResult
    public static func foldConflicts(in layout: LibraryLayout) -> Int {
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: layout.notesDir.path) else { return 0 }
        var folded = 0
        for name in names {
            guard name.hasSuffix(".json"), !AtomicFile.isTemp(name) else { continue }
            let id = String(name.prefix(26))
            guard ULID.isValid(id), name != "\(id).json" else { continue }
            let copyURL = layout.notesDir.appendingPathComponent(name)
            guard let copy = try? GrailsJSON.decode(GrailsNote.self, from: Data(contentsOf: copyURL)) else { continue }
            let canonical = layout.noteURL(id)
            if let data = try? Data(contentsOf: canonical), let current = try? GrailsJSON.decode(GrailsNote.self, from: data),
               stamp(current) > stamp(copy) {
                // the canonical file is newer
            } else {
                try? AtomicFile.writeJSON(copy, to: canonical)
            }
            try? fm.removeItem(at: copyURL)
            folded += 1
        }
        return folded
    }

    /// Copies one creative's notes (and voice) into another library. Same note id, so a later sync does not duplicate it.
    public static func copyItem(_ itemId: String, from src: LibraryLayout, to dst: LibraryLayout) throws {
        let fm = FileManager.default
        for note in all(in: src) where note.itemId == itemId {
            try write(note, in: dst)
            let voice = src.noteVoice(note.id)
            let dest = dst.noteVoice(note.id)
            if fm.fileExists(atPath: voice.path), !fm.fileExists(atPath: dest.path) {
                try fm.copyItem(at: voice, to: dest)
            }
        }
    }

    private static func isHandle(_ c: Character) -> Bool {
        c.isLetter || c.isNumber || c == "." || c == "_" || c == "-"
    }

    private static func stamp(_ note: GrailsNote) -> Date { max(note.at, note.deletedAt ?? .distantPast) }
}
