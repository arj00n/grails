import AppKit
import StashKit

final class TileView: NSView {
    override var wantsUpdateLayer: Bool { true }
    override var isFlipped: Bool { true }
    override func updateLayer() {}
}

final class ThumbCell: NSCollectionViewItem {
    static let identifier = NSUserInterfaceItemIdentifier("ThumbCell")
    private var op: Operation?
    private(set) var itemID: String?
    private let placeholder = NSImageView()
    private let heart = NSImageView()

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
        view = v
    }

    override var isSelected: Bool { didSet { applySelection() } }

    private func applySelection() {
        view.layer?.borderWidth = isSelected ? 3 : 0
        view.layer?.borderColor = NSColor.controlAccentColor.cgColor
    }

    func configure(_ s: ItemSummary, loader: ThumbnailLoader, layout: LibraryLayout, original: URL?, cornerRadius: CGFloat, gravity: CALayerContentsGravity, scale: CGFloat) {
        op?.cancel()
        itemID = s.id
        heart.isHidden = !s.liked
        view.layer?.cornerRadius = cornerRadius
        view.layer?.contentsGravity = gravity
        let pixels = max(view.bounds.width, view.bounds.height) * scale
        placeholder.image = NSImage(systemSymbolName: Self.symbol(for: s.kind), accessibilityDescription: nil)
        view.setAccessibilityLabel(s.name)
        view.setAccessibilityRole(.image)
        if let hit = loader.cached(id: s.id, pixels: pixels) {
            show(hit)
        } else {
            view.layer?.contents = nil
            placeholder.isHidden = false
        }
        let id = s.id
        op = loader.load(id: id, thumb: layout.thumbURL(id), original: original, pixels: pixels) { [weak self] image in
            guard let self, self.itemID == id, let image else { return }
            self.show(image)
        }
        applySelection()
    }

    private func show(_ image: CGImage) {
        view.layer?.contents = image
        placeholder.isHidden = true
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        op?.cancel()
        op = nil
        itemID = nil
        view.layer?.contents = nil
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
