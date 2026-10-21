import Testing
@testable import GrailsDesign

@Suite struct RowPointerHighlightTests {
    private func point(_ x: Double, _ y: Double) -> RowPointerHighlight.Point {
        RowPointerHighlight.Point(x, y)
    }

    @Test func movingThePointerOntoARowSelectsIt() {
        var highlight = RowPointerHighlight()
        highlight.place(point(0, 0))
        highlight.pointer(at: point(12, 36), over: 4)
        #expect(highlight.index == 4)
        highlight.move(by: 1, count: 8)
        #expect(highlight.index == 5)
        highlight.move(by: -1, count: 8)
        #expect(highlight.index == 4)
    }

    @Test func aStillPointerDoesNotFollowAScrollOrNewResults() {
        var highlight = RowPointerHighlight()
        highlight.place(point(4, 8))
        highlight.pointer(at: point(20, 16), over: 1)
        #expect(highlight.index == 1)
        highlight.move(by: 2, count: 6)
        #expect(highlight.index == 3)
        highlight.pointer(at: point(20, 16), over: 5)
        #expect(highlight.index == 3)
        highlight.reset()
        #expect(highlight.index == 0)
        highlight.pointer(at: point(20, 16), over: 2)
        #expect(highlight.index == 0)
    }

    @Test func aRowAppearingUnderThePointerIsNotAMove() {
        var highlight = RowPointerHighlight()
        highlight.pointer(at: point(3, 3), over: 2)
        #expect(highlight.index == 0)
        highlight.place(point(9, 9))
        highlight.pointer(at: point(3, 3), over: 4)
        #expect(highlight.index == 0)
    }

    @Test func aClickSelectsThatRowAndAStillPointerLeavesIt() {
        var highlight = RowPointerHighlight()
        highlight.place(point(0, 0))
        highlight.select(3)
        #expect(highlight.index == 3)
        highlight.pointer(at: point(0, 0), over: 1)
        #expect(highlight.index == 3)
        highlight.clamp(to: 2)
        #expect(highlight.index == 1)
        highlight.clamp(to: 0)
        #expect(highlight.index == 0)
    }
}
