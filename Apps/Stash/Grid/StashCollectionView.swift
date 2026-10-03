import AppKit

/// NSCollectionView with the key handling, pointer-anchored zoom and dev hooks the grid needs.
final class StashCollectionView: NSCollectionView {
    var onPreview: (() -> Void)?
    var onOpen: (() -> Void)?
    var onEscape: (() -> Void)?
    /// +1 / -1 zoom step with the viewport point (in this view's coordinates) to keep fixed.
    var onZoom: ((Int, NSPoint) -> Void)?
    var onScrollActivity: (() -> Void)?
    private var magnifyAccumulator: CGFloat = 0

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
    }

    override func keyDown(with event: NSEvent) {
        guard event.modifierFlags.intersection([.command, .control, .option]).isEmpty else { return super.keyDown(with: event) }
        switch event.keyCode {
        case 49: onPreview?()          // space
        case 36, 76: onOpen?()         // return / enter
        case 53: onEscape?()           // escape
        default: super.keyDown(with: event)
        }
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
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
