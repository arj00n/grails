import AppKit
import GrailsDesign
import QuartzCore
import GrailsKit

/// An infinite, pannable, zoomable board of clusters. A cluster is a group of items packed edge to edge into rows under a
/// title; you move clusters around the board, and items between them. The items' own positions come from the layout.
///
/// World space: points, y down, origin anywhere. The viewport is `origin` (the world point at the view's top-left)
/// and `scale` (screen points per world point). Items are CALayers under one content layer whose affine transform
/// is the viewport, so panning and zooming only change a transform (GPU work) no matter how many items exist.
@MainActor
final class CanvasNSView: NSView {
    // MARK: Callbacks
    var onSelectionChange: ((Set<String>) -> Void)?
    /// The board's clusters after an edit, plus an undo label ("Move on Canvas", "Group", …).
    var onCommitClusters: (([CanvasCluster], String) -> Void)?
    var onRenameClusterTo: ((String, String) -> Void)?
    var onPreview: ((String) -> Void)?
    var keyHandler: ((NSEvent) -> Bool)?
    var contextMenuProvider: ((String) -> NSMenu?)?
    var clusterMenuProvider: ((String) -> NSMenu?)?
    var onPaste: (() -> Void)?
    var onViewportSettled: ((String, CGPoint, CGFloat) -> Void)?
    var onOptionClick: ((String) -> Void)?
    var onSearch: (() -> Void)?
    /// False in views that have no board to save to (the Trash): items can be selected and previewed but not rearranged.
    var editable = true { didSet { if oldValue != editable { for h in headers.values { h.isHidden = !editable } } } }

    // MARK: Data
    var layout: LibraryLayout?
    private(set) var boardKey: String?
    private(set) var items: [String: ItemSummary] = [:]
    private(set) var clusters: [CanvasCluster] = []
    /// Where each visible item sits, from the cluster layout (world space). Everything that needs "the rect of item X" reads this.
    private(set) var placements: [String: CanvasPlacement] = [:]
    private var clusterFrames: [String: CGRect] = [:]          // world, title bar included
    private var memberOf: [String: String] = [:]               // item id → cluster id
    private(set) var selection: Set<String> = []

    // MARK: Viewport
    private(set) var scale: CGFloat = 0.5
    private(set) var origin = CGPoint(x: -60, y: -60)
    static let minScale: CGFloat = 0.004
    static let maxScale: CGFloat = 16

    // MARK: Layers
    private let content = CALayer()
    private let dust = DustLayer()
    private let overlay = CAShapeLayer()
    private let marqueeLayer = CAShapeLayer()
    private let dropOutline = CAShapeLayer()
    private var layers: [String: CanvasItemLayer] = [:]
    private var headers: [String: ClusterHeaderLayer] = [:]
    private var entries: [Entry] = []          // every placed item
    private var imageUpgradeWork: DispatchWorkItem?
    private var settleWork: DispatchWorkItem?
    private var axChildren: [CanvasAXElement] = []
    /// Fit-everything is requested before the view has a size on first display; it runs once there is one.
    private var pendingFit = false
    /// Only a viewport the person (or a fit command) actually set is worth remembering.
    private var viewportDirty = false
    /// Parts of the view covered by floating panels; fitting centres on what's left.
    var contentInsets = NSEdgeInsets()
    private var focus: CGPoint {      // the centre of the uncovered area, in points from the top-left
        CGPoint(x: contentInsets.left + (bounds.width - contentInsets.left - contentInsets.right) / 2,
                y: contentInsets.top + (bounds.height - contentInsets.top - contentInsets.bottom) / 2)
    }

    struct Entry { var id: String; var rect: CGRect; var z: Int }     // rect in world space, y down

    /// Beyond this many visible tiles, the smallest are drawn as dust instead of getting their own layer.
    private let layerCap = 1_200
    private let minLayerPixels: CGFloat = 5

    // MARK: Interaction state
    private final class ItemDrag {
        let ids: [String]                          // dragged items, in reading order
        let startWorld: CGPoint
        let startScreen: CGPoint
        let baseClusters: [CanvasCluster]
        let baseFrames: [String: CGRect]
        let basePlacements: [String: CanvasPlacement]
        var lifted = false
        var previewed: Set<String> = []
        var result: [CanvasCluster]
        var resultKey = ""
        var targetID: String?
        var newClusterFrame: CGRect?
        init(ids: [String], startWorld: CGPoint, startScreen: CGPoint, baseClusters: [CanvasCluster], baseFrames: [String: CGRect], basePlacements: [String: CanvasPlacement]) {
            self.ids = ids; self.startWorld = startWorld; self.startScreen = startScreen; self.baseClusters = baseClusters; self.baseFrames = baseFrames
            self.basePlacements = basePlacements; self.result = baseClusters
        }
    }
    private final class BlockDrag {
        let id: String
        let startWorld: CGPoint
        let startScreen: CGPoint
        let baseClusters: [CanvasCluster]
        let startX: Double, startY: Double, startWidth: Double
        var moved = false
        init(id: String, startWorld: CGPoint, startScreen: CGPoint, baseClusters: [CanvasCluster]) {
            self.id = id; self.startWorld = startWorld; self.startScreen = startScreen; self.baseClusters = baseClusters
            let c = baseClusters.first { $0.id == id }
            startX = c?.x ?? 0; startY = c?.y ?? 0; startWidth = c?.width ?? 0
        }
    }
    private enum Drag {
        case pan(start: CGPoint, originAtStart: CGPoint)
        case marquee(start: CGPoint, base: Set<String>)
        case items(ItemDrag)
        case cluster(BlockDrag)
        case clusterWidth(BlockDrag)
    }
    private var drag: Drag?
    /// Whether moving a cluster pushes other clusters out of the way. Read each time, so the setting applies immediately.
    var pushEnabled: () -> Bool = { true }
    private var spaceHeld = false
    private var spaceUsedForPan = false
    private var animationLink: CADisplayLink?
    private var animation: (from: (CGPoint, CGFloat), to: (CGPoint, CGFloat), start: CFTimeInterval, duration: CFTimeInterval)?

    // MARK: Setup

    override init(frame: NSRect) {
        super.init(frame: frame)
        layer = CALayer()
        wantsLayer = true
        layer?.masksToBounds = true
        content.anchorPoint = .zero
        content.position = .zero
        content.bounds = .zero
        layer?.addSublayer(content)
        dust.zPosition = -1_000_000
        content.addSublayer(dust)
        dropOutline.fillColor = nil
        dropOutline.lineDashPattern = [0.1, 3]
        dropOutline.actions = ["path": NSNull(), "hidden": NSNull(), "position": NSNull(), "bounds": NSNull()]
        dropOutline.zPosition = 9_000
        dropOutline.isHidden = true
        content.addSublayer(dropOutline)
        for l in [overlay, marqueeLayer] { l.actions = ["path": NSNull(), "position": NSNull(), "bounds": NSNull(), "hidden": NSNull()]; layer?.addSublayer(l) }
        overlay.fillColor = nil
        overlay.lineWidth = 1.5
        marqueeLayer.lineWidth = 1
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityIdentifier("canvas")
        setAccessibilityLabel("Canvas")
        refreshColors()
    }

    required init?(coder: NSCoder) { fatalError() }

