import SwiftUI
import Testing
@testable import GrailsDesign

@Suite struct InfoSplitTests {
    /// Every frame of the spring, overshoot included: the panel starts where the content ends, so it never lies over it.
    @Test func thePanelIsAColumnBesideTheContentNeverOverIt() {
        for total in [640.0, 1100.0, 1600.0] {
            for step in 0...40 {
                let reveal = -0.1 + Double(step) * 0.032
                let g = InfoSplitGeometry(total: total, columnWidth: 300, reveal: reveal)
                #expect(g.panelX >= g.contentWidth)
                #expect(abs(g.contentWidth + g.shownWidth - total) < 0.001)
                #expect(g.contentWidth >= 0 && g.shownWidth >= 0)
                #expect(g.panelWidth >= 300)
            }
        }
    }

    @Test func openingNarrowsTheContentByTheColumn() {
        let closed = InfoSplitGeometry(total: 1200, columnWidth: 300, reveal: 0)
        let open = InfoSplitGeometry(total: 1200, columnWidth: 300, reveal: 1)
        #expect(closed.contentWidth == 1200)
        #expect(closed.shownWidth == 0)
        #expect(open.contentWidth == 900)
        #expect(open.panelX == 900)
    }

    /// One ease-out for the width, the fade and the separator: every frame stays between closed and open, so the content beside
    /// it never reflows past its place, and the fade lands with the width.
    @Test func openingAndClosingNeverOvershoot() {
        #expect(GrailsInfoSplit<EmptyView, EmptyView>.motion(reduceMotion: false) == .grailsFlight)
        #expect(GrailsInfoSplit<EmptyView, EmptyView>.motion(reduceMotion: true) == nil)
        let c = Motion.standardCurve
        let curve = UnitCurve.bezier(startControlPoint: UnitPoint(x: c.x1, y: c.y1), endControlPoint: UnitPoint(x: c.x2, y: c.y2))
        var last = 0.0
        for step in 0...60 {
            let reveal = curve.value(at: Double(step) / 60)
            #expect(reveal >= last - 1e-9 && reveal <= 1 + 1e-9)
            let g = InfoSplitGeometry(total: 1200, columnWidth: 300, reveal: reveal)
            #expect(g.panelWidth == 300)                // the column only moves; it is never stretched and redrawn
            last = reveal
        }
        #expect(abs(last - 1) < 1e-9)
    }

    @Test func theLayoutPlacesThePanelBesideTheContent() {
        let layout = InfoSplitLayout(reveal: 1, columnWidth: 300)
        #expect(layout.animatableData == 1)
        var moved = layout
        moved.animatableData = 0.5
        #expect(moved.reveal == 0.5)
        #expect(GrailsInfoSplit<EmptyView, EmptyView>.columnWidth == 300)
    }
}
