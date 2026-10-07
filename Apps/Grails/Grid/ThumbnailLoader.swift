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
    /// Item ids the grid still wants decoded: the viewport plus about one row. Nil when nothing is virtualizing
    /// (the canvas, onboarding), so those callers keep the old "cache whatever was asked for" behaviour.
    private var resident: Set<String>?
    /// Cache keys by item, so a tile that has left the window can be dropped without enumerating `NSCache`.
    private var keysByID: [String: Set<NSString>] = [:]
    /// Prefetch waiters the grid can cancel when a tile scrolls out of the window.
    private var prefetches: [String: Operation] = [:]
    /// Ids with a prefetch already queued, so a scroll tick doesn't start the same decode again.
    private var prefetching: Set<String> = []
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
        let flight = Flight(op: op, itemID: id)
        flight.waiters.append((token, completion))
        flights[flightKey] = flight
        gate.unlock()
        op.queuePriority = priority
        op.addExecutionBlock { [weak self] in
            guard let self else { return }
            self.gate.lock()
            let live = flight.waiters.contains { !$0.token.isCancelled }
            let pinned = self.resident?.contains(id) == true
            if !live, !pinned, self.flights[flightKey] === flight as Flight? { self.flights[flightKey] = nil }
            self.gate.unlock()
            // A cell that scrolled away cancels its waiter. Keep decoding only when the tile is still in the
            // window (pinned) or someone is still waiting. Outside the grid, `resident` is nil and this matches
            // the old rule: no live waiter, no decode.
            guard live || pinned else { return }
            let cacheKey = flightKey as NSString
            var image = self.cache.object(forKey: cacheKey)
            if image == nil {
                if b > 512, let original { image = Self.decode(original, maxPixel: b) }
                if image == nil { image = Self.decode(thumb, maxPixel: min(b, 512)) }
            }
            self.gate.lock()
            let waiters = flight.waiters
            let liveNow = waiters.contains { !$0.token.isCancelled }
            let pinnedNow = self.resident?.contains(id) == true
            let virtualizing = self.resident != nil
            if self.flights[flightKey] === flight as Flight? { self.flights[flightKey] = nil }
            let keep = image != nil && (virtualizing ? (liveNow || pinnedNow) : true)
            if keep, let image {
                self.keysByID[id, default: []].insert(cacheKey)
                self.cache.setObject(image, forKey: cacheKey, cost: image.width * image.height * 4)
            }
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
        gate.lock()
        if prefetching.contains(id) { gate.unlock(); return }
        if let resident, !resident.contains(id) { gate.unlock(); return }
        prefetching.insert(id)
        gate.unlock()
        let token = load(id: id, thumb: thumb, original: nil, pixels: min(pixels, 512), variant: variant, priority: priority) { [weak self] _ in
            guard let self else { return }
            self.gate.lock()
            self.prefetching.remove(id)
            self.gate.unlock()
        }
        gate.lock()
        if let resident, !resident.contains(id) {
            prefetching.remove(id)
            gate.unlock()
            token.cancel()
            return
        }
        prefetches[id] = token
        gate.unlock()
    }

    /// The grid's keep-set: tiles in the viewport plus about one row. Anything the grid had loaded that is no longer
    /// in `ids` is dropped. Passing nil stops virtualizing and leaves the cache alone (canvas / onboarding).
    func setResident(_ ids: Set<String>?) {
        gate.lock()
        let old = resident
        resident = ids
        var tokens: [Operation] = []
        var keys: [NSString] = []
        if let ids {
            let stalePrefetch = prefetches.keys.filter { !ids.contains($0) }
            for id in stalePrefetch {
                if let token = prefetches.removeValue(forKey: id) { tokens.append(token) }
                prefetching.remove(id)
                if let ks = keysByID.removeValue(forKey: id) { keys.append(contentsOf: ks) }
            }
            if let old {
                for id in old.subtracting(ids) {
                    if let ks = keysByID.removeValue(forKey: id) { keys.append(contentsOf: ks) }
                }
            }
        }
        gate.unlock()
        for token in tokens { token.cancel() }
        for key in keys { cache.removeObject(forKey: key) }
    }

    /// Cancels grid prefetches for items that have left the window. No-op until a resident set exists, so an early
    /// collection-view cancel can't throw away the first row already decoding.
    func cancelPrefetches(_ ids: Set<String>) {
        guard !ids.isEmpty else { return }
        gate.lock()
        guard let resident else { gate.unlock(); return }
        var tokens: [Operation] = []
        var keys: [NSString] = []
        for id in ids where !resident.contains(id) {
            if let token = prefetches.removeValue(forKey: id) { tokens.append(token) }
            prefetching.remove(id)
            if let ks = keysByID.removeValue(forKey: id) { keys.append(contentsOf: ks) }
        }
        gate.unlock()
        for token in tokens { token.cancel() }
        for key in keys { cache.removeObject(forKey: key) }
    }

    func clear() {
        cache.removeAllObjects()
        gate.lock()
        let tokens = Array(prefetches.values)
        prefetches.removeAll()
        prefetching.removeAll()
        keysByID.removeAll()
        resident = nil
        gate.unlock()
        for token in tokens { token.cancel() }
    }

    private final class Flight: @unchecked Sendable {
        let op: BlockOperation
        let itemID: String
        var waiters: [(token: Operation, completion: @Sendable (CGImage?) -> Void)] = []
        init(op: BlockOperation, itemID: String) {
            self.op = op
            self.itemID = itemID
        }
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
