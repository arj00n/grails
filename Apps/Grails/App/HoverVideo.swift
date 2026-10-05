import AppKit
import AVFoundation
import GrailsKit
import QuartzCore
import SwiftUI

/// A place that shows item tiles (grid, canvas, the arriving wall) and can host the hover player.
@MainActor
protocol HoverVideoSurface: AnyObject {
    /// Where the tile showing `id` is drawn right now, or nil if it isn't on screen.
    func hoverHost(for id: String) -> HoverVideo.Host?
    func hoverSummary(for id: String) -> ItemSummary?
    func hoverOriginal(for s: ItemSummary) -> URL?
}

/// Videos play on hover. One muted, looping player and one player layer for the whole app, moved to whichever tile the pointer
/// has rested on for 250 ms; nothing plays otherwise. The decisions (dwell, cancels, availability) are `HoverDwell` and
/// `HoverPreview.gate` in the kit; this class owns the player and listens for everything that has to stop it.
@MainActor
final class HoverVideo {
    static let shared = HoverVideo()

    enum Host {
        /// An AppKit tile (grid cell, SwiftUI slot): the player goes in a view under the tile's badges.
        case view(NSView, AVLayerVideoGravity)
        /// A layer tile (canvas): the player layer goes straight in.
        case layer(CALayer, AVLayerVideoGravity)
    }

    struct Target: Hashable, Sendable {
        let id: String
        let surface: ObjectIdentifier
    }

    static let settingKey = "hoverVideos"
    static var settingOn: Bool { UserDefaults.standard.object(forKey: settingKey) == nil || UserDefaults.standard.bool(forKey: settingKey) }

