import AppKit
import GrailsKit

/// Where to read a picture for the preview: the original when it is on this Mac, always the thumbnail as a floor.
struct PreviewSource {
    var original: URL?
    var thumb: URL
    var thumbMax: Int
}

/// Full-size decodes for the page being looked at and its neighbours, kept apart from the grid's thumbnail cache. At most a handful
/// are held, nearest first; stale decodes are cancelled as the position moves.
@MainActor
final class PreviewImageCache {
    static let shared = PreviewImageCache()

    private struct Entry { var image: CGImage; var pixels: Int }
    private var store: [String: Entry] = [:]
    private var pending: [String: (op: Operation, pixels: Int)] = [:]
    private let queue: OperationQueue = {
        let q = OperationQueue()
        q.maxConcurrentOperationCount = 2
        q.qualityOfService = .userInitiated
        return q
    }()

    func image(_ id: String) -> CGImage? { store[id]?.image }
    func pixels(_ id: String) -> Int { store[id]?.pixels ?? 0 }
    func has(_ id: String, atLeast pixels: Int) -> Bool { (store[id]?.pixels ?? 0) >= pixels }

    /// Decode `id` for about `pixels` on the long edge; `done` runs on the main actor when something sharper than before arrived.
    func ensure(_ id: String, source: PreviewSource, pixels: Int, priority: Operation.QueuePriority, done: @escaping @MainActor (String) -> Void) {
        if has(id, atLeast: pixels) { return }
        if let p = pending[id], p.pixels >= pixels { return }
        pending[id]?.op.cancel()
        let op = BlockOperation()
        op.queuePriority = priority
        op.addExecutionBlock { [weak op] in
            guard let op, !op.isCancelled else { return }
            var image: CGImage?
            var got = 0
            if let original = source.original, let hi = ThumbnailLoader.decode(original, maxPixel: pixels) { image = hi; got = pixels }
            else if let t = ThumbnailLoader.decode(source.thumb, maxPixel: source.thumbMax) { image = t; got = source.thumbMax }
            guard !op.isCancelled, let image else { return }
            let result = (image, got)
            Task { @MainActor in
                self.pending[id] = nil
                if got >= self.pixels(id) { self.store[id] = Entry(image: result.0, pixels: result.1) }
                done(id)
            }
        }
        pending[id] = (op, pixels)
        queue.addOperation(op)
    }

    /// Keep only what is near the current page: cancel the rest of the work and let the rest of the pictures go.
    func trim(keeping ids: Set<String>) {
        for (id, p) in pending where !ids.contains(id) { p.op.cancel(); pending[id] = nil }
        for id in store.keys where !ids.contains(id) { store[id] = nil }
    }

    func clear() {
        for p in pending.values { p.op.cancel() }
        pending = [:]
        store = [:]
    }
}
