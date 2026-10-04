import AppKit
import StashKit
import SwiftUI
import UniformTypeIdentifiers

struct GridView: NSViewRepresentable {
    var model: AppModel
    /// Clear space above the first row, for the floating top bar.
    var topInset: CGFloat = 0
    @AppStorage("tileSpacing") private var spacing: Double = 8
    @AppStorage("cornerRadius") private var cornerRadius: Double = 12
    @AppStorage("showAddedBy") private var showAddedBy = false

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
        cv.onZoom = { [weak c] factor, p in c?.hitch?.noteActivity(); c?.zoom(by: factor, at: p) }
        cv.onZoomEnd = { [weak c] in c?.scheduleSettle(after: 0.05) }
        cv.onScrollActivity = { [weak c] in c?.hitch?.noteActivity() }
        cv.keyHandler = { [weak c] event in
            guard let c, let action = ShortcutStore.shared.action(for: event, plainOnly: true) else { return false }
            c.model.run(action)
            return true
        }
        cv.onPaste = { [weak c] in c?.model.paste() }
        cv.contextMenuProvider = { [weak c] i in c?.contextMenu(forItemAt: i) }
        cv.onOptionClick = { [weak c] i in
            guard let c, let s = c.item(at: i), s.kind != .section else { return }
            c.model.toggleLike(ids: [s.id])
        }
        c.collectionView = cv

