import CryptoKit
import Foundation

// Tags, collections, smart folders, likes, notes, and undo support.
extension LibraryStore {
    // MARK: Undo

    /// Starts noting the "before" state of everything subsequently changed. Pair with `endRecording(label:)`.
    /// Use this form from the UI (a closure can't hop from the main actor into this actor under Swift 6).
    public func beginRecording() { recorder = ChangeRecorder() }

    /// Stops recording and returns the change set that undoes everything since `beginRecording()`.
    public func endRecording(label: String) -> ChangeSet {
        let r = recorder ?? ChangeRecorder()
        recorder = nil
        return ChangeSet(label: label, items: r.items, collections: r.collections, smartFolders: r.smartFolders)
    }

    /// Runs `body` and returns the "before" state of everything it changed, ready to hand to `apply(_:)`.
    public func recording<T>(label: String, _ body: () async throws -> T) async throws -> (value: T, undo: ChangeSet) {
        beginRecording()
        do {
            let value = try await body()
            return (value, endRecording(label: label))
        } catch {
            _ = endRecording(label: label)
            throw error
        }
    }

    /// Restores the states in `changes`; returns the inverse (apply that to redo).
    @discardableResult
    public func apply(_ changes: ChangeSet) async throws -> ChangeSet {
        let (_, inverse) = try await recording(label: changes.label) {
            for (id, before) in changes.items {
                if var item = before {
                    item.updatedAt = .stashNow
                    item.updatedBy = userHandle
                    try await persist(item)
                } else if var current = try item(id: id) {
                    current.deletedAt = .stashNow      // an add is undone by moving it to Trash
                    current.updatedAt = .stashNow
                    current.updatedBy = userHandle
                    try await persist(current)
                }
            }
            for (id, before) in changes.collections {
                if var c = before {
                    c.updatedAt = .stashNow
                    c.updatedBy = userHandle
                    try await persistCollection(c)
                } else {
                    try await removeCollectionFile(id: id)
                }
            }
            for (id, before) in changes.smartFolders {
                if var f = before {
                    f.updatedAt = .stashNow
                    f.updatedBy = userHandle
                    try persistSmart(f)
                } else {
                    try removeSmartFile(id: id)
                }
            }
        }
        return inverse
    }

    func noteBefore(item id: String) {
        guard recorder != nil, recorder?.items.keys.contains(id) == false else { return }
        recorder?.items[id] = .some(try? item(id: id))
    }

    func noteBefore(collection id: String) {
        guard recorder != nil, recorder?.collections.keys.contains(id) == false else { return }
        recorder?.collections[id] = .some(readCollection(id: id))
    }

    func noteBefore(smart id: String) {
        guard recorder != nil, recorder?.smartFolders.keys.contains(id) == false else { return }
        recorder?.smartFolders[id] = .some(readSmart(id: id))
    }

    // MARK: Items: bulk edits

    @discardableResult
    public func updateItems(ids: [String], _ mutate: (inout Item) throws -> Void) async throws -> [Item] {
        var out: [Item] = []
        for id in ids { out.append(try await updateItem(id: id, mutate)) }
        return out
    }

    public func setLiked(_ liked: Bool, ids: [String]) async throws {
        try await updateItems(ids: ids) { $0.liked = liked }
    }

    public func setNote(_ note: String, ids: [String]) async throws {
        try await updateItems(ids: ids) { $0.note = note }
    }

    public func rename(id: String, to name: String) async throws {
        try await updateItem(id: id) { $0.name = name }
    }

    // MARK: Tags

    public func addTags(_ tags: [String], to ids: [String]) async throws {
        let add = Self.dedupeTags(tags)
        guard !add.isEmpty else { return }
        try await updateItems(ids: ids) { item in item.tags = Self.dedupeTags(item.tags + add) }
    }

    public func removeTags(_ tags: [String], from ids: [String]) async throws {
        let drop = Set(tags.map { $0.lowercased() })
        try await updateItems(ids: ids) { $0.tags.removeAll { drop.contains($0.lowercased()) } }
    }

