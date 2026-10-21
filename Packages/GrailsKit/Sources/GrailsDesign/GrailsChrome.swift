import AppKit
import CoreText
import SwiftUI

private struct ChromeIdentifier: ViewModifier {
    var id: String
    @ViewBuilder func body(content: Content) -> some View {
        if id.isEmpty { content } else { content.accessibilityIdentifier(id) }
    }
}

public extension View {
    /// Keyboard focus without the macOS blue ring. Text fields draw the grey ring themselves.
    func grailsFocusable() -> some View {
        focusable().focusEffectDisabled()
    }
}

/// First responder for a custom control. The system focus ring stays off; the view still receives keyDown.
open class GrailsKeyView: NSView {
    public var onKey: ((UInt16) -> Bool)?

    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        focusRingType = .none
    }

    public required init?(coder: NSCoder) { nil }

    public override var acceptsFirstResponder: Bool { true }

    public override var focusRingType: NSFocusRingType {
        get { .none }
        set {}
    }

    open override func keyDown(with event: NSEvent) {
        if onKey?(event.keyCode) == true { return }
        super.keyDown(with: event)
    }

    public func claimFocus() {
        focusRingType = .none
        guard let window else { return }
        if !window.isKeyWindow { window.makeKey() }
        if window.firstResponder !== self {
            window.makeFirstResponder(self)
        }
    }
}

public enum ChromeFont {
    public static func body(_ size: Double, bold: Bool = false) -> Font {
        .custom(bold ? Typography.bodyBoldName : Typography.bodyName, fixedSize: size)
    }

    public static func display(_ size: Double) -> Font {
        .custom(Typography.displayName, fixedSize: size)
    }

    /// SF Symbols only. Text uses `body` or `display`.
    public static func symbol(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight)
    }
}

public enum ChromeNSFont {
    public static func body(_ size: CGFloat, bold: Bool = false) -> NSFont {
        NSFont(name: bold ? Typography.bodyBoldName : Typography.bodyName, size: size) ?? .systemFont(ofSize: size, weight: bold ? .bold : .regular)
    }

    public static func display(_ size: CGFloat) -> NSFont {
        NSFont(name: Typography.displayName, size: size) ?? .monospacedSystemFont(ofSize: size, weight: .regular)
    }
}

public enum GrailsNSColor {
    /// One dynamic colour per token, made once. Each holds its light and dark colours ready, so resolving it while drawing is a
    /// lookup, not a new colour from the palette every frame.
    public static func token(_ token: Token) -> NSColor { tokens[token]! }

    nonisolated(unsafe) private static let tokens: [Token: NSColor] = Dictionary(uniqueKeysWithValues: Token.allCases.map { token in
        let light = Palette.rgb(token, dark: false), dark = Palette.rgb(token, dark: true)
        let lightColor = NSColor(srgbRed: light.r, green: light.g, blue: light.b, alpha: 1)
        let darkColor = NSColor(srgbRed: dark.r, green: dark.g, blue: dark.b, alpha: 1)
        return (token, NSColor(name: nil) { $0.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? darkColor : lightColor })
    })

    public static func hue(_ hue: CGFloat, saturation: CGFloat, brightness: CGFloat, alpha: CGFloat = 1) -> NSColor {
        NSColor(hue: hue, saturation: saturation, brightness: brightness, alpha: alpha)
    }

    public static func rgb(red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat = 1) -> NSColor {
        NSColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
    }
}

/// A palette token that follows SwiftUI's colour scheme. A dynamic `NSColor` with no name paints yellow in an offscreen render.
public struct GrailsInk: ShapeStyle {
    public var token: Token
    public var opacity: Double

    public init(_ token: Token, opacity: Double = 1) {
        self.token = token
        self.opacity = opacity
    }

    public func opacity(_ opacity: Double) -> GrailsInk {
        GrailsInk(token, opacity: self.opacity * opacity)
    }

    public func resolve(in environment: EnvironmentValues) -> some ShapeStyle {
        SchemePalette.color(token, environment.colorScheme).opacity(opacity)
    }
}

enum GrailsColor {
    static func token(_ token: Token) -> GrailsInk { GrailsInk(token) }

    static let canvas = GrailsInk(.canvas)
    static let surface = GrailsInk(.surface)
    static let fill = GrailsInk(.fill)
    static let hairline = GrailsInk(.hairline)
    static let text = GrailsInk(.text)
    static let secondary = GrailsInk(.secondary)
    static let tertiary = GrailsInk(.tertiary)
    static let focus = GrailsInk(.focus)
    static let destructive = GrailsInk(.destructive)
    static let destructiveFill = GrailsInk(.destructiveFill)
}

/// A token as a plain sRGB colour for the SwiftUI scheme. Dynamic NSColor fills were resolving to the light grey, which reads as a white rule on a dark sheet.
enum SchemePalette {
    static func color(_ token: Token, _ scheme: ColorScheme) -> Color {
        let c = Palette.rgb(token, dark: scheme == .dark)
        return Color(.sRGB, red: c.r, green: c.g, blue: c.b, opacity: 1)
    }
}

struct GrailsRule: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        GeometryReader { proxy in
            // Only a real 1 pt slot paints. A reader that expands must not draw a line under the title.
            if proxy.size.width > 1, proxy.size.height > 0.5, proxy.size.height < 3 {
                Rectangle().fill(SchemePalette.color(.hairline, scheme))
            }
        }
        .accessibilityHidden(true)
    }
}

public enum GrailsPage {
    public static var animation: Animation { .grailsStandard }

    public static var transition: AnyTransition {
        .asymmetric(
            insertion: .opacity.combined(with: .offset(x: CGFloat(ModalMotion.slide))),
            removal: .opacity.combined(with: .offset(x: CGFloat(-ModalMotion.slide)))
        )
    }
}

struct ButtonChrome {
    var kind: GrailsButtonKind
    var enabled: Bool
    var pressed: Bool
    var hovering: Bool
    var focused: Bool
    var inline: Bool = false

    /// Destructive is the secondary button. One primary and one secondary, app-wide.
    var visual: GrailsButtonKind { kind == .destructive ? .secondary : kind }

    /// Disabled primary stays an ink button. Other kinds fall back to an outline or quiet text.
    var fadedPrimary: Bool { !enabled && visual == .primary }

    var foreground: GrailsInk {
        if fadedPrimary { return GrailsColor.canvas }
        if !enabled { return GrailsColor.tertiary }
        switch visual {
        case .primary: return GrailsColor.canvas
        case .secondary, .destructive: return GrailsColor.text
        case .quiet: return GrailsColor.secondary
        }
    }

    var fill: GrailsInk {
        if fadedPrimary { return GrailsColor.text }
        if !enabled { return GrailsInk(.canvas, opacity: 0) }
        switch visual {
        case .primary: return GrailsColor.text
        case .secondary, .destructive: return hovering ? GrailsColor.fill : GrailsInk(.secondaryFill)
        case .quiet: return hovering ? GrailsColor.fill : GrailsInk(.canvas, opacity: 0)
        }
    }

    var fillOpacity: Double {
        if fadedPrimary { return ChromeMetrics.disabledPrimary }
        if !enabled { return 0 }
        if pressed, visual == .primary { return 0.8 }
        if hovering, visual == .primary { return 0.92 }
        return 1
    }

    var border: GrailsInk {
        if fadedPrimary || visual == .primary || visual == .quiet { return GrailsInk(.canvas, opacity: 0) }
        if !enabled { return GrailsColor.hairline }
        if visual == .secondary { return GrailsInk(.secondaryBorder) }
        return GrailsInk(.canvas, opacity: 0)
    }

    var borderWidth: CGFloat {
        if visual == .quiet || visual == .primary { return 0 }
        if !enabled || visual == .secondary { return 1 }
        return 0
    }

    var metrics: (height: CGFloat, pad: CGFloat, radius: CGFloat, font: Font, width: CGFloat?) {
        if visual == .quiet {
            return (CGFloat(Space.quiet), 8, CGFloat(RadiusToken.chip), ChromeFont.body(TypeScale.quiet), nil)
        }
        if inline {
            return (CGFloat(ChromeMetrics.fieldHeight), 0, CGFloat(RadiusToken.control), ChromeFont.body(TypeScale.button), 72)
        }
        return (CGFloat(Space.button), 14, CGFloat(RadiusToken.control), ChromeFont.body(TypeScale.button), nil)
    }
}

struct ButtonChromeLabel<Label: View>: View {
    var chrome: ButtonChrome
    @ViewBuilder var label: () -> Label

    var body: some View {
        let metrics = chrome.metrics
        let shape = RoundedRectangle(cornerRadius: metrics.radius, style: .continuous)
        label()
            .font(metrics.font)
            .foregroundStyle(chrome.foreground)
            .padding(.horizontal, metrics.pad)
            .frame(width: metrics.width, height: metrics.height)
            .background(chrome.fill.opacity(chrome.fillOpacity), in: shape)
            .overlay(shape.strokeBorder(chrome.border, lineWidth: chrome.borderWidth))
            .overlay {
                if chrome.focused {
                    shape.inset(by: -1.5).stroke(GrailsInk(.text, opacity: 0.08), lineWidth: 3)
                }
            }
            .contentShape(shape)
    }
}

public struct GrailsButtonStyle: ButtonStyle {
    public var kind: GrailsButtonKind
    public var enabled: Bool
    public var inline: Bool

    public init(_ kind: GrailsButtonKind, enabled: Bool = true, inline: Bool = false) {
        self.kind = kind
        self.enabled = enabled
        self.inline = inline
    }

    public func makeBody(configuration: Configuration) -> some View {
        GrailsButtonBody(kind: kind, enabled: enabled, inline: inline, configuration: configuration)
    }
}

private struct GrailsButtonBody: View {
    var kind: GrailsButtonKind
    var enabled: Bool
    var inline: Bool
    var configuration: ButtonStyleConfiguration
    @Environment(\.isEnabled) private var environmentEnabled
    @State private var hovering = false
    @FocusState private var focused: Bool

    var body: some View {
        let live = enabled && environmentEnabled
        let chrome = ButtonChrome(kind: kind, enabled: live, pressed: configuration.isPressed, hovering: hovering, focused: focused, inline: inline)
        ButtonChromeLabel(chrome: chrome) { configuration.label }
            .grailsPressScale(configuration.isPressed && live)
            .focused($focused)
            .focusEffectDisabled()
            .onHover { inside in
                if inside { hovering = true } else { withAnimation(.grailsQuick) { hovering = false } }
            }
            .animation(.grailsQuick, value: focused)
    }
}

public struct GrailsButton: View {
    var title: String
    var kind: GrailsButtonKind
    var symbol: String?
    var loading: Bool
    var identifier: String?
    var enabled: Bool
    var inline: Bool
    var action: () -> Void

    public init(_ title: String, kind: GrailsButtonKind = .primary, symbol: String? = nil, loading: Bool = false, identifier: String? = nil, enabled: Bool = true, inline: Bool = false, action: @escaping () -> Void) {
        self.title = title
        self.kind = kind
        self.symbol = symbol
        self.loading = loading
        self.identifier = identifier
        self.enabled = enabled
        self.inline = inline
        self.action = action
    }

    public var body: some View {
        Button(action: { guard enabled, !loading else { return }; action() }) {
            HStack(spacing: 6) {
                if loading {
                    GrailsSpinner()
                } else if let symbol, !symbol.isEmpty {
                    Image(systemName: symbol).font(ChromeFont.symbol(14, weight: .regular)).imageScale(.small)
                }
                Text(title)
            }
        }
        .buttonStyle(GrailsButtonStyle(kind, enabled: enabled, inline: inline))
        .focusEffectDisabled()
        .modifier(ChromeIdentifier(id: identifier ?? ""))
    }
}

/// A button with no chrome of its own: chips, rows, tile hits. Actions use `GrailsButton`.
/// Menu items use `GrailsMenuItem`. It always presses (`press` picks how much).
public struct GrailsControl<Label: View>: View {
    var role: ButtonRole?
    var press: GrailsPressTarget
    var action: () -> Void
    var label: () -> Label

    public init(_ title: String, role: ButtonRole? = nil, press: GrailsPressTarget = .label, action: @escaping () -> Void) where Label == Text {
        self.role = role
        self.press = press
        self.action = action
        self.label = { Text(title) }
    }

    public init(role: ButtonRole? = nil, press: GrailsPressTarget = .label, action: @escaping () -> Void, @ViewBuilder label: @escaping () -> Label) {
        self.role = role
        self.press = press
        self.action = action
        self.label = label
    }

    public var body: some View {
        Button(role: role, action: action, label: label)
            .buttonStyle(GrailsPressStyle(press))
            .focusEffectDisabled()
    }
}

/// A menu item with no button style. A style drops the item's keyboard shortcut.
public struct GrailsMenuItem: View {
    private var title: String
    private var symbol: String?
    private var shortcut: Shortcut?
    private var enabled: Bool
    private var action: () -> Void

