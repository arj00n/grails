import Foundation

/// "This person has opened the library": one small file per handle in `.members/`, written by their own Grails. Each person writes only
/// their own file, so two Macs never edit the same one. It lets the owner see someone has joined before they've added anything.
public struct MemberRecord: Codable, Equatable, Sendable {
    public var handle: String
    public var firstSeen: Date
    public var lastSeen: Date
    public init(handle: String, firstSeen: Date, lastSeen: Date) { self.handle = handle; self.firstSeen = firstSeen; self.lastSeen = lastSeen }
}

public enum Members {
    public static func folder(_ layout: LibraryLayout) -> URL { layout.root.appendingPathComponent(".members", isDirectory: true) }

    static func fileName(_ handle: String) -> String? {
        let n = Handle.normalize(handle)
        return n.isEmpty ? nil : n + ".json"
    }

    /// Notes that `handle` opened the library. Writes at most once a day per person (`minInterval`), so a shared drive isn't
    /// churned by every launch. Returns whether it wrote.
    @discardableResult
    public static func record(handle: String, in layout: LibraryLayout, now: Date = Date(), minInterval: TimeInterval = 86_400) throws -> Bool {
        guard let name = fileName(handle) else { return false }
        let url = folder(layout).appendingPathComponent(name)
        var record = MemberRecord(handle: handle, firstSeen: now, lastSeen: now)
        if let data = try? Data(contentsOf: url), let old = try? GrailsJSON.decode(MemberRecord.self, from: data) {
            guard now.timeIntervalSince(old.lastSeen) >= minInterval || old.handle != handle else { return false }
            record.firstSeen = old.firstSeen
        }
        try AtomicFile.writeJSON(record, to: url)
        return true
    }

    /// Everyone who has opened the library with a version of Grails that records it. Reading a teammate's record can make the sync
    /// client fetch it (a few hundred bytes), so call this off the main thread.
    public static func all(in layout: LibraryLayout) -> [MemberRecord] {
        let dir = folder(layout)
        let names = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        return names.filter { $0.hasSuffix(".json") && !AtomicFile.isTemp($0) && !$0.contains(" ") }.sorted().compactMap { name in
            guard let data = try? Data(contentsOf: dir.appendingPathComponent(name)) else { return nil }
            return try? GrailsJSON.decode(MemberRecord.self, from: data)
        }
    }
}