    override var acceptsFirstResponder: Bool { true }
    override var isFlipped: Bool { false }
    private var backing: CGFloat { window?.backingScaleFactor ?? 2 }

    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); refreshColors() }

    private func refreshColors() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            overlay.strokeColor = NSColor.ink(.text).cgColor
            marqueeLayer.strokeColor = NSColor.ink(.focus).cgColor
            marqueeLayer.fillColor = NSColor.ink(.focus).withAlphaComponent(0.08).cgColor
            dropOutline.strokeColor = NSColor.ink(.focus).cgColor
            dust.color = NSColor.ink(.fill).cgColor
            layer?.backgroundColor = NSColor.ink(.canvas).cgColor
            for l in layers.values { l.restyle(scale: scale) }
        }
        if !headers.isEmpty { syncHeaders() }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
        let s = backing
        for l in [overlay, marqueeLayer] { l.contentsScale = s }
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        applyViewport()
        fitIfPending()
    }

    // MARK: Data in

    func setItems(_ list: [ItemSummary]) {
        items = Dictionary(list.map { ($0.id, $0) }, uniquingKeysWith: { _, new in new })
        applyLayout()
        for (id, l) in layers { if let s = items[id] { l.summary = s } }
        syncLayers()
        for l in layers.values where l.loadedBucket == 0 { loadImage(for: l, force: true) }
        publishAccessibility()
    }

    /// Replaces the board. A different board restores its saved viewport (or fits everything once it has content);
    /// the same board keeps the view.
    func setClusters(_ new: [CanvasCluster], boardKey key: String?, savedViewport: (CGPoint, CGFloat)?) {
        let switched = key != boardKey
        // a slice of the library (search results, a filter) re-fits whenever its set of items changes
        let derivedChanged = key?.hasPrefix("derived:") == true && Set(new.flatMap(\.items)) != Set(clusters.flatMap(\.items))
        boardKey = key
        // where every tile is drawn right now, so a change to the same board can glide from there instead of redrawing
        let before = switched ? [:] : drawnGeometry()
        clusters = new
        applyLayout()
        if switched {
            for l in layers.values { recycle(l) }
            layers.removeAll()
            viewportDirty = false
            if let v = savedViewport { origin = v.0; scale = v.1; pendingFit = false } else { pendingFit = true }
        }
        if derivedChanged { pendingFit = true; viewportDirty = false }
        applyViewport()
        if !switched { glide(from: before) }
        fitIfPending()
        publishAccessibility()
    }

    private typealias Drawn = (position: CGPoint, bounds: CGRect)

    private func drawnGeometry() -> [String: Drawn] {
        var out: [String: Drawn] = [:]
        for (id, l) in layers { out[id] = (l.presentation()?.position ?? l.position, l.presentation()?.bounds ?? l.bounds) }
        return out
    }

    /// Tiles that were already on screen slide from where they were drawn to where the new layout puts them.
    private func glide(from before: [String: Drawn], duration: CFTimeInterval = Motion.flight) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (id, was) in before {
            guard let layer = layers[id], layer.superlayer != nil else { continue }
            if was.position == layer.position, was.bounds == layer.bounds { continue }
            for (key, from, to) in [("position", NSValue(point: was.position), NSValue(point: layer.position)), ("bounds", NSValue(rect: was.bounds), NSValue(rect: layer.bounds))] {
                let a = CABasicAnimation(keyPath: key)
                a.fromValue = from; a.toValue = to
                a.duration = duration
                a.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.25, 1)          // quick start, long soft landing
                layer.add(a, forKey: "flow-" + key)
            }
        }
        CATransaction.commit()
    }

    /// "Fit everything" is owed until there's both content and a real size; then it happens once, without animation.
    private func fitIfPending() {
        guard pendingFit, !entries.isEmpty, bounds.width > 10, bounds.height > 10 else { return }
        pendingFit = false
        fit(ids: nil, animated: false)
    }

    func setSelection(_ ids: Set<String>) {
        guard ids != selection else { return }
        selection = ids
        updateSelectionVisuals()
    }

    // MARK: Layout

    static func aspect(of s: ItemSummary?) -> Double {
        if let w = s?.width, let h = s?.height, w > 0, h > 0 { return Double(w) / Double(h) }
        return s?.kind == .link ? 4.0 / 3.0 : 1
    }

    private func members(of c: CanvasCluster) -> [String] { c.items.filter { items[$0] != nil } }

    private func pack(_ ids: [String], for c: CanvasCluster) -> ClusterLayout.Packed {
        ClusterLayout.pack(ids.map { .init(id: $0, aspect: Self.aspect(of: items[$0])) }, width: c.width, tile: c.tile)
    }

    /// The cluster's frame: as wide as its packed rows (a lone tile doesn't claim a whole row), at least wide enough for a title.
    private func frame(of c: CanvasCluster, packed: ClusterLayout.Packed) -> CGRect {
        let used = packed.rects.values.map { Double($0.maxX) }.max() ?? 0
        return CGRect(x: c.x, y: c.y, width: max(used, 320), height: ClusterLayout.headerHeight + packed.height)
    }

    /// Recomputes every item's rect and every cluster's frame from `clusters` and `items`.
    private func applyLayout() {
        var p: [String: CanvasPlacement] = [:]
        var frames: [String: CGRect] = [:]
        var owner: [String: String] = [:]
        for c in clusters {
            let ids = members(of: c)
            // a cluster with none of its items in this view (a filter, the Trash, another collection) isn't drawn at all
            if ids.isEmpty { continue }
            let packed = pack(ids, for: c)
            let ox = c.x, oy = c.y + ClusterLayout.headerHeight
            for id in ids {
                guard let r = packed.rects[id] else { continue }
                p[id] = CanvasPlacement(x: ox + r.minX, y: oy + r.minY, w: r.width, h: r.height, z: 0, at: 0)
                owner[id] = c.id
            }
            frames[c.id] = frame(of: c, packed: packed)
        }
        placements = p; clusterFrames = frames; memberOf = owner
        rebuildEntries()
        syncHeaders()
    }

    private func rebuildEntries() {
        var out: [Entry] = []
        out.reserveCapacity(placements.count)
        for c in clusters {
            for id in c.items { if let p = placements[id] { out.append(Entry(id: id, rect: CGRect(x: p.x, y: p.y, width: p.w, height: p.h), z: 0)) } }
        }
        entries = out
        refreshDust()
    }

    private func syncHeaders() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let live = Set(clusterFrames.keys)
        for (id, h) in headers where !live.contains(id) { h.removeFromSuperlayer(); headers[id] = nil }
        for c in clusters where live.contains(c.id) {
            let h = headers[c.id] ?? { let n = ClusterHeaderLayer(); content.addSublayer(n); headers[c.id] = n; return n }()
            h.contentsScale = backing
            h.isHidden = !editable || renaming?.id == c.id
            h.configure(title: c.title, count: members(of: c).count)
        }
        if let r = renaming, !live.contains(r.id) { r.field.finish(commit: false) }
        updateHeaderGeometry()
        CATransaction.commit()
    }

    // MARK: Renaming a cluster in place

    private var renaming: (id: String, field: InlineTitleField)?

    /// Double-clicking a cluster's name edits it right there.
    func beginRename(_ id: String) {
        guard editable, let c = clusters.first(where: { $0.id == id }), clusterFrames[id] != nil else { return }
        renaming?.field.finish(commit: true)
        let field = InlineTitleField(text: c.title, font: .systemFont(ofSize: 14, weight: .semibold))
        field.onFinish = { [weak self] text in
            guard let self else { return }
            self.renaming = nil
            self.headers[id]?.isHidden = !self.editable
            self.window?.makeFirstResponder(self)
            if let text, text.trimmingCharacters(in: .whitespaces) != c.title { self.onRenameClusterTo?(id, text) }
        }
        renaming = (id, field)
        headers[id]?.isHidden = true
        field.begin(in: self, frame: renameFrame(for: id))
    }

    /// Where the name sits on screen: just above the cluster's pictures, at a fixed size at every zoom.
    private func renameFrame(for id: String) -> NSRect {
        guard let f = clusterFrames[id] else { return .zero }
        let s = screenPoint(CGPoint(x: f.minX, y: f.minY + ClusterLayout.headerHeight))
        return NSRect(x: s.x - 5, y: s.y + 8, width: max(f.width * scale, 220) - 30, height: 22)
    }

    /// Title bars keep the same size on screen at every zoom, like Figma's frame names: each header is laid out in screen
    /// points and scaled by 1/zoom, pinned just above its cluster's pictures.
    private func updateHeaderGeometry() {
        let inv = 1 / max(scale, 0.0001)
        for c in clusters {
            guard let f = clusterFrames[c.id], let h = headers[c.id] else { continue }
            let widthPx = max(f.width * scale, 220)                 // a narrow cluster's name still has room
            h.anchorPoint = .zero
            h.bounds = CGRect(x: 0, y: 0, width: widthPx, height: ClusterHeaderLayer.heightPx)
            h.position = CGPoint(x: f.minX, y: -(f.minY + ClusterLayout.headerHeight) + 7 * inv)
            h.setAffineTransform(CGAffineTransform(scaleX: inv, y: inv))
            h.showsGrip = f.width * scale >= 140
        }
        if let r = renaming { r.field.frame = renameFrame(for: r.id) }
    }

    /// On big boards, every item gets a flat placeholder rectangle in one world-space layer underneath the real tiles.
    /// Zooming only transforms it (no redraw); it also stands in for tiles whose own layer hasn't been created yet.
    private func refreshDust() {
        guard entries.count > 500 else { dust.isHidden = true; dust.rects = []; return }
        dust.isHidden = false
        dust.color = NSColor.ink(.fill).cgColor
        dust.setWorldRects(entries.map(\.rect), contentsScale: backing)
    }

    // MARK: Coordinates

    func worldPoint(_ p: CGPoint) -> CGPoint {
        CGPoint(x: origin.x + p.x / scale, y: origin.y + (bounds.height - p.y) / scale)
    }

    func screenPoint(_ w: CGPoint) -> CGPoint {
        CGPoint(x: (w.x - origin.x) * scale, y: bounds.height - (w.y - origin.y) * scale)
    }

    /// Screen rect (view coordinates, y up) of a world rect (y down).
    func screenRect(_ r: CGRect) -> CGRect {
        CGRect(x: (r.minX - origin.x) * scale, y: bounds.height - (r.maxY - origin.y) * scale, width: r.width * scale, height: r.height * scale)
    }

    private var visibleWorld: CGRect {
        CGRect(x: origin.x, y: origin.y, width: bounds.width / scale, height: bounds.height / scale)
    }

    // MARK: Viewport

    private func applyViewport() {
        let t0 = CACurrentMediaTime()
        defer { HitchMonitor.record("applyViewport", since: t0) }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        content.setAffineTransform(CGAffineTransform(a: scale, b: 0, c: 0, d: scale, tx: -scale * origin.x, ty: bounds.height + scale * origin.y))
        updateHeaderGeometry()
        syncLayers()
        updateSelectionVisuals()
        CATransaction.commit()
        scheduleImageUpgrade()
        scheduleSettled()
    }

    func zoom(by factor: CGFloat, at screen: CGPoint) {
        viewportDirty = true
        let next = min(max(scale * factor, Self.minScale), Self.maxScale)
        guard next != scale else { return }
        let anchor = worldPoint(screen)
        scale = next
        origin = CGPoint(x: anchor.x - screen.x / scale, y: anchor.y - (bounds.height - screen.y) / scale)
        applyViewport()
    }

    func pan(byScreen dx: CGFloat, _ dy: CGFloat) {
        viewportDirty = true
        origin.x -= dx / scale
        origin.y -= dy / scale
        applyViewport()
    }

    /// An item's rectangle in window coordinates. Off screen, it is panned (not zoomed) to the middle first.
    func windowRect(ofItem id: String) -> CGRect? {
        guard let p = placements[id], bounds.width > 10 else { return nil }
        let world = CGRect(x: p.x, y: p.y, width: p.w, height: p.h)
        var r = screenRect(world)
        let area = CGRect(x: contentInsets.left, y: contentInsets.bottom, width: bounds.width - contentInsets.left - contentInsets.right, height: bounds.height - contentInsets.top - contentInsets.bottom)
        if !area.contains(r) {
            origin = CGPoint(x: world.midX - focus.x / scale, y: world.midY - focus.y / scale)
            viewportDirty = true
            applyViewport()
            r = screenRect(world)
        }
        return convert(r, to: nil)
    }

    func setItemHidden(_ id: String, _ hidden: Bool) { layers[id]?.opacity = hidden ? 0 : 1 }

    /// Brings `ids` (or everything) into view with a margin.
    func fit(ids: [String]?, animated: Bool, margin: CGFloat = 70) {
        let rects: [CGRect] = ids == nil
            ? Array(clusterFrames.values)
            : ids!.compactMap { placements[$0] }.map { CGRect(x: $0.x, y: $0.y, width: $0.w, height: $0.h) }
        guard let first = rects.first, bounds.width > 10, bounds.height > 10 else {
            if placements.isEmpty { origin = CGPoint(x: -60, y: -60); scale = 0.5; applyViewport() }
            return
        }
        let box = rects.dropFirst().reduce(first) { $0.union($1) }
        let availW = max(bounds.width - contentInsets.left - contentInsets.right, 50), availH = max(bounds.height - contentInsets.top - contentInsets.bottom, 50)
        let s = min(max(min((availW - 2 * margin) / max(box.width, 1), (availH - 2 * margin) / max(box.height, 1)), Self.minScale), 2)
        let o = CGPoint(x: box.midX - focus.x / s, y: box.midY - focus.y / s)
        viewportDirty = true
        if animated { animate(to: (o, s)) } else { origin = o; scale = s; applyViewport() }
    }

    func animate(to target: (CGPoint, CGFloat), duration: CFTimeInterval = Motion.flight) {
        animationLink?.invalidate()
        animation = (from: (origin, scale), to: target, start: CACurrentMediaTime(), duration: duration)
        let link = displayLink(target: self, selector: #selector(animationTick(_:)))
        link.add(to: .main, forMode: .common)
        animationLink = link
    }

    @objc private func animationTick(_ l: CADisplayLink) {
        guard let a = animation else { animationLink?.invalidate(); return }
        let t = min(1, (l.timestamp - a.start) / a.duration)
        let e = CGFloat(1 - pow(1 - t, 3))
        // interpolate the *centre* and log-scale so the motion looks like one smooth zoom
        let s0 = a.from.1, s1 = a.to.1
        let s = s0 * pow(s1 / s0, e)
        let f = focus
        let c0 = CGPoint(x: a.from.0.x + f.x / s0, y: a.from.0.y + f.y / s0)
        let c1 = CGPoint(x: a.to.0.x + f.x / s1, y: a.to.0.y + f.y / s1)
        let c = CGPoint(x: c0.x + (c1.x - c0.x) * e, y: c0.y + (c1.y - c0.y) * e)
        scale = s
        origin = CGPoint(x: c.x - f.x / s, y: c.y - f.y / s)
        applyViewport()
        if t >= 1 { animationLink?.invalidate(); animationLink = nil; animation = nil }
    }

    private func cancelAnimation() { animationLink?.invalidate(); animationLink = nil; animation = nil }

    private func scheduleSettled() {
        guard viewportDirty else { return }
        settleWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self, let key = self.boardKey else { return }
                self.onViewportSettled?(key, self.origin, self.scale)
            }
        }
        settleWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    // MARK: Layers

    /// New layers per frame. Zooming through a dense board can bring thousands of tiles into range at once; creating all
    /// of them in one frame stalls it, so the rest are drawn as placeholders and filled in over the next few frames.
    private let layerBudgetPerFrame = 90
    private var pool: [CanvasItemLayer] = []
    private var followUpScheduled = false

    private func syncLayers() {
        let t0 = CACurrentMediaTime()
        defer { HitchMonitor.record("syncLayers", since: t0) }
        let vis = visibleWorld.insetBy(dx: -40 / scale, dy: -40 / scale)
        var wanted: [Entry] = []
        for e in entries where e.rect.intersects(vis) && max(e.rect.width, e.rect.height) * scale >= minLayerPixels { wanted.append(e) }
        if wanted.count > layerCap {
            wanted.sort { max($0.rect.width, $0.rect.height) > max($1.rect.width, $1.rect.height) }
            wanted = Array(wanted[..<layerCap])
        }
        var keep = Set<String>()
        var created = 0
        var deferred = false
        for e in wanted {
            let existing = layers[e.id]
            if existing == nil, created >= layerBudgetPerFrame {
                deferred = true                            // shows its dust placeholder now; gets a layer on a following frame
                continue
            }
            keep.insert(e.id)
            let l = existing ?? makeLayer(for: e.id)
            if existing == nil { created += 1 }
            l.frame = CGRect(x: e.rect.minX, y: -e.rect.maxY, width: e.rect.width, height: e.rect.height)
            l.zPosition = CGFloat(e.z)
            if existing == nil { let t1 = CACurrentMediaTime(); loadImage(for: l, force: true); HitchMonitor.record("loadImage", since: t1) }
        }
        for (id, l) in layers where !keep.contains(id) { recycle(l); layers[id] = nil }
        for (id, l) in layers where selection.contains(id) { l.setSelected(true, scale: scale) }
        if deferred, !followUpScheduled {
            followUpScheduled = true
            DispatchQueue.main.async { [weak self] in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.followUpScheduled = false
                    CATransaction.begin(); CATransaction.setDisableActions(true)
                    self.syncLayers()
                    CATransaction.commit()
                }
            }
        }
    }

    private func makeLayer(for id: String) -> CanvasItemLayer {
        let t0 = CACurrentMediaTime()
        defer { HitchMonitor.record("makeLayer", since: t0) }
        let l = pool.popLast() ?? {
            let n = CanvasItemLayer()
            n.cornerRadius = 0
            return n
        }()
        l.contentsScale = backing
        l.summary = items[id]
        if l.superlayer == nil { content.addSublayer(l) }
        layers[id] = l
        return l
    }

    /// Takes a layer off the board and keeps it for reuse (allocating thousands of CALayers per zoom is what stalls).
    private func recycle(_ l: CanvasItemLayer) {
        l.removeFromSuperlayer()
        l.loadOperation?.cancel()
        l.summary = nil
        l.contents = nil
        l.borderWidth = 0
        l.showsTitleCard = false
        if pool.count < 600 { pool.append(l) }
    }

    // MARK: Images (level of detail)

    private func pixelsNeeded(_ l: CanvasItemLayer) -> CGFloat { max(l.bounds.width, l.bounds.height) * scale * backing }

    private func loadImage(for l: CanvasItemLayer, force: Bool) {
        guard let s = l.summary, let layout else { return }
        let isLink = s.kind == .link
        let mode = s.linkDisplay ?? "title"
        l.showsTitleCard = isLink && mode == "title"
        guard !l.showsTitleCard else { l.contents = nil; return }
        let variant = isLink ? mode : ""
        let needed = pixelsNeeded(l)
        let bucket = ThumbnailLoader.bucket(forPixels: needed)
        if !force, l.loadedBucket >= bucket { return }
        if let hit = ThumbnailLoader.shared.cached(id: s.id, pixels: needed, variant: variant) {
            l.contents = hit
            l.loadedBucket = max(l.loadedBucket, bucket)
            return
        }
        guard l.pendingBucket < bucket else { return }
        l.pendingBucket = bucket
        // The original file is only worth touching for large decodes; checking whether it's a sync placeholder is a
        // filesystem call, so it isn't done for the small thumbnails that make up nearly every tile.
        let original = (isLink || bucket <= 512) ? nil : model_originalURL(s)
        let cloud = original.map { FileAvailability.of($0) == .cloudOnly } ?? false
        let pictureURL = isLink && mode == "snapshot" ? layout.snapshotURL(s.id) : layout.thumbURL(s.id)
        let id = s.id
        l.loadOperation?.cancel()
        l.loadOperation = ThumbnailLoader.shared.load(id: id, thumb: pictureURL, original: cloud ? nil : original, pixels: needed, variant: variant) { [weak self] image in
            MainActor.assumeIsolated {
                guard let self, let l = self.layers[id], l.summary?.id == id, let image else { return }
                CATransaction.begin(); CATransaction.setDisableActions(true)
                l.contents = image
                CATransaction.commit()
                l.loadedBucket = max(l.loadedBucket, bucket)
            }
        }
    }

    private func model_originalURL(_ s: ItemSummary) -> URL? {
        guard let layout else { return nil }
        return layout.itemDir(s.id).appendingPathComponent(s.ext.map { "original.\($0)" } ?? "original")
    }

    /// After a zoom settles, sharpen what's visible; while zooming, the layers just scale what they have.
    private func scheduleImageUpgrade() {
        imageUpgradeWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.layers.values.forEach { self?.loadImage(for: $0, force: false) } }
        }
        imageUpgradeWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: work)
    }

    // MARK: Selection visuals

    private func updateSelectionVisuals() {
        for (id, l) in layers { l.setSelected(selection.contains(id), scale: scale) }
        let boxes = selection.compactMap { placements[$0] }.map { CGRect(x: $0.x, y: $0.y, width: $0.w, height: $0.h) }
        guard let first = boxes.first, boxes.count > 1 else { overlay.path = nil; return }
        let world = boxes.dropFirst().reduce(first) { $0.union($1) }
        overlay.path = CGPath(rect: screenRect(world).insetBy(dx: -3, dy: -3), transform: nil)
    }

    // MARK: Hit testing

    private func item(atWorld p: CGPoint) -> String? {
        for e in entries.reversed() where e.rect.contains(p) { return e.id }
        return nil
    }

    private enum HeaderHit { case title(String), grip(String) }

    /// The title bar of the cluster under `p`; its right end is the grip that resizes the cluster.
    private func headerHit(atWorld p: CGPoint) -> HeaderHit? {
        for c in clusters.reversed() {
            guard let f = clusterFrames[c.id] else { continue }
            // the label row sits just above the pictures; it is a fixed size on screen, so the grab area is too
            let top = f.minY + ClusterLayout.headerHeight
            let hitHeight = max(ClusterLayout.headerHeight, 34 / scale)
            let bar = CGRect(x: f.minX, y: top - hitHeight, width: max(f.width, 220 / scale), height: hitHeight)
            guard bar.contains(p) else { continue }
            let grip = 30 / scale
            return f.width * scale >= 140 && p.x > f.maxX - grip ? .grip(c.id) : .title(c.id)
        }
        return nil
    }

    private func clusterID(atWorld p: CGPoint) -> String? {
        clusters.last { clusterFrames[$0.id]?.contains(p) == true }?.id
    }

    // MARK: Mouse

    private func trace(_ text: String) {
        guard ProcessInfo.processInfo.environment["GRAILS_TRACE"] != nil, let h = FileHandle(forWritingAtPath: "/private/tmp/grails-actions.log") else { return }
        h.seekToEndOfFile(); h.write(Data((text + "\n").utf8)); try? h.close()
    }

    override func mouseDown(with event: NSEvent) {
        trace("canvas mouseDown clicks=\(event.clickCount) loc=\(convert(event.locationInWindow, from: nil)) flags=\(event.modifierFlags.rawValue)")
        window?.makeFirstResponder(self)
        cancelAnimation()
        let loc = convert(event.locationInWindow, from: nil)
        spaceUsedForPan = spaceHeld
        if spaceHeld { startPan(loc); return }
        let w = worldPoint(loc)

        if editable, let hit = headerHit(atWorld: w) {
            switch hit {
            case .title(let id):
                if event.clickCount == 2 { beginRename(id); return }
                if !selection.isEmpty { selection = []; notifySelection(); updateSelectionVisuals() }
                drag = .cluster(BlockDrag(id: id, startWorld: w, startScreen: loc, baseClusters: clusters))
            case .grip(let id):
                drag = .clusterWidth(BlockDrag(id: id, startWorld: w, startScreen: loc, baseClusters: clusters))
                NSCursor.resizeLeftRight.set()
            }
            return
        }

        if let id = item(atWorld: w) {
            if event.modifierFlags.contains(.option), !event.modifierFlags.contains(.command) { onOptionClick?(id); return }
            if event.modifierFlags.contains(.shift) {
                var s = selection
                if s.contains(id) { s.remove(id); selection = s; notifySelection(); updateSelectionVisuals(); return }
                s.insert(id)
                selection = s
            } else if !selection.contains(id) {
                selection = [id]
            }
            notifySelection()
            updateSelectionVisuals()
            if event.clickCount == 2 { onPreview?(id); return }
            let ids = entries.filter { selection.contains($0.id) }.map(\.id)       // reading order
            guard editable else { return }
            drag = .items(ItemDrag(ids: ids, startWorld: w, startScreen: loc, baseClusters: clusters, baseFrames: clusterFrames, basePlacements: placements))
        } else {
            let base: Set<String> = event.modifierFlags.contains(.shift) ? selection : []
            if !event.modifierFlags.contains(.shift), !selection.isEmpty { selection = []; notifySelection(); updateSelectionVisuals() }
            drag = .marquee(start: loc, base: base)
        }
    }

    private func startPan(_ loc: CGPoint) {
        drag = .pan(start: loc, originAtStart: origin)
        NSCursor.closedHand.set()
    }

    override func mouseDragged(with event: NSEvent) {
        let loc = convert(event.locationInWindow, from: nil)
        trace("canvas mouseDragged loc=\(loc)")
        switch drag {
        case .pan(let start, let o)?:
            viewportDirty = true
            origin = CGPoint(x: o.x - (loc.x - start.x) / scale, y: o.y + (loc.y - start.y) / scale)
            applyViewport()
        case .items(let d)?:
            if !d.lifted {
                guard hypot(loc.x - d.startScreen.x, loc.y - d.startScreen.y) > 4 else { return }
                d.lifted = true
                NSCursor.closedHand.set()
            }
            updateItemDrag(d, world: worldPoint(loc), forceNew: event.modifierFlags.contains(.option))
        case .cluster(let d)?:
            if !d.moved {
                guard hypot(loc.x - d.startScreen.x, loc.y - d.startScreen.y) > 4 else { return }
                d.moved = true
            }
            let w = worldPoint(loc)
            var next = d.baseClusters
            guard let i = next.firstIndex(where: { $0.id == d.id }) else { return }
            let dx = w.x - d.startWorld.x, dy = w.y - d.startWorld.y
            next[i].x = d.startX + dx; next[i].y = d.startY + dy
            if !event.modifierFlags.contains(.option) { next = resolveBlocks(next, moved: [d.id], hint: (Double(dx), Double(dy))) }
            showClusters(next)
        case .clusterWidth(let d)?:
            if !d.moved {
                guard hypot(loc.x - d.startScreen.x, loc.y - d.startScreen.y) > 3 else { return }
                d.moved = true
            }
            var next = d.baseClusters
            guard let i = next.firstIndex(where: { $0.id == d.id }) else { return }
            next[i].width = max(ClusterLayout.minWidth, d.startWidth + (worldPoint(loc).x - d.startWorld.x))
            showClusters(next)
        case .marquee(let start, let base)?:
            let rect = CGRect(x: min(start.x, loc.x), y: min(start.y, loc.y), width: abs(loc.x - start.x), height: abs(loc.y - start.y))
            marqueeLayer.path = CGPath(rect: rect, transform: nil)
            let hit = Set(entries.filter { screenRect($0.rect).intersects(rect) }.map(\.id))
            let next = base.union(hit)
            if next != selection { selection = next; updateSelectionVisuals() }
        case nil:
            break
        }
    }

    override func mouseUp(with event: NSEvent) {
        trace("canvas mouseUp")
        defer { drag = nil; marqueeLayer.path = nil; dropOutline.isHidden = true; if spaceHeld { NSCursor.openHand.set() } else { NSCursor.arrow.set() } }
        switch drag {
        case .items(let d)?:
            if d.lifted { finishItemDrag(d) } else { notifySelection() }
        case .cluster(let d)?:
            if d.moved { onCommitClusters?(clusters, "Move Cluster") }
        case .clusterWidth(let d)?:
            if d.moved {
                let next = resolveBlocks(clusters, moved: [d.id])
                onCommitClusters?(next, "Resize Cluster")
            }
        case .marquee?:
            notifySelection()
        default:
            break
        }
    }

    override func otherMouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        cancelAnimation()
        startPan(convert(event.locationInWindow, from: nil))
    }
    override func otherMouseDragged(with event: NSEvent) { mouseDragged(with: event) }
    override func otherMouseUp(with event: NSEvent) { mouseUp(with: event) }

    /// Shows `next` right now (no animation) and keeps it as the working state, e.g. while a cluster is dragged.
    private func showClusters(_ next: [CanvasCluster]) {
        clusters = next
        applyLayout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        syncLayers()
        updateSelectionVisuals()
        CATransaction.commit()
    }

    /// Pushes other cluster blocks out of the way of `moved`, so blocks never overlap.
    private func resolveBlocks(_ cs: [CanvasCluster], moved: Set<String>, hint: (Double, Double) = (0, 0)) -> [CanvasCluster] {
        guard !moved.isEmpty, pushEnabled() else { return cs }
        var board: [String: CanvasPlacement] = [:]
        for c in cs {
            let ids = members(of: c)
            if ids.isEmpty { continue }
            let f = frame(of: c, packed: pack(ids, for: c))
            board[c.id] = CanvasPlacement(x: f.minX, y: f.minY, w: f.width, h: f.height)
        }
        let out = CanvasReflow.resolve(moved: moved, in: board, hint: hint, gap: 160)
        guard !out.isEmpty else { return cs }
        let now = Date().timeIntervalSince1970
        return cs.map { c in
            guard let p = out[c.id] else { return c }
            var c = c; c.x = p.x; c.y = p.y; c.at = now
            return c
        }
    }

    // MARK: Dragging items

    private func entry(_ id: String) -> ClusterLayout.Entry { .init(id: id, aspect: Self.aspect(of: items[id])) }

    /// While items are carried: they follow the pointer, and the cluster under it opens a slot at the pointer while the
    /// others flow around it. Over empty canvas (or with ⌥ held) they would start a new cluster there.
    private func updateItemDrag(_ d: ItemDrag, world w: CGPoint, forceNew: Bool) {
        let dx = w.x - d.startWorld.x, dy = w.y - d.startWorld.y
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for id in d.ids {
            guard let p = d.basePlacements[id], let l = layers[id] else { continue }
            l.frame = CGRect(x: p.x + dx, y: -(p.y + dy) - p.h, width: p.w, height: p.h)
            l.zPosition = 10_000
        }
        CATransaction.commit()

        let carried = Set(d.ids)
        var target: ClusterOps.Target
        var key: String
        var outline: CGRect
        if !forceNew, let host = d.baseClusters.last(where: { d.baseFrames[$0.id]?.contains(w) == true }) {
            let restVisible = members(of: host).filter { !carried.contains($0) }
            let packed = ClusterLayout.pack(restVisible.map(entry), width: host.width, tile: host.tile)
            let local = CGPoint(x: w.x - host.x, y: w.y - (host.y + ClusterLayout.headerHeight))
            let visibleIndex = ClusterLayout.insertionIndex(of: local, packed: packed, order: restVisible)
            // translate "slot among visible members" into an index in the full member list (hidden members stay put)
            let full = host.items.filter { !carried.contains($0) }
            let index: Int
            if visibleIndex < restVisible.count { index = full.firstIndex(of: restVisible[visibleIndex]) ?? full.count }
            else { index = restVisible.last.flatMap { full.firstIndex(of: $0) }.map { $0 + 1 } ?? full.count }
            target = .cluster(host.id, index: index)
            key = "c:\(host.id):\(index)"
            // just the pictures: the title bar stays outside the outline
            let frame = d.baseFrames[host.id] ?? .zero
            outline = CGRect(x: frame.minX, y: frame.minY + ClusterLayout.headerHeight, width: frame.width, height: max(frame.height - ClusterLayout.headerHeight, 1))
            d.targetID = host.id
        } else {
            let tile = d.baseClusters.first { $0.items.contains(where: carried.contains) }?.tile ?? CanvasCluster.defaultTile
            // the new cluster's first tile lands exactly where the carried one is
            let lead = d.ids.first.flatMap { d.basePlacements[$0] }
            let x = (lead?.x ?? w.x - 60) + dx, y = (lead?.y ?? w.y - 60) + dy - ClusterLayout.headerHeight
            target = .newCluster(x: x, y: y, width: tile * 4.5, tile: tile)
            key = "n"
            outline = CGRect(x: x, y: y + ClusterLayout.headerHeight, width: lead?.w ?? tile, height: lead?.h ?? tile)      // where the first tile lands
            d.targetID = nil
        }
        // the outline of where it would land follows the pointer when making a new cluster
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        dropOutline.isHidden = false
        // fine, screen-sized dots that stay the same at every zoom, hugging the pictures with a small radius
        let px = 1 / max(scale, 0.0001)
        let box = outline.insetBy(dx: -3 * px, dy: -3 * px)
        dropOutline.lineWidth = 1 * px
        dropOutline.lineCap = .round
        dropOutline.lineDashPattern = [NSNumber(value: 0.1 * px), NSNumber(value: 3.2 * px)]      // round caps turn the dashes into dots
        dropOutline.path = CGPath(roundedRect: CGRect(x: box.minX, y: -box.maxY, width: box.width, height: box.height),
                                  cornerWidth: min(5 * px, box.width / 2), cornerHeight: min(5 * px, box.height / 2), transform: nil)
        CATransaction.commit()

        if key == "n" {
            // a new cluster follows the pointer: its position is part of the result, but nothing else moves, so only the
            // result is refreshed (the layout preview is the same wherever it lands)
            let first = d.resultKey != "n"
            d.result = ClusterOps.move(d.ids, to: target, in: d.baseClusters)
            d.resultKey = "n"
            if first { previewLayout(d) }
            return
        }
        guard key != d.resultKey else { return }
        d.resultKey = key
        d.result = ClusterOps.move(d.ids, to: target, in: d.baseClusters)
        previewLayout(d)
    }

    /// Lets everything that isn't being carried glide to where the new arrangement would put it.
    private func previewLayout(_ d: ItemDrag) {
        let carried = Set(d.ids)
        var goal: [String: CGRect] = [:]
        for c in d.result {
            if let base = d.baseClusters.first(where: { $0.id == c.id }), base.items == c.items, base.x == c.x, base.y == c.y { continue }
            let ids = members(of: c)
            let packed = pack(ids, for: c)
            let ox = c.x, oy = c.y + ClusterLayout.headerHeight
            for id in ids where !carried.contains(id) {
                if let r = packed.rects[id] { goal[id] = CGRect(x: ox + r.minX, y: oy + r.minY, width: r.width, height: r.height) }
            }
        }
        for id in d.previewed.subtracting(goal.keys) {          // earlier preview moved it, this one doesn't: back home
            if let p = d.basePlacements[id] { goal[id] = CGRect(x: p.x, y: p.y, width: p.w, height: p.h) }
        }
        d.previewed = Set(goal.keys)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (id, r) in goal {
            guard let layer = layers[id] else { continue }
            let fromPosition = layer.presentation()?.position ?? layer.position, fromBounds = layer.presentation()?.bounds ?? layer.bounds
            layer.frame = CGRect(x: r.minX, y: -r.maxY, width: r.width, height: r.height)
            for (key, from, to) in [("position", NSValue(point: fromPosition), NSValue(point: layer.position)), ("bounds", NSValue(rect: fromBounds), NSValue(rect: layer.bounds))] {
                let a = CABasicAnimation(keyPath: key)
                a.fromValue = from; a.toValue = to
                a.duration = 0.22
                a.timingFunction = CAMediaTimingFunction(name: .easeOut)
                layer.add(a, forKey: "flow-" + key)
            }
        }
        CATransaction.commit()
    }

    private func finishItemDrag(_ d: ItemDrag) {
        guard d.resultKey != "" else { restoreAfterDrag(); return }
        var final = d.result
        let unchanged = final.count == d.baseClusters.count && zip(final, d.baseClusters).allSatisfy { $0.items == $1.items && $0.id == $1.id }
        if unchanged { restoreAfterDrag(); return }
        // clusters that gained items (or are new) may now overlap a neighbour
        let grew = Set(final.filter { c in (d.baseClusters.first { $0.id == c.id }.map { c.items.count > $0.items.count }) ?? true }.map(\.id))
        final = resolveBlocks(final, moved: grew)
        selection = Set(d.ids)
        onCommitClusters?(final, d.ids.count > 1 ? "Move \(d.ids.count) Items" : "Move Item")
    }

    /// Puts every layer back where the layout says it belongs.
    private func restoreAfterDrag() {
        let before = drawnGeometry()
        applyLayout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        syncLayers()
        for l in layers.values { l.zPosition = 0 }
        updateSelectionVisuals()
        CATransaction.commit()
        glide(from: before)
    }

    /// Esc during a drag puts everything back.
    private func cancelDrag() {
        switch drag {
        case .cluster(let d)?, .clusterWidth(let d)?: clusters = d.baseClusters
        case .items(let d)?: clusters = d.baseClusters
        default: break
        }
        drag = nil
        dropOutline.isHidden = true
        marqueeLayer.path = nil
        restoreAfterDrag()
    }

    // MARK: Cluster commands (the app calls these)

    /// ⌘G: the selected items become a new cluster beside the one they came from.
    func groupSelection() {
        let ids = entries.filter { selection.contains($0.id) }.map(\.id)
        guard let first = ids.first else { return }
        let hostID = memberOf[first]
        let host = clusters.first { $0.id == hostID }
        let hostFrame = hostID.flatMap { clusterFrames[$0] } ?? .zero
        let tile = host?.tile ?? CanvasCluster.defaultTile
        var next = ClusterOps.move(ids, to: .newCluster(x: Double(hostFrame.maxX) + 200, y: Double(hostFrame.minY), width: tile * 4.5, tile: tile), in: clusters)
        if let new = next.last { next = resolveBlocks(next, moved: [new.id]) }
        onCommitClusters?(next, "Group into Cluster")
    }

    /// Arranges the cluster blocks into tidy rows.
    func tidyClusters() {
        let shown = clusters.filter { clusterFrames[$0.id] != nil }
        guard !shown.isEmpty else { return }
        var heights: [String: Double] = [:]
        for c in shown { heights[c.id] = Double(clusterFrames[c.id]?.height ?? CGFloat(ClusterLayout.headerHeight)) }
        let spots = ClusterOps.tidy(shown, heights: heights)
        let now = Date().timeIntervalSince1970
        let next = clusters.map { c -> CanvasCluster in
            var c = c
            if let s = spots[c.id] { c.x = s.x; c.y = s.y; c.at = now }
            return c
        }
        onCommitClusters?(next, "Tidy Clusters")
    }

    /// ← / → move the selected items one place within their cluster.
    private func reorderSelection(by step: Int) {
        let ids = entries.filter { selection.contains($0.id) }.map(\.id)
        guard let first = ids.first, let cid = memberOf[first], ids.allSatisfy({ memberOf[$0] == cid }),
              let c = clusters.first(where: { $0.id == cid }), let at = c.items.firstIndex(of: first) else { return }
        let rest = c.items.filter { !ids.contains($0) }
        let index = min(max(at + step, 0), rest.count)
        let next = ClusterOps.move(ids, to: .cluster(cid, index: index), in: clusters)
        guard next != clusters else { return }
        onCommitClusters?(next, "Reorder")
    }

    private func notifySelection() { onSelectionChange?(selection) }

    // MARK: Scroll, zoom, gestures

    override func scrollWheel(with event: NSEvent) {
        cancelAnimation()
        if event.modifierFlags.contains(.command) || event.modifierFlags.contains(.control) {
            zoom(by: exp(event.scrollingDeltaY * (event.hasPreciseScrollingDeltas ? 0.006 : 0.03)), at: convert(event.locationInWindow, from: nil))
        } else {
            pan(byScreen: event.scrollingDeltaX, event.scrollingDeltaY)
        }
    }

    override func magnify(with event: NSEvent) {
        cancelAnimation()
        zoom(by: 1 + event.magnification, at: convert(event.locationInWindow, from: nil))
    }

    /// Two-finger double tap: zoom to the item under the pointer, or back out to everything.
    override func smartMagnify(with event: NSEvent) {
        let w = worldPoint(convert(event.locationInWindow, from: nil))
        if let id = item(atWorld: w), selection != [id] || scale < 1.2 { fit(ids: [id], animated: true, margin: 90) }
        else { fit(ids: nil, animated: true) }
    }

    // MARK: Keys

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 49, !event.isARepeat, event.modifierFlags.intersection([.command, .control, .option]).isEmpty {
            spaceHeld = true
            spaceUsedForPan = false
            NSCursor.openHand.set()
            return
        }
        if event.keyCode == 49 { return }
        guard event.modifierFlags.intersection([.command, .control, .option]).isEmpty else { return super.keyDown(with: event) }
        if event.modifierFlags.intersection(Shortcut.mask).isEmpty, keyHandler?(event) == true { return }
        switch event.keyCode {
        case 44: onSearch?()
        case 53:
            if drag != nil { cancelDrag() }
            else if !selection.isEmpty { selection = []; notifySelection(); updateSelectionVisuals() }
        case 123: reorderSelection(by: -1)
        case 124: reorderSelection(by: 1)
        default:
            super.keyDown(with: event)
        }
    }

    override func keyUp(with event: NSEvent) {
        guard event.keyCode == 49 else { return super.keyUp(with: event) }
        let wasPan = spaceUsedForPan
        spaceHeld = false
        NSCursor.arrow.set()
        // a tap (no panning while held) previews the selection, like in the grid
        if !wasPan, let id = selection.first { onPreview?(id) }
    }

    override func selectAll(_ sender: Any?) {
        selection = Set(entries.map(\.id))
        notifySelection()
        updateSelectionVisuals()
    }

    @objc func paste(_ sender: Any?) { onPaste?() }

    override func menu(for event: NSEvent) -> NSMenu? {
        let w = worldPoint(convert(event.locationInWindow, from: nil))
        window?.makeFirstResponder(self)
        if editable, let hit = headerHit(atWorld: w) {
            switch hit { case .title(let id), .grip(let id): return clusterMenuProvider?(id) }
        }
        guard let id = item(atWorld: w) else { return nil }
        if !selection.contains(id) { selection = [id]; notifySelection(); updateSelectionVisuals() }
        return contextMenuProvider?(id)
    }

    // MARK: Dev benchmark (GRAILS_BENCH=1): zoom in and out, then pan in circles, while a hitch monitor counts slow frames

    private var benchLink: CADisplayLink?
    private var benchStart: CFTimeInterval = 0
    private var benchLast: CFTimeInterval = 0
    private weak var benchHitch: HitchMonitor?

    func startBenchmark(hitch: HitchMonitor?) {
        guard benchLink == nil, !entries.isEmpty else { return }
        benchHitch = hitch
        benchStart = CACurrentMediaTime()
        benchLast = benchStart
        let link = displayLink(target: self, selector: #selector(benchTick(_:)))
        link.add(to: .main, forMode: .common)
        benchLink = link
    }

    @objc private func benchTick(_ l: CADisplayLink) {
        let t = l.timestamp - benchStart
        let dt = l.timestamp - benchLast
        benchLast = l.timestamp
        benchHitch?.noteActivity()
        let centre = CGPoint(x: bounds.midX, y: bounds.midY)
        if t < 8 {
            benchHitch?.setPhase("1-zoom")
            let dir: CGFloat = Int(t / 2) % 2 == 0 ? 1 : -1
            zoom(by: pow(2.4, dir * CGFloat(dt)), at: centre)
        } else if t < 16 {
            benchHitch?.setPhase("2-pan")
            let a = (t - 8) * 1.2
            origin.x += cos(a) * 1400 * CGFloat(dt) / scale
            origin.y += sin(a) * 1400 * CGFloat(dt) / scale
            applyViewport()
        } else {
            benchLink?.invalidate()
            benchLink = nil
            benchHitch?.finish()
        }
    }

    // MARK: Accessibility (also lets UI tests find tiles)

    private func publishAccessibility() {
        axChildren = layers.values.prefix(150).compactMap { l in
            guard let s = l.summary else { return nil }
            let r = screenRect(CGRect(x: l.frame.minX, y: -l.frame.maxY, width: l.frame.width, height: l.frame.height))
            let el = CanvasAXElement()
            el.setAccessibilityRole(.image)
            el.setAccessibilityLabel(s.name)
            el.setAccessibilityParent(self)
            el.setAccessibilityFrameInParentSpace(r)
            el.setAccessibilitySelected(selection.contains(s.id))
            return el
        }
        NSAccessibility.post(element: self, notification: .layoutChanged)
    }

    /// Pointing at the canvas always lands on the canvas itself (tiles stay readable as children for screen readers).
    override func accessibilityHitTest(_ point: NSPoint) -> Any? { self }

    override func accessibilityChildren() -> [Any]? {
        // refresh lazily: frames change as the viewport moves
        publishAccessibilitySilently()
        return axChildren
    }

    private func publishAccessibilitySilently() {
        axChildren = layers.values.prefix(150).compactMap { l in
            guard let s = l.summary else { return nil }
            let r = screenRect(CGRect(x: l.frame.minX, y: -l.frame.maxY, width: l.frame.width, height: l.frame.height))
            let el = CanvasAXElement()
            el.setAccessibilityRole(.image)
            el.setAccessibilityLabel(s.name)
            el.setAccessibilityParent(self)
            el.setAccessibilityFrameInParentSpace(r)
            el.setAccessibilitySelected(selection.contains(s.id))
            return el
        }
    }

    override func accessibilityValue() -> Any? {
        var sel = "null"
        if let id = selection.sorted().first, let p = placements[id] {
            sel = "[\(Int(p.x.rounded())),\(Int(p.y.rounded())),\(Int(p.w.rounded())),\(Int(p.h.rounded())),\(p.z)]"
        }
        return "{\"scale\":\(String(format: "%.4f", scale)),\"ox\":\(Int(origin.x)),\"oy\":\(Int(origin.y)),\"placed\":\(placements.count),\"visible\":\(layers.count),\"selected\":\(selection.count),\"sel\":\(sel)}"
    }
}

