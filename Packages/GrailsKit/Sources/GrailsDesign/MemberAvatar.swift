import AppKit
import SwiftUI

/// Everything needed to draw one person's avatar: their photo when they chose one, else their generated blob.
public struct MemberFace {
    public var memberID: String
    public var name: String
    public var photo: NSImage?
    public var tint: Int?
    public var character: Int?

    public init(memberID: String, name: String, photo: NSImage? = nil, tint: Int? = nil, character: Int? = nil) {
        self.memberID = memberID
        self.name = name
        self.photo = photo
        self.tint = tint
        self.character = character
    }

    public var spec: DitherAvatarSpec { DitherAvatarSpec(memberID: memberID, name: name, tint: tint, character: character) }
}

/// The small name bubble over an avatar. It fades in on `Motion.quick` with the ease-out curve, never on a spring,
/// and appears at once under Reduce Motion.
public enum NameBubble {
    public static let fontSize = 11.0
    public static let insetX = 7.0
    public static let insetY = 3.0
    public static let radius = 6.0
    /// Space between the avatar and the bubble.
    public static let gap = 4.0
    public static let fill = Token.text
    public static let label = Token.canvas

    /// What the bubble says: the display name, or nothing (no bubble) for an empty one.
    public static func text(for name: String) -> String? {
        let t = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }

    /// How long the pointer rests before the bubble opens. Zero opens on the rest itself.
    /// A scroll starts this wait over, so a hover does not survive the scroll.
    public static let rest: TimeInterval = 0

    /// How long the fade in or out runs. Zero under Reduce Motion.
    public static func fade(reduceMotion: Bool) -> TimeInterval { reduceMotion ? 0 : Motion.quick }

    public static func animation(reduceMotion: Bool) -> Animation? { reduceMotion ? nil : .grailsQuick }
}

// MARK: SwiftUI

/// A person's avatar: their photo, or their generated blob. Hovering shows their name in a bubble above it.
public struct GrailsMemberAvatar: View {
    var face: MemberFace
    var side: CGFloat
    var showsName: Bool
    @Environment(\.colorScheme) private var scheme
    @Environment(\.displayScale) private var scale

    public init(_ face: MemberFace, side: CGFloat = 18, showsName: Bool = true) {
        self.face = face
        self.side = side
        self.showsName = showsName
    }

    public var body: some View {
        picture
            .frame(width: side, height: side)
            .clipShape(Circle())
            .overlay(Circle().strokeBorder(GrailsInk(.hairline), lineWidth: 0.5))
            .modifier(NameBubbleHover(name: showsName ? face.name : ""))
            .accessibilityElement()
            .accessibilityLabel(face.name.isEmpty ? "Avatar" : "\(face.name) avatar")
    }

    @ViewBuilder private var picture: some View {
        if let photo = face.photo {
            Image(nsImage: photo).resizable().aspectRatio(contentMode: .fill)
        } else if let cg = DitherAvatar.image(face.spec, side: side, scale: scale, dark: scheme == .dark) {
            Image(decorative: cg, scale: scale).interpolation(.none).resizable()
        } else {
            Rectangle().fill(GrailsInk(.avatar))
        }
    }
}

