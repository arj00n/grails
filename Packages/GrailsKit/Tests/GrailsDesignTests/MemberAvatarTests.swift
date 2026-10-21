import AppKit
import SwiftUI
import Testing
@testable import GrailsDesign

@Suite struct DitherAvatarTests {
    @Test func theSameIdAlwaysGivesTheSameFace() {
        let a = DitherAvatarSpec(memberID: "01HZX3K9V7Q", name: "Ada Lane")
        let b = DitherAvatarSpec(memberID: "01HZX3K9V7Q", name: "Ada Lane")
        #expect(a == b)
        #expect(a.face == b.face)
        // pinned: FNV-1a and the part picker do not change between launches or Macs, unlike hashValue
        #expect(DitherAvatar.seed("") == 0xcbf2_9ce4_8422_2325)
        #expect(DitherAvatar.seed("a") == 0xaf63_dc4c_8601_ec8c)
        #expect(DitherAvatar.mix(0) == 0xe220_a839_7b1d_cdaf)
        #expect(DitherAvatar.cells(a, n: 28) == DitherAvatar.cells(b, n: 28))
        let image = DitherAvatar.image(a, side: 20, scale: 2, dark: false)
        #expect(image != nil)
        #expect(image === DitherAvatar.image(b, side: 20, scale: 2, dark: false), "cached: drawn once")
        #expect(image?.width == 40)
    }

    @Test func aNameChangeKeepsTheFaceAndColour() {
        let before = DitherAvatarSpec(memberID: "m-1", name: "Ada")
        let after = DitherAvatarSpec(memberID: "m-1", name: "Bea")
        #expect(before == after)
    }

    @Test func aTeamOfThirtyRarelyCollides() {
        #expect(BlobFace.combinations >= 5_000)
        #expect(DitherAvatar.tones.count >= 12)
        // 30 people: faces almost never repeat, and with the colour every avatar differs
        let team = (0..<30).map { DitherAvatarSpec(memberID: "01J\($0)Q8ZK\($0 * 7)", name: "x") }
        #expect(Set(team.map(\.face)).count >= 29)
        #expect(Set(team.map { [$0.face.hashValue, $0.tone] }).count == 30)
        // over many ids every part and every tone turns up
        let many = (0..<600).map { DitherAvatarSpec(memberID: "member-\($0)", name: "x") }
        #expect(Set(many.map(\.tone)).count == DitherAvatar.tones.count)
        #expect(Set(many.map(\.face.eyes)).count == BlobFace.Eyes.allCases.count)
        #expect(Set(many.map(\.face.mouth)).count == BlobFace.Mouth.allCases.count)
        #expect(Set(many.map(\.face.brows)).count == BlobFace.Brows.allCases.count)
        #expect(many.allSatisfy { ($0.face.eyes != .angry && $0.face.eyes != .side) || $0.face.brows == .none }, "angry and side eyes bring their own brow")
    }

    @Test func choicesWinAndBadChoicesFallBack() {
        let chosen = DitherAvatarSpec(memberID: "m-1", name: "Ada", tint: 5, character: 42)
        #expect(chosen.tone == 5 && chosen.character == 42)
        #expect(chosen.face == BlobFace(seed: 42))
        let outOfRange = DitherAvatarSpec(memberID: "m-1", name: "Ada", tint: 99)
        #expect(outOfRange.tone == DitherAvatarSpec(memberID: "m-1", name: "Ada").tone)
        #expect(outOfRange.character == DitherAvatar.seed("m-1"))
    }

    /// The blob is the whole circle: no ground, only body shading and a face.
    @Test func theBlobFillsTheCircleWithAFaceAndDitheredShading() {
        for i in 0..<200 {
            let spec = DitherAvatarSpec(memberID: "member-\(i)", name: "x")
            for n in [20, 24, 40] {
                let grid = DitherAvatar.cells(spec, n: n)
                let count = { (ink: DitherAvatar.Ink) in grid.filter { $0 == ink }.count }
                #expect(count(.base) > n * n / 3, "mostly the member's colour: \(spec.face)")
                #expect(count(.ink) > 2 && count(.ink) + count(.paper) > n / 2, "a face: \(spec.face) at \(n)")
                #expect(count(.deep) > n / 2 && count(.lit) > 0, "dithered shading: \(spec.face)")
                // light at the top left, shade at the bottom right
                let corner = { (x0: Int, y0: Int) in (0..<n / 4).flatMap { y in (0..<n / 4).map { grid[(y0 + y) * n + x0 + $0] } } }
                #expect(!corner(0, 0).contains(.deep))
                #expect(corner(3 * n / 4, 3 * n / 4).filter { $0 == .deep }.count > n / 4)
            }
        }
    }

