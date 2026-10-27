import Testing
@testable import GrailsDesign

/// The ink band follows the window: every size maps to a grid of square cells that covers it, with no cell stretched.
@Suite struct DitherBandTests {
    @Test func gridCoversEverySizeWithSquareCells() {
        for width in stride(from: 300.0, through: 3200, by: 0.5) {
            for height in [48.0, 240, 241.5] {
                let g = DitherBand.grid(width: width, height: height)
                let drawnW = Double(g.columns) * DitherBand.cell, drawnH = Double(g.rows) * DitherBand.cell
                #expect(drawnW >= width && drawnW - width < DitherBand.cell, "width \(width)")
                #expect(drawnH >= height && drawnH - height < DitherBand.cell, "height \(height)")
            }
        }
    }

    /// Small window to full screen: one step to the new grid, which depends on nothing but the size it is given.
    @Test func gridIsTheSizeNotItsHistory() {
        let small = DitherBand.grid(width: 520, height: 240)
        let full = DitherBand.grid(width: 1728, height: 240)
        #expect(small.columns == 130 && full.columns == 432)
        #expect(DitherBand.grid(width: 1728, height: 240) == full)
        #expect(DitherBand.grid(width: 10, height: 10) == (DitherBand.minColumns, DitherBand.minRows))
    }

    /// The flames at the foot of an empty screen (and inside the wordmark): one threshold of each 64, ink only below each column's
    /// height, and a gain that fills a short band with more of the body.
    @Test func theFlamesRiseFromTheFloor() {
        #expect(Set(DitherBand.bayer).count == 64 && DitherBand.bayer.allSatisfy { $0 > 0 && $0 < 1 })
        let rows = 60
        func ink(_ y: Int, gain: Float = 1) -> Float { (0..<320).map { DitherBand.flame(x: $0, y: y, rows: rows, phase: 0.35, gain: gain) }.reduce(0, +) }
        #expect(ink(0) == 0)                                  // no column reaches the top
        #expect(ink(rows - 1) > ink(rows / 2) && ink(rows / 2) > 0)
        #expect(ink(rows / 2, gain: 2) > ink(rows / 2))
        #expect((0..<rows).allSatisfy { y in (0..<320).allSatisfy { let v = DitherBand.flame(x: $0, y: y, rows: rows, phase: 0.7); return v >= 0 && v <= 0.94 } })
    }
}