    // Injected by the headless demo; real values otherwise.
    var reduceMotion: () -> Bool = { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
    var enabled: () -> Bool = { HoverVideo.settingOn }
    /// nil when the original isn't there. Never reads the file: an online-only file must not start downloading for a hover.
    var availability: (URL) -> FileAvailability? = { FileManager.default.fileExists(atPath: $0.path) ? FileAvailability.of($0) : nil }

    private var dwell = HoverDwell<Target>()
    private var surfaces: [ObjectIdentifier: WeakSurface] = [:]
    private var timer: DispatchWorkItem?
    private var installed = false
    private var observers: [NSObjectProtocol] = []

    private(set) var player: AVPlayer?
    let playerLayer = AVPlayerLayer()
    private let hostView = HoverVideoView()
    /// The tile view or layer the player is in now (also while it fades out).
    private(set) weak var hostedIn: AnyObject?
    private var generation = 0
    private var statusObservation: NSKeyValueObservation?
    private var endObserver: NSObjectProtocol?

    // Read by the demo.
    private(set) var playingID: String?
    private(set) var lastSkip: HoverPreview.Skip?
    private(set) var playersMade = 0
    private(set) var itemsMade = 0
    private(set) var fadeLog: [(String, Double)] = []
    /// What stopped each preview ("moved", "left", "scroll", "press", "other", "release"), newest last.
    private(set) var stopLog: [String] = []
    private var cause = ""

    private init() {
        playerLayer.opacity = 0
        playerLayer.actions = ["position": NSNull(), "bounds": NSNull(), "frame": NSNull(), "contents": NSNull()]
        hostView.wantsLayer = true
        hostView.layer?.addSublayer(playerLayer)
        hostView.autoresizingMask = [.width, .height]
        // not from inside the view tree's own removal: next turn of the run loop
        hostView.onLeftWindow = { DispatchQueue.main.async { MainActor.assumeIsolated { HoverVideo.shared.cancel(.other) } } }
    }

    private var now: Double { CACurrentMediaTime() }

    // MARK: Pointer in

    /// The pointer moved over a surface; `id` is the tile under it (nil: none, or something sits on top of the surface).
    func pointerMoved(over id: String?, in surface: HoverVideoSurface) {
        installIfNeeded()
        if NSEvent.pressedMouseButtons == 0 { dwell.released() }
        let key = ObjectIdentifier(surface)
        surfaces[key] = WeakSurface(surface)
        var target: Target?
        if let id {
            let t = Target(id: id, surface: key)
            let current: Target? = switch dwell.phase { case .waiting(let w, _): w; case .playing(let p): p; case .idle: nil }
            if t == current { target = t }
            else if let skip = gate(id, surface) { lastSkip = skip }
            else { target = t }
        }
        cause = "moved"
        apply(dwell.pointer(over: target, at: now))
        schedule()
    }

    /// The pointer left a surface altogether.
    func pointerLeft(_ surface: HoverVideoSurface) {
        let key = ObjectIdentifier(surface)
        let current: Target? = switch dwell.phase { case .waiting(let w, _): w; case .playing(let p): p; case .idle: nil }
        guard current?.surface == key else { return }
        cause = "left"
        apply(dwell.pointer(over: nil, at: now))
        schedule()
    }

    func cancel(_ reason: HoverDwell<Target>.Cancel) {
        cause = "\(reason)"
        apply(dwell.cancel(reason, at: now))
        schedule()
    }

    /// A tile view or layer is being reused for another item, or taken away: the player leaves it at once.
    func release(host: AnyObject) {
        guard hostedIn === host else { return }
        cancel(.other)
        if stopLog.last == "other" { stopLog[stopLog.count - 1] = "release" }
        detachNow()
    }

    private func gate(_ id: String, _ surface: HoverVideoSurface) -> HoverPreview.Skip? {
        guard let s = surface.hoverSummary(for: id) else { return .notVideo }
        let original = surface.hoverOriginal(for: s)
        return HoverPreview.gate(kind: s.kind, enabled: enabled(), reduceMotion: reduceMotion(), width: s.width, height: s.height,
                                 availability: { original.flatMap(self.availability) })
    }

    private func schedule() {
        timer?.cancel()
        timer = nil
        guard let deadline = dwell.deadline else { return }
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.apply(self.dwell.tick(at: self.now))
                self.schedule()
            }
        }
        timer = work
        DispatchQueue.main.asyncAfter(deadline: .now() + max(0, deadline - now), execute: work)
    }

    private func apply(_ effect: HoverDwell<Target>.Effect?) {
        switch effect {
        case .start(let t)?: start(t)
        case .stop?: stop()
        case nil: break
        }
    }

    // MARK: Player

    private func start(_ t: Target) {
        guard let surface = surfaces[t.surface]?.value, let s = surface.hoverSummary(for: t.id), let host = surface.hoverHost(for: t.id) else {
            dwell.abandon(t); return
        }
        // settings, Reduce Motion or the file may have changed during the dwell
        if let skip = gate(t.id, surface) { lastSkip = skip; dwell.abandon(t); return }
        guard let url = surface.hoverOriginal(for: s) else { dwell.abandon(t); return }
        generation += 1
        let gen = generation
        detachNow()
        let player = self.player ?? makePlayer()
        let item = AVPlayerItem(asset: AVURLAsset(url: url))
        item.preferredForwardBufferDuration = 1
        itemsMade += 1
        player.replaceCurrentItem(with: item)
        attach(host)
        playingID = t.id
        let from = CMTime(seconds: HoverPreview.posterTime(duration: s.durationSec ?? 0), preferredTimescale: 600)
        statusObservation = item.observe(\.status, options: [.initial, .new]) { item, _ in
            guard item.status == .readyToPlay else { return }
            DispatchQueue.main.async { MainActor.assumeIsolated { HoverVideo.shared.ready(gen: gen, from: from) } }
        }
        endObserver.map(NotificationCenter.default.removeObserver)
        endObserver = NotificationCenter.default.addObserver(forName: AVPlayerItem.didPlayToEndTimeNotification, object: item, queue: .main) { _ in
            MainActor.assumeIsolated {
                let me = HoverVideo.shared
                guard me.generation == gen else { return }
                me.player?.seek(to: .zero)
                me.player?.play()
            }
        }
    }

    /// The file is open: go to the thumbnail's frame (so the crossfade lands on the same picture), play, fade in.
    private func ready(gen: Int, from: CMTime) {
        guard generation == gen, let player else { return }
        statusObservation = nil
        player.seek(to: from, toleranceBefore: .zero, toleranceAfter: .zero) { _ in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    let me = HoverVideo.shared
                    guard me.generation == gen else { return }
                    me.player?.play()
                    me.fade(to: 1, duration: HoverPreview.fadeIn)
                }
            }
        }
    }

    /// Stops right away (no frame decodes after this), fades the video off the still, then lets go of the file.
    private func stop() {
        stopLog.append(cause)
        generation += 1
        let gen = generation
        statusObservation = nil
        player?.pause()
        playingID = nil
        // a tile that is no longer on screen (a view switch took it away) has nothing to fade
        guard let host = hostedIn, (host as? NSView)?.window != nil || host is CALayer else { detachNow(); releaseItem(); return }
        fade(to: 0, duration: HoverPreview.fadeOut) { [weak self] in
            guard let self, self.generation == gen else { return }
            self.detachNow()
            self.releaseItem()
        }
    }

    private func releaseItem() {
        endObserver.map(NotificationCenter.default.removeObserver)
        endObserver = nil
        player?.replaceCurrentItem(with: nil)
    }

    private func makePlayer() -> AVPlayer {
        let p = AVPlayer()
        p.isMuted = true
        p.actionAtItemEnd = .none
        p.automaticallyWaitsToMinimizeStalling = false
        p.preventsDisplaySleepDuringVideoPlayback = false
        p.allowsExternalPlayback = false
        playerLayer.player = p
        player = p
        playersMade += 1
        return p
    }

    private func attach(_ host: Host) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        playerLayer.removeAllAnimations()
        playerLayer.opacity = 0
        switch host {
        case .view(let tile, let gravity):
            playerLayer.videoGravity = gravity
            if playerLayer.superlayer !== hostView.layer { hostView.layer?.addSublayer(playerLayer) }
            hostView.frame = tile.bounds
            playerLayer.frame = hostView.bounds
            // under the tile's own subviews (badge, heart, avatar), over its picture
            tile.addSubview(hostView, positioned: .below, relativeTo: tile.subviews.first)
            hostedIn = tile
        case .layer(let tile, let gravity):
            playerLayer.videoGravity = gravity
            playerLayer.frame = tile.bounds
            tile.insertSublayer(playerLayer, at: 0)
            hostedIn = tile
        }
        CATransaction.commit()
    }

    private func detachNow() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        playerLayer.removeAllAnimations()
        playerLayer.opacity = 0
        if hostView.superview != nil { hostView.removeFromSuperview() }
        if playerLayer.superlayer !== hostView.layer { playerLayer.removeFromSuperlayer(); hostView.layer?.addSublayer(playerLayer) }
        CATransaction.commit()
        hostedIn = nil
    }

    private func fade(to value: Float, duration: TimeInterval, then: (@MainActor () -> Void)? = nil) {
        let from = playerLayer.presentation()?.opacity ?? playerLayer.opacity
        fadeLog.append((value > 0 ? "in" : "out", now))
        CATransaction.begin()
        let a = CABasicAnimation(keyPath: "opacity")
        a.fromValue = from
        a.toValue = value
        a.duration = duration
        a.timingFunction = CAMediaTimingFunction(name: .easeOut)
        playerLayer.opacity = value
        playerLayer.add(a, forKey: "fade")
        CATransaction.commit()
        // a timer, not the transaction's completion: that waits on the render server, which can be late for a hidden window
        if let then { DispatchQueue.main.asyncAfter(deadline: .now() + duration + 0.02) { MainActor.assumeIsolated { then() } } }
    }

    // MARK: Everything that stops it

    private func installIfNeeded() {
        guard !installed else { return }
        installed = true
        // Copies of the events, never consumed: the grid and canvas still get every scroll, click and drag.
        _ = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel, .magnify, .swipe, .rotate, .leftMouseDown, .rightMouseDown, .otherMouseDown,
                                                       .leftMouseUp, .rightMouseUp, .otherMouseUp]) { event in
            MainActor.assumeIsolated { HoverVideo.shared.handle(event) }
            return event
        }
        let nc = NotificationCenter.default
        let stop: @Sendable (Notification) -> Void = { _ in MainActor.assumeIsolated { HoverVideo.shared.cancel(.other) } }
        observers += [
            nc.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main, using: stop),
            nc.addObserver(forName: NSApplication.didHideNotification, object: nil, queue: .main, using: stop),
            nc.addObserver(forName: NSWindow.didResignKeyNotification, object: nil, queue: .main, using: stop),
            nc.addObserver(forName: NSWindow.didMiniaturizeNotification, object: nil, queue: .main, using: stop),
            nc.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { if !HoverVideo.shared.enabled() { HoverVideo.shared.cancel(.other) } }
            },
        ]
        let ws = NSWorkspace.shared.notificationCenter
        observers += [
            ws.addObserver(forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { if HoverVideo.shared.reduceMotion() { HoverVideo.shared.cancel(.other) } }
            },
            ws.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main, using: stop),
            ws.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main, using: stop),
        ]
    }

    /// Scrolling, zooming and pressing stop the preview; a press keeps it off until the button comes up.
    func handle(_ event: NSEvent) {
        switch event.type {
        case .scrollWheel, .magnify, .swipe, .rotate: cancel(.scroll)
        case .leftMouseDown, .rightMouseDown, .otherMouseDown: cancel(.press)
        case .leftMouseUp, .rightMouseUp, .otherMouseUp: dwell.released()
        default: break
        }
    }

    private struct WeakSurface {
        weak var value: HoverVideoSurface?
        init(_ v: HoverVideoSurface) { value = v }
    }
}

