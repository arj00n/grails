import AppKit
import SwiftUI

/// The look: flat. Black underneath, solid surfaces with hairline edges, white as the only accent. Nothing blurs or floats;
/// panels are docked, and the life is in the hover fills and the small symbol animations.

enum Ink {
    static let canvas = Color.black
    static let surface = Color(white: 0.06)
    static let raised = Color(white: 0.10)
    static let hairline = Color.white.opacity(0.09)
    static let fill = Color.white.opacity(0.06)
    static let fillHover = Color.white.opacity(0.12)
    static let text = Color.white.opacity(0.92)
    static let secondary = Color.white.opacity(0.55)
    static let tertiary = Color.white.opacity(0.32)
    static let radius: CGFloat = 8
}

extension View {
    /// A flat dark surface with a hairline edge.
    func glass<S: InsettableShape>(in shape: S, interactive: Bool = false) -> some View {
        self.background(Ink.raised, in: shape)
            .overlay(shape.strokeBorder(Ink.hairline, lineWidth: 1))
    }

    /// Menus, dialogs and the palette: a raised flat card.
    func glassCard(radius: CGFloat = 12) -> some View {
        self.glass(in: RoundedRectangle(cornerRadius: min(radius, 12), style: .continuous))
            .shadow(color: .black.opacity(0.35), radius: 14, y: 6)
    }

    func glassPill(interactive: Bool = false) -> some View { self.glass(in: RoundedRectangle(cornerRadius: Ink.radius, style: .continuous)) }
}

/// An icon that brightens and gives a small bounce under the pointer; the building block of every bar button.
struct BarIcon: View {
    let symbol: String
    var active = false
    var size: CGFloat = 30
    @State private var hovering = false
    @State private var bump = 0

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 14, weight: .medium))
            .symbolEffect(.bounce, options: .speed(1.4), value: bump)
            .symbolEffect(.bounce, options: .speed(1.4), value: active)
            .foregroundStyle(active || hovering ? Ink.text : Ink.secondary)
            .frame(width: size, height: size)
            .background(RoundedRectangle(cornerRadius: Ink.radius, style: .continuous).fill(active ? Ink.fillHover : (hovering ? Ink.fill : .clear)))
            .contentShape(RoundedRectangle(cornerRadius: Ink.radius, style: .continuous))
            .onHover { h in hovering = h; if h { bump += 1 } }
            .animation(.easeOut(duration: 0.14), value: hovering)
            .animation(.easeOut(duration: 0.14), value: active)
    }
}

/// A button in the bar.
struct GlassIconButton: View {
    let symbol: String
    var selected = false
    var help: String = ""
    var identifier: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) { BarIcon(symbol: symbol, active: selected) }
            .buttonStyle(.plain)
            .help(help)
            .accessibilityLabel(help)
            .modifier(OptionalIdentifier(id: identifier))
    }
}

private struct OptionalIdentifier: ViewModifier {
    let id: String?
    func body(content: Content) -> some View { if let id { content.accessibilityIdentifier(id) } else { content } }
}

/// The search field: an NSSearchField underneath (so it behaves like one everywhere, including accessibility).
struct GlassSearchField: NSViewRepresentable {
    @Binding var text: String
    var focusTick: Int
    @Binding var isFocused: Bool
    var onSubmit: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSSearchField {
        let f = NSSearchField()
        f.isBordered = false
        f.drawsBackground = false
        f.focusRingType = .none
        // The cell's own magnifier and clear button don't track the text when the field is focused: the icon stays put and the
        // cursor ends up underneath it. The bar draws its own icon and clear button instead.
        if let cell = f.cell as? NSSearchFieldCell { cell.searchButtonCell = nil; cell.cancelButtonCell = nil }
        f.font = .systemFont(ofSize: 14)
        f.textColor = NSColor.white.withAlphaComponent(0.92)
        f.placeholderAttributedString = NSAttributedString(
            string: "Search", attributes: [.foregroundColor: NSColor.white.withAlphaComponent(0.38), .font: NSFont.systemFont(ofSize: 14)])
        f.sendsSearchStringImmediately = true
        f.delegate = context.coordinator
        f.setAccessibilityIdentifier("search-field")
        f.setAccessibilityLabel("Search library")
        return f
    }

