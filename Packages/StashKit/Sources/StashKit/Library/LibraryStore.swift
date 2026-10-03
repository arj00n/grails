import Foundation

public enum StashError: Error, Equatable {
    case notALibrary(URL)
    case itemNotFound(String)
    case unreadableFile(URL)
}

public enum AddResult: Sendable {
    case added(Item)
    case duplicate(Item)
    public var item: Item {
        switch self { case .added(let i), .duplicate(let i): i }
    }
}

public struct RescanResult: Sendable, Equatable {
    public var added = 0
    public var updated = 0
    public var removed = 0
    public var conflictsMerged = 0
    public var failures: [ScanFailure] = []
}

/// Owns a library folder. All writes go through here: the files are the source of truth and the SQLite
/// index is updated right after each write.
public actor LibraryStore {
    public nonisolated let layout: LibraryLayout
    public private(set) var manifest: LibraryManifest
    public nonisolated let index: LibraryIndex
    public var userHandle: String
    /// Non-nil while `recording(label:)` is running; mutations note the state they overwrite.
    var recorder: ChangeRecorder?

    private init(layout: LibraryLayout, manifest: LibraryManifest, index: LibraryIndex, userHandle: String) {
        self.layout = layout; self.manifest = manifest; self.index = index; self.userHandle = userHandle
    }

    // MARK: Create / open

    public static func create(
        at root: URL, name: String, index: LibraryIndex? = nil, userHandle: String = StashPaths.defaultUserHandle
    ) throws -> LibraryStore {
        let layout = LibraryLayout(root: root)
        let fm = FileManager.default
        guard !fm.fileExists(atPath: layout.manifestURL.path) else { throw StashError.notALibrary(root) }
        for dir in [layout.itemsDir, layout.collectionsDir, layout.canvasDir, layout.smartDir] {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        let manifest = LibraryManifest(name: name)
        try AtomicFile.writeJSON(manifest, to: layout.manifestURL)
        let idx = try index ?? LibraryIndex(path: StashPaths.indexURL(libraryId: manifest.id))
        return LibraryStore(layout: layout, manifest: manifest, index: idx, userHandle: userHandle)
    }

    /// Opens a library. With `rescan: true` (default) the index is brought up to date with disk before returning;
    /// pass false to show the existing index immediately and call `rescan()` yourself in the background.
    /// A discarded or empty index is always rebuilt first.
    public static func open(
        at root: URL, index: LibraryIndex? = nil, userHandle: String = StashPaths.defaultUserHandle, rescan: Bool = true
    ) async throws -> LibraryStore {
        let layout = LibraryLayout(root: root)
        guard let data = try? Data(contentsOf: layout.manifestURL),
              let manifest = try? StashJSON.decode(LibraryManifest.self, from: data) else { throw StashError.notALibrary(root) }
        let idx = try index ?? LibraryIndex(path: StashPaths.indexURL(libraryId: manifest.id))
        let store = LibraryStore(layout: layout, manifest: manifest, index: idx, userHandle: userHandle)
        if idx.wasReset {
            try await idx.rebuild(from: layout)
        } else {
            let empty = try await idx.stats().items == 0
            if rescan || empty { try await store.rescan() }
        }
        return store
    }

    public func setUserHandle(_ handle: String) { userHandle = handle }

    // MARK: Items

    public func item(id: String) throws -> Item? {
        let url = layout.itemJSON(id)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try StashJSON.decode(Item.self, from: Data(contentsOf: url))
    }

    public func originalURL(for item: Item) -> URL? {
        item.file.map { layout.itemDir(item.id).appendingPathComponent($0) }
    }

    public func thumbURL(for id: String) -> URL { layout.thumbURL(id) }

    /// Copies `fileURL` into the library as a new item. Identical content (same SHA-256) returns the existing item.
    @discardableResult
    public func addItem(
        fileAt fileURL: URL, name: String? = nil, source: ItemSource? = nil, tags: [String] = [],
        collectionIds: [String] = [], dedupe: Bool = true
    ) async throws -> AddResult {
        let prepared = try await Task.detached(priority: .userInitiated) { try PreparedFile(url: fileURL) }.value

        if dedupe, let existingId = try await index.itemId(withSHA256: prepared.sha256), let existing = try item(id: existingId) {
            return .duplicate(existing)
        }

        let id = ULID().string
        let dir = layout.itemDir(id)
        let fm = FileManager.default
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let fileName = prepared.ext.isEmpty ? "original" : "original.\(prepared.ext)"
        try fm.copyItem(at: fileURL, to: dir.appendingPathComponent(fileName))
        if let thumb = prepared.thumbnail { try AtomicFile.write(thumb, to: layout.thumbURL(id)) }

        var orders: [String: String] = [:]
        for cid in collectionIds {
            orders[cid] = FractionalIndex.after(try await index.maxOrderKey(collectionId: cid))
        }
        let item = Item(
            id: id, kind: prepared.kind, file: fileName, name: name ?? prepared.baseName,
            ext: prepared.ext.isEmpty ? nil : prepared.ext, bytes: prepared.bytes, width: prepared.width,
            height: prepared.height, sha256: prepared.sha256, source: source, tags: Self.dedupeTags(tags),
            collections: orders, camera: prepared.camera, addedBy: userHandle
        )
        try await persist(item)
        return .added(item)
    }

    /// Reads the item from disk, applies `mutate`, stamps updatedAt/By, writes it back and refreshes the index.
    @discardableResult
    public func updateItem(id: String, _ mutate: (inout Item) throws -> Void) async throws -> Item {
        guard var item = try item(id: id) else { throw StashError.itemNotFound(id) }
        try mutate(&item)
        item.id = id
        item.updatedAt = .stashNow
        item.updatedBy = userHandle
        try await persist(item)
        return item
    }

    public func softDelete(ids: [String]) async throws {
        let now = Date.stashNow
        for id in ids { try await updateItem(id: id) { $0.deletedAt = now } }
    }

    public func restore(ids: [String]) async throws {
        for id in ids { try await updateItem(id: id) { $0.deletedAt = nil } }
    }

    /// Moves everything currently in Trash to `.trash/` (kept 30 days, then purged) and drops it from the index.
    @discardableResult
    public func emptyTrash() async throws -> Int {
        let trashed = try await index.query({ var q = ItemQuery(); q.deleted = true; q.limit = Int.max; return q }())
        let fm = FileManager.default
        try fm.createDirectory(at: layout.trashDir, withIntermediateDirectories: true)
        for t in trashed {
            let dest = layout.trashDir.appendingPathComponent(t.id)
            try? fm.removeItem(at: dest)
            try fm.moveItem(at: layout.itemDir(t.id), to: dest)
        }
        try await index.remove(ids: trashed.map(\.id))
        return trashed.count
    }

    /// Permanently deletes `.trash/` entries whose item was deleted more than `days` ago.
    @discardableResult
    public func purgeTrash(olderThanDays days: Int = 30, now: Date = Date()) throws -> Int {
        let fm = FileManager.default
        let cutoff = now.addingTimeInterval(-Double(days) * 86400)
        var purged = 0
        for url in (try? fm.contentsOfDirectory(at: layout.trashDir, includingPropertiesForKeys: nil)) ?? [] {
            let deletedAt = (try? StashJSON.decode(Item.self, from: Data(contentsOf: url.appendingPathComponent("item.json"))))?.deletedAt
            if (deletedAt ?? .distantPast) < cutoff { try fm.removeItem(at: url); purged += 1 }
        }
        return purged
    }

    // MARK: Collections

    @discardableResult
    public func createCollection(name: String, kind: String = "collection", parentId: String? = nil) async throws -> StashCollection {
        let siblings = try await index.collections().filter { $0.parentId == parentId }
        let c = StashCollection(
            kind: kind, name: name, parentId: parentId, order: FractionalIndex.after(siblings.last?.order), updatedBy: userHandle
        )
        try await persistCollection(c)
        return c
    }

    // MARK: Rescan

    /// Brings the index in line with disk: folds sync conflict copies, picks up files changed by other
    /// machines, and forgets items that vanished.
    @discardableResult
    public func rescan() async throws -> RescanResult {
        var result = RescanResult()
        let fm = FileManager.default
        result.conflictsMerged += (try? ConflictMerger.mergeCollectionConflicts(in: layout.collectionsDir)) ?? 0
        result.conflictsMerged += (try? ConflictMerger.mergeCanvasConflicts(in: layout.canvasDir)) ?? 0

        let known = try await index.allMtimes()
        var onDisk = Set<String>()
        var changed: [URL] = []
        for folder in ItemScanner.itemFolders(in: layout) {
            let id = folder.lastPathComponent
            if let names = try? fm.contentsOfDirectory(atPath: folder.path), names.contains(where: ConflictMerger.isItemConflictCopy) {
                result.conflictsMerged += (try? ConflictMerger.mergeItemConflicts(in: folder)) ?? 0
            }
            guard let mtime = FileStat.mtime(folder.appendingPathComponent("item.json")) else { continue }
            onDisk.insert(id)
            if known[id] != mtime { changed.append(folder) }
        }

        let scan = await ItemScanner.scan(folders: changed)
        result.failures = scan.failures
        for e in scan.items { if known[e.item.id] == nil { result.added += 1 } else { result.updated += 1 } }
        try await index.upsert(scan.items)

        let gone = known.keys.filter { !onDisk.contains($0) }
        result.removed = gone.count
        try await index.remove(ids: gone)

        try await index.replaceCollections(LibraryIndex.readCollections(layout))
        return result
    }

    // MARK: Snapshots

    /// Writes `.snapshots/<yyyy-MM-dd>.stashsnap` (all JSON, no media, LZFSE-compressed) once per day; keeps the newest 14.
    @discardableResult
    public func snapshotIfNeeded(now: Date = Date(), keep: Int = 14) throws -> URL? {
        let fm = FileManager.default
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(identifier: "UTC")
        f.locale = Locale(identifier: "en_US_POSIX")
        let url = layout.snapshotsDir.appendingPathComponent("\(f.string(from: now)).stashsnap")
        guard !fm.fileExists(atPath: url.path) else { return nil }

        var files: [String: JSONValue] = [:]
        func add(_ rel: String, _ file: URL) {
            if let d = try? Data(contentsOf: file), let v = try? JSONDecoder().decode(JSONValue.self, from: d) { files[rel] = v }
        }
        add("library.json", layout.manifestURL)
        for dir in [layout.collectionsDir, layout.smartDir, layout.canvasDir] {
            for u in (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? [] where u.pathExtension == "json" && !AtomicFile.isTemp(u.lastPathComponent) {
                add("\(dir.lastPathComponent)/\(u.lastPathComponent)", u)
            }
        }
        add("tags.json", layout.tagsURL)
        for folder in ItemScanner.itemFolders(in: layout) {
            add("items/\(folder.lastPathComponent)/item.json", folder.appendingPathComponent("item.json"))
        }
        let payload = try StashJSON.encode(JSONValue.object(["createdAt": .string(ISO8601DateFormatter().string(from: now)), "files": .object(files)]))
        let compressed = try (payload as NSData).compressed(using: .lzfse) as Data
        try AtomicFile.write(compressed, to: url)

        let old = ((try? fm.contentsOfDirectory(atPath: layout.snapshotsDir.path)) ?? []).filter { $0.hasSuffix(".stashsnap") }.sorted()
        for name in old.dropLast(keep) { try? fm.removeItem(at: layout.snapshotsDir.appendingPathComponent(name)) }
        return url
    }

    // MARK: Internals

    func persist(_ item: Item, record: Bool = true) async throws {
        if record { noteBefore(item: item.id) }
        let url = layout.itemJSON(item.id)
        try AtomicFile.writeJSON(item, to: url)
        try await index.upsert(item, mtime: FileStat.mtime(url) ?? 0)
    }

    static func dedupeTags(_ tags: [String]) -> [String] {
        var seen = Set<String>()
        return tags.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }
    }
}

/// Everything expensive about ingesting a file, computed off the actor.
struct PreparedFile: Sendable {
    var sha256: String
    var bytes: Int64
    var kind: ItemKind
    var ext: String
    var baseName: String
    var width: Int?
    var height: Int?
    var thumbnail: Data?
    var camera: JSONValue?

    init(url: URL) throws {
        guard FileManager.default.isReadableFile(atPath: url.path) else { throw StashError.unreadableFile(url) }
        sha256 = try FileHash.sha256(of: url)
        bytes = Int64((try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value ?? 0)
        kind = MediaKind.detect(url)
        ext = url.pathExtension.lowercased()
        baseName = url.deletingPathExtension().lastPathComponent
        if kind == .image || kind == .gif || kind == .raw {
            let info = Thumbnailer.imageInfo(at: url)
            width = info?.width
            height = info?.height
            thumbnail = Thumbnailer.jpegThumbnail(for: url)
            camera = Thumbnailer.cameraInfo(at: url)
        }
    }
}
