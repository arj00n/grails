import AppKit
import GrailsDesign

/// Turns the paintings into pictures of the wall: builds each painting's pixel grid for a window size (off the main thread, cached),
/// composes one frame (the painting, or the dither turning into the next, with the title plate left blank and a slow shimmer over it).
/// The maths is in `PaintingWall`; this is the plumbing. Used by `PaintingWallView` and by the headless demo.
@MainActor
final class PaintingWallEngine {
    struct Frame {
        var base: CGImage
        /// Size of `base` in points (a little larger than the window: whole pixels).
        var baseSize: CGSize
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
    func frame(size: CGSize, t: Double, dark: Bool, reduceMotion: Bool) -> Frame? {
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
        // a slow drift added to every threshold, so pixels near one slowly come and go; none with Reduce Motion
        let shimmer = PaintingWall.Shimmer(t: reduceMotion ? 0 : t, cols: cols, rows: rows)
        let amplitude = reduceMotion ? 0 : Float(PaintingWall.shimmerAmplitude)

        var buffer = [UInt32](repeating: 0, count: cols * rows)
        let table = Self.bayer
        buffer.withUnsafeMutableBufferPointer { out in
            for y in 0..<rows {
                for x in 0..<cols {
                    if x >= pc0 && x < pc1 && y >= pr0 && y < pr1 { continue }
                    let i = y * cols + x
                    let threshold = table[(y & 7) << 3 | (x & 7)] * 0.92 + 0.04 + amplitude * shimmer.value(x: x, y: y)
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
        return Frame(base: base, baseSize: CGSize(width: cols * px, height: rows * px))
    }

    /// For the demo: the frame as one image of the window, canvas behind it.
    func render(size: CGSize, t: Double, dark: Bool, reduceMotion: Bool = false) -> CGImage? {
        guard let f = frame(size: size, t: t, dark: dark, reduceMotion: reduceMotion),
              let ctx = CGContext(data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.setFillColor(dark ? CGColor(gray: 0, alpha: 1) : CGColor(gray: 1, alpha: 1))
        ctx.fill(CGRect(origin: .zero, size: size))
        ctx.interpolationQuality = .none
        // the context's y runs up: the image hangs from the top left
        ctx.draw(f.base, in: CGRect(x: 0, y: size.height - f.baseSize.height, width: f.baseSize.width, height: f.baseSize.height))
        return ctx.makeImage()
    }
}
