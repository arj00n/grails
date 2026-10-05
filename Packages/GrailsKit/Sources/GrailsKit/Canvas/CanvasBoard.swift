import CryptoKit
import Foundation

/// Where one item sits on a canvas board. World units are free-floating points; y grows downward, origin top-left.
public struct CanvasPlacement: Codable, Hashable, Sendable {
    public var x: Double
    public var y: Double
    public var w: Double
    public var h: Double
    /// Stacking order: higher is in front.
    public var z: Int
    /// When this placement was last edited (seconds since 1970). Newest wins when two Macs edited the same board.
    public var at: Double

    public init(x: Double, y: Double, w: Double, h: Double, z: Int = 0, at: Double = Date().timeIntervalSince1970) {
        self.x = x; self.y = y; self.w = w; self.h = h; self.z = z; self.at = at
    }

    public var maxX: Double { x + w }
    public var maxY: Double { y + h }
}

/// `canvas/<key>.json` — the free-form arrangement for one view (a collection, a tag, a smart folder, or the whole library).
public struct CanvasBoard: Codable, Sendable, Equatable {
    public var schema: Int
    public var key: String
    public var updatedAt: Date
    public var updatedBy: String
    /// Free-form placements from before clusters; kept so older Grails versions and older boards still work.
    public var placements: [String: CanvasPlacement]
    /// Groups of items that sit edge to edge. When present, these decide what the canvas shows.
    public var clusters: [CanvasCluster]

    public init(key: String, placements: [String: CanvasPlacement] = [:], clusters: [CanvasCluster] = [], updatedAt: Date = .grailsNow, updatedBy: String = "") {
        self.schema = GrailsKit.schemaVersion
        self.key = key; self.placements = placements; self.clusters = clusters; self.updatedAt = updatedAt; self.updatedBy = updatedBy
    }

    private enum CodingKeys: String, CodingKey { case schema, key, updatedAt, updatedBy, placements, clusters }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schema = try c.decode(Int.self, forKey: .schema)
        key = try c.decode(String.self, forKey: .key)
        updatedAt = try c.decode(Date.self, forKey: .updatedAt)
        updatedBy = try c.decode(String.self, forKey: .updatedBy)
        placements = try c.decodeIfPresent([String: CanvasPlacement].self, forKey: .placements) ?? [:]
        clusters = try c.decodeIfPresent([CanvasCluster].self, forKey: .clusters) ?? []
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(schema, forKey: .schema)
        try c.encode(key, forKey: .key)
        try c.encode(updatedAt, forKey: .updatedAt)
        try c.encode(updatedBy, forKey: .updatedBy)
        try c.encode(placements, forKey: .placements)
        if !clusters.isEmpty { try c.encode(clusters, forKey: .clusters) }
    }

    /// Per placement, the newer edit wins; placements only one side has are kept.
    public static func merge(_ a: CanvasBoard, _ b: CanvasBoard) -> CanvasBoard {
        var out = a.updatedAt >= b.updatedAt ? a : b
        out.placements = a.placements.merging(b.placements) { x, y in x.at >= y.at ? x : y }
        // clusters: per cluster, the newer edit wins; clusters only one side has are kept; no item ends up in two
        var byID: [String: CanvasCluster] = [:]
        var order: [String] = []
        for c in a.clusters + b.clusters {
            if let existing = byID[c.id] { byID[c.id] = existing.at >= c.at ? existing : c } else { byID[c.id] = c; order.append(c.id) }
        }
        out.clusters = ClusterOps.normalized(order.compactMap { byID[$0] }).filter { !$0.items.isEmpty }
        out.updatedAt = max(a.updatedAt, b.updatedAt)
        return out
    }
}

/// Stable file names for boards. Names are file-safe whatever the tag text is.
public enum CanvasKey {
    public static let library = "library"
    public static let inbox = "inbox"
    public static func collection(_ id: String) -> String { id }
    public static func smart(_ id: String) -> String { id }
    public static func tag(_ name: String) -> String {
        let h = SHA256.hash(data: Data(name.lowercased().utf8)).prefix(6).map { String(format: "%02x", $0) }.joined()
        return "tag-\(h)"
    }
}

/// Pure layout maths for the canvas: default sizes and shelf packing. No UI, no I/O.
public enum CanvasLayoutEngine {
    public static let defaultHeight = 240.0
    public static let gap = 24.0
    public static let minSide = 24.0

    public struct Entry: Sendable, Equatable {
        public var id: String
        /// width / height of the picture
        public var aspect: Double
        public init(id: String, aspect: Double) { self.id = id; self.aspect = aspect }
    }

    /// A size with the picture's proportions at a given height; extreme panoramas and slivers are tamed.
    public static func size(aspect: Double, height: Double = defaultHeight) -> (w: Double, h: Double) {
        let a = min(max(aspect.isFinite && aspect > 0 ? aspect : 1, 0.3), 3.5)
        return (height * a, height)
    }