final class CanvasAXElement: NSAccessibilityElement {}

/// One item on the board.
final class CanvasItemLayer: CALayer {
    var summary: ItemSummary? { didSet { if summary?.id != oldValue?.id || summary?.linkDisplay != oldValue?.linkDisplay { resetImageState() }; updateTitle() } }
    var loadedBucket = 0
    var pendingBucket = 0
    var loadOperation: Operation?
    var showsTitleCard = false { didSet { updateTitle() } }
    private var titleLayer: CATextLayer?

    override init() {
        super.init()
        masksToBounds = true
        cornerRadius = 0
        backgroundColor = NSColor.ink(.fill).cgColor
        contentsGravity = .resizeAspectFill
        magnificationFilter = .trilinear
        minificationFilter = .trilinear
        actions = ["contents": NSNull(), "position": NSNull(), "bounds": NSNull(), "borderWidth": NSNull(), "zPosition": NSNull(), "frame": NSNull()]
    }

    override init(layer: Any) { super.init(layer: layer) }
    required init?(coder: NSCoder) { fatalError() }

    private func resetImageState() {
        loadOperation?.cancel()
        loadedBucket = 0
        pendingBucket = 0
        contents = nil
    }

    private var selectedNow = false

    func setSelected(_ on: Bool, scale: CGFloat) {
        selectedNow = on
        borderWidth = on ? 2 / max(scale, 0.0001) : 0
        borderColor = NSColor.ink(.text).cgColor
    }

