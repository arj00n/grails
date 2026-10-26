import AppKit
import GrailsDesign

/// NSCollectionView with the key handling, pointer-anchored zoom and dev hooks the grid needs.
final class GrailsCollectionView: NSCollectionView {
    var onPreview: (() -> Void)?
    var onOpen: (() -> Void)?
    /// A plain click landed on the item at this index.
    var onClickOpen: ((Int) -> Void)?
    /// Set when a press turned into a drag (the data source was asked for what to carry): that press never opens the picture.
    var dragBegan = false
    /// The picture a plain press landed on, waiting for the button to come up.
    private var pendingOpen: (item: Int, point: CGPoint)?
    /// The tile under a held click: it shrinks while held and springs back on release or once the click becomes a drag.
    private weak var pressedTile: NSView?
    private var pressedAt: CGPoint = .zero
    /// Double-click on an item; true when it was a section title and got renamed in place instead of opened.
    var onRenameSection: ((Int) -> Bool)?
    var onToggleSection: ((Int) -> Void)?
    var onEscape: (() -> Void)?
    var onSearch: (() -> Void)?
    /// Multiplicative zoom (1.02 = 2% bigger) about a point in this view's coordinates, delivered continuously while
    /// pinching or ⌘-scrolling. `onZoomEnd` fires when the gesture finishes.
    var onZoom: ((CGFloat, NSPoint) -> Void)?
    var onZoomEnd: (() -> Void)?
    var onScrollActivity: (() -> Void)?
    /// Plain-key shortcuts (L, T, M, …). Return true when handled. Only called while the grid itself has focus,
    /// so they never fire while a text field is being typed in.
    var keyHandler: ((NSEvent) -> Bool)?
    /// ⌥-click on a tile (like / unlike without changing the selection)
    var onOptionClick: ((Int) -> Void)?
    var onPaste: (() -> Void)?
    /// Builds the right-click menu for the tile at an index (also makes that tile the selection if it wasn't).
    var contextMenuProvider: ((Int) -> NSMenu?)?
    /// The view joined a window. The grid uses this to load thumbnails without waiting for a click.
    var onAttached: (() -> Void)?
    /// After every layout pass (new items, width, zoom), so what is pinned to the viewport follows the new frames.
    var onLayout: (() -> Void)?

    override var acceptsFirstResponder: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    override func layout() {
        super.layout()
        onLayout?()
    }

    /// Edit ▸ Paste while the grid has focus (text fields keep their own paste).
    @objc func paste(_ sender: Any?) { onPaste?() }

    override func menu(for event: NSEvent) -> NSMenu? {
        let p = convert(event.locationInWindow, from: nil)
        guard let ip = indexPathForItem(at: p) else { return nil }
        window?.makeFirstResponder(self)
        return contextMenuProvider?(ip.item)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
        onAttached?()
    }

    override func keyDown(with event: NSEvent) {
        guard event.modifierFlags.intersection([.command, .control, .option]).isEmpty else { return super.keyDown(with: event) }
        if event.modifierFlags.intersection(Shortcut.mask).isEmpty, keyHandler?(event) == true { return }
        switch event.keyCode {
        case 49: onPreview?()          // space
        case 36, 76: onOpen?()         // return / enter
        case 53: onEscape?()           // escape
        case 44: onSearch?()           // /
        default: super.keyDown(with: event)
        }
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        if event.modifierFlags.contains(.option), !event.modifierFlags.contains(.command),
           let ip = indexPathForItem(at: convert(event.locationInWindow, from: nil)) {
            onOptionClick?(ip.item)
            return
        }
        let down = event.locationInWindow
        let hit = indexPathForItem(at: convert(down, from: nil))
        // the arrow in front of a section's title folds it; a fast second click on it doesn't rename
        if let hit, let cell = item(at: hit) as? ThumbCell, cell.isSection, cell.sectionArrowContains(cell.view.convert(down, from: nil)) {
            if event.clickCount == 1 { onToggleSection?(hit.item) }
            return
        }
        // double-clicking a section's title edits its name
        if event.clickCount == 2, let hit {
            super.mouseDown(with: event)
            _ = onRenameSection?(hit.item)
            return
        }
        dragBegan = false
        pendingOpen = nil
        if let hit, let cell = item(at: hit) as? ThumbCell, !cell.isSection {
            LayerPress.press(cell.view, scale: Motion.tilePressScale)
            pressedTile = cell.view
            pressedAt = down
        }
        super.mouseDown(with: event)
        // the collection view may have tracked the whole click (a drag, a rubber band) before returning
        if NSEvent.pressedMouseButtons & 1 == 0 { releaseTile() }
        // a plain click on a picture opens it, but only once the button comes up and nothing was dragged: pressing and moving picks the
        // picture up instead (⌘ and ⇧ build a selection and never open)
        if event.clickCount == 1, let hit, event.modifierFlags.intersection([.command, .shift, .control]).isEmpty {
            pendingOpen = (hit.item, down)
        }
    }