    @Test func everyExpressionDraws() {
        var seen = Set<BlobFace.Eyes>()
        var seed: UInt64 = 0
        while seen.count < BlobFace.Eyes.allCases.count {
            let spec = DitherAvatarSpec(memberID: "m", name: "x", character: Int(seed))
            if seen.insert(spec.face.eyes).inserted {
                for n in [40, 96] {
                    #expect(DitherAvatar.cells(spec, n: n).filter { $0 == .ink }.count > n / 2, "\(spec.face.eyes) at \(n)")
                }
            }
            seed += 1
        }
    }

    /// Seeds stored by older versions (a creature's `character`, or a hashed `glyph`) are any 31-bit value, or worse: each is just a face.
    @Test func legacySeedsLoadAsBlobs() {
        for legacy in [0, 1, 77, 123_456, 0x7FFF_FFFF, -1, Int.min, Int.max] {
            let spec = DitherAvatarSpec(memberID: "m-ada", name: "Ada", tint: 3, character: legacy)
            #expect(spec.face == BlobFace(seed: UInt64(truncatingIfNeeded: legacy)))
            #expect(spec.tone == 3)
            #expect(DitherAvatar.image(spec, side: 24, scale: 2, dark: true)?.width == 48)
        }
    }

    @Test func largeSizesUseChunkyCells() {
        #expect(DitherAvatar.cellSize(px: 40) == 2)
        #expect(DitherAvatar.cellSize(px: 24) == 1)
        #expect(DitherAvatar.cellSize(px: 192) >= 6, "96 pt at 2x prints visible dots")
    }

    @Test func theFaceReadsOnEveryToneInBothModes() {
        for tone in DitherAvatar.tones {
            for dark in [false, true] {
                #expect(DitherAvatar.contrast(DitherAvatar.ink, tone.base(dark: dark)) >= 4.5, "face on \(tone.name) dark=\(dark)")
                #expect(DitherAvatar.contrast(DitherAvatar.ink, tone.deep(dark: dark)) >= 2.5, "face on \(tone.name) shade dark=\(dark)")
                #expect(DitherAvatar.contrast(DitherAvatar.ink, tone.lit(dark: dark)) >= 6, "face on \(tone.name) highlight dark=\(dark)")
                #expect(DitherAvatar.contrast(tone.base(dark: dark), tone.deep(dark: dark)) >= 1.4, "visible shading on \(tone.name)")
            }
            #expect(tone.light.base != tone.dark.base && tone.light.deep != tone.dark.deep)
        }
        #expect(DitherAvatar.contrast(DitherAvatar.ink, DitherAvatar.paper) >= 12, "pupils on eye whites")
        #expect(Set(DitherAvatar.tones.map(\.name)).count == DitherAvatar.tones.count)
        // stored tints are indices: the first eight keep their names
        #expect(DitherAvatar.tones.prefix(8).map(\.name) == ["Clay", "Ochre", "Moss", "Teal", "Blue", "Iris", "Rose", "Graphite"])
    }
}

@Suite @MainActor struct NameBubbleTests {
    @Test func hoverShowsTheDisplayName() {
        let host = NSView(frame: NSRect(x: 0, y: 0, width: 240, height: 160))
        let avatar = MemberAvatarView(frame: NSRect(x: 8, y: 8, width: 18, height: 18))
        host.addSubview(avatar)
        avatar.show(MemberFace(memberID: "m-1", name: "Ada Lane"))
        #expect(avatar.bubble.superview == nil, "nothing until hovered")

        avatar.setHovering(true, reduceMotion: true)
        #expect(avatar.bubble.superview === host)
        #expect(avatar.bubble.text == "Ada Lane")
        #expect(!avatar.bubble.isHidden && avatar.bubble.alphaValue == 1)
        #expect(avatar.bubble.frame.minX > avatar.frame.maxX)
        #expect(avatar.bubble.frame.maxX <= host.bounds.maxX)

        avatar.setHovering(false, reduceMotion: true)
        #expect(avatar.bubble.isHidden && avatar.bubble.alphaValue == 0)
    }

    @Test func anEmptyNameShowsNoBubble() {
        let host = NSView(frame: NSRect(x: 0, y: 0, width: 200, height: 100))
        let avatar = MemberAvatarView(frame: NSRect(x: 8, y: 8, width: 18, height: 18))
        host.addSubview(avatar)
        avatar.show(MemberFace(memberID: "m-1", name: "  "))
        avatar.setHovering(true, reduceMotion: true)
        #expect(avatar.bubble.superview == nil)
        #expect(NameBubble.text(for: " Ada ") == "Ada")
    }

