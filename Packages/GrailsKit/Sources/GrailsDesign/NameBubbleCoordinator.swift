import Foundation

/// Which name bubble is open. There is at most one.
///
/// Hover is a rest on one avatar. `pointerEntered` starts that rest, and `tick` opens the bubble once `rest` has elapsed.
/// A `rest` of zero opens on the enter itself. A second avatar takes the place of the first.
///
/// `scrollBegan` closes the bubble and drops further hovers. `scrollEnded` does not open anything on its own. When the
/// pointer is still inside the avatar it last entered, the rest starts over. `dismiss` is the window resigning key.
/// `removed` is the avatar leaving the screen or the view going away.
public struct NameBubbleCoordinator<ID: Hashable & Sendable>: Equatable, Sendable {
    enum Phase: Equatable, Sendable {
        case closed
        case waiting(ID, since: Double)
        case open(ID)
        case scrolling
    }

    private var phase: Phase = .closed
    /// The avatar the pointer last entered. A scroll keeps it so the rest can start again if the pointer is still there.
    private var under: ID?
    /// How long the pointer must rest before the bubble opens. Zero opens on the rest itself.
    public let rest: Double

    public init(rest: Double = 0) {
        self.rest = rest
    }

    public var open: ID? {
        if case .open(let id) = phase { id } else { nil }
    }

    public var isScrolling: Bool {
        if case .scrolling = phase { true } else { false }
    }

    /// When `tick` should next run, if a rest is in progress.
    var deadline: Double? {
        if case .waiting(_, let since) = phase { since + rest } else { nil }
    }

    public mutating func pointerEntered(_ id: ID, at time: Double) {
        under = id
        guard !isScrolling else { return }
        switch phase {
        case .open(let current) where current == id: return
        case .waiting(let current, _) where current == id: return
        default: phase = armed(id, at: time)
        }
    }

    public mutating func pointerExited(_ id: ID) {
        guard under == id else { return }
        under = nil
        switch phase {
        case .open(let current) where current == id: phase = .closed
        case .waiting(let current, _) where current == id: phase = .closed
        default: break
        }
    }

    public mutating func scrollBegan() {
        guard !isScrolling else { return }
        phase = .scrolling
    }

    /// The scroll, including momentum, has stopped. Opens nothing until `pointerInside` says the pointer is still on `under`.
    public mutating func scrollEnded(at time: Double, pointerInside: (ID) -> Bool) {
        guard isScrolling else { return }
        guard let id = under, pointerInside(id) else {
            under = nil
            phase = .closed
            return
        }
        phase = armed(id, at: time)
    }

    public mutating func tick(at time: Double) {
        guard case .waiting(let id, let since) = phase else { return }
        // A one-shot timer can fire a hair early. Half a millisecond still counts as the rest having elapsed.
        guard time + 0.000_5 >= since + rest else { return }
        phase = .open(id)
    }

    public mutating func dismiss() {
        under = nil
        if case .scrolling = phase { return }
        phase = .closed
    }

    public mutating func removed(_ id: ID) {
        if under == id { under = nil }
        switch phase {
        case .open(let current) where current == id: phase = .closed
        case .waiting(let current, _) where current == id: phase = .closed
        default: break
        }
    }

    private func armed(_ id: ID, at time: Double) -> Phase {
        rest <= 0 ? .open(id) : .waiting(id, since: time)
    }
}

#if canImport(AppKit)
import AppKit

/// AppKit side of `NameBubbleCoordinator`. One instance listens for live scroll, momentum, and the window resigning key.
/// Avatars register a view. The coordinator decides. The view only shows or hides its bubble.
@MainActor
public final class NameBubbleHost {
    public static let shared = NameBubbleHost()

    private var coordinator = NameBubbleCoordinator<UUID>(rest: NameBubble.rest)
    private var hosts: [UUID: Host] = [:]
    private var shown: UUID?
    private var tokens: [any NSObjectProtocol] = []
    private var monitor: Any?
    private var settle: DispatchWorkItem?
    private var ticket: DispatchWorkItem?
    private var clipToken: (any NSObjectProtocol)?

    private struct Host {
        weak var view: NSView?
        var show: (Bool, Bool) -> Void
    }

    private init() {}

    private var now: Double { ProcessInfo.processInfo.systemUptime }

    public func attach(_ id: UUID, view: NSView, show: @escaping (Bool, Bool) -> Void) {
        installIfNeeded()
        hosts[id] = Host(view: view, show: show)
    }

    public func entered(_ id: UUID) {
        installIfNeeded()
        coordinator.pointerEntered(id, at: now)
        publish(snap: false)
        schedule()
    }

    public func exited(_ id: UUID) {
        coordinator.pointerExited(id)
        publish(snap: false)
        schedule()
    }

    /// The avatar is still on screen. Drop the claim, keep the registration, so a later enter can show it again.
    public func removed(_ id: UUID) {
        coordinator.removed(id)
        publish(snap: true)
        schedule()
    }

    /// The view left the hierarchy.
    public func detach(_ id: UUID) {
        removed(id)
        hosts[id] = nil
        if shown == id { shown = nil }
    }

