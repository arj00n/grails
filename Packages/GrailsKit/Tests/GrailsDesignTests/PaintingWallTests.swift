import CoreGraphics
import Foundation
import Testing
@testable import GrailsDesign

private func spec(mode: PaintingWall.Placement.Mode = .cover, anchor: [Double] = [0.5, 0.5], width: Int = 1000, height: Int = 700) -> PaintingWall.Spec {
    PaintingWall.Spec(id: "t", file: "t.jpg", artist: "A", title: "T", year: "1900", caption: "A 1900", width: width, height: height,
                      placement: .init(mode: mode, focal: [0.5, 0.5], anchor: anchor, zoom: 1), gamma: 1, lo: 0, hi: 1, satLo: 0, satHi: 1,
                      palette: ["#000000", "#ff0000", "#00ff00", "#0000ff", "#ffffff"])
}

@Suite struct DitherTests {
    @Test func thresholdsAreEvenlySpreadAndTile() {
        var seen = Set<Double>()
        for r in 0..<8 { for c in 0..<8 { seen.insert(Dither.bayer(c, r)) } }
        #expect(seen.count == 64 && seen.min()! > 0 && seen.max()! < 1)
        #expect(Dither.bayer(3, 5) == Dither.bayer(11, 13))
        let row0 = (0..<8).map { Int((Dither.bayer($0, 0) * 64).rounded(.down)) }
        #expect(row0 == [0, 32, 8, 40, 2, 34, 10, 42])
    }

    @Test func everyTwoByTwoBlockSpansTheRange() {
        // the clustered (most-significant-first) map fails this: neighbours land in the same quarter
        for by in stride(from: 0, to: 8, by: 2) { for bx in stride(from: 0, to: 8, by: 2) {
            let quarters = Set([(0, 0), (1, 0), (0, 1), (1, 1)].map { Int(Dither.bayer(bx + $0.0, by + $0.1) * 4) })
            #expect(quarters.count == 4)
        } }
    }

    @Test func aFlatToneLightsAboutTheRightShareOfPixels() {
        for v in [0.1, 0.25, 0.5, 0.75, 0.9] {
            var lit = 0
            for y in 0..<8 { for x in 0..<8 where Dither.lit(ink: v, x: x, y: y) { lit += 1 } }
            #expect(abs(Double(lit) - (v - 0.04) / 0.92 * 64) <= 1.5)
        }
        #expect(!Dither.lit(ink: 0.03, x: 1, y: 1) && Dither.lit(ink: 0.97, x: 1, y: 1))
    }
}

@Suite struct PaintingInkTests {
    @Test func inkFollowsLightInTheDarkAndShadowInTheLight() {
        #expect(PaintingWall.ink(luma: 0.8, sat: 0, dark: true) > PaintingWall.ink(luma: 0.3, sat: 0, dark: true))
        #expect(PaintingWall.ink(luma: 0.8, sat: 0, dark: false) < PaintingWall.ink(luma: 0.3, sat: 0, dark: false))
        #expect(PaintingWall.ink(luma: 0.03, sat: 0, dark: true) == 0)                     // the toe: near-black stays blank
        for l in stride(from: 0.0, through: 1.0, by: 0.1) { for s in [0.0, 0.5, 1.0] { for d in [true, false] {
            let v = PaintingWall.ink(luma: l, sat: s, dark: d); #expect(v >= 0 && v <= 1)
        } } }
    }

    @Test func saturationLiftsAnIsoluminantSunInBothModes() {
        #expect(PaintingWall.ink(luma: 0.4, sat: 1, dark: true) > PaintingWall.ink(luma: 0.4, sat: 0, dark: true) + 0.1)
        #expect(PaintingWall.ink(luma: 0.8, sat: 1, dark: false) > PaintingWall.ink(luma: 0.8, sat: 0, dark: false))
    }

    @Test func litColoursAreOpaqueAndBrightInTheDarkDeepInTheLight() {
        let dark = PaintingWall.litColours(palette: ["#400000", "#808080"], dark: true)
        let light = PaintingWall.litColours(palette: ["#400000", "#808080"], dark: false)
        #expect(dark.allSatisfy { $0 >> 24 == 0xFF } && light.allSatisfy { $0 >> 24 == 0xFF })
        #expect((dark[0] & 255) > 200)                                                    // dark red is printed at full strength
        #expect((light[1] & 255) < (dark[1] & 255))
    }
}

