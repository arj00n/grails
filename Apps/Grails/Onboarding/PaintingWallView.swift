import AppKit
import GrailsDesign
import SwiftUI

/// Hello's background: a famous painting as coloured dither pixels, turned into the next by a slow dither cross-construct every 14 seconds,
/// with a slow shimmer over the dither. No pointer handling. Layer-backed: the engine hands over a small bitmap and Core Animation scales
/// it, nearest-neighbour.
final class PaintingWallView: NSView {
    var epoch = Date()
    var reduceMotion = false { didSet { dirty = true } }

    private let engine = PaintingWallEngine.shared
    private let baseLayer = CALayer()
    private let smokeLayer = CALayer()
    private var link: CADisplayLink?
    private var dirty = true
    private var debugged = false
    // the pointer dragging ink through the painting
    private var smoke: SmokeField?
    private var lastMouse: CGPoint?
    private var lastSmokeTick: CFTimeInterval = 0
    private var lastBase: CFTimeInterval = 0
    private var smokeFast = false
    private var sweep = 0

    override var isFlipped: Bool { false }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.masksToBounds = true
        baseLayer.magnificationFilter = .nearest
        baseLayer.minificationFilter = .nearest
        baseLayer.contentsGravity = .resize
        baseLayer.anchorPoint = .zero
        layer?.addSublayer(baseLayer)
        smokeLayer.magnificationFilter = .nearest
        smokeLayer.minificationFilter = .nearest
        smokeLayer.contentsGravity = .resize
        smokeLayer.anchorPoint = .zero
        // white smoke through a difference blend turns the painting's own colours over: it reads on every painting, light or dark
        smokeLayer.compositingFilter = CIFilter(name: "CIDifferenceBlendMode")
        layer?.addSublayer(smokeLayer)
        engine?.onReady = { [weak self] in self?.dirty = true }
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        link?.invalidate(); link = nil
        guard window != nil else { return }
        let l = displayLink(target: self, selector: #selector(tick))
        // the drift is slow: 15 frames a second is plenty
        l.preferredFrameRateRange = CAFrameRateRange(minimum: 10, maximum: 20, preferred: 15)
        l.add(to: .main, forMode: .common)
        link = l
        dirty = true
    }

    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); dirty = true }
    override func setFrameSize(_ newSize: NSSize) { super.setFrameSize(newSize); dirty = true }

    @objc private func tick() {
        guard let engine, bounds.width > 8 else { return }
        let now = CACurrentMediaTime()
        updateSmoke(now)
        // the painting itself moves slowly: 15 frames a second, or only when something about it changed
        guard dirty || (!reduceMotion && now - lastBase >= 1.0 / 15 - 0.004) else { return }
        // with Reduce Motion nothing moves, so only appearance and size changes need a frame
        guard dirty || !reduceMotion else { return }
        dirty = false
        lastBase = now
        let t = reduceMotion ? 10 : Date().timeIntervalSince(epoch)
        let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        // dev: GRAILS_DEBUG_WALL=<file> writes where the wall is, once (it must equal the window's content area)
        if let path = ProcessInfo.processInfo.environment["GRAILS_DEBUG_WALL"], t > 3, !debugged {
            debugged = true
            try? "bounds \(bounds) window content \(String(describing: window?.contentView?.bounds)) top-left in window \(convert(bounds, to: nil))".write(toFile: path, atomically: true, encoding: .utf8)
        }
        guard let frame = engine.frame(size: bounds.size, t: t, dark: dark, reduceMotion: reduceMotion) else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        baseLayer.contents = frame.base
        // hung from the top left; layer y runs up
        baseLayer.frame = CGRect(x: 0, y: bounds.height - frame.baseSize.height, width: frame.baseSize.width, height: frame.baseSize.height)
        smokeLayer.frame = baseLayer.frame
        let px = PaintingWall.pixel
        let cols = Int((bounds.width / CGFloat(px)).rounded(.up)), rows = Int((bounds.height / CGFloat(px)).rounded(.up))
        if smoke?.cols != cols || smoke?.rows != rows { smoke = SmokeField(cols: cols, rows: rows, cell: 3) }
        CATransaction.commit()
    }

    /// The pointer, if it moves over the painting, drags ink through it; the ink thins out and is gone within a couple of seconds.
    private func updateSmoke(_ now: CFTimeInterval) {
        guard !reduceMotion, let smoke, let window, window.isVisible else {
            if smokeLayer.contents != nil { smokeLayer.contents = nil }
            return
        }
        let px = CGFloat(PaintingWall.pixel)
        let p = convert(window.convertPoint(fromScreen: NSEvent.mouseLocation), from: nil)
        if let last = lastMouse, bounds.insetBy(dx: -24, dy: -24).contains(p) {
            smoke.stir(x: Float(p.x / px), y: Float((bounds.height - p.y) / px), vx: Float((p.x - last.x) / px), vy: Float(-(p.y - last.y) / px))
        }
        lastMouse = p
        // dev: GRAILS_ONBOARDING_SMOKE=1 sweeps the pointer across the painting from 3.5 s in, for snapshots
        if ProcessInfo.processInfo.environment["GRAILS_ONBOARDING_SMOKE"] != nil, Date().timeIntervalSince(epoch) > 3.5, sweep < 110 {
            let w = Float(smoke.cols), h = Float(smoke.rows), a = Float(sweep)
            smoke.stir(x: w * 0.3 + a * w * 0.004, y: h * 0.55 + sin(a / 9) * h * 0.2, vx: w * 0.004 * 3, vy: cos(a / 9) * h * 0.2 / 9 * 3)
            sweep += 1
        }
        let dt = lastSmokeTick == 0 ? Float(1.0 / 60) : Float(min(now - lastSmokeTick, 0.05))
        lastSmokeTick = now
        if smoke.active {
            if !smokeFast { smokeFast = true; link?.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 60, preferred: 60) }
            smoke.step(dt)
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            smokeLayer.contents = smoke.active ? smoke.image(ink: 0xFFFF_FFFF) : nil
            CATransaction.commit()
        } else if smokeFast {
            smokeFast = false
            link?.preferredFrameRateRange = CAFrameRateRange(minimum: 10, maximum: 20, preferred: 15)
            lastSmokeTick = 0
        }
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
