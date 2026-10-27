import CoreGraphics
import SwiftUI

/// The Grails wordmark on the title plate: pixel letters, filled with an ordered dither in two inks taken from the painting behind
/// it. Every letter cell is always printed, so the letters stay whole; the dither only chooses which ink, and a slow shimmer moves
/// that choice. When the wall turns into the next painting each cell takes the new inks on the wall's own grain (`Dither.noise`).
/// Everything here is pure, so each part can be checked without a screen. See docs/DESIGN_SYSTEM.md.
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
    /// Points per cell on the title plate: whole device pixels at 1× and 2×, and about as wide as the title used to be.
    public static let cell = 2.0
    public static var size: CGSize { CGSize(width: Double(columns) * cell, height: Double(rows) * cell) }

    private static let cells: [Bool] = bitmap.flatMap { $0.map { $0 == "#" } }
    public static func isSet(_ x: Int, _ y: Int) -> Bool { x >= 0 && x < columns && y >= 0 && y < rows && cells[y * columns + x] }

    /// The share of cells printed in the accent ink, and how far the shimmer moves it either way.
    public static let accentShare = 0.6
    public static let shimmerReach = 0.3
    /// The letters develop out of the plate like the first painting does, starting with the old typing (a second in).
    public static let developStart = 1.0, developDuration = 0.4

    // MARK: Inks

    /// Two printed colours (RGBA packed like `PaintingWall.litColours`): `accent` is the painting's colour, `base` the ink it is dithered with.
    public struct Inks: Equatable, Sendable {
        public var base: UInt32
        public var accent: UInt32
        public init(base: UInt32, accent: UInt32) { self.base = base; self.accent = accent }
    }

    /// The least an ink may contrast with the plate: the base reads like text, the accent like a large graphic.
    public static let baseContrast = 4.5, accentContrast = 3.0
    /// How far apart (as a contrast ratio) the two inks are, so the dither shows; and how saturated a base must be to count as coloured.
    public static let inkSeparation = 1.3, colouredBase = 0.4

    /// Picks the inks from a painting's palette, printed the way the wall prints them in this appearance. `accent` is the most saturated
    /// colour that clears `accentContrast`; `base` is the colour furthest from the plate that sits apart from the accent, preferring one
    /// with colour of its own. An ink that falls short of its bar is pushed toward black (light) or white (dark) until it clears it.
    public static func inks(palette: [String], dark: Bool, plate: UInt32) -> Inks {
        let ground = rgb(hex: plate)
        let printed = PaintingWall.litColours(palette: palette, dark: dark).map(rgb(word:))
        func sat(_ c: RGB) -> Double { PaintingWall.saturation(c.r, c.g, c.b) }
        let readable = printed.filter { contrast($0, ground) >= accentContrast }
        guard let accent = (readable.isEmpty ? printed : readable).max(by: { (sat($0), contrast($0, ground)) < (sat($1), contrast($1, ground)) }) else {
            let ink = word(rgb: dark ? (1, 1, 1) : (0, 0, 0))
            return Inks(base: ink, accent: ink)
        }
        let others = printed.filter { $0 != accent }
        let apart = others.filter { contrast($0, accent) >= inkSeparation }
        let pool = apart.isEmpty ? others : apart
        let coloured = pool.filter { sat($0) >= colouredBase && contrast($0, ground) >= baseContrast }
        let base = (coloured.isEmpty ? pool : coloured).max { contrast($0, ground) < contrast($1, ground) } ?? accent
        return Inks(base: word(rgb: lift(base, from: ground, to: baseContrast, dark: dark)),
                    accent: word(rgb: lift(accent, from: ground, to: accentContrast, dark: dark)))
    }

    typealias RGB = (r: Double, g: Double, b: Double)

    static func rgb(hex: UInt32) -> RGB { (Double((hex >> 16) & 255) / 255, Double((hex >> 8) & 255) / 255, Double(hex & 255) / 255) }
    static func rgb(word: UInt32) -> RGB { (Double(word & 255) / 255, Double((word >> 8) & 255) / 255, Double((word >> 16) & 255) / 255) }
    static func word(rgb c: RGB) -> UInt32 {
        func byte(_ v: Double) -> UInt32 { UInt32(min(max(v, 0), 1) * 255 + 0.5) }
        return 0xFF00_0000 | (byte(c.b) << 16) | (byte(c.g) << 8) | byte(c.r)
    }

    /// WCAG relative luminance and contrast ratio.
    static func luminance(_ c: RGB) -> Double {
        func linear(_ v: Double) -> Double { v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
        return 0.2126 * linear(c.r) + 0.7152 * linear(c.g) + 0.0722 * linear(c.b)
    }

    public static func contrast(_ a: UInt32, plate: UInt32) -> Double { contrast(rgb(word: a), rgb(hex: plate)) }
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

    /// One frame, `columns × rows` RGBA words (0 off the letters). `from` is the painting leaving while the wall turns (`e` its
    /// eased progress), nil while it holds. With Reduce Motion the shimmer is still.
    public static func pixels(t: Double, inks to: Inks, from: Inks? = nil, e: Double = 1, develop: Double = 1, reduceMotion: Bool) -> [UInt32] {
        let shimmer = PaintingWall.Shimmer(t: reduceMotion ? 0 : t, cols: columns, rows: rows)
        let reach = reduceMotion ? 0 : shimmerReach
        var out = [UInt32](repeating: 0, count: columns * rows)
        for y in 0..<rows {
            for x in 0..<columns where cells[y * columns + x] {
                if develop < 1, !Dither.lit(ink: develop, x: x, y: y) { continue }
                let inks = from == nil || e >= 1 || Dither.noise(x, y) < e ? to : from!
                let accent = Dither.lit(ink: accentShare + reach * Double(shimmer.value(x: x, y: y)), x: x, y: y)
                out[y * columns + x] = accent ? inks.accent : inks.base
            }
        }
        return out
    }

    public static func image(_ pixels: [UInt32]) -> CGImage? {
        guard pixels.count == columns * rows else { return nil }
        let data = pixels.withUnsafeBufferPointer { Data(buffer: $0) }
        return CGDataProvider(data: data as CFData).flatMap {
            CGImage(width: columns, height: rows, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: columns * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                    bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue), provider: $0, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
        }
    }
}

/// The wordmark as a view: `Wordmark.size`, nearest-neighbour, named "Grails". `palette` is the painting showing; `from` the one
/// leaving while the wall turns (`progress` 0...1, eased here like the wall). With Reduce Motion it holds still, and a change of
/// painting crossfades quickly instead of turning grain by grain.
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
        let plate = Palette.hex(.canvas, dark: dark)
        let to = Wordmark.inks(palette: palette, dark: dark, plate: plate)
        let leaving = reduceMotion ? nil : from.map { Wordmark.inks(palette: $0, dark: dark, plate: plate) }
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