@Suite struct PlacementTests {
    @Test func coverAlwaysCoversTheWindow() {
        for aspect in [1.2, 1.6, 2.0, 2.4] {
            let win = CGSize(width: 900 * aspect, height: 900)
            for fx in [0.3, 0.5, 0.8] {
                var s = spec(); s.placement.anchor = [fx, 0.5]
                let f = PaintingWall.frame(s, window: win)
                #expect(f.minX <= 0.001 && f.minY <= 0.001 && f.maxX >= win.width - 0.001 && f.maxY >= win.height - 0.001)
            }
        }
    }

    @Test func aSidePictureFitsTheHeightAndSitsAtItsAnchor() {
        let s = spec(mode: .side, anchor: [0.72, 0.5], width: 700, height: 1000)
        let win = CGSize(width: 1280, height: 800)
        let f = PaintingWall.frame(s, window: win)
        #expect(abs(f.height - 800) < 0.001 && abs(f.midX - 0.72 * 1280) < 0.001)
        #expect(PaintingWall.coverage(s, frame: f, x: f.minX + 1) < 0.05 && PaintingWall.coverage(s, frame: f, x: f.midX) == 1)
        #expect(PaintingWall.coverage(spec(), frame: f, x: f.minX) == 1)                    // cover pictures have no edge
    }

    @Test func thePlateIsPixelAlignedCentredAndBigEnough() {
        for win in [CGSize(width: 1280, height: 800), CGSize(width: 1117, height: 733), CGSize(width: 2560, height: 1600)] {
            let p = PaintingWall.plate(window: win)
            #expect(Int(p.minX) % 3 == 0 && Int(p.minY) % 3 == 0 && Int(p.width) % 3 == 0 && Int(p.height) % 3 == 0)
            #expect(p.width >= 304 && p.height >= 148 && p.width <= 310 && p.height <= 154)
            #expect(abs(p.midX - win.width / 2) <= 3 && abs(p.midY - (win.height / 2 - 4)) <= 5)
        }
    }
}

@Suite struct GridTests {
    func gradient(cols: Int, rows: Int) -> [UInt8] {
        var out = [UInt8](repeating: 0, count: cols * rows * 4)
        for y in 0..<rows { for x in 0..<cols {
            let i = (y * cols + x) * 4, v = UInt8(255 * x / max(cols - 1, 1))
            out[i] = v; out[i + 1] = v; out[i + 2] = v; out[i + 3] = 255
        } }
        return out
    }

    @Test func buildingIsRepeatableAndFollowsTheTone() {
        let s = spec(), f = PaintingWall.frame(s, window: CGSize(width: 90, height: 60))
        let a = PaintingWall.Grid.build(rgba: gradient(cols: 30, rows: 20), cols: 30, rows: 20, pixel: 3, spec: s, frame: f)
        let b = PaintingWall.Grid.build(rgba: gradient(cols: 30, rows: 20), cols: 30, rows: 20, pixel: 3, spec: s, frame: f)
        #expect(a == b)
        #expect(a.inkDark[5] < a.inkDark[25] && a.inkLight[5] > a.inkLight[25])           // left black → right white
        #expect(a.colour[0] == 0 && a.colour[29] == 4)                                    // nearest palette entries: black and white
    }

    @Test func nothingIsPrintedWhereThePictureIsNotAndTheEdgeFeathers() {
        var rgba = gradient(cols: 30, rows: 20)
        for y in 0..<20 { for x in 0..<5 { let i = (y * 30 + x) * 4; rgba[i] = 0; rgba[i + 1] = 0; rgba[i + 2] = 0; rgba[i + 3] = 0 } }
        let s = spec(mode: .side, anchor: [0.5, 0.5], width: 700, height: 1000)
        let g = PaintingWall.Grid.build(rgba: rgba, cols: 30, rows: 20, pixel: 3, spec: s, frame: CGRect(x: 15, y: 0, width: 60, height: 60))
        #expect((0..<5).allSatisfy { g.inkDark[$0] == 0 && g.inkLight[$0] == 0 })
        #expect(g.inkLight[6] <= g.inkLight[10])                                           // feathered in near the edge
    }
}

