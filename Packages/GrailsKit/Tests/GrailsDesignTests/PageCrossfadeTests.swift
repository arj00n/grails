import QuartzCore
import Testing
@testable import GrailsDesign

/// A page switch is one crossfade of the content area on the standard fade, and nothing at all under Reduce Motion.
@Suite struct PageCrossfadeTests {
    @Test func aPageSwitchIsOneStandardFade() throws {
        let fade = try #require(PageCrossfade.transition(reduceMotion: false))
        #expect(fade.type == .fade)
        #expect(fade.subtype == nil)                                  // a fade, not a push or a slide
        #expect(fade.duration == Motion.standard)
        #expect(fade.duration <= Motion.longest)
        #expect(fade.beginTime == 0)                                  // nothing waits its turn
        let curve = try #require(fade.timingFunction)
        var p1: [Float] = [0, 0], p2: [Float] = [0, 0]
        curve.getControlPoint(at: 1, values: &p1)
        curve.getControlPoint(at: 2, values: &p2)
        #expect(p1 == [Float(Motion.standardCurve.x1), Float(Motion.standardCurve.y1)])
        #expect(p2 == [Float(Motion.standardCurve.x2), Float(Motion.standardCurve.y2)])
        // ease-out with no overshoot: a fade never bounces
        #expect((0...1).contains(p1[1]) && (0...1).contains(p2[1]))
    }

    @Test func reduceMotionSwapsAtOnce() {
        #expect(PageCrossfade.transition(reduceMotion: true) == nil)
    }
}
