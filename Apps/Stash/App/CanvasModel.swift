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

    /// Makes sure the canvas has the right board loaded and every visible item has a place on it.
    func syncCanvas() async {
        guard viewMode == .canvas, let key = canvasBoardKey else { return }
        if canvasLoadedKey != key { await loadBoard() } else { await placeMissingItems(announce: true) }
    }

    func loadBoard() async {
        guard let store, let key = canvasBoardKey else { return }
        canvasPlacements = await store.canvasBoard(key: key)?.placements ?? [:]
        canvasLoadedKey = key
        await placeMissingItems(announce: false)
        bumpCanvasVersion()
    }

    /// New items (a paste, a teammate's save) get a spot below existing work; the first time a board opens, a tidy layout.
    private func placeMissingItems(announce: Bool) async {
        guard let store, let key = canvasBoardKey else { return }
        let missing = items.filter { canvasPlacements[$0.id] == nil }
        guard !missing.isEmpty else { return }
        let entries = missing.map { CanvasLayoutEngine.Entry(id: $0.id, aspect: Self.aspect(of: $0)) }
        let hadWork = !canvasPlacements.isEmpty
        let placed = CanvasLayoutEngine.placeNew(entries, existing: canvasPlacements)
        for (id, p) in placed { canvasPlacements[id] = p }
        _ = try? await store.updatePlacements(boardKey: key, placed)
        if announce {
            bumpCanvasVersion()
            if hadWork { canvasRequest = CanvasRequest(kind: .reveal(Array(placed.keys))) }
        }
    }

    static func aspect(of s: ItemSummary) -> Double {
        if let w = s.width, let h = s.height, w > 0, h > 0 { return Double(w) / Double(h) }
        return s.kind == .link ? 4.0 / 3.0 : 1
    }

    /// A move, resize or nudge finished on the canvas: remember it locally and save it (undoable).
    func commitCanvas(_ updates: [String: CanvasPlacement], label: String) {
        guard let store, let key = canvasBoardKey, !updates.isEmpty else { return }
        for (id, p) in updates { canvasPlacements[id] = p }
        Task {
            do {
                let (_, undo) = try await recorded(label, in: store) { _ = try await store.updatePlacements(boardKey: key, updates) }
                pushUndo(undo)
            } catch { errorMessage = "Couldn't save the canvas: \(error.localizedDescription)" }
        }
    }

    /// Re-packs the selection (or everything) into tidy rows, keeping each item's size.
    func arrangeCanvas(selectionOnly: Bool) {
        let ids = selectionOnly && !selection.isEmpty ? Array(selection) : items.map(\.id)
        let updates = CanvasLayoutEngine.arrange(ids, in: canvasPlacements)
        guard !updates.isEmpty else { return }
        commitCanvas(updates, label: selectionOnly ? "Arrange Selection" : "Arrange All")
        bumpCanvasVersion()
        canvasRequest = CanvasRequest(kind: selectionOnly ? .fitSelection : .fit)
    }

    func canvasStacking(front: Bool) {
        let ids = selection.filter { canvasPlacements[$0] != nil }.sorted { (canvasPlacements[$0]!.z, $0) < (canvasPlacements[$1]!.z, $1) }
        guard !ids.isEmpty else { return }
        let zs = canvasPlacements.values.map(\.z)
        var updates: [String: CanvasPlacement] = [:]
        for (i, id) in ids.enumerated() {
            var p = canvasPlacements[id]!
            p.z = front ? (zs.max() ?? 0) + 1 + i : (zs.min() ?? 0) - ids.count + i
            updates[id] = p
        }
        commitCanvas(updates, label: front ? "Bring to Front" : "Send to Back")
        bumpCanvasVersion()
    }
}
