import CoreGraphics
import Testing
@testable import GrailsDesign

@Suite struct PaletteTests {
    @Test func textIsReadableOnEverySurface() {
        for dark in [false, true] {
            for text in [Token.text, .link, .secondary] {
                for ground in [Token.canvas, .surface, .fill] {
                    // secondary on a hover fill is a label that sits on panels and the canvas only
                    if text == .secondary && ground == .fill { continue }
                    #expect(Palette.contrast(text, ground, dark: dark) >= 4.5, "\(text) on \(ground) dark=\(dark)")
                }
            }
            #expect(Palette.contrast(.focus, .surface, dark: dark) >= 3, "focus dark=\(dark)")
            #expect(Palette.contrast(.positive, .surface, dark: dark) >= 3)
            #expect(Palette.contrast(.destructive, .surface, dark: dark) >= 3)
        }
    }

    @Test func tertiaryNeverCarriesInformation() {
        // documented: decoration only, because it is below the text threshold on panels
        #expect(Palette.contrast(.tertiary, .surface, dark: false) < 4.5)
    }

    @Test func themesAreOpposites() {
        #expect(Palette.hex(.canvas, dark: false) == 0xFFFFFF && Palette.hex(.canvas, dark: true) == 0x000000)
        #expect(Palette.hex(.text, dark: false) == 0x000000 && Palette.hex(.text, dark: true) == 0xFFFFFF)
    }
}

@Suite struct MotionTests {
    @Test func nothingIsSlowOrBouncy() {
        for d in [Motion.quick, Motion.standard, Motion.flight] { #expect(d <= Motion.longest) }
        let c = Motion.standardCurve
        #expect((0...1).contains(c.y1) && (0...1).contains(c.y2))        // a y outside 0...1 is an overshoot
        #expect(Motion.zoomGlide(columnsChanged: 1) < Motion.zoomGlide(columnsChanged: 3))
        #expect(Motion.zoomGlide(columnsChanged: 40) <= Motion.longest)
    }
}

@Suite struct PagerTests {
    @Test func axisLocksAtTenPointsOrForcesAtTwentyFour() {
        var g = PagerGesture()
        g.add(dx: 6, dy: 1, at: 0)
        let early = g.axis
        g.add(dx: 6, dy: 2, at: 0.01)
        #expect(early == .undecided && g.axis == .horizontal)                    // 12 across, 3 down
        var v = PagerGesture()
        v.add(dx: 1, dy: 12, at: 0)
        #expect(v.axis == .vertical)
        var diagonal = PagerGesture()
        diagonal.add(dx: 9, dy: 8, at: 0)
        let tooClose = diagonal.axis
        diagonal.add(dx: 9, dy: 8, at: 0.01)                                     // 18 vs 16: ratio still below 1.5, under 24
        let stillClose = diagonal.axis
        diagonal.add(dx: 9, dy: 7, at: 0.02)                                     // 27 vs 23: past 24, take the dominant
        #expect(tooClose == .undecided && stillClose == .undecided && diagonal.axis == .horizontal)
    }

    @Test func velocityIsZeroOnceTheFingersRest() {
        var g = PagerGesture()
        for i in 0..<8 { g.add(dx: 10, dy: 0, at: Double(i) * 0.01) }
        let moving = g.velocity(at: 0.075)
        #expect(moving.x > 800 && moving.x < 1300)                                // about 10 pt per 10 ms
        #expect(g.velocity(at: 0.2).x == 0)
    }

    @Test func rubberBandResistsAndNeverPasses() {
        #expect(Pager.rubberBand(0, width: 800) == 0)
        #expect(Pager.rubberBand(100, width: 800) < 100)
        #expect(Pager.rubberBand(100, width: 800) > 0)
        #expect(Pager.rubberBand(-100, width: 800) == -Pager.rubberBand(100, width: 800))
        #expect(Pager.rubberBand(100_000, width: 800) < 800)
        #expect(Pager.rubberBand(400, width: 800) < Pager.rubberBand(800, width: 800))
    }

