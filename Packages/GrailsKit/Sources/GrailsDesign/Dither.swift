import Foundation

/// Ordered dither: a fixed 8×8 threshold map. A pixel is lit where its ink beats the threshold at its position, so a flat tone prints
/// as an even pattern of dots.
public enum Dither {
    /// Dispersed-dot Bayer, thresholds spread evenly over (0, 1). Bits are read least significant first, which spreads neighbours apart
    /// (most significant first gives clustered 16-pixel blocks).
    public static func bayer(_ x: Int, _ y: Int) -> Double {
        var m = 0
        for b in 0..<3 {
            let xb = (x >> b) & 1, yb = (y >> b) & 1
            m = (m << 2) | ((xb ^ yb) << 1) | yb
        }
        return (Double(m) + 0.5) / 64
    }

    /// 0..<1, the same for the same inputs: re-rolled by `k` (the seam at a wave's front uses it).
    public static func hash01(_ x: Int, _ y: Int, _ k: Int) -> Double {
        var h = UInt32(truncatingIfNeeded: x &* 73_856_093) ^ UInt32(truncatingIfNeeded: y &* 19_349_663) ^ UInt32(truncatingIfNeeded: k &* 83_492_791)
        h = (h ^ (h >> 13)) &* 1_274_126_177
        return Double((h ^ (h >> 16)) & 0xFFFF) / 65_535
    }

    /// Fixed, even-looking noise in 0..<1 per pixel (interleaved gradient noise): a pixel adopts the next painting's colour once a
    /// transition passes its value, so colours cross over grain by grain with no pattern.
    public static func noise(_ x: Int, _ y: Int) -> Double {
        let f = 0.06711056 * Double(x) + 0.00583715 * Double(y)
        let v = 52.9829189 * (f - f.rounded(.down))
        return v - v.rounded(.down)
    }

    /// Whether a pixel with `ink` (0...1) is lit at (x, y). Ink under 0.04 is never lit and over 0.96 always is.
    public static func lit(ink: Double, x: Int, y: Int) -> Bool { ink > bayer(x, y) * 0.92 + 0.04 }
}

/// A dithered band drawn as a bitmap of square cells, such as the ink at the foot of an empty screen. The grid is recomputed in the
/// same layout pass as the size, never on a delay, so the band follows a window resize frame by frame like the rest of the layout.
public enum DitherBand {
    /// Points per dither cell.
    public static let cell = 4.0
    public static let minColumns = 24
    public static let minRows = 12

    /// Whole cells that cover a `width` × `height` band. The bitmap is placed at `columns × cell` by `rows × cell` from the bottom
    /// left and clipped by the band, so a cell is always square: it never stretches to fill a size between two grid steps.
    public static func grid(width: Double, height: Double) -> (columns: Int, rows: Int) {
        (max(Int((width / cell).rounded(.up)), minColumns), max(Int((height / cell).rounded(.up)), minRows))
    }

    /// The band's threshold map: the classic recursive 8×8 Bayer, row-major, thresholds over (0, 1).
    public static let bayer: [Float] = {
        var m: [[Int]] = [[0]]
        while m.count < 8 {
            let k = m.count
            var next = Array(repeating: Array(repeating: 0, count: k * 2), count: k * 2)
            for y in 0..<(k * 2) { for x in 0..<(k * 2) {
                let base = m[y % k][x % k] * 4
                next[y][x] = base + [0, 2, 3, 1][(y < k ? 0 : 2) + (x < k ? 0 : 1)]
            } }
            m = next
        }
        return (0..<64).map { (Float(m[$0 / 8][$0 % 8]) + 0.5) / 64 }
    }()

    /// The flames at the foot of an empty screen, as ink 0...1 at column `x` and row `y` (0 at the top) of a band `rows` tall, `phase`
    /// 0..<1 around the loop. Each column is a flame of its own height; the licks scroll up and the whole thing repeats. A `gain` above
    /// 1 fills a short band (the wordmark's) with more of the body; the empty-screen band uses 1.
    public static func flame(x: Int, y: Int, rows: Int, phase: Float, gain: Float = 1) -> Float {
        let turn = phase * 2 * Float.pi
        let floor = Float(y) / Float(rows - 1)
        let xF = Float(x)
        let height = 0.38 + 0.62 * max(0, sin(xF * 0.09 + turn) * sin(xF * 0.041 + 1.6))
        let along = (1 - floor) / height
        var density: Float = 0
        if along < 1 {
            let body = 1 - along
            let lick = 0.5 + 0.5 * sin(Float(y) * 0.45 + turn * 2 + xF * 0.13)
            density = (gain == 1 ? body * body : pow(body, 2 / gain) * gain) * (0.42 + 0.58 * lick)
            density *= 0.72 + 0.28 * sin(turn * 3 + xF * 0.2)
        }
        density = min(max(density, 0), 1)
        return density * density * (3 - 2 * density) * 0.94
    }
}
