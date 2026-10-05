import AppKit
import GrailsDesign

/// Turns the paintings into pictures of the wall: builds each painting's pixel grid for a window size (off the main thread, cached),
/// composes one frame (the painting, or the dither turning into the next, with the title plate left blank) and the pointer's reveal on top.
/// The maths is in `PaintingWall`; this is the plumbing. Used by `PaintingWallView` and by the headless demo.
@MainActor
final class PaintingWallEngine {
    struct Frame {
        var base: CGImage
        /// Size of `base` in points (a little larger than the window: whole pixels).
        var baseSize: CGSize
        var loupe: (image: CGImage, rect: CGRect)?
        /// More frames will differ soon: an intro, a transition, or a pointer trail still fading.
        var animating: Bool
    }

    static let shared = PaintingWallEngine()

    let specs: [PaintingWall.Spec]
    private let dir: URL
    /// Called on the main thread when a grid finishes building.
    var onReady: (() -> Void)?

    private struct Key: Hashable { var index: Int, cols: Int, rows: Int, pixel: Int }
    private var grids: [Key: PaintingWall.Grid] = [:]
    private var pending = Set<Key>()
    private var tints: [Int: [UInt32]] = [:]
    private var falloffs: [Int: [Float]] = [:]
    private var sources: [Int: Source] = [:]
    private static let bayer: [Float] = (0..<64).map { Float(Dither.bayer($0 % 8, $0 / 8)) }

    init?() {
        guard let dir = Bundle.main.resourceURL?.appendingPathComponent("Paintings"),
              let data = try? Data(contentsOf: dir.appendingPathComponent("manifest.json")),
              let manifest = try? JSONDecoder().decode(PaintingWall.Manifest.self, from: data), !manifest.paintings.isEmpty else { return nil }
        self.dir = dir
        specs = manifest.paintings
    }

    // MARK: Grids

    private func key(_ index: Int, _ size: CGSize, pixel: Int) -> Key {
        Key(index: index, cols: Int((size.width / CGFloat(pixel)).rounded(.up)), rows: Int((size.height / CGFloat(pixel)).rounded(.up)), pixel: pixel)
    }

    func grid(_ index: Int, size: CGSize, pixel: Int = PaintingWall.pixel) -> PaintingWall.Grid? { grids[key(index, size, pixel: pixel)] }

