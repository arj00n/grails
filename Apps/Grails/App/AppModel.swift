import AppKit
import Observation
import GrailsKit
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

/// Tile size is continuous: pinch or ⌘-scroll scales it smoothly, then it settles so tiles fill each row.
enum Zoom {
    static let minWidth: CGFloat = 56
    static let maxWidth: CGFloat = 720
    static let defaultWidth: CGFloat = 190
    static func clamp(_ w: CGFloat) -> CGFloat { min(max(w, minWidth), maxWidth) }
}

enum ViewMode: String, CaseIterable, Identifiable {
    case grid, canvas
    var id: String { rawValue }
    var label: String { self == .grid ? "Grid" : "Canvas" }
    var symbol: String { self == .grid ? "square.grid.2x2" : "rectangle.on.rectangle.angled" }
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

struct CanvasRequest: Equatable {
    enum Kind: Equatable { case fit, fitSelection, zoom(CGFloat), reveal([String]), groupSelection, tidyClusters }
    let id = UUID()
    var kind: Kind
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
    var libraryName = "Grails"

    var source: Source = .all {
        didSet {
            guard oldValue != source else { return }
            if !restoringHistory { pushHistory(ViewSnapshot(source: oldValue, addedBy: addedByFilter)) }
            scrollResetTick += 1
            selection = []
            if !searchText.isEmpty { searchText = "" } else { reloadSoon() }
        }
    }
    private(set) var items: [ItemSummary] = []
    /// Views you came from, newest last, for Back.
    @ObservationIgnored var viewHistory: [ViewSnapshot] = []
    @ObservationIgnored var restoringHistory = false
    var canGoBack: Bool { !viewHistory.isEmpty }
    /// Bumped on every reload so the grid can skip O(n) diffing.
    private(set) var itemsVersion = 0
    var selection: Set<String> = []
    private(set) var collections: [GrailsCollection] = []
    private(set) var smartFolders: [SmartFolder] = []
    private(set) var tags: [(tag: String, count: Int)] = []
    /// Tags on the items in the current view, with how many of them have each: what the tab strip offers.
    private(set) var viewTags: [(tag: String, count: Int)] = []
    /// How many items that view has before the strip narrows it.
    private(set) var viewBaseCount = 0
    /// lowercased tag → "#RRGGBB"
    private(set) var tagColors: [String: String] = [:]
    private(set) var totalCount = 0

    var searchText = "" { didSet { if oldValue != searchText { scrollResetTick += 1; reloadSoon() } } }
    private(set) var recentSearches: [String] = UserDefaults.standard.stringArray(forKey: "recentSearches") ?? []
    var filters = ViewFilters() { didSet { if oldValue != filters { scrollResetTick += 1; reloadSoon() } } }
    /// Tags narrowing the current view (the tab strip): a view of "poster" inside the open collection, say.
    var stripTags: [String] = [] { didSet { if oldValue != stripTags { scrollResetTick += 1; reloadSoon() } } }
    /// Tags pinned to the strip, per library.
    var pinnedTags: [String] = []
    var sort: SortChoice = .newest { didSet { if oldValue != sort { scrollResetTick += 1; reloadSoon() } } }
    private var shuffleSeed: UInt64 = 1