    public init(
        _ title: String,
        symbol: String? = nil,
        shortcut: Shortcut? = nil,
        enabled: Bool = true,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.symbol = symbol
        self.shortcut = shortcut
        self.enabled = enabled
        self.action = action
    }

    public var body: some View {
        shortcutApplied(Button(action: action) { // menu item
            if let symbol, !symbol.isEmpty {
                Label(title, systemImage: symbol)
            } else {
                Text(title)
            }
        })
        .disabled(!enabled)
    }

    @ViewBuilder
    private func shortcutApplied<V: View>(_ item: V) -> some View {
        if let shortcut, !shortcut.isPlain, let key = shortcut.keyEquivalent {
            item.keyboardShortcut(key, modifiers: shortcut.eventModifiers)
        } else {
            item
        }
    }
}

struct ChromeButtonSample: View {
    var title: String
    var kind: GrailsButtonKind = .primary
    var symbol: String? = nil
    var state: ChromeState

    var body: some View {
        ButtonChromeLabel(chrome: ButtonChrome(
            kind: kind,
            enabled: state != .disabled,
            pressed: false,
            hovering: state == .hover,
            focused: state == .focus
        )) {
            HStack(spacing: 6) {
                if state == .loading {
                    GrailsSpinner()
                } else if let symbol, !symbol.isEmpty {
                    Image(systemName: symbol).font(ChromeFont.symbol(14, weight: .regular)).imageScale(.small)
                }
                Text(title)
            }
        }
        .accessibilityLabel("\(title), \(state.rawValue)")
    }
}

/// A compact symbol inside a field, or the modal's close control. Tooltip and accessibility label carry the name.
public struct GrailsIconButton: View {
    var symbol: String
    var label: String
    var action: () -> Void
    @State private var hovering = false

    public init(_ symbol: String, label: String, action: @escaping () -> Void) {
        self.symbol = symbol
        self.label = label
        self.action = action
    }

    public var body: some View {
        let shape = RoundedRectangle(cornerRadius: CGFloat(RadiusToken.chip), style: .continuous)
        Button(action: action) {
            Image(systemName: symbol)
                .font(ChromeFont.symbol(14, weight: .regular))
                .imageScale(.small)
                .foregroundStyle(hovering ? GrailsColor.text : GrailsColor.tertiary)
                .grailsSymbolPress()
                .frame(width: CGFloat(ChromeMetrics.iconButton), height: CGFloat(ChromeMetrics.iconButton))
                .background(hovering ? GrailsColor.fill : GrailsInk(.canvas, opacity: 0), in: shape)
        }
        .buttonStyle(GrailsPressStyle(.symbol))
        .focusEffectDisabled()
        .help(label)
        .accessibilityLabel(label)
        .onHover { inside in
            if inside { hovering = true } else { withAnimation(.grailsQuick) { hovering = false } }
        }
    }
}

public struct GrailsBackButton: View {
    var action: () -> Void

    public init(action: @escaping () -> Void) { self.action = action }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: ChromeIcon.back).font(ChromeFont.symbol(14, weight: .regular)).imageScale(.small)
                Text("Back")
            }
        }
        .buttonStyle(GrailsButtonStyle(.quiet))
        .focusEffectDisabled()
        .accessibilityLabel("Back")
    }
}

public struct GrailsSection<Content: View>: View {
    var title: String
    var symbol: String
    var tag: String?
    var detail: String?
    var content: () -> Content

