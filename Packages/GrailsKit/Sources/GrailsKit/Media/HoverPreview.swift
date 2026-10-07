import Foundation

/// Hover-to-play for video tiles: which tiles may play, and when. Pure (times are passed in), so the rules are table-tested;
/// the app owns the one player and moves it between tiles.
public enum HoverPreview {
    /// How long the pointer has to rest on a tile before it plays.
    public static let dwell: TimeInterval = 0.25
    /// After a scroll or a drag, pointer moves this soon don't arm a tile (trackpad momentum, a release mid-move).
    public static let quietAfterScroll: TimeInterval = 0.15
    /// Still to video and back, ease-out. (UI_SYSTEM: ≤ 120 ms, nothing overshoots.)
    public static let fadeIn: TimeInterval = 0.12
    public static let fadeOut: TimeInterval = 0.10
    /// Decoding cap: bigger than 4K UHD keeps the still (one hover shouldn't spin up an 8K decode).
    public static let maxPixels = 3840 * 2160

    /// Why a tile doesn't play. nil from `gate` means it may.
    public enum Skip: Equatable, Sendable {
        case notVideo, disabled, reduceMotion, tooLarge, missing, cloudOnly
    }

    /// The rules, cheapest first: the filesystem is only asked about videos that could play. `availability` returns nil when
    /// the original isn't there at all; it must never read the file (an online-only file would download).
    public static func gate(kind: ItemKind, enabled: Bool, reduceMotion: Bool, width: Int?, height: Int?,
                            availability: () -> FileAvailability?) -> Skip? {
        guard kind == .video else { return .notVideo }
        guard enabled else { return .disabled }
        guard !reduceMotion else { return .reduceMotion }
        if let w = width, let h = height, w * h > maxPixels { return .tooLarge }
        switch availability() {
        case nil: return .missing
        case .cloudOnly?: return .cloudOnly
        case .local?: return nil
        }
    }

    /// The frame the thumbnail was made from (a little way in, so it isn't the black first frame of a fade-in). Playback starts
    /// here so the crossfade from the still lands on the same picture.
    public static func posterTime(duration: Double) -> Double {
        guard duration.isFinite, duration > 0 else { return 0 }
        return min(duration * 0.2, 1.0)
    }

    /// A few frames spread through a clip, clear of the fade at each end. A very short clip is just the poster.
    public static func sampleTimes(duration: Double, count: Int = 3) -> [Double] {
        guard count > 0 else { return [] }
        guard duration.isFinite, duration > 0.4 else { return [posterTime(duration: duration)] }
        if count == 1 { return [posterTime(duration: duration)] }
        let inset = min(duration * 0.12, 0.5)
        let start = inset
        let end = duration - inset
        guard end > start else { return [posterTime(duration: duration)] }
        return (0..<count).map { i in start + (end - start) * Double(i) / Double(count - 1) }
    }
}

/// The dwell and cancel rules for one pointer over many tiles. Feed it pointer moves, ticks and cancels; it answers with what
/// the player should do. At most one target plays at a time.
public struct HoverDwell<Target: Hashable & Sendable>: Sendable {
    public enum Phase: Equatable, Sendable {
        case idle
        case waiting(Target, since: Double)
        case playing(Target)
    }

    public enum Effect: Equatable, Sendable {
        case start(Target)
        case stop(Target)
    }

    public enum Cancel: Equatable, Sendable {
        /// Scrolling, zooming or panning: stop, and ignore pointer moves until things are quiet again.
        case scroll
        /// A button went down (click, drag, marquee): stop, and wait for it to come up.
        case press
        /// The window stopped being key, the app went to the background, the view went away, the tile was reused,
        /// Reduce Motion or the setting turned it off.
        case other
    }

    public private(set) var phase: Phase = .idle
    public let dwell: Double
    public let quiet: Double
    private var quietUntil = -Double.infinity
    private var pressed = false

    public init(dwell: Double = HoverPreview.dwell, quiet: Double = HoverPreview.quietAfterScroll) {
        self.dwell = dwell
        self.quiet = quiet
    }

    public var playing: Target? { if case .playing(let t) = phase { t } else { nil } }

    /// When `tick` should next be called, if a tile is waiting.
    public var deadline: Double? { if case .waiting(_, let since) = phase { since + dwell } else { nil } }

    /// The pointer moved and is now over `target` (nil: over nothing that can play). Moving within the waiting tile keeps its clock.
    public mutating func pointer(over target: Target?, at t: Double) -> Effect? {
        switch phase {
        case .playing(let p):
            if p == target { return nil }
            phase = arm(target, t)
            return .stop(p)
        case .waiting(let w, _):
            if w == target { return nil }
            phase = arm(target, t)
            return nil
        case .idle:
            phase = arm(target, t)
            return nil
        }
    }

    private func arm(_ target: Target?, _ t: Double) -> Phase {
        guard let target, !pressed, t >= quietUntil else { return .idle }
        return .waiting(target, since: t)
    }

    /// Time passed: a tile that has been waiting long enough starts.
    public mutating func tick(at t: Double) -> Effect? {
        guard case .waiting(let w, let since) = phase, t + 0.0005 >= since + dwell else { return nil }
        phase = .playing(w)
        return .start(w)
    }

    public mutating func cancel(_ reason: Cancel, at t: Double) -> Effect? {
        let was = playing
        phase = .idle
        switch reason {
        case .scroll: quietUntil = max(quietUntil, t + quiet)
        case .press: pressed = true
        case .other: break
        }
        return was.map { .stop($0) }
    }

    /// The button came up: pointer moves may arm tiles again.
    public mutating func released() { pressed = false }

    /// The start couldn't happen after all (the tile went away, the file did): back to idle without a stop.
    public mutating func abandon(_ target: Target) {
        if phase == .playing(target) || deadline != nil { phase = .idle }
    }
}
