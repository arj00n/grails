import Foundation
import Testing
@testable import GrailsDesign

@Suite struct WordmarkTests {
    private static let manifest = try! JSONDecoder().decode(PaintingWall.Manifest.self, from: Data(contentsOf: PaintingManifestTests.dir.appendingPathComponent("manifest.json")))
    private static let hokusai = manifest.paintings.first { $0.id == "hokusai" }!.palette
    private static let vangogh = manifest.paintings.first { $0.id == "vangogh" }!.palette

    private static func inks(_ palette: [String], dark: Bool) -> Wordmark.Inks {
        Wordmark.inks(palette: palette, dark: dark, plate: Palette.hex(.canvas, dark: dark), ink: Palette.hex(.text, dark: dark))
    }
    private static let sub = 6, width = Wordmark.columns * sub, height = Wordmark.rows * sub

    @Test func theBitmapIsSeventyByFourteen() {
        #expect(Wordmark.bitmap.count == Wordmark.rows)
        #expect(Wordmark.bitmap.allSatisfy { $0.count == Wordmark.columns && $0.allSatisfy { $0 == "#" || $0 == "." } })
        #expect(Wordmark.size == CGSize(width: 210, height: 42))
        #expect(Wordmark.sub(scale: 2) == 6 && Wordmark.sub(scale: 1) == 3)
    }

    @Test func theLetterEdgesStayOnTheCells() {
        let inks = Self.inks(Self.hokusai, dark: false)
        let px = Wordmark.pixels(t: 3, sub: Self.sub, inks: inks, reduceMotion: false)
        #expect(px.count == Self.width * Self.height)
        for y in 0..<Self.height { for x in 0..<Self.width {
            let p = px[y * Self.width + x]
            #expect(Wordmark.isSet(x / Self.sub, y / Self.sub) ? [inks.ink, inks.tip, inks.core].contains(p) : p == 0)
        } }
    }

    @Test func theFlamesRiseFromTheFootAndTheTopThirdIsPlainInk() {
        let inks = Self.inks(Self.vangogh, dark: true)
        var flame = [Int](repeating: 0, count: Self.height), lit = [Int](repeating: 0, count: Self.height)
        for t in stride(from: 0.0, to: 40, by: 2.5) {
            let px = Wordmark.pixels(t: t, sub: Self.sub, inks: inks, reduceMotion: false)
            for y in 0..<Self.height { for x in 0..<Self.width where px[y * Self.width + x] != 0 {
                lit[y] += 1
                if px[y * Self.width + x] != inks.ink { flame[y] += 1 }
            } }
        }
        func share(_ rows: Range<Int>) -> Double { Double(rows.map { flame[$0] }.reduce(0, +)) / Double(max(rows.map { lit[$0] }.reduce(0, +), 1)) }
        let third = Self.height / 3
        #expect(share(0..<third) == 0)                                    // the top third is plain ink
        #expect(share(Self.height - third..<Self.height) > 0.75)          // the foot is mostly fire
        #expect(share(third..<Self.height - third) > 0.05 && share(third..<Self.height - third) < 0.75)
        #expect((0..<Wordmark.rows).map { Wordmark.heat(u: 35, v: Double($0), t: 4) }.allSatisfy { $0 >= 0 && $0 <= 1 })
    }

