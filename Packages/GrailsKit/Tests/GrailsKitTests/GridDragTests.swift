import AppKit
import GrailsDesign
import Testing
@testable import GrailsKit

@Suite struct GridDragTests {
    @Test func aTileWithNoOriginalStillDragsByItsId() {
        let offer = GridItemDrag.offer(
            itemID: "ada",
            isSection: false,
            original: URL(fileURLWithPath: "/tmp/ada/original.png"),
            fileOnDisk: false
        )
        #expect(offer?.itemID == "ada")
        #expect(offer?.fileURL == nil)
    }

    @Test func aMissingOriginalURLStillDragsByItsId() {
        let offer = GridItemDrag.offer(itemID: "ada", isSection: false, original: nil, fileOnDisk: false)
        #expect(offer?.itemID == "ada")
        #expect(offer?.fileURL == nil)
    }

    @Test func aLocalOriginalTravelsWithTheDrag() {
        let url = URL(fileURLWithPath: "/tmp/ada/original.png")
        let offer = GridItemDrag.offer(itemID: "ada", isSection: false, original: url, fileOnDisk: true)
        #expect(offer == GridItemDrag(itemID: "ada", fileURL: url))
    }

    @Test func aSectionHeaderIsNotAnItemDrag() {
        let offer = GridItemDrag.offer(itemID: "section:ada", isSection: true, original: nil, fileOnDisk: false)
        #expect(offer == nil)
    }

    @Test @MainActor func aClusterTitleDoesNotMoveTheWindow() {
        let title = GrailsClusterTitle(frame: NSRect(x: 0, y: 0, width: 120, height: 24))
        #expect(title.mouseDownCanMoveWindow == false)
    }
}
