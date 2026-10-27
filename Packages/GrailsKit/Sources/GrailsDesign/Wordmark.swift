import CoreGraphics
import SwiftUI

/// The Grails wordmark on the title plate: pixel letters in solid text ink, with dithered flames inside them in the colours of the
/// painting behind. The flames are a smooth field of rising noise (`heat`), printed through the wall's ordered dither (`Dither`) at
/// one device pixel, finer than the letter cells; the letter edges stay on the cells. They rise from the foot of the letters and are
/// gone by the top third, which stays plain ink. When the wall turns into the next painting each flame pixel takes the new colours on
/// the wall's own grain (`Dither.noise`). Everything here is pure in `t`, so each part can be checked without a screen. See
/// docs/DESIGN_SYSTEM.md.
public enum Wordmark {
    /// The letters, one string per row: `#` is printed. Read off the designer's SVG, which is drawn on a 70 × 14 grid.
    public static let bitmap: [String] = [
        "..######....########........##........######....##............######..",
        ".########...#########......####.......######....##...........########.",
        "###....###..##.....###....######........##......##..........###....###",
        "##......##..##......##...###..###.......##......##..........##......##",
        "##..........##......##..###....###......##......##..........##........",
        "##..........##.....###..##......##......##......##..........###.......",
        "##...#####..#########...##......##......##......##...........#######..",
        "##...#####..########....##......##......##......##............#######.",
        "##......##..##.###......##########......##......##.................###",
        "##......##..##..###.....##########......##......##..................##",
        "##......##..##...###....##......##......##......##..........##......##",
        "###....###..##....###...##......##......##......##..........###....###",
        ".########...##.....###..##......##....######....##########...########.",
        "..######....##......##..##......##....######....##########....######..",
    ]
    public static let columns = 70, rows = 14
    /// Points per letter cell: the wall's own pixel, so the letters sit on the same grain as the painting around the plate.
    public static let cell = 3.0
    public static var size: CGSize { CGSize(width: Double(columns) * cell, height: Double(rows) * cell) }
    /// Flame pixels per letter cell at a display scale: one device pixel each (6 on a Retina screen).
    public static func sub(scale: Double) -> Int { max(Int((cell * scale).rounded()), 1) }

    private static let cells: [Bool] = bitmap.flatMap { $0.map { $0 == "#" } }
    public static func isSet(_ x: Int, _ y: Int) -> Bool { x >= 0 && x < columns && y >= 0 && y < rows && cells[y * columns + x] }

    /// The letters develop out of the plate like the first painting does, starting with the old typing (a second in).
    public static let developStart = 1.0, developDuration = 0.4

    // MARK: Flames

    /// How high the flames reach on average, as a share of the letter height, and where they are cut off for good: above `flameTop`
    /// every letter is plain ink.
    public static let flameReach = 0.55, flameTop = 0.68
    /// How fast the flames rise, in letter cells a second, and how hard the noise tears at the smooth fall-off.
    public static let flameRise = 1.4, flameTurbulence = 2.0
    /// The moment Reduce Motion holds still.
    public static let stillTime = 6.0

    /// Smooth value noise in 0...1 on a unit lattice, quintic between the lattice points (the lattice is `Dither.hash01`).
    static func valueNoise(_ x: Double, _ y: Double, _ k: Int) -> Double {
        let i = Int(x.rounded(.down)), j = Int(y.rounded(.down))
        let fx = x - Double(i), fy = y - Double(j)
        let sx = fx * fx * fx * (fx * (fx * 6 - 15) + 10), sy = fy * fy * fy * (fy * (fy * 6 - 15) + 10)
        let a = Dither.hash01(i, j, k), b = Dither.hash01(i + 1, j, k), c = Dither.hash01(i, j + 1, k), d = Dither.hash01(i + 1, j + 1, k)
        return a + (b - a) * sx + (c - a) * sy + (a - b - c + d) * sx * sy
    }

    /// How hot the fire is at `u` cells across and `v` cells up from the foot of the letters, at `t` seconds: 0 (ink) ... 1 (the core).
    /// Three octaves of noise rise through a fall-off that ends around `flameReach`; a slower noise along the word lets some tongues
    /// lick higher than others, and the whole field sways a little.
    public static func heat(u: Double, v: Double, t: Double) -> Double {
        let h = v / Double(rows)
        guard h < flameTop else { return 0 }
        let rise = flameRise * t
        let n = 0.5 * valueNoise(0.28 * u + 0.6 * sin(0.31 * t + 0.17 * v), 0.40 * (v - rise), 1)
            + 0.3 * valueNoise(0.6 * u, 0.85 * (v - rise * 1.15), 2)
            + 0.2 * valueNoise(1.25 * u, 1.7 * (v - rise * 1.3), 3)
        let reach = flameReach * (0.7 + 0.6 * valueNoise(0.09 * u, 0.12 * t, 4))
        let cap = min(max((flameTop - h) / 0.14, 0), 1)
        let f = ((1 - h / reach) + (n - 0.5) * flameTurbulence) * cap * cap * (3 - 2 * cap)
        return min(max(f, 0), 1)
    }

