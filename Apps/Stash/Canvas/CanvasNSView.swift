import AppKit
import QuartzCore
import StashKit

/// An infinite, pannable, zoomable board where items sit wherever they were put.
///
/// World space: points, y down, origin anywhere. The viewport is `origin` (the world point at the view's top-left)
/// and `scale` (screen points per world point). Items are CALayers under one content layer whose affine transform
/// is the viewport, so panning and zooming only change a transform (GPU work) no matter how many items exist.
@MainActor
final class CanvasNSView: NSView {
    // MARK: Callbacks
    var onSelectionChange: ((Set<String>) -> Void)?
    /// Placements that changed, plus an undo label ("Move on Canvas", "Resize on Canvas", …).
    var onCommit: (([String: CanvasPlacement], String) -> Void)?
    var onPreview: ((String) -> Void)?
    var keyHandler: ((NSEvent) -> Bool)?
    var contextMenuProvider: ((String) -> NSMenu?)?
    var onPaste: (() -> Void)?
    var onViewportSettled: ((String, CGPoint, CGFloat) -> Void)?
    var onOptionClick: ((String) -> Void)?

    // MARK: Data
    var layout: LibraryLayout?
    private(set) var boardKey: String?
    private(set) var items: [String: ItemSummary] = [:]
    private(set) var placements: [String: CanvasPlacement] = [:]
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
    private let handles = CAShapeLayer()
    private let marqueeLayer = CAShapeLayer()
    private var layers: [String: CanvasItemLayer] = [:]
    private var entries: [Entry] = []          // every placed item, by z ascending
    private var imageUpgradeWork: DispatchWorkItem?
    private var settleWork: DispatchWorkItem?
    private var axChildren: [CanvasAXElement] = []
    /// Fit-everything is requested before the view has a size on first display; it runs once there is one.
    private var pendingFit = false
    /// Only a viewport the person (or a fit command) actually set is worth remembering.
    private var viewportDirty = false

    struct Entry { var id: String; var rect: CGRect; var z: Int }     // rect in world space, y down

    /// Beyond this many visible tiles, the smallest are drawn as dust instead of getting their own layer.
    private let layerCap = 1_200
    private let minLayerPixels: CGFloat = 5

