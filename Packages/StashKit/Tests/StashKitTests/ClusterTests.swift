import Foundation
import Testing
@testable import StashKit

@Suite struct ClusterLayoutTests {
    func entries(_ aspects: [Double]) -> [ClusterLayout.Entry] { aspects.enumerated().map { .init(id: "i\($0.offset)", aspect: $0.element) } }

    @Test func rowsFillTheWidthExactlyWithNoGaps() {
        let e = entries([1.5, 1, 0.7, 1.8, 1.2, 0.9, 1.4, 1.0, 1.6, 0.8, 1.1, 1.3])
        let p = ClusterLayout.pack(e, width: 1200, tile: 240)
        #expect(p.rects.count == e.count)
        for row in p.rows.dropLast() {
            let rects = row.map { p.rects[$0]! }
            #expect(rects.first?.minX == 0 && rects.last?.maxX == 1200)                       // flush to both edges
            for (a, b) in zip(rects, rects.dropFirst()) { #expect(a.maxX == b.minX) }          // edge to edge
            #expect(Set(rects.map(\.height)).count == 1 && Set(rects.map(\.minY)).count == 1)  // one height, one top
        }
        // rows stack with no gaps either
        let tops = p.rows.map { p.rects[$0[0]]! }
        for (a, b) in zip(tops, tops.dropFirst()) { #expect(a.maxY == b.minY) }
        let bottom = Double(tops.last!.maxY)
        #expect(abs(p.height - bottom) < 0.001)
    }

    @Test func rowHeightsStayNearTheTarget() {
        let e = entries((0..<60).map { 0.6 + Double($0 % 7) * 0.25 })
        let p = ClusterLayout.pack(e, width: 1600, tile: 260)
        for row in p.rows.dropLast() { let h = p.rects[row[0]]!.height; #expect(h > 260 * 0.5 && h < 260 * 2) }
    }

    @Test func aShortLastRowKeepsTheTargetHeightAndAlignsLeft() {
        let p = ClusterLayout.pack(entries([1, 1, 1, 1, 1, 1, 1, 1, 1, 1]), width: 1000, tile: 240)       // 4 per row, then 2 left over
        let last = p.rows.last!.map { p.rects[$0]! }
        #expect(last.count == 2 && last[0].minX == 0 && last[0].height == 240 && last.last!.maxX < 1000)
    }

    @Test func extremeAspectsAreTamedAndEveryItemGetsARect() {
        let p = ClusterLayout.pack(entries([0.0, .nan, 40, 0.01, -3, 1]), width: 800, tile: 200)
        #expect(p.rects.count == 6 && p.rects.values.allSatisfy { $0.width >= 1 && $0.height >= 1 && $0.width.isFinite && $0.height.isFinite })
        #expect(ClusterLayout.pack([], width: 800, tile: 200) == ClusterLayout.Packed())
    }

    @Test func aBiggerTileMeansTallerRowsWithFewerPicturesInEach() {
        let e = entries(Array(repeating: 1.3, count: 40))
        let small = ClusterLayout.pack(e, width: 1600, tile: 160), big = ClusterLayout.pack(e, width: 1600, tile: 400)
        #expect(big.rects["i0"]!.height > small.rects["i0"]!.height && big.rows[0].count < small.rows[0].count)
    }

    @Test func findsTheSlotUnderThePointer() {
        let e = entries(Array(repeating: 1, count: 10))
        let p = ClusterLayout.pack(e, width: 1000, tile: 250)                                  // 4 per row
        let order = e.map(\.id)
        #expect(ClusterLayout.insertionIndex(of: CGPoint(x: 10, y: 10), packed: p, order: order) == 0)
        #expect(ClusterLayout.insertionIndex(of: CGPoint(x: 600, y: 10), packed: p, order: order) == 2)          // right half of tile 1 → before tile 2
        #expect(ClusterLayout.insertionIndex(of: CGPoint(x: 990, y: 10), packed: p, order: order) == 4)          // past the end of row 1: after it
        #expect(ClusterLayout.insertionIndex(of: CGPoint(x: 10, y: 300), packed: p, order: order) == 4)          // start of row 2
        #expect(ClusterLayout.insertionIndex(of: CGPoint(x: 400, y: 5000), packed: p, order: order) == 9 || ClusterLayout.insertionIndex(of: CGPoint(x: 400, y: 5000), packed: p, order: order) == 10)
        #expect(ClusterLayout.insertionIndex(of: CGPoint(x: 5, y: -50), packed: p, order: order) == 0)
        #expect(ClusterLayout.insertionIndex(of: .zero, packed: .init(), order: []) == 0)
    }
}

@Suite struct ClusterOpsTests {
    func c(_ id: String, _ items: [String], x: Double = 0, y: Double = 0, at: Double = 1) -> CanvasCluster { CanvasCluster(id: id, x: x, y: y, items: items, at: at) }

    @Test func newItemsJoinTheFirstClusterOrStartOne() {
        let out = ClusterOps.adopt(["a", "b", "z"], into: [c("1", ["a"]), c("2", ["b"])], at: 9)
        #expect(out[0].items == ["a", "z"] && out[1].items == ["b"] && out[0].at == 9)
        let fresh = ClusterOps.adopt(["a", "b"], into: [], at: 9)
        #expect(fresh.count == 1 && fresh[0].items == ["a", "b"] && fresh[0].width >= 1800)
        #expect(ClusterOps.adopt(["a"], into: [c("1", ["a"])]).count == 1)
    }

    @Test func movingBetweenClustersKeepsEverythingElseInOrder() {
        let start = [c("1", ["a", "b", "c", "d"]), c("2", ["x", "y"])]
        let out = ClusterOps.move(["b", "c"], to: .cluster("2", index: 1), in: start, at: 5)
        #expect(out.map(\.items) == [["a", "d"], ["x", "b", "c", "y"]])
        #expect(out.map(\.at) == [5, 5])
        // within the same cluster: the index counts what's left after taking the moved ones out
        let same = ClusterOps.move(["a"], to: .cluster("1", index: 2), in: start)
        #expect(same[0].items == ["b", "c", "a", "d"])
        #expect(ClusterOps.move(["a"], to: .cluster("nope", index: 0), in: start).flatMap(\.items).sorted() == ["b", "c", "d", "x", "y"])    // unknown target: the items are removed, not duplicated
    }

    @Test func movingOutToEmptySpaceMakesANewClusterAndEmptiesDisappear() {
        let out = ClusterOps.move(["x", "y"], to: .newCluster(x: 4000, y: 100, width: nil, tile: 200), in: [c("1", ["a"]), c("2", ["x", "y"])], at: 7)
        #expect(out.count == 2)                                           // cluster 2 emptied and went away
        #expect(out[0].items == ["a"] && out[1].items == ["x", "y"] && out[1].x == 4000 && out[1].y == 100 && out[1].tile == 200)
        #expect(ClusterOps.move(["a"], to: .newCluster(x: 0, y: 0, width: nil, tile: nil), in: [c("1", ["a"])]).count == 1)       // a lone item moved out is still just one cluster
    }

    @Test func aBoardFromBeforeClustersBecomesOneClusterInReadingOrder() {
        func p(_ x: Double, _ y: Double) -> CanvasPlacement { CanvasPlacement(x: x, y: y, w: 200, h: 200) }
        let out = ClusterOps.migrate(["c": p(300, 10), "a": p(0, 0), "b": p(150, 20), "d": p(0, 260), "e": p(260, 250)])
        #expect(out.count == 1 && out[0].items == ["a", "b", "c", "d", "e"])
        #expect(ClusterOps.migrate([:]).isEmpty)
    }

    @Test func nobodyEndsUpInTwoClusters() {
        let out = ClusterOps.normalized([c("1", ["a", "b"], at: 1), c("2", ["b", "c"], at: 5)])
        #expect(out[0].items == ["a"] && out[1].items == ["b", "c"])      // the newer cluster keeps b
    }

    @Test func blocksTidyIntoRowsWithoutOverlapping() {
        let clusters = (0..<5).map { CanvasCluster(id: "c\($0)", x: Double($0) * 10, y: 0, width: 1000, items: ["i\($0)"]) }
        let spots = ClusterOps.tidy(clusters, heights: Dictionary(uniqueKeysWithValues: clusters.map { ($0.id, 600.0) }), maxRowWidth: 2300, gap: 100)
        var rects = clusters.map { CGRect(x: spots[$0.id]!.x, y: spots[$0.id]!.y, width: 1000, height: 600) }
        for i in rects.indices { for j in rects.indices where j > i { #expect(!rects[i].intersects(rects[j])) } }
        rects.sort { ($0.minY, $0.minX) < ($1.minY, $1.minX) }
        #expect(rects.filter { $0.minY == rects[0].minY }.count == 2)       // 2 per row at 2300 wide
    }
}

@Suite struct ClusterBoardTests {
    @Test func oldBoardsStillReadAndNewOnesRoundTrip() throws {
        let old = """
        {"schema":1,"key":"library","updatedAt":"2026-10-01T10:00:00.000Z","updatedBy":"ana","placements":{"a":{"x":0,"y":0,"w":100,"h":100,"z":0,"at":1}}}
        """
        let board = try StashJSON.decode(CanvasBoard.self, from: Data(old.utf8))
        #expect(board.placements.count == 1 && board.clusters.isEmpty)
        var next = board
        next.clusters = [CanvasCluster(id: "k", title: "Chairs", x: 5, y: 6, width: 900, tile: 200, items: ["a"], at: 3)]
        let again = try StashJSON.decode(CanvasBoard.self, from: StashJSON.encodeCompact(next))
        #expect(again.clusters == next.clusters && again.placements == next.placements)
        // a board without clusters doesn't write the key, so older readers see exactly what they always did
        #expect(!String(decoding: try StashJSON.encodeCompact(board), as: UTF8.self).contains("clusters"))
    }

    @Test func twoMacsEditingClustersMerge() {
        let base = CanvasCluster(id: "k", title: "A", items: ["a", "b"], at: 1)
        var mine = CanvasBoard(key: "x", clusters: [base]); mine.clusters[0].title = "Mine"; mine.clusters[0].at = 5
        var theirs = CanvasBoard(key: "x", clusters: [base, CanvasCluster(id: "n", title: "New", items: ["c"], at: 4)])
        theirs.clusters[0].items = ["a"]; theirs.clusters[0].at = 3
        let merged = CanvasBoard.merge(mine, theirs)
        #expect(merged.clusters.map(\.id) == ["k", "n"] && merged.clusters[0].title == "Mine" && merged.clusters[0].items == ["a", "b"])
    }

    @Test func clusterEditsAreUndoable() async throws {
        let (store, _) = try TestSupport.newStore()
        let first = [CanvasCluster(id: "k", title: "One", items: ["a"], at: 1)]
        try await store.setClusters(boardKey: "library", first)
        let (_, undo) = try await store.recording(label: "Group") {
            try await store.setClusters(boardKey: "library", [CanvasCluster(id: "k", title: "One", items: []), CanvasCluster(id: "m", items: ["a"])])
        }
        #expect(try await store.canvasBoard(key: "library")?.clusters.count == 2)
        try await store.apply(undo)
        #expect(try await store.canvasBoard(key: "library")?.clusters == first)
    }
}
