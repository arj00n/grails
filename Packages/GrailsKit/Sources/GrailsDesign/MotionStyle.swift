import AppKit
import SwiftUI

/// The one place Reduce Motion is read. The app preference wins over macOS; both are read fresh, so a change made while the app
/// runs is picked up on the next animation. AppKit code calls `ReduceMotion.isOn`. SwiftUI reads `\.grailsReduceMotion`.
public enum ReduceMotion {
    public static var preference: GrailsMotionPreference {
        GrailsMotionPreference(stored: UserDefaults.standard.string(forKey: GrailsMotionPreference.key))
    }

    public static var isOn: Bool {
        preference.reducesMotion(system: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
    }
}

private struct GrailsReduceMotionKey: EnvironmentKey {
    static var defaultValue: Bool { ReduceMotion.isOn }
}

public extension EnvironmentValues {
    /// Reduce Motion as the app resolves it. Set by `grailsMotionRoot()`; outside it, read straight from `ReduceMotion`.
    var grailsReduceMotion: Bool {
        get { self[GrailsReduceMotionKey.self] }
        set { self[GrailsReduceMotionKey.self] = newValue }
    }
}

private struct MotionRoot: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var system
    @AppStorage(GrailsMotionPreference.key) private var stored = GrailsMotionPreference.system.rawValue

    func body(content: Content) -> some View {
        content.environment(\.grailsReduceMotion, GrailsMotionPreference(stored: stored).reducesMotion(system: system))
    }
}

public extension View {
    /// Resolves Reduce Motion once for the window and hands it down. Put it at the root of each window.
    func grailsMotionRoot() -> some View { modifier(MotionRoot()) }
}

// MARK: Animation tokens

public extension Animation {
    private static func eased(_ duration: TimeInterval) -> Animation {
        .timingCurve(Motion.standardCurve.x1, Motion.standardCurve.y1, Motion.standardCurve.x2, Motion.standardCurve.y2, duration: duration)
    }

    /// Hover-out, chip fills, every exit.
    static var grailsQuick: Animation { eased(Motion.quick) }
    /// Crossfades and zoom steps.
    static var grailsStandard: Animation { eased(Motion.standard) }
    /// Preview open and close, page settle.
    static var grailsFlight: Animation { eased(Motion.flight) }
    /// Spatial motion only: a press releasing, a panel or overlay arriving, a toast. A fade never uses it.
    static var grailsSpring: Animation { .spring(duration: Motion.spring, bounce: Motion.bounce) }

    /// The spring with Reduce Motion applied: the same settle, with no bounce.
    static func grailsSpring(reduceMotion: Bool) -> Animation {
        .spring(duration: Motion.spring, bounce: Motion.bounce(reduceMotion: reduceMotion))
    }

    /// A fade or a move with Reduce Motion applied: a short ease instead of the full one.
    static func grails(_ animation: Animation, reduceMotion: Bool) -> Animation { reduceMotion ? .grailsQuick : animation }

    /// The painting wall and the ink band only. Their slow fades are ambient, not chrome; see `Motion.ambientCaption`.
    static func grailsAmbient(_ duration: TimeInterval, reduceMotion: Bool) -> Animation {
        eased(reduceMotion ? Motion.quick : duration)
    }
}

public extension CAMediaTimingFunction {
    /// `Motion.standardCurve` for Core Animation. Every AppKit layer animation eases out on it.
    static var grailsStandard: CAMediaTimingFunction {
        CAMediaTimingFunction(controlPoints: Float(Motion.standardCurve.x1), Float(Motion.standardCurve.y1), Float(Motion.standardCurve.x2), Float(Motion.standardCurve.y2))
    }
}

/// A page switch: the sidebar, a search or a filter swaps what the main area shows. The whole content area crossfades once,
/// on `Motion.standard` and the standard curve. No item has motion of its own, nothing staggers, and Reduce Motion swaps at once.
public enum PageCrossfade {
    /// The one transition for the grid's container layer, added in the same pass that swaps the page. Nil under Reduce Motion.
    public static func transition(reduceMotion: Bool) -> CATransition? {
        guard !reduceMotion else { return nil }
        let fade = CATransition()
        fade.type = .fade
        fade.duration = Motion.standard
        fade.timingFunction = .grailsStandard
        return fade
    }
}