    public init(_ title: String, symbol: String = "", tag: String? = nil, detail: String? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.symbol = symbol
        self.tag = tag
        self.detail = detail
        self.content = content
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: CGFloat(ChromeMetrics.fieldGap)) {
            VStack(alignment: .leading, spacing: CGFloat(Space.xxs)) {
                HStack(spacing: 6) {
                    if !symbol.isEmpty {
                        Image(systemName: symbol)
                            .font(ChromeFont.symbol(14, weight: .regular))
                            .imageScale(.small)
                            .foregroundStyle(GrailsColor.token(ChromeRole.section))
                    }
                    Text(title)
                        .font(ChromeFont.body(TypeScale.section, bold: true))
                        .foregroundStyle(GrailsColor.token(ChromeRole.section))
                    if let tag, !tag.isEmpty {
                        Text(tag)
                            .font(ChromeFont.body(10))
                            .foregroundStyle(GrailsColor.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .overlay(RoundedRectangle(cornerRadius: CGFloat(RadiusToken.chip), style: .continuous).strokeBorder(GrailsColor.hairline, lineWidth: 1))
                    }
                    Spacer(minLength: 0)
                }
                if let detail, !detail.isEmpty {
                    Text(detail)
                        .font(ChromeFont.body(TypeScale.help))
                        .foregroundStyle(GrailsColor.token(ChromeRole.help))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

public struct GrailsFormGroup<Content: View>: View {
    var title: String
    var content: () -> Content

    public init(_ title: String, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.content = content
    }

    public var body: some View {
        GrailsSection(title) { content() }
    }
}

public struct GrailsChoiceCard: View {
    var title: String
    var identifier: String
    var symbol: String
    var preview: ChromeState
    var action: () -> Void
    @State private var hovering = false
    @FocusState private var focused: Bool
    @Environment(\.isEnabled) private var enabled

    public init(_ title: String, identifier: String, symbol: String = "", preview: ChromeState = .normal, action: @escaping () -> Void) {
        self.title = title
        self.identifier = identifier
        self.symbol = symbol
        self.preview = preview
        self.action = action
    }

    public var body: some View {
        let shape = RoundedRectangle(cornerRadius: CGFloat(RadiusToken.control), style: .continuous)
        let hover = hovering || preview == .hover
        let ring = focused || preview == .focus
        let live = enabled && preview != .disabled
        Button(action: action) {
            HStack(spacing: CGFloat(Space.xs)) {
                if !symbol.isEmpty {
                    Image(systemName: symbol)
                        .font(ChromeFont.symbol(14, weight: .regular))
                        .imageScale(.small)
                        .foregroundStyle(GrailsColor.secondary)
                        .frame(width: 16)
                }
                Text(title)
                    .font(ChromeFont.body(TypeScale.body))
                    .foregroundStyle(live ? GrailsColor.text : GrailsColor.tertiary)
                Spacer(minLength: 0)
                Image(systemName: ChromeIcon.chevronRight)
                    .font(ChromeFont.symbol(10, weight: .semibold))
                    .foregroundStyle(GrailsColor.tertiary)
            }
            .padding(.horizontal, CGFloat(ChromeMetrics.fieldInset))
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: CGFloat(ChromeMetrics.cardHeight), alignment: .leading)
            .background(hover && live ? GrailsColor.fill : GrailsColor.surface, in: shape)
            .overlay(shape.strokeBorder(ring ? GrailsColor.token(ChromeRole.fieldFocus) : GrailsColor.hairline, lineWidth: 1))
            .overlay {
                if ring {
                    shape.inset(by: -1.5).stroke(GrailsInk(.text, opacity: 0.08), lineWidth: 3)
                }
            }
        }
        .buttonStyle(GrailsPressStyle(.row))
        .focusEffectDisabled()
        .focused($focused)
        .onHover { inside in
            if inside { hovering = true } else { withAnimation(.grailsQuick) { hovering = false } }
        }
        .animation(.grailsQuick, value: focused)
        .accessibilityIdentifier(identifier)
    }
}

public struct GrailsDisclosure<Content: View>: View {
    var title: String
    var value: String
    @Binding var expanded: Bool
    var content: () -> Content
    @Environment(\.grailsReduceMotion) private var reduceMotion

    public init(_ title: String, value: String, expanded: Binding<Bool>, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.value = value
        self._expanded = expanded
        self.content = content
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: CGFloat(ChromeMetrics.labelGap)) {
            Button { withGrailsSpring { expanded.toggle() } } label: {
                HStack(spacing: 6) {
                    Text(title)
                        .font(ChromeFont.body(TypeScale.label))
                        .foregroundStyle(GrailsColor.token(ChromeRole.label))
                    GrailsDisclosureChevron(expanded: expanded)
                        .foregroundStyle(GrailsColor.secondary)
                    Spacer(minLength: 8)
                    if !expanded {
                        Text(verbatim: value)
                            .font(ChromeFont.body(TypeScale.label))
                            .foregroundStyle(GrailsColor.secondary)
                            .transition(.grailsFade)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(GrailsPressStyle(.row))
            .focusEffectDisabled()
            .accessibilityLabel(expanded ? "Hide \(title)" : "\(title), \(value)")
            if expanded { content().transition(.grailsReveal(reduceMotion: reduceMotion)) }
        }
    }
}

/// One line. The placeholder is drawn by the field, on the same line as the caret.
/// An offscreen render skips AppKit's text field: that control paints a yellow bar when it has no window.
private struct PromptField: View {
    @Binding var text: String
    var placeholder: String
    var secure: Bool
    var corrects: Bool
    var identifier: String
    var focused: FocusState<Bool>.Binding
    var onSubmit: () -> Void
    @Environment(\.colorScheme) private var scheme
    @Environment(\.grailsSnapshot) private var snapshot

    var body: some View {
        if snapshot {
            let shown = text.isEmpty ? placeholder : (secure ? String(repeating: "•", count: text.count) : text)
            Text(verbatim: shown)
                .font(ChromeFont.body(TypeScale.body))
                .foregroundStyle(text.isEmpty ? GrailsColor.tertiary : GrailsColor.text)
                .lineLimit(1)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        } else {
            QuietField(
                text: $text,
                placeholder: placeholder,
                secure: secure,
                corrects: corrects,
                identifier: identifier,
                textColor: QuietInk.color(.text, scheme),
                promptColor: QuietInk.color(.tertiary, scheme),
                focused: focused,
                onSubmit: onSubmit
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
    }
}

private enum QuietInk {
    static func color(_ token: Token, _ scheme: ColorScheme) -> NSColor {
        let c = Palette.rgb(token, dark: scheme == .dark)
        return NSColor(srgbRed: c.r, green: c.g, blue: c.b, alpha: 1)
    }
}

/// A single-line field with no bezel and no fill. The sheet draws the outline.
private struct QuietField: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String
    var secure: Bool
    var corrects: Bool
    var identifier: String
    var textColor: NSColor
    var promptColor: NSColor
    var pointSize: CGFloat = CGFloat(TypeScale.body)
    var bold: Bool = false
    var display: Bool = false
    var grabsFocus: Bool = false
    var focused: FocusState<Bool>.Binding
    var onSubmit: () -> Void
    var onMove: ((Int) -> Void)? = nil
    var onEscape: (() -> Void)? = nil
    var onFocusChange: (Bool) -> Void = { _ in }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> QuietTextField {
        let field = QuietTextField(secure: secure)
        field.delegate = context.coordinator
        field.grabsFocus = grabsFocus
        field.onFocus = { [weak coordinator = context.coordinator] on in
            coordinator?.parent.focused.wrappedValue = on
            coordinator?.parent.onFocusChange(on)
        }
        field.onSubmit = { [weak coordinator = context.coordinator] in
            coordinator?.parent.onSubmit()
        }
        context.coordinator.configure(field)
        return field
    }

    func updateNSView(_ field: QuietTextField, context: Context) {
        context.coordinator.parent = self
        context.coordinator.configure(field)
        if focused.wrappedValue { field.focusIfAsked() }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: QuietTextField, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? 120, height: proposal.height ?? CGFloat(ChromeMetrics.fieldHeight))
    }

    @MainActor
    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: QuietField
        init(_ parent: QuietField) { self.parent = parent }

        func configure(_ field: QuietTextField) {
            let font = parent.display ? ChromeNSFont.display(parent.pointSize) : ChromeNSFont.body(parent.pointSize, bold: parent.bold)
            field.isBordered = false
            field.isBezeled = false
            field.drawsBackground = false
            field.backgroundColor = .clear
            field.focusRingType = .none
            field.font = font
            field.textColor = parent.textColor
            field.placeholderAttributedString = NSAttributedString(string: parent.placeholder, attributes: [
                .font: font,
                .foregroundColor: parent.promptColor,
            ])
            field.isEditable = true
            field.isSelectable = true
            field.cell?.isScrollable = true
            field.cell?.wraps = false
            field.lineBreakMode = .byClipping
            field.isAutomaticTextCompletionEnabled = parent.corrects
            if !parent.identifier.isEmpty { field.setAccessibilityIdentifier(parent.identifier) }
            if field.stringValue != parent.text { field.stringValue = parent.text }
        }

        func controlTextDidChange(_ note: Notification) {
            guard let field = note.object as? NSTextField else { return }
            let flat = FieldLine.singleLine(field.stringValue)
            if field.stringValue != flat { field.stringValue = flat }
            parent.text = flat
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            switch commandSelector {
            case #selector(NSResponder.insertNewline(_:)):
                parent.onSubmit()
                return true
            case #selector(NSResponder.moveUp(_:)):
                guard let onMove = parent.onMove else { return false }
                onMove(-1)
                return true
            case #selector(NSResponder.moveDown(_:)):
                guard let onMove = parent.onMove else { return false }
                onMove(1)
                return true
            case #selector(NSResponder.cancelOperation(_:)):
                guard let onEscape = parent.onEscape else { return false }
                onEscape()
                return true
            default:
                return false
            }
        }
    }
}

/// An editable field whose placeholder and value share `FieldLine`. In-place titles subclass it.
open class GrailsValueField: NSTextField {
    public init(frame frameRect: NSRect = .zero, secure: Bool = false) {
        super.init(frame: frameRect)
        let cell: NSTextFieldCell = secure ? QuietSecureCell() : QuietCell()
        cell.isEditable = true
        cell.isSelectable = true
        cell.isScrollable = true
        cell.wraps = false
        cell.drawsBackground = false
        cell.isBordered = false
        cell.isBezeled = false
        self.cell = cell
        drawsBackground = false
        isBordered = false
        isBezeled = false
        focusRingType = .none
        clipsToBounds = true
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) { nil }
}

/// A non-editable caption. A wrapping title reports its own height and clips to that frame, so it cannot paint over the line under it.
open class GrailsCaption: NSTextField {
    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        isEditable = false
        isSelectable = false
        isBordered = false
        drawsBackground = false
        focusRingType = .none
        clipsToBounds = true
    }

    public override func sizeThatFits(_ size: NSSize) -> NSSize {
        let wrapping = cell?.wraps == true || maximumNumberOfLines > 0
        guard wrapping, size.width > 1 else { return super.sizeThatFits(size) }
        let font = self.font ?? NSFont.systemFont(ofSize: 13)
        let height = LineMeasure.block(text: stringValue.isEmpty ? " " : stringValue, font: font, width: size.width, maxLines: maximumNumberOfLines)
        return NSSize(width: size.width, height: height)
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) { nil }
}

/// One line of a cluster title. Height is the font's line — ascender, descender, and leading — and the field does not clip, so a tail such as the "a" in "Diwali" is not cut off.
open class GrailsClusterTitle: NSTextField {
    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        isEditable = false
        isSelectable = false
        isBordered = false
        isBezeled = false
        drawsBackground = false
        focusRingType = .none
        lineBreakMode = .byTruncatingTail
        maximumNumberOfLines = 1
        cell?.wraps = false
        cell?.isScrollable = true
        clipsToBounds = false
        wantsLayer = true
        layer?.masksToBounds = false
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) { nil }

    /// The line the font asks for. Taller than the cap height, so descenders fit.
    public static func lineHeight(for font: NSFont) -> CGFloat {
        max(1, ceil(font.ascender + abs(font.descender) + font.leading))
    }

    /// Each side of a borderless text cell. `drawInterior` insets the line by this before drawing.
    /// The string's own box does not include that inset.
    public static let sideInset: CGFloat = 2

    /// Horizontal padding around the line. `drawingRect` sometimes already includes `sideInset`.
    /// When it does not, `drawInterior` applies it. The larger of the two is the padding, so it is not added twice.
    public static func horizontalPadding(for cell: NSCell?) -> CGFloat {
        let minimum = sideInset * 2
        guard let cell else { return minimum }
        let probe = NSRect(x: 0, y: 0, width: 400, height: 64)
        let drawing = cell.drawingRect(forBounds: probe)
        let inset = max(0, drawing.minX - probe.minX) + max(0, probe.maxX - drawing.maxX)
        return max(minimum, inset)
    }

    open override var intrinsicContentSize: NSSize {
        let font = self.font ?? ChromeNSFont.display(CGFloat(TypeScale.body))
        let shown = attributedStringValue.length > 0 ? attributedStringValue : NSAttributedString(string: stringValue.isEmpty ? " " : stringValue, attributes: [.font: font])
        return NSSize(width: Self.fittedWidth(of: shown, cell: cell), height: Self.lineHeight(for: font))
    }

    /// Ceil the ink, then add the cell padding. A fractional mixed-font box, or a frame that is only the string, clips the last glyph.
    static func fittedWidth(of string: NSAttributedString, cell: NSCell?) -> CGFloat {
        max(1, ceil(textWidth(string)) + horizontalPadding(for: cell))
    }

    /// Right edge of the line, from the pen origin. `size()`, the layout manager, and Core Text disagree on mixed fonts.
    /// The widest finite measurement is the one that does not clip.
    static func textWidth(_ string: NSAttributedString) -> CGFloat {
        guard string.length > 0 else { return 0 }
        var width = string.size().width
        let limit = NSSize(width: 20_000, height: 400)
        let box = string.boundingRect(with: limit, options: [.usesLineFragmentOrigin, .usesFontLeading])
        if box.width > 0, box.width < limit.width { width = max(width, box.maxX) }
        let line = CTLineCreateWithAttributedString(string)
        let optical = CTLineGetBoundsWithOptions(line, .useOpticalBounds)
        let advance = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
        return max(0, sane(width), sane(optical.maxX), sane(advance))
    }

    private static func sane(_ value: CGFloat) -> CGFloat {
        value.isFinite && value > 0 ? value : 0
    }

    /// Display only. A click falls through to the cluster underneath.
    open override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

private final class QuietTextField: GrailsValueField {
    var onFocus: (Bool) -> Void = { _ in }
    var onSubmit: () -> Void = {}
    var grabsFocus = false

    init(secure: Bool) {
        super.init(frame: .zero, secure: secure)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard grabsFocus, window != nil else { return }
        DispatchQueue.main.async { [weak self] in self?.focusIfAsked() }
    }

    override func becomeFirstResponder() -> Bool {
        let ok = super.becomeFirstResponder()
        if ok { onFocus(true) }
        return ok
    }

    override func textDidEndEditing(_ notification: Notification) {
        super.textDidEndEditing(notification)
        onFocus(false)
    }

    override func layout() {
        super.layout()
        guard bounds.height > 1, let editor = currentEditor() else { return }
        let line = FieldLine.line(in: bounds, font: font)
        FieldLine.prepare(editor)
        if let view = editor as? NSTextView, let color = textColor { view.insertionPointColor = color }
        if editor.frame.integral != line.integral {
            editor.frame = line
        }
    }

    func focusIfAsked() {
        guard let window else { return }
        if window.firstResponder === self || window.firstResponder === currentEditor() { return }
        window.makeFirstResponder(self)
    }
}

/// One line for the placeholder and the typed value. The 10 pt inset is the field padding, not a second overlay.
@MainActor
enum FieldLine {
    /// Geist's font box sits a point below its glyphs. Both strings use the same lift so they meet the middle of the field.
    static let opticalLift: CGFloat = 1

    /// A pasted break would wrap the row. A single-line field keeps the characters and drops the break.
    static func singleLine(_ text: String) -> String {
        guard text.contains(where: \.isNewline) else { return text }
        return String(text.filter { !$0.isNewline })
    }

    static func line(in bounds: CGRect, font: NSFont?) -> CGRect {
        let measured = font?.boundingRectForFont.height ?? 16
        let height = min(bounds.height, measured)
        let y = bounds.minY + (bounds.height - height) / 2 - opticalLift
        return CGRect(x: bounds.minX, y: y, width: max(0, bounds.width), height: height)
    }

    static func placeholderFrame(in box: CGRect, font: NSFont) -> CGRect { framed(in: box, font: font) }
    static func valueFrame(in box: CGRect, font: NSFont) -> CGRect { framed(in: box, font: font) }

    private static func framed(in box: CGRect, font: NSFont) -> CGRect {
        let inner = CGRect(
            x: box.minX + ChromeMetrics.fieldInset,
            y: box.minY,
            width: max(0, box.width - ChromeMetrics.fieldInset * 2),
            height: box.height
        )
        return line(in: inner, font: font)
    }

    static func prepare(_ editor: NSText) {
        guard let view = editor as? NSTextView else { return }
        if view.textContainerInset != .zero { view.textContainerInset = .zero }
        if view.textContainer?.lineFragmentPadding != 0 { view.textContainer?.lineFragmentPadding = 0 }
    }

    static func draw(_ string: NSAttributedString, in rect: NSRect, clip: NSRect) {
        guard !string.string.isEmpty, rect.width > 0, rect.height > 0 else { return }
        NSGraphicsContext.current?.saveGraphicsState()
        NSBezierPath(rect: clip).addClip()
        string.draw(with: rect, options: [.usesLineFragmentOrigin, .usesFontLeading])
        NSGraphicsContext.current?.restoreGraphicsState()
    }

    /// Distance from the top of a 32 pt field to its line. Multiline text starts there too.
    static func topInset(font: NSFont) -> CGFloat {
        line(in: CGRect(x: 0, y: 0, width: 10, height: ChromeMetrics.fieldHeight), font: font).minY
    }

    static func multilineInset(font: NSFont, width: CGFloat) -> NSSize {
        NSSize(width: width, height: max(0, topInset(font: font)))
    }

    /// The first line of a multiline field. In a 32 pt box it is the same rect as a single-line field.
    static func firstLine(in box: CGRect, font: NSFont) -> CGRect {
        let inner = CGRect(
            x: box.minX + ChromeMetrics.fieldInset,
            y: box.minY,
            width: max(0, box.width - ChromeMetrics.fieldInset * 2),
            height: box.height
        )
        if inner.height <= ChromeMetrics.fieldHeight + 0.5 {
            return line(in: inner, font: font)
        }
        let sample = line(in: CGRect(x: 0, y: 0, width: inner.width, height: ChromeMetrics.fieldHeight), font: font)
        let y = inner.maxY - sample.minY - sample.height
        return CGRect(x: inner.minX, y: y, width: inner.width, height: sample.height)
    }
}

/// Wrapped text height. `maxLines` of 0 means the text runs as far as it needs.
@MainActor
enum LineMeasure {
    static func block(text: String, font: NSFont, width: CGFloat, maxLines: Int) -> CGFloat {
        let storage = NSTextStorage(string: text, attributes: [.font: font])
        let container = NSTextContainer(containerSize: NSSize(width: max(1, width), height: .greatestFiniteMagnitude))
        container.lineFragmentPadding = 0
        if maxLines > 0 {
            container.maximumNumberOfLines = maxLines
            container.lineBreakMode = .byTruncatingTail
        }
        let manager = NSLayoutManager()
        manager.addTextContainer(container)
        storage.addLayoutManager(manager)
        _ = manager.glyphRange(for: container)
        let used = manager.usedRect(for: container)
        return max(ceil(used.height), ceil(font.boundingRectForFont.height))
    }

    static func field(text: String, font: NSFont, width: CGFloat, horizontalInset: CGFloat, maxLines: Int) -> CGFloat {
        let inset = FieldLine.multilineInset(font: font, width: horizontalInset)
        let inner = max(1, width - inset.width * 2)
        return block(text: text, font: font, width: inner, maxLines: maxLines) + inset.height * 2
    }
}

/// A wrapping title stops at four lines. `needsMore` is what shows the Show more control.
public enum TitleLines {
    public static let collapsed = 4

    @MainActor
    public static func needsMore(_ text: String, font: NSFont, width: CGFloat, lines: Int = collapsed) -> Bool {
        guard width > 1, !text.isEmpty else { return false }
        let full = LineMeasure.block(text: text, font: font, width: width, maxLines: 0)
        let cap = LineMeasure.block(text: text, font: font, width: width, maxLines: lines)
        return full > cap + 0.5
    }
}

/// Plain, secure, search, and multiline all measure placeholder and value with one rule.
@MainActor
enum FieldKind: CaseIterable {
    case plain, secure, search, multiline

    func placeholderFrame(in box: CGRect, font: NSFont) -> CGRect { aligned(in: box, font: font) }
    func valueFrame(in box: CGRect, font: NSFont) -> CGRect { aligned(in: box, font: font) }

    private func aligned(in box: CGRect, font: NSFont) -> CGRect {
        switch self {
        case .plain, .secure, .search: return FieldLine.placeholderFrame(in: box, font: font)
        case .multiline: return FieldLine.firstLine(in: box, font: font)
        }
    }
}

class QuietCell: NSTextFieldCell {
    override func drawingRect(forBounds rect: NSRect) -> NSRect { FieldLine.line(in: rect, font: font) }
    override func titleRect(forBounds rect: NSRect) -> NSRect { FieldLine.line(in: rect, font: font) }

    override func drawInterior(withFrame cellFrame: NSRect, in controlView: NSView) {
        guard !Self.editorIsShowing(in: controlView) else { return }
        let shown = stringValue.isEmpty ? (placeholderAttributedString ?? attributedStringValue) : attributedStringValue
        FieldLine.draw(shown, in: titleRect(forBounds: cellFrame), clip: cellFrame)
    }

    override func edit(withFrame rect: NSRect, in controlView: NSView, editor textObj: NSText, delegate: Any?, event: NSEvent?) {
        let line = titleRect(forBounds: rect)
        super.edit(withFrame: line, in: controlView, editor: textObj, delegate: delegate, event: event)
        FieldLine.prepare(textObj)
    }

    override func select(withFrame rect: NSRect, in controlView: NSView, editor textObj: NSText, delegate: Any?, start selStart: Int, length selLength: Int) {
        let line = titleRect(forBounds: rect)
        super.select(withFrame: line, in: controlView, editor: textObj, delegate: delegate, start: selStart, length: selLength)
        FieldLine.prepare(textObj)
    }

    static func editorIsShowing(in controlView: NSView) -> Bool {
        guard let field = controlView as? NSTextField, let editor = field.currentEditor() else { return false }
        return controlView.window?.firstResponder === editor
    }
}

final class QuietSecureCell: NSSecureTextFieldCell {
    override func drawingRect(forBounds rect: NSRect) -> NSRect { FieldLine.line(in: rect, font: font) }
    override func titleRect(forBounds rect: NSRect) -> NSRect { FieldLine.line(in: rect, font: font) }

    override func drawInterior(withFrame cellFrame: NSRect, in controlView: NSView) {
        guard !QuietCell.editorIsShowing(in: controlView) else { return }
        let shown = secureLine()
        FieldLine.draw(shown, in: titleRect(forBounds: cellFrame), clip: cellFrame)
    }

    override func edit(withFrame rect: NSRect, in controlView: NSView, editor textObj: NSText, delegate: Any?, event: NSEvent?) {
        let line = titleRect(forBounds: rect)
        super.edit(withFrame: line, in: controlView, editor: textObj, delegate: delegate, event: event)
        FieldLine.prepare(textObj)
    }

    override func select(withFrame rect: NSRect, in controlView: NSView, editor textObj: NSText, delegate: Any?, start selStart: Int, length selLength: Int) {
        let line = titleRect(forBounds: rect)
        super.select(withFrame: line, in: controlView, editor: textObj, delegate: delegate, start: selStart, length: selLength)
        FieldLine.prepare(textObj)
    }

    /// Bullets share the placeholder's line. The cell never paints the password itself.
    private func secureLine() -> NSAttributedString {
        let face = font ?? NSFont.systemFont(ofSize: 13)
        if stringValue.isEmpty {
            let prompt = placeholderAttributedString ?? NSAttributedString()
            if prompt.length == 0 { return prompt }
            var attrs = prompt.attributes(at: 0, effectiveRange: nil)
            attrs[.font] = face
            return NSAttributedString(string: prompt.string, attributes: attrs)
        }
        return NSAttributedString(string: String(repeating: "•", count: stringValue.count), attributes: [
            .font: face,
            .foregroundColor: textColor ?? NSColor.labelColor,
        ])
    }
}

final class QuietSearchCell: NSSearchFieldCell {
    override func drawingRect(forBounds rect: NSRect) -> NSRect { FieldLine.line(in: rect, font: font) }
    override func titleRect(forBounds rect: NSRect) -> NSRect { FieldLine.line(in: rect, font: font) }

    override func drawInterior(withFrame cellFrame: NSRect, in controlView: NSView) {
        guard !QuietCell.editorIsShowing(in: controlView) else { return }
        let shown = stringValue.isEmpty ? (placeholderAttributedString ?? attributedStringValue) : attributedStringValue
        FieldLine.draw(shown, in: titleRect(forBounds: cellFrame), clip: cellFrame)
    }

    override func edit(withFrame rect: NSRect, in controlView: NSView, editor textObj: NSText, delegate: Any?, event: NSEvent?) {
        let line = titleRect(forBounds: rect)
        super.edit(withFrame: line, in: controlView, editor: textObj, delegate: delegate, event: event)
        FieldLine.prepare(textObj)
    }

    override func select(withFrame rect: NSRect, in controlView: NSView, editor textObj: NSText, delegate: Any?, start selStart: Int, length selLength: Int) {
        let line = titleRect(forBounds: rect)
        super.select(withFrame: line, in: controlView, editor: textObj, delegate: delegate, start: selStart, length: selLength)
        FieldLine.prepare(textObj)
    }
}

/// Multiline text. The placeholder is drawn at the text container's origin, which is also where the value starts.
public final class GrailsLineText: NSTextView {
    public var prompt = ""
    public var promptColor: NSColor = .secondaryLabelColor

    public func useSharedLine(font: NSFont, horizontalInset: CGFloat) {
        self.font = font
        textContainerInset = FieldLine.multilineInset(font: font, width: horizontalInset)
        textContainer?.lineFragmentPadding = 0
        insertionPointColor = textColor ?? promptColor
    }

    public override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard string.isEmpty, !prompt.isEmpty, let font else { return }
        let pad = textContainer?.lineFragmentPadding ?? 0
        let rect = NSRect(
            x: textContainerInset.width + pad,
            y: textContainerInset.height,
            width: max(0, bounds.width - (textContainerInset.width + pad) * 2),
            height: max(font.boundingRectForFont.height, bounds.height - textContainerInset.height * 2)
        )
        let shown = NSAttributedString(string: prompt, attributes: [.font: font, .foregroundColor: promptColor])
        shown.draw(with: rect, options: [.usesLineFragmentOrigin, .usesFontLeading])
    }
}

public struct GrailsTextField: View {
    var label: String
    @Binding var text: String
    var required: Bool
    var help: String?
    var error: String?
    var placeholder: String
    var identifier: String
    var showsPaste: Bool
    var corrects: Bool
    var autofocus: Bool
    var onSubmit: () -> Void
    @FocusState private var focused: Bool

    public init(_ label: String, text: Binding<String>, required: Bool = false, help: String? = nil, error: String? = nil, placeholder: String = "", identifier: String = "", showsPaste: Bool = false, corrects: Bool = true, autofocus: Bool = false, onSubmit: @escaping () -> Void = {}) {
        self.label = label
        self._text = text
        self.required = required
        self.help = help
        self.error = error
        self.placeholder = placeholder
        self.identifier = identifier
        self.showsPaste = showsPaste
        self.corrects = corrects
        self.autofocus = autofocus
        self.onSubmit = onSubmit
    }

    public var body: some View {
        FieldChrome(label: label, required: required, help: help, error: error, focused: focused, showsPaste: showsPaste, onPaste: paste) {
            PromptField(text: $text, placeholder: placeholder, secure: false, corrects: corrects, identifier: identifier, focused: $focused, onSubmit: onSubmit)
                .accessibilityLabel(accessLabel)
        }
        .focusEffectDisabled()
        .onAppear { if autofocus { focused = true } }
    }

    private var accessLabel: String { required ? "\(label), required" : label }

    private func paste() {
        guard let value = NSPasteboard.general.string(forType: .string) else { return }
        text = value
    }
}

/// A value the person can read and copy, not edit. The invite email stays bound to the key.
public struct GrailsReadOnlyValue: View {
    var label: String
    var value: String
    var identifier: String

    public init(_ label: String, value: String, identifier: String = "") {
        self.label = label
        self.value = value
        self.identifier = identifier
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: CGFloat(ChromeMetrics.labelGap)) {
            Text(label)
                .font(ChromeFont.body(TypeScale.label))
                .foregroundStyle(GrailsColor.token(ChromeRole.label))
            Text(verbatim: value)
                .font(ChromeFont.body(TypeScale.body))
                .foregroundStyle(GrailsColor.secondary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, CGFloat(ChromeMetrics.fieldInset))
                .frame(height: CGFloat(ChromeMetrics.fieldHeight), alignment: .leading)
                .background(GrailsColor.token(ChromeRole.fieldFill), in: RoundedRectangle(cornerRadius: CGFloat(RadiusToken.control), style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: CGFloat(RadiusToken.control), style: .continuous).strokeBorder(GrailsColor.hairline, lineWidth: 1))
                .textSelection(.enabled)
                .accessibilityLabel("\(label), \(value)")
                .modifier(ChromeIdentifier(id: identifier))
        }
    }
}

public struct GrailsSecureField: View {
    var label: String
    @Binding var text: String
    var required: Bool
    var help: String?
    var error: String?
    var placeholder: String
    var identifier: String
    var showsPaste: Bool
    var showsReveal: Bool
    var autofocus: Bool
    var onSubmit: () -> Void
    @FocusState private var focused: Bool
    @State private var revealed = false

    public init(_ label: String, text: Binding<String>, required: Bool = false, help: String? = nil, error: String? = nil, placeholder: String = "", identifier: String = "", showsPaste: Bool = false, showsReveal: Bool = true, autofocus: Bool = false, onSubmit: @escaping () -> Void = {}) {
        self.label = label
        self._text = text
        self.required = required
        self.help = help
        self.error = error
        self.placeholder = placeholder
        self.identifier = identifier
        self.showsPaste = showsPaste
        self.showsReveal = showsReveal
        self.autofocus = autofocus
        self.onSubmit = onSubmit
    }

    public var body: some View {
        FieldChrome(label: label, required: required, help: help, error: error, focused: focused, showsPaste: showsPaste, onPaste: paste, showsReveal: showsReveal, revealed: revealed, onReveal: { revealed.toggle() }) {
            PromptField(text: $text, placeholder: placeholder, secure: !revealed, corrects: false, identifier: identifier, focused: $focused, onSubmit: onSubmit)
                .accessibilityLabel(required ? "\(label), required" : label)
        }
        .focusEffectDisabled()
        .onAppear { if autofocus { focused = true } }
    }

    private func paste() {
        guard let value = NSPasteboard.general.string(forType: .string) else { return }
        text = value
    }
}

/// A single-line box for a row that already has its label beside it.
public struct GrailsInlineField: View {
    @Binding var text: String
    var placeholder: String
    var identifier: String
    var onSubmit: () -> Void
    @FocusState private var focused: Bool

    public init(text: Binding<String>, placeholder: String = "", identifier: String = "", onSubmit: @escaping () -> Void = {}) {
        self._text = text
        self.placeholder = placeholder
        self.identifier = identifier
        self.onSubmit = onSubmit
    }

    public var body: some View {
        let shape = RoundedRectangle(cornerRadius: CGFloat(RadiusToken.control), style: .continuous)
        PromptField(text: $text, placeholder: placeholder, secure: false, corrects: true, identifier: identifier, focused: $focused, onSubmit: onSubmit)
            .padding(.horizontal, CGFloat(ChromeMetrics.fieldInset))
            .frame(height: CGFloat(ChromeMetrics.fieldHeight), alignment: .leading)
            .background(GrailsColor.surface, in: shape)
            .overlay(shape.strokeBorder(focused ? GrailsColor.token(ChromeRole.fieldFocus) : GrailsColor.hairline, lineWidth: 1))
            .overlay {
                if focused {
                    shape.inset(by: -1.5).stroke(GrailsInk(.text, opacity: 0.08), lineWidth: 3)
                }
            }
            .focusEffectDisabled()
            .accessibilityLabel(placeholder.isEmpty ? "Field" : placeholder)
            .animation(.grailsQuick, value: focused)
    }
}

public struct GrailsFieldChrome<Control: View>: View {
    var label: String
    var required: Bool
    var help: String?
    var error: String?
    var focused: Bool
    var control: () -> Control

    public init(_ label: String, required: Bool = false, help: String? = nil, error: String? = nil, focused: Bool, @ViewBuilder control: @escaping () -> Control) {
        self.label = label
        self.required = required
        self.help = help
        self.error = error
        self.focused = focused
        self.control = control
    }

    public var body: some View {
        FieldChrome(label: label, required: required, help: help, error: error, focused: focused, singleLine: false, control: control)
    }
}

struct GrailsFieldSample: View {
    var state: ChromeState

    var body: some View {
        let help: String? = state == .error ? nil : "https endpoint"
        let error: String? = state == .error ? "Check the endpoint" : nil
        FieldChrome(
            label: "Endpoint",
            required: true,
            help: help,
            error: error,
            focused: state == .focus,
            hovering: state == .hover,
            showsPaste: true,
            onPaste: {},
            loading: state == .loading
        ) {
            Text(verbatim: state == .normal || state == .hover ? "https://<account>.r2.cloudflarestorage.com" : "https://acct.r2.cloudflarestorage.com")
                .font(ChromeFont.body(TypeScale.body))
                .foregroundStyle(state == .normal || state == .hover ? GrailsColor.tertiary : GrailsColor.text)
                .lineLimit(1)
        }
        .disabled(state == .disabled)
        .accessibilityLabel("Endpoint, \(state.rawValue)")
    }
}

struct FieldChrome<Control: View>: View {
    var label: String
    var required: Bool
    var help: String?
    var error: String?
    var focused: Bool
    var hovering: Bool = false
    var showsPaste: Bool = false
    var onPaste: () -> Void = {}
    var showsReveal: Bool = false
    var revealed: Bool = false
    var onReveal: () -> Void = {}
    var loading: Bool = false
    var singleLine: Bool = true
    @ViewBuilder var control: () -> Control

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            labelRow
            fieldBox.padding(.top, label.isEmpty ? 0 : CGFloat(ChromeMetrics.labelGap))
            caption
        }
    }

