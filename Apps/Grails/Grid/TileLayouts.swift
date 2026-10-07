import AppKit
import QuartzCore

/// One finished arrangement of every tile for a given column count. Tile tops never decrease with index (every
/// layout here fills top to bottom), which is what lets a visible-rect query binary-search instead of scanning.
struct TileArrangement {
    var frames: [CGRect]
    var height: CGFloat
    let maxTileHeight: CGFloat

    init(frames: [CGRect], height: CGFloat) {
        self.frames = frames
        self.height = height
        maxTileHeight = frames.reduce(0) { max($0, $1.height) }
    }
}

/// Shared geometry for the grid layouts. At rest the tiles fill each row exactly. A pinch scales that arrangement
/// in place (tiles keep their neighbours, like Photos). Letting go eases into the column count that fits.
class TileLayout: NSCollectionViewLayout {
    var targetWidth: CGFloat = 190 { didSet { if oldValue != targetWidth { invalidateLayout() } } }
    var spacing: CGFloat = 8 { didSet { if oldValue != spacing { invalidateLayout() } } }
    var inset: CGFloat = 12
    /// Arrangement being scaled. Nil at rest.
    var zoomBase: Int? { didSet { if oldValue != zoomBase, collectionView != nil { invalidateLayout() } } }
    /// Uniform scale of `zoomBase`. 1 at rest.
    var zoomScale: CGFloat = 1 { didSet { if oldValue != zoomScale, collectionView != nil { invalidateLayout() } } }
    /// Whole column count the pinch is easing into. Nil while the fingers are down.
    var settleTo: Int? { didSet { if oldValue != settleTo, collectionView != nil { invalidateLayout() } } }
    /// 0 = the scaled pinch, 1 = `settleTo` filling the row.
    var settleMix: CGFloat = 0 { didSet { if oldValue != settleMix, collectionView != nil { invalidateLayout() } } }
    /// Bump when the item set or aspect ratios change.
    var dataVersion = 0 { didSet { cache.removeAll() } }
    var itemCount: Int { collectionView?.numberOfItems(inSection: 0) ?? 0 }
    var availableWidth: CGFloat { max(1, (collectionView?.bounds.width ?? 800) - inset * 2) }
    private var lastWidth: CGFloat = 0

    private var cache: [Int: TileArrangement] = [:]
    private var cacheOrder: [Int] = []
    private var cacheSignature: [CGFloat] = []
    private var scale: CGFloat = 1
    private var blend: CGFloat = 0

    override func shouldInvalidateLayout(forBoundsChange newBounds: NSRect) -> Bool {
        defer { lastWidth = newBounds.width }
        return newBounds.width != lastWidth
    }

    /// Columns at rest for the saved tile width.
    func columnCount(for width: CGFloat) -> Int { max(1, Int((width + spacing) / (targetWidth + spacing) + 1e-6)) }

    var restColumns: Int { columnCount(for: availableWidth) }

    /// How many columns zooming can reach: tiles stay between the smallest and largest sizes.
    var columnRange: ClosedRange<Int> {
        let avail = availableWidth
        let most = max(1, Int((avail + spacing) / (Zoom.minWidth + spacing)))
        let fewest = max(1, Int(((avail + spacing) / (Zoom.maxWidth + spacing)).rounded(.up)))
        return min(fewest, most)...most
    }

    /// Tile width when `cols` columns fill the row.
    func tileWidth(forColumns cols: Int) -> CGFloat { (availableWidth - CGFloat(max(0, cols - 1)) * spacing) / CGFloat(max(1, cols)) }

    /// The arrangement for exactly `cols` columns. Subclasses lay out every item.
    func arrange(columns cols: Int) -> TileArrangement { TileArrangement(frames: [], height: 0) }

    /// Extra inputs the arrangement depends on, beyond width, spacing and item count.
    var extraSignature: [CGFloat] { [] }

    private func arrangement(_ cols: Int) -> TileArrangement {
        if let a = cache[cols] { return a }
        let a = arrange(columns: cols)
        cache[cols] = a
        cacheOrder.append(cols)
        if cacheOrder.count > 4 { cache[cacheOrder.removeFirst()] = nil }
        return a
    }

    private var arrangementA = TileArrangement(frames: [], height: 0)
    private var arrangementB: TileArrangement?

    override func prepare() {
        let sig = [availableWidth, spacing, inset, CGFloat(itemCount), CGFloat(dataVersion)] + extraSignature
        if sig != cacheSignature { cacheSignature = sig; cache.removeAll(); cacheOrder.removeAll() }
        let base = zoomBase ?? restColumns
        scale = zoomBase == nil ? 1 : zoomScale
        blend = (settleTo != nil && zoomBase != nil) ? min(max(settleMix, 0), 1) : 0
        arrangementA = arrangement(max(1, base))
        arrangementB = blend > 0.001 ? settleTo.map { arrangement(max(1, $0)) } : nil
    }

    private func frame(_ i: Int) -> CGRect? {
        guard let a = arrangementA.frames[safe: i] else { return nil }
        let s = CGRect(x: a.minX * scale, y: a.minY * scale, width: a.width * scale, height: a.height * scale)
        guard let b = arrangementB?.frames[safe: i], blend > 0 else { return s }
        let p = blend
        return CGRect(x: s.minX + (b.minX - s.minX) * p, y: s.minY + (b.minY - s.minY) * p,
                      width: s.width + (b.width - s.width) * p, height: s.height + (b.height - s.height) * p)
    }

    override var collectionViewContentSize: NSSize {
        let ha = arrangementA.height * scale
        let h = ha + ((arrangementB?.height ?? ha) - ha) * blend
        return NSSize(width: collectionView?.bounds.width ?? 0, height: max(h, 0))
    }