    var showInfo = false
    /// One-shot commands for the canvas (fit, arrange, zoom); the canvas runs each request once.
    var canvasRequest: CanvasRequest?
    /// ⌘+ / ⌘− in the grid: one column fewer or more, animated.
    var gridZoomTick = 0
    @ObservationIgnored private var pendingColumnDelta = 0
    /// Total column steps requested since the last call (rapid presses arrive in one update).
    func takeColumnDelta() -> Int { defer { pendingColumnDelta = 0 }; return pendingColumnDelta }
    var previewID: String?
    /// The items the preview pages through (see PreviewSet): fixed when it opens.
    var previewSet: PreviewSet?
    var previewSetVersion = 0
    var workspaceMenuOpen = false
    var importPanelOpen = false
    /// A browser extension asking to be paired (answered with Allow).
    var pairRequest: PairingBroker.Request?
    var extensionPaired = UserDefaults.standard.bool(forKey: "extensionPaired")
    let importModel = ImportModel()
    @ObservationIgnored var hiddenPanels: (Bool, Bool)?
    /// Where an item's tile is on screen (window coordinates, jumping it into view if needed) and a way to hide it while its picture
    /// flies to or from the preview. Set by whichever of the grid and canvas is showing.
    @ObservationIgnored var tileGeometry: TileGeometry?
    var panel: Panel?
    var prompt: PromptRequest?
    var confirm: ConfirmRequest?
    var smartEditor: SmartEditorState?
    var toast: String?
    /// Grid asks for keyboard focus whenever this changes.
    private(set) var focusGridTick = 0
    var searchFocusTick = 0
    var errorMessage: String?
    var importProgress: (done: Int, total: Int)?
    var autoTagProgress: (done: Int, total: Int)?
    var focusSearchTick = 0
    /// Remembers a UI preference, except in dev and test runs (GRAILS_LIBRARY): those share this app's preferences with the
    /// installed copy, and a test that switches to the canvas must not leave the real app opening on the canvas.
    static func remember(_ value: Any, _ key: String) {
        guard ProcessInfo.processInfo.environment["GRAILS_LIBRARY"] == nil else { return }
        UserDefaults.standard.set(value, forKey: key)
    }
    var sidebarVisible: Bool = UserDefaults.standard.object(forKey: "sidebar.visible") == nil || UserDefaults.standard.bool(forKey: "sidebar.visible") {
        didSet { Self.remember(sidebarVisible, "sidebar.visible") }
    }
    /// A board import in progress: what it's doing, and how far (total 0 = still reading the board).
    var boardImport: (label: String, done: Int, total: Int)?
    @ObservationIgnored var boardImportTask: Task<Void, Never>?
    /// Tags auto-tagging has learned not to suggest in this library (too common to be useful).
    var autoTagSkipped: [String] = []
    @ObservationIgnored var autoTagTask: Task<Void, Never>?
    @ObservationIgnored var autoTagGeneration = 0
    @ObservationIgnored var autoTagSeenTotal = -1
    var renameProgress: (done: Int, total: Int)?

    private(set) var undoStack: [ChangeSet] = []
    private(set) var redoStack: [ChangeSet] = []
    var undoTitle: String? { undoStack.last.map { "Undo \($0.label)" } }
    var redoTitle: String? { redoStack.last.map { "Redo \($0.label)" } }

    /// Persisted tile width for the grid (the grid writes it back after a zoom gesture settles).
    var tileWidth: CGFloat { didSet { Self.remember(Double(tileWidth), "tileWidth") } }
    /// Grid tile shape: squares, or each image's own proportions.
    var layoutMode: GridLayoutMode { didSet { Self.remember(layoutMode.rawValue, "layoutMode") } }
    var viewMode: ViewMode { didSet { Self.remember(viewMode.rawValue, "viewMode"); if viewMode == .canvas { Task { await syncCanvas() } } } }

    private var reloadTask: Task<Void, Never>?
    /// Reloads can overlap (an undoable action's reload vs one triggered by typing in search); only the newest may apply.
    private var reloadGeneration = 0
    private var toastTask: Task<Void, Never>?
    // Canvas: free-form boards (see CanvasModel.swift)
    @ObservationIgnored var canvasClusters: [CanvasCluster] = []
    /// Set by the canvas: starts editing a cluster's name in place.
    @ObservationIgnored var beginClusterRename: ((String) -> Void)?
    /// The grid's titled sections (one per canvas cluster), or nil when the view shows a plain flat grid.
    var gridSections: [GridSection]?
    var sectionsVersion = 0
    @ObservationIgnored var sectionClusters: [CanvasCluster] = []
    @ObservationIgnored var sectionKey: String?
    /// Bumped when the grid-of-record for the canvas changes from outside the canvas (board loaded, undo, teammate, arrange).
    private(set) var canvasVersion = 0
    @ObservationIgnored var canvasLoadedKey: String?