    @Test func theFadeIsQuickNeverBouncesAndStopsUnderReduceMotion() {
        #expect(NameBubble.rest == 0)
        #expect(NameBubble.fade(reduceMotion: false) == Motion.quick)
        #expect(NameBubble.fade(reduceMotion: true) == 0)
        #expect(NameBubble.animation(reduceMotion: true) == nil)
        #expect(NameBubble.animation(reduceMotion: false) == .grailsQuick)
        #expect(Palette.contrast(NameBubble.label, NameBubble.fill, dark: false) >= 4.5)
        #expect(Palette.contrast(NameBubble.label, NameBubble.fill, dark: true) >= 4.5)
    }
}

@Suite struct CanonHighlightTests {
    @Test func textReadsOnTheGoldInBothModes() {
        for dark in [false, true] {
            let fill = CanonTokens.fill(dark: dark)
            #expect(DitherAvatar.contrast(CanonTokens.ink(dark: dark), fill.from) >= 4.5)
            #expect(DitherAvatar.contrast(CanonTokens.ink(dark: dark), fill.to) >= 4.5)
        }
    }

    /// Not selected, the mark and title are only tinted: they read on the sidebar and on the hover fill like any row.
    @Test func theQuietTintReadsOnTheSidebarAndItsHover() {
        for dark in [false, true] {
            #expect(DitherAvatar.contrast(CanonTokens.tint(dark: dark), Palette.hex(.sidebar, dark: dark)) >= 4.5)
            #expect(DitherAvatar.contrast(CanonTokens.tint(dark: dark), Palette.hex(.fill, dark: dark)) >= 4.5)
        }
    }

