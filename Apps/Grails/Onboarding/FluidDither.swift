import AppKit
import GrailsDesign
import SwiftUI

/// Ink rising through a grid of pixels, stirred by the pointer: a small stable-fluids solver (velocity, pressure, dye) on a coarse grid,
/// drawn through an 8×8 ordered dither in one colour on another, like the paintings. The same effect as the website's footer.
final class FluidField {
    private(set) var w = 0, h = 0
    private var n = 0
    private var u, v, u0, v0, d, d0, p, div: UnsafeMutablePointer<Float>
    private var time: Float = 0

    struct Stir { var x: Float, y: Float, vx: Float, vy: Float }

    init() {
        u = .allocate(capacity: 1); v = .allocate(capacity: 1); u0 = .allocate(capacity: 1); v0 = .allocate(capacity: 1)
        d = .allocate(capacity: 1); d0 = .allocate(capacity: 1); p = .allocate(capacity: 1); div = .allocate(capacity: 1)
    }

    deinit { [u, v, u0, v0, d, d0, p, div].forEach { $0.deallocate() } }

    /// The ordered-dither thresholds, 0..1.
    static let bayer: [Float] = {
        var m: [[Int]] = [[0]]
        while m.count < 8 {
            let k = m.count
            var next = Array(repeating: Array(repeating: 0, count: k * 2), count: k * 2)
            for y in 0..<(k * 2) { for x in 0..<(k * 2) {
                let base = m[y % k][x % k] * 4
                next[y][x] = base + [0, 2, 3, 1][(y < k ? 0 : 2) + (x < k ? 0 : 1)]
            } }
            m = next
        }
        return (0..<64).map { (Float(m[$0 / 8][$0 % 8]) + 0.5) / 64 }
    }()

    func resize(_ newW: Int, _ newH: Int) {
        let nw = max(newW, 24), nh = max(newH, 12)
        guard nw != w || nh != h else { return }
        [u, v, u0, v0, d, d0, p, div].forEach { $0.deallocate() }
        w = nw; h = nh; n = nw * nh
        func zeros() -> UnsafeMutablePointer<Float> { let a = UnsafeMutablePointer<Float>.allocate(capacity: nw * nh); a.initialize(repeating: 0, count: nw * nh); return a }
        u = zeros(); v = zeros(); u0 = zeros(); v0 = zeros(); d = zeros(); d0 = zeros(); p = zeros(); div = zeros()
    }

    private func sample(_ a: UnsafeMutablePointer<Float>, _ x: Float, _ y: Float) -> Float {
        let cx = min(max(x, 0), Float(w) - 1.001), cy = min(max(y, 0), Float(h) - 1.001)
        let x0 = Int(cx), y0 = Int(cy)
        let fx = cx - Float(x0), fy = cy - Float(y0)
        let i = y0 * w + x0
        return (a[i] * (1 - fx) + a[i + 1] * fx) * (1 - fy) + (a[i + w] * (1 - fx) + a[i + w + 1] * fx) * fy
    }

    private func advect(_ out: UnsafeMutablePointer<Float>, _ src: UnsafeMutablePointer<Float>, _ dt: Float) {
        for y in 0..<h { for x in 0..<w {
            let i = y * w + x
            out[i] = sample(src, Float(x) - u[i] * dt, Float(y) - v[i] * dt)
        } }
    }

    private func project() {
        for y in 1..<(h - 1) { for x in 1..<(w - 1) {
            let i = y * w + x
            div[i] = -0.5 * (u[i + 1] - u[i - 1] + v[i + w] - v[i - w])
            p[i] = 0
        } }
        for _ in 0..<14 { for y in 1..<(h - 1) { for x in 1..<(w - 1) {
            let i = y * w + x
            p[i] = (div[i] + p[i - 1] + p[i + 1] + p[i - w] + p[i + w]) * 0.25
        } } }
        for y in 1..<(h - 1) { for x in 1..<(w - 1) {
            let i = y * w + x
            u[i] -= 0.5 * (p[i + 1] - p[i - 1])
            v[i] -= 0.5 * (p[i + w] - p[i - w])
        } }
    }

