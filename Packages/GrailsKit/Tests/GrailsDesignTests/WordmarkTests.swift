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
    private static let width = Wordmark.columns * Wordmark.sub, height = Wordmark.rows * Wordmark.sub

    @Test func theBitmapIsSeventyByFourteen() {
        #expect(Wordmark.bitmap.count == Wordmark.rows)
        #expect(Wordmark.bitmap.allSatisfy { $0.count == Wordmark.columns && $0.allSatisfy { $0 == "#" || $0 == "." } })
        #expect(Wordmark.size == CGSize(width: 210, height: 42))
    }

    @Test func theLetterEdgesStayOnTheCells() {
        let inks = Self.inks(Self.hokusai, dark: false)
        let px = Wordmark.pixels(t: 3, inks: inks, reduceMotion: false)
        #expect(px.count == Self.width * Self.height)
        for y in 0..<Self.height { for x in 0..<Self.width {
            let p = px[y * Self.width + x]
            #expect(Wordmark.isSet(x / Wordmark.sub, y / Wordmark.sub) ? (p == inks.ink || p == inks.flame) : p == 0)
        } }
    }

    @Test func theFlamesAreTheEmptyScreensRisingFromTheFootWithThePlainTopThird() {
        let inks = Self.inks(Self.vangogh, dark: true)
        var flame = [Int](repeating: 0, count: Self.height), lit = [Int](repeating: 0, count: Self.height)
        for t in stride(from: 0.0, to: Wordmark.loop, by: 0.5) {
            let px = Wordmark.pixels(t: t, inks: inks, reduceMotion: false)
            for y in 0..<Self.height { for x in 0..<Self.width where px[y * Self.width + x] != 0 {
                lit[y] += 1
                if px[y * Self.width + x] == inks.flame { flame[y] += 1 }
            } }
        }
        func share(_ rows: Range<Int>) -> Double { Double(rows.map { flame[$0] }.reduce(0, +)) / Double(max(rows.map { lit[$0] }.reduce(0, +), 1)) }
        let third = Self.height / 3
        #expect(share(0..<third) == 0)                                    // the top third is plain ink
        #expect(share(Self.height - 3..<Self.height) > 0.7)               // the foot is mostly fire
        #expect(share(third..<Self.height - third) > 0.01 && share(third..<Self.height - third) < share(Self.height - third..<Self.height), "\(share(third..<Self.height - third)) \(share(Self.height - third..<Self.height))")
        // the same loop as the empty screen, so it comes round every `loop` seconds
        #expect(Wordmark.pixels(t: 3, inks: inks, reduceMotion: false) == Wordmark.pixels(t: 3 + Wordmark.loop, inks: inks, reduceMotion: false))
        #expect(Wordmark.phase(t: 0) == Wordmark.stillPhase)
    }

    @Test func theFlameAndTheInkClearThePlateOnEveryPaintingInBothAppearances() {
        for p in Self.manifest.paintings { for dark in [false, true] {
            let plate = Palette.hex(.canvas, dark: dark), inks = Self.inks(p.palette, dark: dark)
            #expect(Wordmark.contrast(inks.ink, plate: plate) >= Wordmark.inkContrast, "\(p.id) dark \(dark)")
            #expect(Wordmark.contrast(inks.flame, plate: plate) >= Wordmark.flameContrast, "\(p.id) dark \(dark)")
            #expect(Wordmark.contrast(inks.flame, inks.ink) >= Wordmark.flameSeparation, "\(p.id) dark \(dark)")
        } }
        // a palette that is all plate is pushed until it reads
        let blank = Wordmark.inks(palette: ["#ffffff"], dark: false, plate: 0xFFFFFF, ink: 0x1A1A1A)
        #expect(Wordmark.contrast(blank.flame, plate: 0xFFFFFF) >= Wordmark.flameContrast)
    }

    @Test func theInkIsTheTextTokenAndTheFlameComesFromThePaintingShowing() {
        let a = Self.inks(Self.hokusai, dark: true), b = Self.inks(Self.vangogh, dark: true)
        #expect(a.ink == b.ink && Wordmark.contrast(a.ink, plate: Palette.hex(.text, dark: true)) < 1.01)
        #expect(a.flame != b.flame)
    }

    @Test func theFlamesTurnOnTheWallsGrain() {
        let a = Self.inks(Self.hokusai, dark: false), b = Self.inks(Self.vangogh, dark: false)
        let start = Wordmark.pixels(t: 20, inks: b, from: a, e: 0, reduceMotion: false)
        let end = Wordmark.pixels(t: 20, inks: b, from: a, e: 1, reduceMotion: false)
        let half = Wordmark.pixels(t: 20, inks: b, from: a, e: 0.5, reduceMotion: false)
        #expect(start.allSatisfy { $0 == 0 || $0 == a.ink || $0 == a.flame })
        #expect(end.allSatisfy { $0 == 0 || $0 == b.ink || $0 == b.flame })
        let turned = half.filter { $0 == b.flame }.count, burning = half.filter { $0 == a.flame || $0 == b.flame }.count
        #expect(Double(turned) / Double(burning) > 0.35 && Double(turned) / Double(burning) < 0.65)
    }

    @Test func theFlamesMoveAndHoldStillWithReduceMotion() {
        let inks = Self.inks(Self.hokusai, dark: true)
        let lit = Double(Wordmark.bitmap.joined().filter { $0 == "#" }.count * Wordmark.sub * Wordmark.sub)
        func changed(_ a: [UInt32], _ b: [UInt32]) -> Double { Double(zip(a, b).filter { $0 != $1 }.count) / lit }
        let now = Wordmark.pixels(t: 30, inks: inks, reduceMotion: false)
        #expect(changed(now, Wordmark.pixels(t: 30 + 1.0 / 30, inks: inks, reduceMotion: false)) < 0.1)
        #expect(changed(now, Wordmark.pixels(t: 32, inks: inks, reduceMotion: false)) > 0.02)
        #expect(Wordmark.pixels(t: 30, inks: inks, reduceMotion: true) == Wordmark.pixels(t: 90, inks: inks, reduceMotion: true))
    }

    @Test func theLettersDevelopOutOfThePlate() {
        let inks = Self.inks(Self.hokusai, dark: false)
        let perCell = Wordmark.sub * Wordmark.sub
        func shown(_ t: Double) -> Int { Wordmark.pixels(t: t, inks: inks, develop: Wordmark.develop(t: t), reduceMotion: false).filter { $0 != 0 }.count / perCell }
        let all = Wordmark.bitmap.joined().filter { $0 == "#" }.count
        #expect(shown(0.5) == 0 && shown(1.2) > 0 && shown(1.2) < all && shown(1.5) == all)
    }
}
