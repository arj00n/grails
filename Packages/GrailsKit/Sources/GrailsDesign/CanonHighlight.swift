import AppKit
import SwiftUI

/// Holy Grail's colours. Warm gold, kept quiet: a pale fill in light mode, a deep one in dark, text well over 4.5:1 on both.
public enum CanonTokens {
    /// The selected row's fill.
    public static func fill(dark: Bool) -> (from: UInt32, to: UInt32) { dark ? (0x3A2E12, 0x55421A) : (0xFBEFCB, 0xF1D58A) }
    /// The mark and the title on the fill.
    public static func ink(dark: Bool) -> UInt32 { dark ? 0xF6E2A8 : 0x4A3608 }
    /// The mark and the title on the plain sidebar: a gentle gold that still reads on the sidebar and on its hover fill.
    public static func tint(dark: Bool) -> UInt32 { dark ? 0xE0C27C : 0x76560F }
    /// The selected row's 1 px outline, one gradient corner to corner. No glow, no shadow.
    public static func stroke(dark: Bool) -> (from: UInt32, to: UInt32) { dark ? (0xC99A35, 0x7A5C1E) : (0xE2B44B, 0xB8892A) }
    public static let strokeWidth = 1.0
    /// The stars' peak opacity: present, never loud.
    public static let starOpacity = 0.6

    static func color(_ hex: UInt32, opacity: Double = 1) -> Color {
        Color(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255, opacity: opacity)
    }
}

/// The few dithered pixel stars around Holy Grail's mark. Each is a 1 px dot or a 3 px plus on a 1 pt grid, lit through the Bayer map, so
/// it fades in and out by whole pixels like the painting wall. They take turns: one at a time, briefly, then rest.
public enum CanonStars {
    public struct Star: Sendable, Equatable {
        /// Centre, in points from the mark's centre.
        public var x: Int, y: Int
        /// A single pixel, or a plus three pixels across.
        public var plus: Bool
        /// Where in the period this star lights.
        public var phase: Double
        /// Its brightness when nothing moves (Reduce Motion, a snapshot).
        public var rest: Double
    }

    public static let stars: [Star] = [
        Star(x: -8, y: -7, plus: true, phase: 0, rest: 0.8),
        Star(x: 8, y: -5, plus: false, phase: 1.0 / 3, rest: 1),
        Star(x: 7, y: 7, plus: true, phase: 2.0 / 3, rest: 0.55),
    ]
    /// The square the stars live in, centred on the mark. It covers only the icon, so only the icon redraws.
    public static let field = 24.0
    /// Share of its period a star is lit; the rest it is dark.
    public static let lit = 0.3
    /// Brightness moves in this many steps, so a star clicks on pixel by pixel rather than gliding.
    public static let steps = 4.0

    /// Where in a lit window (0...1 of `lit`) a star's stepped brightness changes: up through each step, then back down. The peak
    /// itself is a single instant, so the top step is never held.
    static let changes: [Double] = {
        let ups = (1..<Int(steps)).map { asin(Double($0) / steps) / .pi }
        return (ups + ups.reversed().map { 1 - $0 }).map { $0 * lit }
    }()

    /// The next moment after `t` that any star's brightness steps, so the stars redraw only when a pixel changes and not at all while
    /// every star is dark. A hair past the step, so the frame drawn there already shows it.
    public static func nextChange(after t: TimeInterval) -> TimeInterval {
        let period = Motion.canonTwinkle
        var best = TimeInterval.infinity
        for star in stars {
            let cycle = ((t / period + 1 - star.phase).truncatingRemainder(dividingBy: 1) + 1).truncatingRemainder(dividingBy: 1)
            let base = t - cycle * period
            for lap in 0...1 {
                for c in changes {
                    let at = base + (Double(lap) + c) * period + 0.001
                    if at > t + 0.0005, at < best { best = at }
                }
            }
        }
        return best
    }

    /// The stars' timeline: one entry per step while `live`, none after the first while not, so a paused field costs nothing.
    public struct Schedule: TimelineSchedule {
        public var live: Bool
        public init(live: Bool) { self.live = live }

