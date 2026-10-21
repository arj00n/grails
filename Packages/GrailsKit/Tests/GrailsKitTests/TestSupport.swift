import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
@testable import GrailsKit

enum TestSupport {
    static func tempDir(_ label: String = "grails") -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(label)-\(UUID().uuidString)", isDirectory: true)
        try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Writes a solid-colour PNG (optionally with transparency) and returns its URL.
    static func makePNG(in dir: URL, name: String, width: Int = 300, height: Int = 200, rgb: (Double, Double, Double) = (1, 0, 0), alpha: Double = 1) -> URL {
        let ctx = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        ctx.setFillColor(CGColor(red: rgb.0, green: rgb.1, blue: rgb.2, alpha: alpha))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let url = dir.appendingPathComponent("\(name).png")
        let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
        precondition(CGImageDestinationFinalize(dest))
        return url
    }

    static func newStore(handle: String = "tester") throws -> (LibraryStore, URL) {
        let root = tempDir().appendingPathComponent("Test.grails")
        let store = try LibraryStore.create(at: root, name: "Test", index: try LibraryIndex(path: nil), userHandle: handle)
        return (store, root)
    }

    /// Writes items straight to disk (as another Mac would) and rescans, so tests can use kinds we can't import.
    static func seed(_ store: LibraryStore, _ items: [Item]) async throws {
        for item in items { try AtomicFile.writeJSON(item, to: store.layout.itemJSON(item.id)) }
        try await store.rescan()
    }

    static func item(_ name: String, kind: ItemKind = .image, tags: [String] = [], w: Int = 100, h: Int = 100, bytes: Int64 = 1000,
                     liked: Bool = false, note: String = "", site: String? = nil, palette: [PaletteColor] = [],
                     collections: [String: String] = [:], addedAt: Date = .grailsNow, addedBy: String = "ana") -> Item {
        Item(kind: kind, file: "original.png", name: name, ext: "png", bytes: bytes, width: w, height: h,
             source: site.map { ItemSource(site: $0) }, tags: tags, collections: collections, liked: liked, note: note,
             palette: palette, addedAt: addedAt, addedBy: addedBy)
    }
}
