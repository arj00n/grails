import AppKit
import GrailsKit
import GrailsSync

typealias Workspace = WorkspaceEntry

extension WorkspaceEntry {
    var exists: Bool {
        WorkspaceList.isAvailable(path: path, home: NSHomeDirectory(), resolve: Workspaces.resolve) {
            FileManager.default.fileExists(atPath: $0)
        }
    }

    var url: URL { URL(fileURLWithPath: (path as NSString).expandingTildeInPath) }
}

enum Workspaces {
    private static let key = "workspaces"
    private static let legacyKey = "recentLibraries"

    static func resolve(_ path: String) -> String {
        URL(fileURLWithPath: path).resolvingSymlinksInPath().standardizedFileURL.path
    }

    static func load() -> [Workspace] {
        let d = UserDefaults.standard
        let openPath = d.string(forKey: "libraryPath")
        if let data = d.data(forKey: key), let list = try? JSONDecoder().decode([Workspace].self, from: data) {
            let reconciled = WorkspaceList.reconcile(
                list, openPath: openPath, home: NSHomeDirectory(), resolve: resolve
            )
            if reconciled != list { save(reconciled) }
            return reconciled
        }
        if let data = d.data(forKey: legacyKey), let list = try? JSONDecoder().decode([Workspace].self, from: data) {
            let kept = WorkspaceList.reconcile(list, openPath: openPath, home: NSHomeDirectory(), resolve: resolve)
            save(kept)
            return kept
        }
        return []
    }

    static func save(_ list: [Workspace]) {
        if let data = try? JSONEncoder().encode(list) { UserDefaults.standard.set(data, forKey: key) }
    }

    static func remember(id: String, path: String, name: String) -> [Workspace] {
        let list = WorkspaceList.remember(load(), id: id, path: path, name: name, home: NSHomeDirectory(), resolve: resolve)
        save(list)
        return list
    }

    static func remove(id: String) -> [Workspace] {
        let list = WorkspaceList.remove(load(), id: id, home: NSHomeDirectory(), resolve: resolve)
        save(list)
        return list
    }

    static func setColor(_ hex: String?, id: String) -> [Workspace] {
        let list = WorkspaceList.setColor(load(), hex: hex, id: id)
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
                guard let self else { return }
                self.bucket.nudge()      // the background poll is slow; catch up on teammates' changes now
                guard Date().timeIntervalSince(self.lastActivationScan) > 3 else { return }
                self.lastActivationScan = Date()
                await self.refreshLibrary(announce: false)
            }
        }
        rescanLoop = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30), tolerance: .seconds(10))
                if Task.isCancelled { break }
                // a backstop for the watcher; in the background it waits for the scan coming back to the app runs anyway
                guard NSApp.isActive else { continue }
                await self?.refreshLibrary(announce: false)
            }
        }
    }

    func noteExternal(_ paths: [String]) {
        // A poll rewrites .grails-sync.json even when nothing moved. Nudging on that write cancels the 15s pause and the loop never goes idle.
        if SyncNudge.shouldNudge(paths: paths) { bucket.nudge() }
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
        guard let store else { return }
        if let layout, MemberDirectory.pathsTouchMembers(paths, root: layout.root) {
            refreshMemberDirectory()
        }
        guard let summary = try? await store.applyExternalChanges(paths: paths), !summary.isEmpty else { return }
        let bulk = syncProgress.map { SyncFeedback.showsProgress(total: $0.total) } ?? false
        guard SyncWatch.shouldReload(bulkSync: bulk) else { return }
        await reload()
        if let key = canvasBoardKey, summary.canvasBoards.contains(key) {
            if viewMode == .canvas { await loadBoard() }
            await refreshSections(forceRead: true)
        }
        if summary.added > 0, !bucket.syncing, syncProgress == nil, Date() >= bucket.muteArrivalUntil {
            showSyncFeedback(SyncFeedback.arrival(count: summary.added))
        }
        for line in personalNotices(summary) { showToast(line) }
    }

    func showSyncFeedback(_ feedback: SyncFeedback) {
        switch feedback {
        case .silent, .progress: break
        case .subtle(let text), .summary(let text): showToast(text)
        }
    }

    private func personalNotices(_ summary: ExternalChangeSummary) -> [String] {
        guard let layout else { return [] }
        var events: [ActivityEvent] = []
        for id in summary.addedIDs {
            guard let data = try? Data(contentsOf: layout.itemDir(id).appendingPathComponent("item.json")),
                  let item = try? GrailsJSON.decode(Item.self, from: data) else { continue }
            events.append(.itemAdded(by: item.addedBy))
            let viewer = Handle.normalize(userHandle)
            for tag in item.tags where !viewer.isEmpty && Handle.normalize(tag) == viewer {
                events.append(.tagged(by: item.addedBy, handle: viewer))
            }
            for mention in LibraryNotes.mentions(in: item.note, people: [userHandle]) {
                events.append(.mentioned(by: item.updatedBy.isEmpty ? item.addedBy : item.updatedBy, handle: mention))
            }
            for collectionID in item.collections.keys {
                let url = layout.collectionsDir.appendingPathComponent("\(collectionID).json")
                guard let data = try? Data(contentsOf: url),
                      let collection = try? GrailsJSON.decode(GrailsCollection.self, from: data) else { continue }
                let stake = CollectionStakeRead.stake(owner: collection.updatedBy, extras: collection.extras)
                events.append(.addedToCollection(by: item.addedBy, stake: stake))
            }
        }
        for id in summary.noteIDs {
            guard let note = LibraryNotes.read(id, in: layout) else { continue }
            for mention in note.mentions {
                events.append(.mentioned(by: note.author, handle: mention))
            }
        }
        return NotificationPolicy.lines(viewer: userHandle, events: events)
    }

    /// ⌘R and the minute timer: re-read anything that changed on disk.
    func refreshLibrary(announce: Bool = true) async {
        guard let store else { return }
        if let reloaded = try? await store.reloadManifest() {
            let live = await store.manifest.name
            let name = LibraryName.kept(current: libraryName, reloaded: reloaded, live: live, pending: pendingLibraryName)
            if name != libraryName {
                libraryName = name
                rememberWorkspaceName(name)
            }
            if let pending = pendingLibraryName, reloaded == pending, live == pending {
                pendingLibraryName = nil
            }
        }
        refreshMemberDirectory()
        let r = try? await store.rescan()
        if let r, r.added + r.updated + r.removed + r.conflictsMerged + r.notesChanged > 0 {
            await reload()
            if r.added + r.updated > 0 { kickVision() }
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
                showToast("\(move ? "Moved" : "Copied") “\(c.displayName)” to \(name): \(r.copiedItems) new, \(r.reusedItems) already there")
            } catch {
                errorMessage = "Couldn't \(move ? "move" : "copy") the collection: \(error.localizedDescription)"
            }
        }
    }

    func confirmMoveCollection(_ c: GrailsCollection, to library: Workspace) {
        confirm = ConfirmRequest(
            title: "Move “\(c.displayName)” to \(library.name)?",
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
}
