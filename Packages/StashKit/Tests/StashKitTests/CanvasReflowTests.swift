import Foundation
import Testing
@testable import StashKit

@Suite struct CanvasReflowTests {
    func p(_ x: Double, _ y: Double, _ w: Double = 100, _ h: Double = 100) -> CanvasPlacement { CanvasPlacement(x: x, y: y, w: w, h: h, z: 0, at: 1) }

    func overlap(_ a: CanvasPlacement, _ b: CanvasPlacement, gap: Double = 0) -> Bool {
        a.x < b.maxX + gap && b.x < a.maxX + gap && a.y < b.maxY + gap && b.y < a.maxY + gap
    }

    @Test func nothingMovesWhenNothingOverlaps() {
        let board = ["a": p(0, 0), "b": p(400, 0), "c": p(0, 400)]
        #expect(CanvasReflow.resolve(moved: ["a"], in: board).isEmpty)
        #expect(CanvasReflow.resolve(moved: [], in: board).isEmpty)
        #expect(CanvasReflow.resolve(moved: ["ghost"], in: board).isEmpty)
    }

    @Test func droppingOnAnItemPushesItClearAndKeepsAGap() {
        let board = ["a": p(60, 10), "b": p(100, 0)]                  // a lands on the left half of b
        let out = CanvasReflow.resolve(moved: ["a"], in: board, gap: 16)
        #expect(out.keys.sorted() == ["b"])
        let b = out["b"]!
        #expect(!overlap(board["a"]!, b, gap: 15.9))
        #expect(b.w == 100 && b.h == 100)                             // pushed, never resized
        // the shortest way out is straight right (it's the biggest overlap on x, small on y): moved by under 100 + gap
        #expect(b.x > 100 && abs(b.x - 176) < 0.001 && b.y == 0)
    }

    @Test func theDraggedItemNeverMoves() {
        let board = ["a": p(50, 50), "b": p(0, 0), "c": p(100, 100)]
        let out = CanvasReflow.resolve(moved: ["a"], in: board)
        #expect(out["a"] == nil)
    }

