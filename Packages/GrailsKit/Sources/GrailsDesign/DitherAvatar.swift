import AppKit

/// One colour a generated avatar can take: the blob's body and a deeper shade of it, each for light and dark mode.
/// The face is ink on the body; every base keeps ink at 4.5:1 or better, so an expression reads at 20 pt.
public struct DitherAvatarTone: Sendable, Equatable {
    public var name: String
    public var light: (base: UInt32, deep: UInt32)
    public var dark: (base: UInt32, deep: UInt32)

    public func base(dark isDark: Bool) -> UInt32 { isDark ? dark.base : light.base }
    public func deep(dark isDark: Bool) -> UInt32 { isDark ? dark.deep : light.deep }
    /// The highlight at the top left: the base taken 40% of the way to white.
    public func lit(dark isDark: Bool) -> UInt32 { DitherAvatar.mix(base(dark: isDark), 0xFFFFFF, 0.4) }

    public static func == (a: Self, b: Self) -> Bool {
        a.name == b.name && a.light == b.light && a.dark == b.dark
    }
}

/// The face on a blob. Each part is picked from the expression seed, so one seed is always one face.
public struct BlobFace: Hashable, Sendable {
    public enum Eyes: Int, CaseIterable, Sendable { case round, sparkle, wide, side, closed, happy, wink, angry }
    public enum Mouth: Int, CaseIterable, Sendable { case smile, grin, open, small, flat, smirk, none }
    /// Angry and side eyes carry their own brow or lid, so they always have `none` here.
    public enum Brows: Int, CaseIterable, Sendable { case none, raised, worried }

    public var eyes: Eyes
    public var mouth: Mouth
    public var brows: Brows
    public var cheeks: Bool
    /// Small nudges, 0..<3 each: how far apart the eyes sit, how low the face sits, and which way it turns (left, centre, right).
    public var spread: Int
    public var drop: Int
    public var turn: Int

    public init(seed: UInt64) {
        var bits = DitherAvatar.mix(seed)
        func pick(_ n: Int) -> Int {
            let v = Int(bits % UInt64(n))
            bits /= UInt64(n)
            return v
        }
        eyes = Eyes(rawValue: pick(Eyes.allCases.count))!
        mouth = Mouth(rawValue: pick(Mouth.allCases.count))!
        brows = Brows(rawValue: max(0, pick(5) - 2))!
        cheeks = pick(2) == 1
        spread = pick(3)
        drop = pick(3)
        turn = pick(3)
        if eyes == .angry || eyes == .side { brows = .none }
    }

    /// How many different faces there are, before the colour.
    public static let combinations = ((Eyes.allCases.count - 2) * Brows.allCases.count + 2) * Mouth.allCases.count * 2 * 3 * 3 * 3
}

/// What a generated avatar shows. The same member id gives the same face and colour on every Mac and every launch.
public struct DitherAvatarSpec: Hashable, Sendable {
    public var seed: UInt64
    /// Picks the face. The member's own (from Shuffle) or, by default, the id's seed.
    public var character: UInt64
    public var tone: Int

    /// `tint` and `character` are the member's own choices; nil derives them from the id (the name when there is no id).
    public init(memberID: String, name: String, tint: Int? = nil, character: Int? = nil) {
        let key = memberID.isEmpty ? name.lowercased() : memberID
        seed = DitherAvatar.seed(key)
        self.character = character.map { UInt64(truncatingIfNeeded: $0) } ?? seed
        tone = DitherAvatar.toneIndex(seed: seed, chosen: tint)
    }

    public var face: BlobFace { BlobFace(seed: character) }
}