    private var labelRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 2) {
            Text(label)
                .foregroundStyle(GrailsColor.token(ChromeRole.label))
            if required {
                Text(ChromeMetrics.requiredMark)
                    .foregroundStyle(GrailsColor.token(ChromeRole.required))
                    .accessibilityHidden(true)
            }
        }
        .font(ChromeFont.body(TypeScale.label))
    }

    private var fieldRow: some View {
        HStack(alignment: .center, spacing: 2) {
            control()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            if loading {
                GrailsSpinner()
                    .frame(width: CGFloat(ChromeMetrics.iconButton), height: CGFloat(ChromeMetrics.iconButton))
            }
            if showsPaste {
                GrailsIconButton(ChromeIcon.paste, label: "Paste", action: onPaste)
            }
            if showsReveal {
                GrailsIconButton(revealed ? ChromeIcon.conceal : ChromeIcon.reveal, label: revealed ? "Hide" : "Show", action: onReveal)
            }
        }
        .padding(.horizontal, CGFloat(ChromeMetrics.fieldInset))
    }

    private var fieldBox: some View {
        let shape = RoundedRectangle(cornerRadius: CGFloat(RadiusToken.control), style: .continuous)
        return Group {
            if singleLine {
                fieldRow.frame(height: CGFloat(ChromeMetrics.fieldHeight), alignment: .leading)
            } else {
                fieldRow.frame(minHeight: CGFloat(ChromeMetrics.fieldHeight), alignment: .topLeading)
            }
        }
        .background(GrailsColor.token(ChromeRole.fieldFill), in: shape)
        .overlay(shape.strokeBorder(borderColor, lineWidth: 1))
        .overlay {
            if focused {
                shape.inset(by: -1.5).stroke(GrailsInk(.text, opacity: 0.08), lineWidth: 3)
            }
        }
        .animation(.grailsQuick, value: focused)
    }

    private var borderColor: GrailsInk {
        if focused { return GrailsColor.token(ChromeRole.fieldFocus) }
        if let error, !error.isEmpty { return GrailsColor.token(ChromeRole.error) }
        return GrailsColor.token(ChromeRole.fieldBorder)
    }

    @ViewBuilder private var caption: some View {
        if let error, !error.isEmpty {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Image(systemName: ChromeIcon.error)
                Text(error).fixedSize(horizontal: false, vertical: true)
            }
            .font(ChromeFont.body(TypeScale.help))
            .foregroundStyle(GrailsColor.token(ChromeRole.error))
            .padding(.top, CGFloat(ChromeMetrics.helperGap))
        } else if let help, !help.isEmpty {
            Text(help)
                .font(ChromeFont.body(TypeScale.help))
                .foregroundStyle(GrailsColor.token(ChromeRole.help))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, CGFloat(ChromeMetrics.helperGap))
        }
    }
}