    override func layoutAttributesForElements(in rect: NSRect) -> [NSCollectionViewLayoutAttributes] {
        let n = arrangementA.frames.count
        guard n > 0 else { return [] }
        // Tops are non-decreasing in index (a uniform scale, and a blend of two such arrangements, keep that), so
        // find the first tile that could still reach the rect, then walk until tops pass its bottom.
        let tallest = max(arrangementA.maxTileHeight * scale, arrangementB?.maxTileHeight ?? 0)
        let reach = rect.minY - tallest
        var lo = 0, hi = n
        while lo < hi {
            let mid = (lo + hi) / 2
            if (frame(mid)?.minY ?? 0) < reach { lo = mid + 1 } else { hi = mid }
        }
        var out: [NSCollectionViewLayoutAttributes] = []
        var i = lo
        while i < n, let f = frame(i), f.minY <= rect.maxY {
            if f.intersects(rect) { out.append(attributes(i, f)) }
            i += 1
        }
        return out
    }

    override func layoutAttributesForItem(at indexPath: IndexPath) -> NSCollectionViewLayoutAttributes? {
        frame(indexPath.item).map { attributes(indexPath.item, $0) }
    }

    func attributes(_ index: Int, _ frame: CGRect) -> NSCollectionViewLayoutAttributes {
        let a = NSCollectionViewLayoutAttributes(forItemWith: IndexPath(item: index, section: 0))
        a.frame = frame
        return a
    }
}

/// Uniform square tiles.
final class SquareLayout: TileLayout {
    override func arrange(columns cols: Int) -> TileArrangement {
        let w = tileWidth(forColumns: cols)
        let n = itemCount
        var frames: [CGRect] = []
        frames.reserveCapacity(n)
        for i in 0..<n {
            frames.append(CGRect(x: inset + CGFloat(i % cols) * (w + spacing), y: inset + CGFloat(i / cols) * (w + spacing), width: w, height: w))
        }
        let rows = (n + cols - 1) / cols
        return TileArrangement(frames: frames, height: inset * 2 + CGFloat(rows) * w + CGFloat(max(0, rows - 1)) * spacing)
    }
}

/// Pinterest-style columns, each tile keeping its image's aspect ratio. New items go to the shortest column.
final class MasonryLayout: TileLayout {
    /// height / width per item, in index order
    var aspects: [CGFloat] = []

    override func arrange(columns cols: Int) -> TileArrangement {
        let t0 = CACurrentMediaTime()
        defer { HitchMonitor.record("masonryPrepare", since: t0) }
        let w = tileWidth(forColumns: cols)
        var heights = [CGFloat](repeating: inset, count: cols)
        var frames: [CGRect] = []
        frames.reserveCapacity(itemCount)
        for i in 0..<min(itemCount, aspects.count) {
            let c = heights.indices.min { heights[$0] < heights[$1] } ?? 0
            let h = min(max(w * aspects[i], w * 0.3), w * 3)
            frames.append(CGRect(x: inset + CGFloat(c) * (w + spacing), y: heights[c], width: w, height: h))
            heights[c] += h + spacing
        }
        return TileArrangement(frames: frames, height: (heights.max() ?? inset) - spacing + inset)
    }
}

/// The grid with titled sections: each section is a header row followed by its tiles (squares, or each keeping its
/// proportions, to match the grid setting). Sections are laid out one after another.
final class SectionedLayout: TileLayout {
    static let headerHeight: CGFloat = 60
    static let sectionGap: CGFloat = 36

    /// Per item index: true for a section header.
    var headerFlags: [Bool] = []
    /// height / width per item, in index order (used when tiles keep their proportions)
    var aspects: [CGFloat] = []
    var squareTiles = true { didSet { if oldValue != squareTiles { invalidateLayout() } } }

    override var extraSignature: [CGFloat] { [squareTiles ? 1 : 0] }

    override func arrange(columns cols: Int) -> TileArrangement {
        let w = tileWidth(forColumns: cols)
        var frames: [CGRect] = []
        frames.reserveCapacity(itemCount)
        var y = inset
        var i = 0
        let n = min(itemCount, headerFlags.count)
        while i < n {
            if headerFlags[i] {
                frames.append(CGRect(x: inset, y: y, width: availableWidth, height: Self.headerHeight))
                y += Self.headerHeight + spacing
                i += 1
            }
            let first = i
            while i < n, !headerFlags[i] { i += 1 }
            let count = i - first
            if squareTiles {
                for k in 0..<count {
                    frames.append(CGRect(x: inset + CGFloat(k % cols) * (w + spacing), y: y + CGFloat(k / cols) * (w + spacing), width: w, height: w))
                }
                let rows = (count + cols - 1) / cols
                if rows > 0 { y += CGFloat(rows) * (w + spacing) - spacing }
            } else {
                var heights = [CGFloat](repeating: y, count: cols)
                for k in 0..<count {
                    let c = heights.indices.min { heights[$0] < heights[$1] } ?? 0
                    let aspect = first + k < aspects.count ? aspects[first + k] : 1
                    let h = min(max(w * aspect, w * 0.3), w * 3)
                    frames.append(CGRect(x: inset + CGFloat(c) * (w + spacing), y: heights[c], width: w, height: h))
                    heights[c] += h + spacing
                }
                if count > 0 { y = (heights.max() ?? y) - spacing }
            }
            y += Self.sectionGap
        }
        return TileArrangement(frames: frames, height: max(y - Self.sectionGap, 0) + inset)
    }
}