/// A generated avatar: a round blob that fills the circle, with a face. The body is shaded in 1-bit ordered (8×8 Bayer) dither,
/// lighter at the top left and deeper at the bottom right, in chunky cells. The face is drawn per device pixel in solid ink, paper
/// and blush, so it stays crisp at 20 pt. Rendered once per size, scale and appearance into a `CGImage` and cached, so showing it
/// costs a `layer.contents` assignment.
public enum DitherAvatar {
    /// Bold tones that sit beside the neutral chrome. The order is part of the stored choice (`AvatarLook.tint`): append only.
    public static let tones: [DitherAvatarTone] = [
        .init(name: "Clay", light: (0xF26B4F, 0xC9472F), dark: (0xE0583D, 0xB23F29)),
        .init(name: "Ochre", light: (0xF5B323, 0xD08A0F), dark: (0xE09E17, 0xB5760C)),
        .init(name: "Moss", light: (0x9BCB3C, 0x6E9E22), dark: (0x86B52F, 0x5E8A1C)),
        .init(name: "Teal", light: (0x2EC4B0, 0x169482), dark: (0x22AD9B, 0x13806F)),
        .init(name: "Blue", light: (0x4F8EF7, 0x2D63D1), dark: (0x4A86EE, 0x2856BA)),
        .init(name: "Iris", light: (0x9A7CF2, 0x7052D6), dark: (0x9472EA, 0x6246C2)),
        .init(name: "Rose", light: (0xF46FA6, 0xD0477F), dark: (0xE65C95, 0xBA3D6F)),
        .init(name: "Graphite", light: (0x9AA1B3, 0x6F7689), dark: (0x8A91A3, 0x636A7D)),
        .init(name: "Tangerine", light: (0xFF8A2B, 0xD9661A), dark: (0xF07A1E, 0xC05A15)),
        .init(name: "Fern", light: (0x3FC27A, 0x23945A), dark: (0x2FAE69, 0x1F834F)),
        .init(name: "Sky", light: (0x3DB4F2, 0x1B87C6), dark: (0x2BA2E0, 0x1777B0)),
        .init(name: "Orchid", light: (0xD173E6, 0xA64BBF), dark: (0xC060D6, 0x9441AC)),
        .init(name: "Cocoa", light: (0xC9925F, 0x9C6A3F), dark: (0xB98251, 0x8A5D36)),
        .init(name: "Cherry", light: (0xF2545F, 0xC93440), dark: (0xEA505A, 0xB52C38)),
    ]
    /// Eyes, brows and mouths.
    public static let ink: UInt32 = 0x1E1A22
    /// Eye whites and catchlights.
    public static let paper: UInt32 = 0xFFFBF2
    /// Cheeks and tongues.
    public static let blush: UInt32 = 0xFF8FA3
    /// About this many dither cells across at large sizes; small sizes use one device pixel per cell.
    public static let cellsAcross = 24.0

    /// FNV-1a, 64-bit. `hashValue` is reseeded every launch, so it cannot pick a look that has to stay put.
    public static func seed(_ key: String) -> UInt64 {
        var h: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in key.utf8 {
            h ^= UInt64(byte)
            h = h &* 0x0000_0100_0000_01B3
        }
        return h
    }

