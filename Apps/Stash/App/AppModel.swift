import AppKit
import Observation
import StashKit
import UniformTypeIdentifiers

enum Source: Hashable {
    case inbox, all, liked, untagged, trash
    case collection(String)
    case smart(String)
    case tag(String)
}

enum GridLayoutMode: String, CaseIterable, Identifiable {
    case square, masonry
    var id: String { rawValue }
    var label: String { self == .square ? "Square" : "Masonry" }
    var symbol: String { self == .square ? "square.grid.2x2" : "rectangle.3.group" }
}

/// Zoom steps are target tile widths in points. The last one is "Fit" (one big tile per row on most windows).
enum Zoom {
    static let widths: [CGFloat] = [90, 130, 190, 280, 420, 680]
    static let labels = ["XS", "S", "M", "L", "XL", "Fit"]
    static let maxStep = widths.count - 1
}

enum SortChoice: String, CaseIterable, Identifiable {
    case newest, oldest, nameAZ, nameZA, largest, random
    var id: String { rawValue }
    var label: String {
        switch self {
        case .newest: "Newest first"
        case .oldest: "Oldest first"
        case .nameAZ: "Name (A–Z)"
        case .nameZA: "Name (Z–A)"
        case .largest: "Largest first"
        case .random: "Random"
        }
    }
    var itemSort: ItemSort {
        switch self {
        case .newest, .random: .addedDesc
        case .oldest: .addedAsc
        case .nameAZ: .nameAsc
        case .nameZA: .nameDesc
        case .largest: .sizeDesc
        }
    }
}

struct ViewFilters: Equatable {
    var images = false, videos = false, gifs = false, square = false, liked = false
    var isActive: Bool { images || videos || gifs || square || liked }
    var kinds: Set<ItemKind> {
        var k: Set<ItemKind> = []
        if images { k.formUnion([.image, .raw, .svg, .vector]) }
        if videos { k.insert(.video) }
        if gifs { k.insert(.gif) }
        return k
    }
}

enum Panel: Equatable { case commandK, tags, move, note }

struct PromptRequest: Identifiable {
    let id = UUID()
    var title: String
    var message: String = ""
    var placeholder: String = "Name"
    var initial: String = ""
    var confirmTitle: String = "OK"
    var onSubmit: @MainActor (String) -> Void
}

struct ConfirmRequest: Identifiable {
    let id = UUID()
    var title: String
    var message: String
    var confirmTitle: String
    var destructive = true
    var onConfirm: @MainActor () -> Void
}

struct SmartEditorState: Identifiable {
    let id = UUID()
    var existingId: String?
    var name = "Untitled smart folder"
    var match = "all"
    var rules: [SmartRule] = [SmartRule(field: "kind", op: "is", value: "image")]
}

@MainActor @Observable
final class AppModel {
    var store: LibraryStore?
    var layout: LibraryLayout?
    var libraryName = "Stash"

    var source: Source = .all {
        didSet {
            guard oldValue != source else { return }
            selection = []
            if !searchText.isEmpty { searchText = "" } else { reloadSoon() }
        }
    }
    private(set) var items: [ItemSummary] = []
    /// Bumped on every reload so the grid can skip O(n) diffing.
    private(set) var itemsVersion = 0
    var selection: Set<String> = []
    private(set) var collections: [StashCollection] = []
    private(set) var smartFolders: [SmartFolder] = []
    private(set) var tags: [(tag: String, count: Int)] = []
    /// lowercased tag → "#RRGGBB"
    private(set) var tagColors: [String: String] = [:]
    private(set) var totalCount = 0

    var searchText = "" { didSet { if oldValue != searchText { reloadSoon() } } }
    private(set) var recentSearches: [String] = UserDefaults.standard.stringArray(forKey: "recentSearches") ?? []
    var filters = ViewFilters() { didSet { if oldValue != filters { reloadSoon() } } }
    var sort: SortChoice = .newest { didSet { if oldValue != sort { reloadSoon() } } }
    private var shuffleSeed: UInt64 = 1