    /// Fills rows left to right, wrapping at `maxWidth`, starting at `origin`. Items get z values from `zStart` up.
    public static func shelfPack(
        _ entries: [Entry], origin: (x: Double, y: Double), maxWidth: Double, height: Double = defaultHeight,
        gap: Double = CanvasLayoutEngine.gap, zStart: Int = 0, at: Double = Date().timeIntervalSince1970
    ) -> [String: CanvasPlacement] {
        var out: [String: CanvasPlacement] = [:]
        var x = origin.x, y = origin.y, rowH = 0.0
        for (i, e) in entries.enumerated() {
            let s = size(aspect: e.aspect, height: height)
            if x > origin.x, x + s.w > origin.x + maxWidth { x = origin.x; y += rowH + gap; rowH = 0 }
            out[e.id] = CanvasPlacement(x: x, y: y, w: s.w, h: s.h, z: zStart + i, at: at)
            x += s.w + gap
            rowH = max(rowH, s.h)
        }
        return out
    }

    /// First arrangement of a board: roughly a 16:10 sheet.
    public static func initialLayout(_ entries: [Entry], at: Double = Date().timeIntervalSince1970) -> [String: CanvasPlacement] {
        let area = entries.reduce(0.0) { $0 + size(aspect: $1.aspect).w * defaultHeight }
        let width = max(1400, (area * 1.6).squareRoot() * 1.15)
        return shelfPack(entries, origin: (0, 0), maxWidth: width, at: at)
    }

    public static func bounds<S: Sequence>(of placements: S) -> (x: Double, y: Double, w: Double, h: Double)? where S.Element == CanvasPlacement {
        var minX = Double.infinity, minY = Double.infinity, maxX = -Double.infinity, maxY = -Double.infinity
        var any = false
        for p in placements { any = true; minX = min(minX, p.x); minY = min(minY, p.y); maxX = max(maxX, p.maxX); maxY = max(maxY, p.maxY) }
        return any ? (minX, minY, maxX - minX, maxY - minY) : nil
    }

    /// New items go in a band below what's already there, so nothing lands on top of existing work.
    public static func placeNew(
        _ entries: [Entry], existing: [String: CanvasPlacement], at: Double = Date().timeIntervalSince1970
    ) -> [String: CanvasPlacement] {
        guard !entries.isEmpty else { return [:] }
        guard let b = bounds(of: existing.values) else { return initialLayout(entries, at: at) }
        let z = (existing.values.map(\.z).max() ?? 0) + 1
        return shelfPack(entries, origin: (b.x, b.y + b.h + gap * 3), maxWidth: max(b.w, 1400), zStart: z, at: at)
    }

    /// Re-packs `ids` into rows starting at their joint top-left, in reading order (top to bottom, left to right).
    /// Each item keeps its own size; only positions change. Rows wrap at the selection's current width.
    public static func arrange(
        _ ids: [String], in placements: [String: CanvasPlacement], gap: Double = CanvasLayoutEngine.gap,
        at: Double = Date().timeIntervalSince1970
    ) -> [String: CanvasPlacement] {
        let chosen = ids.compactMap { id in placements[id].map { (id, $0) } }
        guard let b = bounds(of: chosen.map(\.1)) else { return [:] }
        // Reading order: cluster into rows by top edge (a row starts at its highest item and takes anything within half an
        // item's height below it), then left to right inside each row. Clustering, rather than a tolerant comparison, keeps
        // the ordering consistent however the items are scattered.
        let rowTolerance = (chosen.map(\.1.h).max() ?? defaultHeight) / 2
        var rows: [[(String, CanvasPlacement)]] = []
        for item in chosen.sorted(by: { ($0.1.y, $0.1.x, $0.0) < ($1.1.y, $1.1.x, $1.0) }) {
            if let top = rows.last?.first, item.1.y - top.1.y <= rowTolerance { rows[rows.count - 1].append(item) } else { rows.append([item]) }
        }
        let ordered = rows.flatMap { $0.sorted { ($0.1.x, $0.0) < ($1.1.x, $1.0) } }
        let maxWidth = max(b.w, chosen.map(\.1.w).max() ?? 0)
        var out: [String: CanvasPlacement] = [:]
        var x = b.x, y = b.y, rowH = 0.0
        for (id, p) in ordered {
            if x > b.x, x + p.w > b.x + maxWidth { x = b.x; y += rowH + gap; rowH = 0 }
            out[id] = CanvasPlacement(x: x, y: y, w: p.w, h: p.h, z: p.z, at: at)
            x += p.w + gap
            rowH = max(rowH, p.h)
        }
        return out
    }
}
