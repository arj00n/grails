import Foundation

public struct TransferResult: Sendable, Equatable {
    public var copiedItems = 0
    public var reusedItems = 0     // already in the destination (same content hash)
    public var collections = 0
    public var trashedInSource = 0
}

/// Copies or moves a collection (and everything inside it) from one library to another.
public enum LibraryTransfer {
    /// - Parameter move: when true the collection leaves the source; items that lived only in it are trashed there.
    @discardableResult
    public static func transferCollection(
        id: String, from src: LibraryStore, to dst: LibraryStore, move: Bool
    ) async throws -> TransferResult {
        var result = TransferResult()
        let tree = try await src.collectionTree(rootedAt: id)
        let allCollections = try await src.index.collections()
        let ordered = allCollections.filter { tree.contains($0.id) }

        // Re-create the folder structure in the destination under fresh ids.
        var idMap: [String: String] = [:]
        var rootSiblings = try await dst.index.collections().filter { $0.parentId == nil }
        for c in ordered { idMap[c.id] = ULID().string }
        for c in ordered {
            var copy = c
            copy.id = idMap[c.id]!
            copy.updatedBy = await dst.userHandle
            copy.coverItemId = nil
            if c.id == id {
                copy.parentId = nil
                copy.order = FractionalIndex.after(rootSiblings.last?.order)
                rootSiblings.append(copy)
            } else {
                copy.parentId = c.parentId.flatMap { idMap[$0] }
            }
            try await dst.persistCollection(copy)
            result.collections += 1
        }

        // Items: everything in any collection of the tree.
        var itemIds = Set<String>()
        for cid in tree { itemIds.formUnion(try await src.index.itemIds(inCollection: cid)) }
        var onlyHere: [String] = []
        for itemId in itemIds.sorted() {
            guard var item = try await src.item(id: itemId), item.deletedAt == nil else { continue }
            let memberships = item.collections.filter { tree.contains($0.key) }
            let mapped = Dictionary(uniqueKeysWithValues: memberships.compactMap { k, v in idMap[k].map { ($0, v) } })
            if item.collections.keys.allSatisfy({ tree.contains($0) }) { onlyHere.append(itemId) }

            if let sha = item.sha256, let existingId = try await dst.index.itemId(withSHA256: sha), var existing = try await dst.item(id: existingId) {
                for (k, v) in mapped { existing.collections[k] = v }
                existing.updatedAt = .grailsNow; existing.updatedBy = await dst.userHandle
                try await dst.persist(existing)
                try LibraryNotes.copyItem(itemId, from: src.layout, to: dst.layout)
                try await dst.reindexNoted(existing.id)
                result.reusedItems += 1
                continue
            }
            let srcDir = src.layout.itemDir(itemId)
            let dstDir = dst.layout.itemDir(itemId)
            let fm = FileManager.default
            if !fm.fileExists(atPath: dstDir.path) {
                try fm.createDirectory(at: dstDir, withIntermediateDirectories: true)
                for name in try fm.contentsOfDirectory(atPath: srcDir.path) where name != "item.json" && !AtomicFile.isTemp(name) {
                    try fm.copyItem(at: srcDir.appendingPathComponent(name), to: dstDir.appendingPathComponent(name))
                }
            }
            item.collections = mapped
            item.updatedAt = .grailsNow
            item.updatedBy = await dst.userHandle
            try await dst.persist(item)
            try LibraryNotes.copyItem(itemId, from: src.layout, to: dst.layout)
            try await dst.reindexNoted(itemId)
            result.copiedItems += 1
        }

        if move {
            for itemId in itemIds {
                if onlyHere.contains(itemId) { try await src.softDelete(ids: [itemId]); result.trashedInSource += 1 }
            }
            // delete deepest collections first so nothing gets re-parented on the way
            func depth(_ cid: String) -> Int {
                var d = 0
                var cur = allCollections.first { $0.id == cid }?.parentId
                while let p = cur, tree.contains(p) { d += 1; cur = allCollections.first { $0.id == p }?.parentId }
                return d
            }
            for cid in tree.sorted(by: { depth($0) > depth($1) }) { try await src.deleteCollection(id: cid) }
        }
        return result
    }
}
