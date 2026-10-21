import AppKit
import SwiftUI

// MARK: The shared modal layer

/// Every modal in the app goes through here. A modal covers the window the person was in when they asked for it (the main
/// window, with the library or the Settings page in it), stacked on the topmost modal of that window. So it always opens above
/// whatever presented it, takes focus and Esc while it is on top, and hands focus back when it closes. `ModalStack` holds the order.
///
/// Each modal is a borderless, clear child window over its window that draws nothing itself. Inside it a scrim fades in and the
/// card (frame, fill, shadow and contents together) settles on the sheet spring. A titled sheet window would slide in on its own
/// and then stand still around contents that move: the card has to be the only frame.
@MainActor
public final class GrailsModalLayer {
    public static let shared = GrailsModalLayer()

    public private(set) var stack = ModalStack<ObjectIdentifier>()
    /// The main window, for a modal asked for while no window of ours is key (an incoming link, a menu with every window
    /// in the background). Set by the window itself.
    public weak var home: NSWindow?

    private struct Open {
        let window: ModalWindow
        let onCancel: @MainActor () -> Void
        let onDismissed: (@MainActor () -> Void)?
    }
    private var open: [String: Open] = [:]
    private var windows: [ObjectIdentifier: WeakWindow] = [:]
    /// A window with modals over it, watched so they keep covering it when it resizes.
    private var resizeWatch: [ObjectIdentifier: NSObjectProtocol] = [:]

    public init() {}

    public func isPresented(_ id: String) -> Bool { open[id] != nil }

    /// Something is open over a window, so Esc belongs to it and not to the page under it.
    public var hasOpenModal: Bool { !stack.entries.isEmpty }

    /// The window `id` is drawn in, while it is open.
    func modalWindow(_ id: String) -> NSWindow? { open[id]?.window }

    /// Shows `content` above the window that asked for it. `anchor` is the window of the view that asked, used when no window
    /// of ours is key. `onCancel` runs for Esc, or when a modal under this one closes; it should clear the state that shows it.
    /// False when there is no window to show it on.
    @discardableResult
    public func present<V: View>(
        _ id: String, from anchor: NSWindow? = nil,
        onCancel: @escaping @MainActor () -> Void, onDismissed: (@MainActor () -> Void)? = nil,
        @ViewBuilder content: () -> V
    ) -> Bool {
        if open[id] != nil { return true }
        guard let presenter = presenter(anchor) else { return false }
        windows[ObjectIdentifier(presenter)] = WeakWindow(window: presenter)
        let parent = stack.push(id, presenter: ObjectIdentifier(presenter), presenterModal: modalID(of: presenter))
        guard var host = window(for: parent) else {
            stack.remove(id)
            return false
        }
        // a system sheet (an alert) already on it: go on top of that too
        while let sheet = host.attachedSheet { host = sheet }

        let root = rootWindow(of: host)
        let w = ModalWindow(content: content(), appearance: host.appearance, frame: root.frame)
        w.presentedOn = host
        w.onCancel = { [weak self] in self?.cancel(id) }
        open[id] = Open(window: w, onCancel: onCancel, onDismissed: onDismissed)
        bringForward(host)
        host.addChildWindow(w, ordered: .above)
        w.makeKeyAndOrderFront(nil)
        watchResize(of: root)
        return true
    }

    /// Closes `id` and every modal stacked on it, topmost first.
    public func dismiss(_ id: String) {
        let back = open[id]?.window.presentedOn
        for closing in stack.remove(id) {
            guard let o = open.removeValue(forKey: closing) else { continue }
            o.window.leave()
            // a modal that closed because the one under it did: its owner's state goes too
            if closing != id { o.onCancel() }
            o.onDismissed?()
        }
        // focus goes back to what presented it, if that is still there
        if let back, back.isVisible, !(back is ModalWindow) || open.values.contains(where: { $0.window === back }) { back.makeKey() }
        unwatchIdleWindows()
    }

    /// Esc on the topmost modal. The owner clears its state, which closes it.
    private func cancel(_ id: String) {
        // only the modal with nothing on it over its window gets Esc
        guard let o = open[id], stack.isTopOfItsWindow(id), o.window.attachedSheet == nil else { return }
        o.onCancel()
        if open[id] != nil { dismiss(id) }
    }

    /// A system alert (a library that fails to open) on the same stack: above whatever asked for it.
    public func alert(title: String, message: String, from anchor: NSWindow? = nil, onClose: @escaping @MainActor () -> Void) {
        let a = NSAlert()
        a.messageText = title
        a.informativeText = message
        a.addButton(withTitle: "OK")
        guard let presenter = presenter(anchor) else {
            a.runModal()
            onClose()
            return
        }
        windows[ObjectIdentifier(presenter)] = WeakWindow(window: presenter)
        let parent = stack.parent(presenter: ObjectIdentifier(presenter), presenterModal: modalID(of: presenter))
        var host = window(for: parent) ?? presenter
        while let sheet = host.attachedSheet { host = sheet }
        bringForward(host)
        a.beginSheetModal(for: host) { _ in MainActor.assumeIsolated { onClose() } }
    }