    /// One step of `dt` seconds. Ink floats up from the floor in slow, uneven plumes; the pointer, if it moved, drags it about.
    func step(_ dt: Float, stir: Stir?) {
        guard n > 0 else { return }
        time += dt
        for x in 0..<w {
            let plume = 0.5 + 0.5 * sin(Float(x) * 0.11 + time * 0.7) * sin(Float(x) * 0.043 - time * 0.31 + 1.7)
            for y in (h - 2)..<h { let i = y * w + x; d[i] = min(1, d[i] + plume * plume * 0.04 * dt * 60) }
        }
        // damping and fade are per 1/60 s, so a slow frame doesn't change how thick the ink gets
        let damp = pow(0.96, dt * 60)
        for y in 0..<h {
            let wind = sin(Float(y) * 0.19 + time * 0.5) * 0.35
            for x in 0..<w {
                let i = y * w + x
                u[i] += wind * dt * 2
                v[i] -= (0.03 + d[i] * 0.2) * dt * 6          // ink is lighter than the air: it floats up
                u[i] *= damp; v[i] *= damp
            }
        }
        if let s = stir {
            let r: Float = 8, r2 = r * r
            let fx = s.vx * 1.4, fy = s.vy * 1.4
            let y0 = max(0, Int(s.y - r * 2)), y1 = min(h, Int(s.y + r * 2) + 1)
            let x0 = max(0, Int(s.x - r * 2)), x1 = min(w, Int(s.x + r * 2) + 1)
            if y0 < y1, x0 < x1 { for y in y0..<y1 { for x in x0..<x1 {
                let dx = Float(x) - s.x, dy = Float(y) - s.y
                let wgt = exp(-(dx * dx + dy * dy) / r2)
                let i = y * w + x
                u[i] += fx * wgt; v[i] += fy * wgt
                d[i] = min(1, d[i] + wgt * 0.2)
            } } }
        }
        project()
        let k = dt * 60 * 0.9
        advect(u0, u, k); advect(v0, v, k)
        swap(&u, &u0); swap(&v, &v0)
        project()
        advect(d0, d, k)
        swap(&d, &d0)
        let fade = pow(0.982, dt * 60)
        for i in 0..<n { d[i] *= fade }
        for x in 0..<w { d[x] *= 0.6; d[x + w] *= 0.85 }      // the top edge lets ink go
    }

    /// The field as a bitmap of `ink` where the dithered density says so and `paper` elsewhere (RGBA, premultiplied, opaque).
    func image(ink: (UInt8, UInt8, UInt8), paper: (UInt8, UInt8, UInt8)) -> CGImage? {
        guard n > 0 else { return nil }
        var pixels = [UInt8](repeating: 255, count: n * 4)
        for y in 0..<h { for x in 0..<w {
            var val = min(d[y * w + x], 1)
            val = val * val * (3 - 2 * val) * 0.94
            let on = val > Self.bayer[((y & 7) << 3) | (x & 7)]
            let o = (y * w + x) * 4
            let c = on ? ink : paper
            pixels[o] = c.0; pixels[o + 1] = c.1; pixels[o + 2] = c.2
        } }
        let provider = CGDataProvider(data: Data(pixels) as CFData)
        return provider.flatMap {
            CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: w * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                    bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue), provider: $0, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
        }
    }
}

/// The band at the foot of the first-run screens. It follows the pointer without ever taking a click, sleeps when it isn't shown, and with
/// Reduce Motion draws one still frame.
final class FluidDitherView: NSView {
    static let cell: CGFloat = 4
    var active = true { didSet { if active != oldValue { activeChanged() } } }
    var reduceMotion = false

