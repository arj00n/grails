import AVKit
import AppKit
import GrailsDesign
import GrailsKit

/// The picture area of the preview: three pages (previous, current, next) on layers, driven by the trackpad. Swipe sideways to turn
/// the page, swipe up or down (or pinch out) to close, pinch and double-tap to zoom. Every drag tracks the fingers 1:1 and any
/// settle can be caught mid-flight. Per-frame state stays in here; SwiftUI hears only about committed changes.
@MainActor
final class PreviewStageView: NSView {
    // MARK: Wiring

    private(set) var pageSet = PreviewSet([])
    private(set) var index = 0
    var sourceFor: (ItemSummary) -> PreviewSource = { _ in PreviewSource(original: nil, thumb: URL(fileURLWithPath: "/"), thumbMax: 512) }
    /// A page turn finished: the new position.
    var onCommit: ((Int) -> Void)?
    var onClose: (() -> Void)?
    /// Progress of a dismiss drag, 0...1, so the page behind can fade with it.
    var onDismissProgress: ((Double) -> Void)?
    /// Keys the stage doesn't own (like, tag, move…) go to the app's shortcuts.
    var keyHandler: ((NSEvent) -> Bool)?
    var onOpenSource: (() -> Void)?
    /// Where an item's tile is (window coordinates) and a way to hide it while its picture flies to or from the preview.
    var tileRectProvider: ((String) -> CGRect?)?
    var tileHide: ((String, Bool) -> Void)?
    /// 0 = the picture is on its tile, 1 = it is in place on the page: the page and its details fade with it.
    var onFlight: ((Double) -> Void)?
    var currentID: String? { pageSet[index]?.id }

    // MARK: State

    private static let gap: CGFloat = 32
    private let pages = [CALayer(), CALayer(), CALayer()]          // slots -1, 0, +1
    private var offsetX = CriticalSpring(response: 0.26)            // page drag, points
    private var dismissY = CriticalSpring(response: 0.26)           // up/down drag, points
    private var zoom = CriticalSpring(value: 1, target: 1, response: 0.2, tolerance: 0.0005)    // relative to fit
    private var panX = CriticalSpring(response: 0.2)
    private var panY = CriticalSpring(response: 0.2)
    private var flight = CriticalSpring(value: 1, target: 1, response: 0.3, tolerance: 0.001)
    private var tileStageRect: CGRect?
    private var flightTileID: String?
    private var pendingOpenFlight = false
    private var closingByFlight = false
    private var gesture: PagerGesture?
    private var gate = MomentumGate()
    private var tracking = false                                    // fingers are driving the page or the dismiss
    private var pinching = false
    private var travelDirection = 1
    private var link: CADisplayLink?
    private var lastTick: CFTimeInterval = 0
    private var overlay: NSView?
    private var overlayID: String?
    private var closing = false
    private var wheelStamp: CFTimeInterval = 0
    private var dragStart: NSPoint?
    private var dragMoved = false
    private var lastDragTime: CFTimeInterval = 0
    private let prevButton = NSButton()
    private let nextButton = NSButton()
    private var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
    private var scale: CGFloat { window?.backingScaleFactor ?? 2 }

