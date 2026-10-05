import AppKit
import GrailsDesign
import SwiftUI

/// The look: flat and quiet, Are.na's greys. Pictures are the only colour; chrome is solid surfaces with hairline edges and one
/// signal colour for focus. Values live in GrailsDesign (`Palette`); here they become dynamic colours that follow light and dark.

extension NSColor {
    /// A token as a colour that resolves itself for whichever appearance it is drawn in.
    static func ink(_ token: Token) -> NSColor {
        NSColor(name: nil) { appearance in
            let dark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let c = Palette.rgb(token, dark: dark)
            return NSColor(srgbRed: c.r, green: c.g, blue: c.b, alpha: 1)
        }
    }

    /// For CALayers, which don't follow appearance by themselves: the colour as it looks in `view`'s appearance right now.
    func cgColor(in view: NSView) -> CGColor {
        var out = cgColor
        view.effectiveAppearance.performAsCurrentDrawingAppearance { out = self.cgColor }
        return out
    }

    /// On top of pictures (captions, badges, the heart): readable on any image, in either theme.
    static let onImage = NSColor.white
    static let onImageScrim = NSColor.black.withAlphaComponent(0.58)
}

enum Ink {
    static let canvas = Color(nsColor: .ink(.canvas))
    static let surface = Color(nsColor: .ink(.surface))
    static let fill = Color(nsColor: .ink(.fill))
    static let fillHover = Color(nsColor: .ink(.fillStrong))
    static let hairline = Color(nsColor: .ink(.hairline))
    static let text = Color(nsColor: .ink(.text))
    static let link = Color(nsColor: .ink(.link))
    static let secondary = Color(nsColor: .ink(.secondary))
    static let tertiary = Color(nsColor: .ink(.tertiary))
    static let focus = Color(nsColor: .ink(.focus))
    static let positive = Color(nsColor: .ink(.positive))
    static let destructive = Color(nsColor: .ink(.destructive))
    static let alert = Color(nsColor: .ink(.alert))

    /// Controls and bar buttons, chips, menus and cards, tiles.
    static let radius: CGFloat = 4
    static let chipRadius: CGFloat = 3
    static let cardRadius: CGFloat = 6
    static let tileRadius: CGFloat = 3
}

/// A card that floats over content (palette, dialogs, recent searches): a hairline edge and, only here, a shadow.
private struct SurfaceCard: ViewModifier {
    var radius: CGFloat
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        content
            .background(Ink.surface, in: shape)
            .overlay(shape.strokeBorder(Ink.hairline, lineWidth: 1))
            .shadow(color: .black.opacity(scheme == .dark ? 0.5 : 0.08), radius: scheme == .dark ? 12 : 10, y: scheme == .dark ? 8 : 0)
    }
}

extension View {
    func surfaceCard(radius: CGFloat = Ink.cardRadius) -> some View { modifier(SurfaceCard(radius: radius)) }

    /// A small rectangular chip background.
    func chipSurface(selected: Bool = false) -> some View {
        self.background(selected ? Ink.fillHover : Ink.fill, in: RoundedRectangle(cornerRadius: Ink.chipRadius, style: .continuous))
    }

    /// Hover in is immediate; hover out eases for a tenth of a second.
    func hoverState(_ hovering: Binding<Bool>) -> some View {
        onHover { inside in
            if inside { hovering.wrappedValue = true } else { withAnimation(.easeOut(duration: Motion.quick)) { hovering.wrappedValue = false } }
        }
    }
}

/// An icon that brightens under the pointer; the building block of every bar button.
struct BarIcon: View {
    let symbol: String
    var active = false
    var size: CGFloat = 28
    @State private var hovering = false

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 14, weight: .regular))
            .foregroundStyle(active || hovering ? Ink.text : Ink.secondary)
            .frame(width: size, height: size)
            .background(RoundedRectangle(cornerRadius: Ink.radius, style: .continuous).fill(active ? Ink.fillHover : (hovering ? Ink.fill : .clear)))
            .contentShape(RoundedRectangle(cornerRadius: Ink.radius, style: .continuous))
            .hoverState($hovering)
    }
}

/// A button in the bar.
struct BarButton: View {
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

/// The one filled button: text on black in light, black on white in dark (Are.na's own call-to-action).
struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.grailsBody(13))
            .foregroundStyle(Ink.canvas)
            .padding(.horizontal, 12).frame(height: 28)
            .background(Ink.text.opacity(enabled ? (configuration.isPressed ? 0.8 : 1) : 0.3), in: RoundedRectangle(cornerRadius: Ink.radius, style: .continuous))
    }
}

private struct OptionalIdentifier: ViewModifier {
    let id: String?
    func body(content: Content) -> some View { if let id { content.accessibilityIdentifier(id) } else { content } }
}

/// The search field: an NSSearchField underneath (so it behaves like one everywhere, including accessibility).
struct SearchField: NSViewRepresentable {
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
        f.font = .grailsBody(13)
        f.textColor = .ink(.text)
        f.placeholderAttributedString = NSAttributedString(
            string: "Search", attributes: [.foregroundColor: NSColor.ink(.secondary), .font: NSFont.grailsBody(13)])
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
        var parent: SearchField
        var lastTick: Int
        init(_ p: SearchField) { parent = p; lastTick = p.focusTick }

        func controlTextDidChange(_ obj: Notification) {
            if let f = obj.object as? NSSearchField, parent.text != f.stringValue { parent.text = f.stringValue }
        }
        func controlTextDidBeginEditing(_ obj: Notification) {
            parent.isFocused = true
            (obj.userInfo?["NSFieldEditor"] as? NSTextView)?.insertionPointColor = .ink(.focus)
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
            w.backgroundColor = .ink(.canvas)
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
        static let barCenterY: CGFloat = 22
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
