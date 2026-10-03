import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
@testable import StashKit

enum TestSupport {
    static func tempDir(_ label: String = "stash") -> URL {
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
        let root = tempDir().appendingPathComponent("Test.stash")
        let store = try LibraryStore.create(at: root, name: "Test", index: try LibraryIndex(path: nil), userHandle: handle)
        return (store, root)
    }
}