/// The name bubble, as a hover modifier. Any view can carry it; `GrailsMemberAvatar` does.
/// The open bubble belongs to `NameBubbleCoordinator`, not to this view.
private struct NameBubbleHover: ViewModifier {
    var name: String
    @State private var token = UUID()
    @State private var shown = false
    @Environment(\.grailsReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        let text = NameBubble.text(for: name)
        content
            .background { NameBubbleAnchor(token: token, active: text != nil, reduceMotion: reduceMotion, shown: $shown) }
            .overlay(alignment: .top) {
                if let text {
                    GrailsNameBubble(text: text)
                        .fixedSize()
                        .alignmentGuide(.top) { d in d[.bottom] + CGFloat(NameBubble.gap) }
                        .opacity(shown ? 1 : 0)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .zIndex(shown ? 1 : 0)
            .onDisappear { NameBubbleHost.shared.detach(token) }
    }
}

/// Puts an AppKit probe under a SwiftUI avatar so hover reaches `NameBubbleHost`.
private struct NameBubbleAnchor: NSViewRepresentable {
    var token: UUID
    var active: Bool
    var reduceMotion: Bool
    @Binding var shown: Bool

    func makeNSView(context: Context) -> NameBubbleProbe {
        let view = NameBubbleProbe()
        view.token = token
        return view
    }

    func updateNSView(_ view: NameBubbleProbe, context: Context) {
        if view.token != token {
            NameBubbleHost.shared.detach(view.token)
            view.token = token
        }
        view.active = active
        let motion = reduceMotion
        view.onShow = { on, snap in
            let animation = (snap || motion) ? nil : NameBubble.animation(reduceMotion: false)
            if let animation {
                withAnimation(animation) { shown = on }
            } else {
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) { shown = on }
            }
        }
        if active {
            NameBubbleHost.shared.attach(token, view: view) { [weak view] on, snap in view?.onShow?(on, snap) }
        } else {
            NameBubbleHost.shared.removed(token)
        }
    }

    static func dismantleNSView(_ view: NameBubbleProbe, coordinator: Void) {
        NameBubbleHost.shared.detach(view.token)
    }
}

public extension View {
    /// Shows `name` in the Grails name bubble while the pointer is over this view.
    func grailsNameBubble(_ name: String) -> some View { modifier(NameBubbleHover(name: name)) }
}

/// The bubble itself: a small pill, text on the inverse of the canvas.
public struct GrailsNameBubble: View {
    var text: String
    public init(text: String) { self.text = text }

    public var body: some View {
        Text(verbatim: text)
            .font(ChromeFont.body(NameBubble.fontSize))
            .foregroundStyle(GrailsInk(NameBubble.label))
            .lineLimit(1)
            .padding(.horizontal, CGFloat(NameBubble.insetX))
            .padding(.vertical, CGFloat(NameBubble.insetY))
            .background(RoundedRectangle(cornerRadius: CGFloat(NameBubble.radius), style: .continuous).fill(GrailsInk(NameBubble.fill)))
    }
}

// MARK: AppKit

/// The avatar for an AppKit surface such as a grid tile. The picture is a cached image set as layer contents; nothing draws per frame.
/// Hovering shows a `NameBubbleView` beside it, inside the same superview.
public final class MemberAvatarView: NSView {
    public private(set) var face: MemberFace?
    public let bubble = NameBubbleView()
    private let bubbleToken = UUID()
    private var tracking: NSTrackingArea?

    public override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layerContentsRedrawPolicy = .never
        layer?.masksToBounds = true
        layer?.contentsGravity = .resizeAspectFill
        layer?.magnificationFilter = .nearest
        layer?.borderWidth = 1
        bubble.alphaValue = 0
        bubble.isHidden = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    public func show(_ face: MemberFace?) {
        let changed = face?.memberID != self.face?.memberID || face?.name != self.face?.name || face?.photo !== self.face?.photo
            || face?.tint != self.face?.tint || face?.character != self.face?.character
        let personChanged = face?.memberID != self.face?.memberID
        self.face = face
        bubble.text = face.flatMap { NameBubble.text(for: $0.name) } ?? ""
        setAccessibilityLabel(face.map { "\($0.name) avatar" })
        setAccessibilityElement(face != nil)
        if personChanged || bubble.text.isEmpty { NameBubbleHost.shared.removed(bubbleToken) }
        if changed { paint() }
    }

    private func paint() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        guard let face else { layer?.contents = nil; return }
        let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        layer?.borderColor = NSColor.white.withAlphaComponent(dark ? 0.35 : 0.8).cgColor // on image
        if let photo = face.photo {
            layer?.contents = photo.layerContents(forContentsScale: scale)
            layer?.magnificationFilter = .linear
        } else {
            layer?.contents = DitherAvatar.image(face.spec, side: max(bounds.width, 1), scale: scale, dark: dark)
            layer?.magnificationFilter = .nearest
        }
        layer?.contentsScale = scale
    }

    private var scale: CGFloat { window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2 }

    public override func layout() {
        super.layout()
        layer?.cornerRadius = bounds.width / 2
    }

    public override func setFrameSize(_ newSize: NSSize) {
        let grew = newSize != frame.size
        super.setFrameSize(newSize)
        layer?.cornerRadius = newSize.width / 2
        if grew { paint() }
    }