    override var acceptsFirstResponder: Bool { true }
    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.masksToBounds = true
        for p in pages {
            p.contentsGravity = .resize
            p.magnificationFilter = .trilinear
            p.minificationFilter = .trilinear
            p.isHidden = true
            layer?.addSublayer(p)
        }
        for (b, symbol, action) in [(prevButton, "chevron.left", #selector(stepBack)), (nextButton, "chevron.right", #selector(stepForward))] {
            b.isBordered = false
            b.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
            b.contentTintColor = .ink(.secondary)
            b.target = self
            b.action = action
            b.alphaValue = 0
            b.wantsLayer = true
            addSubview(b)
        }
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self))
        setAccessibilityElement(true)
        setAccessibilityRole(.image)
        setAccessibilityIdentifier("preview-stage")
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: Loading

    func load(_ newSet: PreviewSet, at position: Int, animatedOpen: Bool) {
        pageSet = newSet
        index = min(max(position, 0), max(pageSet.count - 1, 0))
        closing = false
        offsetX = CriticalSpring(response: 0.26)
        dismissY = CriticalSpring(response: 0.26)
        resetZoom()
        flight = CriticalSpring(value: 1, target: 1, response: 0.3, tolerance: 0.001)
        if animatedOpen, !reduceMotion {
            if tileRectProvider != nil {
                // the picture flies out of its tile once the stage has a size
                flight.value = 0
                pendingOpenFlight = true
            } else {
                // no tile to fly from: settle in from slightly smaller while the page fades up
                dismissY.value = bounds.height * 0.4 * 0.5
                dismissY.target = 0
                startLink()
            }
        }
        refresh()
        if pendingOpenFlight, bounds.width > 100 { beginOpenFlight() }
    }

    private func beginOpenFlight() {
        pendingOpenFlight = false
        guard let id = currentID, let win = tileRectProvider?(id), win.width > 1, window != nil else { forceOpen(); return }
        tileStageRect = convert(win, from: nil)
        flightTileID = id
        tileHide?(id, true)
        flight.value = 0; flight.velocity = 0; flight.target = 1
        layoutPages()
        startLink()
        if let dir = ProcessInfo.processInfo.environment["GRAILS_PREVIEW_DEMO"] { demoWatchOpen(into: dir) }
    }

    /// Skips the flight (no tile, or it never got started): the page is simply there.
    func forceOpen() {
        pendingOpenFlight = false
        flight = CriticalSpring(value: 1, target: 1, response: 0.3, tolerance: 0.001)
        if let id = flightTileID { tileHide?(id, false); flightTileID = nil }
        tileStageRect = nil
        onFlight?(1)
        layoutPages()
    }

    var isWaitingToOpen: Bool { pendingOpenFlight }

    /// The model moved us (a link, the info column): jump without a swipe.
    func jump(to position: Int) {
        guard pageSet[position] != nil, position != index else { return }
        index = position
        offsetX = CriticalSpring(response: 0.26)
        resetZoom()
        refresh()
    }

    func replaceSet(_ newSet: PreviewSet, position: Int) {
        pageSet = newSet
        index = min(max(position, 0), max(pageSet.count - 1, 0))
        resetZoom()
        refresh()
    }

    private func refresh() {
        layoutPages()
        loadImages()
        refreshOverlay()
        if let item = pageSet[index] { setAccessibilityLabel("Image \(index + 1) of \(pageSet.count), \(item.name)") }
        updateArrows()
    }

    private func pixelSize(_ i: Int) -> CGSize {
        guard let s = pageSet[i] else { return .zero }
        if let w = s.width, let h = s.height, w > 0, h > 0 { return CGSize(width: w, height: h) }
        if let img = PreviewImageCache.shared.image(s.id) { return CGSize(width: img.width, height: img.height) }
        return CGSize(width: 4, height: 3)
    }

    private func loadImages() {
        let cache = PreviewImageCache.shared
        let near = Set((-2...2).compactMap { pageSet[index + $0]?.id })
        cache.trim(keeping: near)
        let longEdge = max(bounds.width, bounds.height) * scale
        var pixels = Int(min(longEdge, 4096))
        // zoomed in: ask for what the zoom needs
        if zoom.value > 1.05, let item = pageSet[index] {
            let fit = Pager.fitRect(image: pixelSize(index), stage: bounds.size)
            pixels = Int(min(max(Double(pixels), Double(max(fit.width, fit.height) * zoom.value * scale)), 6000))
            _ = item
        }
        let order: [(Int, Operation.QueuePriority)] = [(0, .veryHigh), (travelDirection, .high), (-travelDirection, .normal), (2 * travelDirection, .low), (-2 * travelDirection, .low)]
        for (slot, priority) in order {
            guard let item = pageSet[index + slot] else { continue }
            cache.ensure(item.id, source: sourceFor(item), pixels: slot == 0 ? pixels : min(pixels, 2048), priority: priority) { [weak self] _ in self?.layoutPages(); self?.refreshOverlay() }
        }
    }

    // MARK: Layout

    private func fitZoomForTall(_ i: Int) -> Double {
        let size = pixelSize(i)
        guard Pager.isTall(size) else { return 1 }
        let fit = Pager.fitRect(image: size, stage: bounds.size)
        let target = max(bounds.width - 48, 1)
        return max(1, Double(target / max(fit.width, 1)))
    }

    private func resetZoom() {
        let z = fitZoomForTall(index)
        zoom = CriticalSpring(value: z, target: z, response: 0.2, tolerance: 0.0005)
        panX = CriticalSpring(response: 0.2)
        panY = CriticalSpring(response: 0.2)
        if z > 1 { panY.value = Double(tallTopPan(z)); panY.target = panY.value }
    }

    /// The vertical pan that shows the top of a tall picture.
    private func tallTopPan(_ z: Double) -> CGFloat {
        let fit = Pager.fitRect(image: pixelSize(index), stage: bounds.size)
        return max((fit.height * CGFloat(z) - bounds.height) / 2, 0)
    }

    private func currentRect() -> CGRect {
        let fit = Pager.fitRect(image: pixelSize(index), stage: bounds.size)
        let z = CGFloat(zoom.value)
        let size = CGSize(width: fit.width * z, height: fit.height * z)
        let c = CGPoint(x: bounds.midX + CGFloat(panX.value), y: bounds.midY + CGFloat(panY.value))
        return CGRect(x: c.x - size.width / 2, y: c.y - size.height / 2, width: size.width, height: size.height)
    }

    private func clampPan() {
        let fit = Pager.fitRect(image: pixelSize(index), stage: bounds.size)
        let z = CGFloat(zoom.value)
        let limitX = max((fit.width * z - bounds.width) / 2, 0), limitY = max((fit.height * z - bounds.height) / 2, 0)
        panX.value = min(max(panX.value, -Double(limitX)), Double(limitX)); panX.target = min(max(panX.target, -Double(limitX)), Double(limitX))
        panY.value = min(max(panY.value, -Double(limitY)), Double(limitY)); panY.target = min(max(panY.target, -Double(limitY)), Double(limitY))
    }

    private func layoutPages() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let W = bounds.width, H = bounds.height
        let p = Pager.dismissProgress(dy: dismissY.value, height: H)
        onDismissProgress?(p)
        let shrink = 1 - 0.2 * p
        let f = CGFloat(min(max(flight.value, 0), 1))
        onFlight?(Double(f))
        let cache = PreviewImageCache.shared
        for (n, layer) in pages.enumerated() {
            let slot = n - 1
            guard let item = pageSet[index + slot] else { layer.isHidden = true; continue }
            layer.isHidden = slot != 0 && f < 1                 // neighbours wait until the picture is in place
            var rect: CGRect
            if slot == 0 { rect = currentRect() } else { rect = Pager.fitRect(image: pixelSize(index + slot), stage: bounds.size) }
            if slot == 0, f < 1, let tile = tileStageRect {
                // the picture as it sits on its tile (whole, not cropped), growing to its place on the page
                let size = pixelSize(index)
                let s = min(tile.width / max(size.width, 1), tile.height / max(size.height, 1))
                let from = CGRect(x: tile.midX - size.width * s / 2, y: tile.midY - size.height * s / 2, width: size.width * s, height: size.height * s)
                rect = CGRect(x: from.minX + (rect.minX - from.minX) * f, y: from.minY + (rect.minY - from.minY) * f,
                              width: from.width + (rect.width - from.width) * f, height: from.height + (rect.height - from.height) * f)
            }
            layer.masksToBounds = slot == 0 && f < 1
            layer.cornerRadius = slot == 0 ? Ink.tileRadius * (1 - f) : 0
            let dx = CGFloat(slot) * (W + Self.gap) + CGFloat(offsetX.value)
            layer.frame = rect.offsetBy(dx: dx, dy: 0)
            layer.setAffineTransform(CGAffineTransform(translationX: 0, y: CGFloat(dismissY.value)).scaledBy(x: shrink, y: shrink))
            layer.backgroundColor = NSColor.ink(.surface).cgColor(in: self)
            if let img = cache.image(item.id) { layer.contents = img }
            else if let thumb = ThumbnailLoader.shared.cached(id: item.id, pixels: 512) { layer.contents = thumb }
            else { layer.contents = nil }
        }
        positionOverlay()
        CATransaction.commit()
    }

    override func layout() {
        super.layout()
        let y = bounds.midY - 20
        prevButton.frame = NSRect(x: 12, y: y, width: 40, height: 40)
        nextButton.frame = NSRect(x: bounds.width - 52, y: y, width: 40, height: 40)
        clampPan()
        layoutPages()
        if pendingOpenFlight, bounds.width > 100 { beginOpenFlight() }
    }

    override func viewDidChangeBackingProperties() { super.viewDidChangeBackingProperties(); loadImages() }

    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); layoutPages() }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil else {
            stopLink(); removeOverlay()
            if let id = flightTileID { tileHide?(id, false); flightTileID = nil }
            return
        }
        DispatchQueue.main.async { [weak self] in self?.window?.makeFirstResponder(self) }
    }

    // MARK: Video and GIF

    private var settled: Bool { flight.value > 0.999 && abs(offsetX.value) < 0.5 && abs(dismissY.value) < 0.5 && !tracking && !pinching && abs(zoom.value - 1) < 0.001 }

    private func refreshOverlay() {
        guard let item = pageSet[index] else { removeOverlay(); return }
        guard settled else { overlay?.isHidden = true; return }
        if overlayID == item.id, overlay != nil { overlay?.isHidden = false; positionOverlay(); return }
        removeOverlay()
        let url = sourceFor(item).original
        guard let url, FileManager.default.fileExists(atPath: url.path) else { return }
        if item.kind == .video {
            let view = StagePlayerView()
            view.controlsStyle = .floating
            view.showsFullScreenToggleButton = false
            let player = AVPlayer(url: url)
            player.isMuted = true
            view.player = player
            if (item.durationSec ?? 0) < 30 {
                NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: player.currentItem, queue: .main) { _ in
                    player.seek(to: .zero); player.play()
                }
            }
            player.play()
            overlay = view
        } else if item.ext?.lowercased() == "gif", let image = NSImage(contentsOf: url) {
            let view = NSImageView(image: image)
            view.animates = true
            view.imageScaling = .scaleAxesIndependently
            overlay = view
        }
        if let overlay { overlayID = item.id; addSubview(overlay, positioned: .below, relativeTo: prevButton); positionOverlay() }
    }

    private func positionOverlay() {
        guard let overlay else { return }
        overlay.frame = Pager.fitRect(image: pixelSize(index), stage: bounds.size)
    }

    private func removeOverlay() {
        if let v = overlay as? AVPlayerView { v.player?.pause(); v.player = nil }
        overlay?.removeFromSuperview()
        overlay = nil
        overlayID = nil
    }

    func togglePlayback() {
        guard let player = (overlay as? AVPlayerView)?.player else { return }
        if player.rate == 0 { player.play() } else { player.pause() }
    }

    private final class StagePlayerView: AVPlayerView {
        override var acceptsFirstResponder: Bool { false }
    }

    // MARK: Animation loop

    private func startLink() {
        guard link == nil else { return }
        lastTick = CACurrentMediaTime()
        let l = displayLink(target: self, selector: #selector(tick(_:)))
        l.add(to: .main, forMode: .common)
        link = l
    }

    private func stopLink() { link?.invalidate(); link = nil }

    @objc private func tick(_ l: CADisplayLink) {
        let dt = min(max(l.targetTimestamp - lastTick, 1.0 / 240), 1.0 / 20)
        lastTick = l.targetTimestamp
        var active = false
        if !flight.isSettled { flight.step(dt); active = true }
        if !tracking {
            if !offsetX.isSettled { offsetX.step(dt); active = true }
            if !dismissY.isSettled { dismissY.step(dt); active = true }
        }
        if !pinching {
            if !zoom.isSettled { zoom.step(dt); active = true }
            if !panX.isSettled { panX.step(dt); active = true }
            if !panY.isSettled { panY.step(dt); active = true }
        }
        layoutPages()
        if closing {
            let arrived = closingByFlight ? flight.isSettled : abs(dismissY.value - dismissY.target) < 1
            if arrived { stopLink(); finishClose(); return }
        }
        if !active {
            stopLink()
            if let id = flightTileID, !closing { tileHide?(id, false); flightTileID = nil; tileStageRect = nil }   // landed: the tile is free again
            refresh()
        }
    }

    // MARK: Turning pages

    private func canMove(_ delta: Int) -> Bool { pageSet[index + delta] != nil }

    /// Moves to the neighbour. The content stays where it is on screen (the offset takes over the distance) and glides to rest.
    private func commitPage(_ delta: Int, velocity: Double) {
        guard canMove(delta) else { settleOffset(velocity: velocity); return }
        travelDirection = delta
        index += delta
        let W = Double(bounds.width + Self.gap)
        offsetX.value += Double(delta) * W            // same picture position as before, expressed from the new page
        offsetX.target = 0
        offsetX.velocity = velocity
        resetZoom()
        removeOverlay()
        onCommit?(index)
        if reduceMotion { offsetX.value = 0; offsetX.velocity = 0 }
        refresh()
        startLink()
    }

    private func settleOffset(velocity: Double) {
        offsetX.target = 0
        offsetX.velocity = velocity
        startLink()
    }

    @objc func stepBack() { step(-1) }
    @objc func stepForward() { step(1) }

    func step(_ delta: Int) {
        guard !closing, canMove(delta) else { offsetX.velocity = 0; return }
        let W = Double(bounds.width + Self.gap)
        // start from where the picture is now (it may be mid-glide), then glide on from there
        let from = offsetX.value
        travelDirection = delta
        index += delta
        offsetX.value = from + Double(delta) * W
        offsetX.target = 0
        offsetX.velocity = 0
        resetZoom()
        removeOverlay()
        onCommit?(index)
        if reduceMotion { offsetX.value = 0 }
        refresh()
        startLink()
    }

    // MARK: Closing

    func close(velocityY: Double = 0, direction: Double = 1) {
        guard !closing else { return }
        closing = true
        tracking = false
        removeOverlay()
        if reduceMotion { onClose?(); return }
        // fly back to the tile (jumping it into view if you paged away from it); without one, fade and shrink away
        if let id = currentID, let win = tileRectProvider?(id), win.width > 1, window != nil {
            tileStageRect = convert(win, from: nil)
            if let old = flightTileID, old != id { tileHide?(old, false) }
            flightTileID = id
            tileHide?(id, true)
            closingByFlight = true
            flight.target = 0
            flight.velocity = 0
            dismissY.target = 0; dismissY.velocity = velocityY * 0.2
            offsetX.target = 0
            let z = fitZoomForTall(index)
            zoom.target = 1; _ = z
            panX.target = 0; panY.target = 0
            startLink()
            return
        }
        dismissY.target = direction * Double(bounds.height) * 0.5
        dismissY.velocity = velocityY
        startLink()
    }

    /// The picture is on its tile: take it off the page, give the tile back, then let the model remove the page.
    private func finishClose() {
        for p in pages { p.isHidden = true }
        if let id = flightTileID { tileHide?(id, false); flightTileID = nil }
        onClose?()
    }

    // MARK: Scrolling (trackpad)

    override func scrollWheel(with e: NSEvent) {
        guard !closing else { return }
        if !e.hasPreciseScrollingDeltas {
            // a wheel notch steps; ⌘ with the wheel zooms
            if e.modifierFlags.contains(.command) { zoomBy(exp(e.scrollingDeltaY * 0.03), at: convert(e.locationInWindow, from: nil)); return }
            let now = CACurrentMediaTime()
            guard now - wheelStamp > 0.15, abs(e.scrollingDeltaY) + abs(e.scrollingDeltaX) > 0 else { return }
            wheelStamp = now
            step((e.scrollingDeltaY + e.scrollingDeltaX) < 0 ? 1 : -1)
            return
        }
        if e.modifierFlags.contains(.command) { zoomBy(exp(e.scrollingDeltaY * 0.006), at: convert(e.locationInWindow, from: nil)); return }
        if pinching { return }

        let began = e.phase.contains(.began)
        let momentum = !e.momentumPhase.isEmpty
        let zoomedIn = zoom.value > 1.001
        if !zoomedIn, gate.shouldSwallow(began: began, momentum: momentum, momentumEnded: e.momentumPhase.contains(.ended)) { return }

        let inverted = e.isDirectionInvertedFromDevice
        let fx = Double(inverted ? e.scrollingDeltaX : -e.scrollingDeltaX), fy = Double(inverted ? e.scrollingDeltaY : -e.scrollingDeltaY)

        if zoomedIn {
            // zoomed in, scrolling moves the picture; paging is for the arrow keys
            panX.value += fx; panX.target = panX.value; panX.velocity = 0
            panY.value += fy; panY.target = panY.value; panY.velocity = 0
            clampPan()
            layoutPages()
            if e.phase.contains(.ended) || e.momentumPhase.contains(.ended) { loadImages() }
            return
        }

        if began {
            gesture = PagerGesture()
            tracking = true
            // catch a glide in flight: carry on from where it is now
            offsetX.target = offsetX.value; offsetX.velocity = 0
            dismissY.target = dismissY.value; dismissY.velocity = 0
            removeOverlay()
        }
        guard var g = gesture, tracking else { return }
        let now = e.timestamp
        if !momentum { g.add(dx: fx, dy: fy, at: now) }
        gesture = g
        applyDrag(g)
        if e.phase.contains(.ended) || e.phase.contains(.cancelled) { finishDrag(g, at: now, cancelled: e.phase.contains(.cancelled)) }
    }

    private func applyDrag(_ g: PagerGesture) {
        switch g.axis {
        case .horizontal:
            let canGo = g.dx > 0 ? canMove(-1) : canMove(1)
            offsetX.value = canGo ? g.dx : Pager.rubberBand(g.dx, width: Double(bounds.width))
            offsetX.target = offsetX.value
        case .vertical:
            dismissY.value = g.dy; dismissY.target = g.dy
        case .undecided: break
        }
        layoutPages()
    }

    private func finishDrag(_ g: PagerGesture, at t: Double, cancelled: Bool) {
        tracking = false
        gesture = nil
        gate.gestureEnded()
        let v = g.velocity(at: t)
        switch g.axis {
        case .horizontal where !cancelled:
            // an offset right shows the previous page
            let delta = g.dx > 0 ? -1 : 1
            if Pager.commitsPage(offset: offsetX.value, velocity: v.x, width: Double(bounds.width)), canMove(delta) { commitPage(delta, velocity: v.x) }
            else { settleOffset(velocity: v.x) }
        case .vertical where !cancelled:
            if Pager.commitsDismiss(dy: g.dy, vy: v.y, height: Double(bounds.height)) { close(velocityY: v.y, direction: g.dy < 0 ? -1 : 1) }
            else { dismissY.target = 0; dismissY.velocity = v.y; startLink() }
        default:
            offsetX.target = 0; dismissY.target = 0; startLink()
        }
    }

    // MARK: Zoom

    override func magnify(with e: NSEvent) {
        guard !closing else { return }
        let fit = fitZoomFloor()
        if e.phase.contains(.began) { pinching = true; zoom.target = zoom.value; zoom.velocity = 0; removeOverlay() }
        let p = convert(e.locationInWindow, from: nil)
        let maxZ = Pager.maxZoom(fit: Double(scaleOfFit()))
        var next = zoom.value * (1 + Double(e.magnification))
        // resistance below fit and above the maximum
        if next < fit { next = fit - (fit - next) * 0.5 }
        if next > maxZ { next = maxZ + (next - maxZ) * 0.3 }
        applyZoom(next, at: p)
        if e.phase.contains(.ended) || e.phase.contains(.cancelled) {
            pinching = false
            if zoom.value < fit * 0.8 { close(); return }
            zoom.target = min(max(zoom.value, fit), maxZ)
            clampPan(); panX.target = panX.value; panY.target = panY.value
            startLink()
            loadImages()
        }
    }

    override func smartMagnify(with e: NSEvent) { toggleZoom(at: convert(e.locationInWindow, from: nil)) }

    private func fitZoomFloor() -> Double { fitZoomForTall(index) > 1 ? 1 : 1 }

    /// Pixels per point at fit (≤ 1): so "maximum zoom" can be expressed against the picture's own resolution.
    private func scaleOfFit() -> CGFloat {
        let size = pixelSize(index)
        let fit = Pager.fitRect(image: size, stage: bounds.size)
        return size.width > 0 ? fit.width / size.width : 1
    }

    private func applyZoom(_ z: Double, at p: CGPoint) {
        let old = zoom.value
        let c = CGPoint(x: bounds.midX, y: bounds.midY)
        let ux = (p.x - c.x - CGFloat(panX.value)) / CGFloat(old), uy = (p.y - c.y - CGFloat(panY.value)) / CGFloat(old)
        zoom.value = z
        panX.value = Double(p.x - c.x - ux * CGFloat(z)); panY.value = Double(p.y - c.y - uy * CGFloat(z))
        panX.target = panX.value; panY.target = panY.value
        if z >= 1 { clampPan() }
        layoutPages()
    }

    private func zoomBy(_ factor: Double, at p: CGPoint) {
        let maxZ = Pager.maxZoom(fit: Double(scaleOfFit()))
        removeOverlay()
        applyZoom(min(max(zoom.value * factor, 1), maxZ), at: p)
        zoom.target = zoom.value
        loadImages()
        if abs(zoom.value - 1) < 0.001 { refreshOverlay() }
    }

    /// Fit ⇄ 100 % (one picture pixel per point), about the pointer.
    func toggleZoom(at p: CGPoint) {
        let maxZ = Pager.maxZoom(fit: Double(scaleOfFit()))
        let actual = min(Double(1 / max(scaleOfFit(), 0.0001)), maxZ)
        let target = zoom.value > 1.05 ? 1.0 : max(actual, 1.0001)
        removeOverlay()
        // finish at the zoom that keeps the point under the pointer, and glide there
        let startZ = zoom.value
        let c = CGPoint(x: bounds.midX, y: bounds.midY)
        let ux = (p.x - c.x - CGFloat(panX.value)) / CGFloat(startZ), uy = (p.y - c.y - CGFloat(panY.value)) / CGFloat(startZ)
        zoom.target = target
        panX.target = Double(p.x - c.x - ux * CGFloat(target)); panY.target = Double(p.y - c.y - uy * CGFloat(target))
        if target <= 1.0001 { panX.target = 0; panY.target = 0 }
        else {
            let fit = Pager.fitRect(image: pixelSize(index), stage: bounds.size)
            let limitX = max((fit.width * CGFloat(target) - bounds.width) / 2, 0), limitY = max((fit.height * CGFloat(target) - bounds.height) / 2, 0)
            panX.target = min(max(panX.target, -Double(limitX)), Double(limitX)); panY.target = min(max(panY.target, -Double(limitY)), Double(limitY))
        }
        if reduceMotion { zoom.value = zoom.target; panX.value = panX.target; panY.value = panY.target; refresh() } else { startLink() }
        loadImages()
    }

    // MARK: Mouse

    override func mouseDown(with e: NSEvent) {
        window?.makeFirstResponder(self)
        if e.clickCount == 2 { toggleZoom(at: convert(e.locationInWindow, from: nil)); return }
        dragStart = convert(e.locationInWindow, from: nil)
        dragMoved = false
        lastDragTime = e.timestamp
    }

    override func mouseDragged(with e: NSEvent) {
        guard let start = dragStart, !closing else { return }
        let p = convert(e.locationInWindow, from: nil)
        if zoom.value > 1.001 {
            panX.value += Double(e.deltaX); panY.value += Double(e.deltaY); panX.target = panX.value; panY.target = panY.value
            clampPan(); layoutPages(); dragMoved = true
            return
        }
        if !dragMoved, hypot(p.x - start.x, p.y - start.y) < 4 { return }
        if !dragMoved {
            dragMoved = true
            gesture = PagerGesture(); tracking = true
            offsetX.target = offsetX.value; dismissY.target = dismissY.value
            removeOverlay()
        }
        guard var g = gesture else { return }
        g.add(dx: Double(e.deltaX), dy: Double(e.deltaY), at: e.timestamp)
        gesture = g
        applyDrag(g)
    }

    override func mouseUp(with e: NSEvent) {
        defer { dragStart = nil }
        if dragMoved, tracking, let g = gesture { finishDrag(g, at: e.timestamp, cancelled: false); return }
        guard !dragMoved, !closing else { return }
        // a click on the empty stage closes; a click on the picture does nothing (video controls handle themselves)
        let p = convert(e.locationInWindow, from: nil)
        if !currentRect().contains(p) { close() }
    }

    override func mouseMoved(with e: NSEvent) { updateArrows(pointer: convert(e.locationInWindow, from: nil)) }
    override func mouseExited(with e: NSEvent) { updateArrows(pointer: nil) }

    private func updateArrows(pointer: NSPoint? = nil) {
        let p = pointer
        let nearLeft = p.map { $0.x < 80 } ?? false, nearRight = p.map { $0.x > bounds.width - 80 } ?? false
        prevButton.alphaValue = nearLeft && canMove(-1) ? 1 : 0
        nextButton.alphaValue = nearRight && canMove(1) ? 1 : 0
    }

    // MARK: Keys

    override func performKeyEquivalent(with e: NSEvent) -> Bool {
        // the grid and canvas aren't visible: ⌘1 and ⌘2 do nothing here
        if e.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command, e.charactersIgnoringModifiers == "1" || e.charactersIgnoringModifiers == "2" { return true }
        return super.performKeyEquivalent(with: e)
    }

    override func keyDown(with e: NSEvent) {
        let mods = e.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting([.numericPad, .function])
        switch (e.keyCode, mods) {
        case (53, []), (49, []): close(); return                                  // esc, space
        case (123, []): step(-1); return
        case (124, []): step(1); return
        case (123, .shift): seek(-5); return
        case (124, .shift): seek(5); return
        case (36, .command), (76, .command): onOpenSource?(); return              // ⌘↩
        case (3, []), (29, []): fitNow(); return                                   // F, 0
        case (29, .command): fitNow(); return
        case (18, []): toggleZoom(at: CGPoint(x: bounds.midX, y: bounds.midY)); return   // 1: 100 %
        case (24, .command): zoomBy(1.25, at: CGPoint(x: bounds.midX, y: bounds.midY)); return
        case (27, .command): zoomBy(0.8, at: CGPoint(x: bounds.midX, y: bounds.midY)); return
        case (40, []): togglePlayback(); return                                    // K
        default: break
        }
        if keyHandler?(e) == true { return }
        super.keyDown(with: e)
    }

    private func fitNow() {
        let z = fitZoomForTall(index)
        zoom.target = z; panX.target = 0; panY.target = z > 1 ? Double(tallTopPan(z)) : 0
        if reduceMotion { zoom.value = z; panX.value = 0; panY.value = panY.target; refresh() } else { startLink() }
    }

    private func seek(_ seconds: Double) {
        guard let player = (overlay as? AVPlayerView)?.player else { return }
        player.seek(to: CMTimeAdd(player.currentTime(), CMTime(seconds: seconds, preferredTimescale: 600)))
    }
}

