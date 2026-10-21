import AppKit
import Testing
@testable import GrailsKit

@Suite struct GridPictureLoadTests {
    /// A collection view that was reloaded off-screen does not build item views until something displays it.
    /// A click used to be that something. Materializing has to do it with no mouse event.
    @Test @MainActor func materializeBuildsCellsWithoutAClick() {
        let source = CellSource()
        let cv = NSCollectionView(frame: NSRect(x: 0, y: 0, width: 180, height: 180))
        let flow = NSCollectionViewFlowLayout()
        flow.itemSize = NSSize(width: 40, height: 40)
        cv.collectionViewLayout = flow
        cv.register(NSCollectionViewItem.self, forItemWithIdentifier: CellSource.identifier)
        cv.dataSource = source
        cv.reloadData()
        #expect(source.made == 0)

        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 180, height: 180))
        scroll.documentView = cv
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 180, height: 180), styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = scroll
        GridPictureLoad.materialize(cv)
        #expect(source.made == 4)
    }

    /// A sync batch inserts the new item and leaves the cells already on screen, pictures included, alone.
    @Test @MainActor func cellIdentityAndThumbnailsSurviveASyncBatch() {
        let ident = NSUserInterfaceItemIdentifier("sync-batch-cell")
        let thumbs = ["a": "thumb-a", "b": "thumb-b", "c": "thumb-c", "d": "thumb-d"]
        let made = CallLog()
        let cv = NSCollectionView(frame: NSRect(x: 0, y: 0, width: 400, height: 80))
        let flow = NSCollectionViewFlowLayout()
        flow.itemSize = NSSize(width: 40, height: 40)
        cv.collectionViewLayout = flow
        cv.register(TokenCell.self, forItemWithIdentifier: ident)
        let dataSource = NSCollectionViewDiffableDataSource<Int, String>(collectionView: cv) { collectionView, indexPath, id in
            made.note(id)
            let cell = collectionView.makeItem(withIdentifier: ident, for: indexPath) as! TokenCell
            cell.itemID = id
            cell.token = thumbs[id] ?? ""
            return cell
        }
        cv.dataSource = dataSource
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 400, height: 80))
        scroll.documentView = cv
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 80), styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = scroll

        let before = [row("a"), row("b", name: "Lamp"), row("c")]
        GridSyncBatch.apply(GridSyncBatch.plan(from: [], to: before), ids: before.map(\.id), to: dataSource)
        GridPictureLoad.materialize(cv)
        let original = cellsByID(cv)
        #expect(original.count == 3)
        let identityA = ObjectIdentifier(original["a"]!)
        let identityB = ObjectIdentifier(original["b"]!)
        let identityC = ObjectIdentifier(original["c"]!)

        var after = before
        after[1].name = "Renamed"
        made.counts.removeAll()
        let incoming = [row("d")] + after
        let plan = GridSyncBatch.plan(from: before, to: incoming)
        #expect(plan.insertIndexes == [0])
        #expect(plan.deleteIndexes.isEmpty)
        #expect(plan.pictureIDs.isEmpty)
        #expect(plan.chromeIDs == ["b"])
        #expect(plan.keptIDs == ["a", "b", "c"])
        GridSyncBatch.apply(plan, ids: incoming.map(\.id), to: dataSource)
        GridPictureLoad.materialize(cv)

        let surviving = cellsByID(cv)
        #expect(ObjectIdentifier(surviving["a"]!) == identityA)
        #expect(ObjectIdentifier(surviving["b"]!) == identityB)
        #expect(ObjectIdentifier(surviving["c"]!) == identityC)
        #expect(surviving["a"]?.token == "thumb-a")
        #expect(surviving["b"]?.token == "thumb-b")
        #expect(surviving["c"]?.token == "thumb-c")
        #expect(surviving["d"]?.token == "thumb-d")
        #expect(made.counts["a"] == nil)
        #expect(made.counts["b"] == nil)
        #expect(made.counts["c"] == nil)
        #expect(made.counts["d"] == 1)

        // A later batch that changes nothing does not ask for those cells again.
        made.counts.removeAll()
        let unchanged = GridSyncBatch.plan(from: incoming, to: incoming)
        GridSyncBatch.apply(unchanged, ids: incoming.map(\.id), to: dataSource)
        let settled = cellsByID(cv)
        #expect(ObjectIdentifier(settled["a"]!) == identityA)
        #expect(ObjectIdentifier(settled["b"]!) == identityB)
        #expect(ObjectIdentifier(settled["c"]!) == identityC)
        #expect(settled["d"]?.token == "thumb-d")
        #expect(made.counts.isEmpty)
        let now = Date(timeIntervalSince1970: 1_000)
        let waited = GridSyncBatch.delay(since: now.addingTimeInterval(-0.1), now: now)
        #expect(abs(waited - 0.15) < 0.001)
    }

    /// A full page switching to an empty one. The old tiles are gone in the same pass that empties the list: no tile is left
    /// visible for a frame, and none is moved to a new place on its way out.
    @Test @MainActor func aFullPageSwapsToAnEmptyPageInOnePass() {
        let (cv, dataSource, window) = pageGrid()
        let full = (0..<24).map { "p\($0)" }
        GridSyncBatch.replace(ids: full, in: dataSource)
        GridPictureLoad.materialize(cv)
        let before = shownTiles(cv)
        #expect(before.count == 24)

        GridSyncBatch.replace(ids: [], in: dataSource)
        // no run loop turn and no layout pass: this is what the next frame would draw
        #expect(shownTiles(cv).isEmpty)
        #expect(cv.numberOfItems(inSection: 0) == 0)
        GridPictureLoad.materialize(cv)
        #expect(shownTiles(cv).isEmpty)
        _ = window
    }

    /// A page switch between two pages that share items. In the same pass, only the new page's tiles are drawn, each at its
    /// place on the new page, and no tile is left animating from where it was.
    @Test @MainActor func aPageSwitchDrawsOnlyTheNewPageInOnePass() {
        let (cv, dataSource, window) = pageGrid()
        let first = (0..<12).map { "p\($0)" }
        GridSyncBatch.replace(ids: first, in: dataSource)
        GridPictureLoad.materialize(cv)
        #expect(shownTiles(cv).count == 12)

        let second = ["q0", "q1", "q2"] + first.suffix(6)
        GridSyncBatch.replace(ids: second, in: dataSource)
        GridPictureLoad.materialize(cv)
        let shown = shownTiles(cv)
        #expect(shown.map(\.id).sorted() == second.sorted())
        let flow = cv.collectionViewLayout!
        for tile in shown {
            let index = second.firstIndex(of: tile.id)!
            #expect(tile.frame == flow.layoutAttributesForItem(at: IndexPath(item: index, section: 0))?.frame)
        }
        // nothing left animating toward a new place
        #expect(cv.subviews.allSatisfy { ($0.layer?.animationKeys() ?? []).isEmpty })
        _ = window
    }
}

