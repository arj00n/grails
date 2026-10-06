import CoreGraphics
import Foundation

/// The pointer dragging ink through the title painting, as smoke: dye on a coarse grid carried by a small stable-fluids flow (with a little
/// vorticity, so it curls), rising slowly and thinning out within a couple of seconds, drawn through an 8×8 ordered dither in one colour. The
/// same effect as the website's hero. Positions are in painting pixels (the wall's dither pixels), y down.
final class SmokeField {
    let cols: Int, rows: Int, cell: Int
    private let gw: Int, gh: Int, n: Int
    private var u, v, u0, v0, d, d0, p, div, curl: UnsafeMutablePointer<Float>
    private var pending: [(x: Float, y: Float, vx: Float, vy: Float)] = []
    private(set) var active = false

    init(cols: Int, rows: Int, cell: Int = 3) {
        self.cols = cols; self.rows = rows; self.cell = cell
        gw = max(8, (cols + cell - 1) / cell); gh = max(8, (rows + cell - 1) / cell); n = gw * gh
        func zeros(_ n: Int) -> UnsafeMutablePointer<Float> { let a = UnsafeMutablePointer<Float>.allocate(capacity: n); a.initialize(repeating: 0, count: n); return a }
        let count = gw * gh
        u = zeros(count); v = zeros(count); u0 = zeros(count); v0 = zeros(count); d = zeros(count); d0 = zeros(count); p = zeros(count); div = zeros(count); curl = zeros(count)
    }

    deinit { [u, v, u0, v0, d, d0, p, div, curl].forEach { $0.deallocate() } }

    func stir(x: Float, y: Float, vx: Float, vy: Float) {
        guard abs(vx) + abs(vy) >= 0.3 else { return }
        pending.append((x / Float(cell), y / Float(cell), vx / Float(cell), vy / Float(cell)))
        if pending.count > 24 { pending.removeFirst() }
        active = true
    }

    private func sample(_ a: UnsafeMutablePointer<Float>, _ x: Float, _ y: Float) -> Float {
        let cx = min(max(x, 0), Float(gw) - 1.001), cy = min(max(y, 0), Float(gh) - 1.001)
        let x0 = Int(cx), y0 = Int(cy)
        let fx = cx - Float(x0), fy = cy - Float(y0)
        let i = y0 * gw + x0
        return (a[i] * (1 - fx) + a[i + 1] * fx) * (1 - fy) + (a[i + gw] * (1 - fx) + a[i + gw + 1] * fx) * fy
    }

    private func advect(_ out: UnsafeMutablePointer<Float>, _ src: UnsafeMutablePointer<Float>, _ k: Float) {
        for y in 0..<gh { for x in 0..<gw {
            let i = y * gw + x
            out[i] = sample(src, Float(x) - u[i] * k, Float(y) - v[i] * k)
        } }
    }

    private func project() {
        for y in 1..<(gh - 1) { for x in 1..<(gw - 1) {
            let i = y * gw + x
            div[i] = -0.5 * (u[i + 1] - u[i - 1] + v[i + gw] - v[i - gw])
            p[i] = 0
        } }
        for _ in 0..<12 { for y in 1..<(gh - 1) { for x in 1..<(gw - 1) {
            let i = y * gw + x
            p[i] = (div[i] + p[i - 1] + p[i + 1] + p[i - gw] + p[i + gw]) * 0.25
        } } }
        for y in 1..<(gh - 1) { for x in 1..<(gw - 1) {
            let i = y * gw + x
            u[i] -= 0.5 * (p[i + 1] - p[i - 1])
            v[i] -= 0.5 * (p[i + gw] - p[i - gw])
        } }
    }

    /// Puts back the small curls that advection smooths away, so the smoke wisps and rolls.
    private func confine(_ strength: Float) {
        for y in 1..<(gh - 1) { for x in 1..<(gw - 1) {
            let i = y * gw + x
            curl[i] = (v[i + 1] - v[i - 1]) - (u[i + gw] - u[i - gw])
        } }
        for y in 2..<(gh - 2) { for x in 2..<(gw - 2) {
            let i = y * gw + x
            let gx = abs(curl[i + 1]) - abs(curl[i - 1]), gy = abs(curl[i + gw]) - abs(curl[i - gw])
            let len = (gx * gx + gy * gy).squareRoot() + 1e-5
            u[i] += strength * (gy / len) * curl[i]
            v[i] -= strength * (gx / len) * curl[i]
        } }
    }

    func step(_ dt: Float) {
        guard active else { return }
        let r = max(3, min(6, Float(gw) * 0.03)), r2 = r * r
        for s in pending {
            let fx = s.vx * 0.5, fy = s.vy * 0.5
            let y0 = max(0, Int(s.y - r * 2)), y1 = min(gh, Int(s.y + r * 2) + 1)
            let x0 = max(0, Int(s.x - r * 2)), x1 = min(gw, Int(s.x + r * 2) + 1)
            if y0 < y1, x0 < x1 { for y in y0..<y1 { for x in x0..<x1 {
                let dx = Float(x) - s.x, dy = Float(y) - s.y
                let w = exp(-(dx * dx + dy * dy) / r2)
                let i = y * gw + x
                u[i] += fx * w; v[i] += fy * w
                d[i] = min(1, d[i] + w * 0.75)
            } } }
        }
        pending.removeAll(keepingCapacity: true)
        let damp = pow(0.975, dt * 60), fade = pow(0.985, dt * 60)
        for i in 0..<n {
            v[i] -= (0.01 + d[i] * 0.05) * dt * 6          // smoke is lighter than air: it drifts up
            u[i] *= damp; v[i] *= damp
        }
        confine(0.35 * dt * 60)
        project()
        let k = dt * 60 * 0.9
        advect(u0, u, k); advect(v0, v, k)
        swap(&u, &u0); swap(&v, &v0)
        project()
        advect(d0, d, k)
        swap(&d, &d0)
        var peak: Float = 0
        for i in 0..<n { d[i] *= fade; peak = max(peak, d[i]) }
        if peak < 0.05 {        // gone: nothing left to draw
            for i in 0..<n { d[i] = 0; u[i] = 0; v[i] = 0 }
            active = false
        }
    }

    /// The smoke as a bitmap the size of the wall in dither pixels: `ink` (opaque RGBA word) where the dithered density says so, clear elsewhere.
    func image(ink: UInt32) -> CGImage? {
        var pixels = [UInt32](repeating: 0, count: cols * rows)
        let lastX = Float(gw) - 1.001, lastY = Float(gh) - 1.001
        for y in 0..<rows {
            let gy = min(max(Float(y) / Float(cell) - 0.5, 0), lastY)
            let y0 = Int(gy), fy = gy - Float(y0), tb = (y & 7) << 3
            for x in 0..<cols {
                let gx = min(max(Float(x) / Float(cell) - 0.5, 0), lastX)
                let x0 = Int(gx), fx = gx - Float(x0), j = y0 * gw + x0
                var s = d[j] * (1 - fx) * (1 - fy) + d[j + 1] * fx * (1 - fy) + d[j + gw] * (1 - fx) * fy + d[j + gw + 1] * fx * fy
                if s < 0.02 { continue }
                s = min(s, 1); s = s * s * (3 - 2 * s) * 0.94
                if s > FluidField.bayer[tb | (x & 7)] { pixels[y * cols + x] = ink }
            }
        }
        let data = pixels.withUnsafeBufferPointer { Data(buffer: $0) }
        return CGDataProvider(data: data as CFData).flatMap {
            CGImage(width: cols, height: rows, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: cols * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                    bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue), provider: $0, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
        }
    }
}