    func updateNSView(_ f: NSSearchField, context: Context) {
        context.coordinator.parent = self
        if f.stringValue != text { f.stringValue = text }
        if context.coordinator.lastTick != focusTick {
            context.coordinator.lastTick = focusTick
            DispatchQueue.main.async { f.window?.makeFirstResponder(f) }
        }
    }

    final class Coordinator: NSObject, NSSearchFieldDelegate {
        var parent: GlassSearchField
        var lastTick: Int
        init(_ p: GlassSearchField) { parent = p; lastTick = p.focusTick }

        func controlTextDidChange(_ obj: Notification) {
            if let f = obj.object as? NSSearchField, parent.text != f.stringValue { parent.text = f.stringValue }
        }
        func controlTextDidBeginEditing(_ obj: Notification) {
            parent.isFocused = true
            (obj.userInfo?["NSFieldEditor"] as? NSTextView)?.insertionPointColor = .white
        }
        func controlTextDidEndEditing(_ obj: Notification) { parent.isFocused = false }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy sel: Selector) -> Bool {
            switch sel {
            case #selector(NSResponder.insertNewline(_:)): parent.onSubmit(); return false
            case #selector(NSResponder.cancelOperation(_:)):
                if !parent.text.isEmpty { parent.text = "" }
                control.window?.makeFirstResponder(nil)      // hand the keyboard back to the grid or canvas
                return true
            default: return false
            }
        }
    }
}

/// Where the window's traffic lights sit, so the top bar can line up with them instead of guessing.
@MainActor @Observable
final class ChromeMetrics {
    static let shared = ChromeMetrics()
    /// Distance from the top of the window to the centre of the traffic lights.
    var centerY: CGFloat = 26
    /// Where the first control can start: just past the zoom button (or the edge in full screen).
    var leading: CGFloat = 86
}

/// Makes the window all content: no title bar, black underneath, draggable from any empty spot.
struct WindowChrome: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { Anchor() }
    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class Anchor: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let w = window else { return }
            w.titleVisibility = .hidden
            w.titlebarAppearsTransparent = true
            w.styleMask.insert(.fullSizeContentView)
            w.isMovableByWindowBackground = true
            w.backgroundColor = .black
            w.toolbar = nil
            measure()
            for name in [NSWindow.didResizeNotification, NSWindow.didEnterFullScreenNotification, NSWindow.didExitFullScreenNotification, NSWindow.didBecomeKeyNotification] {
                observers.append(NotificationCenter.default.addObserver(forName: name, object: w, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.measure() }
                })
            }
        }

        private var observers: [NSObjectProtocol] = []

        /// The top bar's centre line (also where the traffic lights are moved to) and the left edge their group starts at.
        static let barCenterY: CGFloat = 26
        static let leftInset: CGFloat = 14

        private func measure() {
            guard let w = window, let close = w.standardWindowButton(.closeButton), let mini = w.standardWindowButton(.miniaturizeButton),
                  let zoom = w.standardWindowButton(.zoomButton) else { return }
            let m = ChromeMetrics.shared
            let full = w.styleMask.contains(.fullScreen)
            func rect(_ b: NSButton) -> CGRect { b.superview?.convert(b.frame, to: nil) ?? .zero }
            if !full, close.superview != nil {
                // Sit the traffic lights on the same centre line as the bar's controls, and a little in from the corner.
                let c = rect(close)
                let dy = Self.barCenterY - (w.frame.height - c.midY)
                let dx = Self.leftInset - c.minX
                if abs(dy) > 0.5 || abs(dx) > 0.5 {
                    let flipped = close.superview?.isFlipped == true
                    for b in [close, mini, zoom] { b.setFrameOrigin(NSPoint(x: b.frame.origin.x + dx, y: b.frame.origin.y + (flipped ? dy : -dy))) }
                }
            }
            let c = rect(close), z = rect(zoom)
            if c != .zero { m.centerY = max(w.frame.height - c.midY, 12) }
            m.leading = full || z == .zero ? 14 : z.maxX + 16
            if ProcessInfo.processInfo.environment["GRAILS_LOG_CHROME"] != nil { FileHandle.standardError.write(Data("CHROME centerY=\(m.centerY) leading=\(m.leading) close=\(c) zoom=\(z)\n".utf8)) }
        }
    }
}