@Suite struct WaveTests {
    let cols = 427, rows = 267

    @Test func theEndsAreExact() {
        for y in stride(from: 0, to: rows, by: 7) { for x in stride(from: 0, to: cols, by: 5) {
            let t = PaintingWall.tau(x: x, y: y, cols: cols, rows: rows)
            #expect(t >= 0 && t < 1)
            #expect(PaintingWall.wave(tau: t, progress: 0) == 0 && PaintingWall.wave(tau: t, progress: 1) == 1)
        } }
    }

    @Test func aPixelNeverGoesBackAndTheFrontMovesFromTheTopLeft() {
        let t = PaintingWall.tau(x: 200, y: 100, cols: cols, rows: rows)
        var last = 0.0
        for k in 0...100 { let s = PaintingWall.wave(tau: t, progress: Double(k) / 100); #expect(s >= last); last = s }
        let early = PaintingWall.wave(tau: PaintingWall.tau(x: 10, y: 10, cols: cols, rows: rows), progress: 0.3)
        let late = PaintingWall.wave(tau: PaintingWall.tau(x: 400, y: 250, cols: cols, rows: rows), progress: 0.3)
        #expect(early > late)
    }

    @Test func easeOutNeverOvershoots() {
        for k in 0...100 { let e = PaintingWall.ease(Double(k) / 100); #expect(e >= 0 && e <= 1) }
        #expect(PaintingWall.ease(0.5) > 0.5)
    }

    @Test func stateIsExactlyFromThenToWithASeamBetween() {
        let from = PaintingWall.Sample(ink: 200, colour: 3), to = PaintingWall.Sample(ink: 90, colour: 9)
        for (x, y) in [(0, 0), (5, 3), (100, 77)] {
            let a = PaintingWall.state(x: x, y: y, from: from, to: to, s: 0, tick: 4), b = PaintingWall.state(x: x, y: y, from: from, to: to, s: 1, tick: 4)
            #expect(a.lit == Dither.lit(ink: 200.0 / 255, x: x, y: y) && a.colour == 3 && !a.toPainting)
            #expect(b.lit == Dither.lit(ink: 90.0 / 255, x: x, y: y) && b.colour == 9 && b.toPainting)
        }
        // at the front the seam is re-rolled by tick
        let dim = PaintingWall.Sample(ink: 100, colour: 3)       // mid ink + 0.25 is not always lit, so the seam flickers
        let seams = Set((0..<12).map { PaintingWall.state(x: 9, y: 9, from: dim, to: PaintingWall.Sample(ink: 60, colour: 9), s: 0.5, tick: $0).lit })
        #expect(seams.count == 2)
        // an empty pixel on both sides stays empty, so the plate never lights
        #expect((0..<20).allSatisfy { !PaintingWall.state(x: 3, y: 3, from: PaintingWall.Sample(ink: 0, colour: 0), to: PaintingWall.Sample(ink: 0, colour: 0), s: 0.5, tick: $0).lit })
        // the first picture develops from nothing
        #expect(!PaintingWall.state(x: 4, y: 4, from: nil, to: to, s: 0, tick: 0).lit)
    }
}

@Suite struct LoupeTests {
    @Test func theLensIsZeroBeyondItsRadiusAndFadesWithAge() {
        let t = PaintingWall.Touch(x: 100, y: 100, age: 0)
        #expect(PaintingWall.influence(x: 100, y: 100, touches: [t]) == 1)
        #expect(PaintingWall.influence(x: 100 + PaintingWall.loupeRadius, y: 100, touches: [t]) == 0 && PaintingWall.influence(x: 400, y: 400, touches: [t]) == 0)
        let old = PaintingWall.Touch(x: 100, y: 100, age: 0.4)
        #expect(PaintingWall.influence(x: 100, y: 100, touches: [old]) < 0.5)
        #expect(PaintingWall.influence(x: 100, y: 100, touches: [PaintingWall.Touch(x: 100, y: 100, age: 0.8)]) == 0)
        for d in stride(from: 0.0, to: 90, by: 6) { let q = PaintingWall.influence(x: 100 + d, y: 100, touches: [t]); #expect(q >= 0 && q <= 1) }
    }

    @Test func thePaintingThinsOutSoftlyAroundThePlate() {
        let plate = PaintingWall.plate(window: CGSize(width: 1280, height: 800))
        #expect(PaintingWall.falloff(x: plate.midX, y: plate.midY, plate: plate) == 0)
        #expect(PaintingWall.falloff(x: plate.maxX + PaintingWall.plateFalloff, y: plate.midY, plate: plate) == 1)
        var last = 0.0
        for d in stride(from: 0.0, through: PaintingWall.plateFalloff, by: 5) {
            let v = PaintingWall.falloff(x: plate.maxX + d, y: plate.midY, plate: plate); #expect(v >= last); last = v
        }
        let corner = PaintingWall.falloff(x: plate.maxX + 30, y: plate.maxY + 30, plate: plate), edge = PaintingWall.falloff(x: plate.maxX + 30, y: plate.midY, plate: plate)
        #expect(corner > edge)                                                          // distance is round, not boxy
    }
}

@Suite struct ScheduleTests {
    @Test func theFirstPictureHoldsThenEveryEightSecondsAWaveBringsTheNext() {
        #expect(PaintingWall.schedule(t: 0.5, count: 14, reduceMotion: false) == .init(index: 0, next: 1, progress: nil))
        #expect(PaintingWall.schedule(t: 7.9, count: 14, reduceMotion: false).progress == nil)
        let w = PaintingWall.schedule(t: 8.8, count: 14, reduceMotion: false)
        #expect(w.index == 0 && w.next == 1 && abs(w.progress! - 0.5) < 1e-9)
        #expect(PaintingWall.schedule(t: 9.7, count: 14, reduceMotion: false) == .init(index: 1, next: 2, progress: nil))
        #expect(PaintingWall.schedule(t: 8.0 * 14 + 0.1, count: 14, reduceMotion: false).next == 0)       // wraps
    }

    @Test func reduceMotionIsOneStillPicture() {
        for t in [0.0, 3, 8.5, 100] { #expect(PaintingWall.schedule(t: t, count: 14, reduceMotion: true) == .init(index: 0, next: 0, progress: nil)) }
    }

    @Test func theCaptionChangesWhenTheWavePassesTheMiddle() {
        #expect(PaintingWall.captionIndex(PaintingWall.schedule(t: 8.1, count: 14, reduceMotion: false)) == 0)
        #expect(PaintingWall.captionIndex(PaintingWall.schedule(t: 9.4, count: 14, reduceMotion: false)) == 1)
        #expect(PaintingWall.intro(t: 0.05) == 0 && PaintingWall.intro(t: 1.0) == 1 && PaintingWall.intro(t: 0.55) > 0.4)
    }
}

@Suite struct PaintingManifestTests {
    static let dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Apps/Grails/Resources/Paintings")

    @Test func theShippedManifestIsCompleteAndEveryWorkIsCredited() throws {
        let m = try JSONDecoder().decode(PaintingWall.Manifest.self, from: Data(contentsOf: Self.dir.appendingPathComponent("manifest.json")))
        #expect(m.paintings.count == 14 && m.pixel == 3)
        let notice = try String(contentsOf: Self.dir.appendingPathComponent("NOTICE.md"), encoding: .utf8)
        for p in m.paintings {
            #expect(p.palette.count == 16 && p.lo < p.hi && p.satLo < p.satHi)
            #expect(p.caption == p.caption.uppercased() && p.caption.split(separator: " ").count <= 3)
            #expect(FileManager.default.fileExists(atPath: Self.dir.appendingPathComponent(p.file).path))
            #expect(notice.contains(p.title))
            #expect(p.placement.focal.count == 2 && p.placement.anchor.count == 2)
        }
        #expect(m.paintings.first?.id == "cabanel" && Set(m.paintings.map(\.id)).count == 14)
        #expect(notice.components(separatedBy: "https://commons.wikimedia.org/wiki/File:").count - 1 == 14)
    }
}
