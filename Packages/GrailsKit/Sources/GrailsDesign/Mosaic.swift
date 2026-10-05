import CoreGraphics
import Foundation

/// The wall of tiles behind onboarding: blank at first (the shape of an empty library), then filled with the person's own pictures.
/// Pure, seeded, and cheap, so the same wall can be rebuilt on any screen size and checked headlessly.
public enum Mosaic {
    public struct Slot: Equatable, Sendable {
        public var index: Int
        public var rect: CGRect
        /// 0, 1 or 2: which of the three greys the tile is when empty.
        public var shade: Int
        /// Position along the diagonal sweep: 0 for the top-left tile.
        public var order: Int
        public var aspect: Double { rect.height > 0 ? Double(rect.width / rect.height) : 1 }
    }

    /// Fade of one tile, and the sweep that develops them all.
    public static let tileFade = 0.16
    public static let stagger = 0.006
    public static let sweepStart = 0.12

    struct Generator {
        var state: UInt64
        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
        mutating func unit() -> Double { Double(next() >> 11) / Double(1 << 53) }
    }

    /// Masonry in columns of `column` points (8 pt gaps); aspects 2:3 30 %, 4:5 25 %, 1:1 20 %, 3:4 15 %, 16:9 10 %. At most `limit` tiles.
    public static func layout(seed: UInt64, size: CGSize, column: CGFloat = 150, gap: CGFloat = 8, limit: Int = 240) -> [Slot] {
        guard size.width > 0, size.height > 0 else { return [] }
        var g = Generator(state: seed)
        let cols = max(1, Int((size.width + gap) / (column + gap)))
        let w = (size.width - CGFloat(cols - 1) * gap) / CGFloat(cols)
        var heights = [CGFloat](repeating: 0, count: cols)
        var slots: [Slot] = []
        while slots.count < limit {
            let c = heights.indices.min { heights[$0] < heights[$1] } ?? 0
            if heights[c] > size.height { break }
            let r = g.unit()
            let aspect: Double = r < 0.30 ? 2.0 / 3 : r < 0.55 ? 4.0 / 5 : r < 0.75 ? 1 : r < 0.90 ? 3.0 / 4 : 16.0 / 9
            let h = (w / CGFloat(aspect)).rounded()
            let rect = CGRect(x: CGFloat(c) * (w + gap), y: heights[c], width: w, height: h)
            let row = Int(heights[c] / (column * 1.2))
            slots.append(Slot(index: slots.count, rect: rect, shade: Int(g.next() % 3), order: c + row))
            heights[c] += h + gap
        }
        return slots
    }

    /// How visible an empty tile is at time `t` (seconds since the screen appeared): 0 = canvas, 1 = its grey. Tiles develop along a
    /// diagonal sweep, the middle ones step back so the title can stand, and one tile changes grey every 2.4 s afterwards.
    public static func opacity(of slot: Slot, at t: Double, centre: CGRect?) -> Double {
        let start = sweepStart + Double(slot.order) * stagger
        var v = min(max((t - start) / tileFade, 0), 1)
        if let centre, slot.rect.intersects(centre) {
            let back = min(max((t - 0.9) / 0.18, 0), 1)
            v *= (1 - back)
        }
        return v
    }

    /// Which tile is "breathing" at time `t` (a different grey for a moment), or nil.
    public static func idleSlot(count: Int, seed: UInt64, at t: Double) -> Int? {
        guard count > 0, t > 1.6 else { return nil }
        let step = Int((t - 1.6) / 2.4)
        var g = Generator(state: seed &+ UInt64(step) &* 7919)
        return Int(g.next() % UInt64(count))
    }

    /// When the sweep is over: the last tile has finished fading.
    public static func sweepEnd(_ slots: [Slot]) -> Double { sweepStart + Double(slots.map(\.order).max() ?? 0) * stagger + tileFade }

    /// For a new picture: the free slot, among the next `window` free ones in sweep order, whose shape is closest to its own.
    public static func assign(aspect: Double, free: [Slot], window: Int = 12) -> Slot? {
        let candidates = free.sorted { $0.order != $1.order ? $0.order < $1.order : $0.index < $1.index }.prefix(window)
        return candidates.min { abs(log($0.aspect / max(aspect, 0.01))) < abs(log($1.aspect / max(aspect, 0.01))) }
    }

    /// Pictures may swap in at most this often, so parallel downloads never strobe the wall.
    public static func swapInterval(reduceMotion: Bool) -> Double { reduceMotion ? 0.5 : 1.0 / 6 }
}
