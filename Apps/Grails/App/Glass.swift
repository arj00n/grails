import AppKit
import SwiftUI

/// The look: black, glass, white as the only accent. Chrome floats over content; nothing is boxed in.

enum Ink {
    static let canvas = Color.black
    static let hairline = Color.white.opacity(0.10)
    static let fill = Color.white.opacity(0.06)
    static let fillHover = Color.white.opacity(0.12)
    static let text = Color.white.opacity(0.92)
    static let secondary = Color.white.opacity(0.55)
    static let tertiary = Color.white.opacity(0.32)
}

extension View {
    /// A dark glass surface: real Liquid Glass where the OS has it, a frosted material elsewhere.
    @ViewBuilder
    func glass<S: InsettableShape>(in shape: S, interactive: Bool = false) -> some View {
        if GlassSettings.flat {
            self.background(Color(white: 0.10, opacity: 0.92), in: shape)
                .overlay(shape.strokeBorder(Ink.hairline, lineWidth: 0.75))
        } else if #available(macOS 26.0, *) {
            if interactive {
                self.background(Ink.fill, in: shape)
                    .glassEffect(Glass.regular.tint(Color.black.opacity(0.35)).interactive(), in: shape)
                    .overlay(shape.strokeBorder(Ink.hairline, lineWidth: 0.75))
            } else {
                self.background(Ink.fill, in: shape)
                    .glassEffect(Glass.regular.tint(Color.black.opacity(0.35)), in: shape)
                    .overlay(shape.strokeBorder(Ink.hairline, lineWidth: 0.75))
            }
        } else {
            self.background(.ultraThinMaterial, in: shape)
                .background(Color.black.opacity(0.35), in: shape)
                .overlay(shape.strokeBorder(Ink.hairline, lineWidth: 0.75))
        }
    }

    func glassCard(radius: CGFloat = 22) -> some View {
        self.glass(in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .shadow(color: .black.opacity(0.45), radius: 30, y: 12)
    }

    func glassPill(interactive: Bool = false) -> some View { self.glass(in: Capsule(), interactive: interactive) }
}

/// A round icon button that lives in the floating chrome.
struct GlassIconButton: View {
    let symbol: String
    var selected = false
    var help: String = ""
    var identifier: String?
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(selected || hovering ? Ink.text : Ink.secondary)
                .frame(width: 34, height: 34)
                .background(selected ? Ink.fillHover : (hovering ? Ink.fill : .clear), in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help)
        .accessibilityLabel(help)
        .modifier(OptionalIdentifier(id: identifier))
    }
}

private struct OptionalIdentifier: ViewModifier {
    let id: String?
    func body(content: Content) -> some View { if let id { content.accessibilityIdentifier(id) } else { content } }
}

/// The search pill: an NSSearchField underneath (so it behaves like one everywhere, including accessibility).
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
        // cursor ends up underneath it. The pill draws its own icon and clear button instead.
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

/// Where the window's traffic lights sit, so the floating top bar can line up with them instead of guessing.
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

        /// The floating bar's centre line (also where the traffic lights are moved to) and the left edge their group starts at.
        static let barCenterY: CGFloat = 30
        static let leftInset: CGFloat = 14

        private func measure() {
            guard let w = window, let close = w.standardWindowButton(.closeButton), let mini = w.standardWindowButton(.miniaturizeButton),
                  let zoom = w.standardWindowButton(.zoomButton) else { return }
            let m = ChromeMetrics.shared
            let full = w.styleMask.contains(.fullScreen)
            func rect(_ b: NSButton) -> CGRect { b.superview?.convert(b.frame, to: nil) ?? .zero }
            if !full, close.superview != nil {
                // Sit the traffic lights on the same centre line as the bar's pills, and a little in from the corner.
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

enum GlassSettings {
    static let flat = ProcessInfo.processInfo.environment["GRAILS_FLAT_GLASS"] != nil
}
