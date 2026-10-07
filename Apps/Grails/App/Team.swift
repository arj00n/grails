import AppKit
import GrailsKit

/// A library this Mac knows about (a team's shared folder, a personal one). Order is the person's own, so ⌃1…⌃9 stay put.
struct Workspace: Codable, Hashable, Identifiable {
    /// The library's own id (same on every Mac); entries remembered before ids were recorded use their path until reopened.
    var id: String
    var path: String
    var name: String
    var color: String?

    init(id: String? = nil, path: String, name: String, color: String? = nil) {
        self.id = id ?? path; self.path = path; self.name = name; self.color = color
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        path = try c.decode(String.self, forKey: .path)
        name = try c.decode(String.self, forKey: .name)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? path
        color = try c.decodeIfPresent(String.self, forKey: .color)
    }

    var exists: Bool { FileManager.default.fileExists(atPath: path + "/library.json") }
    var url: URL { URL(fileURLWithPath: path) }
}

enum Workspaces {
    private static let key = "workspaces"
    private static let legacyKey = "recentLibraries"

    static func load() -> [Workspace] {
        let d = UserDefaults.standard
        if let data = d.data(forKey: key), let list = try? JSONDecoder().decode([Workspace].self, from: data) { return list }
        // first launch of this version: carry the recent libraries over
        if let data = d.data(forKey: legacyKey), let list = try? JSONDecoder().decode([Workspace].self, from: data) {
            let kept = list.filter(\.exists)
            save(kept)
            return kept
        }
        return []
    }

    static func save(_ list: [Workspace]) {
        if let data = try? JSONEncoder().encode(list) { UserDefaults.standard.set(data, forKey: key) }
    }

    /// Adds a library, or refreshes its name and folder; an existing entry keeps its place and colour.
    static func remember(id: String, path: String, name: String) -> [Workspace] {
        var list = load()
        if let i = list.firstIndex(where: { $0.id == id || $0.path == path }) {
            list[i].id = id; list[i].path = path; list[i].name = name
        } else {
            list.append(Workspace(id: id, path: path, name: name))
        }
        save(list)
        return list
    }

    static func remove(id: String) -> [Workspace] {
        let list = load().filter { $0.id != id }
        save(list)
        return list
    }

    static func setColor(_ hex: String?, id: String) -> [Workspace] {
        var list = load()
        if let i = list.firstIndex(where: { $0.id == id }) { list[i].color = hex }
        save(list)
        return list
    }
}

extension AppModel {
    // MARK: Switching libraries

    /// Opens an existing library, or (for the default location only) creates one. Anything else that isn't a library is refused.
    func openLibrary(at url: URL) {
        let target = LibraryFinder.picked(url) ?? url
        let isLibrary = FileManager.default.fileExists(atPath: target.appendingPathComponent("library.json").path)
        guard isLibrary || url == AppModel.defaultLibraryURL else {
            errorMessage = "“\(url.lastPathComponent)” isn't a Grails library."
            return
        }
        Task { await openOrCreate(at: isLibrary ? target : url) }
    }

    // MARK: Watching a shared folder

    /// Watches the library folder (FSEvents) and also rescans every 30 seconds: sync clients like Google Drive deliver
    /// events late or not at all, so the timer is the safety net.
    func startWatching() {
        watcher?.stop()
        rescanLoop?.cancel()
        guard let layout else { return }
        let w = LibraryWatcher(root: layout.root) { [weak self] paths in
            Task { @MainActor in self?.noteExternal(paths) }
        }
        w.start()
        watcher = w
        // coming back to the app is the moment people expect to see what changed meanwhile (a Finder trash, a teammate's upload)
        if let activationObserver { NotificationCenter.default.removeObserver(activationObserver) }
        activationObserver = NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self, Date().timeIntervalSince(self.lastActivationScan) > 3 else { return }
                self.lastActivationScan = Date()
                await self.refreshLibrary(announce: false)
            }
        }
        rescanLoop = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                if Task.isCancelled { break }
                await self?.refreshLibrary(announce: false)
            }
        }
    }

    func noteExternal(_ paths: [String]) {
        pendingPaths.formUnion(paths)
        watchTask?.cancel()
        watchTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))      // batch bursts of events
            guard !Task.isCancelled else { return }
            await self?.flushExternal()
        }
    }

    private func flushExternal() async {
        let paths = Array(pendingPaths)
        pendingPaths = []
        guard let store, let summary = try? await store.applyExternalChanges(paths: paths), !summary.isEmpty else { return }
        await reload()
        if let key = canvasBoardKey, summary.canvasBoards.contains(key) {
            if viewMode == .canvas { await loadBoard() }
            await refreshSections(forceRead: true)
        }
        if summary.added > 0 { showToast("\(summary.added) new \(summary.added == 1 ? "item" : "items") from your team") }
    }

    /// ⌘R and the minute timer: re-read anything that changed on disk.
    func refreshLibrary(announce: Bool = true) async {
        guard let store else { return }
        let r = try? await store.rescan()
        if let r, r.added + r.updated + r.removed + r.conflictsMerged + r.notesChanged > 0 {
            await reload()
            if announce { showToast("Library refreshed") }
        } else if announce {
            showToast("Library is up to date")
        }
    }

    // MARK: Moving collections between libraries

    func transferCollection(_ c: GrailsCollection, to destination: URL, move: Bool) {
        guard let source = store else { return }
        Task {
            do {
                let dst = try await LibraryStore.open(at: destination, userHandle: userHandle)
                let name = await dst.manifest.name
                let r = try await LibraryTransfer.transferCollection(id: c.id, from: source, to: dst, move: move)
                await reload()
                showToast("\(move ? "Moved" : "Copied") “\(c.name)” to \(name): \(r.copiedItems) new, \(r.reusedItems) already there")
            } catch {
                errorMessage = "Couldn't \(move ? "move" : "copy") the collection: \(error.localizedDescription)"
            }
        }
    }

    func confirmMoveCollection(_ c: GrailsCollection, to library: Workspace) {
        confirm = ConfirmRequest(
            title: "Move “\(c.name)” to \(library.name)?",
            message: "Items that were only in this collection move to this library's Trash.",
            confirmTitle: "Move", destructive: false
        ) { [weak self] in self?.transferCollection(c, to: URL(fileURLWithPath: library.path), move: true) }
    }

    func chooseLibrary(then action: @escaping (URL) -> Void) {
        let p = LibraryPicker.panel(message: "Choose a Grails library (a folder ending in .grails)")
        guard p.runModal() == .OK, let url = p.url else { return }
        guard let lib = LibraryFinder.picked(url) else {
            errorMessage = "“\(url.lastPathComponent)” isn't a Grails library."
            return
        }
        action(lib)
    }

    // MARK: Initials for the "added by" badge

    static func initials(_ handle: String) -> String {
        let parts = handle.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
        if parts.count >= 2 { return String(parts[0].prefix(1) + parts[1].prefix(1)).uppercased() }
        return String(handle.prefix(2)).uppercased()
    }
}
