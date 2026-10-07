import AppKit
import GrailsKit

/// Text label that ignores the mouse, so clicks and right-clicks reach the tile (and the grid's menu) underneath.
final class PassthroughLabel: NSTextField {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    static func make(wrapping: Bool = false) -> PassthroughLabel {
        let l = PassthroughLabel(frame: .zero)
        l.isEditable = false
        l.isSelectable = false
        l.isBordered = false
        l.drawsBackground = false
        if wrapping { l.cell?.wraps = true; l.cell?.isScrollable = false } else { l.cell?.usesSingleLineMode = true }
        return l
    }
}

/// The small pill at a tile's corner: an optional play symbol and a word or a length. Drawn by hand, with the text's cap height centred in
/// a fixed height, so no font's line metrics can push it out of the pill.
final class BadgePill: NSView {
    private var text = ""
    private var play = false
    private var fill = NSColor.black
    private let font = NSFont.grailsBody(9)
    private static let height: CGFloat = 16

    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    private var textSize: CGSize { (text as NSString).size(withAttributes: [.font: font]) }
    private static let playSize = CGSize(width: 6, height: 7)

    override var intrinsicContentSize: NSSize {
        NSSize(width: 6 + (play ? Self.playSize.width + 3 : 0) + ceil(textSize.width) + 6, height: Self.height)
    }

    func show(_ text: String, play: Bool, color: NSColor) {
        self.text = text; self.play = play; fill = color
        invalidateIntrinsicContentSize()
        needsDisplay = true
        superview?.needsLayout = true
    }

    override func draw(_ dirtyRect: NSRect) {
        fill.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 4, yRadius: 4).fill()
        var x: CGFloat = 6
        if play {
            let r = NSRect(x: x, y: (bounds.height - Self.playSize.height) / 2, width: Self.playSize.width, height: Self.playSize.height)
            let path = NSBezierPath()
            path.move(to: NSPoint(x: r.minX, y: r.minY)); path.line(to: NSPoint(x: r.maxX, y: r.midY)); path.line(to: NSPoint(x: r.minX, y: r.maxY)); path.close()
            NSColor.onImage.setFill(); path.fill()
            x += Self.playSize.width + 3
        }
        // flipped: the line box's top is y; the baseline is ascender below it, and the cap height is centred on the pill
        let baseline = (bounds.height + font.capHeight) / 2
        (text as NSString).draw(at: NSPoint(x: x, y: baseline - font.ascender), withAttributes: [.font: font, .foregroundColor: NSColor.onImage])
    }
}

final class TileView: NSView {
    /// What VoiceOver reads (and UI tests find): the item's name.
    var axLabel: String?
    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityLabel() -> String? { axLabel }
    override func accessibilityRole() -> NSAccessibility.Role? { .image }
    override var wantsUpdateLayer: Bool { true }
    override var isFlipped: Bool { true }
    override func updateLayer() {}
    /// A light/dark switch: layer colours don't follow by themselves.
    var onAppearanceChange: (() -> Void)?
    /// Positions the tile's chrome. Called from `layout` so a zoom doesn't run a constraint solve per tile.
    var place: (() -> Void)?
    private var placing = false
    override func layout() {
        super.layout()
        guard !placing else { return }
        placing = true
        place?()
        placing = false
    }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); onAppearanceChange?() }

    /// A right-click lands on the tile first; let the grid build the context menu.
    override func menu(for event: NSEvent) -> NSMenu? {
        var v: NSView? = superview
        while let view = v {
            if let grid = view as? GrailsCollectionView { return grid.menu(for: event) }
            v = view.superview
        }
        return super.menu(for: event)
    }
}

final class ThumbCell: NSCollectionViewItem {
    static let identifier = NSUserInterfaceItemIdentifier("ThumbCell")
    private var op: Operation?
    private var source: (id: String, thumb: URL, original: URL?, variant: String)?
    private(set) var itemID: String?
    private let placeholder = NSImageView()
    private let heart = NSImageView()
    private let captionBar = NSView()
    private let caption = PassthroughLabel.make()
    private let titleLabel = PassthroughLabel.make(wrapping: true)
    private let siteLabel = PassthroughLabel.make()
    private let badge = BadgePill()
    private let cloud = NSImageView()
    private let avatar = PassthroughLabel.make()
    private let sectionLabel = PassthroughLabel.make()
    private var isSection = false

