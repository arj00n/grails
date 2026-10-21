import CoreGraphics

/// Sticky section headers. The header of the section under the viewport sits on the top edge. The next header pushes it up, so two headers never share the same space.
public enum SectionPins {
    /// The header that floats on the viewport, and its top relative to the viewport's top edge: 0 while it is stuck,
    /// negative while the next header pushes it up. Nil when every header is in its laid-out place.
    ///
    /// The grid draws this header on the scroll view itself, not in the scrolling document, so its place on screen
    /// never waits for a layout pass to catch up with the scroll.
    /// `headers` are in document order, y down. `visibleTop` is the top of the viewport in those coordinates.
    public static func floating(_ headers: [CGRect], visibleTop: CGFloat) -> (index: Int, offset: CGFloat)? {
        // the last header whose laid-out top has scrolled above the viewport (tops increase with index)
        var lo = 0, hi = headers.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if headers[mid].minY < visibleTop { lo = mid + 1 } else { hi = mid }
        }
        guard lo > 0 else { return nil }
        let i = lo - 1
        let height = headers[i].height
        let nextY = i + 1 < headers.count ? headers[i + 1].minY : .greatestFiniteMagnitude
        let offset = min(0, nextY - height - visibleTop)
        guard offset > -height else { return nil }
        return (i, offset)
    }
}
