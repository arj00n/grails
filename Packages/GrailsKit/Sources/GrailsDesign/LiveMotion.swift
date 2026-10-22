import AppKit
import SwiftUI

/// When something that moves on its own (a spinner, Holy Grail's stars, a clock-driven view) may run. Every TimelineView in the app goes
/// through `GrailsLiveMotion`, so nothing spends a frame where nobody can see it: the app in the background, the window minimised,
/// hidden or covered, Reduce Motion, a snapshot. Decorative loops also rest once the person has stopped touching the app.
public enum LiveMotion {
    /// Progress motion (a spinner) runs whenever it can be seen in the frontmost app.
    /// Decorative motion also needs recent input: after `Motion.ambientIdle` untouched it rests, still, until the next event.
    public static func isLive(decorative: Bool, reduceMotion: Bool, snapshot: Bool, appActive: Bool, windowVisible: Bool, idle: Bool) -> Bool {
        !reduceMotion && !snapshot && appActive && windowVisible && !(decorative && idle)
    }

    /// Whether `window` can be seen: on screen, not minimised, not hidden, not fully covered.
    @MainActor public static func isVisible(_ window: NSWindow?) -> Bool {
        guard let window, !window.isMiniaturized, window.isVisible, !NSApp.isHidden else { return false }
        return window.occlusionState.contains(.visible)
    }
}

/// App-wide "is anyone here": set by input, cleared `Motion.ambientIdle` after the last event. Event driven, one deadline at a time,
/// no polling: an event only stamps the time, and the one pending check re-arms itself for whatever is left.
@MainActor @Observable
public final class MotionActivity {
    public static let shared = MotionActivity()

    public private(set) var idle = false
    @ObservationIgnored private var last = Date()
    @ObservationIgnored private var check: DispatchWorkItem?
    @ObservationIgnored private var monitor: Any?

    private init() {}

    /// Installs the one input monitor the first time something decorative asks. Idempotent.
    func start() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown, .scrollWheel, .mouseMoved, .magnify]) { event in
            MainActor.assumeIsolated { MotionActivity.shared.touch() }
            return event
        }
        touch()
    }

    func touch() {
        last = Date()
        if idle { idle = false }
        if check == nil { arm(after: Motion.ambientIdle) }
    }

    private func arm(after delay: TimeInterval) {
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.check = nil
                let left = Motion.ambientIdle - Date().timeIntervalSince(self.last)
                if left > 0.5 { self.arm(after: left) } else { self.idle = true }
            }
        }
        check = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }
}

/// Hands `content` whether it may move right now (see `LiveMotion.isLive`). Put the TimelineView inside and pause it on `!live`:
///
///     GrailsLiveMotion { live in TimelineView(.animation(paused: !live)) { … } }
///
/// The view watches its own window and the app, so it works in any window, sheet or panel without a root modifier.
public struct GrailsLiveMotion<Content: View>: View {
    var decorative: Bool
    var content: (Bool) -> Content
    @Environment(\.grailsReduceMotion) private var reduceMotion
    @Environment(\.grailsSnapshot) private var snapshot
    @State private var place = LivePlace()

    public init(decorative: Bool = false, @ViewBuilder content: @escaping (_ live: Bool) -> Content) {
        self.decorative = decorative
        self.content = content
    }

    public var body: some View {
        let idle = decorative && MotionActivity.shared.idle
        content(LiveMotion.isLive(decorative: decorative, reduceMotion: reduceMotion, snapshot: snapshot,
                                  appActive: place.appActive, windowVisible: place.windowVisible, idle: idle))
            .background(LiveProbe(place: place, decorative: decorative).frame(width: 0, height: 0).accessibilityHidden(true))
    }
}

@MainActor @Observable
final class LivePlace {
    var appActive = false
    var windowVisible = false
}

/// A zero-size view that follows its window's occlusion and miniaturisation and the app's active and hidden state.
private struct LiveProbe: NSViewRepresentable {
    var place: LivePlace
    var decorative: Bool

    func makeNSView(context: Context) -> ProbeView {
        if decorative { MotionActivity.shared.start() }
        let v = ProbeView()
        v.place = place
        return v
    }

    func updateNSView(_ nsView: ProbeView, context: Context) { nsView.place = place }

    final class ProbeView: NSView {
        var place: LivePlace? { didSet { refresh() } }
        nonisolated(unsafe) private var tokens: [NSObjectProtocol] = []

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            tokens.forEach(NotificationCenter.default.removeObserver)
            tokens = []
            let nc = NotificationCenter.default
            let names: [Notification.Name] = [NSApplication.didBecomeActiveNotification, NSApplication.didResignActiveNotification,
                                              NSApplication.didHideNotification, NSApplication.didUnhideNotification]
            for name in names {
                tokens.append(nc.addObserver(forName: name, object: NSApp, queue: .main) { [weak self] _ in MainActor.assumeIsolated { self?.refresh() } })
            }
            if let window {
                let windowNames: [Notification.Name] = [NSWindow.didChangeOcclusionStateNotification, NSWindow.didMiniaturizeNotification,
                                                        NSWindow.didDeminiaturizeNotification]
                for name in windowNames {
                    tokens.append(nc.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in MainActor.assumeIsolated { self?.refresh() } })
                }
            }
            refresh()
        }

        private func refresh() {
            guard let place else { return }
            let active = NSApp?.isActive ?? false, visible = LiveMotion.isVisible(window)
            if place.appActive != active { place.appActive = active }
            if place.windowVisible != visible { place.windowVisible = visible }
        }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        deinit { tokens.forEach(NotificationCenter.default.removeObserver) }
    }
}