public extension AnyTransition {
    /// What a page shows besides the grid (its empty state): the same crossfade in and out as the grid. Reduce Motion: none.
    static func grailsPageFade(reduceMotion: Bool) -> AnyTransition {
        reduceMotion ? .identity : .opacity.animation(.grailsStandard)
    }

    /// Arrives with the standard fade and leaves with a quick one, so exits are faster than entries. Never bounces.
    static var grailsFade: AnyTransition {
        .asymmetric(insertion: .opacity.animation(.grailsStandard), removal: .opacity.animation(.grailsQuick))
    }

    /// A tag chip: grows in from `Motion.chipScale` on the spring while it fades in on the ease, and shrinks away quickly.
    /// Put `.animation(.grailsSpring(reduceMotion:), value: ids)` on the container so the neighbours reflow on the same spring.
    static func grailsChip(reduceMotion: Bool) -> AnyTransition {
        guard !reduceMotion else { return .grailsFade }
        return .asymmetric(
            insertion: AnyTransition.opacity.animation(.grailsStandard).combined(with: AnyTransition.scale(scale: Motion.chipScale).animation(.grailsSpring)),
            removal: AnyTransition.opacity.animation(.grailsQuick).combined(with: AnyTransition.scale(scale: Motion.chipScale).animation(.grailsQuick))
        )
    }

    /// One picture replacing another in place, such as a shuffled avatar: the new one grows from `Motion.overlayScale` on the spring
    /// while it fades in on the ease, and the old one fades out quickly. Reduce Motion leaves the crossfade.
    static func grailsSwap(reduceMotion: Bool) -> AnyTransition {
        guard !reduceMotion else { return .grailsFade }
        return .asymmetric(
            insertion: AnyTransition.opacity.animation(.grailsStandard).combined(with: AnyTransition.scale(scale: Motion.overlayScale).animation(.grailsSpring)),
            removal: AnyTransition.opacity.animation(.grailsQuick)
        )
    }

    /// A row a section reveals: it drops the last few points into place on the spring while it fades in. Reduce Motion leaves the fade.
    static func grailsReveal(reduceMotion: Bool) -> AnyTransition {
        guard !reduceMotion else { return .grailsFade }
        return .asymmetric(
            insertion: AnyTransition.opacity.animation(.grailsStandard).combined(with: AnyTransition.offset(y: -Motion.revealDrop).animation(.grailsSpring)),
            removal: AnyTransition.opacity.animation(.grailsQuick)
        )
    }

    /// A docked panel sliding in from `x`: the fade eases, the slide springs. Reduce Motion leaves the fade.
    static func grailsSlide(x: CGFloat, reduceMotion: Bool) -> AnyTransition {
        guard !reduceMotion else { return .opacity.animation(.grailsQuick) }
        return .asymmetric(
            insertion: AnyTransition.opacity.animation(.grailsStandard).combined(with: AnyTransition.offset(x: x).animation(.grailsSpring)),
            removal: AnyTransition.opacity.animation(.grailsQuick).combined(with: AnyTransition.offset(x: x).animation(.grailsQuick))
        )
    }
}

// MARK: Entrances

/// A view that grows into place when it appears. The fade and the move run on separate clocks: the fade eases, the move springs.
private struct Entrance: ViewModifier {
    var scale: CGFloat
    var anchor: UnitPoint
    var offset: CGFloat
    var fades: Bool
    var springs: Bool
    @Environment(\.grailsReduceMotion) private var reduceMotion
    @Environment(\.grailsSnapshot) private var snapshot
    @State private var faded = false
    @State private var placed = false

    func body(content: Content) -> some View {
        let still = reduceMotion || snapshot
        content
            .opacity(fades && !faded && !snapshot ? 0 : 1)
            .scaleEffect(placed || still ? 1 : scale, anchor: anchor)
            .offset(y: placed || still ? 0 : offset)
            .onAppear {
                withAnimation(.grails(.grailsStandard, reduceMotion: reduceMotion)) { faded = true }
                withAnimation(springs ? .grailsSpring : .grailsStandard) { placed = true }
            }
    }
}

