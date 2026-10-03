import AppKit
import ImageIO

/// Decodes thumbnails off the main thread and caches them by (item, pixel bucket).
/// Small tiles use the shared 512 px `thumb.jpg`; tiles larger than that decode from the original.
final class ThumbnailLoader: @unchecked Sendable {
    static let shared = ThumbnailLoader()

    private let cache = NSCache<NSString, CGImage>()
    private let queue: OperationQueue = {
        let q = OperationQueue()
        q.name = "stash.thumbnails"
        q.maxConcurrentOperationCount = 4
        q.qualityOfService = .userInitiated
        return q
    }()

    init() { cache.totalCostLimit = 300 * 1024 * 1024 }

    static func bucket(forPixels px: CGFloat) -> Int {
        for b in [128, 256, 512, 1024, 2048] where px <= CGFloat(b) { return b }
        return 4096
    }

    private func key(_ id: String, _ bucket: Int) -> NSString { "\(id)@\(bucket)" as NSString }

    func cached(id: String, pixels: CGFloat) -> CGImage? {
        let b = Self.bucket(forPixels: pixels)
        if let hit = cache.object(forKey: key(id, b)) { return hit }
        // A larger decode already in cache is fine to show while a sharper/smaller one is wanted.
        for larger in [256, 512, 1024, 2048, 4096] where larger > b {
            if let hit = cache.object(forKey: key(id, larger)) { return hit }
        }
        return nil
    }

    /// Calls `completion` on the main thread. Cancel the returned operation when the cell is reused.
    @discardableResult
    func load(id: String, thumb: URL, original: URL?, pixels: CGFloat, completion: @escaping @Sendable (CGImage?) -> Void) -> Operation {
        let b = Self.bucket(forPixels: pixels)
        let k = key(id, b)
        let op = BlockOperation()
        op.addExecutionBlock { [weak op, weak self] in
            guard let self, let op, !op.isCancelled else { return }
            var image = self.cache.object(forKey: k)
            if image == nil {
                if b > 512, let original { image = Self.decode(original, maxPixel: b) }
                if image == nil { image = Self.decode(thumb, maxPixel: min(b, 512)) }
                if let image { self.cache.setObject(image, forKey: k, cost: image.width * image.height * 4) }
            }
            guard !op.isCancelled else { return }
            DispatchQueue.main.async { completion(image) }
        }
        queue.addOperation(op)
        return op
    }

    func prefetch(id: String, thumb: URL, pixels: CGFloat) {
        guard cached(id: id, pixels: pixels) == nil else { return }
        load(id: id, thumb: thumb, original: nil, pixels: min(pixels, 512)) { _ in }.queuePriority = .low
    }

    func clear() { cache.removeAllObjects() }

    static func decode(_ url: URL, maxPixel: Int) -> CGImage? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        return CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary)
    }
}
