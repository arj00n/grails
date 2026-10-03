import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

public struct ImageInfo: Sendable, Hashable {
    public var width: Int
    public var height: Int
}

public enum Thumbnailer {
    public static let maxPixel = 512

    /// Pixel size as displayed (EXIF orientation applied).
    public static func imageInfo(at url: URL) -> ImageInfo? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
              let w = props[kCGImagePropertyPixelWidth] as? Int,
              let h = props[kCGImagePropertyPixelHeight] as? Int else { return nil }
        let orientation = props[kCGImagePropertyOrientation] as? Int ?? 1
        return orientation >= 5 ? ImageInfo(width: h, height: w) : ImageInfo(width: w, height: h)
    }

    /// JPEG thumbnail (long edge `maxPixel`). Transparent images are flattened onto white.
    public static func jpegThumbnail(for url: URL, maxPixel: Int = Thumbnailer.maxPixel, quality: Double = 0.8) -> Data? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { return nil }
        return encodeJPEG(flattened(cg), quality: quality)
    }

    static func flattened(_ image: CGImage) -> CGImage {
        switch image.alphaInfo {
        case .none, .noneSkipFirst, .noneSkipLast: return image
        default: break
        }
        guard let ctx = CGContext(
            data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else { return image }
        let rect = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(rect)
        ctx.draw(image, in: rect)
        return ctx.makeImage() ?? image
    }

    public static func encodeJPEG(_ image: CGImage, quality: Double = 0.8) -> Data? {
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        return CGImageDestinationFinalize(dest) ? data as Data : nil
    }
}

public enum MediaKind {
    public static func detect(_ url: URL) -> ItemKind {
        let ext = url.pathExtension.lowercased()
        if ext == "gif" { return .gif }
        if ext == "svg" { return .svg }
        if ext == "ai" { return .vector }
        guard let type = UTType(filenameExtension: ext) else { return .file }
        if type.conforms(to: .rawImage) { return .raw }
        if type.conforms(to: .image) { return .image }
        if type.conforms(to: .movie) || type.conforms(to: .video) { return .video }
        if type.conforms(to: .pdf) { return .pdf }
        return .file
    }
}