/// Holds the player layer inside an AppKit tile. Never takes the mouse: clicks, drags and menus go to the tile underneath.
final class HoverVideoView: NSView {
    var onLeftWindow: (@MainActor () -> Void)?
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func isAccessibilityElement() -> Bool { false }
    override func layout() {
        super.layout()
        CATransaction.begin(); CATransaction.setDisableActions(true)
        layer?.sublayers?.forEach { $0.frame = bounds }
        CATransaction.commit()
    }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        // the tile's view went away with us still in it (a view switch): stop
        if window == nil, superview != nil { onLeftWindow?() }
    }
}

/// Tracking-area owner for a surface. It only listens (mouseMoved / exited); it is not in the responder chain or the view tree,
/// so it can't take a click from anything.
final class HoverTracker: NSResponder {
    var onMove: ((NSEvent) -> Void)?
    var onExit: ((NSEvent) -> Void)?
    private(set) var area: NSTrackingArea?

    func install(on view: NSView) {
        if let area { view.removeTrackingArea(area) }
        let a = NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self, userInfo: nil)
        view.addTrackingArea(a)
        area = a
    }

    override func mouseMoved(with event: NSEvent) { onMove?(event) }
    override func mouseEntered(with event: NSEvent) { onMove?(event) }
    override func mouseExited(with event: NSEvent) { onExit?(event) }
}

