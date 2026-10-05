import CoreGraphics
import Foundation

/// The paintings behind Hello, as square ordered-dither pixels coloured from the picture. Everything here is pure: placement, tone,
/// the per-pixel grid, the transition wave, the schedule and the pointer's loupe, so each can be checked without a screen.
/// Spec: docs/ONBOARDING_PAINTINGS.md.
public enum PaintingWall {
    // MARK: Manifest (written by Scripts/gen-paintings.py)

    public struct Placement: Codable, Sendable, Equatable {
        public enum Mode: String, Codable, Sendable { case cover, side }
        public var mode: Mode
        /// The point of the picture (0...1 each way) that lands on `anchor` (0...1 of the window).
        public var focal: [Double]
        public var anchor: [Double]
        public var zoom: Double
        public init(mode: Mode, focal: [Double] = [0.5, 0.5], anchor: [Double] = [0.5, 0.5], zoom: Double = 1) {
            self.mode = mode; self.focal = focal; self.anchor = anchor; self.zoom = zoom
        }
    }

    public struct Spec: Codable, Sendable, Equatable, Identifiable {
        public var id: String
        public var file: String
        public var artist: String
        public var title: String
        public var year: String
        /// One line on the title plate: surname and year.
        public var caption: String
        public var width: Int
        public var height: Int
        public var placement: Placement
        public var gamma: Double
        /// Luma and saturation levels measured on the picture, so a flat painting uses the whole range.
        public var lo: Double, hi: Double, satLo: Double, satHi: Double
        /// Sixteen colours as `#rrggbb`, dark to light.
        public var palette: [String]
    }

    public struct Manifest: Codable, Sendable, Equatable {
        public var version: Int
        public var pixel: Int
        public var paintings: [Spec]
    }

    // MARK: Constants

    public static let pixel = 3
    /// The plate behind the title, Start and caption.
    public static let plateSize = CGSize(width: 304, height: 148)
    public static let feather = 48.0
    public static let period = 8.0
    public static let waveDuration = 1.6
    public static let introStart = 0.1, introDuration = 0.9
    public static let waveWidth = 0.10
    public static let seamHz = 15.0
    public static let loupeRadius = 72.0, loupeDecay = 0.45, loupeLife = 0.75

    // MARK: Placement

    /// Where the picture lands in a window of `window` points. `cover` fills the window; `side` fits the full height and sits at its anchor.
    public static func frame(_ spec: Spec, window: CGSize) -> CGRect {
        let p = spec.placement
        let w = Double(spec.width), h = Double(spec.height)
        guard w > 0, h > 0, window.width > 0, window.height > 0 else { return .zero }
        let W = Double(window.width), H = Double(window.height)
        let scale = p.zoom * (p.mode == .cover ? max(W / w, H / h) : H / h)
        let sw = w * scale, sh = h * scale
        var ox = p.anchor[0] * W - p.focal[0] * sw, oy = p.anchor[1] * H - p.focal[1] * sh
        if p.mode == .cover { ox = min(max(ox, W - sw), 0) }
        oy = min(max(oy, H - sh), 0)
        return CGRect(x: ox, y: oy, width: sw, height: sh)
    }

    /// 1 inside the picture, easing to 0 over `feather` points at the left and right edges of a `side` picture (cover pictures have no edge).
    public static func coverage(_ spec: Spec, frame: CGRect, x: Double) -> Double {
        guard spec.placement.mode == .side else { return 1 }
        let t = min(max(min(x - Double(frame.minX), Double(frame.maxX) - x) / feather, 0), 1)
        return t * t * (3 - 2 * t)
    }

    /// The title plate: centred, four points above the middle, snapped outwards to the pixel grid.
    public static func plate(window: CGSize, pixel: Int = PaintingWall.pixel) -> CGRect {
        let px = Double(pixel)
        let x0 = ((Double(window.width) - Double(plateSize.width)) / 2 / px).rounded(.down) * px
        let y0 = ((Double(window.height) - Double(plateSize.height)) / 2 / px - 4 / px).rounded(.down) * px
        let x1 = ((x0 + Double(plateSize.width)) / px).rounded(.up) * px, y1 = ((y0 + Double(plateSize.height)) / px).rounded(.up) * px
        return CGRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
    }

    // MARK: Tone

    /// Brightness of the ink for a pixel: dark mode prints light as ink (bright on black), light mode prints shadow as ink (like a print).
    /// Saturated colour counts as light in dark mode and as ink in light mode, so isoluminant suns still show.
    public static func ink(luma l: Double, sat s: Double, dark: Bool) -> Double {
        let v = dark ? l + 0.5 * s * (1 - l) : max(1 - l, 0.5 * s)
        return min(max((v - 0.06) / 0.94, 0), 1)
    }

