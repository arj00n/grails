import Testing
@testable import GrailsDesign

@Suite struct ToastPlacementTests {
    @Test func everyToastSitsCentredAboveTheWindowsBottomEdge() {
        for (width, height) in [(900.0, 600.0), (1440.0, 900.0), (720.0, 480.0)] {
            for size in [(width: 180.0, height: 34.0), (width: 420.0, height: 52.0)] {
                let f = ToastPlacement.frame(windowWidth: width, windowHeight: height, size: size)
                #expect(abs((f.x + f.width / 2) - width / 2) < 0.001)
                #expect(abs((f.y + f.height) - (height - ToastPlacement.bottomInset)) < 0.001)
            }
        }
    }

    @Test func thePlacementIsOnTheSpacingScale() {
        #expect(Space.scale.contains(ToastPlacement.bottomInset))
        #expect(Space.scale.contains(ToastPlacement.stackSpacing))
    }

    @Test func aToastWiderThanTheWindowIsClampedNotShifted() {
        let f = ToastPlacement.frame(windowWidth: 300, windowHeight: 400, size: (width: 420, height: 40))
        #expect(f.x == 0)
        #expect(f.width == 300)
    }
}