    /// SplitMix64's finaliser: spreads a seed's bits so neighbouring seeds pick unrelated parts.
    public static func mix(_ x: UInt64) -> UInt64 {
        var z = x &+ 0x9E37_79B9_7F4A_7C15
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// `a` taken `t` of the way to `b`, per channel.
    public static func mix(_ a: UInt32, _ b: UInt32, _ t: Double) -> UInt32 {
        var out: UInt32 = 0
        for shift: UInt32 in [16, 8, 0] {
            let x = Double((a >> shift) & 0xFF), y = Double((b >> shift) & 0xFF)
            out |= UInt32((x + (y - x) * t).rounded()) << shift
        }
        return out
    }

    public static func toneIndex(seed: UInt64, chosen: Int?) -> Int {
        if let chosen, tones.indices.contains(chosen) { return chosen }
        return Int(seed % UInt64(tones.count))
    }

    /// Device pixels per dither cell for an avatar `px` pixels across.
    public static func cellSize(px: Int) -> Int { max(1, Int((Double(px) / cellsAcross).rounded())) }

    /// What a cell or pixel prints. The body is base, deep or lit; the face is ink, paper or blush.
    public enum Ink: UInt8, Sendable { case base, deep, lit, ink, paper, blush }

    /// How much of the body prints deep toward the bottom right, and lit at the top left (0...1, before dithering).
    public static let shadeInk = (deep: 0.7, lit: 0.6)

    /// The body's shading for the cell at `x`, `y` on an `n` × `n` grid.
    static func shade(x: Int, y: Int, n: Int) -> Ink {
        let u = (Double(x) + 0.5) / Double(n), v = (Double(y) + 0.5) / Double(n)
        let dx = (u - 0.5) / 0.5, dy = (v - 0.5) / 0.5
        let toward = (dx + dy) / 2.squareRoot() // along the light, top left (-) to bottom right (+)
        let deep = shadeInk.deep * ramp(0.6 * toward + 0.5 * hypot(dx, dy), from: 0.5, to: 1.1)
        if deep > 0 { return Dither.lit(ink: deep, x: x, y: y) ? .deep : .base }
        let lit = shadeInk.lit * ramp(1 - hypot(u - 0.33, v - 0.3) / 0.24, from: 0, to: 0.6)
        return Dither.lit(ink: lit, x: x, y: y) ? .lit : .base
    }

    static func ramp(_ x: Double, from a: Double, to b: Double) -> Double { max(0, min(1, (x - a) / (b - a))) }

    /// The blob on an `n` × `n` cell grid, row 0 at the top, one ink per cell. The face is point-sampled at the cell centres.
    public static func cells(_ spec: DitherAvatarSpec, n: Int) -> [Ink] {
        let n = max(1, n)
        let plan = FacePlan(spec.face, px: n)
        var out = [Ink](repeating: .base, count: n * n)
        for y in 0..<n {
            for x in 0..<n {
                let p = (u: (Double(x) + 0.5) / Double(n), v: (Double(y) + 0.5) / Double(n))
                out[y * n + x] = plan.ink(p) ?? shade(x: x, y: y, n: n)
            }
        }
        return out
    }

    private nonisolated(unsafe) static let cache: NSCache<NSString, CGImage> = {
        let c = NSCache<NSString, CGImage>()
        c.countLimit = 512
        return c
    }()

    /// The avatar at `side` points. Cached; the first call per key draws about `side × scale` squared pixels once.
    public static func image(_ spec: DitherAvatarSpec, side: CGFloat, scale: CGFloat, dark: Bool) -> CGImage? {
        let px = max(1, Int((side * scale).rounded()))
        let cell = cellSize(px: px)
        let key = "\(spec.character)|\(spec.tone)|\(px)|\(dark)" as NSString
        if let hit = cache.object(forKey: key) { return hit }
        let n = (px + cell - 1) / cell
        var body = [Ink](repeating: .base, count: n * n)
        for y in 0..<n { for x in 0..<n { body[y * n + x] = shade(x: x, y: y, n: n) } }
        let tone = tones[toneIndex(seed: spec.seed, chosen: spec.tone)]
        let palette: [UInt32] = [tone.base(dark: dark), tone.deep(dark: dark), tone.lit(dark: dark), ink, paper, blush] // by `Ink` raw value
        let plan = FacePlan(spec.face, px: px)
        // the grid is centred, so a partial cell at the edge is split between both sides
        let offset = (n * cell - px) / 2
        let samples = 3 // per side: the face's edges are smoothed over 3×3 points a pixel
        var pixels = [UInt8](repeating: 255, count: px * px * 4)
        for y in 0..<px {
            let row = min(n - 1, (y + offset) / cell) * n
            for x in 0..<px {
                let under = palette[Int(body[row + min(n - 1, (x + offset) / cell)].rawValue)]
                var sum = (r: 0, g: 0, b: 0)
                for sy in 0..<samples {
                    for sx in 0..<samples {
                        let p = (u: (Double(x) + (Double(sx) + 0.5) / Double(samples)) / Double(px),
                                 v: (Double(y) + (Double(sy) + 0.5) / Double(samples)) / Double(px))
                        let hex = plan.ink(p).map { palette[Int($0.rawValue)] } ?? under
                        sum.r += Int((hex >> 16) & 0xFF)
                        sum.g += Int((hex >> 8) & 0xFF)
                        sum.b += Int(hex & 0xFF)
                    }
                }
                let count = samples * samples, i = (y * px + x) * 4
                pixels[i] = UInt8(sum.r / count)
                pixels[i + 1] = UInt8(sum.g / count)
                pixels[i + 2] = UInt8(sum.b / count)
            }
        }
        let made: CGImage? = pixels.withUnsafeMutableBytes { raw in
            CGContext(data: raw.baseAddress, width: px, height: px, bitsPerComponent: 8, bytesPerRow: px * 4,
                      space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)?.makeImage()
        }
        if let made { cache.setObject(made, forKey: key) }
        return made
    }

    /// WCAG contrast between two hex colours.
    public static func contrast(_ a: UInt32, _ b: UInt32) -> Double {
        func luminance(_ h: UInt32) -> Double {
            func lin(_ v: UInt32) -> Double {
                let c = Double(v) / 255
                return c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
            }
            return 0.2126 * lin((h >> 16) & 0xFF) + 0.7152 * lin((h >> 8) & 0xFF) + 0.0722 * lin(h & 0xFF)
        }
        let (x, y) = (luminance(a), luminance(b))
        return (max(x, y) + 0.05) / (min(x, y) + 0.05)
    }
}

/// The face's geometry in unit space (0...1, y down; the blob is the whole circle), sized for `px` pixels across so strokes,
/// pupils and catchlights never thin below a pixel.
private struct FacePlan {
    let f: BlobFace
    let px: Double
    /// Half a stroke.
    let line: Double
    let fx: Double, eyeY: Double, eyeDX: Double, mouthY: Double
    /// Which way the face turns: -1 left, 0 ahead, 1 right.
    let look: Double