    static func luma(_ r: Double, _ g: Double, _ b: Double) -> Double { 0.2126 * r + 0.7152 * g + 0.0722 * b }

    static func saturation(_ r: Double, _ g: Double, _ b: Double) -> Double {
        let mx = max(r, g, b), mn = min(r, g, b)
        return (mx - mn) / max(mx, 0.04) * min(max(mx * 3, 0), 1)
    }

    /// `#rrggbb` as 0...1 components.
    public static func parse(hex: String) -> (r: Double, g: Double, b: Double) {
        let s = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        let v = UInt32(s, radix: 16) ?? 0
        return (Double((v >> 16) & 255) / 255, Double((v >> 8) & 255) / 255, Double(v & 255) / 255)
    }

    /// The colour a lit pixel is printed in, as RGBA bytes packed little-endian (R in the low byte). Dark: the palette colour at full
    /// brightness (the dither carries brightness). Light: a deepened ink.
    public static func litColours(palette: [String], dark: Bool) -> [UInt32] {
        palette.map { hex in
            let c = parse(hex: hex)
            let m = max(max(c.r, c.g, c.b), 0.04)
            func channel(_ v: Double) -> Double {
                let boosted = min(max(m - (m - v) * 1.1, 0), 1)
                return dark ? min(boosted / m, 1) : pow(boosted, 1.5)
            }
            let r = UInt32(channel(c.r) * 255 + 0.5), g = UInt32(channel(c.g) * 255 + 0.5), b = UInt32(channel(c.b) * 255 + 0.5)
            return 0xFF00_0000 | (b << 16) | (g << 8) | r
        }
    }

    // MARK: Grid

    /// A painting placed in a window and sampled into pixels: per pixel the ink for dark and for light mode, and the palette index.
    public struct Grid: Sendable, Equatable {
        public var cols: Int, rows: Int, pixel: Int
        public var inkDark: [UInt8]
        public var inkLight: [UInt8]
        public var colour: [UInt8]

        /// `rgba` is cols × rows premultiplied sRGB bytes of the placed picture, box-filtered down to `pixel` points per pixel; its alpha says
        /// how much of the pixel the picture covers. `frame` is `PaintingWall.frame` for the same window.
        public static func build(rgba: [UInt8], cols: Int, rows: Int, pixel: Int, spec: Spec, frame: CGRect) -> Grid {
            precondition(rgba.count >= cols * rows * 4)
            let pal = spec.palette.map { PaintingWall.parse(hex: $0) }
            var dark = [UInt8](repeating: 0, count: cols * rows), light = dark, idx = dark
            let span = max(spec.hi - spec.lo, 1e-3), satSpan = max(spec.satHi - spec.satLo, 1e-3)
            for y in 0..<rows {
                for x in 0..<cols {
                    let i = y * cols + x
                    let a = Double(rgba[i * 4 + 3]) / 255
                    if a < 0.002 { continue }
                    let r = min(Double(rgba[i * 4]) / 255 / a, 1), g = min(Double(rgba[i * 4 + 1]) / 255 / a, 1), b = min(Double(rgba[i * 4 + 2]) / 255 / a, 1)
                    let l = pow(min(max((PaintingWall.luma(r, g, b) - spec.lo) / span, 0), 1), spec.gamma)
                    let s = min(max((PaintingWall.saturation(r, g, b) - spec.satLo) / satSpan, 0), 1)
                    let cover = a * PaintingWall.coverage(spec, frame: frame, x: (Double(x) + 0.5) * Double(pixel))
                    dark[i] = UInt8(min(max(PaintingWall.ink(luma: l, sat: s, dark: true) * cover, 0), 1) * 255 + 0.5)
                    light[i] = UInt8(min(max(PaintingWall.ink(luma: l, sat: s, dark: false) * cover, 0), 1) * 255 + 0.5)
                    var best = 0, bestD = Double.infinity
                    for (k, c) in pal.enumerated() {
                        let d = (c.r - r) * (c.r - r) + (c.g - g) * (c.g - g) + (c.b - b) * (c.b - b)
                        if d < bestD { bestD = d; best = k }
                    }
                    idx[i] = UInt8(best)
                }
            }
            return Grid(cols: cols, rows: rows, pixel: pixel, inkDark: dark, inkLight: light, colour: idx)
        }
    }

