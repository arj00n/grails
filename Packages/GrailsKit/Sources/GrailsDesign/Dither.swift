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