    private func installIfNeeded() {
        guard tokens.isEmpty else { return }
        let center = NotificationCenter.default
        let hop: @Sendable (Notification) -> Void = { note in
            let name = note.name
            MainActor.assumeIsolated {
                switch name {
                case NSScrollView.willStartLiveScrollNotification: NameBubbleHost.shared.scrollBegan()
                case NSScrollView.didEndLiveScrollNotification: NameBubbleHost.shared.scrollEnded()
                default: NameBubbleHost.shared.resignKey()
                }
            }
        }
        tokens.append(center.addObserver(forName: NSScrollView.willStartLiveScrollNotification, object: nil, queue: .main, using: hop))
        tokens.append(center.addObserver(forName: NSScrollView.didEndLiveScrollNotification, object: nil, queue: .main, using: hop))
        tokens.append(center.addObserver(forName: NSWindow.didResignKeyNotification, object: nil, queue: .main, using: hop))
        monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
            MainActor.assumeIsolated { NameBubbleHost.shared.noteScrollWheel(event) }
            return event
        }
    }

    private func noteScrollWheel(_ event: NSEvent) {
        let phase = event.phase
        let momentum = event.momentumPhase
        if phase.contains(.began) || phase.contains(.changed) || momentum.contains(.began) || momentum.contains(.changed) {
            scrollBegan()
        } else if momentum.contains(.ended) || momentum.contains(.cancelled)
            || ((phase.contains(.ended) || phase.contains(.cancelled)) && momentum.isEmpty) {
            scrollEnded()
        }
    }

    private func scrollBegan() {
        settle?.cancel()
        settle = nil
        ticket?.cancel()
        ticket = nil
        let hide = coordinator.open != nil
        coordinator.scrollBegan()
        if hide { publish(snap: true) }
    }

    /// `didEndLiveScroll` can arrive before momentum starts. The next turn lets a momentum event cancel the open.
    private func scrollEnded() {
        guard coordinator.isScrolling else { return }
        settle?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.coordinator.scrollEnded(at: self.now) { [weak self] id in
                    self?.pointerInside(id) ?? false
                }
                self.publish(snap: false)
                self.schedule()
            }
        }
        settle = work
        DispatchQueue.main.async(execute: work)
    }

    private func resignKey() {
        settle?.cancel()
        settle = nil
        ticket?.cancel()
        ticket = nil
        let hide = coordinator.open != nil || coordinator.deadline != nil
        coordinator.dismiss()
        if hide { publish(snap: true) }
    }

    private func pointerInside(_ id: UUID) -> Bool {
        guard let view = hosts[id]?.view, let window = view.window, window.isKeyWindow else { return false }
        if view.isHiddenOrHasHiddenAncestor || view.visibleRect.isEmpty { return false }
        let point = view.convert(window.mouseLocationOutsideOfEventStream, from: nil)
        return view.bounds.contains(point)
    }

    private func publish(snap: Bool) {
        let next = coordinator.open
        if next == shown { return }
        if let shown { hosts[shown]?.show(false, snap) }
        if let next {
            hosts[next]?.show(true, false)
            watchClip(next)
        } else {
            unwatchClip()
        }
        shown = next
    }

    /// One shot at `deadline`. Nothing is scheduled when `rest` is zero, so a closed bubble does no timed work.
    private func schedule() {
        ticket?.cancel()
        ticket = nil
        guard let deadline = coordinator.deadline else { return }
        let wait = max(0, deadline - now)
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.coordinator.tick(at: self.now)
                self.publish(snap: false)
                self.schedule()
            }
        }
        ticket = work
        DispatchQueue.main.asyncAfter(deadline: .now() + wait, execute: work)
    }

    private func watchClip(_ id: UUID) {
        unwatchClip()
        guard let clip = hosts[id]?.view?.enclosingScrollView?.contentView else { return }
        clip.postsBoundsChangedNotifications = true
        clipToken = NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification, object: clip, queue: .main
        ) { _ in
            MainActor.assumeIsolated { NameBubbleHost.shared.clipMoved() }
        }
    }

    private func unwatchClip() {
        if let clipToken { NotificationCenter.default.removeObserver(clipToken) }
        clipToken = nil
    }

    private func clipMoved() {
        guard let id = coordinator.open, !pointerInside(id) else { return }
        coordinator.removed(id)
        publish(snap: true)
        schedule()
    }
}

/// Tracking for a SwiftUI avatar. Clicks pass through. Enter and exit go to `NameBubbleHost`.
final class NameBubbleProbe: NSView {
    var token = UUID()
    var active = false
    var onShow: ((Bool, Bool) -> Void)?
    private var tracking: NSTrackingArea?

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self)
        addTrackingArea(area)
        tracking = area
    }

    override func mouseEntered(with event: NSEvent) {
        guard active else { return }
        NameBubbleHost.shared.entered(token)
    }

    override func mouseExited(with event: NSEvent) {
        NameBubbleHost.shared.exited(token)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { NameBubbleHost.shared.detach(token) }
    }
}
#endif