public extension View {
    /// An overlay card (⌘K, a prompt, a confirm) grows from `anchor` toward full size. Its backdrop and its exit are `grailsFade`.
    func grailsOverlayEntrance(anchor: UnitPoint = .center) -> some View {
        modifier(Entrance(scale: Motion.overlayScale, anchor: anchor, offset: anchor == .top ? -Motion.overlayDrop : 0, fades: false, springs: true))
    }

    /// A toast rises into place. Pair it with `.transition(.grailsFade)`.
    func grailsToastEntrance() -> some View {
        modifier(Entrance(scale: 1, anchor: .bottom, offset: Motion.toastRise, fades: false, springs: true))
    }

    /// A popover's content grows from the side its arrow points at. `arrowEdge` is the one passed to `.popover`.
    func grailsPopoverEntrance(arrowEdge: Edge) -> some View {
        let anchor: UnitPoint = switch arrowEdge {
        case .top: .bottom
        case .bottom: .top
        case .leading: .trailing
        case .trailing: .leading
        }
        return grailsOverlayEntrance(anchor: anchor)
    }

    /// An empty state fades in and rises a little. No bounce: it is not a surface arriving.
    func grailsEmptyEntrance() -> some View {
        modifier(Entrance(scale: 1, anchor: .center, offset: Motion.emptyRise, fades: true, springs: false))
    }
}

// MARK: Press

/// What a press shrinks, and by how much.
public enum GrailsPressTarget: Sendable {
    /// The whole label: a labelled button, a chip.
    case label
    /// A full-width row or a large card.
    case row
    /// A picture tile.
    case tile
    /// A bare glyph with no plate (a ×, a heart): the whole label shrinks as far as an icon button's symbol.
    case icon
    /// Only the symbol inside, which calls `grailsSymbolPress()`; its hover plate stays put.
    case symbol

    public var scale: Double {
        switch self {
        case .label: Motion.pressScale
        case .row: Motion.rowPressScale
        case .tile: Motion.tilePressScale
        case .icon, .symbol: Motion.iconPressScale
        }
    }
}

/// A pressed control shrinks at once and springs back on release. Only the scale animates, so the fill never bounces.
private struct PressScale: ViewModifier {
    var pressed: Bool
    var scale: CGFloat
    @Environment(\.grailsReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.animation(pressed ? nil : .grailsSpring) {
            $0.scaleEffect(pressed && !reduceMotion ? scale : 1)
        }
    }
}

public extension View {
    /// Press feedback for a control: `Motion.pressScale` for a labelled button, `Motion.iconPressScale` for a symbol.
    func grailsPressScale(_ pressed: Bool, scale: Double = Motion.pressScale) -> some View {
        modifier(PressScale(pressed: pressed, scale: CGFloat(scale)))
    }
}

private struct PressedKey: EnvironmentKey {
    static let defaultValue = false
}

public extension EnvironmentValues {
    /// True while the enclosing `GrailsPressStyle(.symbol)` button, or `grailsMenuPress(.symbol)` menu, is held down.
    var grailsPressed: Bool {
        get { self[PressedKey.self] }
        set { self[PressedKey.self] = newValue }
    }
}

/// Applies a press to a label: the whole label scales, or (for `.symbol`) the symbol inside is told and scales itself.
private struct PressedLabel: ViewModifier {
    var target: GrailsPressTarget
    var pressed: Bool

    func body(content: Content) -> some View {
        if target == .symbol {
            content.environment(\.grailsPressed, pressed)
        } else {
            content
                .environment(\.grailsPressed, false)
                .grailsPressScale(pressed, scale: target.scale)
        }
    }
}

/// The press every Grails button goes through. Plain chrome; the label shrinks while held and springs back on release.
/// `.symbol` leaves the label alone and lets an icon inside (`grailsSymbolPress()`) shrink instead.
public struct GrailsPressStyle: ButtonStyle {
    public var target: GrailsPressTarget

    public init(_ target: GrailsPressTarget = .label) { self.target = target }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label.modifier(PressedLabel(target: target, pressed: configuration.isPressed))
    }
}

private struct SymbolPress: ViewModifier {
    @Environment(\.grailsPressed) private var pressed

    func body(content: Content) -> some View { content.grailsPressScale(pressed, scale: Motion.iconPressScale) }
}

public extension View {
    /// The symbol of an icon button, scaled to `Motion.iconPressScale` while its `GrailsPressStyle(.symbol)` button is held.
    func grailsSymbolPress() -> some View { modifier(SymbolPress()) }
}

