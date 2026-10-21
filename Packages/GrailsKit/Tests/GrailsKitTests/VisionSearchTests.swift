import CoreGraphics
import CoreText
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import GrailsKit

@Suite struct VisionSearchTests {
    @Test func namedBuckets() {
        let cases: [(String, NamedColor)] = [
            ("#FF0000", .red),
            ("#FF8000", .orange),
            ("#FFE600", .yellow),
            ("#00AA00", .green),
            ("#00C2C2", .teal),
            ("#0044FF", .blue),
            ("#0000FF", .blue),
            ("#7A3FF0", .purple),
            ("#FF6EB4", .pink),
            ("#FFC0CB", .pink),
            ("#6B3E1F", .brown),
            ("#111111", .black),
            ("#000000", .black),
            ("#F7F7F7", .white),
            ("#FFFFFF", .white),
            ("#8A8A8A", .gray),
        ]
        for (hex, expected) in cases {
            #expect(NamedColor.name(hex: hex) == expected, "\(hex) is \(expected.rawValue)")
        }
    }

    @Test func ranksClosestFirst() {
        let rows: [(id: String, distance: Float)] = [
            ("far", 0.9),
            ("near", 0.1),
            ("mid", 0.4),
            ("bad", .nan),
            ("tie-b", 0.4),
        ]
        #expect(SimilarityRank.order(rows, limit: 3) == ["near", "mid", "tie-b"])
    }

    @Test func colorTokensLeaveTheWords() {
        let parts = SearchText.parse("poster color:Blue color:#ff00aa color:nope")
        #expect(parts.text == "poster color:nope")
        #expect(parts.colorNames == ["blue"])
        #expect(parts.nearHexes == ["#FF00AA"])
    }

    @Test func searchFindsTextAndColourWithoutWritingTheItem() async throws {
        let (store, _) = try TestSupport.newStore()
        let red = try await store.addItem(fileAt: TestSupport.makePNG(in: TestSupport.tempDir(), name: "red", rgb: (1, 0, 0)), name: "Poppy").item
        let blue = try await store.addItem(fileAt: TestSupport.makePNG(in: TestSupport.tempDir(), name: "blue", rgb: (0, 0.2, 1)), name: "Sea").item
        try await store.index.saveVision(VisionRecord(
            itemId: red.id, sha256: try #require(red.sha256), ocrText: "GrailsToken on the poster",
            swatches: [NamedSwatch(hex: "#FF0000", weight: 1, name: .red)], featurePrint: nil
        ))
        try await store.index.saveVision(VisionRecord(
            itemId: blue.id, sha256: try #require(blue.sha256), ocrText: "horizon",
            swatches: [NamedSwatch(hex: "#0044FF", weight: 1, name: .blue)], featurePrint: nil
        ))

        let found = try await store.index.query(ItemQuery(text: "GrailsToken"))
        #expect(found.map(\.name) == ["Poppy"])

        var named = ItemQuery()
        named.colorNames = ["blue"]
        #expect(try await store.index.query(named).map(\.name) == ["Sea"])

        var near = ItemQuery()
        near.nearHexes = ["#FF0000"]
        #expect(try await store.index.query(near).map(\.name) == ["Poppy"])

        var far = ItemQuery()
        far.nearHexes = ["#0000FF"]
        #expect(try await store.index.query(far).map(\.name) == ["Sea"])

        let onDisk = try #require(try await store.item(id: red.id))
        #expect(onDisk.ocrText == "")
        #expect(onDisk.palette.isEmpty)

        try await store.index.rebuild(from: store.layout)
        #expect(try await store.index.query(ItemQuery(text: "GrailsToken")).map(\.name) == ["Poppy"])
        #expect(try await store.index.query(named).map(\.name) == ["Sea"])
    }

