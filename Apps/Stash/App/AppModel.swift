import AppKit
import Observation
import StashKit

enum Source: Hashable {
    case inbox, all, liked, untagged, trash
    case collection(String)
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

@MainActor @Observable
final class AppModel {
    var store: LibraryStore?
    var layout: LibraryLayout?
    var libraryName = "Stash"

    var source: Source = .all { didSet { if oldValue != source { selection = []; reloadSoon() } } }
    private(set) var items: [ItemSummary] = []
    /// Bumped on every reload so the grid can skip O(n) diffing.
    private(set) var itemsVersion = 0
    var selection: Set<String> = []
    private(set) var collections: [StashCollection] = []
    private(set) var tags: [(tag: String, count: Int)] = []
    private(set) var totalCount = 0

    var showInfo = false
    var previewID: String?
    /// Grid asks for keyboard focus whenever this changes.
    private(set) var focusGridTick = 0
    var errorMessage: String?
    var importProgress: (done: Int, total: Int)?

    var zoomStep: Int { didSet { UserDefaults.standard.set(zoomStep, forKey: "zoomStep") } }
    var layoutMode: GridLayoutMode { didSet { UserDefaults.standard.set(layoutMode.rawValue, forKey: "layoutMode") } }

    private var reloadTask: Task<Void, Never>?

    init() {
        let d = UserDefaults.standard
        // `integer(forKey:)` also reads values passed as launch arguments, which arrive as strings.
        zoomStep = min(max(d.object(forKey: "zoomStep") == nil ? 2 : d.integer(forKey: "zoomStep"), 0), Zoom.maxStep)
        layoutMode = GridLayoutMode(rawValue: d.string(forKey: "layoutMode") ?? "") ?? .square
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
        await openOrCreate(at: url, remember: env["STASH_LIBRARY"] == nil)
    }

    static var defaultLibraryURL: URL {
        FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask)[0].appendingPathComponent("Stash Library.stash")
    }

    func openOrCreate(at url: URL, remember: Bool = true) async {
        do {
            let handle = UserDefaults.standard.string(forKey: "userHandle") ?? StashPaths.defaultUserHandle
            let index = ProcessInfo.processInfo.environment["STASH_INDEX_PATH"].map { try? LibraryIndex(path: URL(fileURLWithPath: $0)) } ?? nil
            let store: LibraryStore
            if FileManager.default.fileExists(atPath: url.appendingPathComponent("library.json").path) {
                store = try await LibraryStore.open(at: url, index: index, userHandle: handle, rescan: false)
            } else {
                store = try LibraryStore.create(at: url, name: url.deletingPathExtension().lastPathComponent, index: index, userHandle: handle)
            }
            self.store = store
            layout = store.layout
            libraryName = await store.manifest.name
            if remember { UserDefaults.standard.set(url.path, forKey: "libraryPath") }
            selection = []
            await reload()
            Self.logLaunchTime()
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

    func reload() async {
        guard let store else { return }
        do {
            var q = ItemQuery()
            q.limit = Int.max
            switch source {
            case .inbox: q.unfiled = true
            case .all: break
            case .liked: q.likedOnly = true
            case .untagged: q.untagged = true
            case .trash: q.deleted = true
            case .collection(let id): q.collectionId = id
            case .tag(let t): q.tag = t
            }
            let result = try await store.index.query(q)
            guard !Task.isCancelled else { return }
            items = result
            itemsVersion += 1
            selection.formIntersection(Set(result.map(\.id)))
            collections = try await store.index.collections()
            tags = try await store.index.tagCounts().map { (tag: $0.tag, count: $0.count) }
            totalCount = try await store.index.count(ItemQuery())
        } catch {
            errorMessage = "Couldn't load items: \(error.localizedDescription)"
        }
    }

    var title: String {
        switch source {
        case .inbox: "Inbox"
        case .all: "All"
        case .liked: "Liked"
        case .untagged: "Untagged"
        case .trash: "Trash"
        case .collection(let id): collections.first { $0.id == id }?.name ?? "Collection"
        case .tag(let t): "#\(t)"
        }
    }

    // MARK: Import

    func importFiles(_ urls: [URL]) async {
        guard let store else { return }
        let files = FolderScanner.expandFiles(urls)
        guard !files.isEmpty else { return }
        var collectionIds: [String] = []
        if case .collection(let id) = source { collectionIds = [id] }
        var tagList: [String] = []
        if case .tag(let t) = source { tagList = [t] }
        let finalCollections = collectionIds, finalTags = tagList
        importProgress = (0, files.count)
        var done = 0
        for chunk in stride(from: 0, to: files.count, by: 4).map({ Array(files[$0..<min($0 + 4, files.count)]) }) {
            await withTaskGroup(of: Void.self) { group in
                for file in chunk {
                    group.addTask { _ = try? await store.addItem(fileAt: file, tags: finalTags, collectionIds: finalCollections) }
                }
            }
            done += chunk.count
            importProgress = (done, files.count)
        }
        importProgress = nil
        await reload()
    }

    // MARK: Preview / focus

    func openPreview(_ id: String) { previewID = id }
    func closePreview() { previewID = nil; focusGridTick += 1 }

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