// MARK: Menu press

/// A `Menu` or a popup `Picker` opens on mouse-down and AppKit then tracks the menu itself, so a `ButtonStyle` never sees the press.
/// This watches the window's mouse-downs instead: the label shrinks the moment it is clicked, and springs back when the menu closes.
private struct MenuPress: ViewModifier {
    var target: GrailsPressTarget
    @State private var pressed = false

    func body(content: Content) -> some View {
        content
            .modifier(PressedLabel(target: target, pressed: pressed))
            .background(MenuPressProbe(pressed: $pressed))
    }
}

private struct MenuPressProbe: NSViewRepresentable {
    @Binding var pressed: Bool

    func makeNSView(context: Context) -> ProbeView {
        let view = ProbeView()
        view.onChange = { pressed = $0 }
        return view
    }

    func updateNSView(_ view: ProbeView, context: Context) { view.onChange = { pressed = $0 } }

    static func dismantleNSView(_ view: ProbeView, coordinator: ()) { view.stop() }

    final class ProbeView: NSView {
        var onChange: ((Bool) -> Void)?
        private var monitor: Any?
        private var observer: NSObjectProtocol?
        private var down = false

        // Never takes the click: the menu underneath does.
        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window == nil { stop() } else { start() }
        }

        private func start() {
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseUp]) { [weak self] event in
                MainActor.assumeIsolated { self?.handle(event) }
                return event
            }
            observer = NotificationCenter.default.addObserver(forName: NSMenu.didEndTrackingNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.release() }
            }
        }

        func stop() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            if let observer { NotificationCenter.default.removeObserver(observer) }
            monitor = nil
            observer = nil
            release()
        }

        private func handle(_ event: NSEvent) {
            switch event.type {
            case .leftMouseDown:
                guard event.window === window, !isHiddenOrHasHiddenAncestor, bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
                down = true
                onChange?(true)
            case .leftMouseUp:
                release()
            default:
                break
            }
        }

        private func release() {
            guard down else { return }
            down = false
            onChange?(false)
        }
    }
}

public extension View {
    /// Press feedback for a control that opens a menu: a `Menu` label, a popup `Picker`. `GrailsMenu` already has it.
    func grailsMenuPress(_ target: GrailsPressTarget = .label) -> some View { modifier(MenuPress(target: target)) }
}

/// A menu behind a label, with the Grails press: the label is drawn as is (no system bezel or arrow) and shrinks when clicked.
public struct GrailsMenu<Content: View, Label: View>: View {
    var press: GrailsPressTarget
    var content: () -> Content
    var label: () -> Label

    public init(press: GrailsPressTarget = .symbol, @ViewBuilder content: @escaping () -> Content, @ViewBuilder label: @escaping () -> Label) {
        self.press = press
        self.content = content
        self.label = label
    }

    public var body: some View {
        Menu(content: content, label: label)
            .menuStyle(.button) // menu press: the label is drawn as is
            .buttonStyle(.plain) // menu press: the probe below presses the label, the menu's own button stays plain
            .menuIndicator(.hidden)
            .fixedSize()
            .grailsMenuPress(press)
    }
}

// MARK: Tap press

/// A row that acts on a tap (a gesture, not a `Button`, so a nested control or a drag still works) gets the same press.
private struct TapPress: ViewModifier {
    var target: GrailsPressTarget
    var action: () -> Void
    @GestureState private var pressed = false

    func body(content: Content) -> some View {
        content
            .modifier(PressedLabel(target: target, pressed: pressed))
            .onTapGesture(perform: action)
            .simultaneousGesture(
                LongPressGesture(minimumDuration: 60, maximumDistance: 4).updating($pressed) { holding, state, _ in state = holding }
            )
    }
}

public extension View {
    /// `onTapGesture` with the Grails press. Moving more than a few points lets go, so a drag never looks pressed.
    func grailsTapPress(_ target: GrailsPressTarget = .row, perform action: @escaping () -> Void) -> some View {
        modifier(TapPress(target: target, action: action))
    }
}

// MARK: Selection

private struct SelectionAnchorKey: PreferenceKey {
    static let defaultValue: Anchor<CGRect>? = nil
    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) { value = value ?? nextValue() }
}

