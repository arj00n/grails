import Foundation

public struct AutoTagSummary: Sendable, Equatable {
    public var tagged = 0          // items that received at least one new tag
    public var checked = 0         // items looked at
    public var tagsAdded = 0
    public var skipped = 0         // no usable picture on this Mac (e.g. a placeholder not downloaded)
    public var failed = 0
    public var learned: [String] = []   // tags found too common to be useful here; removed from machine-tagged items
    public var pruned = 0               // how many item tags that removed
    public var merged = 0               // tags folded into a similar one that was already there
}

/// When a tag stops being informative: it sits on more than `maxShare` of the library (and at least `minCount` items).
/// Small libraries are left alone: with a few dozen items, a frequent tag is more likely a real theme than noise.
public struct CommonTagPolicy: Sendable {
    public var minLibrary = 40, minCount = 12
    public var maxShare = 0.25
    public init(minLibrary: Int = 40, minCount: Int = 12, maxShare: Double = 0.25) { self.minLibrary = minLibrary; self.minCount = minCount; self.maxShare = maxShare }
}

public typealias TagClassifier = @Sendable (URL, ImageTaggerOptions) async throws -> [TagSuggestion]

extension AutoTagger {
    /// The best classifier this Mac has: the on-device language model where it can see images (macOS 27 with Apple Intelligence),
    /// the photo classifier otherwise, and the photo classifier again for any single image the language model declines.
    public static let automatic: TagClassifier = { url, options in
        #if canImport(FoundationModels)
        if #available(macOS 27.0, *), LanguageModelTagger.isAvailable {
            if let tags = try? await LanguageModelTagger.suggestions(forImageAt: url, options: options), !tags.isEmpty { return tags }
        }
        #endif
        return try ImageTagger.suggestions(forImageAt: url, options: options)
    }

    /// Which engine `automatic` will use here, for what gets recorded on each item and shown in Settings.
    public static var engineName: String {
        #if canImport(FoundationModels)
        if #available(macOS 27.0, *), LanguageModelTagger.isAvailable { return LanguageModelTagger.modelName }
        #endif
        return ImageTagger.modelName
    }
}

