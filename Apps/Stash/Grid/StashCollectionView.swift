import AppKit

/// NSCollectionView with the key handling, pointer-anchored zoom and dev hooks the grid needs.
final class StashCollectionView: NSCollectionView {
    var onPreview: (() -> Void)?
    var onOpen: (() -> Void)?
    var onEscape: (() -> Void)?
    /// +1 / -1 zoom step with the viewport point (in this view's coordinates) to keep fixed.
    var onZoom: ((Int, NSPoint) -> Void)?
    var onScrollActivity: (() -> Void)?
    /// Plain-key shortcuts (L, T, M, …). Return true when handled. Only called while the grid itself has focus,
    /// so they never fire while a text field is being typed in.
    var keyHandler: ((NSEvent) -> Bool)?
    /// ⌥-click on a tile (like / unlike without changing the selection)
    var onOptionClick: ((Int) -> Void)?
    var onPaste: (() -> Void)?
    /// Builds the right-click menu for the tile at an index (also makes that tile the selection if it wasn't).
    var contextMenuProvider: ((Int) -> NSMenu?)?
    private var magnifyAccumulator: CGFloat = 0

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
        if event.clickCount == 2, indexPathForItem(at: convert(event.locationInWindow, from: nil)) != nil {
            super.mouseDown(with: event)
            onOpen?()
        } else {
            super.mouseDown(with: event)
        }
    }

    override func scrollWheel(with event: NSEvent) {
        if event.modifierFlags.contains(.command) {
            // ⌘+scroll zooms; one step per ~40 points of scroll
            magnifyAccumulator += event.scrollingDeltaY
            let p = convert(event.locationInWindow, from: nil)
            if magnifyAccumulator > 40 { magnifyAccumulator = 0; onZoom?(1, p) }
            else if magnifyAccumulator < -40 { magnifyAccumulator = 0; onZoom?(-1, p) }
            return
        }
        onScrollActivity?()
        super.scrollWheel(with: event)
    }

    override func magnify(with event: NSEvent) {
        magnifyAccumulator += event.magnification * 100
        let p = convert(event.locationInWindow, from: nil)
        if magnifyAccumulator > 25 { magnifyAccumulator = 0; onZoom?(1, p) }
        else if magnifyAccumulator < -25 { magnifyAccumulator = 0; onZoom?(-1, p) }
    }

    override func endGesture(with event: NSEvent) { magnifyAccumulator = 0 }
}