    // MARK: Interaction state
    private enum Drag {
        case pan(start: CGPoint, originAtStart: CGPoint)
        case move(startWorld: CGPoint, starts: [String: CanvasPlacement], raised: Bool)
        case resize(handle: Handle, anchor: CGPoint, grab: CGPoint, starts: [String: CanvasPlacement])
        case marquee(start: CGPoint, base: Set<String>)
    }
    private enum Handle: CaseIterable { case topLeft, topRight, bottomLeft, bottomRight }
    private var drag: Drag?
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
        for l in [overlay, handles, marqueeLayer] { l.actions = ["path": NSNull(), "position": NSNull(), "bounds": NSNull(), "hidden": NSNull()]; layer?.addSublayer(l) }
        overlay.fillColor = nil
        overlay.lineWidth = 1.5
        handles.lineWidth = 1.5
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
            let accent = NSColor.controlAccentColor.cgColor
            overlay.strokeColor = accent
            handles.strokeColor = accent
            handles.fillColor = NSColor.white.cgColor
            marqueeLayer.strokeColor = accent
            marqueeLayer.fillColor = NSColor.controlAccentColor.withAlphaComponent(0.12).cgColor
            dust.color = NSColor.tertiaryLabelColor.cgColor
            layer?.backgroundColor = NSColor.underPageBackgroundColor.cgColor
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
        let s = backing
        for l in [overlay, handles, marqueeLayer] { l.contentsScale = s }
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        applyViewport()
        fitIfPending()
    }

    // MARK: Data in

    func setItems(_ list: [ItemSummary]) {
        items = Dictionary(list.map { ($0.id, $0) }, uniquingKeysWith: { _, new in new })
        rebuildEntries()
        for (id, l) in layers { if let s = items[id] { l.summary = s } }
        syncLayers()
        for l in layers.values where l.loadedBucket == 0 { loadImage(for: l, force: true) }
        publishAccessibility()
    }

    /// Replaces the board. A different board restores its saved viewport (or fits everything once it has content);
    /// the same board keeps the view.
    func setPlacements(_ new: [String: CanvasPlacement], boardKey key: String?, savedViewport: (CGPoint, CGFloat)?) {
        let switched = key != boardKey
        boardKey = key
        placements = new
        rebuildEntries()
        for l in layers.values { recycle(l) }
        layers.removeAll()
        if switched {
            viewportDirty = false
            if let v = savedViewport { origin = v.0; scale = v.1; pendingFit = false } else { pendingFit = true }
        }
        applyViewport()
        fitIfPending()
        publishAccessibility()
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

    private func rebuildEntries() {
        entries = placements.compactMap { id, p in
            items[id] == nil ? nil : Entry(id: id, rect: CGRect(x: p.x, y: p.y, width: p.w, height: p.h), z: p.z)
        }.sorted { ($0.z, $0.id) < ($1.z, $1.id) }
        refreshDust()
    }

    /// On big boards, every item gets a flat placeholder rectangle in one world-space layer underneath the real tiles.
    /// Zooming only transforms it (no redraw); it also stands in for tiles whose own layer hasn't been created yet.
    private func refreshDust() {
        guard entries.count > 500 else { dust.isHidden = true; dust.rects = []; return }
        dust.isHidden = false
        dust.color = NSColor.tertiaryLabelColor.cgColor
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

    /// Brings `ids` (or everything) into view with a margin.
    func fit(ids: [String]?, animated: Bool, margin: CGFloat = 70) {
        let rects = (ids ?? entries.map(\.id)).compactMap { placements[$0] }.map { CGRect(x: $0.x, y: $0.y, width: $0.w, height: $0.h) }
        guard let first = rects.first, bounds.width > 10, bounds.height > 10 else {
            if placements.isEmpty { origin = CGPoint(x: -60, y: -60); scale = 0.5; applyViewport() }
            return
        }
        let box = rects.dropFirst().reduce(first) { $0.union($1) }
        let s = min(max(min((bounds.width - 2 * margin) / max(box.width, 1), (bounds.height - 2 * margin) / max(box.height, 1)), Self.minScale), 2)
        let o = CGPoint(x: box.midX - bounds.width / (2 * s), y: box.midY - bounds.height / (2 * s))
        viewportDirty = true
        if animated { animate(to: (o, s)) } else { origin = o; scale = s; applyViewport() }
    }

    func animate(to target: (CGPoint, CGFloat), duration: CFTimeInterval = 0.3) {
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
        let c0 = CGPoint(x: a.from.0.x + bounds.width / (2 * s0), y: a.from.0.y + bounds.height / (2 * s0))
        let c1 = CGPoint(x: a.to.0.x + bounds.width / (2 * s1), y: a.to.0.y + bounds.height / (2 * s1))
        let c = CGPoint(x: c0.x + (c1.x - c0.x) * e, y: c0.y + (c1.y - c0.y) * e)
        scale = s
        origin = CGPoint(x: c.x - bounds.width / (2 * s), y: c.y - bounds.height / (2 * s))
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
            n.cornerRadius = 6
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
        guard let first = boxes.first else { overlay.path = nil; handles.path = nil; return }
        let world = boxes.dropFirst().reduce(first) { $0.union($1) }
        let r = screenRect(world).insetBy(dx: -3, dy: -3)
        overlay.path = CGPath(rect: r, transform: nil)
        let hp = CGMutablePath()
        for c in [CGPoint(x: r.minX, y: r.minY), CGPoint(x: r.maxX, y: r.minY), CGPoint(x: r.minX, y: r.maxY), CGPoint(x: r.maxX, y: r.maxY)] {
            hp.addRoundedRect(in: CGRect(x: c.x - 5, y: c.y - 5, width: 10, height: 10), cornerWidth: 2, cornerHeight: 2)
        }
        handles.path = hp
    }

    private func selectionBoundsWorld() -> CGRect? {
        let boxes = selection.compactMap { placements[$0] }.map { CGRect(x: $0.x, y: $0.y, width: $0.w, height: $0.h) }
        guard let first = boxes.first else { return nil }
        return boxes.dropFirst().reduce(first) { $0.union($1) }
    }

    private func handle(at screen: CGPoint) -> Handle? {
        guard let world = selectionBoundsWorld() else { return nil }
        let r = screenRect(world).insetBy(dx: -3, dy: -3)
        let corners: [(Handle, CGPoint)] = [(.topLeft, CGPoint(x: r.minX, y: r.maxY)), (.topRight, CGPoint(x: r.maxX, y: r.maxY)),
                                           (.bottomLeft, CGPoint(x: r.minX, y: r.minY)), (.bottomRight, CGPoint(x: r.maxX, y: r.minY))]
        // note: view space is y-up, so "top" corners have the larger y
        return corners.first { hypot($0.1.x - screen.x, $0.1.y - screen.y) <= 11 }?.0
    }

    private func worldCorner(_ h: Handle, of r: CGRect) -> CGPoint {
        switch h {
        case .topLeft: CGPoint(x: r.minX, y: r.minY)
        case .topRight: CGPoint(x: r.maxX, y: r.minY)
        case .bottomLeft: CGPoint(x: r.minX, y: r.maxY)
        case .bottomRight: CGPoint(x: r.maxX, y: r.maxY)
        }
    }

    private func opposite(_ h: Handle) -> Handle {
        switch h { case .topLeft: .bottomRight; case .topRight: .bottomLeft; case .bottomLeft: .topRight; case .bottomRight: .topLeft }
    }

    // MARK: Hit testing

    private func item(atWorld p: CGPoint) -> String? {
        for e in entries.reversed() where e.rect.contains(p) { return e.id }
        return nil
    }

    // MARK: Mouse

    private func trace(_ text: String) {
        guard ProcessInfo.processInfo.environment["STASH_TRACE"] != nil, let h = FileHandle(forWritingAtPath: "/private/tmp/stash-actions.log") else { return }
        h.seekToEndOfFile(); h.write(Data((text + "\n").utf8)); try? h.close()
    }

    override func mouseDown(with event: NSEvent) {
        trace("canvas mouseDown clicks=\(event.clickCount) loc=\(convert(event.locationInWindow, from: nil)) flags=\(event.modifierFlags.rawValue)")
        window?.makeFirstResponder(self)
        cancelAnimation()
        let loc = convert(event.locationInWindow, from: nil)
        spaceUsedForPan = spaceHeld
        if spaceHeld { startPan(loc); return }
        if let h = handle(at: loc), let box = selectionBoundsWorld() {
            let starts = Dictionary(uniqueKeysWithValues: selection.compactMap { id in placements[id].map { (id, $0) } })
            drag = .resize(handle: h, anchor: worldCorner(opposite(h), of: box), grab: worldCorner(h, of: box), starts: starts)
            return
        }
        let w = worldPoint(loc)
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
            let starts = Dictionary(uniqueKeysWithValues: selection.compactMap { sid in placements[sid].map { (sid, $0) } })
            drag = .move(startWorld: w, starts: starts, raised: false)
            raiseIfNeeded(id)
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

    /// Clicking an item brings it to the front.
    private func raiseIfNeeded(_ id: String) {
        guard var p = placements[id], let top = entries.last, top.id != id else { return }
        p.z = top.z + 1
        placements[id] = p
        rebuildEntries()
        layers[id]?.zPosition = CGFloat(p.z)
        if case .move(let w, let s, _) = drag { drag = .move(startWorld: w, starts: s, raised: true) }
    }

    override func mouseDragged(with event: NSEvent) {
        let loc = convert(event.locationInWindow, from: nil)
        trace("canvas mouseDragged loc=\(loc) drag=\(String(describing: drag).prefix(24))")
        switch drag {
        case .pan(let start, let o)?:
            viewportDirty = true
            origin = CGPoint(x: o.x - (loc.x - start.x) / scale, y: o.y + (loc.y - start.y) / scale)
            applyViewport()
        case .move(let startWorld, let starts, _)?:
            let w = worldPoint(loc)
            let dx = w.x - startWorld.x, dy = w.y - startWorld.y
            for (id, p) in starts { placements[id]?.x = p.x + dx; placements[id]?.y = p.y + dy }
            applyPlacementsToLayers(Array(starts.keys))
        case .resize(let h, let anchor, let grab, let starts)?:
            let w = worldPoint(loc)
            let vx = grab.x - anchor.x, vy = grab.y - anchor.y
            let denom = vx * vx + vy * vy
            guard denom > 0 else { return }
            var f = ((w.x - anchor.x) * vx + (w.y - anchor.y) * vy) / denom
            let smallest = starts.values.map { min($0.w, $0.h) }.min() ?? 1
            f = max(f, CanvasLayoutEngine.minSide / max(smallest, 1))
            for (id, p) in starts {
                placements[id]?.x = anchor.x + (p.x - anchor.x) * f
                placements[id]?.y = anchor.y + (p.y - anchor.y) * f
                placements[id]?.w = p.w * f
                placements[id]?.h = p.h * f
            }
            _ = h
            applyPlacementsToLayers(Array(starts.keys))
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
        defer { drag = nil; marqueeLayer.path = nil; if spaceHeld { NSCursor.openHand.set() } else { NSCursor.arrow.set() } }
        switch drag {
        case .move(_, let starts, _)?:
            var updates: [String: CanvasPlacement] = [:]
            var moved = false
            for (id, s) in starts {
                guard let p = placements[id], p != s else { continue }
                updates[id] = p
                if p.x != s.x || p.y != s.y { moved = true }
            }
            // A click that only brought an item to the front still changes stacking, which is worth keeping.
            if !updates.isEmpty { onCommit?(updates, moved ? "Move on Canvas" : "Bring to Front") }
            notifySelection()
            refreshDust()
        case .resize(_, _, _, let starts)?:
            var updates: [String: CanvasPlacement] = [:]
            for (id, s) in starts { if let p = placements[id], p != s { updates[id] = p } }
            if !updates.isEmpty { onCommit?(updates, "Resize on Canvas") }
            refreshDust()
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

    private func applyPlacementsToLayers(_ ids: [String]) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for id in ids {
            guard let p = placements[id] else { continue }
            layers[id]?.frame = CGRect(x: p.x, y: -p.maxY, width: p.w, height: p.h)
        }
        for i in entries.indices { if let p = placements[entries[i].id] { entries[i].rect = CGRect(x: p.x, y: p.y, width: p.w, height: p.h) } }
        updateSelectionVisuals()
        CATransaction.commit()
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
        case 53:
            if !selection.isEmpty { selection = []; notifySelection(); updateSelectionVisuals() }
        case 123, 124, 125, 126:
            let step = (event.modifierFlags.contains(.shift) ? 10.0 : 1.0) / scale
            let d: (CGFloat, CGFloat) = event.keyCode == 123 ? (-step, 0) : event.keyCode == 124 ? (step, 0) : event.keyCode == 125 ? (0, step) : (0, -step)
            nudge(d.0, d.1)
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

    private func nudge(_ dx: CGFloat, _ dy: CGFloat) {
        var updates: [String: CanvasPlacement] = [:]
        for id in selection { if var p = placements[id] { p.x += dx; p.y += dy; placements[id] = p; updates[id] = p } }
        guard !updates.isEmpty else { return }
        applyPlacementsToLayers(Array(updates.keys))
        onCommit?(updates, "Nudge on Canvas")
    }

    override func selectAll(_ sender: Any?) {
        selection = Set(entries.map(\.id))
        notifySelection()
        updateSelectionVisuals()
    }

    @objc func paste(_ sender: Any?) { onPaste?() }

    override func menu(for event: NSEvent) -> NSMenu? {
        let w = worldPoint(convert(event.locationInWindow, from: nil))
        guard let id = item(atWorld: w) else { return nil }
        window?.makeFirstResponder(self)
        if !selection.contains(id) { selection = [id]; notifySelection(); updateSelectionVisuals() }
        return contextMenuProvider?(id)
    }

    // MARK: Dev benchmark (STASH_BENCH=1): zoom in and out, then pan in circles, while a hitch monitor counts slow frames

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
        backgroundColor = NSColor.quaternaryLabelColor.cgColor
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

    func setSelected(_ on: Bool, scale: CGFloat) {
        borderWidth = on ? 2.5 / max(scale, 0.0001) : 0
        borderColor = NSColor.controlAccentColor.cgColor
    }

    private func updateTitle() {
        guard showsTitleCard, let name = summary?.name else { titleLayer?.removeFromSuperlayer(); titleLayer = nil; return }
        let t = titleLayer ?? CATextLayer()
        t.string = name
        t.fontSize = 14
        t.alignmentMode = .center
        t.isWrapped = true
        t.truncationMode = .end
        t.foregroundColor = NSColor.labelColor.cgColor
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
