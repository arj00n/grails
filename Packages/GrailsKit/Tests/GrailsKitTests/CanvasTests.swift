import Foundation
import Testing
@testable import GrailsKit

@Suite struct CanvasLayoutTests {
    func entries(_ n: Int, aspect: Double = 1.5) -> [CanvasLayoutEngine.Entry] { (0..<n).map { .init(id: "i\($0)", aspect: aspect) } }

    @Test func sizesKeepProportionsButTameExtremes() {
        let std = CanvasLayoutEngine.size(aspect: 1.5)
        #expect(std.h == 240 && std.w == 360)
        #expect(CanvasLayoutEngine.size(aspect: 20).w == 240 * 3.5)       // a banner doesn't become a mile wide
        #expect(CanvasLayoutEngine.size(aspect: 0.01).w == 240 * 0.3)
        #expect(CanvasLayoutEngine.size(aspect: .nan).w == 240)
        #expect(CanvasLayoutEngine.size(aspect: -3).w == 240)
        #expect(CanvasLayoutEngine.size(aspect: 1, height: 100).h == 100)
    }

    @Test func shelfPackWrapsRowsWithoutOverlap() {
        let packed = CanvasLayoutEngine.shelfPack(entries(10), origin: (100, 50), maxWidth: 1200, gap: 20)
        #expect(packed.count == 10)
        let list = packed.values.sorted { ($0.y, $0.x) < ($1.y, $1.x) }
        #expect(list.first?.x == 100 && list.first?.y == 50)
        for i in list.indices { for j in list.indices where i < j {
            let a = list[i], b = list[j]
            #expect(!(a.x < b.maxX && b.x < a.maxX && a.y < b.maxY && b.y < a.maxY), "items \(i) and \(j) overlap")
        } }
        #expect(Set(list.map(\.y)).count > 1)                        // wrapped onto several rows
        #expect(list.allSatisfy { $0.maxX <= 100 + 1200 + 0.001 })
        #expect(Set(packed.values.map(\.z)).count == 10)             // distinct stacking
    }

    @Test func initialLayoutIsRoughlyLandscape() {
        let p = CanvasLayoutEngine.initialLayout(entries(200))
        let b = CanvasLayoutEngine.bounds(of: p.values)!
        #expect(b.w > b.h * 0.9 && b.w < b.h * 4)
        #expect(CanvasLayoutEngine.initialLayout([]).isEmpty)
    }

    @Test func newItemsLandBelowExistingWork() {
        let existing = CanvasLayoutEngine.shelfPack(entries(6), origin: (0, 0), maxWidth: 1000)
        let b = CanvasLayoutEngine.bounds(of: existing.values)!
        let added = CanvasLayoutEngine.placeNew([.init(id: "new1", aspect: 1), .init(id: "new2", aspect: 2)], existing: existing)
        #expect(added.count == 2)
        #expect(added.values.allSatisfy { $0.y >= b.y + b.h })        // nothing on top of existing items
        #expect(added.values.allSatisfy { $0.z > (existing.values.map(\.z).max() ?? 0) })
        #expect(CanvasLayoutEngine.placeNew([], existing: existing).isEmpty)
        #expect(CanvasLayoutEngine.placeNew([.init(id: "a", aspect: 1)], existing: [:]).count == 1)
    }