/// A still arc in the secondary ink. The system spinner paints a yellow bar in an offscreen render.
/// A square crop. The bitmap fills it and cannot change the card's size.
public struct GrailsSquareMedia<Content: View>: View {
    public var side: CGFloat
    @ViewBuilder public var content: () -> Content

    public init(side: CGFloat, @ViewBuilder content: @escaping () -> Content) {
        self.side = side
        self.content = content
    }

    public var body: some View {
        Color.clear
            .frame(width: side, height: side)
            .overlay {
                content()
                    .frame(width: side, height: side, alignment: .center)
                    .clipped()
            }
            .clipped()
    }
}

/// A determinate bar in the text ink. The system progress view paints its own accent.
public struct GrailsProgressBar: View {
    public var done: Int
    public var total: Int
    public var label: String

    public init(done: Int, total: Int, label: String) {
        self.done = done
        self.total = total
        self.label = label
    }

    public var body: some View {
        let fraction = total > 0 ? min(1, max(0, Double(done) / Double(total))) : 0
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(ChromeFont.body(TypeScale.help))
                .foregroundStyle(GrailsColor.text)
                .lineLimit(2)
            Capsule()
                .fill(GrailsColor.fill)
                .frame(height: 4)
                .overlay(alignment: .leading) {
                    GeometryReader { proxy in
                        Capsule()
                            .fill(GrailsColor.text)
                            .frame(width: fraction > 0 ? max(2, proxy.size.width * fraction) : 0)
                    }
                }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue("\(done) of \(total)")
    }
}

/// One row's in-flight action. A second tap while it is running is ignored. Failure keeps the message for Retry.
public struct GrailsAsyncActions: Equatable, Sendable {
    public struct Row: Equatable, Sendable {
        public var label: String
        public var failure: String?
        public var running: Bool { failure == nil }
    }

    private var rows: [String: Row] = [:]

    public init() {}

    public mutating func begin(_ key: String, label: String) -> Bool {
        if rows[key]?.running == true { return false }
        rows[key] = Row(label: label, failure: nil)
        return true
    }

    public mutating func succeed(_ key: String) { rows[key] = nil }

    public mutating func fail(_ key: String, message: String) {
        let label = rows[key]?.label ?? ""
        rows[key] = Row(label: label, failure: message)
    }

    public func isBusy(_ key: String) -> Bool { rows[key]?.running == true }

    public func label(_ key: String) -> String? {
        guard let row = rows[key], row.running else { return nil }
        return row.label
    }

    public func statusLabel(_ key: String) -> String? { rows[key]?.label }

    public func failure(_ key: String) -> String? { rows[key]?.failure }
}

/// An arc that turns once every `Motion.spinnerPeriod`. Linear, driven by the clock, so it keeps no animation state of its own.
/// Reduce Motion and an offscreen snapshot hold it still at `Motion.spinnerRest`; a background app or a hidden window pause it.
struct GrailsSpinner: View {
    @Environment(\.grailsReduceMotion) private var reduceMotion
    @Environment(\.grailsSnapshot) private var snapshot

    var body: some View {
        let still = reduceMotion || snapshot
        GrailsLiveMotion { live in
            TimelineView(.animation(paused: !live)) { context in
                Circle()
                    .trim(from: 0.15, to: 0.82)
                    .stroke(GrailsColor.secondary, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                    .frame(width: 12, height: 12)
                    .rotationEffect(.degrees(Motion.spinnerAngle(at: context.date.timeIntervalSinceReferenceDate, reduceMotion: still)))
            }
        }
        .accessibilityLabel("Loading")
    }
}

/// Spinner and one line, for a step that has to wait. The modal keeps its own height.
/// A wait shorter than `Motion.spinnerDelay` shows nothing; the row's place is kept, so nothing jumps when it fades in.
public struct GrailsPending: View {
    var text: String
    @Environment(\.grailsSnapshot) private var snapshot
    @State private var shown = false

    public init(_ text: String) {
        self.text = text
    }

    public var body: some View {
        row
            .opacity(shown || snapshot ? 1 : 0)
            .task {
                try? await Task.sleep(for: .seconds(Motion.spinnerDelay))
                withAnimation(.grailsStandard) { shown = true }
            }
    }

    private var row: some View {
        HStack(spacing: CGFloat(Space.sm)) {
            GrailsSpinner()
            Text(text)
                .font(ChromeFont.body(TypeScale.body))
                .foregroundStyle(GrailsColor.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: CGFloat(Space.button), alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(text)
    }
}

public struct GrailsSegmented: View {
    public struct Option: Equatable, Identifiable, Sendable {
        public var id: String
        public var title: String
        public var enabled: Bool
        public var help: String?
        public var identifier: String

        public init(id: String, title: String, enabled: Bool = true, help: String? = nil, identifier: String = "") {
            self.id = id
            self.title = title
            self.enabled = enabled
            self.help = help
            self.identifier = identifier
        }
    }

    var options: [Option]
    var selection: String
    var onSelect: (String) -> Void

    public init(options: [Option], selection: String, onSelect: @escaping (String) -> Void) {
        self.options = options
        self.selection = selection
        self.onSelect = onSelect
    }

    public var body: some View {
        HStack(spacing: 0) {
            ForEach(options) { option in
                segment(option)
            }
        }
        .grailsSelectionTrack { SegmentThumb() }
        .padding(2)
        .frame(maxWidth: .infinity)
        .frame(height: CGFloat(ChromeMetrics.fieldHeight))
        .background(GrailsInk(.segmentedTrack), in: RoundedRectangle(cornerRadius: CGFloat(RadiusToken.control), style: .continuous))
    }

    private func segment(_ option: Option) -> some View {
        let selected = option.id == selection
        return SegmentButton(option: option, selected: selected) {
            guard option.enabled else { return }
            onSelect(option.id)
        }
    }
}

/// The raised thumb under the selected segment. One per control: it springs from segment to segment.
private struct SegmentThumb: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let thumb = RoundedRectangle(cornerRadius: CGFloat(RadiusToken.chip), style: .continuous)
        thumb
            .fill(GrailsInk(.segmentedSelected))
            .shadow(color: .black.opacity(scheme == .dark ? 0.3 : 0.08), radius: 1, y: 1)
            .overlay(thumb.strokeBorder(Color.black.opacity(scheme == .dark ? 0 : 0.06), lineWidth: 0.5))
    }
}

private struct SegmentButton: View {
    var option: GrailsSegmented.Option
    var selected: Bool
    var action: () -> Void
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Button(action: action) {
            Text(option.title)
                .font(ChromeFont.body(TypeScale.button))
                .foregroundStyle(SchemePalette.color(selected ? .text : (option.enabled ? .secondary : .tertiary), scheme))
                .animation(.grailsQuick, value: selected)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .grailsSelectionTarget(selected)
                .contentShape(Rectangle())
        }
        .buttonStyle(GrailsPressStyle(option.enabled ? .label : .row))
        .focusEffectDisabled()
        .help(option.enabled ? "" : (option.help ?? ""))
        .accessibilityIdentifier(option.identifier)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Connected, syncing, failed, or offline. The only hue in the chrome, besides a picture.
public enum StatusKind: String, Sendable {
    case ok, warn, error, offline

    var token: Token {
        switch self {
        case .ok: .statusOk
        case .warn: .statusWarn
        case .error: .statusError
        case .offline: .statusOffline
        }
    }
}

/// A 6 pt circle in front of a connection or sync status.
public struct StatusDot: View {
    var kind: StatusKind
    var text: String?

    public init(_ kind: StatusKind) {
        self.kind = kind
        self.text = nil
    }

    public init(_ kind: StatusKind, _ text: String) {
        self.kind = kind
        self.text = text
    }

    public var body: some View {
        HStack(spacing: CGFloat(Space.tight)) {
            Circle()
                .fill(GrailsColor.token(kind.token))
                .frame(width: 6, height: 6)
                .accessibilityHidden(true)
            if let text {
                Text(verbatim: text)
                    .font(ChromeFont.body(TypeScale.help))
                    .foregroundStyle(GrailsColor.secondary)
            }
        }
    }
}

public struct GrailsRoleBadge: View {
    var role: String

    public init(_ role: String) { self.role = role }

    public var body: some View {
        Text(role)
            .font(ChromeFont.body(TypeScale.help))
            .foregroundStyle(GrailsColor.secondary)
            .accessibilityLabel("Role \(role)")
    }
}

public struct GrailsRow<Trailing: View>: View {
    var title: String
    var detail: String?
    var trailing: () -> Trailing

    public init(_ title: String, detail: String? = nil, @ViewBuilder trailing: @escaping () -> Trailing = { EmptyView() }) {
        self.title = title
        self.detail = detail
        self.trailing = trailing
    }

    public var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: CGFloat(Space.sm)) {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: title)
                    .font(ChromeFont.body(TypeScale.body))
                    .foregroundStyle(GrailsColor.text)
                    .lineLimit(1)
                if let detail, !detail.isEmpty {
                    Text(verbatim: detail)
                        .font(ChromeFont.body(TypeScale.help))
                        .foregroundStyle(GrailsColor.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: CGFloat(Space.xs))
            trailing()
        }
        .frame(minHeight: CGFloat(ChromeMetrics.fieldHeight))
    }
}

public struct GrailsEmpty: View {
    var title: String
    var detail: String?

    public init(_ title: String, detail: String? = nil) {
        self.title = title
        self.detail = detail
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: CGFloat(Space.xs)) {
            Text(title)
                .font(ChromeFont.display(TypeScale.title))
                .tracking(TypeScale.titleTracking)
                .foregroundStyle(GrailsColor.text)
            if let detail, !detail.isEmpty {
                Text(detail)
                    .font(ChromeFont.body(TypeScale.body))
                    .foregroundStyle(GrailsColor.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, CGFloat(Space.md))
        .grailsEmptyEntrance()
    }
}

/// A field whose own chrome is drawn by the caller. Placeholder and value share one line.
public struct GrailsPlainField<Focus: Hashable>: View {
    @Binding var text: String
    var placeholder: String
    var axis: Axis
    var size: Double
    var bold: Bool
    var display: Bool
    var focus: FocusState<Focus>.Binding
    var equals: Focus
    var idle: Focus
    var lineLimit: ClosedRange<Int>
    var onSubmit: () -> Void
    @Environment(\.grailsSnapshot) private var snapshot
    @Environment(\.colorScheme) private var scheme
    @FocusState private var lineFocused: Bool

