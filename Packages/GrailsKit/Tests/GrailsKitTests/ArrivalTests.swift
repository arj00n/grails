import Testing
@testable import GrailsKit

@Suite struct ArrivalPacerTests {
    @Test func atMostEightEveryQuarterSecondWhileTheViewIsEmpty() {
        var p = ArrivalPacer()
        p.enqueue((0..<100).map(String.init))
        #expect(p.release(at: 0).count == 8)
        #expect(p.release(at: 0.1).isEmpty)
        #expect(p.release(at: 0.25).count == 8)
        var total = 16
        for k in 2..<40 { total += p.release(at: Double(k) * 0.25).count }
        #expect(total == 100 && p.isEmpty)
    }

    @Test func onceTheViewIsFullItIsOneBatchASecond() {
        var p = ArrivalPacer(); p.viewportFull = true
        p.enqueue((0..<40).map(String.init))
        #expect(p.release(at: 0).count == 8)
        #expect(p.release(at: 0.5).isEmpty && p.release(at: 0.99).isEmpty)
        #expect(p.release(at: 1.0).count == 8)
    }

    @Test func reduceMotionIsSlowerAndOrderIsKept() {
        var p = ArrivalPacer(reduceMotion: true)
        p.enqueue(["a", "b", "c"])
        #expect(p.release(at: 0) == ["a", "b", "c"])
        p.enqueue(["d"])
        #expect(p.release(at: 0.3).isEmpty && p.release(at: 0.5) == ["d"])
    }
}

@Suite struct EtaTests {
    func run(_ pace: Double, seconds: Int, total: Int = 2000) -> (Eta, Int) {
        var eta = Eta(); var handled = 0
        for s in 0...seconds { handled = Int(Double(s) * pace); eta.add(handled: handled, at: Double(s)) }
        return (eta, handled)
    }

    @Test func nothingIsSaidTooEarlyOrWhenPaused() {
        let (eta, h) = run(10, seconds: 15)
        #expect(eta.label(handled: h, total: 2000, elapsed: 15, paused: false) == nil)
        let (e2, h2) = run(10, seconds: 40)
        #expect(e2.label(handled: h2, total: 2000, elapsed: 40, paused: true) == nil)
        #expect(e2.label(handled: 10, total: 2000, elapsed: 40, paused: false) == nil)         // fewer than 40 pictures
    }

    @Test func roundsUpToMinutesAndSaysUnderAMinuteNearTheEnd() {
        let (eta, h) = run(10, seconds: 40)                               // 400 done at 10/s: 1,600 left = 160 s
        #expect(eta.label(handled: h, total: 2000, elapsed: 40, paused: false) == "About 3 min")
        #expect(eta.label(handled: h, total: 450, elapsed: 40, paused: false) == "Under a minute")
        #expect(eta.label(handled: h, total: 400, elapsed: 40, paused: false) == nil)                 // nothing left
    }

    @Test func aWildlyChangingPaceOrAnImpossiblyLongWaitIsNotShown() {
        var eta = Eta(); var handled = 0
        var t = 0.0
        for pace in [5.0, 50, 5, 50, 5] { for _ in 0..<20 { t += 1; handled += Int(pace); eta.add(handled: handled, at: t) } }
        #expect(eta.label(handled: handled, total: handled + 500, elapsed: t, paused: false) == nil)
        let (slow, h) = run(1, seconds: 60)
        #expect(slow.label(handled: h, total: 2_000_000, elapsed: 60, paused: false) == nil)           // days away
    }
}