    // MARK: Where a modal goes

    /// The window the person is in. A system sheet counts as the window it hangs from; a modal of ours counts as itself.
    private func presenter(_ anchor: NSWindow?) -> NSWindow? {
        let ours = Set(open.values.map { ObjectIdentifier($0.window) })
        func usable(_ w: NSWindow?) -> NSWindow? {
            guard var w else { return nil }
            // a modal that just closed (its sheet still sliding away, or the next step asked for in its own close) stands
            // for the window it was on
            while let closed = w as? ModalWindow, !ours.contains(ObjectIdentifier(closed)), let on = closed.presentedOn { w = on }
            guard w.isVisible else { return nil }
            while !ours.contains(ObjectIdentifier(w)), let parent = w.sheetParent { w = parent }
            return w
        }
        return usable(NSApp.keyWindow) ?? usable(anchor) ?? usable(home) ?? usable(NSApp.mainWindow)
            ?? NSApp.windows.first { $0.isVisible && $0.canBecomeMain && !($0 is NSPanel) && $0.sheetParent == nil }
    }

    private func modalID(of window: NSWindow) -> String? {
        open.first { $0.value.window === window }?.key
    }

    private func window(for parent: ModalStack<ObjectIdentifier>.Parent) -> NSWindow? {
        switch parent {
        case .window(let id): windows[id]?.window
        case .modal(let id): open[id]?.window
        }
    }

    /// The window the modal goes on comes to the front and becomes main, so activating the app can't put another of ours over it.
    private func bringForward(_ host: NSWindow) {
        let root = rootWindow(of: host)
        if !root.isMainWindow { root.makeKeyAndOrderFront(nil) } else { root.orderFront(nil) }
        if !NSApp.isActive { NSApp.activate() }
    }

    /// The window a modal, or a system sheet on one, finally covers.
    private func rootWindow(of w: NSWindow) -> NSWindow {
        var w = w
        while true {
            if let modal = w as? ModalWindow, let on = modal.presentedOn { w = on }
            else if let parent = w.sheetParent { w = parent }
            else { return w }
        }
    }

    private func watchResize(of root: NSWindow) {
        let key = ObjectIdentifier(root)
        guard resizeWatch[key] == nil else { return }
        resizeWatch[key] = NotificationCenter.default.addObserver(forName: NSWindow.didResizeNotification, object: root, queue: .main) { [weak self, weak root] _ in
            MainActor.assumeIsolated {
                guard let self, let root else { return }
                for o in self.open.values where self.rootWindow(of: o.window) === root { o.window.setFrame(root.frame, display: true) }
            }
        }
    }

    private func unwatchIdleWindows() {
        let covered = Set(open.values.map { ObjectIdentifier(rootWindow(of: $0.window)) })
        for (key, token) in resizeWatch where !covered.contains(key) {
            NotificationCenter.default.removeObserver(token)
            resizeWatch[key] = nil
        }
    }
}

private struct WeakWindow { weak var window: NSWindow? }

/// The window a modal is drawn in. It covers the window under it and draws nothing itself: no frame, no fill, no shadow, and no
/// window animation. `ModalSurface` draws the scrim and the card. It takes key, so Esc and the default button go to the topmost modal.
final class ModalWindow: NSWindow {
    var onCancel: (() -> Void)?
    weak var presentedOn: NSWindow?
    private var leaving = false

    init<V: View>(content: V, appearance: NSAppearance?, frame: NSRect) {
        super.init(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        animationBehavior = .none
        isReleasedWhenClosed = false
        // clear pixels would let a click through to the window under the modal while the scrim is still fading in
        ignoresMouseEvents = false
        self.appearance = appearance
        let host = NSHostingView(rootView: ModalSurface(content: content).grailsMotionRoot())
        host.sizingOptions = []
        contentView = host
        setFrame(frame, display: false)
    }

    override var canBecomeKey: Bool { !leaving }
    override var canBecomeMain: Bool { false }
    override func cancelOperation(_ sender: Any?) { onCancel?() }

    /// Scrim and card fade out together, quickly, and the window goes.
    func leave() {
        guard !leaving else { return }
        leaving = true
        onCancel = nil
        ignoresMouseEvents = true
        let still = ReduceMotion.isOn
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = still ? 0 : Motion.quick
            ctx.timingFunction = .grailsStandard
            animator().alphaValue = 0
        }
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(Motion.quick))
            guard let self else { return }
            self.parent?.removeChildWindow(self)
            self.orderOut(nil)
        }
    }
}