    public override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); paint() }
    public override func viewDidChangeBackingProperties() { super.viewDidChangeBackingProperties(); paint() }

    public override func viewWillMove(toSuperview newSuperview: NSView?) {
        if newSuperview == nil { NameBubbleHost.shared.detach(bubbleToken) }
        else { NameBubbleHost.shared.removed(bubbleToken) }
        bubble.removeFromSuperview()
        super.viewWillMove(toSuperview: newSuperview)
    }

    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil else {
            NameBubbleHost.shared.detach(bubbleToken)
            return
        }
        NameBubbleHost.shared.attach(bubbleToken, view: self) { [weak self] on, snap in
            self?.setHovering(on, reduceMotion: snap || ReduceMotion.isOn)
        }
    }

    public override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self)
        addTrackingArea(area)
        tracking = area
    }

    public override func mouseEntered(with event: NSEvent) {
        guard !bubble.text.isEmpty else { return }
        NameBubbleHost.shared.attach(bubbleToken, view: self) { [weak self] on, snap in
            self?.setHovering(on, reduceMotion: snap || ReduceMotion.isOn)
        }
        NameBubbleHost.shared.entered(bubbleToken)
    }

    public override func mouseExited(with event: NSEvent) { NameBubbleHost.shared.exited(bubbleToken) }

    public override var isHidden: Bool {
        didSet { if isHidden { NameBubbleHost.shared.removed(bubbleToken) } }
    }

    /// Shows or hides the name bubble beside the avatar, clamped inside the superview.
    public func setHovering(_ on: Bool, reduceMotion: Bool = ReduceMotion.isOn) {
        guard let host = superview else { return }
        if on {
            guard !bubble.text.isEmpty else { return }
            if bubble.superview !== host { host.addSubview(bubble, positioned: .above, relativeTo: self) }
            let size = bubble.fittingSize
            let x = frame.maxX + CGFloat(NameBubble.gap)
            let width = min(size.width, max(0, host.bounds.width - x - CGFloat(NameBubble.gap)))
            bubble.frame = NSRect(x: x, y: frame.midY - size.height / 2, width: width, height: size.height).integral
            bubble.isHidden = false
        }
        let target: CGFloat = on ? 1 : 0
        let duration = NameBubble.fade(reduceMotion: reduceMotion)
        guard duration > 0 else {
            bubble.alphaValue = target
            if !on { bubble.isHidden = true }
            return
        }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = duration
            ctx.timingFunction = .grailsStandard
            bubble.animator().alphaValue = target
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self, !on, self.bubble.alphaValue == 0 else { return }
                self.bubble.isHidden = true
            }
        }
    }
}

/// The name bubble for AppKit. Draws its own pill and text; no text field.
public final class NameBubbleView: NSView {
    public var text = "" { didSet { if text != oldValue { invalidateIntrinsicContentSize(); needsDisplay = true } } }

    private var attributes: [NSAttributedString.Key: Any] {
        [.font: ChromeNSFont.body(CGFloat(NameBubble.fontSize)), .foregroundColor: GrailsNSColor.token(NameBubble.label)]
    }

    public override var intrinsicContentSize: NSSize {
        let s = (text as NSString).size(withAttributes: attributes)
        return NSSize(width: ceil(s.width + 2 * NameBubble.insetX), height: ceil(s.height + 2 * NameBubble.insetY))
    }

    public override var fittingSize: NSSize { intrinsicContentSize }

    public override func draw(_ dirtyRect: NSRect) {
        GrailsNSColor.token(NameBubble.fill).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: CGFloat(NameBubble.radius), yRadius: CGFloat(NameBubble.radius)).fill()
        let s = (text as NSString).size(withAttributes: attributes)
        let rect = NSRect(x: CGFloat(NameBubble.insetX), y: (bounds.height - s.height) / 2, width: bounds.width - 2 * CGFloat(NameBubble.insetX), height: s.height)
        let style = NSMutableParagraphStyle()
        style.lineBreakMode = .byTruncatingTail
        var attrs = attributes
        attrs[.paragraphStyle] = style
        (text as NSString).draw(with: rect, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], attributes: attrs)
    }

    public override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

// MARK: Settings

/// The generated avatar's colours as two rows of swatches. The one in use carries a ring.
public struct GrailsAvatarSwatches: View {
    var selected: Int
    var onPick: (Int) -> Void
    @Environment(\.colorScheme) private var scheme

