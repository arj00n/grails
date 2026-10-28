import CoreGraphics
import SwiftUI

/// The Grails wordmark on the title plate: pixel letters in solid text ink, with dithered flames rising inside them in a colour of the
/// painting behind. The flames are the empty-screen band's (`DitherBand.flame`, same loop and threshold map), run in the bottom two
/// thirds of the letters at 1 pt a flame pixel, two to a letter cell; the letter edges stay on the cells and the top third is plain
/// ink. When the wall turns into the next painting each flame pixel takes the new colour on the wall's own grain (`Dither.noise`).
/// Everything here is pure in `t`, so each part can be checked without a screen. See docs/DESIGN_SYSTEM.md.
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
    /// Points per letter cell: two, so the mark sits on the plate at the button's height and stays on whole pixels.
    public static let cell = 2.0
    public static var size: CGSize { CGSize(width: Double(columns) * cell, height: Double(rows) * cell) }
    /// Flame pixels per letter cell: 1 pt each.
    public static let sub = 2

    private static let cells: [Bool] = bitmap.flatMap { $0.map { $0 == "#" } }
    public static func isSet(_ x: Int, _ y: Int) -> Bool { x >= 0 && x < columns && y >= 0 && y < rows && cells[y * columns + x] }

    /// The letters develop out of the plate like the first painting does, starting with the old typing (a second in).
    public static let developStart = 1.0, developDuration = 0.4

    // MARK: Flames

    /// The share of the letter height the flames burn in, from the foot; above it every letter is plain ink.
    public static let flameShare = 2.0 / 3
    /// How much fuller than the empty-screen band the flames burn, so a band this short still fills (`DitherBand.flame`'s gain).
    public static let flameGain: Float = 2
    /// One trip around the loop, in seconds, as on the empty screen, and where Reduce Motion holds it.
    public static let loop = 8.0, stillPhase: Float = 0.35

    /// Where the loop is at `t`. It starts where the empty-screen band starts, so the first frame is already flames.
    public static func phase(t: Double) -> Float {
        let p = Double(stillPhase) + t / loop
        return Float(p - p.rounded(.down))
    }

    // MARK: Inks

    /// Two printed colours (RGBA packed like `PaintingWall.litColours`): `ink` is the letters, `flame` the fire inside them.
    public struct Inks: Equatable, Sendable {
        public var ink: UInt32
        public var flame: UInt32
        public init(ink: UInt32, flame: UInt32) { self.ink = ink; self.flame = flame }
    }

    /// The least the letters and the flames may contrast with the plate: the ink reads like text, the flames like a large graphic.
    public static let inkContrast = 4.5, flameContrast = 3.0
    /// How far the flame stands from the ink (a contrast ratio), so the fire reads inside the letters.
    public static let flameSeparation = 2.0
    /// How saturated a flame must be to count as coloured.
    public static let colouredFlame = 0.35

    /// Picks the flame from a painting's palette, printed the way the wall prints it in this appearance and pushed toward the ink until
    /// it clears `flameContrast` on the plate: the coloured one furthest from the ink (at least `flameSeparation`), so the fire is as
    /// bright as the plate allows. `ink` is the text token, given as `0xRRGGBB` like the plate.
    public static func inks(palette: [String], dark: Bool, plate: UInt32, ink: UInt32) -> Inks {
        let ground = rgb(hex: plate), letter = rgb(hex: ink)
        let printed = PaintingWall.litColours(palette: palette, dark: dark).map { lift(rgb(word: $0), from: ground, to: flameContrast, dark: dark) }
        func away(_ c: RGB) -> Double { contrast(c, letter) }
        let apart = printed.filter { away($0) >= flameSeparation }, pool = apart.isEmpty ? printed : apart
        let coloured = pool.filter { PaintingWall.saturation($0.r, $0.g, $0.b) >= colouredFlame }
        var flame = (coloured.isEmpty ? pool : coloured).max { away($0) < away($1) } ?? mix(ground, letter, 0.5)
        // a palette with nothing apart from the ink: move the flame toward the plate as far as it can go and still read
        for _ in 0..<20 where away(flame) < flameSeparation {
            let next = mix(flame, ground, 0.15)
            if contrast(next, ground) < flameContrast { break }
            flame = next
        }
        return Inks(ink: word(rgb: letter), flame: word(rgb: flame))
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

    /// One frame, `columns × sub` by `rows × sub` RGBA words (0 off the letters). Each letter cell is `sub × sub` flame pixels, ink
    /// or flame by the empty-screen band's formula in the bottom `flameShare`. `from` is the painting leaving while the wall turns
    /// (`e` its eased progress), nil while it holds. With Reduce Motion the flames hold still at `stillPhase`.
    public static func pixels(t: Double, inks to: Inks, from: Inks? = nil, e: Double = 1, develop: Double = 1, reduceMotion: Bool) -> [UInt32] {
        let phase = reduceMotion ? stillPhase : phase(t: t), width = columns * sub, height = rows * sub
        let band = Int((Double(height) * flameShare).rounded()), top = height - band, bayer = DitherBand.bayer
        var out = [UInt32](repeating: 0, count: width * height)
        for cy in 0..<rows {
            for cx in 0..<columns where cells[cy * columns + cx] {
                if develop < 1, !Dither.lit(ink: develop, x: cx, y: cy) { continue }
                for py in cy * sub..<(cy + 1) * sub {
                    let y = py - top
                    for px in cx * sub..<(cx + 1) * sub {
                        let inks = from == nil || e >= 1 || Dither.noise(px, py) < e ? to : from!
                        let lit = y >= 0 && DitherBand.flame(x: px, y: y, rows: band, phase: phase, gain: flameGain) > bayer[((y & 7) << 3) | (px & 7)]
                        out[py * width + px] = lit ? inks.flame : inks.ink
                    }
                }
            }
        }
        return out
    }

    public static func image(_ pixels: [UInt32]) -> CGImage? {
        let width = columns * sub, height = rows * sub
        guard pixels.count == width * height else { return nil }
        let data = pixels.withUnsafeBufferPointer { Data(buffer: $0) }
        return CGDataProvider(data: data as CFData).flatMap {
            CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                    bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue), provider: $0, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
        }
    }
}

/// The wordmark as a view: `Wordmark.size`, nearest-neighbour, named "Grails". `palette` is the
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

    public init(t: Double, palette: [String], from: [String]? = nil, progress: Double? = nil, develop: Double = 1, reduceMotion: Bool) {
        self.t = t; self.palette = palette; self.from = from; self.progress = progress; self.develop = develop; self.reduceMotion = reduceMotion
    }

    public var body: some View {
        let dark = scheme == .dark
        let plate = Palette.hex(.canvas, dark: dark), ink = Palette.hex(.text, dark: dark)
        let to = Wordmark.inks(palette: palette, dark: dark, plate: plate, ink: ink)
        let leaving = reduceMotion ? nil : from.map { Wordmark.inks(palette: $0, dark: dark, plate: plate, ink: ink) }
        let pixels = Wordmark.pixels(t: t, inks: to, from: leaving, e: progress.map(PaintingWall.ease) ?? 1, develop: develop, reduceMotion: reduceMotion)
        ZStack {
            if let image = Wordmark.image(pixels) {
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
