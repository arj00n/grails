import AppKit
import GrailsKit

extension AppModel {
    /// True for views that are a slice of the library rather than a place of their own: a search, active filters, Liked,
    /// Untagged, the Trash. They have no board; the canvas lays their items out as one temporary, read-only cluster,
    /// so nothing arranged or named there can leak into the real boards.
    var canvasIsDerived: Bool {
        if isSearching || filters.isActive || addedByFilter != nil { return true }
        switch source {
        case .liked, .untagged, .trash, .tag, .smart, .mentions: return true
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
        case .liked, .untagged, .trash, .tag, .smart, .mentions: return nil
        }
    }

    /// Identifies what the canvas is showing, so it re-fits when the view changes. Derived views are never saved under it.
    var canvasViewKey: String? {
        if let key = canvasBoardKey { return key }
        if isSearching { return "derived:search" }
        switch source {
        case .mentions: return "derived:mentions"
        case .liked: return "derived:liked"
        case .untagged: return "derived:untagged"
        case .trash: return "derived:trash"
        case .tag(let t): return "derived:tag:\(t)"
        case .smart(let id): return "derived:smart:\(id)"
        default: return "derived:filter"
        }
    }

    /// Boards whose clusters are folders: the whole library (its top-level collections) and a collection (the folders in it).
    /// The Inbox keeps clusters of its own, since nothing in it is in a folder yet.
    var folderBoard: FolderBoard? {
        if canvasIsDerived { return nil }
        switch source {
        case .all: return .library
        case .collection(let id): return .collection(id)
        default: return nil
        }
    }

    /// This board's clusters, read from its folders, with the layout saved on the board. Named clusters from before folders
    /// become folders first (with the cluster's id, so two Macs doing it make one folder), inside a collection only: on the
    /// whole library a named cluster was a way of laying things out, and making it a collection would file most of the
    /// library into it.
    func folderClusters() async -> [CanvasCluster]? {
        guard let store, let place = folderBoard, let key = canvasBoardKey else { return nil }
        let stored = await store.canvasBoard(key: key)?.clusters ?? []
        do {
            var all = try await store.index.collections()
            if place != .library, !bucket.readOnly, migratedBoards.insert(key).inserted {
                let strays = FolderClusters.strays(stored, folders: Set(all.map(\.id)))
                for c in strays {
                    _ = try await store.createCollection(id: c.id, name: c.title.trimmingCharacters(in: .whitespaces), parentId: place.parent)
                    try await store.add(ids: c.items, toCollection: c.id)
                }
                if !strays.isEmpty { all = try await store.index.collections(); bucket.nudge() }
            }
            let children = all.filter { $0.parentId == place.parent && !$0.archived }.sorted { $0.order < $1.order }
            var folders: [FolderClusters.Folder] = []
            for child in children {
                var members = Set<String>()
                for id in Self.subtree(child.id, in: all) { members.formUnion(try await store.index.itemIds(inCollection: id)) }
                folders.append(.init(id: child.id, title: child.displayName, members: members))
            }
            boardFolders = Set(children.map(\.id))
            return FolderClusters.reconcile(stored: stored, folders: folders, visible: items.map(\.id))
        } catch {
            return stored
        }
    }

    /// `id` and every collection beneath it.
    static func subtree(_ id: String, in all: [GrailsCollection]) -> Set<String> {
        var out: Set<String> = [id]
        var frontier = [id]
        while let next = frontier.popLast() {
            for c in all where c.parentId == next && out.insert(c.id).inserted { frontier.append(c.id) }
        }
        return out
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
        if folderBoard != nil, let clusters = await folderClusters() {
            guard key == canvasBoardKey else { return }
            canvasClusters = clusters
            canvasLoadedKey = key
            bumpCanvasVersion()
            return
        }
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
        // a folder board is read again from its folders on every reload (see `refreshSections`)
        guard let store, let key = canvasBoardKey, folderBoard == nil else { return }
        let ids = items.map(\.id)
        let adopted = ClusterOps.adopt(ids, into: canvasClusters)
        guard adopted != canvasClusters else { return }
        let known = Set(canvasClusters.flatMap(\.items))
        let fresh = ids.filter { !known.contains($0) }
        canvasClusters = adopted
        _ = try? await store.setClusters(boardKey: key, adopted)       // housekeeping: not an undo step
        if announce {
            bumpCanvasVersion()
            // while an import streams items in, the camera stays put: revealing each batch would swoop and zoom on every one
            if !known.isEmpty, !fresh.isEmpty, !importModel.isRunning { canvasRequest = CanvasRequest(kind: .reveal(fresh)) }
        }
    }

    static func aspect(of s: ItemSummary) -> Double { CanvasNSView.aspect(of: s) }

