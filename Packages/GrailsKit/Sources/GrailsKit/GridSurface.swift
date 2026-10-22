import AppKit

/// Grid and canvas views. A press here selects, drags an item, or rubber-bands, so it must not move the window.
open class GridSurface: NSView {
    public override init(frame frameRect: NSRect) { super.init(frame: frameRect) }
    public required init?(coder: NSCoder) { super.init(coder: coder) }
    open override var mouseDownCanMoveWindow: Bool { false }
}

open class GridSurfaceCollection: NSCollectionView {
    public override init(frame frameRect: NSRect) { super.init(frame: frameRect) }
    public required init?(coder: NSCoder) { super.init(coder: coder) }
    open override var mouseDownCanMoveWindow: Bool { false }
}

open class GridSurfaceScroll: NSScrollView {
    public override init(frame frameRect: NSRect) { super.init(frame: frameRect) }
    public required init?(coder: NSCoder) { super.init(coder: coder) }
    open override var mouseDownCanMoveWindow: Bool { false }
}

open class GridSurfaceClip: NSClipView {
    public override init(frame frameRect: NSRect) { super.init(frame: frameRect) }
    public required init?(coder: NSCoder) { super.init(coder: coder) }
    open override var mouseDownCanMoveWindow: Bool { false }
}

/// Placeholder and badges. The click belongs to the tile, including before the picture is on disk.
open class GridSurfaceImage: NSImageView {
    public override init(frame frameRect: NSRect) { super.init(frame: frameRect) }
    public required init?(coder: NSCoder) { super.init(coder: coder) }
    open override var mouseDownCanMoveWindow: Bool { false }
    open override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
