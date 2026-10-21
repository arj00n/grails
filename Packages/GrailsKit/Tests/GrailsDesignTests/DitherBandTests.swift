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
}
