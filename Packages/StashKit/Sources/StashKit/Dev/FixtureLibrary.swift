import CoreGraphics
import Foundation

/// Generates large synthetic libraries (valid on-disk format, tiny solid-colour thumbnails) for performance tests.
public enum FixtureLibrary {
    struct SplitMix64: RandomNumberGenerator {
        var state: UInt64
        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
    }

    static let words = [
        "biryani", "packaging", "warm", "night", "top-down", "brass", "neon", "minimal", "typography", "poster",
        "hero", "banner", "food", "street", "spice", "chai", "dessert", "logo", "motion", "lottie", "icon",
        "gradient", "flat", "3d", "grain", "retro", "modern", "app", "ui", "campaign", "festival", "diwali",
        "sunset", "interior", "bar", "cafe", "menu", "label", "box", "bag", "sticker", "illustration",
    ]
    static let palette = ["#C8742F", "#2F7DC8", "#3AAA5C", "#D94F70", "#F2C94C", "#6B4FD9", "#1E1E1E", "#F5F0E6"]

    public static func tinyJPEG(red: Double, green: Double, blue: Double) -> Data {
        let ctx = CGContext(
            data: nil, width: 64, height: 64, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        )!
        ctx.setFillColor(CGColor(red: red, green: green, blue: blue, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: 64, height: 64))
        return Thumbnailer.encodeJPEG(ctx.makeImage()!)!
    }

    /// Creates `count` items under a new library at `root`. Deterministic for a given `seed`.
    @discardableResult
    public static func generate(at root: URL, count: Int, seed: UInt64 = 42) throws -> LibraryLayout {
        var rng = SplitMix64(state: seed)
        let layout = LibraryLayout(root: root)
        let fm = FileManager.default
        for dir in [layout.itemsDir, layout.collectionsDir, layout.canvasDir, layout.smartDir] {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        try AtomicFile.writeJSON(LibraryManifest(name: "Fixture \(count)"), to: layout.manifestURL)

        var collectionIds: [String] = []
        var order: String?
        for i in 0..<20 {
            order = FractionalIndex.after(order)
            let c = StashCollection(name: "Collection \(i + 1)", order: order!, updatedBy: "fixture")
            try AtomicFile.writeJSON(c, to: layout.collectionURL(c.id))
            collectionIds.append(c.id)
        }

        var thumbs: [Data] = []
        for i in 0..<8 {
            let r: Double = Double((i * 37) % 255) / 255.0
            let g: Double = Double((i * 91) % 255) / 255.0
            let b: Double = Double((i * 53) % 255) / 255.0
            thumbs.append(tinyJPEG(red: r, green: g, blue: b))
        }
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        for n in 0..<count {
            let tagCount = Int.random(in: 1...4, using: &rng)
            let tags = Array(Set((0..<tagCount).map { _ in words.randomElement(using: &rng)! }))
            var collections: [String: String] = [:]
            for _ in 0..<Int.random(in: 0...2, using: &rng) {
                collections[collectionIds.randomElement(using: &rng)!] = FractionalIndex.after(String(n))
            }
            let when = start.addingTimeInterval(Double(n) * 60)
            let id = ULID(date: when).string
            let pal = (0..<3).map { _ in PaletteColor(hex: palette.randomElement(using: &rng)!, weight: Double.random(in: 0.1...0.6, using: &rng)) }
            let item = Item(
                id: id, kind: .image, file: "original.jpg",
                name: "Item \(String(format: "%05d", n)) \(tags.first ?? "")", ext: "jpg", bytes: 1500,
                width: 64, height: 64, sha256: "fixture\(n)", source: ItemSource(site: "example.com"), tags: tags,
                collections: collections, liked: Int.random(in: 0..<10, using: &rng) == 0, palette: pal,
                addedAt: Date(timeIntervalSince1970: (when.timeIntervalSince1970 * 1000).rounded() / 1000), addedBy: "fixture"
            )
            let dir = layout.itemDir(id)
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            try thumbs[n % thumbs.count].write(to: layout.thumbURL(id))
            try AtomicFile.writeJSON(item, to: layout.itemJSON(id))
        }
        return layout
    }
}
