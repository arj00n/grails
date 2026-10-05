import Foundation

/// The field behind Hello: a slow drift of colour drawn as characters and dither, which the pointer stirs. Pure maths over a grid of cells,
/// so the same moment can be rebuilt anywhere and checked without a screen.
public enum AsciiField {
    /// Dark to bright. A cell's brightness picks a character; ordered dithering decides between two neighbours so gradients have texture.
    public static let ramp: [Character] = Array(" .:-=+*#%@")

    /// Where the pointer was: in cells, and how long ago (seconds). A trail of these makes the glow smear and fade.
    public struct Touch: Equatable, Sendable {
        public var col: Double, row: Double, age: Double
        public init(col: Double, row: Double, age: Double) { self.col = col; self.row = row; self.age = age }
    }

    /// Cells are about twice as tall as wide; distances use this so glows are round on screen.
    public static let cellAspect = 1.9
    /// How long a touch lasts.
    public static let touchLife = 1.6

    /// 8×8 ordered-dither thresholds, spread evenly over (0, 1).
    public static func bayer(_ col: Int, _ row: Int) -> Double {
        var x = col & 7, y = row & 7
        var m = 0
        for bit in 0..<3 {                                           // interleave the bits of x and x^y
            let xb = (x >> (2 - bit)) & 1, yb = (y >> (2 - bit)) & 1
            m = (m << 2) | ((xb ^ yb) << 1) | yb
        }
        x = 0; y = 0
        return (Double(m) + 0.5) / 64
    }

    private static func smooth(_ a: Double, _ b: Double, _ x: Double) -> Double {
        let t = min(max((x - a) / (b - a), 0), 1)
        return t * t * (3 - 2 * t)
    }

    /// How strongly the touches light a cell, 0...1.
    static func glow(col: Int, row: Int, touches: [Touch]) -> Double {
        var g = 0.0
        for t in touches where t.age < touchLife {
            let dx = Double(col) - t.col, dy = (Double(row) - t.row) * cellAspect
            let d2 = dx * dx + dy * dy
            let fade = exp(-t.age * 1.5)
            let sigma = 4.0 + t.age * 5
            g += fade * exp(-d2 / (2 * sigma * sigma))
            g += 0.22 * fade * max(0, sin(sqrt(d2) * 0.8 - t.age * 8)) * exp(-sqrt(d2) / 9)
        }
        return min(g, 1)
    }

    /// Brightness of a cell, 0...1: a calm drift of overlapping waves, lifted where the pointer has been.
    public static func value(col: Int, row: Int, t: Double, touches: [Touch] = []) -> Double {
        let x = Double(col), y = Double(row) * cellAspect
        var f = sin(x * 0.11 + t * 0.35) + sin(y * 0.13 - t * 0.27) + sin((x + y) * 0.07 + t * 0.2)
        f += sin(((x - 40) * (x - 40) + (y - 30) * (y - 30)).squareRoot() * 0.09 - t * 0.4)
        let base = pow(f / 4 * 0.5 + 0.5, 1.2) * 0.8
        return min(base + 0.85 * glow(col: col, row: row, touches: touches), 1)
    }

    /// Colour of a cell as a hue 0..<1: teal, blue and violet drifting, running to warm where the pointer has been.
    public static func hue(col: Int, row: Int, t: Double, touches: [Touch] = []) -> Double {
        let x = Double(col), y = Double(row) * cellAspect
        var h = 0.62 + 0.13 * sin(x * 0.05 + t * 0.1) + 0.13 * sin(y * 0.06 - t * 0.08)
        h -= 0.5 * glow(col: col, row: row, touches: touches)
        return h - floor(h)
    }

    /// Which character (an index into `ramp`) a cell shows: its brightness, rounded up or down by the dither.
    public static func level(value: Double, col: Int, row: Int) -> Int {
        let top = ramp.count - 1
        let x = min(max(value, 0), 1) * Double(top)
        let base = Int(x)
        return min(base + (x - Double(base) > bayer(col, row) ? 1 : 0), top)
    }

    /// 0...1: the field develops from the top left, a diagonal sweep that is over in about a second.
    public static func reveal(col: Int, row: Int, cols: Int, rows: Int, t: Double) -> Double {
        let diagonal = (Double(col) / Double(max(cols, 1)) + Double(row) / Double(max(rows, 1))) / 2
        return smooth(0, 1, (t - 0.1 - diagonal * 0.7) / 0.16)
    }
}