    public init(_ placeholder: String = "", text: Binding<String>, axis: Axis = .horizontal, size: Double = TypeScale.body, bold: Bool = false, display: Bool = false, focus: FocusState<Focus>.Binding, equals: Focus, idle: Focus, lineLimit: ClosedRange<Int> = 1...1, onSubmit: @escaping () -> Void = {}) {
        self.placeholder = placeholder
        self._text = text
        self.axis = axis
        self.size = size
        self.bold = bold
        self.display = display
        self.focus = focus
        self.equals = equals
        self.idle = idle
        self.lineLimit = lineLimit
        self.onSubmit = onSubmit
    }

    private var multiline: Bool { axis == .vertical || lineLimit.upperBound > 1 }
    private var face: Font { display ? ChromeFont.display(size) : ChromeFont.body(size, bold: bold) }

    public var body: some View {
        Group {
            if snapshot {
                Text(verbatim: text.isEmpty ? placeholder : text)
                    .font(face)
                    .foregroundStyle(text.isEmpty ? GrailsColor.tertiary : GrailsColor.text)
                    .lineLimit(lineLimit)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: multiline ? .topLeading : .leading)
            } else if multiline {
                MultilineHost(text: $text, placeholder: placeholder, size: size, bold: bold, display: display, horizontalInset: 0, maxLines: lineLimit.upperBound, identifier: "", textColor: QuietInk.color(.text, scheme), promptColor: QuietInk.color(.tertiary, scheme), focused: lineFocused, submitsOnReturn: true, onSubmit: onSubmit, onFocus: { lineFocused = $0 })
            } else {
                QuietField(text: $text, placeholder: placeholder, secure: false, corrects: true, identifier: "", textColor: QuietInk.color(.text, scheme), promptColor: QuietInk.color(.tertiary, scheme), pointSize: CGFloat(size), bold: bold, display: display, focused: $lineFocused, onSubmit: onSubmit)
            }
        }
        .onAppear { lineFocused = focus.wrappedValue == equals }
        .onChange(of: focus.wrappedValue) { _, value in
            let on = value == equals
            if lineFocused != on { lineFocused = on }
        }
        .onChange(of: lineFocused) { _, on in
            if on {
                if focus.wrappedValue != equals { focus.wrappedValue = equals }
            } else if focus.wrappedValue == equals {
                focus.wrappedValue = idle
            }
        }
    }
}

/// The library search field. The bar draws the icon; the text uses the shared line.
public struct GrailsSearchField: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String
    var focusTick: Int
    @Binding var isFocused: Bool
    var onSubmit: () -> Void
    @Environment(\.colorScheme) private var scheme

    public init(text: Binding<String>, placeholder: String = "Search", focusTick: Int = 0, isFocused: Binding<Bool>, onSubmit: @escaping () -> Void = {}) {
        self._text = text
        self.placeholder = placeholder
        self.focusTick = focusTick
        self._isFocused = isFocused
        self.onSubmit = onSubmit
    }

    public func makeCoordinator() -> Coordinator { Coordinator(self) }

    public func makeNSView(context: Context) -> NSSearchField {
        let field = SearchLineField(frame: .zero)
        let cell = QuietSearchCell()
        cell.isEditable = true
        cell.isSelectable = true
        cell.isScrollable = true
        cell.wraps = false
        cell.drawsBackground = false
        cell.isBordered = false
        cell.isBezeled = false
        cell.searchButtonCell = nil
        cell.cancelButtonCell = nil
        field.cell = cell
        field.isBordered = false
        field.isBezeled = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.sendsSearchStringImmediately = true
        field.delegate = context.coordinator
        field.setAccessibilityIdentifier("search-field")
        field.setAccessibilityLabel("Search library")
        context.coordinator.configure(field, scheme: scheme)
        return field
    }

    public func updateNSView(_ field: NSSearchField, context: Context) {
        context.coordinator.parent = self
        context.coordinator.configure(field, scheme: scheme)
        if context.coordinator.lastTick != focusTick {
            context.coordinator.lastTick = focusTick
            DispatchQueue.main.async { field.window?.makeFirstResponder(field) }
        }
    }

    @MainActor
    public final class Coordinator: NSObject, NSSearchFieldDelegate {
        var parent: GrailsSearchField
        var lastTick: Int
        init(_ parent: GrailsSearchField) { self.parent = parent; lastTick = parent.focusTick }

        func configure(_ field: NSSearchField, scheme: ColorScheme) {
            let font = ChromeNSFont.body(CGFloat(TypeScale.body))
            field.font = font
            field.textColor = QuietInk.color(.text, scheme)
            field.placeholderAttributedString = NSAttributedString(string: parent.placeholder, attributes: [
                .font: font,
                .foregroundColor: QuietInk.color(.tertiary, scheme),
            ])
            if field.stringValue != parent.text { field.stringValue = parent.text }
        }

        public func controlTextDidChange(_ obj: Notification) {
            guard let field = obj.object as? NSSearchField else { return }
            let flat = FieldLine.singleLine(field.stringValue)
            if field.stringValue != flat { field.stringValue = flat }
            if parent.text != flat { parent.text = flat }
        }

        public func controlTextDidBeginEditing(_ obj: Notification) {
            parent.isFocused = true
            (obj.userInfo?["NSFieldEditor"] as? NSTextView)?.insertionPointColor = (obj.object as? NSTextField)?.textColor
        }

        public func controlTextDidEndEditing(_ obj: Notification) { parent.isFocused = false }

        public func control(_ control: NSControl, textView: NSTextView, doCommandBy sel: Selector) -> Bool {
            switch sel {
            case #selector(NSResponder.insertNewline(_:)): parent.onSubmit(); return false
            case #selector(NSResponder.cancelOperation(_:)):
                if !parent.text.isEmpty { parent.text = "" }
                control.window?.makeFirstResponder(nil)
                return true
            default: return false
            }
        }
    }
}

private final class SearchLineField: NSSearchField {
    override func layout() {
        super.layout()
        guard bounds.height > 1, let editor = currentEditor() else { return }
        let line = FieldLine.line(in: bounds, font: font)
        FieldLine.prepare(editor)
        if let view = editor as? NSTextView, let color = textColor { view.insertionPointColor = color }
        if editor.frame.integral != line.integral { editor.frame = line }
    }
}

/// A single-line field that takes the keyboard from the grid and reports arrows, Escape, and Return.
public struct GrailsCommandField: View {
    @Binding var text: String
    var placeholder: String
    var identifier: String
    var size: Double
    var onSubmit: () -> Void
    var onMove: (Int) -> Void
    var onEscape: () -> Void
    var onFocus: (Bool) -> Void
    @FocusState private var focused: Bool
    @Environment(\.colorScheme) private var scheme

    public init(text: Binding<String>, placeholder: String, identifier: String = "", size: Double = 17, onSubmit: @escaping () -> Void = {}, onMove: @escaping (Int) -> Void = { _ in }, onEscape: @escaping () -> Void = {}, onFocus: @escaping (Bool) -> Void = { _ in }) {
        self._text = text
        self.placeholder = placeholder
        self.identifier = identifier
        self.size = size
        self.onSubmit = onSubmit
        self.onMove = onMove
        self.onEscape = onEscape
        self.onFocus = onFocus
    }

    public var body: some View {
        QuietField(text: $text, placeholder: placeholder, secure: false, corrects: false, identifier: identifier, textColor: QuietInk.color(.text, scheme), promptColor: QuietInk.color(.tertiary, scheme), pointSize: CGFloat(size), grabsFocus: true, focused: $focused, onSubmit: onSubmit, onMove: onMove, onEscape: onEscape, onFocusChange: onFocus)
    }
}

/// A growing field. The placeholder is painted by the text view, on the same origin as the value.
public struct GrailsMultilineField: View {
    @Binding var text: String
    var placeholder: String
    var size: Double
    var bold: Bool
    var horizontalInset: CGFloat
    var maxLines: Int
    var identifier: String
    var focused: FocusState<Bool>.Binding
    var onSubmit: () -> Void
    @Environment(\.colorScheme) private var scheme
    @Environment(\.grailsSnapshot) private var snapshot

    public init(_ placeholder: String = "", text: Binding<String>, size: Double = TypeScale.body, bold: Bool = false, horizontalInset: CGFloat = 0, identifier: String = "", focused: FocusState<Bool>.Binding, onSubmit: @escaping () -> Void = {}) {
        self.placeholder = placeholder
        self._text = text
        self.size = size
        self.bold = bold
        self.horizontalInset = horizontalInset
        self.maxLines = 0
        self.identifier = identifier
        self.focused = focused
        self.onSubmit = onSubmit
    }

    public var body: some View {
        if snapshot {
            Text(verbatim: text.isEmpty ? placeholder : text)
                .font(ChromeFont.body(size, bold: bold))
                .foregroundStyle(text.isEmpty ? GrailsColor.tertiary : GrailsColor.text)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else {
            MultilineHost(text: $text, placeholder: placeholder, size: size, bold: bold, horizontalInset: horizontalInset, maxLines: maxLines, identifier: identifier, textColor: QuietInk.color(.text, scheme), promptColor: QuietInk.color(.tertiary, scheme), focused: focused.wrappedValue, submitsOnReturn: false, onSubmit: onSubmit, onFocus: { focused.wrappedValue = $0 })
        }
    }
}

private struct MultilineHost: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String
    var size: Double
    var bold: Bool
    var display: Bool = false
    var horizontalInset: CGFloat
    var maxLines: Int
    var identifier: String
    var textColor: NSColor
    var promptColor: NSColor
    var focused: Bool
    var submitsOnReturn: Bool
    var onSubmit: () -> Void
    var onFocus: (Bool) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> GrailsLineText {
        let view = GrailsLineText()
        view.delegate = context.coordinator
        view.isRichText = false
        view.importsGraphics = false
        view.drawsBackground = false
        view.isVerticallyResizable = false
        view.isHorizontallyResizable = false
        view.clipsToBounds = true
        view.textContainer?.widthTracksTextView = true
        view.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        view.isAutomaticQuoteSubstitutionEnabled = false
        view.isAutomaticDashSubstitutionEnabled = false
        view.isAutomaticDataDetectionEnabled = false
        view.isAutomaticLinkDetectionEnabled = false
        view.isAutomaticTextReplacementEnabled = false
        context.coordinator.configure(view)
        return view
    }

    func updateNSView(_ view: GrailsLineText, context: Context) {
        context.coordinator.parent = self
        context.coordinator.configure(view)
        if focused, view.window?.firstResponder !== view {
            DispatchQueue.main.async { view.window?.makeFirstResponder(view) }
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: GrailsLineText, context: Context) -> CGSize? {
        let width = proposal.width ?? nsView.bounds.width
        guard width > 1 else { return nil }
        let font = display ? ChromeNSFont.display(CGFloat(size)) : ChromeNSFont.body(CGFloat(size), bold: bold)
        let measured = Self.textHeight(text: text.isEmpty ? " " : text, font: font, width: width, horizontalInset: horizontalInset, maxLines: maxLines)
        return CGSize(width: width, height: measured)
    }

    /// Wrapped height, including the shared line inset, capped at `maxLines` (0 means no cap).
    @MainActor
    private static func textHeight(text: String, font: NSFont, width: CGFloat, horizontalInset: CGFloat, maxLines: Int) -> CGFloat {
        LineMeasure.field(text: text, font: font, width: width, horizontalInset: horizontalInset, maxLines: maxLines)
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: MultilineHost
        init(_ parent: MultilineHost) { self.parent = parent }

        func configure(_ view: GrailsLineText) {
            view.textColor = parent.textColor
            view.prompt = parent.placeholder
            view.promptColor = parent.promptColor
            let font = parent.display ? ChromeNSFont.display(CGFloat(parent.size)) : ChromeNSFont.body(CGFloat(parent.size), bold: parent.bold)
            view.useSharedLine(font: font, horizontalInset: parent.horizontalInset)
            view.textContainer?.maximumNumberOfLines = parent.maxLines
            view.textContainer?.lineBreakMode = parent.maxLines > 0 ? .byTruncatingTail : .byWordWrapping
            if !parent.identifier.isEmpty { view.setAccessibilityIdentifier(parent.identifier) }
            if view.string != parent.text { view.string = parent.text }
        }

        func textDidChange(_ notification: Notification) {
            guard let view = notification.object as? NSTextView, view.string != parent.text else { return }
            parent.text = view.string
        }

        func textDidBeginEditing(_ notification: Notification) { parent.onFocus(true) }
        func textDidEndEditing(_ notification: Notification) { parent.onFocus(false) }

        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            guard parent.submitsOnReturn, commandSelector == #selector(NSResponder.insertNewline(_:)) else { return false }
            parent.onSubmit()
            return true
        }
    }
}