    /// After a light/dark switch: layers keep the colours they were given, so give them again.
    func restyle(scale: CGFloat) {
        backgroundColor = NSColor.ink(.fill).cgColor
        setSelected(selectedNow, scale: scale)
    }

    private func updateTitle() {
        guard showsTitleCard, let name = summary?.name else { titleLayer?.removeFromSuperlayer(); titleLayer = nil; return }
        let t = titleLayer ?? CATextLayer()
        t.string = name
        t.fontSize = 14
        t.alignmentMode = .center
        t.isWrapped = true
        t.truncationMode = .end
        t.foregroundColor = NSColor.ink(.text).cgColor
        t.contentsScale = contentsScale
        t.frame = bounds.insetBy(dx: 10, dy: bounds.height * 0.3)
        t.actions = ["position": NSNull(), "bounds": NSNull(), "contents": NSNull()]
        if titleLayer == nil { addSublayer(t); titleLayer = t }
    }

    override func layoutSublayers() {
        super.layoutSublayers()
        titleLayer?.frame = bounds.insetBy(dx: 10, dy: bounds.height * 0.3)
        titleLayer?.fontSize = max(10, min(bounds.height * 0.09, 28))
    }
}

/// Flat placeholders for every item on a big board, in world space under the real tiles. Redrawn only when the board
/// changes; zooming and panning just transform it.
final class DustLayer: CALayer {
    var rects: [CGRect] = []          // world rects, y down
    var color: CGColor = NSColor.tertiaryLabelColor.cgColor
    private var extent = CGRect.zero

