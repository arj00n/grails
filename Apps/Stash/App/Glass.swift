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
        func controlTextDidBeginEditing(_ obj: Notification) { parent.isFocused = true }
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
        }
    }
}

enum GlassSettings {
    static let flat = ProcessInfo.processInfo.environment["STASH_FLAT_GLASS"] != nil
}