    /// Renames a tag everywhere. If `new` already exists the two merge. Returns how many items changed.
    @discardableResult
    public func renameTag(_ old: String, to new: String, progress: (@Sendable (Int, Int) -> Void)? = nil) async throws -> Int {
        let target = new.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !target.isEmpty, old.lowercased() != target.lowercased() || old != target else { return 0 }
        let ids = try await index.itemIds(withTag: old)
        for (i, id) in ids.enumerated() {
            try await updateItem(id: id) { item in
                item.tags = Self.dedupeTags(item.tags.map { $0.lowercased() == old.lowercased() ? target : $0 })
            }
            if i % 25 == 0 { progress?(i + 1, ids.count) }
        }
        progress?(ids.count, ids.count)
        var meta = tagMetadata()
        if let m = meta[old.lowercased()] {
            meta[old.lowercased()] = nil
            if meta[target.lowercased()] == nil { meta[target.lowercased()] = m }
            try writeTagMetadata(meta)
        }
        return ids.count
    }

    @discardableResult
    public func deleteTag(_ tag: String) async throws -> Int {
        let ids = try await index.itemIds(withTag: tag)
        try await removeTags([tag], from: ids)
        var meta = tagMetadata()
        if meta.removeValue(forKey: tag.lowercased()) != nil { try writeTagMetadata(meta) }
        return ids.count
    }

    public func tagMetadata() -> [String: TagMeta] {
        guard let data = try? Data(contentsOf: layout.tagsURL),
              let file = try? StashJSON.decode(TagsFile.self, from: data) else { return [:] }
        return file.tags
    }

    func writeTagMetadata(_ meta: [String: TagMeta]) throws {
        try AtomicFile.writeJSON(TagsFile(tags: meta), to: layout.tagsURL)
    }

    public func setTagColor(_ hex: String?, for tag: String) throws {
        var meta = tagMetadata()
        var m = meta[tag.lowercased()] ?? TagMeta()
        m.color = hex
        meta[tag.lowercased()] = (m.color == nil && m.order == nil) ? nil : m
        try writeTagMetadata(meta)
    }

    // MARK: Collections

    func readCollection(id: String) -> StashCollection? {
        guard let data = try? Data(contentsOf: layout.collectionURL(id)) else { return nil }
        return try? StashJSON.decode(StashCollection.self, from: data)
    }

    func persistCollection(_ c: StashCollection) async throws {
        noteBefore(collection: c.id)
        let url = layout.collectionURL(c.id)
        try AtomicFile.writeJSON(c, to: url)
        try await index.upsertCollection(c, mtime: FileStat.mtime(url) ?? 0)
    }

    func removeCollectionFile(id: String) async throws {
        noteBefore(collection: id)
        try? FileManager.default.removeItem(at: layout.collectionURL(id))
        try await index.removeCollection(id: id)
    }

    @discardableResult
    public func updateCollection(id: String, _ mutate: (inout StashCollection) -> Void) async throws -> StashCollection {
        guard var c = readCollection(id: id) else { throw StashError.itemNotFound(id) }
        mutate(&c)
        c.id = id
        c.updatedAt = .stashNow
        c.updatedBy = userHandle
        try await persistCollection(c)
        return c
    }

    public func renameCollection(id: String, to name: String) async throws {
        try await updateCollection(id: id) { $0.name = name }
    }

    public func archiveCollection(id: String, _ archived: Bool) async throws {
        try await updateCollection(id: id) { $0.archived = archived }
    }

    public func setCover(itemId: String?, for collectionId: String) async throws {
        try await updateCollection(id: collectionId) { $0.coverItemId = itemId }
    }

    /// `id` and every collection beneath it. A folder therefore shows the union of its children's items.
    public func collectionTree(rootedAt id: String) async throws -> Set<String> {
        let all = try await index.collections()
        var out: Set<String> = [id]
        var frontier = [id]
        while let next = frontier.popLast() {
            for c in all where c.parentId == next && out.insert(c.id).inserted { frontier.append(c.id) }
        }
        return out
    }

