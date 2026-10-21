import CoreGraphics
import Testing
@testable import GrailsDesign

@Suite struct PreviewFlightTests {
    // A 1440 pt window: the stage is what is left of it beside the 300 pt details column and its hairline.
    let stage = CGRect(x: 0, y: 0, width: 1440 - 301, height: 900)
    let page = CGRect(x: 200, y: 100, width: 739, height: 700)
    let image = CGSize(width: 1000, height: 1000)

    @Test func aTileUnderTheDetailsColumnIsFlownToWhereItIs() {
        let tile = CGRect(x: 1250, y: 400, width: 160, height: 160)
        let landing = PreviewFlight.frame(tile: tile, page: page, image: image, progress: 0)
        #expect(landing == tile)                              // not clamped into the stage, not dropped
        #expect(landing.minX > stage.maxX)                    // entirely outside the stage's own bounds
        #expect(!PreviewFlight.clipsStage(inFlight: true))    // so the stage must not clip while it flies
        #expect(PreviewFlight.clipsStage(inFlight: false))    // and clips again once it has landed
        #expect(PreviewFlight.frame(tile: tile, page: page, image: image, progress: 1) == page)
    }

    @Test func thePictureSitsWholeInsideItsTile() {
        let tile = CGRect(x: 1250, y: 400, width: 160, height: 120)
        let r = PreviewFlight.tileFrame(tile: tile, image: CGSize(width: 400, height: 200))
        #expect(r == CGRect(x: 1250, y: 420, width: 160, height: 80))
    }

    @Test func theFlightRidesTheSharedSpringAndItsFadesNeverBounce() {
        for (from, to) in [(1.0, 0.0), (0.0, 1.0)] {
            var spring = SharedSpring(value: from, target: to, reduceMotion: false)
            var fade = from, fades: [Double] = [], overshoot = 0.0, time = 0.0
            while !spring.isSettled, time < 2 {
                spring.step(1.0 / 60); time += 1.0 / 60
                overshoot = max(overshoot, to == 0 ? -spring.value : spring.value - 1)
                fade = PreviewFlight.fade(previous: fade, flight: spring.value, target: to)
                fades.append(fade)
            }
            #expect(spring.value == to)
            #expect(time < Motion.spring * 2)
            #expect(overshoot > 0.005)                          // the picture settles with the shared bounce
            let monotone = zip(fades, fades.dropFirst()).allSatisfy { to == 0 ? $1 <= $0 : $1 >= $0 }
            #expect(monotone)                                   // the wash and the column do not
            #expect(fades.allSatisfy { (0...1).contains($0) })
        }
    }

    @Test func reduceMotionTakesTheBounceAway() {
        var spring = SharedSpring(value: 1, target: 0, reduceMotion: true)
        var lowest = 1.0
        for _ in 0..<120 { spring.step(1.0 / 60); lowest = min(lowest, spring.value) }
        #expect(lowest >= -0.0001)
        #expect(spring.value == 0)
    }
}
