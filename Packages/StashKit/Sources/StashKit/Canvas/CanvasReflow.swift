import Foundation

/// Makes room on the canvas: when items are dragged (or grown) onto others, the others are pushed aside, and anything
/// they bump into is pushed in turn. Pure maths: no UI, no I/O. Items in `moved` never change.
public enum CanvasReflow {
    public static let defaultGap = 16.0

    /// - Parameters:
    ///   - moved: the items being dragged or resized, already at their new places in `placements`.
    ///   - hint: the direction of the drag (world units, y down). Pushes prefer to go that way, like a snowplow.
    ///   - gap: breathing room kept between a pusher and what it pushes.
    /// - Returns: new placements for the items that had to move (only those).
    public static func resolve(
        moved: Set<String>, in placements: [String: CanvasPlacement], hint: (dx: Double, dy: Double) = (0, 0),
        gap: Double = defaultGap, maxPushesPerItem: Int = 12, maxTravel: Double = 6_000
    ) -> [String: CanvasPlacement] {
        let movers = moved.filter { placements[$0] != nil }
        guard !movers.isEmpty else { return [:] }
        var current = placements
        var grid = SpatialGrid(cell: 600)
        for (id, p) in placements { grid.insert(id, rect(p)) }
        var pushes: [String: Int] = [:]
        var displaced = Set<String>()
        let held = movers.sorted().compactMap { placements[$0] }.map { rect($0) }       // what pushed items must never be pushed back under
        var queue = movers.sorted()                 // sorted: the result never depends on dictionary order
        var head = 0
        var budget = max(placements.count * 4, 2_000)

        while head < queue.count, budget > 0 {
            let pusherID = queue[head]; head += 1
            guard let pusher = current[pusherID] else { continue }
            let zone = rect(pusher).insetBy(dx: -gap, dy: -gap)
            for otherID in grid.query(zone).sorted() where otherID != pusherID && !movers.contains(otherID) {
                guard var other = current[otherID] else { continue }
                let box = rect(other)
                guard box.intersects(zone) else { continue }
                budget -= 1
                if pushes[otherID, default: 0] >= maxPushesPerItem { continue }
                let (dx, dy) = escape(other: box, from: rect(pusher), gap: gap, hint: hint, avoiding: held)
                guard dx != 0 || dy != 0 else { continue }
                other.x += dx; other.y += dy
                if let home = placements[otherID], abs(other.x - home.x) > maxTravel || abs(other.y - home.y) > maxTravel { continue }
                grid.move(otherID, from: box, to: rect(other))
                current[otherID] = other
                pushes[otherID, default: 0] += 1
                displaced.insert(otherID)
                queue.append(otherID)               // what it now touches is pushed on in turn
            }
        }
        // Last word: whatever cascades did, nothing may be left beneath a dragged item.
        for _ in 0..<4 {
            var moved = false
            for mover in held {
                for otherID in grid.query(mover).sorted() where !movers.contains(otherID) {
                    guard var other = current[otherID] else { continue }
                    let box = rect(other)
                    guard box.intersects(mover) else { continue }
                    let (dx, dy) = escape(other: box, from: mover, gap: gap, hint: hint, avoiding: held)
                    guard dx != 0 || dy != 0 else { continue }
                    other.x += dx; other.y += dy
                    grid.move(otherID, from: box, to: rect(other))
                    current[otherID] = other
                    displaced.insert(otherID)
                    moved = true
                }
            }
            if !moved { break }
        }
        let now = Date().timeIntervalSince1970
        var out: [String: CanvasPlacement] = [:]
        for id in displaced {
            guard var p = current[id], let before = placements[id], p.x != before.x || p.y != before.y else { continue }
            p.at = now
            out[id] = p
        }
        return out
    }

    /// The smallest slide that takes `other` clear of `pusher` plus `gap`, leaning towards the drag direction.
    static func escape(other o: CGRect, from p: CGRect, gap: Double, hint: (dx: Double, dy: Double), avoiding held: [CGRect] = []) -> (Double, Double) {
        // how far `other` must travel to clear the pusher in each direction
        let right = Double(p.maxX) + gap - Double(o.minX)
        let left = Double(o.maxX) - (Double(p.minX) - gap)
        let down = Double(p.maxY) + gap - Double(o.minY)
        let up = Double(o.maxY) - (Double(p.minY) - gap)
        var options: [(cost: Double, dx: Double, dy: Double)] = [(right, right, 0), (left, -left, 0), (down, 0, down), (up, 0, -up)]
        let h = hypot(hint.dx, hint.dy)
        // a pusher's own centre-to-centre direction breaks ties, so pushes fan out instead of all going one way
        let cx = Double(o.midX - p.midX), cy = Double(o.midY - p.midY)
        for i in options.indices {
            var bias = 1.0
            if h > 0.0001 {
                let align = (options[i].dx * hint.dx + options[i].dy * hint.dy) / (max(abs(options[i].dx + options[i].dy), 1) * h)
                bias -= 0.45 * align                       // going with the drag is cheaper, going against it dearer
            }
            let toward = (options[i].dx * cx + options[i].dy * cy)
            if toward < 0 { bias += 0.25 }                 // sliding back through the pusher's middle feels wrong
            options[i].cost *= bias
        }
        let usable = options.filter { $0.cost > 0 }
        // prefer a slide that doesn't end up under a dragged item; if every way does, take the cheapest anyway
        let clear = usable.filter { opt in !held.contains { $0.intersects(o.offsetBy(dx: opt.dx, dy: opt.dy)) } }
        guard let best = (clear.isEmpty ? usable : clear).min(by: { ($0.cost, $0.dx, $0.dy) < ($1.cost, $1.dx, $1.dy) }) else { return (0, 0) }
        return (best.dx, best.dy)
    }

    static func rect(_ p: CanvasPlacement) -> CGRect { CGRect(x: p.x, y: p.y, width: p.w, height: p.h) }
}

/// A uniform hash grid over world space, so a push only looks at its neighbours, however big the board is.
struct SpatialGrid {
    let cell: Double
    private var buckets: [Int64: Set<String>] = [:]

    init(cell: Double) { self.cell = cell }

    private func span(_ r: CGRect) -> (x0: Int, x1: Int, y0: Int, y1: Int) {
        (Int((Double(r.minX) / cell).rounded(.down)), Int((Double(r.maxX) / cell).rounded(.down)),
         Int((Double(r.minY) / cell).rounded(.down)), Int((Double(r.maxY) / cell).rounded(.down)))
    }

    private static func key(_ x: Int, _ y: Int) -> Int64 { (Int64(x) << 32) ^ (Int64(y) & 0xFFFF_FFFF) }

    mutating func insert(_ id: String, _ r: CGRect) {
        let s = span(r)
        for x in s.x0...s.x1 { for y in s.y0...s.y1 { buckets[Self.key(x, y), default: []].insert(id) } }
    }

    mutating func remove(_ id: String, _ r: CGRect) {
        let s = span(r)
        for x in s.x0...s.x1 { for y in s.y0...s.y1 { buckets[Self.key(x, y)]?.remove(id) } }
    }

    mutating func move(_ id: String, from a: CGRect, to b: CGRect) { remove(id, a); insert(id, b) }

    func query(_ r: CGRect) -> Set<String> {
        let s = span(r)
        var out = Set<String>()
        for x in s.x0...s.x1 { for y in s.y0...s.y1 { if let b = buckets[Self.key(x, y)] { out.formUnion(b) } } }
        return out
    }
}