/// Finds items that haven't been auto-tagged and tags them on-device, one at a time, in the background.
/// Tags go into the item like any other (so they sync, search and filter), and the item remembers which ones the
/// machine added and when, so a re-run never undoes a person's edits.
public actor AutoTagger {
    private let store: LibraryStore
    private let classify: TagClassifier
    private let modelName: String
    private var ignored: Set<String> = []
    private var vocabulary = TagVocabulary()
    public var options: ImageTaggerOptions
    public var policy = CommonTagPolicy()

    public init(
        store: LibraryStore, options: ImageTaggerOptions = .init(),
        classify: @escaping TagClassifier = AutoTagger.automatic
    ) {
        self.store = store; self.options = options; self.classify = classify
        self.modelName = AutoTagger.engineName
    }

    public func setOptions(_ o: ImageTaggerOptions) { options = o }

    /// A better engine than the basic photo classifier is in use: items the classifier tagged earlier are worth redoing.
    private var upgradeTarget: String? { modelName == ImageTagger.modelName ? nil : modelName }

    /// How many items are waiting. `addedBy` limits it to one person's items (so teammates don't all tag the same ones).
    public func pendingCount(addedBy: String? = nil) async -> Int {
        var q = ItemQuery()
        q.needsAutoTags = true
        q.upgradeAutoTagsTo = upgradeTarget
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
        ignored = await store.autoTagIgnored()
        vocabulary = (try? await store.tagVocabulary()) ?? TagVocabulary()
        var targets: [String]
        if let ids { targets = ids } else {
            var q = ItemQuery()
            q.needsAutoTags = true
            q.upgradeAutoTagsTo = upgradeTarget
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
        // A bulk run over the whole library (not a forced redo of chosen items) is when "too common" becomes clear.
        if ids == nil, !Task.isCancelled {
            let (learned, pruned) = await learnCommonTags()
            summary.learned = learned; summary.pruned = pruned
            summary.merged = ((try? await store.mergeSimilarTags()) ?? []).count
        }
        return summary
    }

    /// Tags the classifier keeps putting on a big share of this library say nothing about any one item. Remember not to
    /// suggest them here, and take them off the items the machine tagged. A person's own tags are never touched.
    func learnCommonTags() async -> (learned: [String], pruned: Int) {
        guard let total = try? await store.index.count(ItemQuery()), total >= policy.minLibrary,
              let counts = try? await store.index.tagCounts() else { return ([], 0) }
        let skip = await store.autoTagIgnored()
        let common = counts.filter { $0.count >= policy.minCount && Double($0.count) / Double(total) > policy.maxShare && !skip.contains($0.tag.lowercased()) }
        var learned: [String] = [], pruned = 0
        for c in common {
            if Task.isCancelled { break }
            var removed = 0
            for id in (try? await store.index.itemIds(withTag: c.tag)) ?? [] {
                if Task.isCancelled { break }
                if await (try? store.dropAutoTag(id: id, tag: c.tag)) == true { removed += 1 }
            }
            // only worth remembering if the machine was the one putting it there
            if removed > 0 { learned.append(c.tag.lowercased()); pruned += removed }
        }
        if !learned.isEmpty { try? await store.setAutoTagIgnored(learned, true) }
        return (learned, pruned)
    }

    enum Outcome { case tagged(Int), nothingFound, skipped, failed }

    func tagOne(_ id: String, force: Bool) async -> Outcome {
        guard let item = try? await store.item(id: id), item.deletedAt == nil else { return .skipped }
        if !force, item.isAutoTagged, item.autoTagModel == modelName || upgradeTarget == nil { return .nothingFound }
        guard let source = pictureURL(for: item) else { return .skipped }
        var options = self.options
        options.denylist.formUnion(ignored)          // learned noise doesn't take up one of the tag slots
        let classify = self.classify
        // Vision work happens off the actor so reads and writes on the library stay responsive.
        let result: Result<[TagSuggestion], Error> = await Task.detached(priority: .utility) {
            do { return .success(try await classify(source, options)) } catch { return .failure(error) }
        }.value
        guard case .success(let raw) = result else { return .failed }
        // "posters" when the library already says "poster": write it the way the library does
        var seen = Set<String>()
        let suggestions = raw.compactMap { s -> TagSuggestion? in
            let tag = vocabulary.canonical(s.tag)
            return seen.insert(tag.lowercased()).inserted ? TagSuggestion(tag: tag, confidence: s.confidence) : nil
        }
        do {
            let added = try await store.applyAutoTags(id: id, suggestions: suggestions, model: modelName)
            for s in suggestions { vocabulary.add(s.tag) }
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
    /// Which engine produced the automatic tags.
    public var autoTagModel: String? {
        if case .object(let o)? = extras["autoTagged"], case .string(let m)? = o["model"] { return m }
        return nil
    }
}

extension LibraryStore {
    /// Tags (lowercased) that auto-tagging must not suggest in this library.
    public func autoTagIgnored() -> Set<String> {
        Set(tagMetadata().filter { $0.value.noAuto == true }.keys)
    }

    public func setAutoTagIgnored(_ tags: [String], _ on: Bool) throws {
        var meta = tagMetadata()
        for t in tags {
            var m = meta[t.lowercased()] ?? TagMeta()
            m.noAuto = on ? true : nil
            meta[t.lowercased()] = m.isEmpty ? nil : m
        }
        try writeTagMetadata(meta)
    }

    /// Forgets everything learned about which tags are too common.
    public func resetAutoTagIgnored() throws {
        try setAutoTagIgnored(Array(autoTagIgnored()), false)
    }

    /// Removes `tag` from an item if (and only if) the machine added it. Returns whether it did.
    @discardableResult
    func dropAutoTag(id: String, tag: String) async throws -> Bool {
        guard var item = try item(id: id), item.autoTags.contains(where: { $0.lowercased() == tag.lowercased() }) else { return false }
        item.tags.removeAll { $0.lowercased() == tag.lowercased() }
        if case .array(let a)? = item.extras["autoTags"] {
            item.extras["autoTags"] = .array(a.filter { if case .string(let s) = $0 { s.lowercased() != tag.lowercased() } else { true } })
        }
        item.updatedAt = .grailsNow
        item.updatedBy = userHandle
        try await persist(item, record: false)
        return true
    }

    /// Adds the suggested tags that the item doesn't already have, and records that this item has been auto-tagged
    /// (even when nothing was added, so it isn't looked at again). Not part of undo: it's background housekeeping.
    /// Returns how many tags were added.
    @discardableResult
    public func applyAutoTags(id: String, suggestions: [TagSuggestion], model: String) async throws -> Int {
        guard var item = try item(id: id) else { throw GrailsError.itemNotFound(id) }
        // a re-tag (a better engine, or an explicit redo) replaces what the machine said before; a person's own tags stay
        let previousMachine = Set(item.autoTags.map { $0.lowercased() })
        if !previousMachine.isEmpty { item.tags.removeAll { previousMachine.contains($0.lowercased()) } }
        var have = Set(item.tags.map { $0.lowercased() })
        var added: [String] = []
        for s in suggestions where have.insert(s.tag.lowercased()).inserted { item.tags.append(s.tag); added.append(s.tag) }
        item.extras["autoTags"] = .array(added.map(JSONValue.string))
        item.extras["autoTagged"] = .object(["model": .string(model), "at": .double(Date().timeIntervalSince1970)])
        item.updatedAt = .grailsNow
        item.updatedBy = userHandle
        try await persist(item, record: false)
        return added.count
    }
}