    init(_ f: BlobFace, px: Int) {
        self.f = f
        self.px = Double(px)
        line = max(0.034, 0.7 / Double(px))
        look = Double(f.turn - 1)
        fx = 0.5 + 0.04 * look
        eyeY = 0.41 + 0.025 * Double(f.drop)
        eyeDX = 0.15 + 0.022 * Double(f.spread)
        mouthY = eyeY + 0.215
    }

    private var minR: Double { 0.6 / px }

    private func disc(_ p: (u: Double, v: Double), _ x: Double, _ y: Double, _ r: Double) -> Bool {
        hypot(p.u - x, p.v - y) <= max(r, minR)
    }

    private func ellipse(_ p: (u: Double, v: Double), _ x: Double, _ y: Double, _ rx: Double, _ ry: Double) -> Bool {
        let a = (p.u - x) / max(rx, minR), b = (p.v - y) / max(ry, minR)
        return a * a + b * b <= 1
    }

    /// A stroke along part of a circle. Angles in radians, 0 is right, positive is down.
    private func arc(_ p: (u: Double, v: Double), _ x: Double, _ y: Double, _ r: Double, from a0: Double, to a1: Double) -> Bool {
        let a = atan2(p.v - y, p.u - x)
        if a >= a0 && a <= a1 { return abs(hypot(p.u - x, p.v - y) - r) <= line }
        // round caps
        return disc(p, x + r * cos(a0), y + r * sin(a0), line) || disc(p, x + r * cos(a1), y + r * sin(a1), line)
    }

    private func segment(_ p: (u: Double, v: Double), _ a: (Double, Double), _ b: (Double, Double), _ half: Double? = nil) -> Bool {
        let (ax, ay) = a, (bx, by) = b
        let vx = bx - ax, vy = by - ay
        let t = max(0, min(1, ((p.u - ax) * vx + (p.v - ay) * vy) / (vx * vx + vy * vy)))
        return hypot(p.u - (ax + t * vx), p.v - (ay + t * vy)) <= (half ?? line)
    }

    /// The face's ink at `p`, or nil for the body.
    func ink(_ p: (u: Double, v: Double)) -> DitherAvatar.Ink? {
        for s in [-1.0, 1.0] {
            if let e = eye(p, side: s) { return e }
        }
        if let m = mouth(p) { return m }
        if f.cheeks {
            for s in [-1.0, 1.0] where ellipse(p, fx + s * (eyeDX + 0.06), eyeY + 0.11, 0.06, 0.036) { return .blush }
        }
        return nil
    }