extension NSView {
    /// Whether a point (window coordinates) lands on this view or inside it, not on something drawn over it (the top bar,
    /// a panel, the preview page).
    func isFrontmost(atWindowPoint p: NSPoint) -> Bool {
        // hitTest takes a point in the receiver's superview's coordinates
        guard let content = window?.contentView, let hit = content.hitTest(content.superview?.convert(p, from: nil) ?? p) else { return false }
        return hit === self || hit.isDescendant(of: self)
    }
}

/// A SwiftUI tile's hover surface (the Arriving wall): a transparent view over the picture that tracks the pointer and, when its
/// video plays, holds the shared player. It never takes the mouse.
struct HoverVideoSlot: NSViewRepresentable {
    let id: String
    var app: AppModel

    func makeNSView(context: Context) -> HoverSlotView {
        let v = HoverSlotView()
        v.itemID = id
        v.app = app
        return v
    }

    func updateNSView(_ v: HoverSlotView, context: Context) {
        if v.itemID != id { HoverVideo.shared.release(host: v); v.itemID = id }
        v.app = app
    }

    static func dismantleNSView(_ v: HoverSlotView, coordinator: ()) { HoverVideo.shared.release(host: v) }
}

final class HoverSlotView: NSView, HoverVideoSurface {
    var itemID = ""
    weak var app: AppModel?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self, userInfo: nil))
    }
    required init?(coder: NSCoder) { fatalError() }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func isAccessibilityElement() -> Bool { false }
    override func mouseEntered(with event: NSEvent) { HoverVideo.shared.pointerMoved(over: itemID, in: self) }
    override func mouseMoved(with event: NSEvent) { HoverVideo.shared.pointerMoved(over: itemID, in: self) }
    override func mouseExited(with event: NSEvent) { HoverVideo.shared.pointerLeft(self) }

    func hoverHost(for id: String) -> HoverVideo.Host? { id == itemID && window != nil ? .view(self, .resizeAspectFill) : nil }
    func hoverSummary(for id: String) -> ItemSummary? { app?.summary(id) }
    func hoverOriginal(for s: ItemSummary) -> URL? { app?.originalURL(for: s) }
}
