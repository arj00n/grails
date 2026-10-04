import AppKit
import StashKit

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

final class TileView: NSView {
    /// What VoiceOver reads (and UI tests find): the item's name.
    var axLabel: String?
    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityLabel() -> String? { axLabel }
    override func accessibilityRole() -> NSAccessibility.Role? { .image }
    override var wantsUpdateLayer: Bool { true }
    override var isFlipped: Bool { true }
    override func updateLayer() {}

    /// A right-click lands on the tile first; let the grid build the context menu.
    override func menu(for event: NSEvent) -> NSMenu? {
        var v: NSView? = superview
        while let view = v {
            if let grid = view as? StashCollectionView { return grid.menu(for: event) }
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
    private let badge = PassthroughLabel.make()
    private let cloud = NSImageView()
    private let avatar = PassthroughLabel.make()
    private let sectionLabel = PassthroughLabel.make()
    private var isSection = false

    override func loadView() {
        let v = TileView()
        v.wantsLayer = true
        v.layer?.masksToBounds = true
        v.layer?.backgroundColor = NSColor.quaternaryLabelColor.cgColor
        v.layer?.contentsGravity = .resizeAspect
        v.layer?.magnificationFilter = .trilinear
        v.layer?.minificationFilter = .trilinear
        placeholder.imageScaling = .scaleProportionallyDown
        placeholder.contentTintColor = .tertiaryLabelColor
        placeholder.translatesAutoresizingMaskIntoConstraints = false
        v.addSubview(placeholder)
        NSLayoutConstraint.activate([
            placeholder.centerXAnchor.constraint(equalTo: v.centerXAnchor),
            placeholder.centerYAnchor.constraint(equalTo: v.centerYAnchor),
            placeholder.widthAnchor.constraint(equalToConstant: 28),
            placeholder.heightAnchor.constraint(equalToConstant: 28),
        ])
        heart.image = NSImage(systemSymbolName: "heart.fill", accessibilityDescription: "Liked")
        heart.contentTintColor = .systemPink
        heart.shadow = {
            let sh = NSShadow(); sh.shadowColor = NSColor.black.withAlphaComponent(0.55); sh.shadowBlurRadius = 3; sh.shadowOffset = .zero
            return sh
        }()
        heart.translatesAutoresizingMaskIntoConstraints = false
        heart.isHidden = true
        v.addSubview(heart)
        NSLayoutConstraint.activate([
            heart.topAnchor.constraint(equalTo: v.topAnchor, constant: 8),
            heart.trailingAnchor.constraint(equalTo: v.trailingAnchor, constant: -8),
            heart.widthAnchor.constraint(equalToConstant: 16),
            heart.heightAnchor.constraint(equalToConstant: 16),
        ])
        // Link cards: caption over the picture, or a big title when there's no picture
        captionBar.wantsLayer = true
        captionBar.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.58).cgColor
        captionBar.translatesAutoresizingMaskIntoConstraints = false
        captionBar.isHidden = true
        caption.font = .systemFont(ofSize: 11, weight: .medium)
        caption.textColor = .white
        caption.lineBreakMode = .byTruncatingTail
        caption.translatesAutoresizingMaskIntoConstraints = false
        captionBar.addSubview(caption)
        v.addSubview(captionBar)
        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        titleLabel.textColor = .labelColor
        titleLabel.alignment = .center
        titleLabel.maximumNumberOfLines = 4
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.isHidden = true
        siteLabel.font = .systemFont(ofSize: 10)
        siteLabel.textColor = .secondaryLabelColor
        siteLabel.alignment = .center
        siteLabel.translatesAutoresizingMaskIntoConstraints = false
        siteLabel.isHidden = true
        v.addSubview(titleLabel)
        v.addSubview(siteLabel)
        badge.font = .systemFont(ofSize: 9, weight: .bold)
        badge.textColor = .white
        badge.wantsLayer = true
        badge.layer?.backgroundColor = NSColor(red: 0.64, green: 0.33, blue: 1.0, alpha: 0.95).cgColor
        badge.layer?.cornerRadius = 4
        badge.translatesAutoresizingMaskIntoConstraints = false
        badge.isHidden = true
        v.addSubview(badge)
        sectionLabel.font = .systemFont(ofSize: 24, weight: .semibold)
        sectionLabel.textColor = NSColor.white.withAlphaComponent(0.92)
        sectionLabel.lineBreakMode = .byTruncatingTail
        sectionLabel.translatesAutoresizingMaskIntoConstraints = false
        sectionLabel.isHidden = true
        v.addSubview(sectionLabel)
        NSLayoutConstraint.activate([
            sectionLabel.leadingAnchor.constraint(equalTo: v.leadingAnchor, constant: 2),
            sectionLabel.trailingAnchor.constraint(lessThanOrEqualTo: v.trailingAnchor),
            sectionLabel.bottomAnchor.constraint(equalTo: v.bottomAnchor, constant: -6),
        ])
        NSLayoutConstraint.activate([
            captionBar.leadingAnchor.constraint(equalTo: v.leadingAnchor),
            captionBar.trailingAnchor.constraint(equalTo: v.trailingAnchor),
            captionBar.bottomAnchor.constraint(equalTo: v.bottomAnchor),
            captionBar.heightAnchor.constraint(equalToConstant: 24),
            caption.leadingAnchor.constraint(equalTo: captionBar.leadingAnchor, constant: 8),
            caption.trailingAnchor.constraint(equalTo: captionBar.trailingAnchor, constant: -8),
            caption.centerYAnchor.constraint(equalTo: captionBar.centerYAnchor),
            titleLabel.leadingAnchor.constraint(equalTo: v.leadingAnchor, constant: 10),
            titleLabel.trailingAnchor.constraint(equalTo: v.trailingAnchor, constant: -10),
            titleLabel.centerYAnchor.constraint(equalTo: v.centerYAnchor, constant: -8),
            siteLabel.leadingAnchor.constraint(equalTo: v.leadingAnchor, constant: 10),
            siteLabel.trailingAnchor.constraint(equalTo: v.trailingAnchor, constant: -10),
            siteLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 6),
            badge.leadingAnchor.constraint(equalTo: v.leadingAnchor, constant: 8),
            badge.topAnchor.constraint(equalTo: v.topAnchor, constant: 8),
        ])
        cloud.image = NSImage(systemSymbolName: "icloud.and.arrow.down", accessibilityDescription: "Not downloaded yet")
        cloud.contentTintColor = .white
        cloud.shadow = heart.shadow
        cloud.translatesAutoresizingMaskIntoConstraints = false
        cloud.isHidden = true
        v.addSubview(cloud)
        avatar.font = .systemFont(ofSize: 9, weight: .bold)
        avatar.textColor = .white
        avatar.alignment = .center
        avatar.wantsLayer = true
        avatar.layer?.cornerRadius = 9
        avatar.translatesAutoresizingMaskIntoConstraints = false
        avatar.isHidden = true
        v.addSubview(avatar)
        NSLayoutConstraint.activate([
            cloud.trailingAnchor.constraint(equalTo: v.trailingAnchor, constant: -8),
            cloud.bottomAnchor.constraint(equalTo: v.bottomAnchor, constant: -8),
            cloud.widthAnchor.constraint(equalToConstant: 16),
            cloud.heightAnchor.constraint(equalToConstant: 16),
            avatar.leadingAnchor.constraint(equalTo: v.leadingAnchor, constant: 8),
            avatar.bottomAnchor.constraint(equalTo: v.bottomAnchor, constant: -8),
            avatar.widthAnchor.constraint(equalToConstant: 20),
            avatar.heightAnchor.constraint(equalToConstant: 18),
        ])
        view = v
    }