/// One indicator for a whole group (tabs, segments, sidebar rows). It sits under the selected view and springs to the next one.
/// Appearing or disappearing is a plain fade. Reduce Motion moves it without the glide.
private struct SelectionTrack<Indicator: View>: ViewModifier {
    var indicator: () -> Indicator

    func body(content: Content) -> some View {
        content
            .backgroundPreferenceValue(SelectionAnchorKey.self) { anchor in
                GeometryReader { proxy in
                    SelectionIndicator(rect: anchor.map { proxy[$0] }, indicator: indicator)
                }
            }
            .transformPreference(SelectionAnchorKey.self) { $0 = nil }
    }
}

private struct SelectionIndicator<Indicator: View>: View {
    var rect: CGRect?
    var indicator: () -> Indicator
    @Environment(\.grailsReduceMotion) private var reduceMotion
    @Environment(\.grailsSnapshot) private var snapshot
    @State private var frame: CGRect = .zero
    @State private var shown = false

    var body: some View {
        let placed = snapshot ? (rect ?? .zero) : frame
        indicator()
            .frame(width: placed.width, height: placed.height)
            .offset(x: placed.minX, y: placed.minY)
            .opacity((snapshot ? rect != nil : shown) ? 1 : 0)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .onAppear { place(rect, glide: false) }
            .onChange(of: rect) { _, new in place(new, glide: true) }
    }

    private func place(_ new: CGRect?, glide: Bool) {
        guard let new else {
            withAnimation(.grailsQuick) { shown = false }
            return
        }
        if glide, shown, !reduceMotion {
            withAnimation(.grailsSpring) { frame = new }
        } else {
            var still = Transaction()
            still.disablesAnimations = true
            withTransaction(still) { frame = new }
            if !shown { withAnimation(.grailsStandard) { shown = true } }
        }
    }
}

public extension View {
    /// Marks this view as the selected one inside a `grailsSelectionTrack`.
    func grailsSelectionTarget(_ selected: Bool) -> some View {
        anchorPreference(key: SelectionAnchorKey.self, value: .bounds) { selected ? $0 : nil }
    }

    /// Draws `indicator` under whichever child is marked with `grailsSelectionTarget(true)`, and springs it between them.
    func grailsSelectionTrack<Indicator: View>(@ViewBuilder indicator: @escaping () -> Indicator) -> some View {
        modifier(SelectionTrack(indicator: indicator))
    }
}

// MARK: Disclosure and pop

/// Runs a change on the spring, with Reduce Motion applied: a section folding, a list reordering.
@MainActor public func withGrailsSpring<Result>(_ body: () throws -> Result) rethrows -> Result {
    try withAnimation(.grailsSpring(reduceMotion: ReduceMotion.isOn), body)
}

/// The chevron in front of a section you can fold. It turns on the spring rather than swapping icons.
public struct GrailsDisclosureChevron: View {
    var expanded: Bool
    var size: CGFloat
    var weight: Font.Weight
    @Environment(\.grailsReduceMotion) private var reduceMotion

    public init(expanded: Bool, size: CGFloat = 10, weight: Font.Weight = .semibold) {
        self.expanded = expanded
        self.size = size
        self.weight = weight
    }

    public var body: some View {
        Image(systemName: ChromeIcon.chevronRight)
            .font(ChromeFont.symbol(size, weight: weight))
            .rotationEffect(.degrees(expanded ? 90 : 0))
            .animation(.grailsSpring(reduceMotion: reduceMotion), value: expanded)
    }
}

/// Something small that appears in place (a radio dot, a checkmark): it grows on the spring and fades on the ease.
private struct Pop: ViewModifier {
    var shown: Bool
    @Environment(\.grailsReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .animation(.grails(.grailsStandard, reduceMotion: reduceMotion)) { $0.opacity(shown ? 1 : 0) }
            .animation(.grailsSpring) { $0.scaleEffect(shown || reduceMotion ? 1 : Motion.chipScale) }
    }
}

public extension View {
    /// Shows or hides this view in place with a pop. It keeps its layout space either way.
    func grailsPop(_ shown: Bool) -> some View { modifier(Pop(shown: shown)) }
}

// MARK: Toggle