    @Test func pagesTurnOnDistanceOrFlick() {
        #expect(Pager.commitsPage(offset: -300, velocity: 0, width: 800))          // past 30 %
        #expect(!Pager.commitsPage(offset: -100, velocity: 0, width: 800))
        #expect(Pager.commitsPage(offset: -40, velocity: -600, width: 800))        // a flick the same way
        #expect(!Pager.commitsPage(offset: -40, velocity: 600, width: 800))        // a flick back
        #expect(!Pager.commitsPage(offset: -10, velocity: -900, width: 800))       // too small a move to count
    }

    @Test func dismissThresholds() {
        #expect(Pager.dismissProgress(dy: 0, height: 800) == 0)
        #expect(Pager.dismissProgress(dy: 200, height: 800) == 0.5)
        #expect(Pager.dismissProgress(dy: 5000, height: 800) == 1)
        #expect(Pager.commitsDismiss(dy: 130, vy: 0, height: 800))
        #expect(!Pager.commitsDismiss(dy: 60, vy: 0, height: 800))
        #expect(Pager.commitsDismiss(dy: 40, vy: 700, height: 800))
        #expect(!Pager.commitsDismiss(dy: 40, vy: -700, height: 800))
    }

    @Test func momentumAfterAGestureIsSwallowedUntilItEnds() {
        var gate = MomentumGate()
        let beforeAnything = gate.shouldSwallow(began: false, momentum: true, momentumEnded: false)
        #expect(!beforeAnything)                                                              // nothing handled yet
        gate.gestureEnded()
        let during = gate.shouldSwallow(began: false, momentum: true, momentumEnded: false)
        let last = gate.shouldSwallow(began: false, momentum: true, momentumEnded: true)
        let after = gate.shouldSwallow(began: false, momentum: false, momentumEnded: false)
        #expect(during && last && !after)                                                     // swallowed until the fling is over
        gate.gestureEnded()
        let fresh = gate.shouldSwallow(began: true, momentum: false, momentumEnded: false)
        #expect(!fresh)                                                                       // new fingers end the swallowing
    }

    @Test func fitKeepsMarginsAndNeverUpscales() {
        let big = Pager.fitRect(image: CGSize(width: 4000, height: 3000), stage: CGSize(width: 1000, height: 800))
        #expect(big.width <= 952 && big.height <= 752)
        #expect(abs(big.midX - 500) < 0.5 && abs(big.midY - 400) < 0.5)
        let small = Pager.fitRect(image: CGSize(width: 200, height: 100), stage: CGSize(width: 1000, height: 800))
        #expect(small.width == 200 && small.height == 100)                                  // one pixel per point at most
        #expect(Pager.isTall(CGSize(width: 800, height: 3000)) && !Pager.isTall(CGSize(width: 800, height: 1000)))
        #expect(Pager.maxZoom(fit: 0.2) == 2 && Pager.maxZoom(fit: 1) == 4)
    }
}

@Suite struct SpringTests {
    @Test func settlesWithoutOvershootingFromRest() {
        var s = CriticalSpring(value: 300, target: 0)
        var minValue = s.value
        for _ in 0..<120 { s.step(1.0 / 60); minValue = min(minValue, s.value) }
        #expect(s.value == 0 && minValue >= 0)                                    // never crossed the target
    }

    @Test func aFlickTowardTheTargetCarriesItThere() {
        var slow = CriticalSpring(value: 300, velocity: 0, target: 0)
        var fast = CriticalSpring(value: 300, velocity: -3000, target: 0)
        for _ in 0..<6 { slow.step(1.0 / 60); fast.step(1.0 / 60) }
        #expect(fast.value < slow.value)
    }

    @Test func aLongFrameIsStable() {
        var s = CriticalSpring(value: 500, velocity: 4000, target: 0)
        s.step(0.5)
        #expect(s.value.isFinite && abs(s.value) < 500)
    }

    @Test func finishesInAboutAQuarterSecond() {
        var s = CriticalSpring(value: 400, target: 0)
        var t = 0.0
        while !s.isSettled && t < 2 { s.step(1.0 / 120); t += 1.0 / 120 }
        #expect(t < 0.5)
    }
}