    override func loadView() {
        let v = TileView()
        v.wantsLayer = true
        v.autoresizesSubviews = false
        v.place = { [weak self] in self?.placeChrome() }
        v.layer?.masksToBounds = true
        v.layer?.backgroundColor = NSColor.ink(.surface).cgColor
        v.layer?.contentsGravity = .resizeAspect
        v.layer?.magnificationFilter = .trilinear
        v.layer?.minificationFilter = .trilinear
        placeholder.imageScaling = .scaleProportionallyDown
        placeholder.contentTintColor = .ink(.tertiary)
        v.addSubview(placeholder)
        heart.image = NSImage(systemSymbolName: "heart.fill", accessibilityDescription: "Liked")
        heart.contentTintColor = .onImage
        heart.shadow = {
            let sh = NSShadow(); sh.shadowColor = NSColor.black.withAlphaComponent(0.55); sh.shadowBlurRadius = 3; sh.shadowOffset = .zero
            return sh
        }()
        heart.isHidden = true
        v.addSubview(heart)
        // Link cards: caption over the picture, or a big title when there's no picture
        captionBar.wantsLayer = true
        captionBar.layer?.backgroundColor = NSColor.onImageScrim.cgColor
        captionBar.isHidden = true
        caption.font = .grailsBody(11)
        caption.textColor = .onImage
        caption.lineBreakMode = .byTruncatingTail
        captionBar.addSubview(caption)
        v.addSubview(captionBar)
        titleLabel.font = .grailsDisplay(14)
        titleLabel.textColor = .ink(.text)
        titleLabel.alignment = .center
        titleLabel.maximumNumberOfLines = 4
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.isHidden = true
        siteLabel.font = .grailsBody(10)
        siteLabel.textColor = .ink(.secondary)
        siteLabel.alignment = .center
        siteLabel.isHidden = true
        v.addSubview(titleLabel)
        v.addSubview(siteLabel)
        badge.isHidden = true
        v.addSubview(badge)
        sectionLabel.font = .grailsDisplay(26)
        sectionLabel.textColor = .ink(.text)
        sectionLabel.lineBreakMode = .byTruncatingTail
        sectionLabel.isHidden = true
        v.addSubview(sectionLabel)
        cloud.image = NSImage(systemSymbolName: "icloud.and.arrow.down", accessibilityDescription: "Not downloaded yet")
        cloud.contentTintColor = .onImage
        cloud.shadow = heart.shadow
        cloud.isHidden = true
        v.addSubview(cloud)
        avatar.font = .grailsBody(9)
        avatar.textColor = .onImage
        avatar.alignment = .center
        avatar.wantsLayer = true
        avatar.layer?.cornerRadius = 9
        avatar.isHidden = true
        v.addSubview(avatar)
        v.onAppearanceChange = { [weak self] in self?.restyle() }
        view = v
    }

    /// Same insets the constraints used to pin. The tile is flipped; the caption bar is not.
    private func placeChrome() {
        let b = view.bounds
        placeholder.frame = NSRect(x: (b.width - 28) / 2, y: (b.height - 28) / 2, width: 28, height: 28)
        heart.frame = NSRect(x: b.width - 24, y: 8, width: 16, height: 16)
        if !badge.isHidden {
            let badgeSize = badge.intrinsicContentSize
            badge.frame = NSRect(x: 8, y: 8, width: badgeSize.width, height: badgeSize.height)
        }
        cloud.frame = NSRect(x: b.width - 24, y: b.height - 24, width: 16, height: 16)
        avatar.frame = NSRect(x: 8, y: b.height - 26, width: 20, height: 18)
        if !captionBar.isHidden {
            captionBar.frame = NSRect(x: 0, y: b.height - 24, width: b.width, height: 24)
            let capH = caption.intrinsicContentSize.height
            caption.frame = NSRect(x: 8, y: (24 - capH) / 2, width: max(0, captionBar.bounds.width - 16), height: capH)
        }
        if !titleLabel.isHidden {
            let w = max(0, b.width - 20)
            let h = titleLabel.sizeThatFits(NSSize(width: w, height: 800)).height
            titleLabel.frame = NSRect(x: 10, y: b.midY - 8 - h / 2, width: w, height: h)
            let sh = siteLabel.intrinsicContentSize.height
            siteLabel.frame = NSRect(x: 10, y: titleLabel.frame.maxY + 6, width: w, height: sh)
        }
        if !sectionLabel.isHidden {
            let s = sectionLabel.intrinsicContentSize
            let w = min(max(s.width, 0), max(0, b.width - 2))
            sectionLabel.frame = NSRect(x: 2, y: b.height - 6 - s.height, width: w, height: s.height)
        }
    }

