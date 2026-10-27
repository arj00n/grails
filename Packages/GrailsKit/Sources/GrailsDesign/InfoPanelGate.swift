/// Whether a selection change may open the info panel.
///
/// A context-menu selection (right-click or control-click) keeps the panel as it was:
/// a closed panel stays closed, and an open panel stays open. Several writes in one
/// gesture share the first reading, so a deselect followed by a select cannot close it.
/// Any other selection clears that hold, and the panel may open.
public struct InfoPanelGate: Equatable {
    /// Visibility at the start of the current context-menu gesture. Nil between gestures.
    public private(set) var heldShown: Bool?

    public init() {}

    /// The value to store in the flag that keeps the panel closed.
    public mutating func keepClosed(wasShown: Bool, contextMenu: Bool) -> Bool {
        guard contextMenu else {
            heldShown = nil
            return false
        }
        let shown = heldShown ?? wasShown
        heldShown = shown
        return !shown
    }

    public mutating func endGesture() {
        heldShown = nil
    }
}

/// Where the info panel could be on screen.
public enum InfoPanelSurface: Sendable {
    case grid, canvas, fullscreen
}

/// Whether the info panel is open, decided per surface.
///
/// The grid never shows it: a click or the arrow keys only move the highlight. The canvas shows it while something is selected,
/// with the context-menu hold of `InfoPanelGate`, and keeps it closed on the way back from fullscreen until the next plain
/// selection there. Fullscreen has its own choice, which no selection anywhere changes, so leaving fullscreen and coming back
/// finds the panel as it was left.
public struct InfoPanelState: Equatable {
    /// Fullscreen's choice. Open until it is closed there.
    public var fullscreenOpen = true
    /// The canvas panel is held closed: by the return from fullscreen, or by a context menu that found it closed.
    public private(set) var canvasHeldClosed = false
    private var gate = InfoPanelGate()

    public init() {}

    public func isOpen(on surface: InfoPanelSurface, hasSelection: Bool, sidebarVisible: Bool) -> Bool {
        switch surface {
        case .grid: false
        case .canvas: sidebarVisible && hasSelection && !canvasHeldClosed
        case .fullscreen: fullscreenOpen
        }
    }

    /// The selection changed. `inFullscreen` covers the flight back to the tile too.
    public mutating func selectionChanged(wasShown: Bool, contextMenu: Bool, inFullscreen: Bool) {
        if inFullscreen {
            canvasHeldClosed = true
            return
        }
        canvasHeldClosed = gate.keepClosed(wasShown: wasShown, contextMenu: contextMenu)
    }

    /// Fullscreen is closing: the library's panel stays shut on the way back.
    public mutating func holdClosedForReturn() {
        canvasHeldClosed = true
    }

    public mutating func endContextMenuGesture() {
        gate.endGesture()
    }
}

/// What the info panel shows: the live value while it is open, and the value it last showed while it closes and stays closed.
///
/// The canvas closes its panel by clearing the selection, so without this the panel would switch to the view's totals in the
/// same update and fade those out instead of the item it was showing. Opening shows the live value at once.
public struct InfoPanelHold<Value: Equatable>: Equatable {
    public private(set) var held: Value

    public init(_ value: Value) { held = value }

    public func shown(isOpen: Bool, live: Value) -> Value { isOpen ? live : held }

    public mutating func update(isOpen: Bool, live: Value) {
        if isOpen { held = live }
    }
}
