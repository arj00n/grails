import Foundation

public struct BoardImportSummary: Sendable, Equatable {
    public var added = 0
    public var alreadyHad = 0       // identical item already in the library; now also in the collection
    public var failed = 0
    public var skipped: [String: Int] = [:]
    public var collectionId: String?
    public var collectionName = ""
    public var cancelled = false

    public var skippedCount: Int { skipped.values.reduce(0, +) }

    /// "Added 48 items to “Interiors”" plus whatever else is worth saying.
    public var headline: String {
        var s = "Added \(added) item\(added == 1 ? "" : "s")" + (collectionId == nil ? "" : " to “\(collectionName)”")
        var extra: [String] = []
        if alreadyHad > 0 { extra.append("\(alreadyHad) already in the library") }
        if failed > 0 { extra.append("\(failed) failed") }
        if skippedCount > 0 { extra.append("\(skippedCount) skipped (" + skipped.sorted { $0.key < $1.key }.map { "\($0.value) \($0.key)" }.joined(separator: ", ") + ")") }
        if !extra.isEmpty { s += ": " + extra.joined(separator: ", ") }
        return s
    }
}

extension BoardImporter {
    /// Saves every entry of `board` into `store`, inside one collection (reused if one with that name exists, so
    /// importing the same board again only brings in what's new). Four downloads at a time.
    public func run(
        _ board: RemoteBoard, into store: LibraryStore, service: LibraryCaptureService,
        collectionName: String? = nil, tags: [String] = [], concurrency: Int = 4,
        progress: @escaping @Sendable (Int, Int) -> Void = { _, _ in }
    ) async throws -> BoardImportSummary {
        let name = (collectionName ?? board.name).trimmingCharacters(in: .whitespacesAndNewlines)
        var summary = BoardImportSummary(skipped: board.skipped, collectionName: name.isEmpty ? board.ref.service : name)
        // A single post's media isn't a board: it lands loose in the library.
        let collectionId: String?
        if board.ref.isPost {
            collectionId = nil
        } else {
            let existing = try await store.index.collections().first { !$0.archived && $0.parentId == nil && $0.kind == "collection" && $0.name.lowercased() == summary.collectionName.lowercased() }
            let collection: GrailsCollection
            if let existing { collection = existing } else { collection = try await store.createCollection(name: summary.collectionName) }
            summary.collectionId = collection.id
            collectionId = collection.id
        }

        let total = board.entries.count
        progress(0, total)
        var next = 0, done = 0
        await withTaskGroup(of: Outcome.self) { group in
            func launch() {
                guard next < total, !Task.isCancelled else { return }
                let entry = board.entries[next]; next += 1
                group.addTask { await Self.save(entry, collectionId: collectionId, tags: tags, store: store, service: service) }
            }
            for _ in 0..<min(max(concurrency, 1), total) { launch() }
            for await outcome in group {
                done += 1
                switch outcome {
                case .added: summary.added += 1
                case .had: summary.alreadyHad += 1
                case .failed: summary.failed += 1
                }
                progress(done, total)
                launch()
            }
        }
        summary.cancelled = Task.isCancelled && done < total
        return summary
    }

    enum Outcome: Sendable { case added, had, failed }

    static func save(_ e: RemoteBoard.Entry, collectionId: String?, tags: [String], store: LibraryStore, service: LibraryCaptureService) async -> Outcome {
        // Files: first URL that downloads wins. Links (no file URL): saved as a link card.
        let attempts: [SaveRequest] = e.mediaUrls.isEmpty
            ? [SaveRequest(pageUrl: e.pageUrl, title: e.title, collectionId: collectionId, tags: tags, author: e.author)]
            : e.mediaUrls.map { SaveRequest(mediaUrl: $0, pageUrl: e.pageUrl, title: e.title, collectionId: collectionId, tags: tags, author: e.author) }
        for request in attempts {
            if Task.isCancelled { return .failed }
            guard let result = try? await service.save(request) else { continue }
            if result.duplicate {
                // identical content was already there (maybe filed elsewhere): file it in this collection too
                if let collectionId { try? await store.add(ids: [result.id], toCollection: collectionId) }
                return .had
            }
            return .added
        }
        return .failed
    }
}
