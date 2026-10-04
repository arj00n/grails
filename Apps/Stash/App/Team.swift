import AppKit
import StashKit

struct RecentLibrary: Codable, Hashable, Identifiable {
    var path: String
    var name: String
    var id: String { path }

    static func load() -> [RecentLibrary] {
        guard let data = UserDefaults.standard.data(forKey: "recentLibraries") else { return [] }
        return ((try? JSONDecoder().decode([RecentLibrary].self, from: data)) ?? []).filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    static func remember(path: String, name: String) {
        var list = load().filter { $0.path != path }
        list.insert(RecentLibrary(path: path, name: name), at: 0)
        if let data = try? JSONEncoder().encode(Array(list.prefix(6))) { UserDefaults.standard.set(data, forKey: "recentLibraries") }
    }
}

extension AppModel {
    // MARK: Switching libraries

    /// Opens an existing library, or (for the default location only) creates one. Anything else that isn't a library is refused.
    func openLibrary(at url: URL) {
        let isLibrary = FileManager.default.fileExists(atPath: url.appendingPathComponent("library.json").path)
        guard isLibrary || url == AppModel.defaultLibraryURL else {
            errorMessage = "“\(url.lastPathComponent)” isn't a Stash library. Choose a folder ending in .stash."
            return
        }
        Task { await openOrCreate(at: url) }
    }

    // MARK: Watching a shared folder

    /// Watches the library folder (FSEvents) and also rescans every minute: sync clients like Google Drive deliver
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
        rescanLoop = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
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
        if let r, r.added + r.updated + r.removed + r.conflictsMerged > 0 {
            await reload()
            if announce { showToast("Library refreshed") }
        } else if announce {
            showToast("Library is up to date")
        }
    }

    // MARK: Moving collections between libraries

    func transferCollection(_ c: StashCollection, to destination: URL, move: Bool) {
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

    func confirmMoveCollection(_ c: StashCollection, to library: RecentLibrary) {
        confirm = ConfirmRequest(
            title: "Move “\(c.name)” to \(library.name)?",
            message: "The collection and its items go to \(library.name). Items that were only in this collection are moved to this library's Trash.",
            confirmTitle: "Move", destructive: false
        ) { [weak self] in self?.transferCollection(c, to: URL(fileURLWithPath: library.path), move: true) }
    }

    func chooseLibrary(then action: @escaping (URL) -> Void) {
        let p = NSOpenPanel()
        p.canChooseDirectories = true
        p.canChooseFiles = false
        p.message = "Choose a Stash library (a folder ending in .stash)"
        if p.runModal() == .OK, let url = p.url { action(url) }
    }

    // MARK: Initials for the "added by" badge

    static func initials(_ handle: String) -> String {
        let parts = handle.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
        if parts.count >= 2 { return String(parts[0].prefix(1) + parts[1].prefix(1)).uppercased() }
        return String(handle.prefix(2)).uppercased()
    }
}
