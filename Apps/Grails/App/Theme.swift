import AppKit
import GrailsDesign
import SwiftUI

/// The look: flat and quiet. Pictures are the colour. A status dot is the only other hue. Values live in GrailsDesign (`Palette`).

extension NSColor {
    /// A token as a colour that resolves itself for whichever appearance it is drawn in.
    static func ink(_ token: Token) -> NSColor {
        GrailsNSColor.token(token)
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

enum AppearanceChoice {
    /// GRAILS_APPEARANCE=light|dark forces this launch only. It does not write the person's setting.
    static var proof: ColorScheme? {
        switch ProcessInfo.processInfo.environment["GRAILS_APPEARANCE"] {
        case "light": .light
        case "dark": .dark
        default: nil
        }
    }

    static func scheme(stored: String) -> ColorScheme? {
        if let proof { return proof }
        switch stored {
        case "light": return .light
        case "dark": return .dark
        default: return nil
        }
    }
}

enum Ink {
    static let canvas = GrailsInk(.canvas)
    static let surface = GrailsInk(.surface)
    static let fill = GrailsInk(.fill)
    static let fillHover = GrailsInk(.fillStrong)
    static let hairline = GrailsInk(.hairline)
    static let text = GrailsInk(.text)
    static let link = GrailsInk(.link)
    static let secondary = GrailsInk(.secondary)
    static let tertiary = GrailsInk(.tertiary)
    static let focus = GrailsInk(.focus)
    static let positive = GrailsInk(.positive)
    static let destructive = GrailsInk(.destructive)
    static let alert = GrailsInk(.alert)
    static let sidebar = GrailsInk(.sidebar)
    static let separator = GrailsInk(.separator)
    static let avatar = GrailsInk(.avatar)
    static let clear = GrailsInk(.canvas, opacity: 0)

    /// Controls and bar buttons, chips, menus and cards, tiles. Same numbers as `RadiusToken`.
    static let radius: CGFloat = RadiusToken.control
    static let chipRadius: CGFloat = RadiusToken.chip
    static let cardRadius: CGFloat = RadiusToken.card
    static let tileRadius: CGFloat = RadiusToken.tile
    static let sidebarRadius: CGFloat = RadiusToken.sidebarItem
    static let rowRadius: CGFloat = RadiusToken.row
}

/// A token drawn as a view, so it can ignore the safe area. `GrailsInk` itself is only a fill.
struct InkWash: View {
    var ink: GrailsInk
    var body: some View { Rectangle().fill(ink) }
}

/// A card that floats over content (palette, dialogs). The shadow is on the plate only, so a row hover inside stays flat.
private struct SurfaceCard: ViewModifier {
    var radius: CGFloat
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        content
            .background {
                shape
                    .fill(Ink.surface)
                    .overlay(shape.strokeBorder(Ink.hairline, lineWidth: 1))
                    .shadow(color: .black.opacity(scheme == .dark ? 0.5 : 0.08), radius: scheme == .dark ? 12 : 10, y: scheme == .dark ? 8 : 0)
            }
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
            if inside { hovering.wrappedValue = true } else { withAnimation(.grailsQuick) { hovering.wrappedValue = false } }
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
            .font(ChromeFont.symbol(14, weight: .regular))
            .foregroundStyle(active || hovering ? Ink.text : Ink.secondary)
            .grailsSymbolPress()
            .frame(width: size, height: size)
            .background(RoundedRectangle(cornerRadius: Ink.radius, style: .continuous).fill(active ? Ink.fillHover : (hovering ? Ink.fill : Ink.clear)))
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
        GrailsControl(press: .symbol, action: action) { BarIcon(symbol: symbol, active: selected) }
            .help(help)
            .accessibilityLabel(help)
            .modifier(OptionalIdentifier(id: identifier))
    }
}

private struct OptionalIdentifier: ViewModifier {
    let id: String?
    func body(content: Content) -> some View { if let id { content.accessibilityIdentifier(id) } else { content } }
}

/// Where the window's traffic lights sit, so the top bar can line up with them instead of guessing.
/// Named apart from `ChromeMetrics`, which is the design token. An app type of that name hides the token.
@MainActor @Observable
final class TrafficLightMetrics {
    static let shared = TrafficLightMetrics()
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
            // the library window: where a modal goes when no window of ours is key
            GrailsModalLayer.shared.home = w
            w.titleVisibility = .hidden
            w.titlebarAppearsTransparent = true
            w.titlebarSeparatorStyle = .none
            w.styleMask.insert(.fullSizeContentView)
            w.isMovableByWindowBackground = true
            w.backgroundColor = .ink(.canvas)
            w.toolbar = nil
            measure()
            for name in [NSWindow.didResizeNotification, NSWindow.didEnterFullScreenNotification, NSWindow.didExitFullScreenNotification, NSWindow.didBecomeKeyNotification] {
                observers.append(NotificationCenter.default.addObserver(forName: name, object: w, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated {
                        self?.stripToolbar()
                        self?.measure()
                    }
                })
            }
            DispatchQueue.main.async { [weak self] in self?.stripToolbar() }
        }

        override func layout() {
            super.layout()
            stripToolbar()
        }

        /// SwiftUI can reinstall an empty toolbar; the scroll pocket is the same hover strip above a column.
        private func stripToolbar() {
            guard let w = window else { return }
            if w.titlebarSeparatorStyle != .none { w.titlebarSeparatorStyle = .none }
            if w.toolbar != nil { w.toolbar = nil }
            if let content = w.contentView { hideTitlebarScrollPocket(content) }
        }

        private var observers: [NSObjectProtocol] = []

        /// The top bar's centre line (also where the traffic lights are moved to) and the left edge their group starts at.
        static let barCenterY: CGFloat = 22
        static let leftInset: CGFloat = 14

        private func measure() {
            guard let w = window, let close = w.standardWindowButton(.closeButton), let mini = w.standardWindowButton(.miniaturizeButton),
                  let zoom = w.standardWindowButton(.zoomButton) else { return }
            let m = TrafficLightMetrics.shared
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

/// The system scroll pocket is the grey bar beside a sidebar, under the titlebar. It highlights on hover and draws a line.
func hideTitlebarScrollPocket(_ view: NSView) {
    if String(describing: type(of: view)) == "NSScrollPocket" {
        if !view.isHidden { view.isHidden = true }
        return
    }
    if view is NSClipView { return }
    for subview in view.subviews { hideTitlebarScrollPocket(subview) }
}
