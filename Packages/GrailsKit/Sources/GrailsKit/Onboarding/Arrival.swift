import Foundation

/// Lets pictures into the grid on the Arriving screen a few at a time, so it fills calmly and never storms: at most 8 every 250 ms while the
/// visible area isn't full, and at most one batch a second once new pictures land below the fold. Reduce Motion halves the rate.
public struct ArrivalPacer: Sendable {
    public private(set) var waiting: [String] = []
    private var lastRelease = -Double.infinity
    public var reduceMotion: Bool
    /// The visible part of the grid is full: new pictures only add to what is below.
    public var viewportFull = false

    public static let batch = 8
    public init(reduceMotion: Bool = false) { self.reduceMotion = reduceMotion }

    public var interval: Double { reduceMotion ? 0.5 : (viewportFull ? 1.0 : 0.25) }
    public mutating func enqueue(_ ids: [String]) { waiting += ids }
    public var isEmpty: Bool { waiting.isEmpty }

    /// The ids that may join the grid now (possibly none).
    public mutating func release(at now: Double) -> [String] {
        guard !waiting.isEmpty, now - lastRelease >= interval else { return [] }
        lastRelease = now
        let n = min(Self.batch, waiting.count)
        let out = Array(waiting.prefix(n))
        waiting.removeFirst(n)
        return out
    }
}

/// "About 3 min", only once it can be said honestly: after 20 s and 40 pictures, from the pace of the last 30 s, never a countdown in seconds.
public struct Eta: Sendable {
    private var samples: [(t: Double, handled: Int)] = []
    private var estimates: [Double] = []
    private var lastEstimate = -Double.infinity
    public init() {}

    public static let minElapsed = 20.0, minHandled = 40, window = 30.0, ceiling = 2.0 * 3600

    public mutating func add(handled: Int, at t: Double) {
        samples.append((t, handled))
        samples.removeAll { t - $0.t > Self.window + 5 }
        // an estimate every 10 s: three of them that disagree mean the pace isn't steady enough to promise anything
        if t - lastEstimate >= 10, let r = rate(at: t), r > 0 { lastEstimate = t; estimates.append(r); if estimates.count > 3 { estimates.removeFirst() } }
    }

    private func rate(at t: Double) -> Double? {
        guard let first = samples.first(where: { t - $0.t <= Self.window }), let last = samples.last, last.t > first.t, last.handled > first.handled else { return nil }
        return Double(last.handled - first.handled) / (last.t - first.t)
    }

    /// The words, or nil while it can't be said.
    public func label(handled: Int, total: Int, elapsed: Double, paused: Bool) -> String? {
        guard !paused, elapsed >= Self.minElapsed, handled >= Self.minHandled, total > handled, let current = estimates.last, current > 0 else { return nil }
        // three estimates in a row that disagree by more than 30 % aren't worth showing
        if estimates.count >= 3, let hi = estimates.max(), let lo = estimates.min(), (hi - lo) / hi > 0.3 { return nil }
        let seconds = Double(total - handled) / current
        guard seconds <= Self.ceiling else { return nil }
        if seconds < 60 { return "Under a minute" }
        return "About \(Int((seconds / 60).rounded(.up))) min"
    }
}