    var showInfo = false
    var previewID: String?
    var panel: Panel?
    var prompt: PromptRequest?
    var confirm: ConfirmRequest?
    var smartEditor: SmartEditorState?
    var toast: String?
    var cheatSheetVisible = false
    /// Grid asks for keyboard focus whenever this changes.
    private(set) var focusGridTick = 0
    var searchFocusTick = 0
    var errorMessage: String?
    var importProgress: (done: Int, total: Int)?
    var renameProgress: (done: Int, total: Int)?

    private(set) var undoStack: [ChangeSet] = []
    private(set) var redoStack: [ChangeSet] = []
    var undoTitle: String? { undoStack.last.map { "Undo \($0.label)" } }
    var redoTitle: String? { redoStack.last.map { "Redo \($0.label)" } }

    var zoomStep: Int { didSet { UserDefaults.standard.set(zoomStep, forKey: "zoomStep") } }
    var layoutMode: GridLayoutMode { didSet { UserDefaults.standard.set(layoutMode.rawValue, forKey: "layoutMode") } }

    private var reloadTask: Task<Void, Never>?
    /// Reloads can overlap (an undoable action's reload vs one triggered by typing in search); only the newest may apply.
    private var reloadGeneration = 0
    private var toastTask: Task<Void, Never>?
    @ObservationIgnored private var cheatMonitor: Any?
    @ObservationIgnored private var cheatTask: Task<Void, Never>?

    init() {
        let d = UserDefaults.standard
        // `integer(forKey:)` also reads values passed as launch arguments, which arrive as strings.
        zoomStep = min(max(d.object(forKey: "zoomStep") == nil ? 2 : d.integer(forKey: "zoomStep"), 0), Zoom.maxStep)
        layoutMode = GridLayoutMode(rawValue: d.string(forKey: "layoutMode") ?? "") ?? .square
        showInfo = ProcessInfo.processInfo.environment["STASH_SHOW_INFO"] != nil   // dev/UI tests
    }

    // MARK: Library lifecycle

    /// Opens the library named by STASH_LIBRARY (tests), the last used one, or creates the default.
    func openInitialLibrary() async {
        let env = ProcessInfo.processInfo.environment
        let url: URL
        if let p = env["STASH_LIBRARY"] {
            url = URL(fileURLWithPath: p)
        } else if let saved = UserDefaults.standard.string(forKey: "libraryPath") {
            url = URL(fileURLWithPath: saved)
        } else {
            url = Self.defaultLibraryURL
        }
        // Dev/UI tests: STASH_SEED=<n> fills a library that doesn't exist yet with n synthetic items.
        if let seed = env["STASH_SEED"].flatMap(Int.init), !FileManager.default.fileExists(atPath: url.appendingPathComponent("library.json").path) {
            // STASH_SEED_PLAIN=1: no collections and no liked items, for predictable UI tests
            let plain = env["STASH_SEED_PLAIN"] != nil
            _ = try? FixtureLibrary.generate(at: url, count: seed, collections: plain ? 0 : 20, likedOneIn: plain ? 0 : 10)
        }
        await openOrCreate(at: url, remember: env["STASH_LIBRARY"] == nil)
    }

