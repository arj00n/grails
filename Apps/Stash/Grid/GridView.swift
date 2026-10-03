import AppKit
import StashKit
import SwiftUI
import UniformTypeIdentifiers

struct GridView: NSViewRepresentable {
    var model: AppModel
    @AppStorage("tileSpacing") private var spacing: Double = 8
    @AppStorage("cornerRadius") private var cornerRadius: Double = 8

    func makeCoordinator() -> Coordinator { Coordinator(model: model) }

    func makeNSView(context: Context) -> NSView {
        let c = context.coordinator
        let cv = StashCollectionView()
        cv.collectionViewLayout = c.squareLayout
        cv.autoresizingMask = [.width]
        cv.isSelectable = true
        cv.allowsMultipleSelection = true
        cv.allowsEmptySelection = true
        cv.backgroundColors = [.clear]
        cv.dataSource = c
        cv.delegate = c
        cv.prefetchDataSource = c
        cv.register(ThumbCell.self, forItemWithIdentifier: ThumbCell.identifier)
        cv.setDraggingSourceOperationMask(.copy, forLocal: false)
        cv.setAccessibilityIdentifier("grid")
        cv.onPreview = { [weak c] in c?.previewSelection() }
        cv.onOpen = { [weak c] in c?.previewSelection() }
        cv.onEscape = { [weak c] in c?.escape() }
        cv.onZoom = { [weak c] step, p in c?.hitch?.noteActivity(); c?.zoom(step: step, at: p) }
        cv.onScrollActivity = { [weak c] in c?.hitch?.noteActivity() }
        cv.keyHandler = { [weak c] event in
            guard let c, let action = ShortcutStore.shared.action(for: event, plainOnly: true) else { return false }
            c.model.run(action)
            return true
        }
        cv.onOptionClick = { [weak c] i in
            guard let c, let s = c.item(at: i) else { return }
            c.model.toggleLike(ids: [s.id])
        }
        c.collectionView = cv

        let scroll = NSScrollView()
        scroll.documentView = cv
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.automaticallyAdjustsContentInsets = true
        scroll.autoresizingMask = [.width, .height]
        let container = NSView()
        scroll.frame = container.bounds
        container.addSubview(scroll)
        c.hitch = HitchMonitor.make()
        if let probe = c.hitch?.probe {
            probe.frame = NSRect(x: 0, y: 0, width: 2, height: 2)
            probe.alphaValue = 0.02
            container.addSubview(probe)
        }
        c.hitch?.start(on: cv)
        return container
    }

    func updateNSView(_ view: NSView, context: Context) {
        context.coordinator.update(model: model, spacing: spacing, cornerRadius: cornerRadius)
    }

    @MainActor
    final class Coordinator: NSObject, NSCollectionViewDataSource, NSCollectionViewDelegate, NSCollectionViewPrefetching {
        var model: AppModel
        weak var collectionView: StashCollectionView?
        let squareLayout = SquareLayout()
        let masonryLayout = MasonryLayout()
        var hitch: HitchMonitor?

        private var items: [ItemSummary] = []
        private var indexByID: [String: Int] = [:]
        private var version = -1
        private var layout: LibraryLayout?
        private var applying = false
        private var zoomStep = -1
        private var mode: GridLayoutMode = .square
        private var cornerRadius: CGFloat = 8
        private var focusTick = 0
        /// Item index + its offset from the viewport top, restored after the layout changes size.
        private var anchor: (index: Int, offsetY: CGFloat)?

        init(model: AppModel) {
            self.model = model
            super.init()
        }

        private var scale: CGFloat { collectionView?.window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2 }
        private var activeLayout: TileLayout { mode == .square ? squareLayout : masonryLayout }

        // MARK: SwiftUI → AppKit