    /// Moves a collection under `parentId` (nil = top level), placed after `afterSibling` (nil = first).
    public func moveCollection(id: String, toParent parentId: String?, after afterSibling: String? = nil) async throws {
        if let parentId, try await collectionTree(rootedAt: id).contains(parentId) { return } // would create a cycle
        let siblings = try await index.collections().filter { $0.parentId == parentId && $0.id != id }
        let lower = afterSibling.flatMap { a in siblings.first { $0.id == a }?.order }
        let upper = siblings.first { s in lower == nil ? true : s.order > (lower ?? "") }?.order
        let key = FractionalIndex.between(lower, upper)
        try await updateCollection(id: id) { $0.parentId = parentId; $0.order = key }
    }

    /// Deletes a collection file. Items lose the membership; children move up to the deleted collection's parent.
    public func deleteCollection(id: String) async throws {
        guard let c = readCollection(id: id) else { return }
        for child in try await index.collections() where child.parentId == id {
            try await updateCollection(id: child.id) { $0.parentId = c.parentId }
        }
        let members = try await index.itemIds(inCollection: id)
        try await updateItems(ids: members) { $0.collections[id] = nil }
        try await removeCollectionFile(id: id)
    }

    /// Copies a collection (and, for folders, everything beneath it) including item membership and order.
    @discardableResult
    public func duplicateCollection(id: String) async throws -> StashCollection {
        guard let original = readCollection(id: id) else { throw StashError.itemNotFound(id) }
        let siblings = try await index.collections().filter { $0.parentId == original.parentId }
        let after = siblings.first { $0.order > original.order }?.order
        var copy = original
        copy.id = ULID().string
        copy.name = original.name + " copy"
        copy.order = FractionalIndex.between(original.order, after)
        try await persistCollection(copy)
        let members = try await index.itemIds(inCollection: id)
        try await updateItems(ids: members) { item in
            if let key = item.collections[id] { item.collections[copy.id] = key }
        }
        for child in try await index.collections() where child.parentId == id {
            let childCopy = try await duplicateCollection(id: child.id)
            try await updateCollection(id: childCopy.id) { $0.parentId = copy.id; $0.name = child.name }
        }
        return copy
    }

    public func add(ids: [String], toCollection cid: String) async throws {
        var last = try await index.maxOrderKey(collectionId: cid)
        for id in ids {
            guard let item = try item(id: id), item.collections[cid] == nil else { continue }
            let key = FractionalIndex.after(last)
            last = key
            try await updateItem(id: id) { $0.collections[cid] = key }
        }
    }

    public func remove(ids: [String], fromCollection cid: String) async throws {
        try await updateItems(ids: ids) { $0.collections[cid] = nil }
    }

    public func move(ids: [String], from: String?, to: String) async throws {
        if let from { try await remove(ids: ids, fromCollection: from) }
        try await add(ids: ids, toCollection: to)
    }

    /// Places an item between two neighbours inside a collection (manual ordering).
    public func setOrder(itemId: String, in cid: String, after previous: String?, before next: String?) async throws {
        let key = FractionalIndex.between(previous, next)
        try await updateItem(id: itemId) { $0.collections[cid] = key }
    }

    // MARK: Smart folders

    func readSmart(id: String) -> SmartFolder? {
        guard let data = try? Data(contentsOf: layout.smartURL(id)) else { return nil }
        return try? StashJSON.decode(SmartFolder.self, from: data)
    }

    func persistSmart(_ f: SmartFolder) throws {
        noteBefore(smart: f.id)
        try AtomicFile.writeJSON(f, to: layout.smartURL(f.id))
    }

    func removeSmartFile(id: String) throws {
        noteBefore(smart: id)
        try? FileManager.default.removeItem(at: layout.smartURL(id))
    }

    public func smartFolders() -> [SmartFolder] {
        let urls = (try? FileManager.default.contentsOfDirectory(at: layout.smartDir, includingPropertiesForKeys: nil)) ?? []
        return urls.compactMap { url -> SmartFolder? in
            let name = url.lastPathComponent
            guard name.hasSuffix(".json"), !AtomicFile.isTemp(name), ULID.isValid(String(name.dropLast(5))),
                  let data = try? Data(contentsOf: url) else { return nil }
            return try? StashJSON.decode(SmartFolder.self, from: data)
        }.sorted { ($0.order, $0.id) < ($1.order, $1.id) }
    }