    // Team: libraries, watching, who added what
    var needsLibrary = false
    /// First-run onboarding, while it is on screen.
    var onboarding: OnboardingModel?
    private(set) var workspaces: [Workspace] = Workspaces.load()
    /// The open library's own id (the same on every Mac), used in `grails://` links.
    private(set) var libraryID = ""
    private(set) var contributors: [(who: String, count: Int)] = []
    var addedByFilter: String? { didSet { if oldValue != addedByFilter { scrollResetTick += 1; reloadSoon() } } }
    /// Bumped when the visible set changes meaning (new view, filter, search) so the grid jumps to the top; plain data
    /// refreshes (a teammate's save arriving) keep the scroll position.
    private(set) var scrollResetTick = 0
    @ObservationIgnored var watcher: LibraryWatcher?
    @ObservationIgnored var pendingPaths = Set<String>()
    @ObservationIgnored var watchTask: Task<Void, Never>?
    @ObservationIgnored var rescanLoop: Task<Void, Never>?

    // Capture: paste, menu bar, browser extension
    @ObservationIgnored var captureService: LibraryCaptureService?
    @ObservationIgnored var apiServer: LocalAPIServer?
    @ObservationIgnored var menuBar: MenuBarController?
    /// GRAILS_API_TOKEN lets UI tests use a known token; otherwise the pairing token lives in the Keychain.
    @ObservationIgnored let tokens: TokenStorage = ProcessInfo.processInfo.environment["GRAILS_API_TOKEN"].map { InMemoryTokenStorage($0) as TokenStorage } ?? KeychainTokenStorage()
    var apiStatus = "Starting…"
    var apiPort: UInt16 = 0

    init() {
        let d = UserDefaults.standard
        // `double(forKey:)` also reads values passed as launch arguments, which arrive as strings.
        tileWidth = d.object(forKey: "tileWidth") == nil ? Zoom.defaultWidth : Zoom.clamp(CGFloat(d.double(forKey: "tileWidth")))
        viewMode = ViewMode(rawValue: d.string(forKey: "viewMode") ?? "") ?? .grid
        layoutMode = GridLayoutMode(rawValue: d.string(forKey: "layoutMode") ?? "") ?? .square
        showInfo = ProcessInfo.processInfo.environment["GRAILS_SHOW_INFO"] != nil   // dev/UI tests
        importModel.app = self
    }

    // MARK: Library lifecycle

    /// Opens the library named by GRAILS_LIBRARY (tests), the last used one, or creates the default.
    func openInitialLibrary() async {
        let env = ProcessInfo.processInfo.environment
        if let dir = env["GRAILS_ONBOARDING_DEMO"] { await startOnboardingDemo(dir); return }
        let url: URL
        if let p = env["GRAILS_LIBRARY"] {
            url = URL(fileURLWithPath: p)
        } else if let saved = UserDefaults.standard.string(forKey: "libraryPath"), FileManager.default.fileExists(atPath: saved) {
            url = URL(fileURLWithPath: saved)
        } else {
            // First run (or the last library's folder is gone, e.g. a drive that isn't mounted): never create anything
            // silently; let the person choose between the team's shared library and a new one.
            needsLibrary = true
            onboarding = OnboardingModel(app: self)
            await startCapture()
            return
        }
        // Dev/UI tests: GRAILS_SEED=<n> fills a library that doesn't exist yet with n synthetic items.
        if let seed = env["GRAILS_SEED"].flatMap(Int.init), !FileManager.default.fileExists(atPath: url.appendingPathComponent("library.json").path) {
            // GRAILS_SEED_PLAIN=1: no collections and no liked items, for predictable UI tests
            let plain = env["GRAILS_SEED_PLAIN"] != nil
            let people = env["GRAILS_SEED_PEOPLE"].map { $0.split(separator: ",").map(String.init) } ?? ["fixture"]
            _ = try? FixtureLibrary.generate(at: url, count: seed, collections: plain ? 0 : 20, likedOneIn: plain ? 0 : 10, contributors: people)
        }
        await openOrCreate(at: url, remember: env["GRAILS_LIBRARY"] == nil)
        // quit halfway through first-run import: pick up where it was
        let saved = OnboardingState.load()
        if env["GRAILS_LIBRARY"] == nil, !saved.done, saved.step == .importing || saved.step == .arriving, store != nil {
            let o = OnboardingModel(app: self, resuming: true)
            if saved.step == .arriving, !importModel.isRunning { o.finish() } else { onboarding = o }
        }
    }

    static var defaultLibraryURL: URL {
        FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask)[0].appendingPathComponent("Grails Library.grails")
    }

