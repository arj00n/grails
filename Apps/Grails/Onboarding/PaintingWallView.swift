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
    private var link: CADisplayLink?
    private var dirty = true

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
        // with Reduce Motion nothing moves, so only appearance and size changes need a frame
        guard dirty || !reduceMotion else { return }
        dirty = false
        let t = reduceMotion ? 10 : Date().timeIntervalSince(epoch)
        let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        guard let frame = engine.frame(size: bounds.size, t: t, dark: dark, reduceMotion: reduceMotion) else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        baseLayer.contents = frame.base
        // hung from the top left; layer y runs up
        baseLayer.frame = CGRect(x: 0, y: bounds.height - frame.baseSize.height, width: frame.baseSize.width, height: frame.baseSize.height)
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
