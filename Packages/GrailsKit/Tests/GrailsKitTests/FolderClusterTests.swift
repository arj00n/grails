import Foundation
import Testing
@testable import GrailsKit

@Suite struct FolderClusterTests {
    let brand = FolderClusters.Folder(id: "F1", title: "Brand", members: ["a", "b"])
    let web = FolderClusters.Folder(id: "F2", title: "Web", members: ["b", "c"])

    @Test func eachFolderIsAClusterAndTheRestIsLoose() {
        let out = FolderClusters.reconcile(stored: [], folders: [brand, web], visible: ["a", "b", "c", "d"])
        #expect(out.map(\.id) == [FolderClusters.looseID, "F1", "F2"])
        #expect(out.map(\.title) == ["", "Brand", "Web"])
        #expect(out.map(\.items) == [["d"], ["a", "b"], ["b", "c"]])
    }

    @Test func aPictureInTwoFoldersIsInBothClusters() {
        let out = FolderClusters.reconcile(stored: [], folders: [brand, web], visible: ["b"])
        #expect(out.map(\.items) == [["b"], ["b"]])
    }

    @Test func savedLayoutAndOrderAreKept() {
        let saved = CanvasCluster(id: "F1", title: "Old name", x: 500, y: 80, width: 900, tile: 400, items: ["b", "gone", "a"], at: 5)
        let out = FolderClusters.reconcile(stored: [saved], folders: [brand], visible: ["a", "b"])
        let c = try! #require(out.first { $0.id == "F1" })
        #expect((c.x, c.y, c.width, c.tile) == (500, 80, 900, 400))
        #expect(c.items == ["b", "a"])
        #expect(c.title == "Brand")
    }

    @Test func aNewFolderGoesRightOfEverything() {
        let saved = CanvasCluster(id: "F1", x: 0, y: 40, width: 1000, items: ["a"])
        let out = FolderClusters.reconcile(stored: [saved], folders: [brand, web], visible: ["a", "b", "c"])
        let fresh = try! #require(out.first { $0.id == "F2" })
        #expect(fresh.x == 1160)
        #expect(fresh.y == 40)
    }

    @Test func theFirstUntitledClusterBecomesTheLooseOne() {
        let old = CanvasCluster(id: "X", title: "", x: 7, y: 9, items: ["d"])
        let out = FolderClusters.reconcile(stored: [old], folders: [brand], visible: ["a", "d"])
        let loose = try! #require(out.first)
        #expect(loose.id == FolderClusters.looseID)
        #expect((loose.x, loose.y) == (7, 9))
    }

    @Test func namedClustersFromBeforeFoldersAreStrays() {
        let named = CanvasCluster(id: "N", title: "Moodboard", items: ["a"])
        let untitled = CanvasCluster(id: "U", title: " ", items: ["b"])
        let folder = CanvasCluster(id: "F1", title: "Brand", items: ["a"])
        #expect(FolderClusters.strays([named, untitled, folder], folders: ["F1"]).map(\.id) == ["N"])
    }

    @Test func movingATileMovesItBetweenFolders() {
        let old = [CanvasCluster(id: "F1", title: "Brand", items: ["a", "b"]), CanvasCluster(id: "F2", title: "Web", items: ["c"])]
        let new = [CanvasCluster(id: "F1", title: "Brand", items: ["b"]), CanvasCluster(id: "F2", title: "Web", items: ["c", "a"])]
        let e = FolderClusters.edit(from: old, to: new, folders: ["F1", "F2"])
        #expect(e.removed == ["F1": ["a"]])
        #expect(e.added == ["F2": ["a"]])
        #expect(e.created.isEmpty && e.renamed.isEmpty)
    }

    @Test func aNewClusterIsANewFolderAndAnEmptiedOneLosesItsItems() {
        let old = [CanvasCluster(id: "F1", title: "Brand", items: ["a"])]
        let new = [CanvasCluster(id: "NEW", title: "", items: ["a"])]
        let e = FolderClusters.edit(from: old, to: new, folders: ["F1"])
        #expect(e.created.map(\.id) == ["NEW"])
        #expect(e.removed == ["F1": ["a"]])
    }

    @Test func renamingAClusterRenamesItsFolderButNeverTheLooseOne() {
        let old = [CanvasCluster(id: "F1", title: "Brand", items: ["a"]), CanvasCluster(id: FolderClusters.looseID, items: ["d"])]
        let new = [CanvasCluster(id: "F1", title: "Identity", items: ["a"]), CanvasCluster(id: FolderClusters.looseID, title: "Hmm", items: ["d"])]
        let e = FolderClusters.edit(from: old, to: new, folders: ["F1"])
        #expect(e.renamed == ["F1": "Identity"])
        #expect(e.isEmpty == false && e.added.isEmpty && e.removed.isEmpty)
    }

    @Test func layoutOnlyEditsChangeNoFolder() {
        var moved = CanvasCluster(id: "F1", title: "Brand", items: ["a", "b"])
        let old = [moved]
        moved.x = 900; moved.tile = 500; moved.items = ["b", "a"]
        #expect(FolderClusters.edit(from: old, to: [moved], folders: ["F1"]).isEmpty)
    }

    @Test func repeatedPicturesGetTheirOwnTileKeys() {
        let keyed = TileKey.keyed([CanvasCluster(id: "F1", items: ["a", "b"]), CanvasCluster(id: "F2", items: ["b", "c"])])
        #expect(keyed[0].items == ["a", "b"])
        #expect(keyed[1].items[0] != "b")
        #expect(TileKey.item(keyed[1].items[0]) == "b")
        #expect(TileKey.unkeyed(keyed).map(\.items) == [["a", "b"], ["b", "c"]])
    }

    @Test func aTileDroppedWhereItsItemAlreadyIsCountsOnce() {
        let keyed = TileKey.keyed([CanvasCluster(id: "F1", items: ["b"]), CanvasCluster(id: "F2", items: ["b"])])
        let dropped = ClusterOps.move([keyed[0].items[0]], to: .cluster("F2", index: 0), in: keyed)
        #expect(TileKey.unkeyed(dropped).map(\.items) == [["b"]])
    }
}