    @Test func arrangeRepacksSelectionInReadingOrderAtItsTopLeft() {
        var board: [String: CanvasPlacement] = [
            "far": CanvasPlacement(x: 2000, y: 40, w: 100, h: 100),
            "a": CanvasPlacement(x: 500, y: 300, w: 300, h: 200, z: 3),
            "b": CanvasPlacement(x: 100, y: 310, w: 200, h: 200, z: 5),
            "c": CanvasPlacement(x: 300, y: 900, w: 240, h: 240, z: 4),
        ]
        let out = CanvasLayoutEngine.arrange(["a", "b", "c"], in: board)
        #expect(Set(out.keys) == ["a", "b", "c"])                     // "far" untouched
        // reading order is b (left, row 1), a (right, row 1), c (row 2); top-left of the selection is (100, 300)
        #expect(out["b"]!.x == 100 && out["b"]!.y == 300)
        #expect(out["a"]!.x > out["b"]!.x && out["a"]!.y == 300)
        #expect(out["c"]!.y >= out["b"]!.maxY)
        #expect(out["a"]!.w == 300 && out["a"]!.h == 200 && out["c"]!.w == 240)      // sizes kept; only positions change
        #expect(Set(out.values.map(\.z)) == [3, 4, 5])                                 // stacking kept
        board["far"] = nil
        #expect(CanvasLayoutEngine.arrange(["zzz"], in: board).isEmpty)
    }