    // MARK: Inks

    /// Three printed colours (RGBA packed like `PaintingWall.litColours`): `ink` is the letters, `tip` and `core` the flames, the tip
    /// nearer the ink in lightness and the core furthest from it.
    public struct Inks: Equatable, Sendable {
        public var ink: UInt32
        public var tip: UInt32
        public var core: UInt32
        public init(ink: UInt32, tip: UInt32, core: UInt32) { self.ink = ink; self.tip = tip; self.core = core }
    }

    /// The least the letters and the flames may contrast with the plate: the ink reads like text, the flames like a large graphic.
    public static let inkContrast = 4.5, flameContrast = 3.0
    /// How far (as contrast ratios) the core stands from the ink, the tip from the ink, and the tip from the core, so the fire reads
    /// inside the letters.
    public static let coreSeparation = 2.0, tipSeparation = 1.6, flameSeparation = 1.3
    /// How saturated a core must be to count as coloured.
    public static let colouredCore = 0.35

    /// Picks the flames from a painting's palette, printed the way the wall prints them in this appearance, each pushed toward the ink
    /// until it clears `flameContrast` on the plate. `core` is the coloured one furthest from the ink (at least `coreSeparation`), so
    /// the fire is as bright as the plate allows; `tip` the
    /// most saturated of those between the core and the ink, `tipSeparation` from the ink and `flameSeparation` from the core. `ink` is the text token, given as `0xRRGGBB` like the plate.
    public static func inks(palette: [String], dark: Bool, plate: UInt32, ink: UInt32) -> Inks {
        let ground = rgb(hex: plate), letter = rgb(hex: ink)
        let printed = PaintingWall.litColours(palette: palette, dark: dark).map { lift(rgb(word: $0), from: ground, to: flameContrast, dark: dark) }
        func sat(_ c: RGB) -> Double { PaintingWall.saturation(c.r, c.g, c.b) }
        func away(_ c: RGB) -> Double { contrast(c, letter) }
        let hot = printed.filter { away($0) >= coreSeparation }, pool = hot.isEmpty ? printed : hot
        let coloured = pool.filter { sat($0) >= colouredCore }
        var core = (coloured.isEmpty ? pool : coloured).max { away($0) < away($1) } ?? mix(ground, letter, 0.5)
        // a palette with nothing apart from the ink: move the core toward the plate as far as it can go and still read
        for _ in 0..<20 where away(core) < coreSeparation {
            let next = mix(core, ground, 0.15)
            if contrast(next, ground) < flameContrast { break }
            core = next
        }
        let between = printed.filter { away($0) >= tipSeparation && away($0) < away(core) && contrast($0, core) >= flameSeparation }
        let tip = between.max { (sat($0), away($0)) < (sat($1), away($1)) } ?? mix(core, letter, 0.35)
        return Inks(ink: word(rgb: letter), tip: word(rgb: tip), core: word(rgb: core))
    }

    typealias RGB = (r: Double, g: Double, b: Double)

    static func rgb(hex: UInt32) -> RGB { (Double((hex >> 16) & 255) / 255, Double((hex >> 8) & 255) / 255, Double(hex & 255) / 255) }
    static func rgb(word: UInt32) -> RGB { (Double(word & 255) / 255, Double((word >> 8) & 255) / 255, Double((word >> 16) & 255) / 255) }
    static func word(rgb c: RGB) -> UInt32 {
        func byte(_ v: Double) -> UInt32 { UInt32(min(max(v, 0), 1) * 255 + 0.5) }
        return 0xFF00_0000 | (byte(c.b) << 16) | (byte(c.g) << 8) | byte(c.r)
    }
    static func mix(_ a: RGB, _ b: RGB, _ k: Double) -> RGB { (a.r + (b.r - a.r) * k, a.g + (b.g - a.g) * k, a.b + (b.b - a.b) * k) }

