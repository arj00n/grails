import CoreGraphics
import Testing
@testable import GrailsKit

@Suite struct SectionPinTests {
    private let headers = [
        CGRect(x: 12, y: 12, width: 400, height: 60),
        CGRect(x: 12, y: 900, width: 400, height: 60),
        CGRect(x: 12, y: 1800, width: 400, height: 60),
    ]

    @Test func theFloatingHeaderNeverOverlapsTheNextOneWhileScrolling() {
        for step in 0...2400 {
            let top = CGFloat(step)
            guard let f = SectionPins.floating(headers, visibleTop: top) else { continue }
            let onDocument = CGRect(x: 12, y: top + f.offset, width: 400, height: 60)
            #expect(f.offset <= 0 && f.offset > -60, "header left the top edge at \(top): \(f.offset)")
            if f.index + 1 < headers.count {
                #expect(onDocument.maxY <= headers[f.index + 1].minY + 0.5, "headers overlap at \(top)")
            }
            // its own laid-out copy has scrolled above the edge, so the two never both show
            #expect(headers[f.index].minY < top)
        }
    }

    @Test func aStuckHeaderSitsExactlyOnTheTopEdge() {
        // Any scroll position inside a section, at any speed (the answer depends on the position alone).
        for top in stride(from: CGFloat(13), through: 839, by: 0.25) {
            let f = SectionPins.floating(headers, visibleTop: top)
            #expect(f?.index == 0)
            #expect(f?.offset == 0, "stuck header moved off the edge at \(top)")
        }
    }

    @Test func theNextHeaderPushesTheFloatingOneUp() {
        let f = SectionPins.floating(headers, visibleTop: 860)
        #expect(f?.index == 0)
        #expect(f.map { abs($0.offset - -20) < 0.5 } == true)   // 900 - 60 - 860, just above the next header
    }

    @Test func theOffsetIsContinuousSoThePushNeverJumps() {
        var last: (index: Int, offset: CGFloat)?
        for step in 0...24000 {
            let top = CGFloat(step) / 10
            let f = SectionPins.floating(headers, visibleTop: top)
            if let a = last, let b = f, a.index == b.index {
                #expect(abs(b.offset - a.offset) <= 0.1 + 1e-6, "jump at \(top)")
            }
            last = f
        }
    }

    @Test func noHeaderFloatsWhileTheyAreAllInPlace() {
        #expect(SectionPins.floating(headers, visibleTop: 0) == nil)
        #expect(SectionPins.floating(headers, visibleTop: 12) == nil)     // the first header is exactly at the top
        #expect(SectionPins.floating(headers, visibleTop: 900) == nil)    // the second takes over in its own place
        #expect(SectionPins.floating([], visibleTop: 500) == nil)
    }

    @Test func theLastHeaderStaysStuckToTheEnd() {
        let f = SectionPins.floating(headers, visibleTop: 50_000)
        #expect(f?.index == 2)
        #expect(f?.offset == 0)
    }
}