    private let field = FluidField()
    private let imageLayer = CALayer()
    private var link: CADisplayLink?
    private var lastMouse: CGPoint?
    private var lastTick: CFTimeInterval = 0
    private var needsStill = true
    /// The bitmap last drawn (dev snapshots read it: a layer's contents don't show up in cacheDisplay).
    private(set) var lastImage: CGImage?

    override var isFlipped: Bool { false }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.masksToBounds = true
        imageLayer.magnificationFilter = .nearest
        imageLayer.minificationFilter = .nearest
        imageLayer.contentsGravity = .resize
        layer?.addSublayer(imageLayer)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        link?.invalidate(); link = nil
        guard window != nil else { return }
        let l = displayLink(target: self, selector: #selector(tick))
        l.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 60, preferred: 60)
        l.add(to: .main, forMode: .common)
        l.isPaused = !active
        link = l
        needsStill = true
    }

    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); needsStill = true }

    override func layout() {
        super.layout()
        imageLayer.frame = bounds
        let before = (field.w, field.h)
        field.resize(Int(bounds.width / Self.cell), Int(bounds.height / Self.cell))
        if before != (field.w, field.h) { for _ in 0..<160 { field.step(1 / 60, stir: nil) }; needsStill = true }
    }

    private func activeChanged() {
        link?.isPaused = !active
        lastTick = 0
        lastMouse = nil
    }

    private func colours() -> ((UInt8, UInt8, UInt8), (UInt8, UInt8, UInt8)) {
        func rgb(_ c: NSColor) -> (UInt8, UInt8, UInt8) {
            var out: (UInt8, UInt8, UInt8) = (0, 0, 0)
            effectiveAppearance.performAsCurrentDrawingAppearance {
                let s = c.usingColorSpace(.sRGB) ?? c
                out = (UInt8(max(0, min(255, s.redComponent * 255))), UInt8(max(0, min(255, s.greenComponent * 255))), UInt8(max(0, min(255, s.blueComponent * 255))))
            }
            return out
        }
        return (rgb(.ink(.text)), rgb(.ink(.canvas)))
    }

    /// The pointer in field cells (rows count down from the top), and how far it moved since the last frame.
    private func stir() -> FluidField.Stir? {
        guard let window, window.isVisible else { return nil }
        let inWindow = window.convertPoint(fromScreen: NSEvent.mouseLocation)
        let p = convert(inWindow, from: nil)
        defer { lastMouse = p }
        guard let last = lastMouse, bounds.insetBy(dx: -30, dy: -30).contains(p) else { return nil }
        let dx = p.x - last.x, dy = p.y - last.y
        guard abs(dx) + abs(dy) > 0.5 else { return nil }
        // view y runs up, the field's runs down
        return .init(x: Float(p.x / Self.cell), y: Float((bounds.height - p.y) / Self.cell), vx: Float(dx / Self.cell) * 0.6, vy: Float(-dy / Self.cell) * 0.6)
    }

    @objc private func tick() {
        guard active, field.w > 0, window?.occlusionState.contains(.visible) ?? false else { lastTick = 0; return }
        if reduceMotion {
            guard needsStill else { return }
            needsStill = false
        } else {
            let now = CACurrentMediaTime()
            let dt = lastTick == 0 ? 1.0 / 60 : Float(min(now - lastTick, 0.05))
            lastTick = now
            field.step(dt, stir: stir())
        }
        let (ink, paper) = colours()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        lastImage = field.image(ink: ink, paper: paper)
        imageLayer.contents = lastImage
        CATransaction.commit()
    }
}

struct FluidBand: NSViewRepresentable {
    var active: Bool

    func makeNSView(context: Context) -> FluidDitherView {
        let v = FluidDitherView()
        v.reduceMotion = reduceMotionOn
        v.active = active
        return v
    }

    func updateNSView(_ v: FluidDitherView, context: Context) { v.active = active }
}