    override func mouseDragged(with event: NSEvent) {
        if let p = pendingOpen, hypot(event.locationInWindow.x - p.point.x, event.locationInWindow.y - p.point.y) >= 3 { pendingOpen = nil }
        if pressedTile != nil, hypot(event.locationInWindow.x - pressedAt.x, event.locationInWindow.y - pressedAt.y) >= 3 { releaseTile() }
        super.mouseDragged(with: event)
    }

    private func releaseTile() {
        if let pressedTile { LayerPress.release(pressedTile) }
        pressedTile = nil
    }

    override func mouseUp(with event: NSEvent) {
        releaseTile()
        let open = pendingOpen
        pendingOpen = nil
        super.mouseUp(with: event)
        guard let open, !dragBegan, hypot(event.locationInWindow.x - open.point.x, event.locationInWindow.y - open.point.y) < 3 else { return }
        onClickOpen?(open.item)
    }

    override func scrollWheel(with event: NSEvent) {
        if event.modifierFlags.contains(.command) {
            // ⌘ + two-finger scroll zooms continuously about the pointer
            let p = convert(event.locationInWindow, from: nil)
            onZoom?(exp(event.scrollingDeltaY * (event.hasPreciseScrollingDeltas ? 0.006 : 0.03)), p)
            if event.phase == .ended || event.momentumPhase == .ended || event.phase == .cancelled { onZoomEnd?() }
            return
        }
        onScrollActivity?()
        super.scrollWheel(with: event)
    }

    override func magnify(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        onZoom?(1 + event.magnification, p)
        if event.phase == .ended || event.phase == .cancelled { onZoomEnd?() }
    }

    override func endGesture(with event: NSEvent) { onZoomEnd?() }
}

final class GridScrollView: NSScrollView {
    override var mouseDownCanMoveWindow: Bool { false }
}

final class GridClipView: NSClipView {
    override var mouseDownCanMoveWindow: Bool { false }
}

/// What the grid hands SwiftUI. Its frame is the content area under the top bar and does not change with a page; the tag
/// strip and mention bar (`chromeTop`) are taken off the scroll view inside it. A page crossfade on this layer then fades the
/// previous page out exactly where it was.
final class GridContainer: NSView {
    override var mouseDownCanMoveWindow: Bool { false }
    var chromeTop: CGFloat = 0 {
        didSet { if chromeTop != oldValue { placeScroll() } }
    }

    override func resizeSubviews(withOldSize oldSize: NSSize) {
        super.resizeSubviews(withOldSize: oldSize)
        placeScroll()
    }

    private func placeScroll() {
        guard let scroll = subviews.first(where: { $0 is NSScrollView }) else { return }
        let frame = NSRect(x: 0, y: 0, width: bounds.width, height: max(0, bounds.height - chromeTop))
        if scroll.frame != frame { scroll.frame = frame }
    }
}
