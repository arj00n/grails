import Foundation
import Testing
@testable import GrailsKit

@Suite struct FormatTests {
    @Test func itemPreservesUnknownFieldsOnRoundTrip() throws {
        let json = """
        {
          "schema": 1, "id": "01JABC", "kind": "image", "name": "x", "tags": ["a"],
          "addedAt": "2026-10-03T10:00:00.123Z", "addedBy": "ana",
          "futureField": {"nested": [1, 2.5, "three", null, true]}, "aiScore": 0.93
        }
        """
        let item = try GrailsJSON.decode(Item.self, from: Data(json.utf8))
        #expect(item.extras["aiScore"] == .double(0.93))
        let back = try GrailsJSON.decode(Item.self, from: GrailsJSON.encode(item))
        #expect(back == item)
        #expect(back.extras["futureField"] == .object(["nested": .array([.int(1), .double(2.5), .string("three"), .null, .bool(true)])]))
    }

    @Test func datesKeepMillisecondPrecision() throws {
        let item = Item(kind: .image, name: "n", addedBy: "a")
        let back = try GrailsJSON.decode(Item.self, from: GrailsJSON.encode(item))
        #expect(back.addedAt == item.addedAt)
    }

    @Test func manyRandomDatesRoundTripExactly() throws {
        for _ in 0..<2000 {
            let d = Date(timeIntervalSince1970: Double.random(in: 1_500_000_000...2_000_000_000)).roundedToMilliseconds
            let item = Item(kind: .image, name: "n", addedAt: d, addedBy: "a")
            let back = try GrailsJSON.decode(Item.self, from: GrailsJSON.encode(item))
            #expect(back.addedAt == d && back.updatedAt == d)
        }
    }

    @Test func ulidsSortByTime() {
        let early = ULID(date: Date(timeIntervalSince1970: 1_700_000_000))
        let late = ULID(date: Date(timeIntervalSince1970: 1_800_000_000))
        #expect(early < late)
        #expect(early.string.count == 26)
        #expect(abs(early.date.timeIntervalSince1970 - 1_700_000_000) < 1)
        #expect(ULID(string: early.string) == early)
        #expect(ULID(string: "nope") == nil)
    }

    @Test func fractionalIndexAlwaysLandsBetweenNeighbours() {
        var keys = [FractionalIndex.initial]
        var rng = SystemRandomNumberGenerator()
        for _ in 0..<2000 {
            let pos = Int.random(in: 0...keys.count, using: &rng)
            let lo = pos == 0 ? nil : keys[pos - 1]
            let hi = pos == keys.count ? nil : keys[pos]
            let k = FractionalIndex.between(lo, hi)
            if let lo { #expect(lo < k) }
            if let hi { #expect(k < hi) }
            keys.insert(k, at: pos)
        }
        #expect(keys == keys.sorted())
        #expect(!keys.contains { $0.hasSuffix("0") })
    }

    @Test func atomicWriteLeavesNoTempFiles() throws {
        let dir = TestSupport.tempDir()
        let url = dir.appendingPathComponent("a.json")
        try AtomicFile.write(Data("1".utf8), to: url)
        try AtomicFile.write(Data("2".utf8), to: url)
        #expect(try String(contentsOf: url, encoding: .utf8) == "2")
        #expect(try FileManager.default.contentsOfDirectory(atPath: dir.path) == ["a.json"])
    }

    @Test func conflictCopyNamesAreRecognised() {
        #expect(ConflictMerger.isItemConflictCopy("item (1).json"))
        #expect(ConflictMerger.isItemConflictCopy("item (Ana's conflicted copy 2026-10-03).json"))
        #expect(ConflictMerger.isItemConflictCopy("item 2.json"))
        #expect(!ConflictMerger.isItemConflictCopy("item.json"))
        #expect(!ConflictMerger.isItemConflictCopy("item.json.tmp-123"))
        #expect(!ConflictMerger.isItemConflictCopy("thumb.jpg"))
    }
}