    /// One eye and its brow. `s` is -1 for the left eye, 1 for the right.
    private func eye(_ p: (u: Double, v: Double), side s: Double) -> DitherAvatar.Ink? {
        let ex = fx + s * eyeDX
        if let b = brow(p, ex: ex, side: s) { return b }
        switch f.eyes {
        case .round:
            return dot(p, ex)
        case .sparkle:
            guard ellipse(p, ex, eyeY, 0.098, 0.114) else { return nil }
            return disc(p, ex - 0.031, eyeY - 0.039, 0.039) || disc(p, ex + 0.034, eyeY + 0.042, 0.017) ? .paper : .ink
        case .wide:
            let pupil = ex + 0.023 * look
            guard disc(p, ex, eyeY, 0.111) else { return nil }
            if disc(p, pupil - 0.018, eyeY - 0.021, 0.018) { return .paper }
            return disc(p, pupil, eyeY, 0.06) ? .ink : .paper
        case .side:
            // half-lidded, both pupils off to one side
            let lid = eyeY - 0.029
            if segment(p, (ex - 0.111, lid), (ex + 0.111, lid)) { return .ink }
            guard p.v > lid, ellipse(p, ex, eyeY, 0.117, 0.091) else { return nil }
            return disc(p, ex + 0.058 * (look == 0 ? 1 : look), eyeY + 0.013, 0.055) ? .ink : .paper
        case .closed:
            return arc(p, ex, eyeY - 0.046, 0.072, from: 0.15 * .pi, to: 0.85 * .pi) ? .ink : nil
        case .happy:
            return happyArc(p, ex) ? .ink : nil
        case .wink:
            return s < 0 ? dot(p, ex) : (happyArc(p, ex) ? .ink : nil)
        case .angry:
            // a lowered brow cuts the top of a white eye: high at the outside, low at the inside
            let outer = (ex + s * 0.13, eyeY - 0.117), inner = (ex - s * 0.104, eyeY - 0.033)
            if segment(p, outer, inner, line * 1.2) { return .ink }
            let t = (p.u - outer.0) / (inner.0 - outer.0)
            let browY = outer.1 + (inner.1 - outer.1) * t
            guard p.v > browY, disc(p, ex, eyeY, 0.101) else { return nil }
            return disc(p, ex - s * 0.016, eyeY + 0.021, 0.057) ? .ink : .paper
        }
    }

    private func dot(_ p: (u: Double, v: Double), _ ex: Double) -> DitherAvatar.Ink? {
        guard ellipse(p, ex, eyeY, 0.078, 0.098) else { return nil }
        return disc(p, ex - 0.026, eyeY - 0.036, 0.027) ? .paper : .ink
    }

    private func happyArc(_ p: (u: Double, v: Double), _ ex: Double) -> Bool {
        arc(p, ex, eyeY + 0.046, 0.072, from: -0.85 * .pi, to: -0.15 * .pi)
    }

    private func brow(_ p: (u: Double, v: Double), ex: Double, side s: Double) -> DitherAvatar.Ink? {
        switch f.brows {
        case .none: return nil
        case .raised: return arc(p, ex, eyeY + 0.02, 0.165, from: -0.63 * .pi, to: -0.37 * .pi) ? .ink : nil
        case .worried: return segment(p, (ex - s * 0.07, eyeY - 0.175), (ex + s * 0.07, eyeY - 0.14)) ? .ink : nil
        }
    }

    private func mouth(_ p: (u: Double, v: Double)) -> DitherAvatar.Ink? {
        let mx = fx, my = mouthY
        switch f.mouth {
        case .smile:
            return arc(p, mx, my - 0.065, 0.078, from: 0.2 * .pi, to: 0.8 * .pi) ? .ink : nil
        case .grin:
            return p.v >= my - 0.026 && ellipse(p, mx, my - 0.026, 0.111, 0.088) ? .ink : nil
        case .open:
            guard p.v >= my - 0.033, ellipse(p, mx, my - 0.033, 0.068, 0.091) else { return nil }
            return ellipse(p, mx, my + 0.042, 0.044, 0.026) ? .blush : .ink
        case .small:
            return ellipse(p, mx, my, 0.031, 0.042) ? .ink : nil
        case .flat:
            return segment(p, (mx - 0.055, my), (mx + 0.055, my)) ? .ink : nil
        case .smirk:
            // flat on one side, curling up on the other
            let d = look == 0 ? 1 : look
            let r = 0.09, cx = mx + d * 0.01, cy = my - r
            return arc(p, cx, cy, r, from: d > 0 ? 0.22 * .pi : 0.5 * .pi, to: d > 0 ? 0.5 * .pi : 0.78 * .pi)
                || segment(p, (cx - d * 0.055, my), (cx, my)) ? .ink : nil
        case .none:
            return nil
        }
    }
}
