import AppKit

/// NSCollectionView with the key handling, pointer-anchored zoom and dev hooks the grid needs.
final class GrailsCollectionView: NSCollectionView {
    var onPreview: (() -> Void)?
    var onOpen: (() -> Void)?
    /// A plain click landed on the item at this index.
    var onClickOpen: ((Int) -> Void)?
    /// Double-click on an item; true when it was a section title and got renamed in place instead of opened.
    var onRenameSection: ((Int) -> Bool)?
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

    override var acceptsFirstResponder: Bool { true }

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
        // double-clicking a section's title edits its name
        if event.clickCount == 2, let hit {
            super.mouseDown(with: event)
            _ = onRenameSection?(hit.item)
            return
        }
        super.mouseDown(with: event)
        // a plain click on a picture opens it: one click, no drag (a drag moves things), no ⌘ or ⇧ (those build a selection)
        if event.clickCount == 1, let hit, event.modifierFlags.intersection([.command, .shift, .control]).isEmpty {
            let up = window?.currentEvent?.locationInWindow ?? down
            if hypot(up.x - down.x, up.y - down.y) < 4 { onClickOpen?(hit.item) }
        }
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
