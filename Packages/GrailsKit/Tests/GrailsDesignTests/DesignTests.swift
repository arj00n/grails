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
        }
    }

    @Test func tertiaryNeverCarriesInformation() {
        // placeholder grey sits below the text threshold on a field
        #expect(Palette.contrast(.tertiary, .surface, dark: false) < 4.5)
    }

    @Test func approvedTokens() {
        #expect(Palette.hex(.canvas, dark: false) == 0xFFFFFF && Palette.hex(.canvas, dark: true) == 0x1C1D20)
        #expect(Palette.hex(.text, dark: false) == 0x1A1A1A && Palette.hex(.text, dark: true) == 0xF3F4F6)
        #expect(Palette.hex(.focus, dark: false) == 0xA8A8A4 && Palette.hex(.focus, dark: true) == 0x5E6067)
        #expect(Palette.hex(.secondary, dark: false) == 0x6B6B68 && Palette.hex(.secondary, dark: true) == 0x9A9CA2)
        #expect(Palette.hex(.backdrop, dark: false) == 0xECECEA && Palette.hex(.sidebar, dark: true) == 0x18191B)
        #expect(Palette.hex(.positive, dark: false) == Palette.hex(.text, dark: false))
        #expect(Palette.hex(.destructive, dark: true) == Palette.hex(.text, dark: true))
        #expect(Palette.hex(.statusOk, dark: true) == 0x3FB950 && Palette.hex(.statusOk, dark: false) == 0x2DA44E)
        #expect(Palette.hex(.statusOffline, dark: false) == Palette.hex(.tertiary, dark: false))
    }
}

@Suite struct MotionTests {
    @Test func nothingIsSlowAndTheCurveNeverOvershoots() {
        for d in [Motion.quick, Motion.standard, Motion.flight] { #expect(d <= Motion.longest) }
        let c = Motion.standardCurve
        #expect((0...1).contains(c.y1) && (0...1).contains(c.y2))        // a y outside 0...1 is an overshoot
        #expect(Motion.zoomGlide(columnsChanged: 1) < Motion.zoomGlide(columnsChanged: 3))
        #expect(Motion.zoomGlide(columnsChanged: 40) <= Motion.longest)
    }

    @Test func theBounceIsSubtleAndReduceMotionRemovesIt() {
        #expect(Motion.bounce >= 0.1 && Motion.bounce <= 0.2)
        #expect(Motion.bounce(reduceMotion: false) == Motion.bounce)
        #expect(Motion.bounce(reduceMotion: true) == 0)
    }

    @Test func pressAndEntrancesStaySmall() {
        #expect(Motion.pressScale >= 0.94 && Motion.pressScale < 1)
        #expect(Motion.iconPressScale >= 0.8 && Motion.iconPressScale < Motion.pressScale)
        #expect(Motion.overlayScale >= 0.9 && Motion.overlayScale < 1)
        #expect(Motion.overlayDrop <= 8 && Motion.emptyRise <= 8 && Motion.toastRise <= 16 && Motion.spring <= 0.4)
    }

    @Test func everyPressTargetShrinksALittle() {
        let targets: [GrailsPressTarget] = [.label, .row, .tile, .icon, .symbol]
        for t in targets { #expect(t.scale >= Motion.iconPressScale && t.scale < 1, "\(t)") }
        #expect(GrailsPressTarget.row.scale > GrailsPressTarget.label.scale)
        #expect(GrailsPressTarget.tile.scale > GrailsPressTarget.label.scale && GrailsPressTarget.tile.scale < GrailsPressTarget.row.scale)
        #expect(Motion.chipScale > 0.5 && Motion.chipScale < Motion.overlayScale)
        #expect(Motion.revealDrop <= Motion.overlayDrop)
    }

    @Test func coreAnimationSpringMatchesTheSwiftUISpring() {
        // SwiftUI's .spring(duration:bounce:) is unit mass with stiffness (2π/d)² and damping 4π(1−bounce)/d
        let omega = 2 * Double.pi / Motion.spring
        #expect(abs(Motion.springStiffness() - omega * omega) < 1e-9)
        #expect(abs(Motion.springDamping(reduceMotion: false) - 2 * omega * (1 - Motion.bounce)) < 1e-9)
        // Reduce Motion: critically damped, no overshoot
        #expect(abs(Motion.springDamping(reduceMotion: true) - 2 * omega) < 1e-9)
    }

    @Test func spinnerTurnsOnTheClockAndRestsUnderReduceMotion() {
        #expect(Motion.spinnerAngle(at: 0, reduceMotion: false) == Motion.spinnerRest)
        #expect(abs(Motion.spinnerAngle(at: Motion.spinnerPeriod / 2, reduceMotion: false) - (Motion.spinnerRest + 180)) < 0.001)
        #expect(Motion.spinnerAngle(at: 12.34, reduceMotion: true) == Motion.spinnerRest)
        #expect(Motion.spinnerDelay == 0.3)
    }

    @Test func motionPreferenceOverridesTheSystem() {
        #expect(GrailsMotionPreference(stored: nil) == .system)
        #expect(GrailsMotionPreference(stored: "junk") == .system)
        for system in [false, true] {
            #expect(GrailsMotionPreference.system.reducesMotion(system: system) == system)
            #expect(GrailsMotionPreference.reduce.reducesMotion(system: system))
            #expect(!GrailsMotionPreference.full.reducesMotion(system: system))
        }
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

@Suite struct TypographyTests {
    @Test func theThreeFacesAreDistinct() {
        #expect(Typography.displayName != Typography.bodyName && Typography.bodyName != Typography.bodyBoldName)
    }
}