    static var defaultLibraryURL: URL {
        FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask)[0].appendingPathComponent("Stash Library.stash")
    }

    var userHandle: String { UserDefaults.standard.string(forKey: "userHandle") ?? StashPaths.defaultUserHandle }

    func openOrCreate(at url: URL, remember: Bool = true) async {
        do {
            let index = ProcessInfo.processInfo.environment["STASH_INDEX_PATH"].map { try? LibraryIndex(path: URL(fileURLWithPath: $0)) } ?? nil
            let store: LibraryStore
            if FileManager.default.fileExists(atPath: url.appendingPathComponent("library.json").path) {
                store = try await LibraryStore.open(at: url, index: index, userHandle: userHandle, rescan: false)
            } else {
                store = try LibraryStore.create(at: url, name: url.deletingPathExtension().lastPathComponent, index: index, userHandle: userHandle)
            }
            self.store = store
            layout = store.layout
            libraryName = await store.manifest.name
            if remember { UserDefaults.standard.set(url.path, forKey: "libraryPath") }
            selection = []
            undoStack = []
            redoStack = []
            await reload()
            Self.logLaunchTime()
            if ProcessInfo.processInfo.environment["STASH_AUTOLIKE"] != nil, let first = items.first {
                toggleLike(ids: [first.id])
            }
            // Dev/UI tests: STASH_PANEL=note|tags|move|commandK opens that panel right away (with the first item selected).
            if let name = ProcessInfo.processInfo.environment["STASH_PANEL"] {
                if let first = items.first { selection = [first.id] }
                panel = ["note": .note, "tags": .tags, "move": .move, "commandK": .commandK][name]
            }
            if let text = ProcessInfo.processInfo.environment["STASH_AUTONOTE"], let first = items.first {
                // mirrors NotePanel.save(): close the panel, then record a note edit
                Task {
                    try? await Task.sleep(for: .seconds(2))
                    closePanel()
                    await perform("Edit Note") { try await $0.setNote(text, ids: [first.id]) }
                }
            }
            // The grid is already showing the index; pick up changes made on disk (other Macs) afterwards.
            Task {
                if let r = try? await store.rescan(), r.added + r.updated + r.removed + r.conflictsMerged > 0 { await reload() }
                _ = try? await store.snapshotIfNeeded()
            }
        } catch {
            errorMessage = "Couldn't open the library: \(error.localizedDescription)"
        }
    }

    private static var logged = false
    /// Dev: STASH_LAUNCH_LOG=1 prints process-start → first populated grid, in ms.
    private static func logLaunchTime() {
        guard !logged, ProcessInfo.processInfo.environment["STASH_LAUNCH_LOG"] != nil else { return }
        logged = true
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        guard sysctl(&mib, 4, &info, &size, nil, 0) == 0 else { return }
        let start = Double(info.kp_proc.p_un.__p_starttime.tv_sec) + Double(info.kp_proc.p_un.__p_starttime.tv_usec) / 1e6
        print("launchToItemsMs=\(Int((Date().timeIntervalSince1970 - start) * 1000))")
        fflush(stdout)
    }

    // MARK: Data

    func reloadSoon() {
        reloadTask?.cancel()
        reloadTask = Task { await reload() }
    }

    var isSearching: Bool { !searchText.trimmingCharacters(in: .whitespaces).isEmpty }

    private func makeQuery(store: LibraryStore, smartFolders: [SmartFolder]) async throws -> ItemQuery {
        var q = ItemQuery()
        q.limit = Int.max
        if isSearching {
            q.text = searchText
        } else {
            switch source {
            case .inbox: q.unfiled = true
            case .all: break
            case .liked: q.likedOnly = true
            case .untagged: q.untagged = true
            case .trash: q.deleted = true
            case .collection(let id): q.collectionIds = try await store.collectionTree(rootedAt: id)
            case .smart(let id): q.smart = smartFolders.first { $0.id == id }
            case .tag(let t): q.tag = t
            }
        }
        q.kinds = filters.kinds
        if filters.liked { q.likedOnly = true }
        q.squareOnly = filters.square
        if sort != .newest || !isSearching { q.sort = sort.itemSort }
        return q
    }

    /// Reads everything the window shows into locals first and applies it in one go, so an older, slower reload can
    /// never overwrite a newer one's data piecemeal.
    func reload() async {
        guard let store else { return }
        reloadGeneration += 1
        let generation = reloadGeneration
        do {
            let smart = await store.smartFolders()
            let colls = try await store.index.collections()
            let q = try await makeQuery(store: store, smartFolders: smart)
            var result = try await store.index.query(q)
            let tagList = try await store.index.tagCounts().map { (tag: $0.tag, count: $0.count) }
            let colors = await store.tagMetadata().compactMapValues(\.color)
            let total = try await store.index.count(ItemQuery())
            guard !Task.isCancelled, generation == reloadGeneration else { return }
            if sort == .random { result = Self.shuffled(result, seed: shuffleSeed) }
            smartFolders = smart
            collections = colls
            items = result
            itemsVersion += 1
            selection.formIntersection(Set(result.map(\.id)))
            tags = tagList
            tagColors = colors
            totalCount = total
        } catch {
            errorMessage = "Couldn't load items: \(error.localizedDescription)"
        }
    }

    private static func shuffled(_ items: [ItemSummary], seed: UInt64) -> [ItemSummary] {
        struct RNG: RandomNumberGenerator {
            var s: UInt64
            mutating func next() -> UInt64 {
                s &+= 0x9E37_79B9_7F4A_7C15
                var z = s
                z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
                z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
                return z ^ (z >> 31)
            }
        }
        var rng = RNG(s: seed)
        return items.shuffled(using: &rng)
    }

    var countLabel: String { "\(items.count.formatted()) \(items.count == 1 ? "item" : "items")" }

    var title: String {
        if isSearching { return "Search: \(searchText)" }
        switch source {
        case .inbox: return "Inbox"
        case .all: return "All"
        case .liked: return "Liked"
        case .untagged: return "Untagged"
        case .trash: return "Trash"
        case .collection(let id): return collections.first { $0.id == id }?.name ?? "Collection"
        case .smart(let id): return smartFolders.first { $0.id == id }?.name ?? "Smart folder"
        case .tag(let t): return "#\(t)"
        }
    }

    func summary(_ id: String) -> ItemSummary? { items.first { $0.id == id } }
    var selectedSummaries: [ItemSummary] { items.filter { selection.contains($0.id) } }

    func rememberSearch() {
        let t = searchText.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return }
        recentSearches = ([t] + recentSearches.filter { $0.caseInsensitiveCompare(t) != .orderedSame }).prefix(3).map { $0 }
        UserDefaults.standard.set(recentSearches, forKey: "recentSearches")
    }

    // MARK: Undoable operations

    /// Runs `body` while the store notes the state it overwrites; returns the result and the undo change set.
    private func recorded<T>(_ label: String, in store: LibraryStore, _ body: () async throws -> T) async throws -> (T, ChangeSet) {
        await store.beginRecording()
        do {
            let value = try await body()
            return (value, await store.endRecording(label: label))
        } catch {
            _ = await store.endRecording(label: label)
            throw error
        }
    }

    /// Runs a library mutation, records what it changed for undo, and refreshes the grid.
    @discardableResult
    func perform<T: Sendable>(_ label: String, _ body: @escaping @Sendable (LibraryStore) async throws -> T) async -> T? {
        guard let store else { return nil }
        do {
            let (value, undo) = try await recorded(label, in: store) { try await body(store) }
            if !undo.isEmpty {
                undoStack.append(undo)
                if undoStack.count > 100 { undoStack.removeFirst() }
                redoStack = []
            }
            await reload()
            return value
        } catch {
            errorMessage = "\(label) failed: \(error.localizedDescription)"
            return nil
        }
    }

    func undo() async {
        guard let store, let cs = undoStack.popLast() else { return }
        do {
            let inverse = try await store.apply(cs)
            redoStack.append(inverse)
            await reload()
            showToast(cs.label.isEmpty ? "Undone" : "Undid \(cs.label.lowercased())")
        } catch { errorMessage = "Undo failed: \(error.localizedDescription)" }
    }

    func redo() async {
        guard let store, let cs = redoStack.popLast() else { return }
        do {
            let inverse = try await store.apply(cs)
            undoStack.append(inverse)
            await reload()
            showToast("Redid \(cs.label.lowercased())")
        } catch { errorMessage = "Redo failed: \(error.localizedDescription)" }
    }

    func showToast(_ text: String) {
        toast = text
        toastTask?.cancel()
        toastTask = Task {
            try? await Task.sleep(for: .seconds(2.2))
            if !Task.isCancelled { toast = nil }
        }
    }

    // MARK: Import

    func importFiles(_ urls: [URL], collectionId: String? = nil, tag: String? = nil) async {
        guard let store else { return }
        let files = FolderScanner.expandFiles(urls)
        guard !files.isEmpty else { return }
        var collectionIds: [String] = []
        if let collectionId { collectionIds = [collectionId] } else if case .collection(let id) = source { collectionIds = [id] }
        var tagList: [String] = []
        if let tag { tagList = [tag] } else if case .tag(let t) = source { tagList = [t] }
        let finalCollections = collectionIds, finalTags = tagList
        importProgress = (0, files.count)
        var done = 0
        do {
            let (_, undo) = try await recorded("Add \(files.count) \(files.count == 1 ? "Item" : "Items")", in: store) {
                for chunk in stride(from: 0, to: files.count, by: 4).map({ Array(files[$0..<min($0 + 4, files.count)]) }) {
                    await withTaskGroup(of: Void.self) { group in
                        for file in chunk {
                            group.addTask { _ = try? await store.addItem(fileAt: file, tags: finalTags, collectionIds: finalCollections) }
                        }
                    }
                    done += chunk.count
                    importProgress = (done, files.count)
                }
            }
            if !undo.isEmpty { undoStack.append(undo); redoStack = [] }
        } catch { errorMessage = "Import failed: \(error.localizedDescription)" }
        importProgress = nil
        await reload()
    }

    // MARK: Actions (menu items, grid shortcuts, ⌘K)

    func run(_ action: ShortcutAction) {
        #if DEBUG
        if ProcessInfo.processInfo.environment["STASH_TRACE"] != nil {
            let line = "\(Date()) run(\(action.rawValue)) panel=\(String(describing: panel)) event=\(String(describing: NSApp.currentEvent))\n"
            if let h = FileHandle(forWritingAtPath: "/private/tmp/stash-actions.log") { h.seekToEndOfFile(); h.write(Data(line.utf8)); try? h.close() }
            else { try? line.write(toFile: "/private/tmp/stash-actions.log", atomically: true, encoding: .utf8) }
        }
        #endif
        switch action {
        case .toggleInfo: showInfo.toggle()
        case .like: toggleLike(ids: Array(selection))
        case .note: if !selection.isEmpty { panel = .note }
        case .move: if !selection.isEmpty { panel = .move }
        case .tag: if !selection.isEmpty { panel = .tags }
        case .copyURL: copySourceURL()
        case .shuffle:
            shuffleSeed = UInt64.random(in: 1...UInt64.max)
            if sort == .random { reloadSoon() } else { sort = .random }
        case .trash: trashSelection()
        case .commandPalette: panel = .commandK
        case .zoomIn: zoomStep = min(zoomStep + 1, Zoom.maxStep)
        case .zoomOut: zoomStep = max(zoomStep - 1, 0)
        case .newCollection: promptNewCollection(kind: "collection", parent: nil)
        case .newSmartFolder: smartEditor = SmartEditorState()
        }
    }

    func toggleLike(ids: [String]) {
        guard !ids.isEmpty else { return }
        let all = ids.allSatisfy { summary($0)?.liked == true }
        let like = !all
        Task { await perform(like ? "Like" : "Unlike") { try await $0.setLiked(like, ids: ids) } }
    }

    func trashSelection() {
        let ids = Array(selection)
        guard !ids.isEmpty, source != .trash else { return }
        Task {
            await perform("Move to Trash") { try await $0.softDelete(ids: ids) }
            showToast("Moved \(ids.count) \(ids.count == 1 ? "item" : "items") to Trash")
        }
    }

    func restoreSelection() {
        let ids = Array(selection)
        guard !ids.isEmpty else { return }
        Task { await perform("Restore") { try await $0.restore(ids: ids) } }
    }

    func confirmEmptyTrash() {
        confirm = ConfirmRequest(
            title: "Empty Trash?",
            message: "Items in the Trash are removed from the library. A copy stays in the library's .trash folder for 30 days.",
            confirmTitle: "Empty Trash"
        ) { [weak self] in
            guard let self, let store = self.store else { return }
            Task {
                _ = try? await store.emptyTrash()
                await self.reload()
            }
        }
    }

    func copySourceURL() {
        guard let first = selectedSummaries.first, let store else { return }
        Task {
            guard let item = try? await store.item(id: first.id), let s = item.source?.pageUrl ?? item.source?.url else {
                showToast("No source URL for this item")
                return
            }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(s, forType: .string)
            showToast("Copied source URL")
        }
    }

    // MARK: Collections

    func promptNewCollection(kind: String, parent: String?, thenAdd ids: [String] = []) {
        prompt = PromptRequest(
            title: kind == "folder" ? "New Folder" : "New Collection", placeholder: "Name", confirmTitle: "Create"
        ) { [weak self] name in
            guard let self, !name.isEmpty else { return }
            Task {
                let created = await self.perform(kind == "folder" ? "New Folder" : "New Collection") { store in
                    let c = try await store.createCollection(name: name, kind: kind, parentId: parent)
                    if !ids.isEmpty { try await store.add(ids: ids, toCollection: c.id) }
                    return c.id
                }
                if let created { self.source = .collection(created) }
            }
        }
    }

    func promptRenameCollection(_ c: StashCollection) {
        prompt = PromptRequest(title: "Rename", placeholder: "Name", initial: c.name, confirmTitle: "Rename") { [weak self] name in
            guard let self, !name.isEmpty, name != c.name else { return }
            Task { await self.perform("Rename Collection") { try await $0.renameCollection(id: c.id, to: name) } }
        }
    }

    func confirmDeleteCollection(_ c: StashCollection) {
        confirm = ConfirmRequest(
            title: "Delete “\(c.name)”?",
            message: "Items stay in your library; they just leave this \(c.kind == "folder" ? "folder" : "collection"). You can undo this.",
            confirmTitle: "Delete"
        ) { [weak self] in
            guard let self else { return }
            Task {
                await self.perform("Delete Collection") { try await $0.deleteCollection(id: c.id) }
                if self.source == .collection(c.id) { self.source = .all }
            }
        }
    }

    func duplicateCollection(_ c: StashCollection) {
        Task { await perform("Duplicate Collection") { try await $0.duplicateCollection(id: c.id).id } }
    }

    func archiveCollection(_ c: StashCollection, _ archived: Bool) {
        Task {
            await perform(archived ? "Archive Collection" : "Unarchive Collection") { try await $0.archiveCollection(id: c.id, archived) }
            if archived, source == .collection(c.id) { source = .all }
        }
    }

    func setCoverFromSelection(_ c: StashCollection) {
        guard let id = selection.first else { showToast("Select an item first"); return }
        Task { await perform("Set Cover") { try await $0.setCover(itemId: id, for: c.id) } }
    }

    func moveCollection(_ id: String, intoFolder folder: String) {
        Task { await perform("Move Collection") { try await $0.moveCollection(id: id, toParent: folder) } }
    }

    func moveCollection(_ id: String, after target: StashCollection) {
        Task { await perform("Reorder Collections") { try await $0.moveCollection(id: id, toParent: target.parentId, after: target.id) } }
    }

    // MARK: Tags

    func toggleTag(_ tag: String, on ids: [String]) {
        let present = ids.allSatisfy { id in tagsOf(id).contains { $0.caseInsensitiveCompare(tag) == .orderedSame } }
        Task {
            await perform(present ? "Remove Tag" : "Add Tag") { store in
                if present { try await store.removeTags([tag], from: ids) } else { try await store.addTags([tag], to: ids) }
            }
        }
    }

    /// Tags for an item in the current grid, read lazily from the tag index (cheap enough for a handful of ids).
    private var tagCache: [String: [String]] = [:]
    func tagsOf(_ id: String) -> [String] { tagCache[id] ?? [] }

    func loadTags(for ids: [String]) async -> [String: [String]] {
        guard let store else { return [:] }
        var out: [String: [String]] = [:]
        for id in ids { out[id] = (try? await store.item(id: id))?.tags ?? [] }
        tagCache.merge(out) { _, new in new }
        return out
    }

    func promptRenameTag(_ tag: String) {
        prompt = PromptRequest(title: "Rename Tag", message: "If the new name already exists, the two tags merge.", placeholder: "Tag", initial: tag, confirmTitle: "Rename") { [weak self] name in
            guard let self, !name.isEmpty, name != tag, let store = self.store else { return }
            Task {
                self.renameProgress = (0, 1)
                do {
                    let (_, undo) = try await self.recorded("Rename Tag", in: store) {
                        try await store.renameTag(tag, to: name) { done, total in
                            Task { @MainActor in self.renameProgress = (done, total) }
                        }
                    }
                    if !undo.isEmpty { self.undoStack.append(undo); self.redoStack = [] }
                } catch { self.errorMessage = "Rename failed: \(error.localizedDescription)" }
                self.renameProgress = nil
                if self.source == .tag(tag) { self.source = .tag(name) }
                await self.reload()
            }
        }
    }

    func confirmDeleteTag(_ tag: String) {
        confirm = ConfirmRequest(title: "Delete tag “\(tag)”?", message: "The tag is removed from every item. You can undo this.", confirmTitle: "Delete Tag") { [weak self] in
            guard let self else { return }
            Task {
                await self.perform("Delete Tag") { try await $0.deleteTag(tag) }
                if self.source == .tag(tag) { self.source = .all }
            }
        }
    }

    func setTagColor(_ hex: String?, for tag: String) {
        guard let store else { return }
        Task {
            try? await store.setTagColor(hex, for: tag)
            await reload()
        }
    }

    // MARK: Smart folders

    func editSmartFolder(_ f: SmartFolder) {
        smartEditor = SmartEditorState(existingId: f.id, name: f.name, match: f.match, rules: f.rules)
    }

    func saveSmartFolder(_ s: SmartEditorState) {
        Task {
            let id = await perform(s.existingId == nil ? "New Smart Folder" : "Edit Smart Folder") { store -> String in
                if let id = s.existingId {
                    try await store.updateSmartFolder(id: id) { $0.name = s.name; $0.match = s.match; $0.rules = s.rules }
                    return id
                }
                return try await store.createSmartFolder(name: s.name, match: s.match, rules: s.rules).id
            }
            if let id { source = .smart(id) }
        }
    }

    func deleteSmartFolder(_ f: SmartFolder) {
        Task {
            await perform("Delete Smart Folder") { try await $0.deleteSmartFolder(id: f.id) }
            if source == .smart(f.id) { source = .all }
        }
    }

    // MARK: Drops

    enum DropTarget { case collection(String), tag(String), trash }

    func dropItems(ids: [String], onto target: DropTarget) {
        guard !ids.isEmpty else { return }
        switch target {
        case .collection(let cid):
            let name = collections.first { $0.id == cid }?.name ?? "collection"
            Task {
                await perform("Add to Collection") { try await $0.add(ids: ids, toCollection: cid) }
                showToast("Added \(ids.count) \(ids.count == 1 ? "item" : "items") to \(name)")
            }
        case .tag(let t):
            Task {
                await perform("Add Tag") { try await $0.addTags([t], to: ids) }
                showToast("Tagged \(ids.count) \(ids.count == 1 ? "item" : "items") #\(t)")
            }
        case .trash:
            Task { await perform("Move to Trash") { try await $0.softDelete(ids: ids) } }
        }
    }

    // MARK: Cheat sheet (hold ⌘)

    func startCheatSheetMonitor() {
        guard cheatMonitor == nil else { return }
        cheatMonitor = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged, .keyDown, .leftMouseDown]) { [weak self] e in
            #if DEBUG
            if ProcessInfo.processInfo.environment["STASH_TRACE"] != nil, e.type != .leftMouseDown {
                let line = "\(e.type == .keyDown ? "keyDown" : "flagsChanged") chars=\(e.charactersIgnoringModifiers ?? "-") flags=0x\(String(e.modifierFlags.rawValue, radix: 16))\n"
                if let h = FileHandle(forWritingAtPath: "/private/tmp/stash-actions.log") { h.seekToEndOfFile(); h.write(Data(line.utf8)); try? h.close() }
            }
            #endif
            MainActor.assumeIsolated {
                guard let self else { return }
                self.cheatTask?.cancel()
                if e.type == .flagsChanged, e.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command {
                    self.cheatTask = Task { [weak self] in
                        try? await Task.sleep(for: .seconds(1))
                        if !Task.isCancelled { self?.cheatSheetVisible = true }
                    }
                } else {
                    self.cheatSheetVisible = false
                }
            }
            return e
        }
    }

    // MARK: Preview / focus

    func openPreview(_ id: String) { previewID = id }
    func closePreview() { previewID = nil; focusGridTick += 1 }
    func closePanel() { panel = nil; focusGridTick += 1 }
    func focusGridTick_bump() { focusGridTick += 1 }

    func stepPreview(_ delta: Int) {
        guard let id = previewID, let i = items.firstIndex(where: { $0.id == id }) else { return }
        let n = i + delta
        if items.indices.contains(n) { previewID = items[n].id; selection = [items[n].id] }
    }

    func originalURL(for s: ItemSummary) -> URL? {
        guard let layout else { return nil }
        return layout.itemDir(s.id).appendingPathComponent(s.ext.map { "original.\($0)" } ?? "original")
    }
}
