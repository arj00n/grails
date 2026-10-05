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
    }

    func closePreview() {
        guard previewID != nil else { return }
        previewID = nil
        previewSet = nil
        PreviewImageCache.shared.clear()
        focusGridTick_bump()
    }

    /// A page turn finished in the stage.
    func commitPreview(position: Int) {
        guard let s = previewSet?[position] else { return }
        previewID = s.id
        selection = [s.id]
    }

    /// Something was deleted or filtered out while the preview was open: carry on at the next item, or close if nothing is left.
    func refreshPreviewSet() {
        guard var set = previewSet, let id = previewID, let position = set.position(of: id) else { return }
        let alive = Set(items.map(\.id))
        guard set.items.contains(where: { !alive.contains($0.id) }) else { return }
        guard let next = set.drop(where: { !alive.contains($0) }, keepingPosition: position), let s = set[next] else { closePreview(); return }
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
