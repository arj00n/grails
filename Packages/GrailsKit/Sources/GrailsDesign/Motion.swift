import Foundation

/// How things move. Nothing overshoots, and nothing takes longer than a quarter of a second.
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

    /// Grid zoom glide: short for one column, a little longer for several, never above `longest`.
    public static func zoomGlide(columnsChanged: Double) -> TimeInterval { min(longest, 0.16 + 0.03 * abs(columnsChanged)) }
}