        func update(model: AppModel, spacing: Double, cornerRadius: Double) {
            self.model = model
            guard let cv = collectionView else { return }
            let needsData = version != model.itemsVersion || layout != model.layout
            let spacingChanged = squareLayout.spacing != CGFloat(spacing)
            let radiusChanged = self.cornerRadius != CGFloat(cornerRadius)
            let zoomChanged = zoomStep != model.zoomStep
            let modeChanged = mode != model.layoutMode

            self.cornerRadius = CGFloat(cornerRadius)
            layout = model.layout
            mode = model.layoutMode
            zoomStep = model.zoomStep
            for l in [squareLayout, masonryLayout] as [TileLayout] {
                l.spacing = CGFloat(spacing)
                l.targetWidth = Zoom.widths[model.zoomStep]
            }

            if zoomChanged && !needsData && anchor == nil { anchor = centreAnchor() }

            if modeChanged { cv.collectionViewLayout = activeLayout }
            if needsData {
                items = model.items
                indexByID = Dictionary(uniqueKeysWithValues: items.enumerated().map { ($1.id, $0) })
                version = model.itemsVersion
                masonryLayout.aspects = items.map { s in
                    guard let w = s.width, let h = s.height, w > 0 else { return 1 }
                    return CGFloat(h) / CGFloat(w)
                }
                masonryLayout.dataVersion = version
                masonryLayout.invalidateLayout()
                cv.reloadData()
                applySelection()
            } else if zoomChanged || spacingChanged || modeChanged || radiusChanged {
                activeLayout.invalidateLayout()
                if radiusChanged { cv.visibleItems().forEach { ($0 as? ThumbCell)?.view.layer?.cornerRadius = self.cornerRadius } }
                if modeChanged { cv.reloadData() }
            }
            if !needsData { applySelection() }
            restoreAnchor()

            startBenchmarkIfRequested()

            if focusTick != model.focusGridTick {
                focusTick = model.focusGridTick
                cv.window?.makeFirstResponder(cv)
            }
        }

        private func applySelection() {
            guard let cv = collectionView else { return }
            let wanted = Set(model.selection.compactMap { indexByID[$0] }.map { IndexPath(item: $0, section: 0) })
            guard wanted != cv.selectionIndexPaths else { return }
            applying = true
            cv.selectionIndexPaths = wanted
            applying = false
        }

        // MARK: Pointer-anchored zoom

        func zoom(step: Int, at point: NSPoint) {
            let next = min(max(model.zoomStep + step, 0), Zoom.maxStep)
            guard next != model.zoomStep, let cv = collectionView else { return }
            anchor = anchorFor(point: point, in: cv)
            model.zoomStep = next
        }

        private func anchorFor(point: NSPoint, in cv: NSCollectionView) -> (Int, CGFloat)? {
            let visible = cv.visibleRect
            let path = cv.indexPathForItem(at: point) ?? nearestVisible(to: point, in: cv)
            guard let i = path?.item, let f = frame(of: i) else { return nil }
            return (i, f.minY - visible.minY)
        }

        private func centreAnchor() -> (Int, CGFloat)? {
            guard let cv = collectionView else { return nil }
            let v = cv.visibleRect
            return anchorFor(point: NSPoint(x: v.midX, y: v.midY), in: cv)
        }

        private func nearestVisible(to p: NSPoint, in cv: NSCollectionView) -> IndexPath? {
            cv.indexPathsForVisibleItems().min { a, b in
                dist(frame(of: a.item), p) < dist(frame(of: b.item), p)
            }
        }

        private func dist(_ r: CGRect?, _ p: NSPoint) -> CGFloat {
            guard let r else { return .greatestFiniteMagnitude }
            return hypot(r.midX - p.x, r.midY - p.y)
        }

        private func frame(of i: Int) -> CGRect? {
            activeLayout.layoutAttributesForItem(at: IndexPath(item: i, section: 0))?.frame
        }

        private func restoreAnchor() {
            guard let a = anchor, let cv = collectionView, let scroll = cv.enclosingScrollView else { return }
            anchor = nil
            activeLayout.prepare()
            guard let f = frame(of: a.index) else { return }
            let maxY = max(0, activeLayout.collectionViewContentSize.height - scroll.contentView.bounds.height)
            let y = min(max(0, f.minY - a.offsetY), maxY)
            scroll.contentView.scroll(to: NSPoint(x: 0, y: y))
            scroll.reflectScrolledClipView(scroll.contentView)
        }

        // MARK: Dev benchmark (STASH_BENCH=1)

        private var benchLink: CADisplayLink?
        private var benchStart: CFTimeInterval = 0
        private var benchLast: CFTimeInterval = 0
        private var benchStepsDone = 0