public struct GrailsCodeDisplay: View {
    var code: String
    var onCopy: () -> Void
    @State private var hidden = false

    public init(code: String, onCopy: @escaping () -> Void = {}) {
        self.code = code
        self.onCopy = onCopy
    }

    public var body: some View {
        HStack(spacing: CGFloat(Space.xs)) {
            Text(hidden ? "••• •••" : Self.grouped(code))
                .font(ChromeFont.display(TypeScale.monoCode))
                .tracking(TypeScale.monoCodeTracking)
                .foregroundStyle(GrailsColor.text)
                .accessibilityLabel(hidden ? "Invite code hidden" : "Invite code \(code)")
            GrailsIconButton(hidden ? ChromeIcon.reveal : ChromeIcon.conceal, label: hidden ? "Show code" : "Hide code") {
                hidden.toggle()
            }
            GrailsIconButton(ChromeIcon.copy, label: "Copy code", action: onCopy)
        }
    }

    public static func grouped(_ code: String) -> String {
        guard code.count == 6, code.allSatisfy(\.isNumber) else { return code }
        let split = code.index(code.startIndex, offsetBy: 3)
        return "\(code[..<split]) \(code[split...])"
    }
}

/// A read-only field with an inline secondary Copy button. Mono is for an invite link or code.
public struct GrailsCopyField: View {
    var label: String
    var value: String
    var mono: Bool
    var size: Double
    var tracking: Double
    var identifier: String
    var accessory: String?
    var accessoryLabel: String
    var onAccessory: (() -> Void)?
    var onCopy: () -> Void

    public init(_ label: String, value: String, mono: Bool = false, size: Double = TypeScale.body, tracking: Double = 0, identifier: String = "", accessory: String? = nil, accessoryLabel: String = "", onAccessory: (() -> Void)? = nil, onCopy: @escaping () -> Void) {
        self.label = label
        self.value = value
        self.mono = mono
        self.size = size
        self.tracking = tracking
        self.identifier = identifier
        self.accessory = accessory
        self.accessoryLabel = accessoryLabel
        self.onAccessory = onAccessory
        self.onCopy = onCopy
    }

    public var body: some View {
        let shape = RoundedRectangle(cornerRadius: CGFloat(RadiusToken.control), style: .continuous)
        VStack(alignment: .leading, spacing: CGFloat(ChromeMetrics.labelGap)) {
            Text(label)
                .font(ChromeFont.body(TypeScale.label))
                .foregroundStyle(GrailsColor.token(ChromeRole.label))
            HStack(spacing: CGFloat(Space.xs)) {
                HStack(spacing: CGFloat(Space.xs)) {
                    Text(verbatim: value)
                        .font(mono ? ChromeFont.display(size) : ChromeFont.body(size))
                        .tracking(tracking)
                        .foregroundStyle(GrailsColor.text)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if let accessory, let onAccessory {
                        GrailsIconButton(accessory, label: accessoryLabel, action: onAccessory)
                    }
                }
                .padding(.leading, CGFloat(ChromeMetrics.fieldInset))
                .padding(.trailing, accessory == nil ? CGFloat(ChromeMetrics.fieldInset) : 2)
                .frame(height: CGFloat(ChromeMetrics.fieldHeight))
                .background(GrailsColor.token(ChromeRole.fieldFill), in: shape)
                .overlay(shape.strokeBorder(GrailsColor.hairline, lineWidth: 1))
                GrailsButton("Copy", kind: .secondary, symbol: ChromeIcon.copy, identifier: identifier, inline: true, action: onCopy)
            }
        }
    }
}

/// One person on the team page. The initial is Geist Bold. Pending adds a dot beside the role.
public struct GrailsPersonRow<Actions: View>: View {
    var email: String
    var subtitle: String
    var role: String
    var pending: Bool
    var revealed: Bool
    var busy: Bool
    var actions: () -> Actions
    @State private var hovering = false

    public init(_ email: String, subtitle: String = "", role: String, pending: Bool = false, revealed: Bool = false, busy: Bool = false, @ViewBuilder actions: @escaping () -> Actions) {
        self.email = email
        self.subtitle = subtitle
        self.role = role
        self.pending = pending
        self.revealed = revealed
        self.busy = busy
        self.actions = actions
    }

    /// Actions replace the role cluster. They stay out of the tree until then, so a hidden button cannot collapse into a sliver.
    private var showActions: Bool {
        (hovering || revealed) && Actions.self != EmptyView.self
    }

    public var body: some View {
        let initial = email.trimmingCharacters(in: .whitespaces).first.map { String($0).uppercased() } ?? ""
        HStack(spacing: CGFloat(Space.sm)) {
            Text(initial)
                .font(ChromeFont.body(TypeScale.label, bold: true))
                .foregroundStyle(GrailsColor.secondary)
                .frame(width: 30, height: 30)
                .background(GrailsInk(.avatar), in: Circle())
            VStack(alignment: .leading, spacing: 0) {
                Text(verbatim: email)
                    .font(ChromeFont.body(TypeScale.body))
                    .foregroundStyle(GrailsColor.text)
                    .lineLimit(1)
                if !subtitle.isEmpty {
                    Text(verbatim: subtitle)
                        .font(ChromeFont.body(TypeScale.help))
                        .foregroundStyle(GrailsColor.tertiary)
                        .lineLimit(1)
                        .layoutPriority(1)
                }
            }
            .layoutPriority(showActions ? 0 : 1)
            Spacer(minLength: CGFloat(Space.sm))
            if busy {
                GrailsSpinner()
            } else if showActions {
                HStack(spacing: CGFloat(Space.xs)) {
                    actions()
                }
                .fixedSize(horizontal: true, vertical: false)
            } else {
                HStack(spacing: 6) {
                    Text(role)
                        .font(ChromeFont.body(TypeScale.help))
                        .foregroundStyle(GrailsColor.secondary)
                        .lineLimit(1)
                    if pending {
                        Circle().fill(GrailsColor.tertiary).frame(width: 5, height: 5)
                        Text("Pending")
                            .font(ChromeFont.body(TypeScale.help))
                            .foregroundStyle(GrailsColor.secondary)
                            .lineLimit(1)
                    }
                }
            }
        }
        .padding(.horizontal, CGFloat(Space.sm))
        .frame(height: 52)
        .background {
            RoundedRectangle(cornerRadius: CGFloat(RadiusToken.row), style: .continuous)
                .fill(hovering ? GrailsColor.fill : GrailsInk(.canvas, opacity: 0))
                .animation(.grailsQuick, value: hovering)
        }
        .onHover { hovering = $0 }
    }
}

public extension GrailsPersonRow where Actions == EmptyView {
    init(_ email: String, subtitle: String = "", role: String, pending: Bool = false, revealed: Bool = false, busy: Bool = false) {
        self.init(email, subtitle: subtitle, role: role, pending: pending, revealed: revealed, busy: busy) { EmptyView() }
    }
}

public struct GrailsToast: View {
    var text: String
    var symbol: String

    public init(_ text: String, symbol: String = "checkmark.circle") {
        self.text = text
        self.symbol = symbol
    }

    public var body: some View {
        HStack(spacing: CGFloat(Space.xs)) {
            Image(systemName: symbol)
                .font(ChromeFont.symbol(13, weight: .medium))
                .foregroundStyle(symbol == ChromeIcon.error ? GrailsColor.destructive : GrailsColor.secondary)
            Text(text)
                .font(ChromeFont.body(TypeScale.button))
                .foregroundStyle(GrailsColor.text)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(GrailsColor.surface, in: RoundedRectangle(cornerRadius: CGFloat(RadiusToken.card), style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: CGFloat(RadiusToken.card), style: .continuous).strokeBorder(GrailsColor.hairline, lineWidth: 1))
        // caps the width offered to the text, so a long message wraps; the card still hugs a short one
        .frame(maxWidth: 420)
    }
}

public extension View {
    /// Places a toast (or the stack it leads) by `ToastPlacement`. Apply it to a view that spans the whole window.
    func grailsToastPlacement() -> some View {
        frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .padding(.bottom, CGFloat(ToastPlacement.bottomInset))
    }
}

/// Body, then footer, then the hairline. The hairline is placed only when the body actually overflows, in the same layout pass.
private struct ModalSplit: Layout {
    var showsFooter: Bool

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? CGFloat(ModalMetrics.width)
        let parts = measure(width: width, subviews: subviews)
        return CGSize(width: width, height: parts.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard subviews.count >= 2 else { return }
        let parts = measure(width: bounds.width, subviews: subviews)
        var y = bounds.minY
        subviews[0].place(at: CGPoint(x: bounds.minX, y: y), proposal: ProposedViewSize(width: bounds.width, height: parts.body))
        y += parts.body + parts.below
        let rule = parts.rule ? 1 : 0
        // The footer's Group flattens into this layout, so the 1 pt spacer can sit between the footer and the rule. The rule is always last.
        if subviews.count >= 3 {
            subviews[subviews.count - 1].place(
                at: CGPoint(x: bounds.minX, y: parts.rule ? y : bounds.maxY),
                proposal: ProposedViewSize(width: parts.rule ? bounds.width : 0, height: CGFloat(rule))
            )
            for index in 2..<(subviews.count - 1) {
                subviews[index].place(at: CGPoint(x: bounds.minX, y: bounds.maxY), proposal: ProposedViewSize(width: 0, height: 0))
            }
        }
        y += CGFloat(rule)
        if parts.footer > 1, subviews.count >= 2 {
            let footerWidth = bounds.width - CGFloat(ModalMetrics.padding) * 2
            subviews[1].place(
                at: CGPoint(x: bounds.minX + CGFloat(ModalMetrics.padding), y: y),
                proposal: ProposedViewSize(width: footerWidth, height: parts.footer)
            )
        } else {
            subviews[1].place(at: CGPoint(x: bounds.minX, y: y), proposal: ProposedViewSize(width: 0, height: 0))
        }
    }

    private func measure(width: CGFloat, subviews: Subviews) -> (body: CGFloat, footer: CGFloat, below: CGFloat, rule: Bool, height: CGFloat) {
        let cap = CGFloat(ChromeMetrics.maxBody)
        // Propose the cap, not an open height. A flexible scroll would otherwise report its own minimum and an empty body would still count.
        let body = subviews.first?.sizeThatFits(ProposedViewSize(width: width, height: cap)).height ?? 0
        let footerWidth = width - CGFloat(ModalMetrics.padding) * 2
        let footer = showsFooter ? (subviews.dropFirst().first?.sizeThatFits(ProposedViewSize(width: footerWidth, height: nil)).height ?? 0) : 0
        let liveFooter = footer > 1
        let liveBody = body > 1
        let scrolls = body >= cap - 0.5
        let rule = ModalDivider.shows(hasBody: liveBody, hasFooter: liveFooter, scrolls: scrolls)
        let below: CGFloat = liveFooter ? CGFloat(ModalMetrics.footerGap) : CGFloat(ModalMetrics.padding)
        let footerBlock = liveFooter ? footer + CGFloat(ModalMetrics.padding) : 0
        return (body, footer, below, rule, body + below + (rule ? 1 : 0) + footerBlock)
    }
}

private struct SnapshotRenderingKey: EnvironmentKey {
    static let defaultValue = false
}

public extension EnvironmentValues {
    /// Set while a picture is drawn offscreen. AppKit text fields paint a yellow bar there, and scroll views paint empty.
    public var grailsSnapshot: Bool {
        get { self[SnapshotRenderingKey.self] }
        set { self[SnapshotRenderingKey.self] = newValue }
    }
}

/// The body's height is the content, capped. An empty view stays empty: the scroll frame's minimum is not content.
private struct FittingScroll<Content: View>: View {
    var maxHeight: CGFloat
    @ViewBuilder var content: () -> Content
    @Environment(\.grailsSnapshot) private var snapshot

    var body: some View {
        if snapshot {
            content()
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            ViewThatFits(in: .vertical) {
                content()
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .fixedSize(horizontal: false, vertical: true)
                ScrollView {
                    content()
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                .frame(height: maxHeight)
            }
        }
    }
}

public struct GrailsKeychainNotice: View {
    var onContinue: () -> Void
    var onClose: () -> Void

    public init(onContinue: @escaping () -> Void, onClose: @escaping () -> Void) {
        self.onContinue = onContinue
        self.onClose = onClose
    }

