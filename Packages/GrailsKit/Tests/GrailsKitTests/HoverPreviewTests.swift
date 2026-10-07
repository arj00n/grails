import Foundation
import Testing
@testable import GrailsKit

@Suite struct HoverPreviewTests {
    typealias Dwell = HoverDwell<String>

    // MARK: Dwell

    @Test func restingForTheDwellStartsAndNotBefore() {
        var d = Dwell()
        #expect(d.pointer(over: "a", at: 10) == nil)
        #expect(d.deadline == 10.25)
        #expect(d.tick(at: 10.1) == nil)
        #expect(d.tick(at: 10.249) == nil)
        #expect(d.tick(at: 10.25) == .start("a"))
        #expect(d.playing == "a")
        #expect(d.tick(at: 11) == nil)                     // one start only
    }

    @Test func movingWithinTheSameTileKeepsItsClock() {
        var d = Dwell()
        _ = d.pointer(over: "a", at: 0)
        _ = d.pointer(over: "a", at: 0.2)
        #expect(d.tick(at: 0.25) == .start("a"))
        #expect(d.pointer(over: "a", at: 0.4) == nil)        // still playing
        #expect(d.playing == "a")
    }

    @Test func passingOverATileNeverStartsIt() {
        var d = Dwell()
        _ = d.pointer(over: "a", at: 0)
        _ = d.pointer(over: nil, at: 0.1)
        #expect(d.tick(at: 1) == nil)
        _ = d.pointer(over: "a", at: 2)
        _ = d.pointer(over: "b", at: 2.2)                    // a's clock is dropped, b's starts
        #expect(d.tick(at: 2.3) == nil)
        #expect(d.tick(at: 2.45) == .start("b"))
    }

    @Test func leavingStopsAtOnce() {
        var d = Dwell()
        _ = d.pointer(over: "a", at: 0)
        _ = d.tick(at: 0.3)
        #expect(d.pointer(over: nil, at: 1) == .stop("a"))
        #expect(d.phase == .idle)
    }

    @Test func anotherTileTakesOverAfterItsOwnDwell() {
        var d = Dwell()
        _ = d.pointer(over: "a", at: 0)
        _ = d.tick(at: 0.3)
        #expect(d.pointer(over: "b", at: 1) == .stop("a"))   // a stops the moment the pointer leaves it
        #expect(d.playing == nil)
        #expect(d.tick(at: 1.1) == nil)
        #expect(d.tick(at: 1.25) == .start("b"))
    }

    // MARK: Cancels

    @Test func scrollingStopsAndIgnoresMovesUntilQuiet() {
        var d = Dwell()
        _ = d.pointer(over: "a", at: 0)
        _ = d.tick(at: 0.3)
        #expect(d.cancel(.scroll, at: 1) == .stop("a"))
        #expect(d.cancel(.scroll, at: 1.05) == nil)          // momentum: nothing more to stop
        _ = d.pointer(over: "b", at: 1.1)                    // too soon after the last scroll event
        #expect(d.deadline == nil)
        #expect(d.tick(at: 2) == nil)
        _ = d.pointer(over: "b", at: 1.25)                   // quiet now
        #expect(d.tick(at: 1.5) == .start("b"))
    }

    @Test func scrollWhileWaitingDropsTheWait() {
        var d = Dwell()
        _ = d.pointer(over: "a", at: 0)
        #expect(d.cancel(.scroll, at: 0.1) == nil)
        #expect(d.tick(at: 1) == nil)
    }

    @Test func pressingStopsUntilTheButtonComesUp() {
        var d = Dwell()
        _ = d.pointer(over: "a", at: 0)
        _ = d.tick(at: 0.3)
        #expect(d.cancel(.press, at: 1) == .stop("a"))
        _ = d.pointer(over: "a", at: 1.5)                    // a drag or marquee: never arms
        #expect(d.tick(at: 3) == nil)
        d.released()
        _ = d.pointer(over: "a", at: 4)
        #expect(d.tick(at: 4.25) == .start("a"))
    }

    @Test func otherCancelsStopWithoutAQuietPeriod() {
        var d = Dwell()
        _ = d.pointer(over: "a", at: 0)
        _ = d.tick(at: 0.3)
        #expect(d.cancel(.other, at: 1) == .stop("a"))       // window resigned key, app inactive, reduce motion…
        _ = d.pointer(over: "a", at: 1.01)
        #expect(d.tick(at: 1.26) == .start("a"))
    }

    @Test func abandonGoesIdleWithoutAStop() {
        var d = Dwell()
        _ = d.pointer(over: "a", at: 0)
        #expect(d.tick(at: 0.3) == .start("a"))
        d.abandon("a")
        #expect(d.phase == .idle)
        #expect(d.pointer(over: nil, at: 1) == nil)
    }

    // MARK: Gate

    @Test func onlyLocalVideosWithinTheCapPlay() {
        var asked = 0
        func gate(_ kind: ItemKind = .video, enabled: Bool = true, reduceMotion: Bool = false, w: Int? = 1920, h: Int? = 1080,
                  file a: FileAvailability? = .local) -> HoverPreview.Skip? {
            HoverPreview.gate(kind: kind, enabled: enabled, reduceMotion: reduceMotion, width: w, height: h, availability: { asked += 1; return a })
        }
        #expect(gate() == nil)
        #expect(gate(w: nil, h: nil) == nil)                   // size unknown: still plays
        #expect(gate(file: .cloudOnly) == .cloudOnly)
        #expect(gate(file: nil) == .missing)
        asked = 0
        #expect(gate(.image) == .notVideo)
        #expect(gate(.gif) == .notVideo)
        #expect(gate(enabled: false) == .disabled)
        #expect(gate(reduceMotion: true) == .reduceMotion)
        #expect(gate(w: 7680, h: 4320) == .tooLarge)
        #expect(asked == 0)                                    // the filesystem is only asked about videos that could play
        #expect(gate(w: 3840, h: 2160) == nil)
    }

    @Test func posterTimeMatchesTheThumbnailFrame() {
        #expect(HoverPreview.posterTime(duration: 0) == 0)
        #expect(HoverPreview.posterTime(duration: .nan) == 0)
        #expect(abs(HoverPreview.posterTime(duration: 3) - 0.6) < 1e-9)
        #expect(HoverPreview.posterTime(duration: 60) == 1.0)
    }

    @Test func sampleTimesSpreadThroughTheClip() {
        #expect(HoverPreview.sampleTimes(duration: 0) == [0])
        #expect(HoverPreview.sampleTimes(duration: 0.2, count: 3) == [HoverPreview.posterTime(duration: 0.2)])
        let times = HoverPreview.sampleTimes(duration: 10, count: 3)
        #expect(times.count == 3)
        #expect(times[0] < times[1] && times[1] < times[2])
        #expect(times[0] >= 0.4 && times[2] <= 9.6)
    }

    @Test func fadesStayWithinTheMotionBudget() {
        #expect(HoverPreview.fadeIn <= 0.12)
        #expect(HoverPreview.fadeOut <= 0.12)
        #expect(abs(HoverPreview.dwell - 0.25) < 1e-9)
    }
}