@MainActor
private func pageGrid() -> (NSCollectionView, NSCollectionViewDiffableDataSource<Int, String>, NSWindow) {
    let ident = NSUserInterfaceItemIdentifier("page-cell")
    let cv = NSCollectionView(frame: NSRect(x: 0, y: 0, width: 300, height: 300))
    let flow = NSCollectionViewFlowLayout()
    flow.itemSize = NSSize(width: 40, height: 40)
    cv.collectionViewLayout = flow
    cv.register(TokenCell.self, forItemWithIdentifier: ident)
    let dataSource = NSCollectionViewDiffableDataSource<Int, String>(collectionView: cv) { collectionView, indexPath, id in
        let cell = collectionView.makeItem(withIdentifier: ident, for: indexPath) as! TokenCell
        cell.itemID = id
        cell.view.identifier = NSUserInterfaceItemIdentifier(id)
        return cell
    }
    cv.dataSource = dataSource
    let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 300, height: 300))
    scroll.documentView = cv
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 300), styleMask: [.borderless], backing: .buffered, defer: false)
    window.contentView = scroll
    return (cv, dataSource, window)
}

/// Item views that would be drawn: in the collection view, not hidden, not faded out.
@MainActor
private func shownTiles(_ cv: NSCollectionView) -> [(id: String, frame: NSRect)] {
    cv.subviews.compactMap { v in
        guard let id = v.identifier?.rawValue, !v.isHidden, v.alphaValue > 0.01, (v.layer?.opacity ?? 1) > 0.01 else { return nil }
        return (id, v.frame)
    }
}

private func row(_ id: String, name: String = "Name") -> ItemSummary {
    ItemSummary(
        id: id, kind: .image, name: name, ext: "jpg", width: 40, height: 40, bytes: 10,
        liked: false, addedAt: .distantPast, addedBy: "", deletedAt: nil, site: nil, linkDisplay: nil, badge: nil
    )
}

@MainActor
private final class CallLog {
    var counts: [String: Int] = [:]
    func note(_ id: String) { counts[id, default: 0] += 1 }
}

@MainActor
private final class TokenCell: NSCollectionViewItem {
    var itemID = ""
    var token = ""
}

@MainActor
private func cellsByID(_ cv: NSCollectionView) -> [String: TokenCell] {
    var out: [String: TokenCell] = [:]
    for case let cell as TokenCell in cv.visibleItems() {
        out[cell.itemID] = cell
    }
    return out
}

@MainActor
private final class CellSource: NSObject, NSCollectionViewDataSource {
    static let identifier = NSUserInterfaceItemIdentifier("grid-picture-cell")
    var made = 0

    func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int { 4 }

    func collectionView(_ collectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
        made += 1
        return collectionView.makeItem(withIdentifier: Self.identifier, for: indexPath)
    }
}