    override init() {
        super.init()
        actions = ["contents": NSNull(), "position": NSNull(), "bounds": NSNull(), "hidden": NSNull()]
    }
    override init(layer: Any) { super.init(layer: layer) }
    required init?(coder: NSCoder) { fatalError() }

    func setWorldRects(_ r: [CGRect], contentsScale backing: CGFloat) {
        rects = r
        guard let first = r.first else { return }
        extent = r.dropFirst().reduce(first) { $0.union($1) }.insetBy(dx: -4, dy: -4)
        // keep the backing store within what the GPU accepts: ≤ 8192 pixels on a side
        let longest = max(extent.width, extent.height)
        let scale = min(backing, max(8192 / max(longest, 1), 0.02))
        CATransaction.begin(); CATransaction.setDisableActions(true)
        frame = CGRect(x: extent.minX, y: -extent.maxY, width: extent.width, height: extent.height)
        contentsScale = scale
        setNeedsDisplay()
        CATransaction.commit()
    }

    override func draw(in ctx: CGContext) {
        guard !rects.isEmpty else { return }
        ctx.setFillColor(color)
        // layer space is y up with its origin at the extent's bottom-left
        ctx.fill(rects.map { CGRect(x: $0.minX - extent.minX, y: extent.maxY - $0.maxY, width: $0.width, height: $0.height).insetBy(dx: 0.5, dy: 0.5) })
    }
}