/// What a modal window shows: the scrim over the whole window and the card hanging from the top. The scrim only fades. The card
/// is one piece, frame and contents together, and settles on the sheet spring. A modal is its own window, so it gets the root
/// environment again: the body face and the ink tint (Reduce Motion comes from `grailsMotionRoot` around it).
struct ModalSurface<V: View>: View {
    let content: V
    @Environment(\.grailsReduceMotion) private var reduceMotion
    @Environment(\.grailsSnapshot) private var snapshot
    /// A test holds the entrance at its start or its end.
    private let held: Bool?
    @State private var scrimIn = false
    @State private var cardIn = false

    init(content: V) {
        self.content = content
        held = nil
    }

    init(content: V, heldArrived arrived: Bool) {
        self.content = content
        held = arrived
    }

    var body: some View {
        let scrim = ModalPresentation.scrim(arrived: held ?? (scrimIn || snapshot))
        let card = ModalPresentation.card(arrived: held ?? (cardIn || snapshot), reduceMotion: reduceMotion)
        GeometryReader { proxy in
            ZStack(alignment: .top) {
                Rectangle()
                    .fill(GrailsColor.canvas.opacity(ModalPresentation.scrimOpacity))
                    .opacity(scrim.opacity)
                    .contentShape(Rectangle())
                    .accessibilityHidden(true)
                content
                    .font(ChromeFont.body(TypeScale.body))
                    .tint(GrailsColor.text)
                    .grailsModalCard()
                    // everything above this line moves together: the card never stands still around its contents
                    .scaleEffect(card.scale, anchor: .top)
                    .offset(y: card.offsetY)
                    .opacity(card.opacity)
                    .padding(.top, ModalPresentation.cardTop(windowHeight: proxy.size.height))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
        }
        .onAppear {
            withAnimation(.grails(.grailsStandard, reduceMotion: reduceMotion)) { scrimIn = true }
            withAnimation(reduceMotion ? .grailsStandard : .grailsSpring) { cardIn = true }
        }
    }
}

// MARK: SwiftUI

public extension View {
    /// A modal through the shared layer. It opens above whatever the person was in (the library, Settings, another modal),
    /// its card settles in as one piece on the sheet spring over a fading scrim, and Esc clears `isPresented`.
    func grailsSheet<Content: View>(isPresented: Binding<Bool>, onDismiss: (() -> Void)? = nil, @ViewBuilder content: @escaping () -> Content) -> some View {
        modifier(ModalPresenter(
            key: isPresented.wrappedValue ? AnyHashable(true) : nil,
            close: { isPresented.wrappedValue = false },
            onDismiss: onDismiss,
            make: { AnyView(content()) }
        ))
    }

    /// `grailsSheet` for an item: a new item replaces the modal, nil closes it.
    func grailsSheet<Item: Identifiable, Content: View>(item: Binding<Item?>, onDismiss: (() -> Void)? = nil, @ViewBuilder content: @escaping (Item) -> Content) -> some View {
        modifier(ModalPresenter(
            key: item.wrappedValue.map { AnyHashable($0.id) },
            close: { item.wrappedValue = nil },
            onDismiss: onDismiss,
            make: { item.wrappedValue.map { AnyView(content($0)) } ?? AnyView(EmptyView()) }
        ))
    }
}

/// Keeps one call site's modal in step with its state: shown while `key` is set, replaced when it changes.
private struct ModalPresenter: ViewModifier {
    let key: AnyHashable?
    let close: @MainActor () -> Void
    let onDismiss: (() -> Void)?
    let make: @MainActor () -> AnyView
    @State private var slot = Slot()

    final class Slot {
        let base = UUID().uuidString
        weak var window: NSWindow?
        var shown: String?
    }

    func body(content: Content) -> some View {
        content
            .background(WindowProbe(slot: slot))
            .onAppear(perform: sync)
            .onChange(of: key) { sync() }
            .onDisappear {
                if let shown = slot.shown { slot.shown = nil; GrailsModalLayer.shared.dismiss(shown) }
            }
    }

    private func sync() {
        let layer = GrailsModalLayer.shared
        let want = key.map { "\(slot.base)-\(String(describing: $0))" }
        if let want, want == slot.shown, layer.isPresented(want) { return }
        if let shown = slot.shown {
            slot.shown = nil
            layer.dismiss(shown)
        }
        guard let want else { return }
        let onDismiss = onDismiss
        if layer.present(want, from: slot.window, onCancel: close, onDismissed: { onDismiss?() }, content: make) {
            slot.shown = want
        } else {
            close()
        }
    }
}

/// Reads the window a view is in, so a modal asked for while no window is key still knows where it came from.
private struct WindowProbe: NSViewRepresentable {
    let slot: ModalPresenter.Slot

    func makeNSView(context: Context) -> NSView { Probe(slot: slot) }
    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class Probe: NSView {
        let slot: ModalPresenter.Slot
        init(slot: ModalPresenter.Slot) { self.slot = slot; super.init(frame: .zero) }
        required init?(coder: NSCoder) { nil }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            slot.window = window
        }
    }
}
