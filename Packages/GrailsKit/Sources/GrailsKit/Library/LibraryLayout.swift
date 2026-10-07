import Foundation

/// Every path inside a `.grails` package, in one place.
public struct LibraryLayout: Sendable, Hashable {
    public let root: URL
    public init(root: URL) { self.root = root }

    public var manifestURL: URL { root.appendingPathComponent("library.json") }
    public var itemsDir: URL { root.appendingPathComponent("items", isDirectory: true) }
    public var collectionsDir: URL { root.appendingPathComponent("collections", isDirectory: true) }
    public var canvasDir: URL { root.appendingPathComponent("canvas", isDirectory: true) }
    public var smartDir: URL { root.appendingPathComponent("smart", isDirectory: true) }
    public var tagsURL: URL { root.appendingPathComponent("tags.json") }
    /// One file per note, so two people never edit the same text. Voice sits beside its note as `<id>.m4a`.
    public var notesDir: URL { root.appendingPathComponent("notes", isDirectory: true) }
    public func noteURL(_ id: String) -> URL { notesDir.appendingPathComponent("\(id).json") }
    public func noteVoice(_ id: String) -> URL { notesDir.appendingPathComponent("\(id).m4a") }
    public var trashDir: URL { root.appendingPathComponent(".trash", isDirectory: true) }
    public var snapshotsDir: URL { root.appendingPathComponent(".snapshots", isDirectory: true) }

    public func itemDir(_ id: String) -> URL { itemsDir.appendingPathComponent(id, isDirectory: true) }
    public func itemJSON(_ id: String) -> URL { itemDir(id).appendingPathComponent("item.json") }
    public func thumbURL(_ id: String) -> URL { itemDir(id).appendingPathComponent("thumb.jpg") }
    public func snapshotURL(_ id: String) -> URL { itemDir(id).appendingPathComponent("snapshot.jpg") }
    public func collectionURL(_ id: String) -> URL { collectionsDir.appendingPathComponent("\(id).json") }
    public func canvasURL(_ key: String) -> URL { canvasDir.appendingPathComponent("\(key).json") }
    public func smartURL(_ id: String) -> URL { smartDir.appendingPathComponent("\(id).json") }
}

/// Machine-local locations. Nothing here is ever written inside a library.
public enum GrailsPaths {
    public static var appSupport: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Grails", isDirectory: true)
    }
    public static func indexURL(libraryId: String) -> URL {
        appSupport.appendingPathComponent("index/\(libraryId).sqlite")
    }
    public static var defaultUserHandle: String { NSUserName() }
}

enum FileStat {
    /// Modification time as seconds since 1970 (nanosecond precision), nil if the file doesn't exist.
    static func mtime(_ url: URL) -> Double? {
        var st = stat()
        guard stat(url.path, &st) == 0 else { return nil }
        return Double(st.st_mtimespec.tv_sec) + Double(st.st_mtimespec.tv_nsec) / 1_000_000_000
    }
}