    private func restyle() {
        if !isSection { view.layer?.backgroundColor = NSColor.ink(.surface).cgColor }
        applySelection()
    }

    override var isSelected: Bool { didSet { applySelection() } }

    private func applySelection() {
        view.layer?.borderWidth = isSelected && !isSection ? 2 : 0
        view.layer?.borderColor = NSColor.ink(.text).cgColor
    }

    /// A section divider: just the cluster's title and how many items it holds.
    /// The section title becomes an editable field; `commit` gets the new name.
    func beginRenamingSection(text: String, commit: @escaping (String) -> Void) {
        guard isSection else { return }
        view.layoutSubtreeIfNeeded()
        let field = InlineTitleField(text: text, font: .grailsDisplay(26))
        sectionLabel.isHidden = true
        field.onFinish = { [weak self] new in
            self?.sectionLabel.isHidden = false
            self?.view.window?.makeFirstResponder(self?.view.superview)
            if let new, new.trimmingCharacters(in: .whitespaces) != text { commit(new) }
        }
        let r = sectionLabel.frame
        field.begin(in: view, frame: NSRect(x: 0, y: max(r.minY - 3, 0), width: min(view.bounds.width, 520), height: 34))
    }

    func configureSection(_ s: ItemSummary) {
        op?.cancel()
        HoverVideo.shared.release(host: view)
        source = nil
        itemID = nil
        isSection = true
        view.layer?.contents = nil
        view.layer?.backgroundColor = NSColor.clear.cgColor
        view.layer?.borderWidth = 0
        for v in [placeholder, heart, captionBar, titleLabel, siteLabel, badge, cloud, avatar] as [NSView] { v.isHidden = true }
        let untitled = s.name.isEmpty
        let text = NSMutableAttributedString(string: untitled ? "Untitled" : s.name, attributes: [
            .font: NSFont.grailsDisplay(26),
            .foregroundColor: NSColor.ink(untitled ? .secondary : .text),
        ])
        text.append(NSAttributedString(string: "   \(s.bytes ?? 0)", attributes: [
            .font: NSFont.grailsBody(16), .foregroundColor: NSColor.ink(.secondary),
        ]))
        sectionLabel.attributedStringValue = text
        sectionLabel.isHidden = false
        (view as? TileView)?.axLabel = "Cluster: \(untitled ? "Untitled" : s.name)"
        view.needsLayout = true
    }