        public func entries(from start: Date, mode: TimelineScheduleMode) -> AnyIterator<Date> {
            var next: Date? = start
            return AnyIterator {
                guard let now = next else { return nil }
                next = live ? Date(timeIntervalSinceReferenceDate: CanonStars.nextChange(after: now.timeIntervalSinceReferenceDate)) : nil
                return now
            }
        }
    }

    /// 0...1 for one star at time `t`: a short smooth bump once per `Motion.canonTwinkle`, stepped, dark the rest of the period.
    public static func brightness(_ star: Star, at t: TimeInterval) -> Double {
        let cycle = (t / Motion.canonTwinkle + 1 - star.phase).truncatingRemainder(dividingBy: 1)
        guard cycle < lit else { return 0 }
        let bump = sin(cycle / lit * .pi)
        return (bump * steps).rounded(.down) / steps
    }

    /// The pixels lit for `star` at `brightness`, relative to its centre. The centre carries the full brightness, the arms less,
    /// and each pixel is lit where its ink beats the Bayer threshold at its place in the field.
    public static func pixels(_ star: Star, brightness: Double) -> [(x: Int, y: Int)] {
        let cells: [(Int, Int, Double)] = star.plus ? [(0, 0, 1), (-1, 0, 0.6), (1, 0, 0.6), (0, -1, 0.6), (0, 1, 0.6)] : [(0, 0, 1)]
        let half = Int(field / 2)
        return cells.compactMap { dx, dy, weight in
            let x = star.x + dx, y = star.y + dy
            return Dither.lit(ink: brightness * weight, x: x + half, y: y + half) ? (dx, dy) : nil
        }
    }
}

/// The Holy Grail mark, everywhere Holy Grail appears: a filled rosette. SF Symbols has `rosette` but no fill variant, so the filled
/// mark is `rosette` with a disc laid in its ring. `filled: false` is the plain outline, for "Add to Holy Grail" before an item is in it.
/// `CanonMark.image` is the same mark for AppKit menus.
public struct CanonMark: View {
    var size: CGFloat
    var filled: Bool
    public init(size: CGFloat = 12, filled: Bool = true) {
        self.size = size
        self.filled = filled
    }

    public static let symbolName = "rosette"
    /// The rosette's ring and ribbons stand taller and carry more ink than the heart or a folder at the same point size; at this share
    /// of it they sit level with them.
    public static let opticalScale = 0.88
    /// The ring's hole in `rosette`, as shares of the image height: its centre from the top, and the disc's radius, which reaches halfway
    /// into the ring so no gap shows. Measured from the symbol; a test checks the hole is filled.
    static let ringCentre = 0.377, discRadius = 0.27

    public var body: some View {
        Image(nsImage: Self.image(pointSize: size, filled: filled))
            .renderingMode(.template)
            .accessibilityLabel("Holy Grail")
    }

    /// A template image of the mark, sized like the other symbols in a menu.
    /// Nonisolated, so AppKit may draw the filled image off the main thread.
    nonisolated public static func image(pointSize: CGFloat = NSFont.menuFont(ofSize: 0).pointSize, filled: Bool = true) -> NSImage {
        let config = NSImage.SymbolConfiguration(pointSize: pointSize * opticalScale, weight: .regular)
        guard let ring = NSImage(systemSymbolName: symbolName, accessibilityDescription: "Holy Grail")?.withSymbolConfiguration(config) else { return NSImage() }
        let image = filled ? NSImage(size: ring.size, flipped: false) { rect in
            ring.draw(in: rect)
            let r = rect.height * discRadius
            NSColor.black.setFill()
            NSBezierPath(ovalIn: CGRect(x: rect.midX - r, y: rect.height * (1 - ringCentre) - r, width: r * 2, height: r * 2)).fill()
            return true
        } : ring
        image.alignmentRect = ring.alignmentRect
        image.accessibilityDescription = "Holy Grail"
        image.isTemplate = true
        return image
    }
}

