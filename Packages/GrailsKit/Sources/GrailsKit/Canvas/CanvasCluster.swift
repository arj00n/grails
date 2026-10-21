import Foundation

/// A group of items on a canvas that sit edge to edge, packed into rows. Clusters are what you move around the canvas; the
/// items inside are placed by the layout, not by hand. In the grid view a cluster is a titled section.
public struct CanvasCluster: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    /// Empty = untitled.
    public var title: String
    /// Top-left of the cluster (the corner of its title bar), in world units, y down.
    public var x: Double
    public var y: Double
    /// Width of the packed area. Items fill rows exactly to this width.
    public var width: Double
    /// Target row height: a bigger tile makes fewer, taller rows.
    public var tile: Double
    /// Members, in reading order.
    public var items: [String]
    /// When this cluster was last edited (seconds since 1970). Newest wins when two Macs edited the same cluster.
    public var at: Double

    public static let defaultTile = 260.0

    public init(id: String = ULID().string, title: String = "", x: Double = 0, y: Double = 0, width: Double = 1800,
                tile: Double = CanvasCluster.defaultTile, items: [String] = [], at: Double = Date().timeIntervalSince1970) {
        self.id = id; self.title = title; self.x = x; self.y = y; self.width = width; self.tile = tile; self.items = items; self.at = at
    }
}

/// Edge-to-edge row packing. Pure maths: no UI, no I/O.
public enum ClusterLayout {
    public static let headerHeight = 76.0
    public static let minWidth = 360.0
    public static let minTile = 80.0
    public static let maxTile = 900.0

    public struct Entry: Sendable, Equatable {
        public var id: String
        /// width / height of the picture
        public var aspect: Double
        public init(id: String, aspect: Double) { self.id = id; self.aspect = aspect }
    }

    /// The packed area. Rects are relative to the top-left of the content (just under the title bar), y down.
    public struct Packed: Sendable, Equatable {
        public var rects: [String: CGRect] = [:]
        public var rows: [[String]] = []
        public var height: Double = 0
    }

    /// Fills rows to exactly `width`, scaling each row's height so the pictures meet the right edge; no gaps between tiles.
    /// A short last row keeps the target height rather than stretching into something huge.
    public static func pack(_ entries: [Entry], width: Double, tile: Double) -> Packed {
        let W = max(width, minWidth)
        let T = min(max(tile, minTile), maxTile)
        var out = Packed()
        var row: [Entry] = []
        var sum = 0.0
        var y = 0.0

        func clampAspect(_ a: Double) -> Double { min(max(a.isFinite && a > 0 ? a : 1, 0.25), 4) }

        func flush(stretch: Bool) {
            guard !row.isEmpty else { return }
            let natural = sum * T
            var h = stretch ? W / sum : T
            h = min(max(h, T * 0.5), T * 2)
            let rowHeight = h.rounded()
            let fills = stretch && abs(sum * h - W) < 0.5
            var edge = 0.0
            var cumulative = 0.0
            for (i, e) in row.enumerated() {
                cumulative += clampAspect(e.aspect) * h
                let right = (i == row.count - 1 && fills) ? W : cumulative.rounded()
                out.rects[e.id] = CGRect(x: edge, y: y, width: max(right - edge, 1), height: rowHeight)
                edge = right
            }
            _ = natural
            out.rows.append(row.map(\.id))
            y += rowHeight
            row = []; sum = 0
        }

        for e in entries {
            let a = clampAspect(e.aspect)
            if !row.isEmpty, (sum + a) * T > W {
                let over = (sum + a) * T - W, under = W - sum * T
                if over < under {                      // closer to full with this one in the row
                    row.append(e); sum += a
                    flush(stretch: true)
                } else {
                    flush(stretch: true)
                    row = [e]; sum = a
                }
            } else {
                row.append(e); sum += a
            }
        }
        flush(stretch: sum * T >= W * 0.7)              // the last row fills only if it is nearly full anyway
        out.height = y
        return out
    }

    /// Where a dropped item would go: its index among `order` (the members without the dragged ones).
    /// `point` is relative to the content's top-left.
    public static func insertionIndex(of point: CGPoint, packed: Packed, order: [String]) -> Int {
        guard !packed.rows.isEmpty else { return 0 }
        if point.y < 0 { return 0 }
        // the row under the point (clamped to the first and last)
        var rowIndex = packed.rows.count - 1
        for (i, row) in packed.rows.enumerated() {
            guard let r = row.first.flatMap({ packed.rects[$0] }) else { continue }
            if point.y < r.maxY { rowIndex = i; break }
        }
        let row = packed.rows[rowIndex]
        for id in row {
            guard let r = packed.rects[id] else { continue }
            if point.x < r.midX { return order.firstIndex(of: id) ?? order.count }
        }
        // past the last tile of the row: after it
        if let last = row.last, let i = order.firstIndex(of: last) { return i + 1 }
        return order.count
    }

    /// The whole cluster, title bar included.
    public static func frame(of c: CanvasCluster, contentHeight: Double) -> CGRect {
        CGRect(x: c.x, y: c.y, width: max(c.width, minWidth), height: headerHeight + max(contentHeight, 0))
    }
}

/// Operations on a board's list of clusters. Pure: they return new lists.
public enum ClusterOps {
    /// A width that makes `count` tiles roughly a 16:10 sheet (so a library of thousands isn't one endless strip).
    public static func suggestedWidth(count: Int, tile: Double = CanvasCluster.defaultTile) -> Double {
        let area = Double(max(count, 1)) * (tile * 1.3) * tile
        return min(max((area * 1.6).squareRoot(), 1800), 60_000)
    }