    @Test func fixtureImageIsIndexedByTheWordsOnIt() async throws {
        let (store, _) = try TestSupport.newStore()
        let url = VisionFixture.labeled("GrailsToken")
        let item = try await store.addItem(fileAt: url, name: "Card").item
        let record = await VisionBackfill.analyze(itemId: item.id, sha256: try #require(item.sha256), url: url)
        #expect(record.ocrText.localizedCaseInsensitiveContains("GrailsToken"))
        try await store.index.saveVision(record)
        let hits = try await store.index.query(ItemQuery(text: "GrailsToken"))
        #expect(hits.map(\.id) == [item.id])
        #expect(try await store.item(id: item.id)?.ocrText == "")
    }

    @Test func solidRedIsNamedRed() async throws {
        let url = TestSupport.makePNG(in: TestSupport.tempDir(), name: "solid", width: 64, height: 64, rgb: (1, 0, 0))
        let record = await VisionBackfill.analyze(itemId: "red", sha256: "abc", url: url)
        #expect(record.swatches.first?.name == .red)
    }

    @Test func aPosterKeepsEachMajorColourOnce() {
        let swatches = PaletteExtractor.swatches(from: PaletteFixture.poster())
        #expect(swatches.count <= 5)
        #expect(Set(swatches.map(\.name)).count == swatches.count)
        let names = Set(swatches.map(\.name))
        #expect(names.isSuperset(of: [.red, .orange, .green, .blue]), "\(PaletteFixture.describe(swatches))")
        #expect(PaletteFixture.closestPair(swatches) >= 12, "\(PaletteFixture.describe(swatches))")
    }

    @Test func aSmallAccentSurvivesANeutralField() {
        let swatches = PaletteExtractor.swatches(from: PaletteFixture.accent())
        let names = Set(swatches.map(\.name))
        #expect(names.contains(.red), "\(PaletteFixture.describe(swatches))")
        #expect(names.contains(.gray) || names.contains(.white))
        #expect(Set(swatches.map(\.name)).count == swatches.count)
        #expect(swatches.count <= 5)
        #expect(PaletteFixture.closestPair(swatches) >= 12)
    }

    @Test func unreadableItemsDoNotStallTheBackfill() async throws {
        let (store, _) = try TestSupport.newStore()
        let dir = TestSupport.tempDir()
        var width = 200
        func add(_ name: String, readable: Bool) async throws -> Item {
            width += 1
            let item = try await store.addItem(fileAt: TestSupport.makePNG(in: dir, name: name, width: width, rgb: (0, 0.5, 1)), name: name).item
            if !readable {
                // As a cloud-only or thumbnail-less item: the row is there, the pictures are not.
                if let file = item.file { try? FileManager.default.removeItem(at: store.layout.itemDir(item.id).appendingPathComponent(file)) }
                try? FileManager.default.removeItem(at: store.layout.thumbURL(item.id))
            }
            return item
        }
        for n in 0..<9 { _ = try await add("old-\(n)", readable: false) }
        let good = try await add("good", readable: true)
        for n in 0..<9 { _ = try await add("new-\(n)", readable: false) }

        let first = try await store.index.visionPending(limit: 8).map(\.id)
        #expect(first == (try await store.index.visionPending(limit: 8).map(\.id)))
        #expect(!(try await store.index.visionPending(limit: 50, excluding: Set(first)).map(\.id)).contains { first.contains($0) })

        let done = await VisionBackfill.run(store: store, pause: {})
        #expect(done == 1)
        #expect(try await store.index.vision(for: good.id) != nil)
        #expect(try await store.index.visionPending(limit: 50).count == 18)
    }

    @Test func anOlderPaletteIsReadAgain() async throws {
        let root = TestSupport.tempDir().appendingPathComponent("Older.grails")
        let indexURL = TestSupport.tempDir().appendingPathComponent("index.sqlite")
        let store = try LibraryStore.create(at: root, name: "Older", index: try LibraryIndex(path: indexURL))
        let url = TestSupport.makePNG(in: TestSupport.tempDir(), name: "swatch", rgb: (1, 0, 0))
        let item = try await store.addItem(fileAt: url, name: "Poppy").item
        try await store.index.saveVision(VisionRecord(
            itemId: item.id, sha256: try #require(item.sha256), ocrText: "",
            swatches: [NamedSwatch(hex: "#FF0000", weight: 1, name: .red)], featurePrint: nil
        ))
        let fresh = try await store.index.visionPending(limit: 20).map(\.id)
        #expect(!fresh.contains(item.id))

        let update = Process()
        update.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        update.arguments = [indexURL.path, "UPDATE vision_meta SET algo = 0"]
        try update.run()
        update.waitUntilExit()
        #expect(update.terminationStatus == 0)
        let stale = try await store.index.visionPending(limit: 20).map(\.id)
        #expect(stale.contains(item.id))
    }

    @Test func aGradientKeepsTheEndsAndDropsTheSteps() {
        let swatches = PaletteExtractor.swatches(from: PaletteFixture.gradient())
        let names = Set(swatches.map(\.name))
        #expect(names.isSuperset(of: [.red, .blue]), "\(PaletteFixture.describe(swatches))")
        #expect(Set(swatches.map(\.name)).count == swatches.count)
        #expect(swatches.count <= 5)
        #expect(PaletteFixture.closestPair(swatches) >= 12)
    }

    @Test func similarRanksTheMatchingPictureFirst() async throws {
        let (store, _) = try TestSupport.newStore()
        let dir = TestSupport.tempDir()
        let redURL = TestSupport.makePNG(in: dir, name: "a", width: 80, height: 80, rgb: (1, 0, 0))
        let blueURL = TestSupport.makePNG(in: dir, name: "b", width: 80, height: 80, rgb: (0, 0.2, 1))
        let redAgain = TestSupport.makePNG(in: dir, name: "c", width: 80, height: 80, rgb: (0.95, 0.05, 0.05))
        let red = try await store.addItem(fileAt: redURL, name: "Red").item
        let blue = try await store.addItem(fileAt: blueURL, name: "Blue").item
        let near = try await store.addItem(fileAt: redAgain, name: "Near").item
        for (item, url) in [(red, redURL), (blue, blueURL), (near, redAgain)] {
            let record = await VisionBackfill.analyze(itemId: item.id, sha256: try #require(item.sha256), url: url)
            try await store.index.saveVision(record)
        }
        let ranked = try await VisionBackfill.similarIDs(to: red.id, store: store, limit: 2)
        #expect(ranked.first == near.id)
        #expect(!ranked.contains(red.id))
    }
}

private enum PaletteFixture {
    static func poster() -> CGImage {
        let bands: [(CGFloat, CGFloat, CGFloat)] = [
            (0.23, 0.44, 0.88),
            (0.29, 0.48, 0.91),
            (0.18, 0.37, 0.78),
            (0.89, 0.23, 0.18),
            (0.94, 0.54, 0.14),
            (0.24, 0.61, 0.31),
        ]
        return image(width: 180, height: 90) { ctx in
            let band = 180 / bands.count
            for (index, rgb) in bands.enumerated() {
                ctx.setFillColor(CGColor(srgbRed: rgb.0, green: rgb.1, blue: rgb.2, alpha: 1))
                ctx.fill(CGRect(x: index * band, y: 0, width: band, height: 90))
            }
        }
    }

    static func accent() -> CGImage {
        image(width: 160, height: 160) { ctx in
            ctx.setFillColor(CGColor(srgbRed: 0.82, green: 0.82, blue: 0.80, alpha: 1))
            ctx.fill(CGRect(x: 0, y: 0, width: 160, height: 160))
            ctx.setFillColor(CGColor(srgbRed: 0.86, green: 0.15, blue: 0.12, alpha: 1))
            ctx.fill(CGRect(x: 6, y: 6, width: 18, height: 18))
        }
    }

    static func gradient() -> CGImage {
        image(width: 128, height: 48) { ctx in
            for x in 0..<128 {
                let t = CGFloat(x) / 127
                ctx.setFillColor(CGColor(srgbRed: 1 - t, green: 0.05, blue: t, alpha: 1))
                ctx.fill(CGRect(x: x, y: 0, width: 1, height: 48))
            }
        }
    }

    static func describe(_ swatches: [NamedSwatch]) -> String {
        swatches.map { "\($0.name.rawValue) \($0.hex) \(String(format: "%.3f", $0.weight))" }.joined(separator: ", ")
    }

    static func closestPair(_ swatches: [NamedSwatch]) -> Double {
        guard swatches.count >= 2 else { return 100 }
        var best = Double.greatestFiniteMagnitude
        for i in swatches.indices {
            for j in swatches.indices where j > i {
                guard let a = ColorMath.lab(fromHex: swatches[i].hex), let b = ColorMath.lab(fromHex: swatches[j].hex) else { continue }
                let d = hypot(a.l - b.l, hypot(a.a - b.a, a.b - b.b))
                if d < best { best = d }
            }
        }
        return best
    }

    private static func image(width: Int, height: Int, draw: (CGContext) -> Void) -> CGImage {
        let ctx = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        draw(ctx)
        return ctx.makeImage()!
    }
}

private enum VisionFixture {
    static func labeled(_ word: String) -> URL {
        let width = 900
        let height = 240
        let ctx = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let font = CTFontCreateWithName("Helvetica-Bold" as CFString, 92, nil)
        let line = CTLineCreateWithAttributedString(CFAttributedStringCreate(nil, word as CFString, [
            kCTFontAttributeName: font,
            kCTForegroundColorAttributeName: CGColor(gray: 0, alpha: 1),
        ] as CFDictionary))
        ctx.textPosition = CGPoint(x: 48, y: 70)
        CTLineDraw(line, ctx)
        let url = TestSupport.tempDir().appendingPathComponent("label.png")
        let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
        precondition(CGImageDestinationFinalize(dest))
        return url
    }
}