/// The label above one cluster: its name (or a faint "Untitled"), how many items it holds, and a small grip at the right
/// end that resizes the cluster. Laid out in screen points; the canvas scales it by 1/zoom so it never changes size.
final class ClusterHeaderLayer: CALayer {
    static let heightPx: CGFloat = 24
    private let text = CATextLayer()
    private let grip = CAShapeLayer()
    var showsGrip = true { didSet { grip.isHidden = !showsGrip } }

    override init() {
        super.init()
        let none: [String: CAAction] = ["position": NSNull(), "bounds": NSNull(), "contents": NSNull(), "frame": NSNull(), "string": NSNull(), "path": NSNull(),
                                        "hidden": NSNull(), "transform": NSNull(), "anchorPoint": NSNull()]
        actions = none
        text.actions = none
        grip.actions = none
        text.truncationMode = .end
        text.alignmentMode = .left
        grip.fillColor = nil
        grip.strokeColor = NSColor.ink(.secondary).cgColor
        grip.lineWidth = 1.4
        grip.lineCap = .round
        grip.lineJoin = .round
        addSublayer(text)
        addSublayer(grip)
    }

    override init(layer: Any) { super.init(layer: layer) }
    required init?(coder: NSCoder) { fatalError() }

    func configure(title: String, count: Int) {
        let s = NSMutableAttributedString()
        s.append(NSAttributedString(string: title.isEmpty ? "Untitled" : title, attributes: [
            .font: NSFont.systemFont(ofSize: 14, weight: .semibold),
            .foregroundColor: NSColor.ink(title.isEmpty ? .secondary : .text),
        ]))
        s.append(NSAttributedString(string: "  \(count)", attributes: [
            .font: NSFont.systemFont(ofSize: 11, weight: .regular), .foregroundColor: NSColor.ink(.secondary),
        ]))
        text.string = s
        text.contentsScale = contentsScale
        setNeedsLayout()
    }