    override var isSelected: Bool { didSet { applySelection() } }

    private func applySelection() {
        view.layer?.borderWidth = isSelected && !isSection ? 2.5 : 0
        view.layer?.borderColor = NSColor.white.withAlphaComponent(0.92).cgColor
    }

    /// A section divider: just the cluster's title and how many items it holds.
    /// The section title becomes an editable field; `commit` gets the new name.
    func beginRenamingSection(text: String, commit: @escaping (String) -> Void) {
        guard isSection else { return }
        view.layoutSubtreeIfNeeded()
        let field = InlineTitleField(text: text, font: .systemFont(ofSize: 24, weight: .semibold))
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
        source = nil
        itemID = nil
        isSection = true
        view.layer?.contents = nil
        view.layer?.backgroundColor = NSColor.clear.cgColor
        view.layer?.borderWidth = 0
        for v in [placeholder, heart, captionBar, titleLabel, siteLabel, badge, cloud, avatar] as [NSView] { v.isHidden = true }
        let untitled = s.name.isEmpty
        let text = NSMutableAttributedString(string: untitled ? "Untitled" : s.name, attributes: [
            .font: NSFont.systemFont(ofSize: 24, weight: .semibold),
            .foregroundColor: NSColor.white.withAlphaComponent(untitled ? 0.30 : 0.92),
        ])
        text.append(NSAttributedString(string: "   \(s.bytes ?? 0)", attributes: [
            .font: NSFont.systemFont(ofSize: 16, weight: .regular), .foregroundColor: NSColor.white.withAlphaComponent(0.38),
        ]))
        sectionLabel.attributedStringValue = text
        sectionLabel.isHidden = false
        (view as? TileView)?.axLabel = "Cluster: \(untitled ? "Untitled" : s.name)"
    }

    func configure(_ s: ItemSummary, loader: ThumbnailLoader, layout: LibraryLayout, original: URL?, cornerRadius: CGFloat, gravity: CALayerContentsGravity, scale: CGFloat, cloudOnly: Bool = false, showAddedBy: Bool = false) {
        op?.cancel()
        itemID = s.id
        isSection = false
        sectionLabel.isHidden = true
        view.layer?.backgroundColor = NSColor.quaternaryLabelColor.cgColor
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
            badge.stringValue = String(format: " ▶ %d:%02d ", Int(d) / 60, Int(d) % 60)
            badge.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.55).cgColor
        } else {
            badge.isHidden = s.badge == nil
            badge.layer?.backgroundColor = NSColor(red: 0.64, green: 0.33, blue: 1.0, alpha: 0.95).cgColor
            if let b = s.badge { badge.stringValue = " \(b.capitalized) " }
        }
        let pixels = max(view.bounds.width, view.bounds.height) * scale
        placeholder.image = NSImage(systemSymbolName: Self.symbol(for: s.kind), accessibilityDescription: nil)
        (view as? TileView)?.axLabel = s.name
        guard showsPicture else {
            view.layer?.contents = nil
            placeholder.isHidden = true
            applySelection()
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
        op?.cancel()
        op = nil
        source = nil
        itemID = nil
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
        view.layer?.backgroundColor = NSColor.quaternaryLabelColor.cgColor
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
