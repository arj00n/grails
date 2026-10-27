import Foundation
import Testing
@testable import GrailsDesign

@Suite struct WordmarkTests {
    private static let manifest = try! JSONDecoder().decode(PaintingWall.Manifest.self, from: Data(contentsOf: PaintingManifestTests.dir.appendingPathComponent("manifest.json")))
    private static let hokusai = manifest.paintings.first { $0.id == "hokusai" }!.palette
    private static let vangogh = manifest.paintings.first { $0.id == "vangogh" }!.palette

    @Test func theBitmapIsSeventyByFourteen() {
        #expect(Wordmark.bitmap.count == Wordmark.rows)
        #expect(Wordmark.bitmap.allSatisfy { $0.count == Wordmark.columns && $0.allSatisfy { $0 == "#" || $0 == "." } })
        #expect(Wordmark.size == CGSize(width: 140, height: 28))
    }

    @Test func everyLetterCellIsPrintedAndNothingElse() {
        let inks = Wordmark.inks(palette: Self.hokusai, dark: false, plate: Palette.hex(.canvas, dark: false))
        let px = Wordmark.pixels(t: 3, inks: inks, reduceMotion: false)
        for y in 0..<Wordmark.rows { for x in 0..<Wordmark.columns {
            let p = px[y * Wordmark.columns + x]
            #expect(Wordmark.isSet(x, y) ? (p == inks.base || p == inks.accent) : p == 0)
        } }
        // both inks show, mostly the painting's accent
        let accent = px.filter { $0 == inks.accent }.count, base = px.filter { $0 == inks.base }.count
        #expect(base > 0 && Double(accent) / Double(accent + base) > 0.4)
    }

    @Test func everyPaintingsInksClearThePlateInBothAppearances() {
        for p in Self.manifest.paintings { for dark in [false, true] {
            let plate = Palette.hex(.canvas, dark: dark)
            let inks = Wordmark.inks(palette: p.palette, dark: dark, plate: plate)
            #expect(Wordmark.contrast(inks.base, plate: plate) >= Wordmark.baseContrast, "\(p.id) dark \(dark)")
            #expect(Wordmark.contrast(inks.accent, plate: plate) >= Wordmark.accentContrast, "\(p.id) dark \(dark)")
            #expect(inks.base != inks.accent, "\(p.id) dark \(dark)")
        } }
        // a palette that is all plate is pushed until it reads
        let blank = Wordmark.inks(palette: ["#ffffff"], dark: false, plate: 0xFFFFFF)
        #expect(Wordmark.contrast(blank.accent, plate: 0xFFFFFF) >= Wordmark.accentContrast)
    }

    @Test func theInksComeFromThePaintingShowing() {
        let plate = Palette.hex(.canvas, dark: true)
        let a = Wordmark.inks(palette: Self.hokusai, dark: true, plate: plate), b = Wordmark.inks(palette: Self.vangogh, dark: true, plate: plate)
        #expect(a != b)
        #expect(Set(PaintingWall.litColours(palette: Self.hokusai, dark: true)).contains(a.accent))
    }

    @Test func theInksTurnOnTheWallsGrain() {
        let plate = Palette.hex(.canvas, dark: false)
        let a = Wordmark.inks(palette: Self.hokusai, dark: false, plate: plate), b = Wordmark.inks(palette: Self.vangogh, dark: false, plate: plate)
        let start = Wordmark.pixels(t: 20, inks: b, from: a, e: 0, reduceMotion: false)
        let end = Wordmark.pixels(t: 20, inks: b, from: a, e: 1, reduceMotion: false)
        let half = Wordmark.pixels(t: 20, inks: b, from: a, e: 0.5, reduceMotion: false)
        #expect(start.allSatisfy { $0 == 0 || $0 == a.base || $0 == a.accent })
        #expect(end.allSatisfy { $0 == 0 || $0 == b.base || $0 == b.accent })
        let turned = half.filter { $0 == b.base || $0 == b.accent }.count, lit = half.filter { $0 != 0 }.count
        #expect(Double(turned) / Double(lit) > 0.35 && Double(turned) / Double(lit) < 0.65)
    }

    @Test func itShimmersSlowlyAndHoldsStillWithReduceMotion() {
        let inks = Wordmark.inks(palette: Self.hokusai, dark: true, plate: Palette.hex(.canvas, dark: true))
        let lit = Double(Wordmark.bitmap.joined().filter { $0 == "#" }.count)
        func changed(_ a: [UInt32], _ b: [UInt32]) -> Double { Double(zip(a, b).filter { $0 != $1 }.count) / lit }
        let now = Wordmark.pixels(t: 30, inks: inks, reduceMotion: false)
        let soon = Wordmark.pixels(t: 30 + 1.0 / 30, inks: inks, reduceMotion: false)
        let later = Wordmark.pixels(t: 33, inks: inks, reduceMotion: false)
        #expect(changed(now, soon) < 0.03)
        #expect(changed(now, later) > 0.02)
        #expect(Wordmark.pixels(t: 30, inks: inks, reduceMotion: true) == Wordmark.pixels(t: 90, inks: inks, reduceMotion: true))
    }

    @Test func theLettersDevelopOutOfThePlate() {
        let inks = Wordmark.inks(palette: Self.hokusai, dark: false, plate: Palette.hex(.canvas, dark: false))
        func shown(_ t: Double) -> Int { Wordmark.pixels(t: t, inks: inks, develop: Wordmark.develop(t: t), reduceMotion: false).filter { $0 != 0 }.count }
        let all = Wordmark.bitmap.joined().filter { $0 == "#" }.count
        #expect(shown(0.5) == 0 && shown(1.2) > 0 && shown(1.2) < all && shown(1.5) == all)
    }
}