// MARK: Dev demo (GRAILS_PREVIEW_DEMO=<output dir>)
//
// Feeds synthetic trackpad events straight to this view (never through the window server) and writes what happened to
// `result.txt`, with a PNG of the stage after each step.

extension PreviewStageView {
    private func scrollEvent(dx: Double, dy: Double, phase: Int64, momentum: Int64 = 0, at t: Double) -> NSEvent? {
        guard let cg = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2, wheel1: Int32(dy), wheel2: Int32(dx), wheel3: 0) else { return nil }
        cg.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
        cg.setIntegerValueField(.scrollWheelEventScrollPhase, value: phase)
        cg.setIntegerValueField(.scrollWheelEventMomentumPhase, value: momentum)
        cg.timestamp = CGEventTimestamp(t * 1_000_000_000)
        return NSEvent(cgEvent: cg)
    }

    func demoSnapshot(_ path: String) {
        let w = Int(bounds.width), h = Int(bounds.height)
        guard w > 0, h > 0, let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue), let root = layer else { return }
        ctx.setFillColor(NSColor.ink(.canvas).cgColor); ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        ctx.translateBy(x: 0, y: CGFloat(h)); ctx.scaleBy(x: 1, y: -1)
        root.render(in: ctx)
        if let img = ctx.makeImage(), let rep = NSBitmapImageRep(cgImage: img).representation(using: .png, properties: [:]) {
            try? rep.write(to: URL(fileURLWithPath: path))
        }
    }

    /// Dev: watches the opening flight and writes how it went.
    func demoWatchOpen(into dir: String) {
        Task { @MainActor in
            try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            var samples: [String] = []
            var shot = false
            let t0 = CACurrentMediaTime()
            let tile = tileStageRect.map { "tile \(Int($0.minX)),\(Int($0.minY)) \(Int($0.width))x\(Int($0.height))" } ?? "no tile"
            for _ in 0..<40 {
                let f = flight.value
                samples.append(String(format: "%.3f@%dms", f, Int((CACurrentMediaTime() - t0) * 1000)))
                if !shot, f > 0.25, f < 0.85 { shot = true; demoSnapshot(dir + "/flight-mid.png") }
                if f >= 0.999 { break }
                try? await Task.sleep(for: .milliseconds(20))
            }
            try? ("open flight from \(tile)\n" + samples.joined(separator: " ") + "\n").write(toFile: dir + "/flight.txt", atomically: true, encoding: .utf8)
        }
    }

    func runDemo(into dir: String) {
        Task { @MainActor in
            try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            var log: [String] = []
            func say(_ s: String) { log.append(s); try? log.joined(separator: "\n").write(toFile: dir + "/result.txt", atomically: true, encoding: .utf8) }
            func wait(_ s: Double) async { try? await Task.sleep(for: .seconds(s)) }
            @MainActor func snap(_ name: String) { demoSnapshot("\(dir)/\(name).png") }
            // wait for a real size and the first picture
            for _ in 0..<40 where bounds.width < 100 || pageSet.count == 0 { await wait(0.25) }
            say("stage \(Int(bounds.width))x\(Int(bounds.height)), items \(pageSet.count), start index \(index)")
            await wait(1.2)
            snap("0-open")

            // 1. a slow drag past a third of the width, then release: turns the page
            let start = index
            var t = 1000.0
            if let e = scrollEvent(dx: 0, dy: 0, phase: 1, at: t) { scrollWheel(with: e) }
            for _ in 0..<12 { t += 0.016; if let e = scrollEvent(dx: 40, dy: 2, phase: 2, at: t) { scrollWheel(with: e) } }
            snap("1-dragging")
            t += 0.016
            if let e = scrollEvent(dx: 0, dy: 0, phase: 4, at: t) { scrollWheel(with: e) }
            await wait(0.8)
            say("after slow drag of 480 pt: index \(start) → \(index)")
            snap("2-after-turn")

            // 2. a flick: short and fast
            let beforeFlick = index
            t += 1
            if let e = scrollEvent(dx: 0, dy: 0, phase: 1, at: t) { scrollWheel(with: e) }
            for _ in 0..<4 { t += 0.008; if let e = scrollEvent(dx: 25, dy: 0, phase: 2, at: t) { scrollWheel(with: e) } }
            if let e = scrollEvent(dx: 0, dy: 0, phase: 4, at: t + 0.004) { scrollWheel(with: e) }
            // momentum events right after must not turn another page
            for i in 0..<6 { if let e = scrollEvent(dx: 30, dy: 0, phase: 0, momentum: i == 5 ? 4 : 2, at: t + 0.02 + Double(i) * 0.016) { scrollWheel(with: e) } }
            await wait(0.8)
            say("flick of 100 pt + momentum: index \(beforeFlick) → \(index) (one page expected)")

            // 3. rubber band at the first item: jump there and drag toward the missing previous page
            jump(to: 0)
            t += 1
            if let e = scrollEvent(dx: 0, dy: 0, phase: 1, at: t) { scrollWheel(with: e) }
            for _ in 0..<10 { t += 0.016; if let e = scrollEvent(dx: -60, dy: 0, phase: 2, at: t) { scrollWheel(with: e) } }
            say("dragging 600 pt toward nothing at the first item: page offset \(Int(offsetX.value)) pt (resisted: well under 600)")
            snap("3-rubber-band")
            t += 0.5
            if let e = scrollEvent(dx: 0, dy: 0, phase: 4, at: t) { scrollWheel(with: e) }
            await wait(0.8)
            say("after release: index \(index), offset \(Int(offsetX.value))")

            // 4. a small vertical drag springs back; a big one closes
            var closed = false
            onClose = { closed = true }
            t += 1
            if let e = scrollEvent(dx: 0, dy: 0, phase: 1, at: t) { scrollWheel(with: e) }
            for _ in 0..<5 { t += 0.016; if let e = scrollEvent(dx: 0, dy: 10, phase: 2, at: t) { scrollWheel(with: e) } }
            snap("4-vertical")
            t += 0.5
            if let e = scrollEvent(dx: 0, dy: 0, phase: 4, at: t) { scrollWheel(with: e) }
            await wait(0.8)
            say("small vertical drag (50 pt): closed=\(closed), dismiss offset \(Int(dismissY.value))")
            t += 1
            if let e = scrollEvent(dx: 0, dy: 0, phase: 1, at: t) { scrollWheel(with: e) }
            for _ in 0..<10 { t += 0.016; if let e = scrollEvent(dx: 0, dy: 20, phase: 2, at: t) { scrollWheel(with: e) } }
            t += 0.016
            if let e = scrollEvent(dx: 0, dy: 0, phase: 4, at: t) { scrollWheel(with: e) }
            await wait(1.0)
            say("large vertical drag (200 pt): closed=\(closed)")

            // 5. the close flight: reopen on a tile, press Esc-equivalent, and watch the picture head back to it
            closed = false
            var hidden: [String] = []
            tileHide = { id, h in hidden.append("\(id.suffix(4)):\(h ? "hide" : "show")") }
            let backTo = pageSet[index]?.id ?? ""
            _ = backTo
            closing = false; dismissY = CriticalSpring(response: 0.26)
            for p in pages { p.isHidden = false }
            layoutPages()
            let before = flight.value
            close()
            var closeSamples: [String] = []
            for _ in 0..<30 { closeSamples.append(String(format: "%.2f", flight.value)); if closed { break }; await wait(0.02) }
            await wait(0.3)
            say("close flight from f=\(before): onClose=\(closed), tile calls \(hidden), flight \(closeSamples.joined(separator: " "))")
            say("done")
            if ProcessInfo.processInfo.environment["GRAILS_PREVIEW_DEMO_QUIT"] != nil { NSApp.terminate(nil) }
        }
    }
}