        func startBenchmarkIfRequested() {
            guard ProcessInfo.processInfo.environment["STASH_BENCH"] != nil, benchLink == nil, !items.isEmpty,
                  let cv = collectionView else { return }
            benchStart = CACurrentMediaTime()
            benchLast = benchStart
            benchLink = cv.displayLink(target: self, selector: #selector(benchTick(_:)))
            benchLink?.add(to: .main, forMode: .common)
        }

        /// 0–6 s fast scroll down (≈4000 pt/s), 6–9 s back up, 9–19 s zoom through every step while scrolling.
        @objc private func benchTick(_ l: CADisplayLink) {
            guard let cv = collectionView, let scroll = cv.enclosingScrollView else { return }
            let now = l.timestamp
            let t = now - benchStart
            let dt = now - benchLast
            benchLast = now
            hitch?.noteActivity()

            func scrollBy(_ dy: CGFloat) {
                let maxY = max(0, cv.frame.height - scroll.contentView.bounds.height)
                let y = min(max(0, scroll.contentView.bounds.origin.y + dy), maxY)
                scroll.contentView.scroll(to: NSPoint(x: 0, y: y))
                scroll.reflectScrolledClipView(scroll.contentView)
            }

            if t < 6 { hitch?.setPhase("1-scroll-down"); scrollBy(4000 * dt) }
            else if t < 9 { hitch?.setPhase("2-scroll-up"); scrollBy(-4000 * dt) }
            else if t < 19 {
                hitch?.setPhase("3-zoom")
                scrollBy(1500 * dt)
                let sequence = [3, 4, 5, 4, 3, 2, 1, 0, 1, 2]
                let due = Int((t - 9) / 1.0)
                if benchStepsDone <= due, due < sequence.count {
                    let target = sequence[due]
                    let dir = target > model.zoomStep ? 1 : -1
                    let v = cv.visibleRect
                    zoom(step: dir, at: NSPoint(x: v.midX, y: v.midY))
                    benchStepsDone = due + 1
                }
            } else {
                benchLink?.invalidate()
                hitch?.finish()
            }
        }

        // MARK: Data source

        func collectionView(_ cv: NSCollectionView, numberOfItemsInSection section: Int) -> Int { items.count }

        func collectionView(_ cv: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
            let cell = cv.makeItem(withIdentifier: ThumbCell.identifier, for: indexPath) as! ThumbCell
            guard let layout, let s = items[safe: indexPath.item] else { return cell }
            cell.view.frame.size = activeLayout.layoutAttributesForItem(at: indexPath)?.frame.size ?? cell.view.frame.size
            cell.configure(
                s, loader: .shared, layout: layout, original: model.originalURL(for: s), cornerRadius: cornerRadius,
                gravity: mode == .square ? .resizeAspect : .resizeAspectFill, scale: scale
            )
            return cell
        }

        func collectionView(_ cv: NSCollectionView, prefetchItemsAt indexPaths: [IndexPath]) {
            guard let layout else { return }
            let px = Zoom.widths[zoomStep] * scale
            for ip in indexPaths { if let s = items[safe: ip.item] { ThumbnailLoader.shared.prefetch(id: s.id, thumb: layout.thumbURL(s.id), pixels: px) } }
        }

        // MARK: Selection

        func collectionView(_ cv: NSCollectionView, didSelectItemsAt indexPaths: Set<IndexPath>) { pushSelection(cv) }
        func collectionView(_ cv: NSCollectionView, didDeselectItemsAt indexPaths: Set<IndexPath>) { pushSelection(cv) }

        private func pushSelection(_ cv: NSCollectionView) {
            guard !applying else { return }
            model.selection = Set(cv.selectionIndexPaths.compactMap { items[safe: $0.item]?.id })
        }

        func previewSelection() {
            guard let cv = collectionView else { return }
            let first = cv.selectionIndexPaths.sorted().first
            if let id = first.flatMap({ items[safe: $0.item]?.id }) { model.openPreview(id) }
        }

        func escape() {
            collectionView?.deselectAll(nil)
            model.selection = []
        }

        func item(at i: Int) -> ItemSummary? { items[safe: i] }

        // MARK: Drag out

        /// Each dragged tile carries its file (for Finder, Figma, Slack) and its id (for the sidebar's drop targets).
        func collectionView(_ cv: NSCollectionView, pasteboardWriterForItemAt indexPath: IndexPath) -> NSPasteboardWriting? {
            guard let s = items[safe: indexPath.item] else { return nil }
            let pb = NSPasteboardItem()
            if let ids = try? JSONEncoder().encode([s.id]) { pb.setData(ids, forType: NSPasteboard.PasteboardType(UTType.stashItems.identifier)) }
            if let url = model.originalURL(for: s), FileManager.default.fileExists(atPath: url.path) {
                pb.setString(url.absoluteString, forType: .fileURL)
            }
            return pb
        }
    }
}

extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}