    @discardableResult
    public func createSmartFolder(name: String, match: String = "all", rules: [SmartRule]) throws -> SmartFolder {
        var f = SmartFolder(name: name, match: match, rules: rules, updatedBy: userHandle)
        f.order = FractionalIndex.after(smartFolders().last?.order)
        try persistSmart(f)
        return f
    }

    @discardableResult
    public func updateSmartFolder(id: String, _ mutate: (inout SmartFolder) -> Void) throws -> SmartFolder {
        guard var f = readSmart(id: id) else { throw StashError.itemNotFound(id) }
        mutate(&f)
        f.id = id
        f.updatedAt = .stashNow
        f.updatedBy = userHandle
        try persistSmart(f)
        return f
    }

    public func deleteSmartFolder(id: String) throws { try removeSmartFile(id: id) }
}

// MARK: Links
extension LibraryStore {
    public func snapshotURL(for id: String) -> URL { layout.itemDir(id).appendingPathComponent("snapshot.jpg") }

    /// Adds a web link as a card. Links are deduplicated by URL (the item's `sha256` is the hash of the URL).
    @discardableResult
    public func addLink(
        url: URL, title: String?, site: String?, author: String? = nil, summary: String? = nil, previewImage: Data? = nil,
        snapshot: Data? = nil, badge: String? = nil, tags: [String] = [], collectionIds: [String] = []
    ) async throws -> AddResult {
        let key = "link:" + url.absoluteString
        let hash = SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
        if let existingId = try await index.itemId(withSHA256: hash), let existing = try item(id: existingId) { return .duplicate(existing) }

        let id = ULID().string
        try FileManager.default.createDirectory(at: layout.itemDir(id), withIntermediateDirectories: true)
        var thumb: Data?
        if let previewImage { thumb = Thumbnailer.jpegThumbnail(forData: previewImage) }
        if let thumb { try AtomicFile.write(thumb, to: layout.thumbURL(id)) }
        var snap: Data?
        if let snapshot, let jpeg = Thumbnailer.jpegThumbnail(forData: snapshot, maxPixel: 1280) {
            snap = jpeg
            try AtomicFile.write(jpeg, to: snapshotURL(for: id))
        }
        var orders: [String: String] = [:]
        for cid in collectionIds { orders[cid] = FractionalIndex.after(try await index.maxOrderKey(collectionId: cid)) }
        var extras: [String: JSONValue] = ["linkDisplay": .string(thumb != nil ? "image" : (snap != nil ? "snapshot" : "title"))]
        if let summary, !summary.isEmpty { extras["summary"] = .string(summary) }
        if let badge { extras["badge"] = .string(badge) }
        let item = Item(
            id: id, kind: .link, file: nil, name: (title?.isEmpty == false ? title! : (CaptureClassifier.siteName(for: url) ?? url.absoluteString)),
            sha256: hash, source: ItemSource(url: nil, pageUrl: url.absoluteString, site: site, author: author, title: title),
            tags: Self.dedupeTags(tags), collections: orders, addedBy: userHandle, extras: extras
        )
        try await persist(item)
        return .added(item)
    }

    /// Replaces a link's page snapshot (and switches the card to show it).
    /// Accepts any image bytes (PNG from WebKit, JPEG from a browser tab) and stores a JPEG of at most 1280 px.
    public func setSnapshot(_ imageData: Data, for id: String, show: Bool = true) async throws {
        guard let item = try item(id: id), item.kind == .link else { throw StashError.itemNotFound(id) }
        guard let jpeg = Thumbnailer.jpegThumbnail(forData: imageData, maxPixel: 1280) else { throw CaptureError.unsupported("snapshot isn't an image") }
        try AtomicFile.write(jpeg, to: snapshotURL(for: id))
        if show { try await updateItem(id: id) { $0.extras["linkDisplay"] = .string("snapshot") } }
    }

    public func setLinkDisplay(_ mode: String, for id: String) async throws {
        try await updateItem(id: id) { $0.extras["linkDisplay"] = .string(mode) }
    }
}