    @Test func theStarsHoldUnderReduceMotionAndInTheBackground() {
        func live(reduceMotion: Bool = false, active: Bool = true, visible: Bool = true, idle: Bool = false) -> Bool {
            LiveMotion.isLive(decorative: true, reduceMotion: reduceMotion, snapshot: false, appActive: active, windowVisible: visible, idle: idle)
        }
        #expect(live())
        #expect(!live(reduceMotion: true))
        #expect(!live(active: false))
        #expect(!live(visible: false))
        #expect(!live(idle: true))
        // held still, every star is still shown
        for star in CanonStars.stars { #expect(!CanonStars.pixels(star, brightness: star.rest).isEmpty) }
    }

    /// The stars' timeline ticks only where a star steps: every tick changes a pixel, nothing changes between ticks, and a whole
    /// period needs a few ticks a second at most, where a frame clock would need a dozen.
    @Test func theStarsRedrawOnlyWhenAStarSteps() {
        func frame(_ t: TimeInterval) -> [Double] { CanonStars.stars.map { CanonStars.brightness($0, at: t) } }
        let start = 800_000_000.0
        var t = start, ticks = 0
        while true {
            let next = CanonStars.nextChange(after: t)
            #expect(next > t)
            #expect(frame(next) != frame(next - 0.002), "a tick that changes nothing")
            for k in 1..<8 { #expect(frame(t + (next - t) * Double(k) / 8 - 0.0005) == frame(t), "a change between ticks") }
            guard next < start + Motion.canonTwinkle else { break }
            t = next; ticks += 1
        }
        #expect(ticks <= CanonStars.stars.count * 2 * (Int(CanonStars.steps) - 1))
        #expect(Double(ticks) / Motion.canonTwinkle < 4)
        // paused: the first frame and nothing after it
        let paused = Array(CanonStars.Schedule(live: false).entries(from: Date(), mode: .normal))
        #expect(paused.count == 1)
    }

    @Test func progressMotionIgnoresIdleButNotVisibility() {
        #expect(LiveMotion.isLive(decorative: false, reduceMotion: false, snapshot: false, appActive: true, windowVisible: true, idle: true))
        #expect(!LiveMotion.isLive(decorative: false, reduceMotion: false, snapshot: false, appActive: false, windowVisible: true, idle: false))
        #expect(!LiveMotion.isLive(decorative: false, reduceMotion: false, snapshot: true, appActive: true, windowVisible: true, idle: false))
    }

    /// Two or three stars, a few pixels each, outside the mark, inside the icon's own field, never more than one lit at once,
    /// and dark most of the time.
    @Test func theStarsAreFewTinyAndSparse() {
        #expect((2...3).contains(CanonStars.stars.count))
        #expect(Motion.canonTwinkle >= 5)
        #expect(CanonTokens.starOpacity <= 0.7)
        let half = CanonStars.field / 2
        for star in CanonStars.stars {
            let px = CanonStars.pixels(star, brightness: 1)
            #expect((1...5).contains(px.count))
            for p in px {
                let x = Double(star.x + p.x), y = Double(star.y + p.y)
                #expect(abs(x) < half && abs(y) < half, "inside the icon's field")
                #expect(max(abs(x), abs(y)) > 6, "off the 12 pt mark")
                #expect(abs(p.x) <= 1 && abs(p.y) <= 1, "three pixels across at most")
            }
        }
        var dark = 0, samples = 0
        for i in 0..<720 {
            let t = Double(i) * Motion.canonTwinkle / 720
            let lit = CanonStars.stars.filter { CanonStars.brightness($0, at: t) > 0 }.count
            #expect(lit <= 1)
            if lit == 0 { dark += 1 }
            samples += 1
        }
        #expect(Double(dark) / Double(samples) >= 0.05)
        // stepped: brightness only takes whole steps
        for i in 0..<100 {
            let b = CanonStars.brightness(CanonStars.stars[0], at: Double(i) * 0.037)
            #expect((b * CanonStars.steps).rounded() == b * CanonStars.steps)
        }
    }

    /// Not selected the row has no gold behind it; selected it has the fill and the outline. Writes the four rows to
    /// `GRAILS_CANON_PREVIEW` when that is set.
    @MainActor @Test func theRowIsPlainUntilSelected() throws {
        for dark in [false, true] {
            let plain = try CanonRowPixels(selected: false, dark: dark)
            let sidebar = Palette.hex(.sidebar, dark: dark)
            #expect(plain.matches(x: 120, y: 14, sidebar), "no fill behind the plain row")
            let chosen = try CanonRowPixels(selected: true, dark: dark)
            #expect(chosen.matches(x: 120, y: 14, CanonTokens.fill(dark: dark).from, tolerance: 0x28), "gold fill when selected")
            #expect(!chosen.matches(x: 120, y: 14, sidebar))
        }
        if let path = ProcessInfo.processInfo.environment["GRAILS_CANON_PREVIEW"], !path.isEmpty {
            try CanonRowPixels.writePreview(to: URL(fileURLWithPath: path))
        }
    }

    @Test func theMarkIsATemplateImage() {
        let image = CanonMark.image(pointSize: 14)
        #expect(image.isTemplate)
        #expect(image.size == NSSize(width: 14, height: 14))
    }
}

/// Canon's sidebar row as the sidebar draws it, on the sidebar colour, for the tests and the preview.
private struct CanonRowSample: View {
    var selected: Bool
    var hovering = false
    var body: some View {
        HStack(spacing: 8) {
            CanonMark(size: 12).foregroundStyle(CanonInk(selected: selected)).frame(width: 16)
                .overlay { CanonSparkles(selected: selected) }
            Text("Canon").font(.system(size: 13)).foregroundStyle(CanonInk(selected: selected))
            Spacer(minLength: 4)
        }
        .padding(.horizontal, 8)
        .frame(width: 200, height: 28)
        .background { GrailsCanonHighlight(selected: selected, hovering: hovering, radius: 7) }
        .padding(8)
        .background(GrailsInk(.sidebar))
    }
}

private struct CanonRowPixels {
    let width: Int, height: Int
    let data: [UInt8]

    @MainActor init(selected: Bool, dark: Bool) throws {
        let image = try #require(Self.render(CanonRowSample(selected: selected), dark: dark, scale: 1))
        width = image.width
        height = image.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let ctx = try #require(CGContext(data: &bytes, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                         space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        data = bytes
    }

    /// `x`, `y` in the row, from its top left (the sample pads the row by 8).
    func matches(x: Int, y: Int, _ hex: UInt32, tolerance: Int = 6) -> Bool {
        let i = ((y + 8) * width + (x + 8)) * 4
        let want = [Int(hex >> 16 & 0xFF), Int(hex >> 8 & 0xFF), Int(hex & 0xFF)]
        return (0..<3).allSatisfy { abs(Int(data[i + $0]) - want[$0]) <= tolerance }
    }

    @MainActor static func render<V: View>(_ view: V, dark: Bool, scale: CGFloat) -> CGImage? {
        let scheme: ColorScheme = dark ? .dark : .light
        let renderer = ImageRenderer(content: view.environment(\.colorScheme, scheme).environment(\.grailsSnapshot, true))
        renderer.scale = scale
        return renderer.cgImage
    }

    /// Plain and selected, light and dark, at 2x and then doubled again so the 1 pt star pixels are easy to see.
    @MainActor static func writePreview(to url: URL) throws {
        let grid = VStack(spacing: 0) {
            ForEach([false, true], id: \.self) { dark in
                HStack(spacing: 0) {
                    ForEach([false, true], id: \.self) { selected in
                        CanonRowSample(selected: selected).environment(\.colorScheme, dark ? .dark : .light)
                    }
                }
            }
        }
        let image = try #require(render(grid.environment(\.grailsSnapshot, true), dark: false, scale: 4))
        let rep = NSBitmapImageRep(cgImage: image)
        let png = try #require(rep.representation(using: .png, properties: [:]))
        try png.write(to: url)
    }
}