/// An SF Symbol at `size`, with the Holy Grail mark at its optical size.
public struct GrailsSymbol: View {
    var name: String
    var size: CGFloat
    public init(_ name: String, size: CGFloat) {
        self.name = name
        self.size = size
    }

    public var body: some View {
        if name == CanonMark.symbolName {
            CanonMark(size: size)
        } else {
            Image(systemName: name).font(ChromeFont.symbol(size))
        }
    }
}

/// What sits behind Holy Grail's row in the sidebar. Not selected: nothing but the hover every row has. Selected: the gold fill and a thin
/// gold outline. No glow, no sweeping light.
public struct GrailsCanonHighlight: View {
    var selected: Bool
    var hovering: Bool
    var radius: CGFloat
    @Environment(\.colorScheme) private var scheme

    public init(selected: Bool = false, hovering: Bool = false, radius: CGFloat = 6) {
        self.selected = selected
        self.hovering = hovering
        self.radius = radius
    }

    public var body: some View {
        let dark = scheme == .dark
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        if selected {
            let fill = CanonTokens.fill(dark: dark), stroke = CanonTokens.stroke(dark: dark)
            shape
                .fill(LinearGradient(colors: [CanonTokens.color(fill.from), CanonTokens.color(fill.to)], startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay(shape.strokeBorder(LinearGradient(colors: [CanonTokens.color(stroke.from), CanonTokens.color(stroke.to)], startPoint: .topLeading, endPoint: .bottomTrailing),
                                            lineWidth: CanonTokens.strokeWidth))
                .accessibilityHidden(true)
        } else {
            shape.fill(GrailsInk(.fill, opacity: hovering ? 1 : 0)).accessibilityHidden(true)
        }
    }
}

/// The stars around Holy Grail's mark: put it over the mark (`.overlay { CanonSparkles() }`). One small canvas the size of the icon that
/// redraws only when a star steps (`CanonStars.Schedule`), so the row itself never redraws. Through `GrailsLiveMotion`: still under
/// Reduce Motion and in snapshots, paused with the app in the background, the window out of sight, or nobody touching the app.
public struct CanonSparkles: View {
    var selected: Bool
    @Environment(\.colorScheme) private var scheme
    @Environment(\.grailsReduceMotion) private var reduceMotion
    @Environment(\.grailsSnapshot) private var snapshot

    public init(selected: Bool = false) { self.selected = selected }

    private var still: Bool { reduceMotion || snapshot }

    public var body: some View {
        let dark = scheme == .dark
        let ink = CanonTokens.color(selected ? CanonTokens.ink(dark: dark) : CanonTokens.tint(dark: dark), opacity: CanonTokens.starOpacity)
        GrailsLiveMotion(decorative: true) { live in
            TimelineView(CanonStars.Schedule(live: live)) { context in
                let t = context.date.timeIntervalSinceReferenceDate
                Canvas(rendersAsynchronously: false) { gc, size in
                    let cx = (size.width / 2).rounded(.down), cy = (size.height / 2).rounded(.down)
                    for star in CanonStars.stars {
                        let b = still ? star.rest : CanonStars.brightness(star, at: t)
                        for p in CanonStars.pixels(star, brightness: b) {
                            gc.fill(Path(CGRect(x: cx + CGFloat(star.x + p.x), y: cy + CGFloat(star.y + p.y), width: 1, height: 1)), with: .color(ink))
                        }
                    }
                }
            }
        }
        .frame(width: CanonStars.field, height: CanonStars.field)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Holy Grail's gold ink for the mark and title: the deep gold on the selected fill, the gentle tint on the plain sidebar.
public struct CanonInk: ShapeStyle {
    var selected: Bool
    public init(selected: Bool = true) { self.selected = selected }
    public func resolve(in environment: EnvironmentValues) -> Color {
        let dark = environment.colorScheme == .dark
        return CanonTokens.color(selected ? CanonTokens.ink(dark: dark) : CanonTokens.tint(dark: dark))
    }
}