    var userHandle: String { UserDefaults.standard.string(forKey: "userHandle") ?? GrailsPaths.defaultUserHandle }

    func openOrCreate(at url: URL, remember: Bool = true) async {
        do {
            let index = ProcessInfo.processInfo.environment["GRAILS_INDEX_PATH"].map { try? LibraryIndex(path: URL(fileURLWithPath: $0)) } ?? nil
            let store: LibraryStore
            if FileManager.default.fileExists(atPath: url.appendingPathComponent("library.json").path) {
                store = try await LibraryStore.open(at: url, index: index, userHandle: userHandle, rescan: false)
            } else {
                store = try LibraryStore.create(at: url, name: url.deletingPathExtension().lastPathComponent, index: index, userHandle: userHandle)
            }
            cancelAutoTag()
            autoTagSeenTotal = -1
            self.store = store
            needsLibrary = false
            layout = store.layout
            libraryName = await store.manifest.name
            if remember { UserDefaults.standard.set(url.path, forKey: "libraryPath") }
            libraryID = await store.manifest.id
            pinnedTags = UserDefaults.standard.stringArray(forKey: "pinnedTags.\(libraryID)") ?? []
            stripTags = []
            if remember { workspaces = Workspaces.remember(id: libraryID, path: url.path, name: libraryName) }
            addedByFilter = nil
            startWatching()
            selection = []
            undoStack = []
            redoStack = []
            await reload()
            kickAutoTag()
            resumeInterruptedImport()
            Self.logLaunchTime()
            await startCapture()
            if let delay = ProcessInfo.processInfo.environment["GRAILS_SIMULATE_REMOTE"].flatMap(Double.init), let layout {
                // Dev/UI tests: write an item straight into the folder, like another Mac's sync client would.
                Task {
                    try? await Task.sleep(for: .seconds(delay))
                    try? FixtureLibrary.writeRemoteItem(into: layout, name: "Remote item", addedBy: "ben")
                }
            }
            if let dir = ProcessInfo.processInfo.environment["GRAILS_IMPORT_DEMO"] { importModel.opensFirstCollection = true; importModel.runDemo(into: dir) }
            if ProcessInfo.processInfo.environment["GRAILS_PREVIEW_DEMO"] != nil, let first = items.first { openPreview(first.id) }
            if ProcessInfo.processInfo.environment["GRAILS_AUTOLIKE"] != nil, let first = items.first {
                toggleLike(ids: [first.id])
            }
            // Dev/UI tests: GRAILS_PANEL=note|tags|move|commandK opens that panel right away (with the first item selected).
            if let name = ProcessInfo.processInfo.environment["GRAILS_PANEL"] {
                if let first = items.first { selection = [first.id] }
                panel = ["note": .note, "tags": .tags, "move": .move, "commandK": .commandK][name]
            }
            if let text = ProcessInfo.processInfo.environment["GRAILS_AUTONOTE"], let first = items.first {
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
    /// Dev: GRAILS_LAUNCH_LOG=1 prints process-start → first populated grid, in ms.
    private static func logLaunchTime() {
        guard !logged, ProcessInfo.processInfo.environment["GRAILS_LAUNCH_LOG"] != nil else { return }
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
        q.extraTags = stripTags
        q.addedBy = addedByFilter
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
            // the strip's tags come from the view without the strip's own narrowing, so its tabs stay put while you switch between them
            var baseIDs = Set(result.map(\.id))
            if !stripTags.isEmpty {
                var base = q
                base.extraTags = []
                baseIDs = Set(try await store.index.query(base).map(\.id))
            }
            let inView = try await store.index.tagCounts(among: baseIDs)
            let baseCount = baseIDs.count
            let colors = await store.tagMetadata().compactMapValues(\.color)
            let total = try await store.index.count(ItemQuery())
            let people = try await store.index.addedByCounts()
            guard !Task.isCancelled, generation == reloadGeneration else { return }
            if sort == .random { result = Self.shuffled(result, seed: shuffleSeed) }
            smartFolders = smart
            collections = colls
            items = result
            itemsVersion += 1
            selection.formIntersection(Set(result.map(\.id)))
            tags = tagList
            viewTags = inView.map { (tag: $0.tag, count: $0.count) }
            viewBaseCount = baseCount
            tagColors = colors
            totalCount = total
            if autoTagSeenTotal >= 0, total > autoTagSeenTotal { kickAutoTag() }
            contributors = people.map { (who: $0.who, count: $0.count) }
            if viewMode == .canvas { await syncCanvas() }
            await refreshSections()
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
        if let who = addedByFilter, source == .all { return "Added by \(who)" }
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
    func bumpCanvasVersion() { canvasVersion += 1 }
    var selectedSummaries: [ItemSummary] { items.filter { selection.contains($0.id) } }

    func rememberSearch() {
        let t = searchText.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return }
        recentSearches = ([t] + recentSearches.filter { $0.caseInsensitiveCompare(t) != .orderedSame }).prefix(3).map { $0 }
        UserDefaults.standard.set(recentSearches, forKey: "recentSearches")
    }

    // MARK: Undoable operations

    /// Runs `body` while the store notes the state it overwrites; returns the result and the undo change set.
    func recorded<T>(_ label: String, in store: LibraryStore, _ body: () async throws -> T) async throws -> (T, ChangeSet) {
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

    /// Records an undoable action's change set (used by files that extend AppModel).
    func pushUndo(_ cs: ChangeSet) {
        guard !cs.isEmpty else { return }
        undoStack.append(cs)
        if undoStack.count > 100 { undoStack.removeFirst() }
        redoStack = []
    }

    func undo() async {
        guard let store, let cs = undoStack.popLast() else { return }
        do {
            let inverse = try await store.apply(cs)
            redoStack.append(inverse)
            await reload()
            if viewMode == .canvas { await loadBoard() }
            await refreshSections(forceRead: true)
            showToast(cs.label.isEmpty ? "Undone" : "Undid \(cs.label.lowercased())")
        } catch { errorMessage = "Undo failed: \(error.localizedDescription)" }
    }

    func redo() async {
        guard let store, let cs = redoStack.popLast() else { return }
        do {
            let inverse = try await store.apply(cs)
            undoStack.append(inverse)
            await reload()
            if viewMode == .canvas { await loadBoard() }
            await refreshSections(forceRead: true)
            showToast("Redid \(cs.label.lowercased())")
        } catch { errorMessage = "Redo failed: \(error.localizedDescription)" }
    }

    func showToast(_ text: String, seconds: Double = 2.2) {
        toast = text
        toastTask?.cancel()
        toastTask = Task {
            try? await Task.sleep(for: .seconds(seconds))
            if !Task.isCancelled { toast = nil }
        }
    }

    // MARK: Import

    /// Imports files or folders. `recordUndo: false` is for callers that already wrap the work in their own recording.
    func importFiles(_ urls: [URL], collectionId: String? = nil, tag: String? = nil, recordUndo: Bool = true) async {
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

        func addAll() async {
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

        do {
            if recordUndo {
                let (_, undo) = try await recorded("Add \(files.count) \(files.count == 1 ? "Item" : "Items")", in: store) { await addAll() }
                if !undo.isEmpty { undoStack.append(undo); redoStack = [] }
            } else {
                await addAll()
            }
        } catch { errorMessage = "Import failed: \(error.localizedDescription)" }
        importProgress = nil
        if recordUndo { await reload() }
        kickAutoTag()
    }

    // MARK: Actions (menu items, grid shortcuts, ⌘K)

    func run(_ action: ShortcutAction) {
        #if DEBUG
        if ProcessInfo.processInfo.environment["GRAILS_TRACE"] != nil {
            let line = "\(Date()) run(\(action.rawValue)) panel=\(String(describing: panel)) event=\(String(describing: NSApp.currentEvent))\n"
            if let h = FileHandle(forWritingAtPath: "/private/tmp/grails-actions.log") { h.seekToEndOfFile(); h.write(Data(line.utf8)); try? h.close() }
            else { try? line.write(toFile: "/private/tmp/grails-actions.log", atomically: true, encoding: .utf8) }
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
        case .zoomIn: zoom(by: 1.25)
        case .zoomOut: zoom(by: 1 / 1.25)
        case .newCollection: promptNewCollection(kind: "collection", parent: nil)
        case .newSmartFolder: smartEditor = SmartEditorState()
        }
    }

    /// ⌘+ / ⌘−: the grid animates to the new size; the canvas zooms about its centre.
    func zoom(by factor: CGFloat) {
        if viewMode == .canvas { canvasRequest = CanvasRequest(kind: .zoom(factor)) }
        else { pendingColumnDelta += factor > 1 ? -1 : 1; gridZoomTick += 1 }   // bigger tiles = fewer columns
    }

    func toggleLike(ids: [String]) {
        guard !ids.isEmpty else { return }
        let all = ids.allSatisfy { summary($0)?.liked == true }
        let like = !all
        Task {
            guard await perform(like ? "Like" : "Unlike", { try await $0.setLiked(like, ids: ids) }) != nil else { return }
            let word = like ? "Liked" : "Unliked"
            showToast(ids.count == 1 ? word : "\(word) \(ids.count) items")
        }
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
            message: "Copies stay in the library's .trash folder for 30 days.",
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

    func promptRenameCollection(_ c: GrailsCollection) {
        prompt = PromptRequest(title: "Rename", placeholder: "Name", initial: c.name, confirmTitle: "Rename") { [weak self] name in
            guard let self, !name.isEmpty, name != c.name else { return }
            Task { await self.perform("Rename Collection") { try await $0.renameCollection(id: c.id, to: name) } }
        }
    }

    func confirmDeleteCollection(_ c: GrailsCollection) {
        confirm = ConfirmRequest(
            title: "Delete “\(c.name)”?",
            message: "The items stay in your library.",
            confirmTitle: "Delete"
        ) { [weak self] in
            guard let self else { return }
            Task {
                await self.perform("Delete Collection") { try await $0.deleteCollection(id: c.id) }
                if self.source == .collection(c.id) { self.source = .all }
            }
        }
    }

    func duplicateCollection(_ c: GrailsCollection) {
        Task { await perform("Duplicate Collection") { try await $0.duplicateCollection(id: c.id).id } }
    }

    func archiveCollection(_ c: GrailsCollection, _ archived: Bool) {
        Task {
            await perform(archived ? "Archive Collection" : "Unarchive Collection") { try await $0.archiveCollection(id: c.id, archived) }
            if archived, source == .collection(c.id) { source = .all }
        }
    }

    func setCoverFromSelection(_ c: GrailsCollection) {
        guard let id = selection.first else { showToast("Select an item first"); return }
        Task { await perform("Set Cover") { try await $0.setCover(itemId: id, for: c.id) } }
    }

    func moveCollection(_ id: String, intoFolder folder: String) {
        Task { await perform("Move Collection") { try await $0.moveCollection(id: id, toParent: folder) } }
    }

    func moveCollection(_ id: String, after target: GrailsCollection) {
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
        prompt = PromptRequest(title: "Rename Tag", placeholder: "Tag", initial: tag, confirmTitle: "Rename") { [weak self] name in
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

    /// Folds tags that mean the same ("poster", "posters"; "minimal", "minimalist") into the most used one.
    func mergeSimilarTags() {
        Task {
            guard let merged = await perform("Merge Similar Tags", { try await $0.mergeSimilarTags() }) else { return }
            if case .tag(let current) = source, let m = merged.first(where: { $0.from.lowercased() == current.lowercased() }) { source = .tag(m.into) }
            showToast(merged.isEmpty ? "No similar tags" : "Merged \(merged.count) similar tag\(merged.count == 1 ? "" : "s")")
        }
    }

    func confirmDeleteTag(_ tag: String) {
        confirm = ConfirmRequest(title: "Delete tag “\(tag)”?", message: "It will be removed from every item.", confirmTitle: "Delete Tag") { [weak self] in
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

    // MARK: Preview / focus

    func closePanel() { panel = nil; focusGridTick += 1 }
    func focusGridTick_bump() { focusGridTick += 1 }

    func originalURL(for s: ItemSummary) -> URL? {
        guard let layout else { return nil }
        return layout.itemDir(s.id).appendingPathComponent(s.ext.map { "original.\($0)" } ?? "original")
    }
}

extension AppModel {
    func removeWorkspace(_ w: Workspace) { workspaces = Workspaces.remove(id: w.id) }
    func setWorkspaceColor(_ hex: String?, for w: Workspace) { workspaces = Workspaces.setColor(hex, id: w.id) }
}
