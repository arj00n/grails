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

    @Test @MainActor func gridSurfacesDoNotMoveTheWindow() {
        let views: [NSView] = [
            GridSurface(frame: NSRect(x: 0, y: 0, width: 80, height: 80)),
            GridSurfaceCollection(frame: NSRect(x: 0, y: 0, width: 80, height: 80)),
            GridSurfaceImage(frame: NSRect(x: 0, y: 0, width: 28, height: 28)),
            GridSurfaceScroll(frame: NSRect(x: 0, y: 0, width: 80, height: 80)),
            GridSurfaceClip(frame: NSRect(x: 0, y: 0, width: 80, height: 80)),
        ]
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 80, height: 80),
            styleMask: [.titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.isMovableByWindowBackground = true
        for view in views {
            #expect(view.mouseDownCanMoveWindow == false)
            window.contentView?.addSubview(view)
            #expect(view.mouseDownCanMoveWindow == false)
            view.removeFromSuperview()
        }
    }

    @Test @MainActor func aPlaceholderIconPassesTheClickToTheTile() {
        let host = NSView(frame: NSRect(x: 0, y: 0, width: 80, height: 80))
        let tile = GridSurface(frame: host.bounds)
        let icon = GridSurfaceImage(frame: NSRect(x: 26, y: 26, width: 28, height: 28))
        host.addSubview(tile)
        tile.addSubview(icon)
        #expect(icon.hitTest(NSPoint(x: 40, y: 40)) == nil)
        #expect(icon.mouseDownCanMoveWindow == false)
        #expect(tile.mouseDownCanMoveWindow == false)
    }

    @Test @MainActor func aClusterTitleDoesNotMoveTheWindow() {
        let title = GrailsClusterTitle(frame: NSRect(x: 0, y: 0, width: 120, height: 24))
        #expect(title.mouseDownCanMoveWindow == false)
    }
}
