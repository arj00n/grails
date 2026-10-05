import AppKit
import GrailsDesign
import SwiftUI

/// Hello's background: coloured dither pixels drifting slowly, stirred by the pointer. One view, one bitmap a frame, 30 frames a second,
/// and still when Reduce Motion is on.
final class AsciiWallView: NSView {
    var reduceMotion = false { didSet { restart() } }
    /// The middle, where the title stands: the field steps back there once the sweep is done (view coordinates, top left origin).
    var centre: CGRect?

    private var link: CADisplayLink?
    private var monitor: Any?
    private var start = CACurrentMediaTime()
    private var trail: [(col: Double, row: Double, at: Double)] = []
    private var lastMove = 0.0

    override var isFlipped: Bool { true }
    override var isOpaque: Bool { false }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    // MARK: Drawing (shared with headless snapshots)

    /// The field is worked out on a coarse grid of cells (10 × 20 pt) and drawn as small dither pixels between them.
    struct Metrics {
        let cellW: CGFloat = 10, cellH: CGFloat = 20
    }

    nonisolated(unsafe) static let metrics = Metrics()

    private static let hueSteps = 24
    /// Dither pixels are this many points square.
    private static let pixel: CGFloat = 4

    private static func rgb(hue: Int, shade: Int, dark: Bool) -> (r: CGFloat, g: CGFloat, b: CGFloat) {
        let h = CGFloat(hue) / CGFloat(hueSteps)
        let (s, b): (CGFloat, CGFloat) = dark ? (0.6, [0.6, 0.82, 1.0][shade]) : (0.5, [0.95, 0.85, 0.74][shade])
        let c = NSColor(hue: h, saturation: s, brightness: b, alpha: 1).usingColorSpace(.sRGB) ?? .white
        return (c.redComponent, c.greenComponent, c.blueComponent)
    }

