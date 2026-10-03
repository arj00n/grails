import AppKit
import QuartzCore

/// Shared geometry settings for both grid layouts.
class TileLayout: NSCollectionViewLayout {
    var targetWidth: CGFloat = 190 { didSet { if oldValue != targetWidth { invalidateLayout() } } }
    var spacing: CGFloat = 8 { didSet { if oldValue != spacing { invalidateLayout() } } }
    var inset: CGFloat = 12
    var itemCount: Int { collectionView?.numberOfItems(inSection: 0) ?? 0 }
    var availableWidth: CGFloat { max(1, (collectionView?.bounds.width ?? 800) - inset * 2) }
    private var lastWidth: CGFloat = 0

    override func shouldInvalidateLayout(forBoundsChange newBounds: NSRect) -> Bool {
        defer { lastWidth = newBounds.width }
        return newBounds.width != lastWidth
    }

    func columnCount(for width: CGFloat) -> Int { max(1, Int((width + spacing) / (targetWidth + spacing))) }

    func attributes(_ index: Int, _ frame: CGRect) -> NSCollectionViewLayoutAttributes {
        let a = NSCollectionViewLayoutAttributes(forItemWith: IndexPath(item: index, section: 0))
        a.frame = frame
        return a
    }
}

/// Uniform square tiles. All geometry is arithmetic, so it costs nothing at 20k+ items.
final class SquareLayout: TileLayout {
    private var cols = 1
    private var tile: CGFloat = 100
    private var height: CGFloat = 0

    override func prepare() {
        cols = columnCount(for: availableWidth)
        tile = (availableWidth - CGFloat(cols - 1) * spacing) / CGFloat(cols)
        let rows = (itemCount + cols - 1) / cols
        height = inset * 2 + CGFloat(rows) * tile + CGFloat(max(0, rows - 1)) * spacing
    }

    override var collectionViewContentSize: NSSize { NSSize(width: collectionView?.bounds.width ?? 0, height: height) }

    private func frame(_ i: Int) -> CGRect {
        let row = i / cols, col = i % cols
        return CGRect(x: inset + CGFloat(col) * (tile + spacing), y: inset + CGFloat(row) * (tile + spacing), width: tile, height: tile)
    }

    override func layoutAttributesForElements(in rect: NSRect) -> [NSCollectionViewLayoutAttributes] {
        let n = itemCount
        guard n > 0 else { return [] }
        let stride = tile + spacing
        let firstRow = max(0, Int((rect.minY - inset) / stride))
        let lastRow = max(0, Int((rect.maxY - inset) / stride))
        let first = firstRow * cols, last = min(n - 1, (lastRow + 1) * cols - 1)
        guard first <= last else { return [] }
        return (first...last).map { attributes($0, frame($0)) }
    }

    override func layoutAttributesForItem(at indexPath: IndexPath) -> NSCollectionViewLayoutAttributes? {
        indexPath.item < itemCount ? attributes(indexPath.item, frame(indexPath.item)) : nil
    }
}

/// Pinterest-style columns, each tile keeping its image's aspect ratio. New items go to the shortest column.
final class MasonryLayout: TileLayout {
    /// height / width per item, in index order
    var aspects: [CGFloat] = []
    private var frames: [CGRect] = []
    private var columns: [[Int]] = []
    private var height: CGFloat = 0

    /// Inputs the current geometry was computed from; `prepare()` is a no-op while they're unchanged.
    private var signature: [CGFloat] = []
    /// Bump when the item set or aspect ratios change.
    var dataVersion = 0 { didSet { signature = [] } }

    override func prepare() {
        let sig: [CGFloat] = [availableWidth, targetWidth, spacing, inset, CGFloat(itemCount), CGFloat(dataVersion)]
        guard sig != signature else { return }
        signature = sig
        let t0 = CACurrentMediaTime()
        defer { HitchMonitor.record("masonryPrepare", since: t0) }
        let cols = columnCount(for: availableWidth)
        let w = (availableWidth - CGFloat(cols - 1) * spacing) / CGFloat(cols)
        var heights = [CGFloat](repeating: inset, count: cols)
        columns = Array(repeating: [], count: cols)
        frames = []
        frames.reserveCapacity(itemCount)
        for i in 0..<min(itemCount, aspects.count) {
            let c = heights.indices.min { heights[$0] < heights[$1] } ?? 0
            let h = min(max(w * aspects[i], w * 0.3), w * 3)
            frames.append(CGRect(x: inset + CGFloat(c) * (w + spacing), y: heights[c], width: w, height: h))
            columns[c].append(i)
            heights[c] += h + spacing
        }
        height = (heights.max() ?? inset) - spacing + inset
    }

    override var collectionViewContentSize: NSSize { NSSize(width: collectionView?.bounds.width ?? 0, height: max(height, 0)) }

    override func layoutAttributesForElements(in rect: NSRect) -> [NSCollectionViewLayoutAttributes] {
        var out: [NSCollectionViewLayoutAttributes] = []
        for col in columns {
            // first tile in this column whose bottom edge reaches the rect
            var lo = 0, hi = col.count
            while lo < hi {
                let mid = (lo + hi) / 2
                if frames[col[mid]].maxY < rect.minY { lo = mid + 1 } else { hi = mid }
            }
            var k = lo
            while k < col.count, frames[col[k]].minY <= rect.maxY {
                out.append(attributes(col[k], frames[col[k]]))
                k += 1
            }
        }
        return out
    }

    override func layoutAttributesForItem(at indexPath: IndexPath) -> NSCollectionViewLayoutAttributes? {
        indexPath.item < frames.count ? attributes(indexPath.item, frames[indexPath.item]) : nil
    }

    func frame(ofItem i: Int) -> CGRect? { frames.indices.contains(i) ? frames[i] : nil }
}