    /// Starts building a grid in the background, unless it exists or is on its way.
    func request(_ index: Int, size: CGSize, pixel: Int = PaintingWall.pixel) {
        let k = key(index, size, pixel: pixel)
        guard grids[k] == nil, !pending.contains(k), specs.indices.contains(index) else { return }
        pending.insert(k)
        let spec = specs[index], url = dir.appendingPathComponent(spec.file)
        Task.detached(priority: .userInitiated) {
            let grid = Self.build(spec: spec, url: url, size: size, pixel: pixel)
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.pending.remove(k)
                if let grid { self.store(grid, for: k) }
                self.onReady?()
            }
        }
    }

    /// For the demo and benchmark: builds now, on this thread.
    func prepare(_ index: Int, size: CGSize, pixel: Int = PaintingWall.pixel) {
        let k = key(index, size, pixel: pixel)
        guard grids[k] == nil, specs.indices.contains(index) else { return }
        if let g = Self.build(spec: specs[index], url: dir.appendingPathComponent(specs[index].file), size: size, pixel: pixel) { store(g, for: k) }
    }

    private func store(_ grid: PaintingWall.Grid, for k: Key) {
        // a different window size makes the old grids useless
        for old in grids.keys where old.cols != k.cols || old.rows != k.rows { if old.pixel == k.pixel || grids.count > 24 { grids[old] = nil } }
        grids[k] = grid
    }

    nonisolated private static func build(spec: PaintingWall.Spec, url: URL, size: CGSize, pixel: Int) -> PaintingWall.Grid? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil), let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        let cols = Int((size.width / CGFloat(pixel)).rounded(.up)), rows = Int((size.height / CGFloat(pixel)).rounded(.up))
        guard cols > 1, rows > 1 else { return nil }
        let frame = PaintingWall.frame(spec, window: size), px = CGFloat(pixel)
        var bytes = [UInt8](repeating: 0, count: cols * rows * 4)
        let drawn = bytes.withUnsafeMutableBytes { raw -> Bool in
            guard let ctx = CGContext(data: raw.baseAddress, width: cols, height: rows, bitsPerComponent: 8, bytesPerRow: cols * 4,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.interpolationQuality = .high
            // memory row 0 is the top of the window; the context's y runs up
            ctx.draw(image, in: CGRect(x: frame.minX / px, y: CGFloat(rows) - frame.maxY / px, width: frame.width / px, height: frame.height / px))
            return true
        }
        guard drawn else { return nil }
        return PaintingWall.Grid.build(rgba: bytes, cols: cols, rows: rows, pixel: pixel, spec: spec, frame: frame)
    }

    // MARK: The painting itself (for the reveal under the pointer)

    /// A painting's own pixels, 8-bit RGBA, for sampling with true colour.
    private struct Source {
        var width: Int, height: Int
        var bytes: [UInt8]

        /// Bilinear sample at (u, v) in source pixels, as 0...255 red, green, blue.
        func rgb(u: Double, v: Double) -> (r: Double, g: Double, b: Double) {
            let x = min(max(u - 0.5, 0), Double(width - 1) - 0.001), y = min(max(v - 0.5, 0), Double(height - 1) - 0.001)
            let x0 = Int(x), y0 = Int(y), fx = x - Double(x0), fy = y - Double(y0)
            let i00 = (y0 * width + x0) * 4, i10 = i00 + 4, i01 = i00 + width * 4, i11 = i01 + 4
            func ch(_ o: Int) -> Double {
                let top = Double(bytes[i00 + o]) * (1 - fx) + Double(bytes[i10 + o]) * fx
                let bottom = Double(bytes[i01 + o]) * (1 - fx) + Double(bytes[i11 + o]) * fx
                return top * (1 - fy) + bottom * fy
            }
            return (ch(0), ch(1), ch(2))
        }
    }

    private func source(_ index: Int) -> Source? {
        if let s = sources[index] { return s }
        guard specs.indices.contains(index), let src = CGImageSourceCreateWithURL(dir.appendingPathComponent(specs[index].file) as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return nil }
        let w = image.width, h = image.height
        var bytes = [UInt8](repeating: 0, count: w * h * 4)
        let ok = bytes.withUnsafeMutableBytes { raw -> Bool in
            guard let ctx = CGContext(data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard ok else { return nil }
        if sources.count >= 3 { sources.removeAll() }
        let s = Source(width: w, height: h, bytes: bytes)
        sources[index] = s
        return s
    }

    /// How much of the painting shows at each pixel: 0 on the plate, easing to 1 around it.
    private func falloff(cols: Int, rows: Int, plate: CGRect) -> [Float] {
        let k = cols << 16 | rows
        if let f = falloffs[k] { return f }
        let px = Double(PaintingWall.pixel)
        var f = [Float](repeating: 1, count: cols * rows)
        let reach = Int(PaintingWall.plateFalloff / px) + 2
        let x0 = max(Int(plate.minX / px) - reach, 0), x1 = min(Int(plate.maxX / px) + reach, cols), y0 = max(Int(plate.minY / px) - reach, 0), y1 = min(Int(plate.maxY / px) + reach, rows)
        for y in y0..<max(y1, y0) { for x in x0..<max(x1, x0) { f[y * cols + x] = Float(PaintingWall.falloff(x: (Double(x) + 0.5) * px, y: (Double(y) + 0.5) * px, plate: plate)) } }
        falloffs[k] = f
        return f
    }

    // MARK: Frames

    private func tint(_ index: Int, dark: Bool) -> [UInt32] {
        let k = index * 2 + (dark ? 1 : 0)
        if let t = tints[k] { return t }
        let t = PaintingWall.litColours(palette: specs[index].palette, dark: dark)
        tints[k] = t
        return t
    }

    private static func image(_ buffer: inout [UInt32], width: Int, height: Int) -> CGImage? {
        buffer.withUnsafeMutableBytes { raw in
            CGContext(data: raw.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                      space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)?.makeImage()
        }
    }

    /// One frame at `t` seconds. Nil while the first painting's grid is still being built (it asks for it, and `onReady` fires).
    func frame(size: CGSize, t: Double, dark: Bool, reduceMotion: Bool, touches: [PaintingWall.Touch]) -> Frame? {
        guard size.width > 8, size.height > 8 else { return nil }
        let px = PaintingWall.pixel
        let cols = Int((size.width / CGFloat(px)).rounded(.up)), rows = Int((size.height / CGFloat(px)).rounded(.up))
        let sched = PaintingWall.schedule(t: t, count: specs.count, reduceMotion: reduceMotion)
        let intro = !reduceMotion && t < PaintingWall.introStart + PaintingWall.introDuration

        var fromIdx: Int?, toIdx = sched.index
        var progress: Double?
        if intro { progress = PaintingWall.intro(t: t) }
        else if let p = sched.progress { fromIdx = sched.index; toIdx = sched.next; progress = p }

        request(toIdx, size: size)
        if let f = fromIdx { request(f, size: size) }
        if progress == nil || intro { request(sched.next, size: size) }
        guard let gTo = grid(toIdx, size: size) else { return nil }
        let gFrom = fromIdx.flatMap { grid($0, size: size) }
        if fromIdx != nil, gFrom == nil { return nil }

        let plate = PaintingWall.plate(window: size)
        let pc0 = Int(plate.minX) / px, pc1 = Int(plate.maxX) / px, pr0 = Int(plate.minY) / px, pr1 = Int(plate.maxY) / px
        let fade = falloff(cols: cols, rows: rows, plate: plate)
        let toTint = tint(toIdx, dark: dark), fromTint = fromIdx.map { tint($0, dark: dark) } ?? toTint
        let toInk = dark ? gTo.inkDark : gTo.inkLight, fromInk = gFrom.map { dark ? $0.inkDark : $0.inkLight }
        let toColour = gTo.colour, fromColour = gFrom?.colour
        let e = progress.map(PaintingWall.ease)

        var buffer = [UInt32](repeating: 0, count: cols * rows)
        let table = Self.bayer
        buffer.withUnsafeMutableBufferPointer { out in
            for y in 0..<rows {
                for x in 0..<cols {
                    if x >= pc0 && x < pc1 && y >= pr0 && y < pr1 { continue }
                    let i = y * cols + x
                    let threshold = table[(y & 7) << 3 | (x & 7)] * 0.92 + 0.04
                    if let e {
                        // the old and new inks blend (so the dither pattern itself changes), and each pixel takes the new colour
                        // once the blend passes its own noise value
                        let a = fromInk.map { Float($0[i]) } ?? 0, b = Float(toInk[i])
                        let ink = (e >= 1 ? b : a + (b - a) * Float(e)) / 255 * fade[i]
                        if ink > threshold {
                            let useTo = fromColour == nil || e >= 1 || (e > 0 && Dither.noise(x, y) < e)
                            out[i] = useTo ? toTint[Int(toColour[i])] : fromTint[Int(fromColour![i])]
                        }
                    } else if Float(toInk[i]) / 255 * fade[i] > threshold {
                        out[i] = toTint[Int(toColour[i])]
                    }
                }
            }
        }
        guard let base = Self.image(&buffer, width: cols, height: rows) else { return nil }
        var result = Frame(base: base, baseSize: CGSize(width: cols * px, height: rows * px), loupe: nil, animating: progress != nil || !touches.isEmpty)

        if !touches.isEmpty {
            result.loupe = loupe(touches: touches, size: size, plate: plate, to: toIdx, from: fromIdx, blend: e)
        }
        return result
    }

    /// The painting itself, in true colour, under the pointer and its trail: a soft-edged window onto the picture the dither stands for.
    /// During a transition it shows the two paintings blended, like the dither does.
    private func loupe(touches: [PaintingWall.Touch], size: CGSize, plate: CGRect, to: Int, from: Int?, blend e: Double?) -> (image: CGImage, rect: CGRect)? {
        guard let srcTo = source(to) else { return nil }
        let srcFrom = from.flatMap { source($0) }
        let frameTo = PaintingWall.frame(specs[to], window: size), frameFrom = from.map { PaintingWall.frame(specs[$0], window: size) } ?? frameTo
        let r = PaintingWall.loupeRadius
        let live = touches.filter { $0.age <= PaintingWall.loupeLife }
        guard !live.isEmpty else { return nil }
        let minX = max(Int((live.map(\.x).min()! - r).rounded(.down)), 0), maxX = min(Int((live.map(\.x).max()! + r).rounded(.up)), Int(size.width))
        let minY = max(Int((live.map(\.y).min()! - r).rounded(.down)), 0), maxY = min(Int((live.map(\.y).max()! + r).rounded(.up)), Int(size.height))
        let w = maxX - minX, h = maxY - minY
        guard w > 0, h > 0, w * h <= 400_000 else { return nil }
        let mix = srcFrom == nil ? 1 : (e ?? 1)
        var buffer = [UInt32](repeating: 0, count: w * h)
        buffer.withUnsafeMutableBufferPointer { out in
            for fy in 0..<h {
                let Y = minY + fy
                for fx in 0..<w {
                    let X = minX + fx
                    let q = PaintingWall.influence(x: Double(X) + 0.5, y: Double(Y) + 0.5, touches: live)
                    if q <= 0 { continue }
                    if Double(X) >= plate.minX && Double(X) < plate.maxX && Double(Y) >= plate.minY && Double(Y) < plate.maxY { continue }
                    var c = srcTo.rgb(u: (Double(X) + 0.5 - Double(frameTo.minX)) / Double(frameTo.width) * Double(srcTo.width),
                                      v: (Double(Y) + 0.5 - Double(frameTo.minY)) / Double(frameTo.height) * Double(srcTo.height))
                    if mix < 1, let srcFrom {
                        let o = srcFrom.rgb(u: (Double(X) + 0.5 - Double(frameFrom.minX)) / Double(frameFrom.width) * Double(srcFrom.width),
                                            v: (Double(Y) + 0.5 - Double(frameFrom.minY)) / Double(frameFrom.height) * Double(srcFrom.height))
                        c = (o.r + (c.r - o.r) * mix, o.g + (c.g - o.g) * mix, o.b + (c.b - o.b) * mix)
                    }
                    let a = min(q * 1.6, 1), alpha = a * a * (3 - 2 * a)
                    out[fy * w + fx] = UInt32(alpha * 255 + 0.5) << 24 | UInt32(c.b * alpha + 0.5) << 16 | UInt32(c.g * alpha + 0.5) << 8 | UInt32(c.r * alpha + 0.5)
                }
            }
        }
        guard let image = Self.image(&buffer, width: w, height: h) else { return nil }
        return (image, CGRect(x: minX, y: minY, width: w, height: h))
    }

    /// For the demo: the frame as one image of the window, canvas behind it.
    func render(size: CGSize, t: Double, dark: Bool, touches: [PaintingWall.Touch] = [], reduceMotion: Bool = false) -> CGImage? {
        guard let f = frame(size: size, t: t, dark: dark, reduceMotion: reduceMotion, touches: touches),
              let ctx = CGContext(data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.setFillColor(dark ? CGColor(gray: 0, alpha: 1) : CGColor(gray: 1, alpha: 1))
        ctx.fill(CGRect(origin: .zero, size: size))
        ctx.interpolationQuality = .none
        // the context's y runs up: the image hangs from the top left
        ctx.draw(f.base, in: CGRect(x: 0, y: size.height - f.baseSize.height, width: f.baseSize.width, height: f.baseSize.height))
        if let l = f.loupe { ctx.draw(l.image, in: CGRect(x: l.rect.minX, y: size.height - l.rect.maxY, width: l.rect.width, height: l.rect.height)) }
        return ctx.makeImage()
    }
}