    /// Paints the field for one moment into `ctx`, which must have its origin at the top left (flipped). Ordered dither in small square pixels.
    static func draw(_ ctx: CGContext, size: CGSize, t: Double, touches: [AsciiField.Touch], dark: Bool, centre: CGRect?) {
        let m = metrics
        let cols = Int(ceil(size.width / m.cellW)), rows = Int(ceil(size.height / m.cellH))
        guard cols > 1, rows > 1 else { return }

        // 1. the field on the character grid
        var value = [Float](repeating: 0, count: cols * rows)
        var tone = [UInt8](repeating: 0, count: cols * rows)            // hue bucket × 3 + shade
        let back = min(max((t - 0.9) / 0.4, 0), 1)
        for row in 0..<rows {
            for col in 0..<cols {
                let reveal = AsciiField.reveal(col: col, row: row, cols: cols, rows: rows, t: t)
                var v = AsciiField.value(col: col, row: row, t: t, touches: touches) * reveal
                if let c = centre, back > 0 {
                    let x = (CGFloat(col) + 0.5) * m.cellW, y = (CGFloat(row) + 0.5) * m.cellH
                    let dx = max(c.minX - x, 0, x - c.maxX), dy = max(c.minY - y, 0, y - c.maxY)
                    let near = 1 - min(max(hypot(dx, dy) / 90, 0), 1)
                    v *= 1 - back * near * near * (3 - 2 * near)
                }
                let hue = Int(AsciiField.hue(col: col, row: row, t: t, touches: touches) * Double(hueSteps)) % hueSteps
                value[row * cols + col] = Float(v)
                tone[row * cols + col] = UInt8(hue * 3 + (v < 0.4 ? 0 : (v < 0.75 ? 1 : 2)))
            }
        }

        // 2. dither: the field, smoothed between cells, against an 8×8 threshold map, one small square per lit pixel
        let px = pixel
        let density = dark ? 1.05 : 0.85
        let pw = Int(ceil(size.width / px)), ph = Int(ceil(size.height / px))
        var table = [UInt32](repeating: 0, count: hueSteps * 3)
        for k in 0..<table.count {
            let c = rgb(hue: k / 3, shade: k % 3, dark: dark)
            table[k] = (UInt32(0.9 * 255) << 24) | (UInt32(c.b * 0.9 * 255) << 16) | (UInt32(c.g * 0.9 * 255) << 8) | UInt32(c.r * 0.9 * 255)
        }
        var pixels = [UInt32](repeating: 0, count: pw * ph)
        pixels.withUnsafeMutableBufferPointer { out in
            for y in 0..<ph {
                let fy = max((CGFloat(y) + 0.5) * px / m.cellH - 0.5, 0)
                let r0 = min(Int(fy), rows - 2), ty = Float(min(fy - CGFloat(r0), 1))
                for x in 0..<pw {
                    let fx = max((CGFloat(x) + 0.5) * px / m.cellW - 0.5, 0)
                    let c0 = min(Int(fx), cols - 2), tx = Float(min(fx - CGFloat(c0), 1))
                    let i = r0 * cols + c0
                    let top = value[i] * (1 - tx) + value[i + 1] * tx, bottom = value[i + cols] * (1 - tx) + value[i + cols + 1] * tx
                    let v = top * (1 - ty) + bottom * ty
                    if Double(v) * density > AsciiField.bayer(x, y) * 0.92 + 0.06 {
                        out[y * pw + x] = table[Int(tone[(ty < 0.5 ? r0 : r0 + 1) * cols + (tx < 0.5 ? c0 : c0 + 1)])]
                    }
                }
            }
        }
        pixels.withUnsafeMutableBytes { raw in
            guard let bitmap = CGContext(data: raw.baseAddress, width: pw, height: ph, bitsPerComponent: 8, bytesPerRow: pw * 4,
                                         space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
                  let image = bitmap.makeImage() else { return }
            ctx.saveGState()
            ctx.interpolationQuality = .none
            // the context is flipped (origin top left); draw the picture upright inside it
            ctx.translateBy(x: 0, y: CGFloat(ph) * px); ctx.scaleBy(x: 1, y: -1)
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: CGFloat(pw) * px, height: CGFloat(ph) * px))
            ctx.restoreGState()
        }
    }

    /// For headless snapshots: the field at time `t` with the pointer at `pointer` (view points) as an image.
    @MainActor static func render(size: CGSize, t: Double, pointer: CGPoint?, dark: Bool, centre: CGRect?) -> CGImage? {
        let scale: CGFloat = 1
        guard let ctx = CGContext(data: nil, width: Int(size.width * scale), height: Int(size.height * scale), bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.translateBy(x: 0, y: size.height * scale); ctx.scaleBy(x: scale, y: -scale)
        let m = metrics
        var touches: [AsciiField.Touch] = []
        if let p = pointer {
            // a short trail up and to the left, as if the pointer had just arrived
            for i in 0..<8 {
                let k = Double(i)
                touches.append(AsciiField.Touch(col: Double(p.x / m.cellW) - k * 1.6, row: Double(p.y / m.cellH) + k * 0.5, age: k * 0.07))
            }
        }
        draw(ctx, size: size, t: t, touches: touches, dark: dark, centre: centre)
        return ctx.makeImage()
    }

    // MARK: Pointer and clock

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
        link?.invalidate(); link = nil
        guard let window else { return }
        start = CACurrentMediaTime()
        window.acceptsMouseMovedEvents = true
        // a local monitor sees the pointer wherever it is in the window, even over the title and button laid on top
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { [weak self] event in
            self?.moved(to: event.locationInWindow, in: event.window)
            return event
        }
        restart()
    }

    private func restart() {
        link?.invalidate(); link = nil
        needsDisplay = true
        guard window != nil, !reduceMotion else { return }
        let l = displayLink(target: self, selector: #selector(tick))
        l.preferredFrameRateRange = CAFrameRateRange(minimum: 20, maximum: 30, preferred: 30)
        l.add(to: .main, forMode: .common)
        link = l
    }

    @objc private func tick() { needsDisplay = true }

    private func moved(to location: NSPoint, in eventWindow: NSWindow?) {
        guard !reduceMotion, eventWindow === window else { return }
        let p = convert(location, from: nil)
        guard bounds.contains(p) else { return }
        let now = CACurrentMediaTime()
        // a point every ~40 ms is plenty for a smooth trail
        guard now - lastMove > 0.04 else { return }
        lastMove = now
        let m = Self.metrics
        trail.append((p.x / m.cellW, p.y / m.cellH, now))
        if trail.count > 40 { trail.removeFirst(trail.count - 40) }
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let now = CACurrentMediaTime()
        trail.removeAll { now - $0.at > AsciiField.touchLife }
        let touches = trail.map { AsciiField.Touch(col: $0.col, row: $0.row, age: now - $0.at) }
        let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        Self.draw(ctx, size: bounds.size, t: reduceMotion ? 10 : now - start, touches: touches, dark: dark, centre: centre)
    }
}

struct AsciiWall: NSViewRepresentable {
    var reduceMotion: Bool
    var centre: CGRect?

    func makeNSView(context: Context) -> AsciiWallView {
        let v = AsciiWallView()
        v.reduceMotion = reduceMotion
        v.centre = centre
        return v
    }

    func updateNSView(_ v: AsciiWallView, context: Context) {
        v.centre = centre
        if v.reduceMotion != reduceMotion { v.reduceMotion = reduceMotion }
    }
}