    /// An edit finished on the canvas: remember it locally and save it (undoable).
    func commitClusters(_ new: [CanvasCluster], label: String) {
        guard let store, let key = canvasBoardKey else { return }
        if folderBoard != nil { commitFolderClusters(new, label: label); return }
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

    /// An edit on a folder board: the layout is saved on the board, and moving pictures between clusters moves them between
    /// folders. A new cluster is a new folder; renaming a cluster renames its folder.
    private func commitFolderClusters(_ new: [CanvasCluster], label: String) {
        guard let store, let key = canvasBoardKey, let place = folderBoard else { return }
        let old = viewMode == .canvas && canvasLoadedKey == key ? canvasClusters : sectionClusters
        let edit = FolderClusters.edit(from: old, to: new, folders: boardFolders)
        if !edit.isEmpty {
            let canonID = Canon.collection(in: collections)?.id
            let touchesCanon = canonID.map { edit.added[$0] != nil || edit.removed[$0] != nil || edit.renamed[$0] != nil } ?? false
            let refusal = bucket.readOnly ? "Update Grails" : touchesCanon && !canPromoteToCanon ? "Only owners and admins can change \(Canon.title)" : nil
            if let refusal {
                showToast(refusal)
                bumpCanvasVersion()      // the canvas goes back to the board as it was
                return
            }
        }
        canvasClusters = new
        sectionClusters = new; sectionKey = key; rebuildSections()
        bumpCanvasVersion()
        let parent = place.parent
        let all = collections
        Task {
            do {
                let (_, undo) = try await recorded(label, in: store) {
                    for (id, ids) in edit.removed {
                        if id == FolderClusters.looseID { if let parent { try await store.remove(ids: ids, fromCollection: parent) } }
                        else { for c in Self.subtree(id, in: all) { try await store.remove(ids: ids, fromCollection: c) } }
                    }
                    for c in edit.created {
                        let name = c.title.trimmingCharacters(in: .whitespaces)
                        _ = try await store.createCollection(id: c.id, name: name.isEmpty ? "Untitled" : name, parentId: parent)
                        try await store.add(ids: c.items, toCollection: c.id)
                    }
                    for (id, ids) in edit.added {
                        if id == FolderClusters.looseID { if let parent { try await store.add(ids: ids, toCollection: parent) } }
                        else { try await store.add(ids: ids, toCollection: id) }
                    }
                    for (id, name) in edit.renamed { try await store.renameCollection(id: id, to: name) }
                    _ = try await store.setClusters(boardKey: key, new)
                }
                pushUndo(undo)
                if !edit.isEmpty {
                    bucket.nudge()
                    await reload()
                }
            } catch { errorMessage = "Couldn't save the canvas: \(error.localizedDescription)" }
        }
    }

    /// A folder's cluster goes away with its folder. Its pictures stay in the collection that's open (or, on the whole
    /// library, become unfiled); folders inside it move up.
    private func deleteClusterFolder(_ id: String) {
        guard let place = folderBoard, let folder = collections.first(where: { $0.id == id }) else { return }
        let parent = place.parent
        let name = folder.displayName
        Task {
            let done: Void? = await perform(folder.kind == "folder" ? "Delete Folder" : "Delete Collection") { store in
                if let parent { try await store.add(ids: try await store.index.itemIds(inCollection: id), toCollection: parent) }
                try await store.deleteCollection(id: id)
            }
            guard done != nil else { return }
            bucket.nudge()
            showToast("Deleted \(name)")
        }
    }

    // MARK: Cluster commands

    /// Names are edited in place on the canvas header (or the grid's section title).
    func promptRenameCluster(_ id: String) {
        guard folderBoard == nil || id != FolderClusters.looseID else { return }
        beginClusterRename?(id)
    }

    func renameCluster(_ id: String, to title: String) {
        guard folderBoard == nil || id != FolderClusters.looseID else { bumpCanvasVersion(); return }
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

    /// Folds a cluster to its title bar, or opens it again, in the grid and on the canvas alike.
    func toggleClusterCollapsed(_ id: String) {
        guard let key = canvasBoardKey else { return }
        var next = viewMode == .canvas && canvasLoadedKey == key ? canvasClusters : sectionClusters
        guard let i = next.firstIndex(where: { $0.id == id }) else { return }
        next[i].collapsed.toggle()
        next[i].at = Date().timeIntervalSince1970
        commitClusters(next, label: next[i].collapsed ? "Collapse Cluster" : "Expand Cluster")
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
        if folderBoard == nil || id != FolderClusters.looseID { add("Rename…", "pencil") { [self] in promptRenameCluster(id) } }
        add("Notes", "note.text") { [self] in
            let title = canvasClusters.first { $0.id == id }?.title ?? ""
            if let board = canvasBoardKey { showClusterNotes(board: board, id: id, title: title) }
        }
        if let c = (viewMode == .canvas ? canvasClusters : sectionClusters).first(where: { $0.id == id }) {
            add(c.collapsed ? "Expand" : "Collapse", c.collapsed ? "chevron.down" : "chevron.right") { [self] in toggleClusterCollapsed(id) }
        }
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
        if folderBoard != nil {
            // a folder board's clusters are folders: removing one deletes the folder, never its pictures
            if let folder = collections.first(where: { $0.id == id }), folder.id != Canon.collection(in: collections)?.id {
                add(folder.kind == "folder" ? "Delete Folder" : "Delete Collection", "trash") { [self] in deleteClusterFolder(id) }
            }
        } else {
            add("Dissolve Cluster", "rectangle.badge.minus") { [self] in dissolveCluster(id) }
        }
        return menu
    }
}

enum FolderBoard: Equatable {
    case library
    case collection(String)

    /// The collection whose folders are the clusters; nil for the whole library's top-level collections.
    var parent: String? {
        if case .collection(let id) = self { return id }
        return nil
    }
}
