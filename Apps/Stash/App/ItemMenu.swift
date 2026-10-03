import AppKit
import StashKit

extension AppModel {
    /// The right-click menu for the selected items, shared by the grid and the canvas.
    func itemContextMenu(anchor s: ItemSummary, canvas: Bool) -> NSMenu {
        let selected = selectedSummaries
        let links = selected.filter { $0.kind == .link }
        let menu = NSMenu()
        func add(_ title: String, _ symbol: String? = nil, _ action: @escaping @MainActor () -> Void) {
            let item = ClosureMenuItem(title: title, handler: action)
            if let symbol { item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) }
            menu.addItem(item)
        }
        add(selected.count == 1 ? "Open Preview" : "Preview", "eye") { [self] in openPreview(s.id) }
        if selected.count == 1, s.kind == .link { add("Open Link in Browser", "safari") { [self] in openLinkInBrowser(s.id) } }
        if !links.isEmpty {
            let sub = NSMenu()
            for (title, mode) in [("Preview Image", "image"), ("Page Snapshot", "snapshot"), ("Title Only", "title")] {
                let item = ClosureMenuItem(title: title) { [self] in setLinkDisplay(mode, ids: links.map(\.id)) }
                if links.count == 1, links[0].linkDisplay == mode { item.state = .on }
                sub.addItem(item)
            }
            let parent = NSMenuItem(title: "Show Link As", action: nil, keyEquivalent: "")
            parent.submenu = sub
            menu.addItem(parent)
            if links.count == 1 { add("Retake Snapshot", "camera.viewfinder") { [self] in retakeSnapshot(id: links[0].id) } }
        }
        if canvas {
            menu.addItem(.separator())
            add("Bring to Front", "square.3.layers.3d.top.filled") { [self] in canvasStacking(front: true) }
            add("Send to Back", "square.3.layers.3d.bottom.filled") { [self] in canvasStacking(front: false) }
            if selected.count > 1 { add("Arrange Selection", "rectangle.grid.2x2") { [self] in arrangeCanvas(selectionOnly: true) } }
            add("Zoom to Selection", "arrow.up.left.and.down.right.magnifyingglass") { [self] in canvasRequest = CanvasRequest(kind: .fitSelection) }
        }
        menu.addItem(.separator())
        let allLiked = selected.allSatisfy(\.liked)
        add(allLiked ? "Unlike" : "Like", allLiked ? "heart.slash" : "heart") { [self] in run(.like) }
        add("Edit Tags…", "tag") { [self] in run(.tag) }
        add("Move to Collection…", "rectangle.stack") { [self] in run(.move) }
        add("Add Note…", "note.text") { [self] in run(.note) }
        add("Copy Source URL", "link") { [self] in run(.copyURL) }
        if selected.count == 1, s.kind != .link, let url = originalURL(for: s), FileManager.default.fileExists(atPath: url.path) {
            add("Reveal in Finder", "folder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
        }
        menu.addItem(.separator())
        if source == .trash { add("Restore", "arrow.uturn.backward") { [self] in restoreSelection() } }
        else { add("Move to Trash", "trash") { [self] in run(.trash) } }
        return menu
    }
}
