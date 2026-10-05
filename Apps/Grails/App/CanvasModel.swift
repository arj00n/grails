import AppKit
import GrailsKit

extension AppModel {
    /// True for views that are a slice of the library rather than a place of their own: a search, active filters, Liked,
    /// Untagged, the Trash. They have no board; the canvas lays their items out as one temporary, read-only cluster,
    /// so nothing arranged or named there can leak into the real boards.
    var canvasIsDerived: Bool {
        if isSearching || filters.isActive || addedByFilter != nil { return true }
        switch source {
        case .liked, .untagged, .trash, .tag, .smart: return true
        case .all, .inbox, .collection: return false
        }
    }

    /// Which saved board the current view uses (nil for derived views).
    var canvasBoardKey: String? {
        if canvasIsDerived { return nil }
        switch source {
        case .all: return CanvasKey.library
        case .inbox: return CanvasKey.inbox
        case .collection(let id): return CanvasKey.collection(id)
        case .liked, .untagged, .trash, .tag, .smart: return nil
        }
    }

    /// Identifies what the canvas is showing, so it re-fits when the view changes. Derived views are never saved under it.
    var canvasViewKey: String? {
        if let key = canvasBoardKey { return key }
        if isSearching { return "derived:search" }
        switch source {
        case .liked: return "derived:liked"
        case .untagged: return "derived:untagged"
        case .trash: return "derived:trash"
        case .tag(let t): return "derived:tag:\(t)"
        case .smart(let id): return "derived:smart:\(id)"
        default: return "derived:filter"
        }
    }

    /// Makes sure the canvas has the right board loaded and every visible item belongs to a cluster.
    func syncCanvas() async {
        guard viewMode == .canvas else { return }
        guard let key = canvasBoardKey else {
            // A derived view (search, filters, Liked, Untagged, Trash) has no board: its items are one temporary, read-only cluster.
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

    /// Names are edited in place on the canvas header (or the grid's section title).
    func promptRenameCluster(_ id: String) { beginClusterRename?(id) }

    func renameCluster(_ id: String, to title: String) {
        // the grid's sections and the canvas share one list; prefer whichever is loaded for this view
        let base = sectionKey != nil && sectionKey == canvasBoardKey && !sectionClusters.isEmpty ? sectionClusters : canvasClusters
        var next = base
        let name = title.trimmingCharacters(in: .whitespaces)
        guard let i = next.firstIndex(where: { $0.id == id }), next[i].title != name else { return }
        next[i].title = name
        next[i].at = Date().timeIntervalSince1970
        commitClusters(next, label: "Rename Cluster")
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