    @Test func theFlamesAndTheInkClearThePlateOnEveryPaintingInBothAppearances() {
        for p in Self.manifest.paintings { for dark in [false, true] {
            let plate = Palette.hex(.canvas, dark: dark), inks = Self.inks(p.palette, dark: dark)
            #expect(Wordmark.contrast(inks.ink, plate: plate) >= Wordmark.inkContrast, "\(p.id) dark \(dark)")
            #expect(Wordmark.contrast(inks.core, plate: plate) >= Wordmark.flameContrast, "\(p.id) dark \(dark)")
            #expect(Wordmark.contrast(inks.tip, plate: plate) >= Wordmark.flameContrast, "\(p.id) dark \(dark)")
            #expect(Wordmark.contrast(inks.core, inks.ink) >= Wordmark.coreSeparation, "\(p.id) dark \(dark)")
            #expect(Wordmark.contrast(inks.tip, inks.ink) >= Wordmark.tipSeparation, "\(p.id) dark \(dark)")
            #expect(Wordmark.contrast(inks.tip, inks.core) >= Wordmark.flameSeparation, "\(p.id) dark \(dark)")
            #expect(Wordmark.contrast(inks.tip, inks.ink) < Wordmark.contrast(inks.core, inks.ink), "\(p.id) dark \(dark)")
        } }
        // a palette that is all plate is pushed until it reads
        let blank = Wordmark.inks(palette: ["#ffffff"], dark: false, plate: 0xFFFFFF, ink: 0x1A1A1A)
        #expect(Wordmark.contrast(blank.core, plate: 0xFFFFFF) >= Wordmark.flameContrast)
    }

    @Test func theInkIsTheTextTokenAndTheFlamesComeFromThePaintingShowing() {
        let a = Self.inks(Self.hokusai, dark: true), b = Self.inks(Self.vangogh, dark: true)
        #expect(a.ink == b.ink && Wordmark.contrast(a.ink, plate: Palette.hex(.text, dark: true)) < 1.01)
        #expect(a.core != b.core)
    }

    @Test func theFlamesTurnOnTheWallsGrain() {
        let a = Self.inks(Self.hokusai, dark: false), b = Self.inks(Self.vangogh, dark: false)
        let flames = { (inks: Wordmark.Inks) in Set([inks.tip, inks.core]) }
        let start = Wordmark.pixels(t: 20, sub: Self.sub, inks: b, from: a, e: 0, reduceMotion: false)
        let end = Wordmark.pixels(t: 20, sub: Self.sub, inks: b, from: a, e: 1, reduceMotion: false)
        let half = Wordmark.pixels(t: 20, sub: Self.sub, inks: b, from: a, e: 0.5, reduceMotion: false)
        #expect(start.allSatisfy { $0 == 0 || $0 == a.ink || flames(a).contains($0) })
        #expect(end.allSatisfy { $0 == 0 || $0 == b.ink || flames(b).contains($0) })
        let turned = half.filter { flames(b).contains($0) }.count, burning = half.filter { flames(a).contains($0) || flames(b).contains($0) }.count
        #expect(Double(turned) / Double(burning) > 0.35 && Double(turned) / Double(burning) < 0.65)
    }

    @Test func theFlamesMoveCalmlyAndHoldStillWithReduceMotion() {
        let inks = Self.inks(Self.hokusai, dark: true)
        let lit = Double(Wordmark.bitmap.joined().filter { $0 == "#" }.count * Self.sub * Self.sub)
        func changed(_ a: [UInt32], _ b: [UInt32]) -> Double { Double(zip(a, b).filter { $0 != $1 }.count) / lit }
        let now = Wordmark.pixels(t: 30, sub: Self.sub, inks: inks, reduceMotion: false)
        let soon = Wordmark.pixels(t: 30 + 1.0 / 30, sub: Self.sub, inks: inks, reduceMotion: false)
        let later = Wordmark.pixels(t: 33, sub: Self.sub, inks: inks, reduceMotion: false)
        #expect(changed(now, soon) < 0.04)
        #expect(changed(now, later) > 0.05)
        #expect(Wordmark.pixels(t: 30, sub: Self.sub, inks: inks, reduceMotion: true) == Wordmark.pixels(t: 90, sub: Self.sub, inks: inks, reduceMotion: true))
    }

    @Test func theLettersDevelopOutOfThePlate() {
        let inks = Self.inks(Self.hokusai, dark: false)
        func shown(_ t: Double) -> Int { Wordmark.pixels(t: t, sub: 1, inks: inks, develop: Wordmark.develop(t: t), reduceMotion: false).filter { $0 != 0 }.count }
        let all = Wordmark.bitmap.joined().filter { $0 == "#" }.count
        #expect(shown(0.5) == 0 && shown(1.2) > 0 && shown(1.2) < all && shown(1.5) == all)
    }
}