    // MARK: Transition wave

    /// When a pixel flips during a wave, 0..<1: a diagonal from the top left, ragged by 15 % of the dither map so the front advances as dither.
    public static func tau(x: Int, y: Int, cols: Int, rows: Int) -> Double {
        let d = (Double(x) / Double(max(cols - 1, 1)) + Double(y) / Double(max(rows - 1, 1))) / 2
        return 0.85 * d + 0.15 * Dither.bayer(x, y)
    }

    public static func ease(_ p: Double) -> Double { let q = 1 - min(max(p, 0), 1); return 1 - q * q }

    /// 0 = still the old picture, 1 = the new one, with a front `waveWidth` wide.
    public static func wave(tau: Double, progress p: Double) -> Double {
        min(max((ease(p) * (1 + waveWidth) - tau) / waveWidth, 0), 1)
    }

    public struct Sample: Equatable, Sendable {
        public var ink: UInt8
        public var colour: UInt8
        public init(ink: UInt8, colour: UInt8) { self.ink = ink; self.colour = colour }
    }

    /// What a pixel shows at wave position `s`: exactly `from` at 0 and exactly `to` at 1; in between a lit seam whose thresholds are
    /// re-rolled each `tick` so it sparkles. Plate pixels are never lit: pass `ink` 0 for them.
    public static func state(x: Int, y: Int, from: Sample?, to: Sample, s: Double, tick: Int) -> (lit: Bool, colour: UInt8, toPainting: Bool) {
        if s <= 0 {
            let f = from ?? Sample(ink: 0, colour: 0)
            return (Dither.lit(ink: Double(f.ink) / 255, x: x, y: y), f.colour, false)
        }
        if s >= 1 { return (Dither.lit(ink: Double(to.ink) / 255, x: x, y: y), to.colour, true) }
        let a = Double(from?.ink ?? 0) / 255, b = Double(to.ink) / 255
        let ink = min(max(a, b) + 0.25, 1) * (b == 0 && a == 0 ? 0 : 1)
        let lit = ink > Dither.hash01(x, y, tick) * 0.92 + 0.04
        return (lit, s >= 0.5 ? to.colour : (from?.colour ?? to.colour), s >= 0.5)
    }

    // MARK: Schedule

    public struct Schedule: Equatable, Sendable {
        /// The picture on screen (or leaving, during a wave).
        public var index: Int
        public var next: Int
        /// 0...1 during a wave, nil while holding.
        public var progress: Double?
    }

    /// Every `period` seconds a `waveDuration` wave brings the next picture; the first picture develops by itself (`intro`).
    public static func schedule(t: Double, count: Int, reduceMotion: Bool) -> Schedule {
        guard count > 0, !reduceMotion, t >= 0 else { return Schedule(index: 0, next: 0, progress: nil) }
        let k = Int(t / period), phase = t - Double(k) * period
        if k >= 1, phase < waveDuration { return Schedule(index: (k - 1) % count, next: k % count, progress: phase / waveDuration) }
        return Schedule(index: k % count, next: (k + 1) % count, progress: nil)
    }

    /// How far the first picture has developed, 0...1.
    public static func intro(t: Double) -> Double { min(max((t - introStart) / introDuration, 0), 1) }

    /// The picture whose caption is shown: it changes when the wave passes the middle of the plate.
    public static func captionIndex(_ s: Schedule) -> Int {
        guard let p = s.progress else { return s.index }
        return ease(p) >= 0.5 ? s.next : s.index
    }

    // MARK: Loupe

    public struct Touch: Equatable, Sendable {
        public var x: Double, y: Double, age: Double
        public init(x: Double, y: Double, age: Double) { self.x = x; self.y = y; self.age = age }
    }

    /// 0...1: how much the pointer (and its trail) has magnified the point (x, y).
    public static func influence(x: Double, y: Double, touches: [Touch]) -> Double {
        var q = 0.0
        for t in touches where t.age <= loupeLife {
            let d = ((x - t.x) * (x - t.x) + (y - t.y) * (y - t.y)).squareRoot()
            let f = min(max(1 - d / loupeRadius, 0), 1)
            if f > 0 { q = max(q, f * f * (3 - 2 * f) * exp(-t.age / loupeDecay)) }
        }
        return q
    }

    /// Whether a finer (one point) pixel at (x, y) is drawn instead of the coarse one. The lens edge is dithered.
    public static func loupeLit(q: Double, x: Int, y: Int) -> Bool { q > Dither.bayer(x, y) * 0.6 + 0.2 }
}
