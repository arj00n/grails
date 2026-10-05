import AppKit
import GrailsDesign
import SwiftUI

/// Hello's background: a famous painting as coloured dither pixels, turned into the next by a slow dither cross-construct every 14 seconds, with a
/// reveal of the real painting at the pointer. Layer-backed: the engine hands over a small bitmap and Core Animation scales it, nearest-neighbour.
final class PaintingWallView: NSView {
    var epoch = Date()
    var reduceMotion = false { didSet { dirty = true } }

    private let engine = PaintingWallEngine.shared
    private let baseLayer = CALayer(), loupeLayer = CALayer()
    private var link: CADisplayLink?
    private var monitor: Any?
    private var dirty = true
    private var pointer: CGPoint?
    private var trail: [(x: Double, y: Double, at: Double)] = []
    private var lastTrail = 0.0

    override var isFlipped: Bool { false }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.masksToBounds = true
        for l in [baseLayer, loupeLayer] {
            l.magnificationFilter = .nearest
            l.minificationFilter = .nearest
            l.contentsGravity = .resize
            l.anchorPoint = .zero
            layer?.addSublayer(l)
        }
        engine?.onReady = { [weak self] in self?.dirty = true }
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
        link?.invalidate(); link = nil
        guard let window else { return }
        window.acceptsMouseMovedEvents = true
        // a local monitor sees the pointer wherever it is in the window, even over the title plate laid on top
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged, .mouseExited]) { [weak self] event in
            self?.moved(event)
            return event
        }
        let l = displayLink(target: self, selector: #selector(tick))
        l.preferredFrameRateRange = CAFrameRateRange(minimum: 20, maximum: 30, preferred: 30)
        l.add(to: .main, forMode: .common)
        link = l
        dirty = true
    }

    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); dirty = true }
    override func setFrameSize(_ newSize: NSSize) { super.setFrameSize(newSize); dirty = true }

    private func moved(_ event: NSEvent) {
        guard !reduceMotion, event.window === window else { return }
        let p = convert(event.locationInWindow, from: nil)
        guard bounds.contains(p), event.type != .mouseExited else { pointer = nil; dirty = true; return }
        pointer = CGPoint(x: p.x, y: bounds.height - p.y)               // points from the top left, like the grids
        let now = CACurrentMediaTime()
        if now - lastTrail > 0.04 {                                      // a point every ~40 ms is plenty for a smooth trail
            lastTrail = now
            trail.append((Double(p.x), Double(bounds.height - p.y), now))
            if trail.count > 48 { trail.removeFirst(trail.count - 48) }
        }
        dirty = true
    }

    @objc private func tick() {
        guard let engine, bounds.width > 8 else { return }
        let now = CACurrentMediaTime()
        trail.removeAll { now - $0.at > PaintingWall.loupeLife }
        var touches = trail.map { PaintingWall.Touch(x: $0.x, y: $0.y, age: now - $0.at) }
        if let p = pointer { touches.append(PaintingWall.Touch(x: Double(p.x), y: Double(p.y), age: 0)) }
        let t = reduceMotion ? 10 : Date().timeIntervalSince(epoch)
        let sched = PaintingWall.schedule(t: t, count: engine.specs.count, reduceMotion: reduceMotion)
        let moving = !reduceMotion && (t < PaintingWall.introStart + PaintingWall.introDuration + 0.05 || sched.progress != nil || !touches.isEmpty)
        // nothing moves while a painting holds and the pointer is still: no work at all
        guard dirty || moving else { return }
        dirty = false
        let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        guard let frame = engine.frame(size: bounds.size, t: t, dark: dark, reduceMotion: reduceMotion, touches: reduceMotion ? [] : touches) else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        baseLayer.contents = frame.base
        // hung from the top left; layer y runs up
        baseLayer.frame = CGRect(x: 0, y: bounds.height - frame.baseSize.height, width: frame.baseSize.width, height: frame.baseSize.height)
        if let l = frame.loupe {
            loupeLayer.contents = l.image
            loupeLayer.frame = CGRect(x: l.rect.minX, y: bounds.height - l.rect.maxY, width: l.rect.width, height: l.rect.height)
            loupeLayer.isHidden = false
        } else {
            loupeLayer.isHidden = true
        }
        CATransaction.commit()
    }
}

struct PaintingWallBackground: NSViewRepresentable {
    var epoch: Date
    var reduceMotion: Bool

    func makeNSView(context: Context) -> PaintingWallView {
        let v = PaintingWallView()
        v.epoch = epoch
        v.reduceMotion = reduceMotion
        return v
    }

    func updateNSView(_ v: PaintingWallView, context: Context) {
        v.epoch = epoch
        if v.reduceMotion != reduceMotion { v.reduceMotion = reduceMotion }
    }
}
