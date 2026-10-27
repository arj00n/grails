import AppKit
import GrailsKit

extension AppModel {
    /// Opens the preview on `id`, paging through what's on screen: the grid's order, or the canvas's reading order.
    func openPreview(_ id: String) {
        HoverVideo.shared.cancel(.other)          // the page plays it now; the tile's preview stops under it
        var source = items
        if viewMode == .canvas, !canvasClusters.isEmpty {
            let byID = Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            let placed = canvasClusters.flatMap(\.items)
            let placedSet = Set(placed)
            source = placed.compactMap { byID[$0] } + items.filter { !placedSet.contains($0.id) }
        }
        var set = PreviewSet(source)
        if set.position(of: id) == nil { set = PreviewSet(items) }
        guard set.position(of: id) != nil else { return }
        previewSet = set
        previewSetVersion += 1
        previewID = id
        selection = [id]
        noteReferenceOpened(id)
    }

    /// The details column and the library's info panel stay hidden from the first frame of the flight back to the tile.
    /// Fullscreen's own choice is untouched, so the next fullscreen opens the column as this one left it.
    func holdInfoClosedForPreviewReturn() {
        previewCloseGeneration += 1
        previewClosing = true
        infoPanel.holdClosedForReturn()
    }

    /// Fullscreen's details column, shown or hidden from its bar. Remembered for the next fullscreen.
    func toggleFullscreenInfo() {
        infoPanel.fullscreenOpen.toggle()
    }

    func closePreview() {
        guard previewID != nil else { return }
        // Before previewID clears, so a selection write in this turn cannot open the panel for a frame.
        holdInfoClosedForPreviewReturn()
        previewID = nil
        previewSet = nil
        PreviewImageCache.shared.clear()
        focusGridTick_bump()
        infoPanel.holdClosedForReturn()
        let generation = previewCloseGeneration
        Task { @MainActor [weak self] in
            guard let self, previewCloseGeneration == generation else { return }
            previewClosing = false
        }
    }

    /// A page turn finished in the stage.
    func commitPreview(position: Int) {
        guard let s = previewSet?[position] else { return }
        previewID = s.id
        selection = [s.id]
        noteReferenceOpened(s.id)
    }

    private func noteReferenceOpened(_ id: String) {
        Task {
            guard let store else { return }
            guard let item = try? await store.item(id: id), item.extras["openedAt"] == nil else { return }
            let now = Date().timeIntervalSince1970
            _ = try? await store.updateItem(id: id) { @Sendable (item: inout Item) in
                item.extras["openedAt"] = .double(now)
            }
        }
    }

    /// Something was deleted or filtered out while the preview was open: carry on at the next item. When nothing is left, the stage
    /// gets the empty set and closes itself, so the page leaves on its close motion rather than vanishing.
    func refreshPreviewSet() {
        guard var set = previewSet, let id = previewID, let position = set.position(of: id) else { return }
        let alive = Set(items.map(\.id))
        guard set.items.contains(where: { !alive.contains($0.id) }) else { return }
        guard let next = set.drop(where: { !alive.contains($0) }, keepingPosition: position), let s = set[next] else {
            previewSet = set
            previewSetVersion += 1
            return
        }
        previewSet = set
        previewSetVersion += 1
        previewID = s.id
        selection = [s.id]
    }

    func previewSource(for s: ItemSummary) -> PreviewSource {
        guard let layout else { return PreviewSource(original: nil, thumb: URL(fileURLWithPath: "/"), thumbMax: 512) }
        let snapshot = s.kind == .link && s.linkDisplay == "snapshot"
        let thumb = snapshot ? layout.snapshotURL(s.id) : layout.thumbURL(s.id)
        var original: URL?
        if s.kind != .link, let url = originalURL(for: s) {
            switch FileAvailability.of(url) {
            case .local where FileManager.default.fileExists(atPath: url.path): original = url
            case .cloudOnly: FileAvailability.requestDownload(url)          // the thumbnail shows meanwhile
            default: break
            }
        }
        return PreviewSource(original: original, thumb: thumb, thumbMax: snapshot ? 1600 : 512)
    }

    /// ⌘↩ in the preview: the page a link points to, or where a picture came from.
    func openPreviewSource() {
        guard let id = previewID else { return }
        if previewSet?[previewSet?.position(of: id) ?? -1]?.kind == .link { openLinkInBrowser(id); return }
        Task {
            guard let item = try? await store?.item(id: id), let s = item.source?.pageUrl ?? item.source?.url, let url = URL(string: s) else { return }
            NSWorkspace.shared.open(url)
        }
    }
}

extension AppModel {
    /// ⌘\: the panels away for a clean stage, and back. The info panel follows the sidebar.
    func togglePanels() {
        if sidebarVisible {
            hiddenPanels = true
            sidebarVisible = false
        } else {
            sidebarVisible = true
            hiddenPanels = nil
        }
    }
}

struct TileGeometry {
    var rect: (String) -> CGRect?
    var hide: (String, Bool) -> Void
}