    /// Items that no cluster holds join the first cluster (or a new one when the board has none).
    public static func adopt(_ ids: [String], into clusters: [CanvasCluster], at now: Double = Date().timeIntervalSince1970) -> [CanvasCluster] {
        let known = Set(clusters.flatMap(\.items))
        let fresh = ids.filter { !known.contains($0) }
        guard !fresh.isEmpty else { return clusters }
        var out = clusters
        if out.isEmpty {
            out = [CanvasCluster(width: suggestedWidth(count: fresh.count), items: fresh, at: now)]
        } else {
            out[0].items += fresh
            out[0].at = now
        }
        return out
    }

    /// A board from before clusters: its items become one cluster in their old reading order (top to bottom, left to right).
    public static func migrate(_ placements: [String: CanvasPlacement], at now: Double = Date().timeIntervalSince1970) -> [CanvasCluster] {
        guard !placements.isEmpty else { return [] }
        let tile = placements.values.map(\.h).sorted()[placements.count / 2]
        let rowTolerance = max(tile / 2, 20)
        var rows: [[(String, CanvasPlacement)]] = []
        for item in placements.sorted(by: { ($0.value.y, $0.value.x, $0.key) < ($1.value.y, $1.value.x, $1.key) }) {
            if let top = rows.last?.first, item.value.y - top.1.y <= rowTolerance { rows[rows.count - 1].append((item.key, item.value)) } else { rows.append([(item.key, item.value)]) }
        }
        let ordered = rows.flatMap { $0.sorted { ($0.1.x, $0.0) < ($1.1.x, $1.0) } }.map(\.0)
        let box = CanvasLayoutEngine.bounds(of: placements.values)
        let t = min(max(tile, ClusterLayout.minTile), ClusterLayout.maxTile)
        return [CanvasCluster(x: box?.x ?? 0, y: (box?.y ?? 0) - ClusterLayout.headerHeight, width: max(suggestedWidth(count: ordered.count, tile: t), box?.w ?? 0), tile: t, items: ordered, at: now)]
    }

    /// One item can only live in one cluster: where a merge left it in two, the most recently edited cluster keeps it.
    public static func normalized(_ clusters: [CanvasCluster]) -> [CanvasCluster] {
        var owner: [String: Int] = [:]
        for (i, c) in clusters.enumerated().sorted(by: { ($0.element.at, $1.offset) > ($1.element.at, $0.offset) }) {
            for id in c.items where owner[id] == nil { owner[id] = i }
        }
        return clusters.enumerated().map { i, c in
            var c = c
            c.items = c.items.filter { owner[$0] == i }
            return c
        }
    }

    public enum Target: Sendable {
        /// Into an existing cluster, at this index among its members (after the moved ones are taken out).
        case cluster(String, index: Int)
        /// Into a new cluster whose top-left is here.
        case newCluster(x: Double, y: Double, width: Double?, tile: Double?)
    }

    /// Takes `ids` out of wherever they are and puts them at `target`. Clusters left empty are removed.
    public static func move(_ ids: [String], to target: Target, in clusters: [CanvasCluster], at now: Double = Date().timeIntervalSince1970) -> [CanvasCluster] {
        let moving = Set(ids)
        guard !moving.isEmpty else { return clusters }
        var out = clusters
        for i in out.indices where out[i].items.contains(where: moving.contains) {
            out[i].items.removeAll(where: moving.contains)
            out[i].at = now
        }
        switch target {
        case .cluster(let id, let index):
            if let i = out.firstIndex(where: { $0.id == id }) {
                let at = min(max(index, 0), out[i].items.count)
                out[i].items.insert(contentsOf: ids, at: at)
                out[i].at = now
            }
        case .newCluster(let x, let y, let width, let tile):
            let t = tile ?? CanvasCluster.defaultTile
            out.append(CanvasCluster(x: x, y: y, width: width ?? max(ClusterLayout.minWidth, min(suggestedWidth(count: ids.count, tile: t), 1800)), tile: t, items: ids, at: now))
        }
        return out.filter { !$0.items.isEmpty }
    }

    /// Lays cluster blocks out in rows, left to right, wrapping when a row would pass `maxRowWidth`. `heights` are the blocks' full heights.
    public static func tidy(_ clusters: [CanvasCluster], heights: [String: Double], maxRowWidth: Double? = nil, gap: Double = 160) -> [String: (x: Double, y: Double)] {
        guard !clusters.isEmpty else { return [:] }
        let ordered = clusters.sorted { ($0.y, $0.x, $0.id) < ($1.y, $1.x, $1.id) }
        let total = ordered.reduce(0.0) { $0 + max($1.width, ClusterLayout.minWidth) }
        let limit = maxRowWidth ?? max(total / 2, ordered.map(\.width).max() ?? 0)
        let originX = clusters.map(\.x).min() ?? 0, originY = clusters.map(\.y).min() ?? 0
        var out: [String: (x: Double, y: Double)] = [:]
        var x = originX, y = originY, rowH = 0.0
        for c in ordered {
            let w = max(c.width, ClusterLayout.minWidth)
            if x > originX, x + w > originX + limit { x = originX; y += rowH + gap; rowH = 0 }
            out[c.id] = (x, y)
            x += w + gap
            rowH = max(rowH, heights[c.id] ?? ClusterLayout.headerHeight)
        }
        return out
    }
}
