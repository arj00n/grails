import Foundation

public struct ExternalChangeSummary: Sendable, Equatable {
    public var added = 0
    public var updated = 0
    public var removed = 0
    public var conflictsMerged = 0
    public var collectionsChanged = false
    /// Canvas boards (by key) that changed on disk
    public var canvasBoards: Set<String> = []
    public var failures: [ScanFailure] = []
    public var notesChanged = false
    public var isEmpty: Bool { added + updated + removed + conflictsMerged == 0 && !collectionsChanged && canvasBoards.isEmpty && !notesChanged }
}

extension LibraryStore {
    /// Applies what a file watcher reported: only the affected items are re-read, not the whole library.
    /// Our own writes show up here too; they're recognised by an unchanged `item.json` mtime and cost one stat.
    @discardableResult
    public func applyExternalChanges(paths: [String]) async throws -> ExternalChangeSummary {
        var summary = ExternalChangeSummary()
        let itemsPrefix = layout.itemsDir.path + "/"
        let collectionsPrefix = layout.collectionsDir.path + "/"
        let canvasPrefix = layout.canvasDir.path + "/"
        let notesPrefix = layout.notesDir.path + "/"
        var ids = Set<String>()
        var collectionsTouched = false
        for path in paths {
            if AtomicFile.isTemp((path as NSString).lastPathComponent) { continue }
            if path.hasPrefix(itemsPrefix) {
                let first = path.dropFirst(itemsPrefix.count).split(separator: "/", maxSplits: 1).first.map(String.init)
                if let first, !first.hasPrefix(".") { ids.insert(first) }
            } else if path.hasPrefix(collectionsPrefix) || path == layout.collectionsDir.path {
                collectionsTouched = true
            } else if path.hasPrefix(notesPrefix) || path == layout.notesDir.path {
                summary.notesChanged = true
            } else if path.hasPrefix(canvasPrefix) {
                let file = String(path.dropFirst(canvasPrefix.count))
                if file.hasSuffix(".json") { summary.canvasBoards.insert(String(file.prefix { $0 != " " && $0 != "." })) }
            }
        }

        let fm = FileManager.default
        if !summary.canvasBoards.isEmpty { summary.conflictsMerged += (try? ConflictMerger.mergeCanvasConflicts(in: layout.canvasDir)) ?? 0 }
        let known = try await index.mtimes(for: Array(ids))
        var toRead: [URL] = []
        var gone: [String] = []
        for id in ids {
            let folder = layout.itemDir(id)
            guard fm.fileExists(atPath: folder.path) else { if known[id] != nil { gone.append(id) }; continue }
            if let names = try? fm.contentsOfDirectory(atPath: folder.path), names.contains(where: ConflictMerger.isItemConflictCopy) {
                summary.conflictsMerged += (try? ConflictMerger.mergeItemConflicts(in: folder)) ?? 0
            }
            guard let mtime = FileStat.mtime(folder.appendingPathComponent("item.json")) else { if known[id] != nil { gone.append(id) }; continue }
            if known[id] != mtime { toRead.append(folder) }
        }
        let scan = await ItemScanner.scan(folders: toRead)
        summary.failures = scan.failures
        for e in scan.items { if known[e.item.id] == nil { summary.added += 1 } else { summary.updated += 1 } }
        try await index.upsert(scan.items.map { (forSearch($0.item), $0.mtime) })
        try await index.remove(ids: gone)
        summary.removed = gone.count

        if summary.notesChanged {
            summary.conflictsMerged += LibraryNotes.foldConflicts(in: layout)
            _ = try await reindexNoteSearch()
            notesStamp = FileStat.mtime(layout.notesDir) ?? 0
        }
        if collectionsTouched {
            summary.conflictsMerged += (try? ConflictMerger.mergeCollectionConflicts(in: layout.collectionsDir)) ?? 0
            let before = try await index.collections().map { "\($0.id)|\($0.name)|\($0.parentId ?? "")|\($0.order)|\($0.archived)" }
            try await index.replaceCollections(LibraryIndex.readCollections(layout))
            let after = try await index.collections().map { "\($0.id)|\($0.name)|\($0.parentId ?? "")|\($0.order)|\($0.archived)" }
            summary.collectionsChanged = before != after
        }
        return summary
    }
}
