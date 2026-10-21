import Foundation

public enum VisionBackfill {
    public static func pictureURL(_ item: Item, _ layout: LibraryLayout) -> URL? {
        let thumb = layout.thumbURL(item.id)
        if item.kind == .video || item.kind == .link {
            return localFile(thumb)
        }
        if let name = item.file {
            let original = layout.itemDir(item.id).appendingPathComponent(name)
            if let url = localFile(original) { return url }
        }
        return localFile(thumb)
    }

    public static func analyze(itemId: String, sha256: String, url: URL) async -> VisionRecord {
        await Task.detached(priority: .utility) {
            let ocrImage = ImageSignals.cgImage(at: url, maxPixel: 1600)
            let small = ImageSignals.cgImage(at: url, maxPixel: 512) ?? ocrImage
            let text = ocrImage.map { TextRecognizer.recognize($0) } ?? ""
            let swatches = small.map { PaletteExtractor.swatches(from: $0) } ?? []
            let print = small.flatMap { ImageFeatures.data(from: $0) }
            let clipped = text.count > 8_000 ? String(text.prefix(8_000)) : text
            return VisionRecord(itemId: itemId, sha256: sha256, ocrText: clipped, swatches: swatches, featurePrint: print)
        }.value
    }

    @discardableResult
    public static func run(store: LibraryStore, pause: (@Sendable () async -> Void)? = nil) async -> Int {
        let pause: @Sendable () async -> Void = pause ?? {
            await Task.yield()
            try? await Task.sleep(for: .milliseconds(60))
        }
        var done = 0
        // Every item this run has tried, read or not. The query leaves them out, so a batch of
        // cloud-only or thumbnail-less items can't come back and stall the queue.
        var tried: Set<String> = []
        while !Task.isCancelled {
            let batch: [(id: String, sha256: String)]
            do {
                batch = try await store.index.visionPending(limit: 8, excluding: tried)
            } catch {
                return done
            }
            if batch.isEmpty { return done }
            for row in batch {
                if Task.isCancelled { return done }
                tried.insert(row.id)
                guard let item = try? await store.item(id: row.id), let url = pictureURL(item, store.layout) else { continue }
                let record = await analyze(itemId: row.id, sha256: row.sha256, url: url)
                if (try? await store.index.saveVision(record)) != nil { done += 1 }
                await pause()
            }
        }
        return done
    }

    public static func similarIDs(to id: String, store: LibraryStore, limit: Int = 60) async throws -> [String] {
        if let item = try await store.item(id: id), let url = pictureURL(item, store.layout) {
            let sha = item.sha256 ?? ""
            let existing = try await store.index.vision(for: id)
            if existing?.featurePrint == nil || existing?.sha256 != sha {
                let record = await analyze(itemId: id, sha256: sha, url: url)
                try await store.index.saveVision(record)
            }
        }
        guard let query = try await store.index.featurePrint(for: id) else { return [] }
        let others = try await store.index.featurePrints(excluding: id)
        return SimilarityRank.order(ImageFeatures.distances(query: query, candidates: others), limit: limit)
    }

    private static func localFile(_ url: URL) -> URL? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        guard FileAvailability.of(url) == .local else { return nil }
        return url
    }
}
