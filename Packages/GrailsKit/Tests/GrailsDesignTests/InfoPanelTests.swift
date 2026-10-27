import Testing
@testable import GrailsDesign

@Suite struct InfoPanelTests {
    @Test func rightClickDoesNotOpenOrToggleTheInfoPanel() {
        var gate = InfoPanelGate()

        // A closed panel stays closed. A second write in the same gesture cannot open it.
        let closed = gate.keepClosed(wasShown: false, contextMenu: true)
        let stillClosed = gate.keepClosed(wasShown: true, contextMenu: true)
        #expect(closed)
        #expect(stillClosed)
        gate.endGesture()

        // An open panel stays open. A deselect in the same gesture reports the panel as closed;
        // the gesture still remembers that it was open, so it does not toggle shut.
        let staysOpen = gate.keepClosed(wasShown: true, contextMenu: true)
        let staysOpenAfterDeselect = gate.keepClosed(wasShown: false, contextMenu: true)
        #expect(!staysOpen)
        #expect(!staysOpenAfterDeselect)
        gate.endGesture()

        // The next gesture reads the panel again. Closed stays closed.
        let nextGesture = gate.keepClosed(wasShown: false, contextMenu: true)
        #expect(nextGesture)
        gate.endGesture()

        // A click, the arrow keys, or a marquee may open the panel.
        let click = gate.keepClosed(wasShown: false, contextMenu: false)
        let arrows = gate.keepClosed(wasShown: true, contextMenu: false)
        #expect(!click)
        #expect(!arrows)
        #expect(gate.heldShown == nil)
    }

    @Test func arrowKeysInTheGridAfterFullscreenNeverOpenThePanel() {
        var state = InfoPanelState()

        // Open an item fullscreen: the details column is there, and the selection follows the page.
        state.selectionChanged(wasShown: false, contextMenu: false, inFullscreen: true)
        #expect(state.isOpen(on: .fullscreen, hasSelection: true, sidebarVisible: true))

        // Close it. The tile stays highlighted, the grid shows no panel.
        state.holdClosedForReturn()
        #expect(!state.isOpen(on: .grid, hasSelection: true, sidebarVisible: true))

        // The arrow keys and clicks move the highlight. Still no panel, however many moves.
        for _ in 0..<5 {
            state.selectionChanged(wasShown: false, contextMenu: false, inFullscreen: false)
            #expect(!state.isOpen(on: .grid, hasSelection: true, sidebarVisible: true))
        }
        state.selectionChanged(wasShown: false, contextMenu: true, inFullscreen: false)
        state.endContextMenuGesture()
        #expect(!state.isOpen(on: .grid, hasSelection: true, sidebarVisible: true))

        // Back into fullscreen: the column comes back as it was left.
        state.selectionChanged(wasShown: false, contextMenu: false, inFullscreen: true)
        #expect(state.isOpen(on: .fullscreen, hasSelection: true, sidebarVisible: true))
    }

    @Test func fullscreenRemembersItsOwnChoice() {
        var state = InfoPanelState()
        state.fullscreenOpen = false
        state.holdClosedForReturn()
        for _ in 0..<3 { state.selectionChanged(wasShown: false, contextMenu: false, inFullscreen: false) }
        state.selectionChanged(wasShown: false, contextMenu: false, inFullscreen: true)
        #expect(!state.isOpen(on: .fullscreen, hasSelection: true, sidebarVisible: true))

        state.fullscreenOpen = true
        state.holdClosedForReturn()
        state.selectionChanged(wasShown: false, contextMenu: false, inFullscreen: false)
        state.selectionChanged(wasShown: false, contextMenu: false, inFullscreen: true)
        #expect(state.isOpen(on: .fullscreen, hasSelection: true, sidebarVisible: true))
    }

    @Test func theCanvasPanelFollowsTheSelectionAndWaitsAfterFullscreen() {
        var state = InfoPanelState()
        state.selectionChanged(wasShown: false, contextMenu: false, inFullscreen: false)
        #expect(state.isOpen(on: .canvas, hasSelection: true, sidebarVisible: true))
        #expect(!state.isOpen(on: .canvas, hasSelection: false, sidebarVisible: true))
        #expect(!state.isOpen(on: .canvas, hasSelection: true, sidebarVisible: false))

        // On the way back from fullscreen it stays shut until the next plain selection on the canvas.
        state.holdClosedForReturn()
        #expect(!state.isOpen(on: .canvas, hasSelection: true, sidebarVisible: true))
        state.selectionChanged(wasShown: false, contextMenu: true, inFullscreen: false)
        #expect(!state.isOpen(on: .canvas, hasSelection: true, sidebarVisible: true))
        state.endContextMenuGesture()
        state.selectionChanged(wasShown: false, contextMenu: false, inFullscreen: false)
        #expect(state.isOpen(on: .canvas, hasSelection: true, sidebarVisible: true))
    }

    @Test func theDetailsColumnFadesOutWithTheReturnToATile() {
        #expect(PreviewInfoFade.opacity(flight: 1, dismiss: 0, returningToTile: true) == 1)
        #expect(abs(PreviewInfoFade.opacity(flight: 0.7, dismiss: 0, returningToTile: true) - 0.7) < 0.001)
        #expect(PreviewInfoFade.opacity(flight: 0, dismiss: 0, returningToTile: true) == 0)
        #expect(PreviewInfoFade.opacity(flight: -0.03, dismiss: 0, returningToTile: true) == 0)

        #expect(PreviewInfoFade.opacity(flight: 1, dismiss: 0, returningToTile: false) == 1)
        let mid = PreviewInfoFade.opacity(flight: 0.7, dismiss: 0, returningToTile: false)
        #expect(abs(mid - 0.5) < 0.001)
        #expect(PreviewInfoFade.opacity(flight: 0.4, dismiss: 0, returningToTile: false) == 0)
        #expect(PreviewInfoFade.opacity(flight: 1, dismiss: 1.0 / 3.0, returningToTile: false) == 0)
    }

    /// The canvas closes its panel by clearing the selection: the closing panel keeps the item, it does not swap to the totals.
    @Test func aClosingPanelKeepsShowingWhatItShowedOpen() {
        var hold = InfoPanelHold<Set<String>>([])
        #expect(hold.shown(isOpen: true, live: ["a"]) == ["a"])
        hold.update(isOpen: true, live: ["a"])
        hold.update(isOpen: true, live: ["b"])
        // the close: selection and visibility change in one update
        hold.update(isOpen: false, live: [])
        #expect(hold.shown(isOpen: false, live: []) == ["b"])
        // opening on another item shows it at once, not the held one
        #expect(hold.shown(isOpen: true, live: ["c"]) == ["c"])
    }
}
