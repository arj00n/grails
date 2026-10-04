import AppKit
import StashKit

extension AppModel {
    /// Which board the current view uses. Liked / Untagged / search show subsets of the library, so they share its board.
    var canvasBoardKey: String? {
        if isSearching { return CanvasKey.library }
        switch source {
        case .all, .liked, .untagged: return CanvasKey.library
        case .inbox: return CanvasKey.inbox
        case .collection(let id): return CanvasKey.collection(id)
        case .smart(let id): return CanvasKey.smart(id)
        case .tag(let t): return CanvasKey.tag(t)
        case .trash: return nil
        }
    }

    /// Makes sure the canvas has the right board loaded and every visible item belongs to a cluster.
    func syncCanvas() async {
        guard viewMode == .canvas else { return }
        guard let key = canvasBoardKey else {
            // The Trash has no board of its own: what is in it is laid out as one temporary, read-only cluster (nothing is saved).
            canvasClusters = ClusterOps.adopt(items.map(\.id), into: [])
            canvasLoadedKey = nil
            bumpCanvasVersion()
            return
        }
        if canvasLoadedKey != key { await loadBoard() } else { await adoptNewItems(announce: true) }
    }

    func loadBoard() async {
        guard let store, let key = canvasBoardKey else { return }
        let board = await store.canvasBoard(key: key)
        var clusters = board?.clusters ?? []
        // a board from before clusters: its items become one cluster, in the order they were laid out
        if clusters.isEmpty, let placements = board?.placements, !placements.isEmpty { clusters = ClusterOps.migrate(placements) }
        canvasClusters = clusters
        canvasLoadedKey = key
        await adoptNewItems(announce: false)
        bumpCanvasVersion()
    }

    /// New items (a paste, a teammate's save, an import) join the first cluster; a board with none gets one.
    private func adoptNewItems(announce: Bool) async {
        guard let store, let key = canvasBoardKey else { return }
        let ids = items.map(\.id)
        let adopted = ClusterOps.adopt(ids, into: canvasClusters)
        guard adopted != canvasClusters else { return }
        let known = Set(canvasClusters.flatMap(\.items))
        let fresh = ids.filter { !known.contains($0) }
        canvasClusters = adopted
        _ = try? await store.setClusters(boardKey: key, adopted)       // housekeeping: not an undo step
        if announce {
            bumpCanvasVersion()
            if !known.isEmpty, !fresh.isEmpty { canvasRequest = CanvasRequest(kind: .reveal(fresh)) }
        }
    }

    static func aspect(of s: ItemSummary) -> Double { CanvasNSView.aspect(of: s) }

    /// An edit finished on the canvas: remember it locally and save it (undoable).
    func commitClusters(_ new: [CanvasCluster], label: String) {
        guard let store, let key = canvasBoardKey else { return }
        canvasClusters = new
        sectionClusters = new; sectionKey = key; rebuildSections()
        bumpCanvasVersion()
        Task {
            do {
                let (_, undo) = try await recorded(label, in: store) { _ = try await store.setClusters(boardKey: key, new) }
                pushUndo(undo)
            } catch { errorMessage = "Couldn't save the canvas: \(error.localizedDescription)" }
        }
    }

    // MARK: Cluster commands

    func promptRenameCluster(_ id: String) {
        guard let c = canvasClusters.first(where: { $0.id == id }) else { return }
        prompt = PromptRequest(title: "Cluster name", message: "Shown as the section title in the grid, too.", placeholder: "Name", initial: c.title, confirmTitle: "Rename") { [weak self] name in
            guard let self else { return }
            var next = self.canvasClusters
            guard let i = next.firstIndex(where: { $0.id == id }) else { return }
            next[i].title = name.trimmingCharacters(in: .whitespaces)
            next[i].at = Date().timeIntervalSince1970
            self.commitClusters(next, label: "Rename Cluster")
        }
    }

    func setClusterTile(_ id: String, tile: Double) {
        var next = canvasClusters
        guard let i = next.firstIndex(where: { $0.id == id }) else { return }
        next[i].tile = min(max(tile, ClusterLayout.minTile), ClusterLayout.maxTile)
        next[i].at = Date().timeIntervalSince1970
        commitClusters(next, label: "Change Tile Size")
    }

    /// Breaks a cluster up: its items go to the first other cluster (or stay, if it is the only one).
    func dissolveCluster(_ id: String) {
        guard canvasClusters.count > 1, let c = canvasClusters.first(where: { $0.id == id }), let into = canvasClusters.first(where: { $0.id != id }) else {
            showToast("This is the only cluster")
            return
        }
        let next = ClusterOps.move(c.items, to: .cluster(into.id, index: into.items.count), in: canvasClusters)
        commitClusters(next, label: "Dissolve Cluster")
    }

    func clusterMenu(_ id: String) -> NSMenu {
        let menu = NSMenu()
        func add(_ title: String, _ symbol: String? = nil, _ action: @escaping @MainActor () -> Void) {
            let item = ClosureMenuItem(title: title, handler: action)
            if let symbol { item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) }
            menu.addItem(item)
        }
        add("Rename…", "pencil") { [self] in promptRenameCluster(id) }
        let sizes = NSMenu()
        for (name, tile) in [("Small", 160.0), ("Medium", 260.0), ("Large", 400.0), ("Extra Large", 600.0)] {
            let item = ClosureMenuItem(title: name) { [self] in setClusterTile(id, tile: tile) }
            if let c = canvasClusters.first(where: { $0.id == id }), abs(c.tile - tile) < 1 { item.state = .on }
            sizes.addItem(item)
        }
        let parent = NSMenuItem(title: "Tile Size", action: nil, keyEquivalent: "")
        parent.image = NSImage(systemSymbolName: "square.grid.3x3", accessibilityDescription: nil)
        parent.submenu = sizes
        menu.addItem(parent)
        menu.addItem(.separator())
        add("Dissolve Cluster", "rectangle.badge.minus") { [self] in dissolveCluster(id) }
        return menu
    }
}
