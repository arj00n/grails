import CoreGraphics
import Foundation

public enum PagerAxis: Equatable, Sendable { case undecided, horizontal, vertical }

/// One trackpad drag in the preview: which way it is going, how far, how fast. Deltas are finger movement (content follows the
/// fingers whatever the scroll-direction setting is); time is in seconds.
public struct PagerGesture: Sendable {
    public private(set) var axis: PagerAxis = .undecided
    public private(set) var dx = 0.0
    public private(set) var dy = 0.0
    private var samples: [(t: Double, dx: Double, dy: Double)] = []

    public init() {}

    public static let lockDistance = 10.0
    public static let forceDistance = 24.0
    public static let axisRatio = 1.5

    public mutating func add(dx ddx: Double, dy ddy: Double, at t: Double) {
        dx += ddx; dy += ddy
        samples.append((t, ddx, ddy))
        if samples.count > 24 { samples.removeFirst(samples.count - 24) }
        guard axis == .undecided else { return }
        let ax = abs(dx), ay = abs(dy)
        if max(ax, ay) >= Self.lockDistance {
            if ax >= Self.axisRatio * ay { axis = .horizontal }
            else if ay >= Self.axisRatio * ax { axis = .vertical }
            else if max(ax, ay) >= Self.forceDistance { axis = ax >= ay ? .horizontal : .vertical }     // a diagonal: take the dominant one
        }
    }

    /// Points per second over the last 80 ms; zero when the fingers have been still for 50 ms.
    public func velocity(at t: Double) -> (x: Double, y: Double) {
        guard let last = samples.last, t - last.t <= 0.05 else { return (0, 0) }
        let recent = samples.filter { t - $0.t <= 0.08 }
        guard let first = recent.first else { return (0, 0) }
        let span = max(last.t - first.t, 1.0 / 120)
        return (recent.reduce(0) { $0 + $1.dx } / span, recent.reduce(0) { $0 + $1.dy } / span)
    }
}

/// After a paging or dismiss gesture the trackpad keeps sending momentum events: swallow them, so the fling doesn't leak into
/// the next page or the grid underneath.
public struct MomentumGate: Sendable {
    public private(set) var swallowing = false
    public init() {}

    public mutating func gestureEnded() { swallowing = true }

    /// `began`: a new finger-down; `momentum`: this event is a momentum event; `momentumEnded`: the last one.
    public mutating func shouldSwallow(began: Bool, momentum: Bool, momentumEnded: Bool) -> Bool {
        if began { swallowing = false; return false }
        guard swallowing else { return false }
        if momentum && momentumEnded { swallowing = false }
        return true                  // everything until the momentum ends belongs to the fling we just handled
    }
}

public enum Pager {
    /// Resistance at the ends: the page follows the fingers less and less. `width` is the stage width.
    public static func rubberBand(_ x: Double, width: Double) -> Double {
        let sign = x < 0 ? -1.0 : 1.0
        let a = abs(x)
        return sign * (1 - 1 / (a * 0.55 / max(width, 1) + 1)) * width
    }

    /// Does releasing here turn the page? Far enough, or a flick in the same direction.
    public static func commitsPage(offset: Double, velocity: Double, width: Double) -> Bool {
        if abs(offset) > 0.30 * width { return true }
        return abs(velocity) > 350 && abs(offset) > 16 && (offset < 0) == (velocity < 0)
    }

    /// 0 at rest to 1 at half the stage height: drives the image's shrink and the page's fade while dragging down or up.
    public static func dismissProgress(dy: Double, height: Double) -> Double { min(abs(dy) / (0.5 * max(height, 1)), 1) }

    public static func commitsDismiss(dy: Double, vy: Double, height: Double) -> Bool {
        abs(dy) > 0.15 * height || (abs(vy) > 450 && (dy < 0) == (vy < 0) && abs(dy) > 8)
    }

    /// The picture, fitted into the stage with margins, never shown larger than one image pixel per point.
    public static func fitRect(image: CGSize, stage: CGSize, margin: Double = 24) -> CGRect {
        guard image.width > 0, image.height > 0 else { return .zero }
        let avail = CGSize(width: max(stage.width - margin * 2, 1), height: max(stage.height - margin * 2, 1))
        let scale = min(avail.width / image.width, avail.height / image.height, 1)
        let size = CGSize(width: image.width * scale, height: image.height * scale)
        return CGRect(x: (stage.width - size.width) / 2, y: (stage.height - size.height) / 2, width: size.width, height: size.height)
    }

    /// Tall items (full-page snapshots) open at the stage's width and are read by scrolling.
    public static func isTall(_ image: CGSize) -> Bool { image.height > 2.5 * image.width }

    /// The largest zoom (relative to fit): four times fit, but never less than two pixels per point.
    public static func maxZoom(fit: Double) -> Double { max(4 * fit, 2) }
}