    func configure(_ s: ItemSummary, loader: ThumbnailLoader, layout: LibraryLayout, original: URL?, cornerRadius: CGFloat, gravity: CALayerContentsGravity, scale: CGFloat, cloudOnly: Bool = false, showAddedBy: Bool = false) {
        op?.cancel()
        // the hover player belongs to the item, not the cell: a cell given another item lets it go
        if itemID != s.id { HoverVideo.shared.release(host: view) }
        itemID = s.id
        isSection = false
        sectionLabel.isHidden = true
        view.layer?.backgroundColor = NSColor.ink(.surface).cgColor
        cloud.isHidden = !cloudOnly
        avatar.isHidden = !showAddedBy || s.addedBy.isEmpty
        if showAddedBy {
            avatar.stringValue = AppModel.initials(s.addedBy)
            let hue = CGFloat(abs(s.addedBy.hashValue % 360)) / 360
            avatar.layer?.backgroundColor = NSColor(hue: hue, saturation: 0.55, brightness: 0.62, alpha: 0.95).cgColor
            avatar.toolTip = s.addedBy
        }
        heart.isHidden = !s.liked
        view.layer?.cornerRadius = cornerRadius
        let isLink = s.kind == .link
        let mode = s.linkDisplay ?? "title"
        let showsPicture = !isLink || mode != "title"
        view.layer?.contentsGravity = isLink ? .resizeAspectFill : gravity
        captionBar.isHidden = !(isLink && showsPicture)
        caption.stringValue = isLink ? s.name : ""
        titleLabel.isHidden = !(isLink && !showsPicture)
        siteLabel.isHidden = titleLabel.isHidden
        if isLink && !showsPicture { titleLabel.stringValue = s.name; siteLabel.stringValue = s.site ?? "" }
        if s.kind == .video, let d = s.durationSec, d > 0 {
            badge.isHidden = false
            badge.show(String(format: "%d:%02d", Int(d) / 60, Int(d) % 60), play: true, color: .onImageScrim)
        } else {
            badge.isHidden = s.badge == nil
            if let b = s.badge { badge.show(b.capitalized, play: false, color: NSColor(red: 0.64, green: 0.33, blue: 1.0, alpha: 0.95)) }
        }
        let pixels = max(view.bounds.width, view.bounds.height) * scale
        placeholder.image = NSImage(systemSymbolName: Self.symbol(for: s.kind), accessibilityDescription: nil)
        (view as? TileView)?.axLabel = s.name
        guard showsPicture else {
            view.layer?.contents = nil
            placeholder.isHidden = true
            applySelection()
            view.needsLayout = true
            return
        }
        let variant = isLink ? mode : ""
        let pictureURL = isLink && mode == "snapshot" ? layout.snapshotURL(s.id) : layout.thumbURL(s.id)
        if let hit = loader.cached(id: s.id, pixels: pixels, variant: variant) {
            show(hit)
        } else {
            view.layer?.contents = nil
            placeholder.isHidden = isLink
        }
        let id = s.id
        source = (id, pictureURL, isLink ? nil : original, variant)
        op = loader.load(id: id, thumb: pictureURL, original: isLink ? nil : original, pixels: pixels, variant: variant) { [weak self] image in
            guard let self, self.itemID == id, let image else { return }
            self.show(image)
        }
        applySelection()
        view.needsLayout = true
    }

    /// After the tile changed size: fetch a sharper picture and swap it in, leaving the current one up until it arrives.
    func refreshResolution(loader: ThumbnailLoader, scale: CGFloat) {
        guard let src = source, itemID == src.id, !isSection else { return }
        let pixels = max(view.bounds.width, view.bounds.height) * scale
        op?.cancel()
        let id = src.id
        op = loader.load(id: id, thumb: src.thumb, original: src.original, pixels: pixels, variant: src.variant) { [weak self] image in
            guard let self, self.itemID == id, let image else { return }
            self.show(image)
        }
    }

    private func show(_ image: CGImage) {
        view.layer?.contents = image
        placeholder.isHidden = true
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        HoverVideo.shared.release(host: view)
        op?.cancel()
        op = nil
        source = nil
        itemID = nil
        view.alphaValue = 1
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        view.layer?.removeAnimation(forKey: "land")
        view.layer?.opacity = 1
        CATransaction.commit()
        view.layer?.contents = nil
        cloud.isHidden = true
        avatar.isHidden = true
        captionBar.isHidden = true
        titleLabel.isHidden = true
        siteLabel.isHidden = true
        badge.isHidden = true
        sectionLabel.isHidden = true
        placeholder.isHidden = false
        isSection = false
        view.layer?.backgroundColor = NSColor.ink(.surface).cgColor
    }

    static func symbol(for kind: ItemKind) -> String {
        switch kind {
        case .video: "film"
        case .pdf: "doc.richtext"
        case .link: "link"
        case .svg, .vector: "scribble.variable"
        case .lottie: "sparkles"
        case .color: "paintpalette"
        default: "photo"
        }
    }
}
