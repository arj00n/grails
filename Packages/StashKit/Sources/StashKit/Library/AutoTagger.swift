import Foundation

public struct AutoTagSummary: Sendable, Equatable {
    public var tagged = 0          // items that received at least one new tag
    public var checked = 0         // items looked at
    public var tagsAdded = 0
    public var skipped = 0         // no usable picture on this Mac (e.g. a placeholder not downloaded)
    public var failed = 0
}

public typealias TagClassifier = @Sendable (URL, ImageTaggerOptions) throws -> [TagSuggestion]

/// Finds items that haven't been auto-tagged and tags them on-device, one at a time, in the background.
/// Tags go into the item like any other (so they sync, search and filter), and the item remembers which ones the
/// machine added and when, so a re-run never undoes a person's edits.
public actor AutoTagger {
    private let store: LibraryStore
    private let classify: TagClassifier
    public var options: ImageTaggerOptions

    public init(
        store: LibraryStore, options: ImageTaggerOptions = .init(),
        classify: @escaping TagClassifier = { url, options in try ImageTagger.suggestions(forImageAt: url, options: options) }
    ) {
        self.store = store; self.options = options; self.classify = classify
    }

    public func setOptions(_ o: ImageTaggerOptions) { options = o }

    /// How many items are waiting. `addedBy` limits it to one person's items (so teammates don't all tag the same ones).
    public func pendingCount(addedBy: String? = nil) async -> Int {
        var q = ItemQuery()
        q.needsAutoTags = true
        q.addedBy = addedBy
        return (try? await store.index.count(q)) ?? 0
    }

    /// Tags everything pending (or exactly `ids` when given, even if already tagged: that's an explicit "do it again").
    /// `progress(done, total)` is called as it goes. Stops promptly when the surrounding task is cancelled.
    @discardableResult
    public func run(
        addedBy: String? = nil, ids: [String]? = nil, limit: Int = .max,
        progress: @Sendable (Int, Int) -> Void = { _, _ in }
    ) async -> AutoTagSummary {
        var summary = AutoTagSummary()
        var targets: [String]
        if let ids { targets = ids } else {
            var q = ItemQuery()
            q.needsAutoTags = true
            q.addedBy = addedBy
            q.sort = .addedDesc          // newest first: what you just saved gets tags first
            q.limit = limit
            targets = ((try? await store.index.query(q)) ?? []).map(\.id)
        }
        let total = targets.count
        progress(0, total)
        for (i, id) in targets.enumerated() {
            if Task.isCancelled { break }
            summary.checked += 1
            switch await tagOne(id, force: ids != nil) {
            case .tagged(let n): summary.tagged += 1; summary.tagsAdded += n
            case .nothingFound: break
            case .skipped: summary.skipped += 1
            case .failed: summary.failed += 1
            }
            progress(i + 1, total)
        }
        return summary
    }

    enum Outcome { case tagged(Int), nothingFound, skipped, failed }

    func tagOne(_ id: String, force: Bool) async -> Outcome {
        guard let item = try? await store.item(id: id), item.deletedAt == nil else { return .skipped }
        if !force, item.extras["autoTagged"] != nil { return .nothingFound }
        guard let source = pictureURL(for: item) else { return .skipped }
        let options = self.options
        let classify = self.classify
        // Vision work happens off the actor so reads and writes on the library stay responsive.
        let result: Result<[TagSuggestion], Error> = await Task.detached(priority: .utility) {
            Result { try classify(source, options) }
        }.value
        guard case .success(let suggestions) = result else { return .failed }
        do {
            let added = try await store.applyAutoTags(id: id, suggestions: suggestions, model: ImageTagger.modelName)
            return added > 0 ? .tagged(added) : .nothingFound
        } catch { return .failed }
    }

    /// The small shared thumbnail is plenty for classification and is always local, even when originals are streamed.
    private func pictureURL(for item: Item) -> URL? {
        let fm = FileManager.default
        let thumb = store.layout.thumbURL(item.id)
        if fm.fileExists(atPath: thumb.path), FileAvailability.of(thumb) == .local { return thumb }
        if item.kind == .link { return nil }
        guard let file = item.file else { return nil }
        let original = store.layout.itemDir(item.id).appendingPathComponent(file)
        guard fm.fileExists(atPath: original.path), FileAvailability.of(original) == .local else { return nil }
        return original
    }
}

extension Item {
    /// Tags the machine added (a subset of `tags`; a person may have removed some since).
    public var autoTags: [String] {
        guard case .array(let a)? = extras["autoTags"] else { return [] }
        let present = Set(tags.map { $0.lowercased() })
        return a.compactMap { if case .string(let s) = $0, present.contains(s.lowercased()) { s } else { nil } }
    }

    public var isAutoTagged: Bool { extras["autoTagged"] != nil }
}

extension LibraryStore {
    /// Adds the suggested tags that the item doesn't already have, and records that this item has been auto-tagged
    /// (even when nothing was added, so it isn't looked at again). Not part of undo: it's background housekeeping.
    /// Returns how many tags were added.
    @discardableResult
    public func applyAutoTags(id: String, suggestions: [TagSuggestion], model: String) async throws -> Int {
        guard var item = try item(id: id) else { throw StashError.itemNotFound(id) }
        var have = Set(item.tags.map { $0.lowercased() })
        var added: [String] = []
        for s in suggestions where have.insert(s.tag.lowercased()).inserted { item.tags.append(s.tag); added.append(s.tag) }
        var previous: [JSONValue] = []
        if case .array(let a)? = item.extras["autoTags"] { previous = a }
        let known = Set(previous.compactMap { if case .string(let s) = $0 { s.lowercased() } else { nil } })
        item.extras["autoTags"] = .array(previous + added.filter { !known.contains($0.lowercased()) }.map(JSONValue.string))
        item.extras["autoTagged"] = .object(["model": .string(model), "at": .double(Date().timeIntervalSince1970)])
        item.updatedAt = .stashNow
        item.updatedBy = userHandle
        try await persist(item, record: false)
        return added.count
    }
}