    public init(selected: Int, onPick: @escaping (Int) -> Void) {
        self.selected = selected
        self.onPick = onPick
    }

    public var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.fixed(20), spacing: 6), count: (DitherAvatar.tones.count + 1) / 2), spacing: 6) {
            ForEach(DitherAvatar.tones.indices, id: \.self) { i in
                let tone = DitherAvatar.tones[i]
                GrailsControl(press: .icon) { onPick(i) } label: {
                    Circle()
                        .fill(CanonTokens.color(tone.base(dark: scheme == .dark)))
                        .frame(width: 16, height: 16)
                        .padding(2)
                        .overlay(Circle().strokeBorder(GrailsInk(.text), lineWidth: i == selected ? 1.5 : 0))
                        .contentShape(Circle())
                }
                .help(tone.name)
                .accessibilityLabel(tone.name)
                .accessibilityAddTraits(i == selected ? .isSelected : [])
                .accessibilityIdentifier("avatar-tone-\(i)")
            }
        }
        .fixedSize()
    }
}

/// Settings ▸ Profile: the avatar large, then one compact row of choices under it. Everyone starts with a generated blob and
/// shuffles until they like one; a photo replaces the blob until it is removed. There is no mode switch.
public struct GrailsAvatarEditor: View {
    public static let side: CGFloat = 72

    var face: MemberFace
    var onShuffle: () -> Void
    var onPickTone: (Int) -> Void
    var onUploadPhoto: () -> Void
    var onRemovePhoto: () -> Void
    @Environment(\.grailsReduceMotion) private var reduceMotion

    public init(_ face: MemberFace, onShuffle: @escaping () -> Void, onPickTone: @escaping (Int) -> Void,
                onUploadPhoto: @escaping () -> Void, onRemovePhoto: @escaping () -> Void) {
        self.face = face
        self.onShuffle = onShuffle
        self.onPickTone = onPickTone
        self.onUploadPhoto = onUploadPhoto
        self.onRemovePhoto = onRemovePhoto
    }

    /// Changes whenever the picture does, so a shuffle swaps the old avatar for the new one instead of redrawing in place.
    private var look: String {
        let photo = face.photo.map { "\(ObjectIdentifier($0).hashValue)" } ?? "-"
        return "\(face.spec.tone).\(face.character ?? -1).\(photo)"
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: CGFloat(Space.sm)) {
            ZStack {
                GrailsMemberAvatar(face, side: Self.side, showsName: false)
                    .id(look)
                    .transition(.grailsSwap(reduceMotion: reduceMotion))
            }
            .frame(width: Self.side, height: Self.side)
            .animation(.grailsSpring(reduceMotion: reduceMotion), value: look)
            .accessibilityIdentifier("settings-avatar-preview")
            choices
        }
    }

    private var choices: some View {
        HStack(alignment: .center, spacing: CGFloat(Space.sm)) {
            if face.photo == nil {
                GrailsButton("Shuffle", kind: .secondary, symbol: "shuffle", identifier: "settings-avatar-shuffle", action: onShuffle)
                    .help("Another face and colour")
                GrailsAvatarSwatches(selected: face.spec.tone, onPick: onPickTone)
                Spacer(minLength: 0)
                GrailsButton("Upload photo…", kind: .secondary, identifier: "settings-avatar-upload", action: onUploadPhoto)
            } else {
                GrailsButton("Remove photo", kind: .secondary, identifier: "settings-avatar-remove", action: onRemovePhoto)
                Spacer(minLength: 0)
            }
        }
    }
}

/// Settings ▸ Profile as it ships, for the design snapshot: the avatar editor over the username field, on the page canvas.
struct GrailsAvatarEditorPreview: View {
    var photo: NSImage?
    @State private var name = "Ada Lane"

    var body: some View {
        GrailsSettingsGroup("Profile") {
            GrailsSettingsBlock {
                GrailsAvatarEditor(MemberFace(memberID: "sample-member-07", name: name, photo: photo), onShuffle: {}, onPickTone: { _ in },
                                   onUploadPhoto: {}, onRemovePhoto: {})
            }
            GrailsSettingsBlock {
                GrailsTextField("Username", text: $name, required: true)
            }
        }
        .padding(CGFloat(Space.xl))
        .background(GrailsColor.canvas)
    }
}