        let scroll = NSScrollView()
        scroll.documentView = cv
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.automaticallyAdjustsContentInsets = false
        scroll.contentInsets = NSEdgeInsets(top: topInset, left: 0, bottom: 16, right: 0)
        scroll.scrollerInsets = NSEdgeInsets(top: topInset, left: 0, bottom: 0, right: 0)
        scroll.contentView.scroll(to: NSPoint(x: 0, y: -topInset))
        scroll.reflectScrolledClipView(scroll.contentView)
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
        context.coordinator.update(model: model, spacing: spacing, cornerRadius: cornerRadius, showAddedBy: showAddedBy)
    }

    @MainActor
    final class Coordinator: NSObject, NSCollectionViewDataSource, NSCollectionViewDelegate, NSCollectionViewPrefetching {
        var model: AppModel
        weak var collectionView: StashCollectionView?
        let squareLayout = SquareLayout()
        let masonryLayout = MasonryLayout()
        let sectionedLayout = SectionedLayout()
        private var useSections = false
        private var sectionsSeen = -1
        var hitch: HitchMonitor?

        private var items: [ItemSummary] = []
        private var indexByID: [String: Int] = [:]
        private var version = -1
        private var layout: LibraryLayout?
        private var applying = false
        /// Tile width as currently shown. Follows the fingers during a gesture, then settles to fill the row.
        private var liveWidth: CGFloat = Zoom.defaultWidth
        private var lastModelWidth: CGFloat = 0
        private var settleWork: DispatchWorkItem?
        private var zoomAnimation: ZoomAnimation?
        private var lastZoomTick = 0
        private var mode: GridLayoutMode = .square
        private var cornerRadius: CGFloat = 8
        private var focusTick = 0
        private var scrollTick = 0
        private var showAddedBy = false
        /// Item index + its offset from the viewport top, restored after the layout changes size.
        private var anchor: (index: Int, offsetY: CGFloat)?

        init(model: AppModel) {
            self.model = model
            super.init()
        }

        private var scale: CGFloat { collectionView?.window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2 }
        private var activeLayout: TileLayout { useSections ? sectionedLayout : (mode == .square ? squareLayout : masonryLayout) }

        // MARK: SwiftUI → AppKit

        func update(model: AppModel, spacing: Double, cornerRadius: Double, showAddedBy: Bool) {
            self.model = model
            guard let cv = collectionView else { return }
            let sections = model.gridSections
            useSections = sections != nil
            let needsData = version != model.itemsVersion || sectionsSeen != model.sectionsVersion || layout != model.layout
            let spacingChanged = squareLayout.spacing != CGFloat(spacing)
            let radiusChanged = self.cornerRadius != CGFloat(cornerRadius)
            let modeChanged = mode != model.layoutMode
            let avatarsChanged = self.showAddedBy != showAddedBy
            self.showAddedBy = showAddedBy
            let resetScroll = scrollTick != model.scrollResetTick
            scrollTick = model.scrollResetTick
            let keptOrigin = cv.enclosingScrollView?.contentView.bounds.origin

            self.cornerRadius = CGFloat(cornerRadius)
            layout = model.layout
            mode = model.layoutMode
            for l in [squareLayout, masonryLayout, sectionedLayout] as [TileLayout] { l.spacing = CGFloat(spacing) }
            sectionedLayout.squareTiles = model.layoutMode == .square
            if lastZoomTick != model.gridZoomTick {
                lastZoomTick = model.gridZoomTick
                let delta = model.takeColumnDelta()
                if delta != 0 { stepColumns(delta) }
            }
            applyModelWidth()

            if cv.collectionViewLayout !== activeLayout { cv.collectionViewLayout = activeLayout }
            if needsData {
                if let sections {
                    // one header row per cluster, then its tiles
                    let byID = Dictionary(model.items.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
                    var flat: [ItemSummary] = []
                    flat.reserveCapacity(model.items.count + sections.count)
                    for sec in sections {
                        flat.append(.sectionHeader(id: sec.id, title: sec.title, count: sec.ids.count))
                        for id in sec.ids { if let it = byID[id] { flat.append(it) } }
                    }
                    items = flat
                } else {
                    items = model.items
                }
                sectionsSeen = model.sectionsVersion
                indexByID = Dictionary(uniqueKeysWithValues: items.enumerated().map { ($1.id, $0) })
                version = model.itemsVersion
                masonryLayout.aspects = items.map { s in
                    guard let w = s.width, let h = s.height, w > 0 else { return 1 }
                    return CGFloat(h) / CGFloat(w)
                }
                masonryLayout.dataVersion = version &+ model.sectionsVersion
                masonryLayout.invalidateLayout()
                sectionedLayout.aspects = masonryLayout.aspects
                sectionedLayout.headerFlags = items.map { $0.kind == .section }
                sectionedLayout.dataVersion = version &+ model.sectionsVersion &* 7919
                sectionedLayout.invalidateLayout()
                cv.reloadData()
                applySelection()
                // A refresh (a teammate's save arriving, an edit) keeps you where you were; a new view starts at the top.
                if let scroll = cv.enclosingScrollView {
                    activeLayout.prepare()
                    let range = scrollRange(scroll, contentHeight: activeLayout.collectionViewContentSize.height)
                    let y = resetScroll ? range.lowerBound : min(max(keptOrigin?.y ?? range.lowerBound, range.lowerBound), range.upperBound)
                    scroll.contentView.scroll(to: NSPoint(x: 0, y: y))
                    scroll.reflectScrolledClipView(scroll.contentView)
                }
            } else if avatarsChanged {
                cv.reloadData()
                applySelection()
            } else if spacingChanged || modeChanged || radiusChanged {
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

        // MARK: Continuous, pointer-anchored zoom

        private struct ZoomAnimation {
            var from: CGFloat, to: CGFloat, start: CFTimeInterval, duration: CFTimeInterval
            var anchor: (Int, CGFloat)?
        }
        private var zoomLink: CADisplayLink?

        /// Sets the grid's tile width from the model (startup, ⌘+ / ⌘−), animating unless it's the first layout.
        private func applyModelWidth() {
            guard abs(model.tileWidth - lastModelWidth) > 0.5 else { return }
            lastModelWidth = model.tileWidth
            if liveWidth == Zoom.defaultWidth && zoomLink == nil && items.isEmpty && version < 0 {
                setLiveWidth(model.tileWidth, exact: false)       // first layout: no animation
            } else {
                animateWidth(to: activeLayout.fillWidth(forTarget: model.tileWidth), anchor: centreAnchor())
            }
        }

        /// ⌘+ / ⌘−: animate to one column fewer (bigger tiles) or more.
        private func stepColumns(_ delta: Int) {
            let l = activeLayout
            // Rapid key presses chain: step from where the running animation is heading, not where it is now.
            let current: Int
            if let target = zoomAnimation?.to { current = max(1, Int((l.availableWidth + l.spacing) / (target + l.spacing) + 0.5)) }
            else { current = l.geometry().cols }
            let cols = max(1, current + delta)
            let tile = (l.availableWidth - CGFloat(cols - 1) * l.spacing) / CGFloat(cols)
            animateWidth(to: tile, anchor: centreAnchor())
        }

        private func setLiveWidth(_ w: CGFloat, exact: Bool) {
            liveWidth = w
            for l in [squareLayout, masonryLayout, sectionedLayout] as [TileLayout] { l.exact = exact; l.targetWidth = w }
        }

        /// One step of a pinch or ⌘-scroll: scale the tile size and keep the tile under the pointer under the pointer.
        func zoom(by factor: CGFloat, at point: NSPoint) {
            guard let cv = collectionView, factor.isFinite, factor > 0 else { return }
            cancelAnimation()
            settleWork?.cancel()
            let next = Zoom.clamp(liveWidth * factor)
            guard abs(next - liveWidth) > 0.01 else { scheduleSettle(); return }
            anchor = anchorFor(point: point, in: cv)
            setLiveWidth(next, exact: true)
            restoreAnchor()
            scheduleSettle()
        }

        /// A gesture that ends without an explicit end event (⌘-scroll) settles after a short pause.
        func scheduleSettle(after delay: TimeInterval = 0.22) {
            settleWork?.cancel()
            let work = DispatchWorkItem { [weak self] in MainActor.assumeIsolated { self?.settle() } }
            settleWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
        }

        private func settle() {
            let target = activeLayout.fillWidth(forTarget: liveWidth)
            animateWidth(to: target, anchor: centreAnchor())
        }

        private func animateWidth(to target: CGFloat, anchor: (Int, CGFloat)?) {
            guard let cv = collectionView else { return }
            cancelAnimation()
            let to = Zoom.clamp(target) == target ? target : Zoom.clamp(target)
            if abs(to - liveWidth) < 0.5 { finishZoom(at: to); return }
            zoomAnimation = ZoomAnimation(from: liveWidth, to: to, start: CACurrentMediaTime(), duration: 0.2, anchor: anchor)
            let link = cv.displayLink(target: self, selector: #selector(zoomTick(_:)))
            link.add(to: .main, forMode: .common)
            zoomLink = link
        }

        @objc private func zoomTick(_ l: CADisplayLink) {
            guard let a = zoomAnimation else { cancelAnimation(); return }
            hitch?.noteActivity()
            let t = min(1, (l.timestamp - a.start) / a.duration)
            let eased = 1 - pow(1 - t, 3)
            anchor = a.anchor
            setLiveWidth(a.from + (a.to - a.from) * CGFloat(eased), exact: true)
            restoreAnchor()
            if t >= 1 { cancelAnimation(); finishZoom(at: a.to) }
        }

        private func cancelAnimation() {
            zoomLink?.invalidate()
            zoomLink = nil
            zoomAnimation = nil
        }

        /// Back to "fill" mode at the settled width, remember it, and re-decode visible tiles for their new size.
        private func finishZoom(at width: CGFloat) {
            setLiveWidth(width, exact: false)
            lastModelWidth = width
            model.tileWidth = width
            if let cv = collectionView {
                let visible = Set(cv.indexPathsForVisibleItems())
                if !visible.isEmpty { cv.reloadItems(at: visible); applySelection() }
            }
        }

        /// Valid scroll offsets: the top inset (room for the floating bar) lets the origin go negative.
        private func scrollRange(_ scroll: NSScrollView, contentHeight: CGFloat) -> ClosedRange<CGFloat> {
            let lo = -scroll.contentInsets.top
            return lo...max(lo, contentHeight - scroll.contentView.bounds.height + scroll.contentInsets.bottom)
        }

        private func anchorFor(point: NSPoint, in cv: NSCollectionView) -> (Int, CGFloat)? {
            let top = cv.enclosingScrollView?.contentView.bounds.origin.y ?? cv.visibleRect.minY      // may be negative (inset)
            let path = cv.indexPathForItem(at: point) ?? nearestVisible(to: point, in: cv)
            guard let i = path?.item, let f = frame(of: i) else { return nil }
            return (i, f.minY - top)
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
            let range = scrollRange(scroll, contentHeight: activeLayout.collectionViewContentSize.height)
            let y = min(max(range.lowerBound, f.minY - a.offsetY), range.upperBound)
            scroll.contentView.scroll(to: NSPoint(x: 0, y: y))
            scroll.reflectScrolledClipView(scroll.contentView)
        }

        // MARK: Dev benchmark (STASH_BENCH=1)

        private var benchLink: CADisplayLink?
        private var benchStart: CFTimeInterval = 0
        private var benchLast: CFTimeInterval = 0

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
                let range = scrollRange(scroll, contentHeight: cv.frame.height)
                let y = min(max(range.lowerBound, scroll.contentView.bounds.origin.y + dy), range.upperBound)
                scroll.contentView.scroll(to: NSPoint(x: 0, y: y))
                scroll.reflectScrolledClipView(scroll.contentView)
            }

            if t < 6 { hitch?.setPhase("1-scroll-down"); scrollBy(4000 * dt) }
            else if t < 9 { hitch?.setPhase("2-scroll-up"); scrollBy(-4000 * dt) }
            else if t < 19 {
                hitch?.setPhase("3-zoom")
                scrollBy(1500 * dt)
                // continuous zoom, like a long pinch: 2.5 s in, 2.5 s out, repeated; the rate is ×1.7 per second
                let direction: CGFloat = Int((t - 9) / 2.5) % 2 == 0 ? 1 : -1
                let v = cv.visibleRect
                zoom(by: pow(1.7, direction * CGFloat(dt)), at: NSPoint(x: v.midX, y: v.midY))
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
            if s.kind == .section {
                cell.view.frame.size = activeLayout.layoutAttributesForItem(at: indexPath)?.frame.size ?? cell.view.frame.size
                cell.configureSection(s)
                return cell
            }
            cell.view.frame.size = activeLayout.layoutAttributesForItem(at: indexPath)?.frame.size ?? cell.view.frame.size
            // Files that only exist as sync placeholders must never be read while browsing (it would force a download).
            let original = model.originalURL(for: s)
            let cloudOnly = s.kind != .link && original.map { FileAvailability.of($0) == .cloudOnly } ?? false
            cell.configure(
                s, loader: .shared, layout: layout, original: cloudOnly ? nil : original, cornerRadius: cornerRadius,
                gravity: mode == .square ? .resizeAspect : .resizeAspectFill, scale: scale, cloudOnly: cloudOnly, showAddedBy: showAddedBy
            )
            return cell
        }

        func collectionView(_ cv: NSCollectionView, prefetchItemsAt indexPaths: [IndexPath]) {
            guard let layout else { return }
            let px = liveWidth * scale
            for ip in indexPaths { if let s = items[safe: ip.item], s.kind != .section { ThumbnailLoader.shared.prefetch(id: s.id, thumb: layout.thumbURL(s.id), pixels: px) } }
        }

        // MARK: Selection

        func collectionView(_ cv: NSCollectionView, didSelectItemsAt indexPaths: Set<IndexPath>) { pushSelection(cv) }
        func collectionView(_ cv: NSCollectionView, didDeselectItemsAt indexPaths: Set<IndexPath>) { pushSelection(cv) }

        private func pushSelection(_ cv: NSCollectionView) {
            guard !applying else { return }
            model.selection = Set(cv.selectionIndexPaths.compactMap { items[safe: $0.item] }.filter { $0.kind != .section }.map(\.id))
        }

        func previewSelection() {
            guard let cv = collectionView else { return }
            let first = cv.selectionIndexPaths.sorted().first(where: { items[safe: $0.item]?.kind != .section })
            if let id = first.flatMap({ items[safe: $0.item]?.id }) { model.openPreview(id) }
        }

        func escape() {
            collectionView?.deselectAll(nil)
            model.selection = []
        }

        func item(at i: Int) -> ItemSummary? { items[safe: i] }

        // MARK: Context menu

        func contextMenu(forItemAt index: Int) -> NSMenu? {
            guard let s = items[safe: index], s.kind != .section, let cv = collectionView else { return nil }
            if !model.selection.contains(s.id) {
                applying = true
                cv.selectionIndexPaths = [IndexPath(item: index, section: 0)]
                applying = false
                model.selection = [s.id]
            }
            return model.itemContextMenu(anchor: s, canvas: false)
        }

        // MARK: Drag out

        /// Each dragged tile carries its file (for Finder, Figma, Slack) and its id (for the sidebar's drop targets).
        func collectionView(_ cv: NSCollectionView, pasteboardWriterForItemAt indexPath: IndexPath) -> NSPasteboardWriting? {
            guard let s = items[safe: indexPath.item], s.kind != .section else { return nil }
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

/// NSMenuItem that runs a closure (menus here are built per right-click, so targets don't need to outlive them).
@MainActor
final class ClosureMenuItem: NSMenuItem {
    private let handler: @MainActor () -> Void
    init(title: String, handler: @escaping @MainActor () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(fire), keyEquivalent: "")
        target = self
    }
    required init(coder: NSCoder) { fatalError() }
    @objc private func fire() { handler() }
}
