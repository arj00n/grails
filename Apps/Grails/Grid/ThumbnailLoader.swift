import AppKit
import ImageIO

/// Decodes thumbnails off the main thread and caches them by (item, pixel bucket).
/// Small tiles use the shared 512 px `thumb.jpg`; tiles larger than that decode from the original.
final class ThumbnailLoader: @unchecked Sendable {
    static let shared = ThumbnailLoader()

    private let cache = NSCache<NSString, CGImage>()
    private let gate = NSLock()
    /// One decode per picture. A cell that asks while that decode is running joins it instead of starting another.
    private var flights: [String: Flight] = [:]
    private let queue: OperationQueue = {
        let q = OperationQueue()
        q.name = "grails.thumbnails"
        q.maxConcurrentOperationCount = 8
        q.qualityOfService = .userInitiated
        return q
    }()

    init() { cache.totalCostLimit = 300 * 1024 * 1024 }

    static func bucket(forPixels px: CGFloat) -> Int {
        for b in [128, 256, 512, 1024, 2048] where px <= CGFloat(b) { return b }
        return 4096
    }

    private func key(_ id: String, _ bucket: Int, _ variant: String = "") -> NSString { "\(id)\(variant)@\(bucket)" as NSString }

    /// `variant` separates different pictures for one item (a link's snapshot vs its preview image).
    func cached(id: String, pixels: CGFloat, variant: String = "") -> CGImage? {
        let b = Self.bucket(forPixels: pixels)
        if let hit = cache.object(forKey: key(id, b, variant)) { return hit }
        // A larger decode already in cache is fine to show while a sharper/smaller one is wanted.
        for larger in [256, 512, 1024, 2048, 4096] where larger > b {
            if let hit = cache.object(forKey: key(id, larger, variant)) { return hit }
        }
        return nil
    }

    /// Calls `completion` on the main thread. Cancel the returned operation when the cell is reused.
    /// That cancels only this caller: a decode someone else is waiting on keeps going.
    @discardableResult
    func load(id: String, thumb: URL, original: URL?, pixels: CGFloat, variant: String = "", priority: Operation.QueuePriority = .normal, completion: @escaping @Sendable (CGImage?) -> Void) -> Operation {
        let b = Self.bucket(forPixels: pixels)
        let flightKey = "\(id)\(variant)@\(b)"
        let token = BlockOperation()
        gate.lock()
        if let flight = flights[flightKey] {
            flight.waiters.append((token, completion))
            if priority.rawValue > flight.op.queuePriority.rawValue { flight.op.queuePriority = priority }
            gate.unlock()
            return token
        }
        let op = BlockOperation()
        let flight = Flight(op: op)
        flight.waiters.append((token, completion))
        flights[flightKey] = flight
        gate.unlock()
        op.queuePriority = priority
        op.addExecutionBlock { [weak self] in
            guard let self else { return }
            self.gate.lock()
            let live = flight.waiters.contains { !$0.token.isCancelled }
            if !live { self.flights[flightKey] = nil }
            self.gate.unlock()
            guard live else { return }
            let cacheKey = flightKey as NSString
            var image = self.cache.object(forKey: cacheKey)
            if image == nil {
                if b > 512, let original { image = Self.decode(original, maxPixel: b) }
                if image == nil { image = Self.decode(thumb, maxPixel: min(b, 512)) }
                if let image { self.cache.setObject(image, forKey: cacheKey, cost: image.width * image.height * 4) }
            }
            self.gate.lock()
            let waiters = flight.waiters
            self.flights[flightKey] = nil
            self.gate.unlock()
            DispatchQueue.main.async {
                for waiter in waiters where !waiter.token.isCancelled { waiter.completion(image) }
            }
        }
        queue.addOperation(op)
        return token
    }

    func prefetch(id: String, thumb: URL, pixels: CGFloat, variant: String = "", priority: Operation.QueuePriority = .low) {
        guard cached(id: id, pixels: pixels, variant: variant) == nil else { return }
        load(id: id, thumb: thumb, original: nil, pixels: min(pixels, 512), variant: variant, priority: priority) { _ in }
    }

    func clear() { cache.removeAllObjects() }

    private final class Flight: @unchecked Sendable {
        let op: BlockOperation
        var waiters: [(token: Operation, completion: @Sendable (CGImage?) -> Void)] = []
        init(op: BlockOperation) { self.op = op }
    }

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