/// A checkbox in the Grails ink. The box presses like an icon button and the check pops in.
public struct GrailsToggleStyle: ToggleStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        Button { configuration.isOn.toggle() } label: {
            HStack(spacing: 7) {
                ToggleBox(on: configuration.isOn).grailsSymbolPress()
                configuration.label
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(GrailsPressStyle(.symbol))
        .focusEffectDisabled()
        .accessibilityValue(configuration.isOn ? "On" : "Off")
    }
}

private struct ToggleBox: View {
    var on: Bool

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 4, style: .continuous)
        shape
            .fill(on ? GrailsColor.text : GrailsColor.surface)
            .overlay(shape.strokeBorder(on ? GrailsInk(.canvas, opacity: 0) : GrailsColor.token(ChromeRole.fieldBorder), lineWidth: 1))
            .overlay {
                Image(systemName: "checkmark")
                    .font(ChromeFont.symbol(9, weight: .bold))
                    .foregroundStyle(GrailsColor.canvas)
                    .grailsPop(on)
            }
            .frame(width: 14, height: 14)
            .animation(.grailsQuick, value: on)
    }
}

// MARK: AppKit press

/// The same press for AppKit views: the layer shrinks about its centre at once and springs back on release.
@MainActor public enum LayerPress {
    private static let key = "grailsPress"

    public static func press(_ view: NSView, scale: Double = Motion.pressScale) {
        guard !ReduceMotion.isOn else { return }
        view.wantsLayer = true
        guard let layer = view.layer else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.removeAnimation(forKey: key)
        layer.transform = centred(scale, in: layer)
        CATransaction.commit()
    }

    public static func release(_ view: NSView) {
        guard let layer = view.layer, !CATransform3DIsIdentity(layer.transform) else { return }
        let from = layer.presentation()?.transform ?? layer.transform
        let spring = CASpringAnimation(keyPath: "transform")
        spring.mass = 1
        spring.stiffness = Motion.springStiffness()
        spring.damping = Motion.springDamping(reduceMotion: ReduceMotion.isOn)
        spring.fromValue = NSValue(caTransform3D: from)
        spring.toValue = NSValue(caTransform3D: CATransform3DIdentity)
        spring.duration = spring.settlingDuration
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.transform = CATransform3DIdentity
        CATransaction.commit()
        layer.add(spring, forKey: key)
    }

    /// A scale about the layer's centre, whatever its anchor point (AppKit puts it at the corner).
    private static func centred(_ scale: Double, in layer: CALayer) -> CATransform3D {
        let dx = (0.5 - layer.anchorPoint.x) * layer.bounds.width
        let dy = (0.5 - layer.anchorPoint.y) * layer.bounds.height
        var t = CATransform3DMakeTranslation(dx, dy, 0)
        t = CATransform3DScale(t, scale, scale, 1)
        return CATransform3DTranslate(t, -dx, -dy, 0)
    }
}

/// An AppKit button with the Grails press. `NSButton` tracks the mouse itself, so the press is set before tracking and released after.
public final class GrailsPressButton: NSButton {
    public var pressScale = Motion.iconPressScale

    public override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return super.mouseDown(with: event) }
        LayerPress.press(self, scale: pressScale)
        CATransaction.flush()
        super.mouseDown(with: event)
        LayerPress.release(self)
    }
}

// MARK: Sheets and popovers

// `grailsSheet` lives in ModalLayer.swift: every modal goes through the one stack there.

public extension View {
    /// `.popover` whose content grows from its anchor on the spring.
    func grailsPopover<Content: View>(isPresented: Binding<Bool>, arrowEdge: Edge = .top, @ViewBuilder content: @escaping () -> Content) -> some View {
        modifier(GrailsPopoverModifier(isPresented: isPresented, arrowEdge: arrowEdge, popoverContent: content))
    }
}

/// Wraps `.popover` in a concrete modifier so Release builds don't need SwiftUI's opaque popover type across modules.
private struct GrailsPopoverModifier<PopoverContent: View>: ViewModifier {
    @Binding var isPresented: Bool
    let arrowEdge: Edge
    let popoverContent: () -> PopoverContent

    func body(content: Content) -> some View {
        content.popover(isPresented: $isPresented, arrowEdge: arrowEdge) {
            AnyView(popoverContent().grailsPopoverEntrance(arrowEdge: arrowEdge))
        }
    }
}