    override func layoutSublayers() {
        super.layoutSublayers()
        let w = bounds.width
        text.frame = CGRect(x: 1, y: 2, width: max(w - 30, 20), height: 20)
        grip.frame = CGRect(x: max(w - 24, 0), y: 4, width: 24, height: 16)
        let p = CGMutablePath()
        p.move(to: CGPoint(x: 4, y: 8)); p.addLine(to: CGPoint(x: 20, y: 8))
        p.move(to: CGPoint(x: 8, y: 4)); p.addLine(to: CGPoint(x: 4, y: 8)); p.addLine(to: CGPoint(x: 8, y: 12))
        p.move(to: CGPoint(x: 16, y: 4)); p.addLine(to: CGPoint(x: 20, y: 8)); p.addLine(to: CGPoint(x: 16, y: 12))
        grip.path = p
    }
}

// MARK: Dev demo (GRAILS_CANVAS_DEMO=<output dir>)
//
// Drives the canvas with synthetic events delivered straight to this view (never through the window server, so nothing else
// on the Mac can be touched) and renders it to PNGs after each step. For checking layout and drag behaviour by eye.

extension CanvasNSView {
    func runDemo(into dir: String, quit: Bool) {
        Task { @MainActor in
            try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            @MainActor func wait(_ s: Double) async { try? await Task.sleep(for: .seconds(s)) }
            @MainActor func snap(_ name: String) {
                let w = Int(bounds.width), h = Int(bounds.height)
                guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue), let root = layer else { return }
                CATransaction.flush()
                root.render(in: ctx)
                guard let cg = ctx.makeImage() else { return }
                let rep = NSBitmapImageRep(cgImage: cg)
                try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: "\(dir)/\(name).png"))
                print("DEMO: \(dir)/\(name).png clusters=\(clusters.map { "\($0.title.isEmpty ? "·" : $0.title):\($0.items.count)" })")
            }
            @MainActor func event(_ type: NSEvent.EventType, _ viewPoint: CGPoint, flags: NSEvent.ModifierFlags = [], clicks: Int = 1) -> NSEvent? {
                NSEvent.mouseEvent(with: type, location: convert(viewPoint, to: nil), modifierFlags: flags, timestamp: ProcessInfo.processInfo.systemUptime,
                                   windowNumber: window?.windowNumber ?? 0, context: nil, eventNumber: 0, clickCount: clicks, pressure: 1)
            }
            @MainActor func drag(from a: CGPoint, to b: CGPoint, hold: (() -> Void)? = nil) async {
                if let e = event(.leftMouseDown, a) { mouseDown(with: e) }
                for i in 1...12 {
                    let t = CGFloat(i) / 12
                    if let e = event(.leftMouseDragged, CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)) { mouseDragged(with: e) }
                    await wait(0.02)
                }
                await wait(0.35)
                hold?()
                if let e = event(.leftMouseUp, b) { mouseUp(with: e) }
                await wait(0.12)
                // is anything still travelling to its slot? (presentation = what is on screen, model = where it ends up)
                let travelling = layers.values.filter { l in
                    guard let p = l.presentation()?.position else { return false }
                    return abs(p.x - l.position.x) > 1 || abs(p.y - l.position.y) > 1
                }.count
                print("DEMO: \(travelling) tiles still gliding 0.12 s after the drop")
                await wait(0.8)
            }
            @MainActor func centre(of id: String) -> CGPoint? { placements[id].map { screenPoint(CGPoint(x: $0.x + $0.w / 2, y: $0.y + $0.h / 2)) } }

            await wait(2.0)
            fit(ids: nil, animated: false)
            zoom(by: 0.62, at: CGPoint(x: bounds.midX, y: bounds.midY))
            await wait(0.8)
            snap("1-packed")
            zoom(by: 0.3, at: CGPoint(x: bounds.midX, y: bounds.midY)); await wait(0.5); snap("1b-zoomed-out")
            zoom(by: 9, at: CGPoint(x: bounds.midX, y: bounds.midY)); await wait(0.5); snap("1c-zoomed-in")
            zoom(by: 1 / 2.7, at: CGPoint(x: bounds.midX, y: bounds.midY)); await wait(0.5)

            // 1. carry the second tile out onto empty canvas: a new cluster
            if let id = clusters.first?.items.dropFirst().first, let from = centre(of: id) {
                let to = CGPoint(x: bounds.maxX - 220, y: 160)
                await drag(from: from, to: to, hold: { snap("2-carrying-out") })
                snap("3-new-cluster")
            }
            // 2. carry a tile from the big cluster into the middle of the new one's row
            if clusters.count >= 2, let moving = clusters[0].items.dropFirst(3).first, let from = centre(of: moving),
               let target = clusters.last?.items.first, let to = centre(of: target) {
                await drag(from: from, to: CGPoint(x: to.x + 10, y: to.y), hold: { snap("4-carrying-in") })
                snap("5-joined")
            }
            // 3. move the new cluster's block by its title bar
            if let c = clusters.last, let f = clusterFrames[c.id] {
                let from = screenPoint(CGPoint(x: f.minX + 80, y: f.minY + ClusterLayout.headerHeight / 2))
                await drag(from: from, to: CGPoint(x: from.x - 120, y: from.y + 220))
                snap("6-moved-block")
            }
            if quit { NSApp.terminate(nil) }
        }
    }
}