    /// WCAG relative luminance and contrast ratio.
    static func luminance(_ c: RGB) -> Double {
        func linear(_ v: Double) -> Double { v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
        return 0.2126 * linear(c.r) + 0.7152 * linear(c.g) + 0.0722 * linear(c.b)
    }

    public static func contrast(_ a: UInt32, plate: UInt32) -> Double { contrast(rgb(word: a), rgb(hex: plate)) }
    public static func contrast(_ a: UInt32, _ b: UInt32) -> Double { contrast(rgb(word: a), rgb(word: b)) }
    static func contrast(_ a: RGB, _ b: RGB) -> Double {
        let x = luminance(a), y = luminance(b)
        return (max(x, y) + 0.05) / (min(x, y) + 0.05)
    }

    private static func lift(_ c: RGB, from ground: RGB, to bar: Double, dark: Bool) -> RGB {
        var c = c
        let end: Double = dark ? 1 : 0
        for _ in 0..<20 where contrast(c, ground) < bar {
            c = (c.r + (end - c.r) * 0.15, c.g + (end - c.g) * 0.15, c.b + (end - c.b) * 0.15)
        }
        return c
    }

    // MARK: Pixels

    /// How far the letters have developed at `t`, 0...1.
    public static func develop(t: Double) -> Double { PaintingWall.ease((t - developStart) / developDuration) }

    /// One frame, `columns × sub` by `rows × sub` RGBA words (0 off the letters). Each letter cell is `sub × sub` flame pixels: the heat
    /// there, dithered into ink, tip and core. `from` is the painting leaving while the wall turns (`e` its eased progress), nil while
    /// it holds. With Reduce Motion the flames hold still at `stillTime`.
    public static func pixels(t: Double, sub: Int, inks to: Inks, from: Inks? = nil, e: Double = 1, develop: Double = 1, reduceMotion: Bool) -> [UInt32] {
        let time = reduceMotion ? stillTime : t, width = columns * sub, s = Double(sub)
        var out = [UInt32](repeating: 0, count: width * rows * sub)
        for cy in 0..<rows {
            for cx in 0..<columns where cells[cy * columns + cx] {
                if develop < 1, !Dither.lit(ink: develop, x: cx, y: cy) { continue }
                for py in cy * sub..<(cy + 1) * sub {
                    let v = Double(rows) - (Double(py) + 0.5) / s
                    for px in cx * sub..<(cx + 1) * sub {
                        let inks = from == nil || e >= 1 || Dither.noise(px, py) < e ? to : from!
                        let f = heat(u: (Double(px) + 0.5) / s, v: v, t: time)
                        let level = f > 0 ? min(Int(f * 2 + Dither.bayer(px, py) * 0.92 + 0.04), 2) : 0
                        out[py * width + px] = level == 0 ? inks.ink : level == 1 ? inks.tip : inks.core
                    }
                }
            }
        }
        return out
    }

    public static func image(_ pixels: [UInt32], sub: Int) -> CGImage? {
        let width = columns * sub, height = rows * sub
        guard pixels.count == width * height else { return nil }
        let data = pixels.withUnsafeBufferPointer { Data(buffer: $0) }
        return CGDataProvider(data: data as CFData).flatMap {
            CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                    bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue), provider: $0, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
        }
    }
}

/// The wordmark as a view: `Wordmark.size`, one flame pixel per device pixel, nearest-neighbour, named "Grails". `palette` is the
/// painting showing; `from` the one leaving while the wall turns (`progress` 0...1, eased here like the wall). With Reduce Motion the
/// flames hold still, and a change of painting crossfades quickly instead of turning grain by grain.
public struct GrailsWordmark: View {
    var t: Double
    var palette: [String]
    var from: [String]?
    var progress: Double?
    var develop: Double
    var reduceMotion: Bool
    @Environment(\.colorScheme) private var scheme
    @Environment(\.displayScale) private var scale

    public init(t: Double, palette: [String], from: [String]? = nil, progress: Double? = nil, develop: Double = 1, reduceMotion: Bool) {
        self.t = t; self.palette = palette; self.from = from; self.progress = progress; self.develop = develop; self.reduceMotion = reduceMotion
    }

    public var body: some View {
        let dark = scheme == .dark
        let plate = Palette.hex(.canvas, dark: dark), ink = Palette.hex(.text, dark: dark)
        let to = Wordmark.inks(palette: palette, dark: dark, plate: plate, ink: ink)
        let leaving = reduceMotion ? nil : from.map { Wordmark.inks(palette: $0, dark: dark, plate: plate, ink: ink) }
        let sub = Wordmark.sub(scale: scale)
        let pixels = Wordmark.pixels(t: t, sub: sub, inks: to, from: leaving, e: progress.map(PaintingWall.ease) ?? 1, develop: develop, reduceMotion: reduceMotion)
        ZStack {
            if let image = Wordmark.image(pixels, sub: sub) {
                Image(decorative: image, scale: 1).interpolation(.none).resizable()
                    .id(reduceMotion ? palette : [])
                    .transition(.opacity)
            }
        }
        .frame(width: Wordmark.size.width, height: Wordmark.size.height)
        .animation(reduceMotion ? .grailsQuick : nil, value: palette)
        .accessibilityElement()
        .accessibilityLabel("Grails")
        .accessibilityAddTraits(.isHeader)
    }
}