    public var body: some View {
        GrailsModal(title: KeychainNoticeCopy.title, step: "keychain", identifier: "keychain-notice", onClose: onClose) {
            HStack(alignment: .top, spacing: CGFloat(Space.sm)) {
                Image(systemName: KeychainNoticeCopy.symbol)
                    .font(ChromeFont.symbol(16, weight: .medium))
                    .foregroundStyle(GrailsColor.secondary)
                    .frame(width: 20)
                Text(KeychainNoticeCopy.body)
                    .font(ChromeFont.body(TypeScale.body))
                    .foregroundStyle(GrailsColor.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } footer: {
            HStack {
                Spacer()
                GrailsButton(KeychainNoticeCopy.action, kind: .primary, identifier: "keychain-continue", action: onContinue)
            }
        }
    }
}

/// Asks before a destructive bucket action. Cancel is the default; the action draws as destructive and has no Return shortcut.
public struct GrailsConfirmModal: View {
    var confirm: DestructiveConfirm
    var onCancel: () -> Void
    var onConfirm: () -> Void

    public init(_ confirm: DestructiveConfirm, onCancel: @escaping () -> Void, onConfirm: @escaping () -> Void) {
        self.confirm = confirm
        self.onCancel = onCancel
        self.onConfirm = onConfirm
    }

    public var body: some View {
        GrailsModal(title: confirm.title, step: "confirm", identifier: "confirm-\(confirm.id)", onClose: onCancel) {
            Text(confirm.message)
                .font(ChromeFont.body(TypeScale.subtitle))
                .foregroundStyle(GrailsColor.secondary)
                .fixedSize(horizontal: false, vertical: true)
        } footer: {
            HStack(spacing: CGFloat(Space.xs)) {
                Spacer()
                GrailsButton("Cancel", kind: .secondary, identifier: "confirm-cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                GrailsButton(confirm.action, kind: .destructive, symbol: confirm.symbol, identifier: "confirm-destructive", action: onConfirm)
            }
        }
    }
}

/// The one container a modal is: the canvas in the sheet shape, the dark edge, the shadow. `GrailsModalLayer` draws it around
/// whatever it presents and moves it as one piece; a `GrailsModal` inside it then draws none of its own, so a frame never stands
/// still while its contents move. Outside the layer (the gallery, a snapshot) the modal draws its own.
struct ModalCard: ViewModifier {
    @Environment(\.grailsInModalCard) private var inCard
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        if inCard {
            content
        } else {
            let shape = RoundedRectangle(cornerRadius: CGFloat(RadiusToken.sheet), style: .continuous)
            content
                .environment(\.grailsInModalCard, true)
                .background(GrailsColor.canvas, in: shape)
                .overlay {
                    if scheme == .dark {
                        shape.strokeBorder(Color.white.opacity(0.06), lineWidth: 0.5)
                    }
                }
                .clipShape(shape)
                .compositingGroup()
                .shadow(color: .black.opacity(scheme == .dark ? 0.5 : 0.10), radius: scheme == .dark ? 24 : 20, y: scheme == .dark ? 16 : 12)
                .shadow(color: .black.opacity(scheme == .dark ? 0 : 0.04), radius: 1, y: 1)
        }
    }
}

private struct InModalCardKey: EnvironmentKey {
    static let defaultValue = false
}

public extension EnvironmentValues {
    /// Inside a modal card already: a nested `GrailsModal` draws no second frame.
    var grailsInModalCard: Bool {
        get { self[InModalCardKey.self] }
        set { self[InModalCardKey.self] = newValue }
    }
}

public extension View {
    /// The modal card around this view, unless it is inside one already.
    func grailsModalCard() -> some View { modifier(ModalCard()) }
}

public struct GrailsModal<Content: View, Footer: View>: View {
    var title: String
    var subtitle: String?
    var step: String
    var error: String?
    var width: CGFloat
    var identifier: String
    var showsFooter: Bool
    var onClose: (() -> Void)?
    var content: () -> Content
    var footer: () -> Footer
    @Environment(\.grailsReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var scheme

    public init(title: String, subtitle: String? = nil, step: String, error: String? = nil, width: CGFloat = CGFloat(ModalMetrics.width), identifier: String = "", showsFooter: Bool = true, onClose: (() -> Void)? = nil, @ViewBuilder content: @escaping () -> Content, @ViewBuilder footer: @escaping () -> Footer) {
        self.title = title
        self.subtitle = subtitle
        self.step = step
        self.error = error
        self.width = width
        self.identifier = identifier
        self.showsFooter = showsFooter
        self.onClose = onClose
        self.content = content
        self.footer = footer
    }

    public var body: some View {
        ZStack(alignment: .topLeading) {
            page
                .id(step)
                .frame(maxWidth: .infinity, alignment: .leading)
                .transition(GrailsPage.transition)
        }
        .frame(width: width, alignment: .topLeading)
        .grailsModalCard()
        .animation(.grails(GrailsPage.animation, reduceMotion: reduceMotion), value: step)
        .accessibilityElement(children: .contain)
        .modifier(ChromeIdentifier(id: identifier))
    }

    private var page: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, CGFloat(ModalMetrics.padding))
                .padding(.top, CGFloat(ModalMetrics.paddingTop))
                .padding(.bottom, CGFloat(Space.lg))
            ModalSplit(showsFooter: showsFooter) {
                FittingScroll(maxHeight: CGFloat(ChromeMetrics.maxBody)) {
                    VStack(alignment: .leading, spacing: CGFloat(ModalMetrics.gap)) {
                        content()
                        if let error, !error.isEmpty {
                            HStack(alignment: .firstTextBaseline, spacing: 4) {
                                Image(systemName: ChromeIcon.error)
                                Text(error).fixedSize(horizontal: false, vertical: true)
                            }
                            .font(ChromeFont.body(TypeScale.help))
                            .foregroundStyle(GrailsColor.text)
                        }
                    }
                    .padding(.horizontal, CGFloat(ModalMetrics.padding))
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .fixedSize(horizontal: false, vertical: true)
                }
                Group {
                    if showsFooter { footer() }
                    // An empty footer is dropped from the layout, and the rule then takes the body.
                    Color.clear.frame(width: 1, height: 1).accessibilityHidden(true)
                }
                GrailsRule()
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: CGFloat(Space.sm)) {
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(ChromeFont.display(TypeScale.title))
                    .tracking(TypeScale.titleTracking)
                    .foregroundStyle(GrailsColor.text)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(ChromeFont.body(TypeScale.body))
                        .foregroundStyle(GrailsColor.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let onClose {
                GrailsIconButton(ChromeIcon.close, label: "Close", action: onClose)
            }
        }
    }
}

/// The cloud bucket page. New Workspace and the gallery both use it, so the sheet cannot drift.
public struct GrailsBucketForm: View {
    @Binding var draft: BucketDraft
    @Binding var showRegion: Bool
    var onSubmit: () -> Void

    public init(draft: Binding<BucketDraft>, showRegion: Binding<Bool>, onSubmit: @escaping () -> Void = {}) {
        self._draft = draft
        self._showRegion = showRegion
        self.onSubmit = onSubmit
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: CGFloat(ChromeMetrics.sectionGap)) {
            GrailsSection(BucketDraft.bucketSection, symbol: ChromeIcon.bucket) {
                VStack(alignment: .leading, spacing: CGFloat(ChromeMetrics.groupGap)) {
                    text("endpoint", value: $draft.endpoint, error: draft.endpointError, autofocus: true)
                    text("bucket", value: $draft.bucket)
                    GrailsDisclosure("Region", value: draft.regionForSave, expanded: $showRegion) {
                        GrailsInlineField(text: $draft.region, placeholder: BucketDraft.field("region").placeholder, identifier: "bucket-region", onSubmit: onSubmit)
                    }
                    text("accessKey", value: $draft.accessKey)
                    secure("secret", value: $draft.secret)
                    text("email", value: $draft.email, error: draft.emailError)
                }
            }
            GrailsSection(BucketDraft.invitesSection, symbol: ChromeIcon.invite, tag: BucketDraft.invitesTag, detail: BucketDraft.invitesDetail) {
                VStack(alignment: .leading, spacing: CGFloat(ChromeMetrics.groupGap)) {
                    text("accountID", value: $draft.accountID)
                    secure("apiToken", value: $draft.apiToken)
                }
            }
        }
    }

    private func text(_ id: String, value: Binding<String>, error: String? = nil, autofocus: Bool = false) -> some View {
        let spec = BucketDraft.field(id)
        return GrailsTextField(spec.label, text: value, required: spec.required, error: error, placeholder: spec.placeholder, identifier: fieldID(id), corrects: false, autofocus: autofocus, onSubmit: onSubmit)
    }

    private func secure(_ id: String, value: Binding<String>) -> some View {
        let spec = BucketDraft.field(id)
        return GrailsSecureField(spec.label, text: value, required: spec.required, placeholder: spec.placeholder, identifier: fieldID(id), showsPaste: true, onSubmit: onSubmit)
    }

    private func fieldID(_ id: String) -> String {
        switch id {
        case "endpoint": "bucket-endpoint"
        case "bucket": "bucket-name"
        case "accessKey": "bucket-key"
        case "secret": "bucket-secret"
        case "email": "bucket-email"
        case "accountID": "bucket-account"
        case "apiToken": "bucket-token"
        default: id
        }
    }
}

/// The cloud bucket sheet, empty, so Create stays a disabled primary. The gallery and the snapshot both render this.
/// Three modal frames for the divider snapshot: both sides, body only, footer only.
public struct GrailsModalDividerPreview: View {
    public enum Kind: String { case both, body, footer, scroll }
    var kind: Kind

    public init(_ kind: Kind) { self.kind = kind }

    public var body: some View {
        switch kind {
        case .both:
            GrailsModal(title: "Invite", step: "both", onClose: {}) {
                ModalSampleBody()
            } footer: {
                GrailsButton("Continue", enabled: false) {}
            }
        case .body:
            GrailsModal(title: "Invite", step: "body", showsFooter: true, onClose: {}) {
                ModalSampleBody()
            } footer: {
                EmptyView()
            }
        case .footer:
            GrailsModal(title: "Invite", step: "footer", onClose: {}) {
                EmptyView()
            } footer: {
                GrailsButton("Done") {}
            }
        case .scroll:
            GrailsModal(title: "Invite", step: "scroll", onClose: {}) {
                VStack(alignment: .leading, spacing: CGFloat(Space.sm)) {
                    ForEach(0..<28, id: \.self) { index in
                        Text("Reference \(index + 1)")
                            .font(ChromeFont.body(TypeScale.body))
                            .foregroundStyle(GrailsColor.text)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            } footer: {
                GrailsButton("Continue", enabled: false) {}
            }
        }
    }

}

/// Ink fill, so the divider scan does not mistake the sample for a hairline.
struct ModalSampleBody: View {
    var body: some View {
        Text("name@company.com")
            .font(ChromeFont.body(TypeScale.body))
            .foregroundStyle(GrailsColor.canvas)
            .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
            .padding(.horizontal, 8)
            .background(GrailsColor.text)
    }
}

/// Invite step with Person and Role. The body is short, so the footer has no rule. Continue is disabled.
public struct GrailsInviteRolePreview: View {
    @State private var email = ""

    public init() {}

    public var body: some View {
        GrailsModal(title: "Invite", step: "email", onClose: {}) {
            VStack(alignment: .leading, spacing: CGFloat(ChromeMetrics.groupGap)) {
                GrailsTextField("Email", text: $email, required: true, placeholder: "name@company.com", identifier: "bucket-invite-email", corrects: false)
                VStack(alignment: .leading, spacing: CGFloat(ChromeMetrics.labelGap)) {
                    Text("Role")
                        .font(ChromeFont.body(TypeScale.label))
                        .foregroundStyle(GrailsColor.token(ChromeRole.label))
                    GrailsSegmented(options: [
                        GrailsSegmented.Option(id: "member", title: "Member", identifier: "bucket-invite-role-member"),
                        GrailsSegmented.Option(id: "admin", title: "Admin", enabled: false, help: InviteRolePreview.adminLocked, identifier: "bucket-invite-role-admin"),
                    ], selection: "member") { _ in }
                    Text(InviteRolePreview.membersHelp)
                        .font(ChromeFont.body(TypeScale.help))
                        .foregroundStyle(GrailsColor.secondary)
                        .padding(.top, 2)
                }
            }
        } footer: {
            HStack(spacing: CGFloat(ModalMetrics.buttonGap)) {
                Spacer()
                GrailsButton("Cancel", kind: .secondary) {}
                GrailsButton("Create invite", enabled: false) {}
            }
        }
    }
}

public enum InviteRolePreview {
    public static let adminLocked = "Only the owner can invite an admin."
    public static let membersHelp = "Members can add and edit. Admins can also invite and manage people."
}

public struct GrailsBucketSheetPreview: View {
    @State private var draft = BucketDraft()
    @State private var showRegion = false

    public init() {}

    public var body: some View {
        GrailsModal(title: WorkspaceStep.bucket.title, step: WorkspaceStep.bucket.rawValue, onClose: {}) {
            GrailsBucketForm(draft: $draft, showRegion: $showRegion)
        } footer: {
            HStack {
                GrailsBackButton {}
                Spacer()
                GrailsButton("Create", enabled: draft.canCreate) {}
            }
        }
    }
}