    @Test func arrangeOrderingIsStableForScatteredItems() {
        // items scattered at awkward offsets must still come out in a deterministic, row-by-row order
        var board: [String: CanvasPlacement] = [:]
        for i in 0..<30 { board["i\(i)"] = CanvasPlacement(x: Double((i * 137) % 900), y: Double((i * 91) % 700), w: 200, h: 200, z: i) }
        let a = CanvasLayoutEngine.arrange(Array(board.keys), in: board, at: 1)
        let b = CanvasLayoutEngine.arrange(Array(board.keys.reversed()), in: board, at: 1)
        #expect(a == b)                                                    // input order doesn't matter
        let rows = Dictionary(grouping: a.values, by: \.y)
        for (_, row) in rows { #expect(row.sorted { $0.x < $1.x }.map(\.x) == row.map(\.x).sorted()) }
        let list = a.values.sorted { ($0.y, $0.x) < ($1.y, $1.x) }
        for i in list.indices { for j in list.indices where i < j {
            #expect(!(list[i].x < list[j].maxX && list[j].x < list[i].maxX && list[i].y < list[j].maxY && list[j].y < list[i].maxY))
        } }
    }

    @Test func boardKeysAreFileSafeAndStable() {
        #expect(CanvasKey.tag("Food Photography") == CanvasKey.tag("food photography"))
        #expect(CanvasKey.tag("a/b:c").allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" })
        #expect(CanvasKey.tag("x") != CanvasKey.tag("y"))
        #expect(CanvasKey.tag("x").hasPrefix("tag-"))
    }
}

@Suite struct CanvasStoreTests {
    @Test func placementsPersistAndMergeWithWhatsOnDisk() async throws {
        let (store, root) = try TestSupport.newStore()
        #expect(await store.canvasBoard(key: "k") == nil)
        try await store.updatePlacements(boardKey: "k", ["a": CanvasPlacement(x: 1, y: 2, w: 3, h: 4, z: 1)])
        // a teammate's edit lands on disk, then we save a different item: both survive
        var theirs = try #require(await store.canvasBoard(key: "k"))
        theirs.placements["b"] = CanvasPlacement(x: 9, y: 9, w: 9, h: 9, z: 2, at: Date().timeIntervalSince1970 + 5)
        try AtomicFile.write(GrailsJSON.encodeCompact(theirs), to: root.appendingPathComponent("canvas/k.json"))
        try await store.updatePlacements(boardKey: "k", ["c": CanvasPlacement(x: 5, y: 5, w: 5, h: 5, z: 3)])
        let board = try #require(await store.canvasBoard(key: "k"))
        #expect(Set(board.placements.keys) == ["a", "b", "c"])
        #expect(board.placements["b"]?.x == 9)
        #expect(board.updatedBy == "tester")
        try await store.updatePlacements(boardKey: "k", [:], removing: ["a"])
        #expect(await store.canvasBoard(key: "k")?.placements.keys.sorted() == ["b", "c"])
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent("canvas").path) == ["k.json"])
    }

    @Test func undoRestoresOnlyTheMovedPlacements() async throws {
        let (store, _) = try TestSupport.newStore()
        let start = CanvasPlacement(x: 0, y: 0, w: 100, h: 100, z: 1)
        try await store.updatePlacements(boardKey: "k", ["a": start, "b": start])
        let (_, undo) = try await store.recording(label: "Move on Canvas") {
            try await store.updatePlacements(boardKey: "k", ["a": CanvasPlacement(x: 500, y: 500, w: 100, h: 100, z: 2), "new": start])
        }
        // meanwhile someone else moves b
        try await store.updatePlacements(boardKey: "k", ["b": CanvasPlacement(x: 77, y: 77, w: 100, h: 100, z: 1)])
        let redo = try await store.apply(undo)
        var board = try #require(await store.canvasBoard(key: "k"))
        #expect(board.placements["a"]?.x == 0)                         // restored
        #expect(board.placements["new"] == nil)                        // never existed before
        #expect(board.placements["b"]?.x == 77)                        // untouched by our undo
        _ = try await store.apply(redo)
        board = try #require(await store.canvasBoard(key: "k"))
        #expect(board.placements["a"]?.x == 500 && board.placements["new"] != nil)
    }

    @Test func conflictCopiesOfBoardsMergePerPlacement() async throws {
        let (store, root) = try TestSupport.newStore()
        let now = Date().timeIntervalSince1970
        let base = CanvasBoard(key: "k", placements: [
            "a": CanvasPlacement(x: 1, y: 1, w: 10, h: 10, at: now), "b": CanvasPlacement(x: 2, y: 2, w: 10, h: 10, at: now)])
        let ben = CanvasBoard(key: "k", placements: [
            "a": CanvasPlacement(x: 100, y: 100, w: 10, h: 10, at: now + 10), "c": CanvasPlacement(x: 3, y: 3, w: 10, h: 10, at: now)])
        try AtomicFile.write(GrailsJSON.encodeCompact(base), to: root.appendingPathComponent("canvas/k.json"))
        try AtomicFile.write(GrailsJSON.encodeCompact(ben), to: root.appendingPathComponent("canvas/k (1).json"))
        let summary = try await store.applyExternalChanges(paths: [root.appendingPathComponent("canvas/k (1).json").path])
        #expect(summary.canvasBoards == ["k"] && summary.conflictsMerged == 1 && !summary.isEmpty)
        let merged = try #require(await store.canvasBoard(key: "k"))
        #expect(Set(merged.placements.keys) == ["a", "b", "c"])
        #expect(merged.placements["a"]?.x == 100)                      // the newer edit of "a" won
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent("canvas").path) == ["k.json"])
    }

    @Test func pruningDropsPlacementsOfItemsThatAreGone() async throws {
        let (store, _) = try TestSupport.newStore()
        let p = CanvasPlacement(x: 0, y: 0, w: 1, h: 1)
        try await store.updatePlacements(boardKey: "k", ["a": p, "b": p, "c": p])
        try await store.pruneBoard(key: "k", keeping: ["a", "c"])
        #expect(await store.canvasBoard(key: "k")?.placements.keys.sorted() == ["a", "c"])
    }

    @Test func largeBoardsStayCompact() async throws {
        let (store, root) = try TestSupport.newStore()
        let entries = (0..<20_000).map { _ in CanvasLayoutEngine.Entry(id: ULID().string, aspect: 1.2) }
        let t0 = Date()
        let placements = CanvasLayoutEngine.initialLayout(entries)
        let packTime = Date().timeIntervalSince(t0)
        try await store.updatePlacements(boardKey: "big", placements)
        let size = try FileManager.default.attributesOfItem(atPath: root.appendingPathComponent("canvas/big.json").path)[.size] as? Int ?? 0
        #expect(packTime < 1.0)
        #expect(size < 3_500_000)                                      // ≈ 150 bytes per placement
        #expect(await store.canvasBoard(key: "big")?.placements.count == 20_000)
    }
}