    @Test func pushesCascadeThroughARow() {
        // four tiles shoulder to shoulder; a fifth is dropped onto the first
        var board: [String: CanvasPlacement] = ["drag": p(10, 5)]
        for i in 0..<4 { board["t\(i)"] = p(Double(i) * 100, 0) }
        let out = CanvasReflow.resolve(moved: ["drag"], in: board, hint: (1, 0), gap: 10)
        let final = board.merging(out) { $1 }
        let ids = final.keys.sorted()
        for (i, a) in ids.enumerated() { for b in ids[(i + 1)...] { #expect(!overlap(final[a]!, final[b]!), "\(a) overlaps \(b)") } }
        // dragging right: tiles go right, in order, and none jumps over another
        for i in 0..<3 where final["t\(i)"]!.x > 0 { #expect(final["t\(i)"]!.x < final["t\(i + 1)"]!.x) }
        #expect(out.count >= 2)
    }

    @Test func theDragDirectionDecidesWhichWayThingsGo() {
        let board = ["a": p(40, 40), "b": p(80, 60)]                    // heavy overlap, a nearly centred on b
        let down = CanvasReflow.resolve(moved: ["a"], in: board, hint: (0, 1))["b"]!
        let right = CanvasReflow.resolve(moved: ["a"], in: board, hint: (1, 0))["b"]!
        #expect(down.y > right.y)                                        // dragged downwards ⇒ b slides down
        #expect(right.x > down.x || right.x == down.x)
        let left = CanvasReflow.resolve(moved: ["a"], in: ["a": p(300, 40), "b": p(260, 60)], hint: (-1, 0))["b"]!
        #expect(left.x < 260)                                            // dragged leftwards ⇒ b goes left
    }

    @Test func aGroupPushesAroundEveryMember() {
        let board = ["a": p(0, 0), "b": p(120, 0), "x": p(60, 20)]       // x sits between the two dragged items
        let out = CanvasReflow.resolve(moved: ["a", "b"], in: board, gap: 8)
        let x = (board.merging(out) { $1 })["x"]!
        #expect(!overlap(board["a"]!, x, gap: 7.9) && !overlap(board["b"]!, x, gap: 7.9))
    }

    @Test func itemsComeBackWhenTheDragMovesAway() {
        // the canvas always resolves from the original layout, so a pushed item returns home on its own
        let home = ["a": p(500, 500), "b": p(100, 0)]
        var board = home; board["a"] = p(90, 10)
        #expect(CanvasReflow.resolve(moved: ["a"], in: board)["b"] != nil)
        board["a"] = p(500, 500)
        #expect(CanvasReflow.resolve(moved: ["a"], in: board).isEmpty)
    }

    @Test func existingStacksThatNobodyTouchedStayPut() {
        let board = ["s1": p(900, 900), "s2": p(920, 920), "a": p(0, 0), "b": p(50, 0)]    // s1/s2 overlap on purpose, far away
        let out = CanvasReflow.resolve(moved: ["a"], in: board)
        #expect(out["s1"] == nil && out["s2"] == nil)
    }

    @Test func isDeterministic() {
        var board: [String: CanvasPlacement] = [:]
        for i in 0..<60 { board["i\(i)"] = p(Double(i % 8) * 90, Double(i / 8) * 90, 80, 80) }
        board["i0"] = p(200, 200)
        func spots(_ r: [String: CanvasPlacement]) -> [String: [Double]] { r.mapValues { [$0.x, $0.y] } }   // `at` is a timestamp
        let a = spots(CanvasReflow.resolve(moved: ["i0"], in: board, hint: (1, 0.3)))
        #expect(!a.isEmpty)
        for _ in 0..<5 { #expect(spots(CanvasReflow.resolve(moved: ["i0"], in: board, hint: (1, 0.3))) == a) }
    }

    struct Seeded: RandomNumberGenerator {
        var s: UInt64
        mutating func next() -> UInt64 { s = s &* 6364136223846793005 &+ 1442695040888963407; return s }
    }

    @Test func randomBoardsEndUpWithoutOverlapsAroundTheDrop() {
        var worst = 0
        for trial in 0..<3000 {
            var rng = Seeded(s: UInt64(trial) &+ 1)         // seeded: a failure names its trial and can be replayed
            // a tidy 7x7 grid, then one item dropped somewhere inside it
            var board: [String: CanvasPlacement] = [:]
            for i in 0..<49 { board["i\(i)"] = p(Double(i % 7) * 140, Double(i / 7) * 140, 120, 120) }
            let dragged = "i\(Int.random(in: 0..<49, using: &rng))"
            board[dragged] = p(Double.random(in: 0...800, using: &rng), Double.random(in: 0...800, using: &rng), 120, 120)
            let out = CanvasReflow.resolve(moved: [dragged], in: board, hint: (Double.random(in: -1...1, using: &rng), Double.random(in: -1...1, using: &rng)), gap: 10)
            let final = board.merging(out) { $1 }
            // nothing may overlap the dragged item
            for (id, q) in final where id != dragged { #expect(!overlap(final[dragged]!, q), "trial \(trial): \(id) still under the dragged item") }
            // and, other than the hole the dragged item left, neighbours shouldn't pile up on each other
            var pairs = 0
            let ids = final.keys.sorted()
            for (i, a) in ids.enumerated() { for b in ids[(i + 1)...] where a != dragged && b != dragged && overlap(final[a]!, final[b]!) { pairs += 1 } }
            worst = max(worst, pairs)
        }
        #expect(worst <= 2, "worst case left \(worst) overlapping pairs")
    }

    @Test func staysFastOnABigBoard() {
        var board: [String: CanvasPlacement] = [:]
        for i in 0..<20_000 { board["i\(i)"] = p(Double(i % 200) * 140, Double(i / 200) * 140, 120, 120) }
        board["i5000"] = p(5 * 140 + 30, 25 * 140 + 30, 120, 120)
        let t0 = Date()
        let out = CanvasReflow.resolve(moved: ["i5000"], in: board, hint: (1, 0))
        let ms = Date().timeIntervalSince(t0) * 1000
        print("reflow on 20k items: \(Int(ms)) ms, displaced \(out.count)")
        #expect(ms < 150)                                               // debug build; it runs on every drag event
        #expect(out.count < 400)                                        // a local nudge, not a global reshuffle
    }
}
