import Foundation

/// How things move. Everything eases out, and nothing takes longer than a quarter of a second.
/// Spatial motion (a press releasing, a panel or overlay arriving, a toast) may settle with a small bounce.
/// An opacity fade never bounces, and Reduce Motion takes the bounce away.
public enum Motion {
    /// Hover-out, chip fills, toasts.
    public static let quick: TimeInterval = 0.10
    /// View crossfades, zoom steps.
    public static let standard: TimeInterval = 0.18
    /// Preview open and close, page settle, dismiss cancel.
    public static let flight: TimeInterval = 0.22
    public static let longest: TimeInterval = 0.24

    /// Cubic-bezier control points for `standard` (ease-out, no overshoot: y never leaves 0...1).
    public static let standardCurve = (x1: 0.22, y1: 1.0, x2: 0.36, y2: 1.0)

    /// The spring's bounce, for spatial motion only. Zero is critically damped.
    public static let bounce = 0.18
    /// How long a spatial spring takes to settle. Longer than `flight` so the overshoot reads.
    public static let spring: TimeInterval = 0.34
    /// The bounce to use: none when Reduce Motion is on.
    public static func bounce(reduceMotion: Bool) -> Double { reduceMotion ? 0 : bounce }

    /// A pressed button shrinks this much. Press-in is instant; the release springs back.
    public static let pressScale = 0.95
    /// An icon button scales its symbol only, a little further than a labelled button.
    public static let iconPressScale = 0.82
    /// A full-width row or a large card shrinks less, so its edges barely move.
    public static let rowPressScale = 0.98
    /// A grid tile under the pointer.
    public static let tilePressScale = 0.97
    /// A tag chip arrives from, and leaves toward, this scale.
    public static let chipScale = 0.6
    /// A disclosed row drops in from this far above its place.
    public static let revealDrop = 6.0
    /// An overlay grows from this scale toward its anchor.
    public static let overlayScale = 0.92
    /// An overlay anchored at the top drops this far as it arrives.
    public static let overlayDrop = 8.0
    /// A toast rises this far as it arrives.
    public static let toastRise = 16.0
    /// An empty state rises this far as it fades in.
    public static let emptyRise = 8.0
    /// One turn of the spinner. Linear, continuous: not a duration in the 240 ms sense.
    public static let spinnerPeriod: TimeInterval = 0.9
    /// A wait shorter than this never shows a spinner.
    public static let spinnerDelay: TimeInterval = 0.3
    /// Where the still spinner rests under Reduce Motion, in degrees.
    public static let spinnerRest = -70.0

    /// The painting wall's caption crossfade and the ink band's fade. Ambient, not chrome: the one place a fade runs past `longest`.
    public static let ambientCaption: TimeInterval = 0.7
    public static let ambientBand: TimeInterval = 0.4
    /// Canon's stars: each lights once per period, in turn. Ambient like the wall; they hold with the window and under Reduce Motion.
    public static let canonTwinkle: TimeInterval = 7.2
    /// Decorative motion (Canon's stars) rests this long after the last key, click or scroll, until the next one.
    public static let ambientIdle: TimeInterval = 30

    /// Spinner angle at a moment in time: a linear turn every `spinnerPeriod`, starting at `spinnerRest`.
    public static func spinnerAngle(at time: TimeInterval, reduceMotion: Bool) -> Double {
        guard !reduceMotion else { return spinnerRest }
        return spinnerRest + time.truncatingRemainder(dividingBy: spinnerPeriod) / spinnerPeriod * 360
    }

    /// Core Animation spring parameters equal to SwiftUI's `.spring(duration: spring, bounce:)` (unit mass).
    public static func springStiffness() -> Double { pow(2 * Double.pi / spring, 2) }
    public static func springDamping(reduceMotion: Bool) -> Double { 4 * Double.pi * (1 - bounce(reduceMotion: reduceMotion)) / spring }

    /// Grid zoom glide: short for one column, a little longer for several, never above `longest`.
    public static func zoomGlide(columnsChanged: Double) -> TimeInterval { min(longest, 0.16 + 0.03 * abs(columnsChanged)) }
}

/// The app's Reduce Motion setting. System follows macOS; the other two override it.
public enum GrailsMotionPreference: String, CaseIterable, Sendable {
    case system, reduce, full

    /// The `UserDefaults` key the preference is stored under.
    public static let key = "motionPreference"

    public init(stored: String?) { self = stored.flatMap(Self.init(rawValue:)) ?? .system }

    /// Whether motion is reduced, given what macOS says.
    public func reducesMotion(system: Bool) -> Bool {
        switch self {
        case .system: return system
        case .reduce: return true
        case .full: return false
        }
    }
}
