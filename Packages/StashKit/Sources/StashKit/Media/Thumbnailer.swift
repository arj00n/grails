import CoreGraphics
import AVFoundation
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

    /// Camera, lens and exposure settings from EXIF/TIFF, as a JSON object. nil when the file has none.
    public static func cameraInfo(at url: URL) -> JSONValue? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any] else { return nil }
        let exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any] ?? [:]
        let tiff = props[kCGImagePropertyTIFFDictionary] as? [CFString: Any] ?? [:]
        var out: [String: JSONValue] = [:]
        func str(_ v: Any?) -> JSONValue? { (v as? String).map(JSONValue.string) }
        func num(_ v: Any?) -> JSONValue? { (v as? NSNumber).map { .double($0.doubleValue) } }
        if let v = str(tiff[kCGImagePropertyTIFFMake]) { out["make"] = v }
        if let v = str(tiff[kCGImagePropertyTIFFModel]) { out["model"] = v }
        if let v = str(exif[kCGImagePropertyExifLensModel]) { out["lens"] = v }
        if let v = num(exif[kCGImagePropertyExifFocalLength]) { out["focalLength"] = v }
        if let iso = (exif[kCGImagePropertyExifISOSpeedRatings] as? [NSNumber])?.first { out["iso"] = .int(iso.intValue) }
        if let v = num(exif[kCGImagePropertyExifFNumber]) { out["aperture"] = v }
        if let v = num(exif[kCGImagePropertyExifExposureTime]) { out["shutter"] = v }
        if let v = num(exif[kCGImagePropertyExifExposureBiasValue]) { out["exposureBias"] = v }
        if let v = str(exif[kCGImagePropertyExifDateTimeOriginal]) { out["capturedAt"] = v }
        return out.isEmpty ? nil : .object(out)
    }

    public struct VideoInfo: Sendable { public var width: Int; public var height: Int; public var durationSec: Double; public var poster: Data? }

    /// Size (as displayed), length and a poster frame of a video file. Runs synchronously: call it off the main thread.
    @available(macOS, deprecated: 15.0, message: "synchronous AVFoundation reads are fine here: this runs on a background task")
    public static func videoInfo(at url: URL, maxPixel: Int = Thumbnailer.maxPixel) -> VideoInfo? {
        let asset = AVURLAsset(url: url)
        guard let track = asset.tracks(withMediaType: .video).first else { return nil }
        let size = track.naturalSize.applying(track.preferredTransform)
        let w = Int(abs(size.width).rounded()), h = Int(abs(size.height).rounded())
        guard w > 0, h > 0 else { return nil }
        let seconds = CMTimeGetSeconds(asset.duration)
        let duration = seconds.isFinite ? max(seconds, 0) : 0
        let gen = AVAssetImageGenerator(asset: asset)
        gen.appliesPreferredTrackTransform = true
        gen.maximumSize = CGSize(width: maxPixel, height: maxPixel)
        gen.requestedTimeToleranceBefore = .positiveInfinity
        gen.requestedTimeToleranceAfter = .positiveInfinity
        // a little way in, so the poster isn't the black first frame of a fade-in
        let at = CMTime(seconds: min(max(duration * 0.2, 0), 1.0), preferredTimescale: 600)
        let frame = (try? gen.copyCGImage(at: at, actualTime: nil)) ?? (try? gen.copyCGImage(at: .zero, actualTime: nil))
        return VideoInfo(width: w, height: h, durationSec: duration, poster: frame.flatMap { encodeJPEG(flattened($0)) })
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

    /// JPEG thumbnail from in-memory image bytes (a downloaded preview image, a screenshot).
    public static func jpegThumbnail(forData data: Data, maxPixel: Int = Thumbnailer.maxPixel, quality: Double = 0.8) -> Data? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
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
