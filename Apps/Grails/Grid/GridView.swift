import AppKit
import GrailsDesign
import GrailsKit
import SwiftUI
import UniformTypeIdentifiers

struct GridView: NSViewRepresentable {
    var model: AppModel
    /// Clear space above the first row, for the floating top bar.
    var topInset: CGFloat = 0
    /// The tag strip and mention bar above the grid. Applied inside the grid's frame, so a page switch never moves the frame.
    var chromeTop: CGFloat = 0
    /// Settings is over the library: hidden, so no hover, tracking area or key reaches the grid under the page.
    var dormant = false
    var memberDirectory: MemberDirectory
    @AppStorage("tileSpacing") private var spacing: Double = 8
    @AppStorage("showAddedBy") private var showAddedBy = false

    func makeCoordinator() -> Coordinator { Coordinator(model: model) }

    func makeNSView(context: Context) -> NSView {
        let c = context.coordinator
        let cv = GrailsCollectionView()
        cv.collectionViewLayout = c.squareLayout
        cv.autoresizingMask = [.width]
        cv.isSelectable = true
        cv.allowsMultipleSelection = true
        cv.allowsEmptySelection = true
        cv.backgroundColors = [.clear]
        c.attachDataSource(cv)
        cv.delegate = c
        cv.prefetchDataSource = c
        cv.register(ThumbCell.self, forItemWithIdentifier: ThumbCell.identifier)
        cv.setDraggingSourceOperationMask(.copy, forLocal: false)
        cv.setAccessibilityIdentifier("grid")
        cv.onPreview = { [weak c] in c?.previewSelection() }
        cv.onOpen = { [weak c] in c?.previewSelection() }
        cv.onClickOpen = { [weak c] i in c?.openItem(at: i) }
        cv.onEscape = { [weak c] in c?.escape() }
        cv.onSearch = { [weak c] in c?.model.focusSearchTick += 1 }
        cv.onRenameSection = { [weak c] i in c?.beginRenameSection(at: i) ?? false }
        cv.onToggleSection = { [weak c] i in c?.toggleSection(at: i) }
        cv.onZoom = { [weak c] factor, p in c?.hitch?.noteActivity(); c?.zoom(by: factor, at: p) }
        cv.onZoomEnd = { [weak c] in c?.flushPendingZoom(); c?.scheduleSettle(after: 0.03) }
        cv.onScrollActivity = { [weak c] in c?.hitch?.noteActivity() }
        cv.keyHandler = { [weak c] event in
            guard let c, let action = ShortcutStore.shared.action(for: event, plainOnly: true) else { return false }
            c.model.run(action)
            return true
        }
        cv.onPaste = { [weak c] in c?.model.paste() }
        cv.contextMenuProvider = { [weak c] i in c?.contextMenu(forItemAt: i) }
        cv.onAttached = { [weak c] in c?.wakePictures() }
        cv.onLayout = { [weak c] in c?.placePinnedHeader() }
        cv.onOptionClick = { [weak c] i in
            guard let c, let s = c.item(at: i), s.kind != .section else { return }
            c.model.toggleLike(ids: [TileKey.item(s.id)])
        }
        c.collectionView = cv
        c.installTileGeometry()
        c.installHover(on: cv)

        let scroll = GridScrollView()
        scroll.contentView = GridClipView()
        scroll.documentView = cv
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.automaticallyAdjustsContentInsets = false
        scroll.contentInsets = NSEdgeInsets(top: topInset, left: 0, bottom: 16, right: 0)
        scroll.scrollerInsets = NSEdgeInsets(top: topInset, left: 0, bottom: 0, right: 0)
        scroll.contentView.scroll(to: NSPoint(x: 0, y: -topInset))
        scroll.reflectScrolledClipView(scroll.contentView)
        scroll.autoresizingMask = [.width, .height]
        // the pinned title is pushed up past the top edge by the next one; the scroll view's edge cuts it off
        scroll.clipsToBounds = true
        c.pinnedHeader.onRename = { [weak c] i in c?.renamePinnedSection(at: i) }
        c.pinnedHeader.menuProvider = { [weak c] i in c?.contextMenu(forItemAt: i) }
        scroll.addFloatingSubview(c.pinnedHeader, for: .vertical)
        let container = GridContainer()
        container.wantsLayer = true
        scroll.frame = container.bounds
        container.addSubview(scroll)
        c.hitch = HitchMonitor.make()
        if let probe = c.hitch?.probe {
            probe.frame = NSRect(x: 0, y: 0, width: 2, height: 2)
            probe.alphaValue = 0.02
            container.addSubview(probe)
        }
        c.hitch?.start(on: cv)
        c.watchScroll(scroll)
        return container
    }

    func updateNSView(_ view: NSView, context: Context) {
        if view.isHidden != dormant { view.isHidden = dormant }
        (view as? GridContainer)?.chromeTop = chromeTop
        context.coordinator.update(
            model: model,
            directory: memberDirectory,
            spacing: spacing,
            cornerRadius: Ink.tileRadius,
            showAddedBy: showAddedBy
        )
    }

    @MainActor
    final class Coordinator: NSObject, NSCollectionViewDelegate, NSCollectionViewPrefetching, HoverVideoSurface {
        var model: AppModel
        weak var collectionView: GrailsCollectionView?
        private var diffable: NSCollectionViewDiffableDataSource<Int, String>?
        let squareLayout = SquareLayout()
        let masonryLayout = MasonryLayout()
        let sectionedLayout = SectionedLayout()
        let pinnedHeader = PinnedSectionHeader()
        private var useSections = false
        private var sectionsSeen = -1
        var hitch: HitchMonitor?

        private var items: [ItemSummary] = []
        private var indexByID: [String: Int] = [:]
        private var version = -1
        private var layout: LibraryLayout?
        private var applying = false
        private var lastModelWidth: CGFloat = 0
        private var settleWork: DispatchWorkItem?
        private var zoomAnimation: ZoomAnimation?
        private var lastZoomTick = 0
        private var lastSettleTick = 0
        private var settleUntil = Date.distantPast
        /// The page the grid's items belong to (`AppModel.shownScrollTick`). Read only when items arrive: the selection
        /// changes before the new page's items do, and an update in between must not use the switch up.
        private var pageTick = -1
        /// The grid was shown before the collection view had frames. One retry is in flight.
        private var bareRetry: DispatchWorkItem?
        /// How many times a view switch has asked again because the cells were not on screen yet.
        private var barePasses = 0
        private var scrollObserver: NSObjectProtocol?
        private var trimQueued = false
        /// Sync writes land many times a second. One grid update per quarter-second, not one per file.
        private var coalesceWork: DispatchWorkItem?
        private var lastDataApply = Date.distantPast
        private var mode: GridLayoutMode = .square
        private var cornerRadius: CGFloat = 8
        private var focusTick = 0
        private var showAddedBy = false
        private var avatarDirectory = MemberDirectory()
        /// Item index + its offset from the viewport top, restored after the layout changes size.
        private var anchor: ZoomAnchor?

        init(model: AppModel) {
            self.model = model
            super.init()
        }

        private var scale: CGFloat { collectionView?.window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2 }
        private var activeLayout: TileLayout { useSections ? sectionedLayout : (mode == .square ? squareLayout : masonryLayout) }

        isolated deinit {
            if let scrollObserver { NotificationCenter.default.removeObserver(scrollObserver) }
            ThumbnailLoader.shared.setResident(nil)
        }

        /// One row past the viewport stays decoded, so a small scroll doesn't flash back to placeholders.
        /// The pinned section title moves in the same call as the scroll (no queue hop), so it is never a frame behind.
        func watchScroll(_ scroll: NSScrollView) {
            scroll.contentView.postsBoundsChangedNotifications = true
            scrollObserver = NotificationCenter.default.addObserver(
                forName: NSView.boundsDidChangeNotification, object: scroll.contentView, queue: nil
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.placePinnedHeader()
                    self?.scheduleTrim()
                }
            }
        }

        /// Floats the title of the section under the viewport's top edge (see `PinnedSectionHeader`). The grid's own
        /// header rows stay where the layout put them, so a scroll never invalidates the layout.
        func placePinnedHeader() {
            guard useSections, let scroll = collectionView?.enclosingScrollView else { pinnedHeader.hide(); return }
            let headers = sectionedLayout.headerFrames()
            guard let f = SectionPins.floating(headers.map(\.frame), visibleTop: scroll.contentView.bounds.minY),
                  let s = items[safe: headers[f.index].index], s.kind == .section else { pinnedHeader.hide(); return }
            let laid = headers[f.index].frame
            let clusterId = s.id.hasPrefix("section:") ? String(s.id.dropFirst("section:".count)) : s.id
            // Floating subviews start below the top content inset; the title sticks to the clip view's top, as it always has.
            pinnedHeader.show(s, noted: model.notedClusters.contains(clusterId), at: headers[f.index].index,
                              frame: NSRect(x: laid.minX, y: f.offset - scroll.contentInsets.top, width: laid.width, height: laid.height))
        }

        /// Double-click on the pinned title: bring the section's own header row to the top edge, where the pinned copy
        /// was drawn, and rename that row in place.
        func renamePinnedSection(at index: Int) {
            guard let cv = collectionView, let scroll = cv.enclosingScrollView, let f = frame(of: index) else { return }
            let range = scrollRange(scroll, contentHeight: activeLayout.collectionViewContentSize.height)
            scroll.contentView.scroll(to: NSPoint(x: 0, y: min(max(f.minY, range.lowerBound), range.upperBound)))
            scroll.reflectScrolledClipView(scroll.contentView)
            cv.layoutSubtreeIfNeeded()
            _ = beginRenameSection(at: index)
        }

        // MARK: SwiftUI → AppKit

        func update(
            model: AppModel, directory: MemberDirectory, spacing: Double, cornerRadius: CGFloat, showAddedBy: Bool
        ) {
            self.model = model
            guard let cv = collectionView else { return }
            let sections = model.gridSections
            useSections = sections != nil
            let needsData = version != model.itemsVersion || sectionsSeen != model.sectionsVersion || layout != model.layout
            let spacingChanged = squareLayout.spacing != CGFloat(spacing)
            let radiusChanged = self.cornerRadius != cornerRadius
            let modeChanged = mode != model.layoutMode
            let avatarsChanged = self.showAddedBy != showAddedBy
            self.showAddedBy = showAddedBy
            let directoryChanged = directory != avatarDirectory
            let hadFaces = avatarDirectory != MemberDirectory()
            let affected = directoryChanged ? directory.changedTokens(from: avatarDirectory) : []
            if directoryChanged { avatarDirectory = directory }
            let keptOrigin = cv.enclosingScrollView?.contentView.bounds.origin

            self.cornerRadius = cornerRadius
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
            if lastSettleTick != model.settleTick { lastSettleTick = model.settleTick; settleUntil = Date().addingTimeInterval(3) }

            if cv.collectionViewLayout !== activeLayout { cv.collectionViewLayout = activeLayout }
            if needsData {
                let incoming = flattened(sections)
                let newPage = pageTick != model.shownScrollTick
                pageTick = model.shownScrollTick
                if newPage || items.isEmpty {
                    swapPage(to: incoming, toTop: newPage, keptOrigin: keptOrigin)
                } else {
                    scheduleSyncBatch()
                }
            } else if avatarsChanged {
                refreshVisible(keepPicture: true)
                applySelection()
            } else if directoryChanged, showAddedBy, !affected.isEmpty {
                refreshVisible(tokens: affected, keepPicture: true)
            } else if spacingChanged || modeChanged || radiusChanged {
                activeLayout.invalidateLayout()
                if radiusChanged { cv.visibleItems().forEach { ($0 as? ThumbCell)?.view.layer?.cornerRadius = self.cornerRadius } }
                if modeChanged {
                    let gravity: CALayerContentsGravity = mode == .square ? .resizeAspect : .resizeAspectFill
                    cv.visibleItems().forEach { ($0 as? ThumbCell)?.view.layer?.contentsGravity = gravity }
                }
            }
            if !needsData { applySelection() }
            if needsData, hadFaces, directoryChanged, showAddedBy, !affected.isEmpty {
                refreshVisible(tokens: affected, keepPicture: true)
            }
            restoreAnchor()

            applyDevScroll()
            placePinnedHeader()
            startBenchmarkIfRequested()
            if !devZoomApplied, !items.isEmpty, let u = ProcessInfo.processInfo.environment["GRAILS_ZOOM_DEMO"].flatMap(Double.init) {
                devZoomApplied = true       // dev: freeze the grid mid-zoom at this column count (pair with GRAILS_SNAPSHOT)
                let base = max(1, Int(u.rounded()))
                zoomBase = base
                let natural = activeLayout.tileWidth(forColumns: base)
                let want = (activeLayout.availableWidth - CGFloat(max(u, 1) - 1) * activeLayout.spacing) / CGFloat(max(u, 1))
                zoomScale = want / max(natural, 1)
                pushZoom()
            }

            // a hidden grid keeps the request until it shows again
            if focusTick != model.focusGridTick, !cv.isHiddenOrHasHiddenAncestor {
                focusTick = model.focusGridTick
                cv.window?.makeFirstResponder(cv)
            }
            runSettleIfDue(cv)
            materializeIfBare(cv)
            trimToViewport()
        }

        /// The collection view joined a window after a view switch. Display it so item views exist without a click.
        func wakePictures() {
            guard let cv = collectionView, cv.window != nil else { return }
            materializeIfBare(cv)
        }

        /// A page switch. The new page replaces the old one in one step and the whole grid crossfades once: nothing on the
        /// old page moves, nothing on the new one has motion of its own. Reduce Motion swaps at once.
        private func swapPage(to incoming: [ItemSummary], toTop: Bool, keptOrigin: NSPoint?) {
            guard let cv = collectionView else { return }
            coalesceWork?.cancel()
            coalesceWork = nil
            // the onboarding settle brings its own entrance
            if toTop, Date() >= settleUntil, let fade = PageCrossfade.transition(reduceMotion: ReduceMotion.isOn) {
                cv.enclosingScrollView?.superview?.layer?.add(fade, forKey: "page")
            }
            install(incoming)
            if let diffable { GridSyncBatch.replace(ids: incoming.map(\.id), in: diffable) }
            lastDataApply = Date()
            applySelection()
            // a refresh keeps you where you were; a new page starts at the top
            if let scroll = cv.enclosingScrollView {
                activeLayout.prepare()
                let range = scrollRange(scroll, contentHeight: activeLayout.collectionViewContentSize.height)
                let y = toTop ? range.lowerBound : min(max(keptOrigin?.y ?? range.lowerBound, range.lowerBound), range.upperBound)
                scroll.contentView.scroll(to: NSPoint(x: 0, y: y))
                scroll.reflectScrolledClipView(scroll.contentView)
            }
        }

        /// Canvas → Grid reloads before the collection view has frames, and nothing displays it again until a click.
        /// Keep displaying, a turn at a time, until the cells exist.
        private func materializeIfBare(_ cv: NSCollectionView) {
            guard cv.visibleItems().isEmpty, !items.isEmpty else { barePasses = 0; return }
            GridPictureLoad.materialize(cv)
            guard cv.visibleItems().isEmpty, barePasses < 45, bareRetry == nil else { return }
            barePasses += 1
            let work = DispatchWorkItem { [weak self] in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.bareRetry = nil
                    guard let cv = self.collectionView else { return }
                    self.materializeIfBare(cv)
                }
            }
            bareRetry = work
            DispatchQueue.main.async(execute: work)
        }

        /// Right out of onboarding the visible pictures settle in one after another (a short rise and fade, ease-out, no bounce). If the
        /// pictures haven't been laid out yet, the next update tries again for a few seconds.
        private func runSettleIfDue(_ cv: NSCollectionView) {
            guard Date() < settleUntil else { return }
            cv.layoutSubtreeIfNeeded()
            let cells = cv.visibleItems().compactMap { $0 as? ThumbCell }
            guard !cells.isEmpty else { return }
            settleUntil = .distantPast
            let reduce = ReduceMotion.isOn
            let ordered = cells.sorted { ($0.view.frame.minY, $0.view.frame.minX) < ($1.view.frame.minY, $1.view.frame.minX) }
            let now = CACurrentMediaTime()
            for (i, cell) in ordered.enumerated() {
                guard let layer = cell.view.layer else { continue }
                let begin = now + 0.15 + (reduce ? 0 : min(Double(i) * 0.03, 0.9))
                let curve = CAMediaTimingFunction.grailsStandard
                let fade = CABasicAnimation(keyPath: "opacity")
                fade.fromValue = 0; fade.toValue = 1; fade.duration = reduce ? 0.12 : 0.35
                let rise = CABasicAnimation(keyPath: "position.y")
                rise.fromValue = 12; rise.toValue = 0; rise.isAdditive = true; rise.duration = 0.45
                let group = CAAnimationGroup()
                group.animations = reduce ? [fade] : [fade, rise]
                group.duration = reduce ? 0.12 : 0.45
                group.beginTime = begin
                group.fillMode = .backwards
                group.timingFunction = curve
                layer.add(group, forKey: "settle")
            }
        }

        private func flattened(_ sections: [GridSection]?) -> [ItemSummary] {
            guard let sections else { return model.items }
            let byID = Dictionary(model.items.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            var flat: [ItemSummary] = []
            flat.reserveCapacity(model.items.count + sections.count)
            for sec in sections {
                flat.append(.sectionHeader(id: sec.id, title: sec.title, count: sec.ids.count, collapsed: sec.collapsed))
                if sec.collapsed { continue }
                // a picture in two folders is a second tile, under its own key
                for key in sec.ids {
                    guard var it = byID[TileKey.item(key)] else { continue }
                    it.id = key
                    flat.append(it)
                }
            }
            return flat
        }

        /// The next sync batch is applied once, at most every quarter-second, from whatever the model holds then.
        private func scheduleSyncBatch() {
            if coalesceWork != nil { return }
            let delay = GridSyncBatch.delay(since: lastDataApply)
            let work = DispatchWorkItem { [weak self] in
                self?.coalesceWork = nil
                self?.flushSyncBatch()
            }
            coalesceWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
        }

        private func flushSyncBatch() {
            guard let cv = collectionView else { return }
            guard version != model.itemsVersion || sectionsSeen != model.sectionsVersion || layout != model.layout else { return }
            let incoming = flattened(model.gridSections)
            let plan = GridSyncBatch.plan(from: items, to: incoming)
            let keptOrigin = cv.enclosingScrollView?.contentView.bounds.origin
            publish(incoming)
            refreshVisible(ids: Set(plan.chromeIDs), keepPicture: true)
            lastDataApply = Date()
            applySelection()
            if let scroll = cv.enclosingScrollView {
                activeLayout.prepare()
                let range = scrollRange(scroll, contentHeight: activeLayout.collectionViewContentSize.height)
                let y = min(max(keptOrigin?.y ?? range.lowerBound, range.lowerBound), range.upperBound)
                scroll.contentView.scroll(to: NSPoint(x: 0, y: y))
                scroll.reflectScrolledClipView(scroll.contentView)
            }
            if coalesceWork == nil, version != model.itemsVersion || sectionsSeen != model.sectionsVersion {
                scheduleSyncBatch()
            }
        }

        func attachDataSource(_ cv: GrailsCollectionView) {
            let source = NSCollectionViewDiffableDataSource<Int, String>(collectionView: cv) { [weak self] collectionView, indexPath, id in
                self?.makeCell(collectionView, indexPath: indexPath, id: id) ?? NSCollectionViewItem()
            }
            diffable = source
            cv.dataSource = source
        }

        /// Publishes a sync batch on the page already showing as one snapshot.
        private func publish(_ incoming: [ItemSummary]) {
            let plan = GridSyncBatch.plan(from: items, to: incoming)
            install(incoming)
            if let diffable {
                GridSyncBatch.apply(plan, ids: incoming.map(\.id), to: diffable)
            }
        }

        private func refreshVisible(ids: Set<String>? = nil, tokens: Set<String>? = nil, keepPicture: Bool) {
            guard let cv = collectionView, let layout else { return }
            for case let cell as ThumbCell in cv.visibleItems() {
                // A picture cell is the item it already shows. Its index path can lag an insert, and configuring it as the new row would drop the thumbnail.
                let summary: ItemSummary?
                if let id = cell.itemID, let index = indexByID[id] {
                    summary = items[safe: index]
                } else if let ip = cv.indexPath(for: cell) {
                    summary = items[safe: ip.item]
                } else {
                    summary = nil
                }
                guard let s = summary else { continue }
                if let ids, !ids.contains(s.id) { continue }
                if let tokens, !MemberDirectory.lists(s.addedBy, in: tokens) { continue }
                if s.kind == .section {
                    let clusterId = s.id.hasPrefix("section:") ? String(s.id.dropFirst("section:".count)) : s.id
                    cell.configureSection(s, noted: model.notedClusters.contains(clusterId))
                    continue
                }
                let original = model.originalURL(for: s)
                let cloudOnly = s.kind != .link && original.map { FileAvailability.of($0) == .cloudOnly } ?? false
                cell.configure(
                    s, loader: .shared, layout: layout, original: cloudOnly ? nil : original, cornerRadius: cornerRadius,
                    gravity: mode == .square ? .resizeAspect : .resizeAspectFill, scale: scale, cloudOnly: cloudOnly, showAddedBy: showAddedBy,
                    keepPicture: keepPicture, addedBy: showAddedBy ? model.face(for: s.addedBy) : nil
                )
            }
        }

        private func install(_ incoming: [ItemSummary]) {
            items = incoming
            let count = incoming.count
            squareLayout.itemCount = count
            masonryLayout.itemCount = count
            sectionedLayout.itemCount = count
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
        }

        private func applySelection() {
            guard let cv = collectionView else { return }
            // the tile that was clicked stays the selected one; a selection made elsewhere shows on every tile of those items
            let shown = Set(cv.selectionIndexPaths.compactMap { items[safe: $0.item] }.filter { $0.kind != .section }.map { TileKey.item($0.id) })
            guard shown != model.selection else { return }
            let wanted = Set(model.selection.isEmpty ? [] : items.indices.filter { items[$0].kind != .section && model.selection.contains(TileKey.item(items[$0].id)) }.map { IndexPath(item: $0, section: 0) })
            guard wanted != cv.selectionIndexPaths else { return }
            applying = true
            cv.selectionIndexPaths = wanted
            applying = false
        }

        // MARK: Continuous, pointer-anchored zoom
        //
        // A pinch scales the arrangement already on screen, so tiles keep their neighbours and the one under the
        // pointer stays put (Photos). When the fingers lift, that picture eases into the column count that fits.

        private struct ZoomAnchor { var index: Int; var fy: CGFloat; var vy: CGFloat }
        private struct ZoomAnimation {
            var base: Int
            var fromScale: CGFloat
            var toColumns: Int
            var start: CFTimeInterval
            var duration: CFTimeInterval
            var anchor: ZoomAnchor?
        }
        private var zoomLink: CADisplayLink?
        /// Pinch and ⌘-scroll can deliver several events before the next frame. One layout per frame is enough.
        private var zoomCoalesceLink: CADisplayLink?
        private var pendingZoomFactor: CGFloat = 1
        private var pendingZoomPoint = NSPoint.zero
        /// Column count the pinch started from, and how far that arrangement is scaled.
        private var zoomBase: Int?
        private var zoomScale: CGFloat = 1
        private var gestureStart: CGFloat = 0
        private var devZoomApplied = false
        /// GRAILS_SCROLL is applied once, after the sections exist, so a snapshot can catch headers mid-scroll.
        private var devScrolled = false
        private var allLayouts: [TileLayout] { [squareLayout, masonryLayout, sectionedLayout] }

        /// Column count the magnified tiles correspond to (fractional).
        private var columnsNow: CGFloat {
            guard let b = zoomBase else { return CGFloat(activeLayout.restColumns) }
            let w = max(1, activeLayout.tileWidth(forColumns: b) * zoomScale)
            return (activeLayout.availableWidth + activeLayout.spacing) / (w + activeLayout.spacing)
        }

        /// Tile width as currently shown (for sizing pictures).
        private var shownTile: CGFloat {
            if let b = zoomBase { return activeLayout.tileWidth(forColumns: b) * zoomScale }
            return activeLayout.tileWidth(forColumns: max(1, activeLayout.restColumns))
        }

        private func pushZoom(settleTo: Int? = nil, settleMix: CGFloat = 0) {
            for l in allLayouts { l.setZoom(base: zoomBase, scale: zoomScale, settleTo: settleTo, mix: settleMix) }
        }

        /// Tile width clamped to what the column range allows.
        private func clampedWidth(_ w: CGFloat) -> CGFloat {
            let r = activeLayout.columnRange
            let lo = activeLayout.tileWidth(forColumns: r.upperBound)
            let hi = activeLayout.tileWidth(forColumns: r.lowerBound)
            return min(max(w, max(lo, Zoom.minWidth)), min(hi, Zoom.maxWidth))
        }

        /// Restores the saved tile width (startup); zooming itself goes through `finishZoom`.
        private func applyModelWidth() {
            guard abs(model.tileWidth - lastModelWidth) > 0.5 else { return }
            lastModelWidth = model.tileWidth
            for l in allLayouts { l.targetWidth = model.tileWidth }
        }

        private func clampColumns(_ c: Int) -> Int {
            let r = activeLayout.columnRange
            return min(max(c, r.lowerBound), r.upperBound)
        }

        /// ⌘+ / ⌘−: glide to one column fewer (bigger tiles) or more.
        private func stepColumns(_ delta: Int) {
            // Rapid key presses chain: step from where the running animation is heading, not where it is now.
            let current = zoomAnimation?.toColumns ?? Int(columnsNow.rounded())
            if zoomAnimation != nil {
                cancelAnimation()
                finishZoom(columns: current)
            }
            if zoomBase == nil {
                zoomBase = activeLayout.restColumns
                zoomScale = 1
                gestureStart = CGFloat(zoomBase!)
            }
            beginSettle(to: clampColumns(current + delta), anchor: centreAnchor())
        }

        /// One step of a pinch or ⌘-scroll. Events that land before the next frame are folded into one layout.
        func zoom(by factor: CGFloat, at point: NSPoint) {
            guard factor.isFinite, factor > 0, collectionView != nil else { return }
            pendingZoomFactor *= factor
            pendingZoomPoint = point
            guard zoomCoalesceLink == nil, let cv = collectionView else { return }
            let link = cv.displayLink(target: self, selector: #selector(coalescedZoom(_:)))
            link.add(to: .main, forMode: .common)
            zoomCoalesceLink = link
        }

        func flushPendingZoom() { drainZoom() }

        @objc private func coalescedZoom(_ l: CADisplayLink) { drainZoom() }

        private func drainZoom() {
            zoomCoalesceLink?.invalidate()
            zoomCoalesceLink = nil
            let factor = pendingZoomFactor
            pendingZoomFactor = 1
            guard abs(factor - 1) > 0.0000001 else { return }
            applyZoom(by: factor, at: pendingZoomPoint)
        }

        /// Scale the grid in place and keep the tile under the pointer under the pointer.
        private func applyZoom(by factor: CGFloat, at point: NSPoint) {
            guard let cv = collectionView, factor.isFinite, factor > 0 else { return }
            if let anim = zoomAnimation {
                let dest = anim.toColumns
                cancelAnimation()
                finishZoom(columns: dest)
            }
            settleWork?.cancel()
            if zoomBase == nil {
                zoomBase = activeLayout.restColumns
                zoomScale = 1
                gestureStart = CGFloat(zoomBase!)
            }
            let baseW = activeLayout.tileWidth(forColumns: zoomBase!)
            let next = clampedWidth(baseW * zoomScale * factor) / baseW
            guard abs(next - zoomScale) > 0.0005 else { scheduleSettle(); return }
            ThumbCell.layoutLite = true
            performZoomFrame {
                anchor = anchorFor(point: point, in: cv)
                zoomScale = next
                pushZoom()
                restoreAnchor()
            }
            scheduleSettle()
        }

        /// One layout pass with AppKit's own frame animation turned off, so a pinch doesn't lag a frame behind.
        private func performZoomFrame(_ body: () -> Void) {
            NSAnimationContext.beginGrouping()
            NSAnimationContext.current.duration = 0
            NSAnimationContext.current.allowsImplicitAnimation = false
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            body()
            CATransaction.commit()
            NSAnimationContext.endGrouping()
        }

        /// A gesture that ends without an explicit end event (⌘-scroll) settles after a short pause.
        func scheduleSettle(after delay: TimeInterval = 0.12) {
            settleWork?.cancel()
            let work = DispatchWorkItem { [weak self] in MainActor.assumeIsolated { self?.settle() } }
            settleWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
        }

        /// Picks the whole column count to land on. A pinch that has clearly gone one way commits that way.
        private func settle() {
            guard zoomBase != nil else { return }
            let u = columnsNow
            let moved = u - gestureStart
            let target: Int
            if moved < -0.15 { target = Int((u + 0.2).rounded(.down)) }
            else if moved > 0.15 { target = Int((u - 0.2).rounded(.up)) }
            else { target = Int(u.rounded()) }
            beginSettle(to: clampColumns(target), anchor: centreAnchor())
        }

        /// Ease the scaled picture into `columns`. Same column count is only a size correction; a new count
        /// glides each tile from where the pinch left it into its slot.
        private func beginSettle(to columns: Int, anchor: ZoomAnchor?) {
            ThumbCell.layoutLite = true
            cancelAnimation()
            let base = zoomBase ?? columns
            let fromScale = zoomScale
            let same = base == columns && abs(fromScale - 1) < 0.001
            if same { finishZoom(columns: columns); return }
            if zoomBase == nil { zoomBase = base; zoomScale = 1 }
            let duration = base == columns ? Motion.quick : Motion.zoomGlide(columnsChanged: Double(abs(columns - base)))
            zoomAnimation = ZoomAnimation(base: base, fromScale: fromScale, toColumns: columns, start: CACurrentMediaTime(), duration: duration, anchor: anchor)
            guard let cv = collectionView else { return }
            let link = cv.displayLink(target: self, selector: #selector(zoomTick(_:)))
            link.add(to: .main, forMode: .common)
            zoomLink = link
        }

        @objc private func zoomTick(_ l: CADisplayLink) {
            guard let a = zoomAnimation else { cancelAnimation(); return }
            hitch?.noteActivity()
            let t = min(1, max(0, (l.targetTimestamp - a.start) / a.duration))
            let eased = 1 - pow(1 - t, 4)          // quick start off the fingers, long soft landing
            performZoomFrame {
                anchor = a.anchor
                zoomBase = a.base
                if a.base == a.toColumns {
                    zoomScale = a.fromScale + (1 - a.fromScale) * CGFloat(eased)
                    pushZoom()
                } else {
                    zoomScale = a.fromScale
                    pushZoom(settleTo: a.toColumns, settleMix: CGFloat(eased))
                }
                restoreAnchor()
            }
            if t >= 1 { cancelAnimation(); finishZoom(columns: a.toColumns) }
        }

        private func cancelAnimation() {
            zoomLink?.invalidate()
            zoomLink = nil
            zoomAnimation = nil
        }

        /// Back to rest at a whole column count: remember it and sharpen the pictures for their new size.
        private func finishZoom(columns: Int) {
            let width = activeLayout.tileWidth(forColumns: columns)
            zoomBase = nil
            zoomScale = 1
            ThumbCell.layoutLite = false
            for l in allLayouts { l.targetWidth = width }
            pushZoom()
            lastModelWidth = width
            model.tileWidth = width
            if let cv = collectionView {
                for case let cell as ThumbCell in cv.visibleItems() {
                    cell.view.needsLayout = true
                    cell.refreshResolution(loader: .shared, scale: scale)
                }
            }
            trimToViewport()
        }

        /// Dev: GRAILS_SCROLL=0...1 places the grid partway down, once sections are showing.
        private func applyDevScroll() {
            guard !devScrolled, useSections, !items.isEmpty,
                  let frac = ProcessInfo.processInfo.environment["GRAILS_SCROLL"].flatMap(Double.init),
                  let scroll = collectionView?.enclosingScrollView else { return }
            devScrolled = true
            activeLayout.prepare()
            let range = scrollRange(scroll, contentHeight: activeLayout.collectionViewContentSize.height)
            let t = min(max(frac, 0), 1)
            let y = range.lowerBound + (range.upperBound - range.lowerBound) * CGFloat(t)
            scroll.contentView.scroll(to: NSPoint(x: 0, y: y))
            scroll.reflectScrolledClipView(scroll.contentView)
        }

        /// Valid scroll offsets: the top inset (room for the floating bar) lets the origin go negative.
        private func scrollRange(_ scroll: NSScrollView, contentHeight: CGFloat) -> ClosedRange<CGFloat> {
            let lo = -scroll.contentInsets.top
            return lo...max(lo, contentHeight - scroll.contentView.bounds.height + scroll.contentInsets.bottom)
        }

        /// The tile under `point` (or the nearest one) and where in it the point sits, read from the layout so it's
        /// right even mid-glide.
        private func anchorFor(point: NSPoint, in cv: NSCollectionView) -> ZoomAnchor? {
            let top = cv.enclosingScrollView?.contentView.bounds.origin.y ?? cv.visibleRect.minY      // may be negative (inset)
            let l = activeLayout
            l.prepare()
            guard let b = l.nearestFrame(to: point, in: cv.visibleRect), b.frame.height > 0 else { return nil }
            return ZoomAnchor(index: b.index, fy: min(max((point.y - b.frame.minY) / b.frame.height, 0), 1), vy: point.y - top)
        }

        private func centreAnchor() -> ZoomAnchor? {
            guard let cv = collectionView else { return nil }
            let v = cv.visibleRect
            return anchorFor(point: NSPoint(x: v.midX, y: v.midY), in: cv)
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
            let y = min(max(range.lowerBound, f.minY + a.fy * f.height - a.vy), range.upperBound)
            scroll.contentView.scroll(to: NSPoint(x: 0, y: y))
            scroll.reflectScrolledClipView(scroll.contentView)
        }

        // MARK: Dev benchmark (GRAILS_BENCH=1)

        private var benchLink: CADisplayLink?
        private var benchStart: CFTimeInterval = 0
        private var benchLast: CFTimeInterval = 0

        func startBenchmarkIfRequested() {
            guard ProcessInfo.processInfo.environment["GRAILS_BENCH"] != nil, benchLink == nil, !items.isEmpty,
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

        // MARK: Cells

        private func makeCell(_ cv: NSCollectionView, indexPath: IndexPath, id: String) -> NSCollectionViewItem {
            let cell = cv.makeItem(withIdentifier: ThumbCell.identifier, for: indexPath) as! ThumbCell
            guard let layout, let s = indexByID[id].flatMap({ items[safe: $0] }) else { return cell }
            if s.kind == .section {
                cell.view.frame.size = activeLayout.layoutAttributesForItem(at: indexPath)?.frame.size ?? cell.view.frame.size
                let clusterId = s.id.hasPrefix("section:") ? String(s.id.dropFirst("section:".count)) : s.id
                cell.configureSection(s, noted: model.notedClusters.contains(clusterId))
                return cell
            }
            cell.view.frame.size = activeLayout.layoutAttributesForItem(at: indexPath)?.frame.size ?? cell.view.frame.size
            // Files that only exist as sync placeholders must never be read while browsing (it would force a download).
            let original = model.originalURL(for: s)
            let cloudOnly = s.kind != .link && original.map { FileAvailability.of($0) == .cloudOnly } ?? false
            cell.configure(
                s, loader: .shared, layout: layout, original: cloudOnly ? nil : original, cornerRadius: cornerRadius,
                gravity: mode == .square ? .resizeAspect : .resizeAspectFill, scale: scale, cloudOnly: cloudOnly, showAddedBy: showAddedBy,
                addedBy: showAddedBy ? model.face(for: s.addedBy) : nil
            )
            return cell
        }

        func collectionView(_ cv: NSCollectionView, prefetchItemsAt indexPaths: [IndexPath]) {
            guard zoomBase == nil, let layout else { return }
            let keep = residentIDs(in: cv)
            guard !keep.isEmpty else { return }
            let px = shownTile * scale
            for ip in indexPaths {
                let id = items[safe: ip.item].map { TileKey.item($0.id) }
                guard let s = items[safe: ip.item], let id, s.kind != .section, keep.contains(id) else { continue }
                ThumbnailLoader.shared.prefetch(id: id, thumb: layout.thumbURL(id), pixels: px)
            }
        }

        func collectionView(_ cv: NSCollectionView, cancelPrefetchingForItemsAt indexPaths: [IndexPath]) {
            let keep = residentIDs(in: cv)
            guard !keep.isEmpty else { return }
            var drop = Set<String>()
            for ip in indexPaths {
                guard let s = items[safe: ip.item], s.kind != .section, !keep.contains(TileKey.item(s.id)) else { continue }
                drop.insert(TileKey.item(s.id))
            }
            ThumbnailLoader.shared.cancelPrefetches(drop)
        }

        /// Ids whose pictures may stay decoded: what's on screen, plus about one row above and below.
        private func residentIDs(in cv: NSCollectionView) -> Set<String> {
            guard let scroll = cv.enclosingScrollView else { return [] }
            let clip = scroll.contentView.bounds
            guard clip.width > 1, clip.height > 1 else { return [] }
            var rect = clip
            rect.origin.y -= overscan
            rect.size.height += overscan * 2
            activeLayout.prepare()
            var keep = Set<String>()
            for a in activeLayout.layoutAttributesForElements(in: rect) {
                guard let item = a.indexPath?.item, let s = items[safe: item], s.kind != .section else { continue }
                keep.insert(TileKey.item(s.id))
            }
            for case let cell as ThumbCell in cv.visibleItems() {
                if let id = cell.itemID { keep.insert(TileKey.item(id)) }
            }
            return keep
        }

        private var overscan: CGFloat {
            let tile = max(shownTile, 1)
            return (mode == .square ? tile : tile * 2) + activeLayout.spacing
        }

        private func scheduleTrim() {
            guard zoomBase == nil, !trimQueued else { return }
            trimQueued = true
            DispatchQueue.main.async { [weak self] in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.trimQueued = false
                    self.trimToViewport()
                }
            }
        }

        /// Drop decoded pictures and prefetches that have left the window, and start the next row only.
        private func trimToViewport() {
            guard zoomBase == nil, let cv = collectionView, cv.window != nil else { return }
            let keep = residentIDs(in: cv)
            guard !keep.isEmpty else { return }
            ThumbnailLoader.shared.setResident(keep)
            guard let layout else { return }
            let visible = Set(cv.visibleItems().compactMap { ($0 as? ThumbCell)?.itemID })
            let px = shownTile * scale
            for id in keep where !visible.contains(id) {
                guard let i = indexByID[id], let s = items[safe: i], s.kind != .section else { continue }
                ThumbnailLoader.shared.prefetch(id: s.id, thumb: layout.thumbURL(s.id), pixels: px, priority: .low)
            }
        }

        // MARK: Selection

        func collectionView(_ cv: NSCollectionView, didSelectItemsAt indexPaths: Set<IndexPath>) { pushSelection(cv) }
        func collectionView(_ cv: NSCollectionView, didDeselectItemsAt indexPaths: Set<IndexPath>) { pushSelection(cv) }

        private func pushSelection(_ cv: NSCollectionView) {
            guard !applying else { return }
            let ids = Set(cv.selectionIndexPaths.compactMap { items[safe: $0.item] }.filter { $0.kind != .section }.map { TileKey.item($0.id) })
            // AppKit can select the tile on right-click before the menu is built. That selection is the menu's target.
            if isContextClick { model.selectForContextMenu(ids) } else { model.selection = ids }
        }

        /// Right-click, or control-click, is asking for the context menu.
        private var isContextClick: Bool {
            guard let event = NSApp.currentEvent else { return false }
            switch event.type {
            case .rightMouseDown, .rightMouseUp, .rightMouseDragged:
                return true
            case .leftMouseDown, .leftMouseUp:
                return event.modifierFlags.contains(.control)
            default:
                return false
            }
        }

        /// One click opens a picture (sections are only for renaming and collapsing).
        func openItem(at index: Int) {
            guard let s = items[safe: index], s.kind != .section else { return }
            model.openPreview(TileKey.item(s.id))
        }

        func previewSelection() {
            guard let cv = collectionView else { return }
            let first = cv.selectionIndexPaths.sorted().first(where: { items[safe: $0.item]?.kind != .section })
            if let id = first.flatMap({ items[safe: $0.item]?.id }) { model.openPreview(TileKey.item(id)) }
        }

        /// The arrow in front of a section's title folds it to its title, or opens it again.
        func toggleSection(at index: Int) {
            guard let s = items[safe: index], s.kind == .section else { return }
            model.toggleClusterCollapsed(s.id.hasPrefix("section:") ? String(s.id.dropFirst("section:".count)) : s.id)
        }

        /// Double-clicking a section's title edits its name in place.
        func beginRenameSection(at index: Int) -> Bool {
            guard let cv = collectionView, let s = items[safe: index], s.kind == .section,
                  let cell = cv.item(at: IndexPath(item: index, section: 0)) as? ThumbCell else { return false }
            let id = s.id.hasPrefix("section:") ? String(s.id.dropFirst("section:".count)) : s.id
            cell.beginRenamingSection(text: s.name) { [weak self] name in self?.model.renameCluster(id, to: name) }
            return true
        }

        // MARK: Preview flight

        /// The tile's rectangle in window coordinates, after jumping it into view if it was scrolled out.
        private func windowRect(ofItem id: String) -> CGRect? {
            guard let cv = collectionView, let scroll = cv.enclosingScrollView, let i = indexByID[id], let f = frame(of: i) else { return nil }
            activeLayout.prepare()
            let clip = scroll.contentView.bounds, inset = scroll.contentInsets
            if f.minY < clip.minY + inset.top || f.maxY > clip.maxY - inset.bottom {
                let range = scrollRange(scroll, contentHeight: activeLayout.collectionViewContentSize.height)
                let y = min(max(range.lowerBound, f.midY - clip.height / 2), range.upperBound)
                scroll.contentView.scroll(to: NSPoint(x: 0, y: y))
                scroll.reflectScrolledClipView(scroll.contentView)
                cv.layoutSubtreeIfNeeded()
            }
            // A tile under the right edge is flown to like any other: the grid never reflows for the panels, and the preview
            // lifts its clip and fades its details column on the flight's clock (see `PreviewFlight`).
            return cv.convert(f, to: nil)
        }

        private func setTileHidden(_ id: String, _ hidden: Bool) {
            guard let cv = collectionView, let i = indexByID[id], let cell = cv.item(at: IndexPath(item: i, section: 0)) else { return }
            cell.view.alphaValue = hidden ? 0 : 1
        }

        func installTileGeometry() {
            model.tileGeometry = TileGeometry(
                rect: { [weak self] id in self?.windowRect(ofItem: id) },
                hide: { [weak self] id, hidden in self?.setTileHidden(id, hidden) })
        }

        // MARK: Hover video
        //
        // One tracking area on the grid (not one per tile): each move asks the layout which tile is under the pointer, so it is
        // right after any scroll, zoom glide or section change. The player lives inside that tile's cell and moves with it.

        private let hoverTracker = HoverTracker()

        func installHover(on cv: GrailsCollectionView) {
            hoverTracker.install(on: cv)
            hoverTracker.onMove = { [weak self] e in self?.hoverMoved(e) }
            hoverTracker.onExit = { [weak self] _ in
                guard let self else { return }
                HoverVideo.shared.pointerLeft(self)
            }
        }

        func hoverMoved(_ e: NSEvent) {
            guard let cv = collectionView else { return }
            var id: String?
            if cv.isFrontmost(atWindowPoint: e.locationInWindow), let ip = cv.indexPathForItem(at: cv.convert(e.locationInWindow, from: nil)),
               let s = items[safe: ip.item], s.kind != .section {
                id = s.id
            }
            HoverVideo.shared.pointerMoved(over: id, in: self)
        }

        func hoverHost(for id: String) -> HoverVideo.Host? {
            guard let cv = collectionView, let i = indexByID[id], let cell = cv.item(at: IndexPath(item: i, section: 0)) as? ThumbCell,
                  cell.itemID == id, cell.view.window != nil else { return nil }
            // the same fit as the still (see `configure`), so the crossfade doesn't jump
            return .view(cell.view, mode == .square ? .resizeAspect : .resizeAspectFill)
        }

        func hoverSummary(for id: String) -> ItemSummary? { indexByID[id].flatMap { items[safe: $0] } }
        func hoverOriginal(for s: ItemSummary) -> URL? { model.originalURL(for: s) }

        func escape() {
            collectionView?.deselectAll(nil)
            model.selection = []
        }

        func item(at i: Int) -> ItemSummary? { items[safe: i] }

        // MARK: Context menu

        func contextMenu(forItemAt index: Int) -> NSMenu? {
            guard let s = items[safe: index] else { return nil }
            if s.kind == .section {
                let clusterId = s.id.hasPrefix("section:") ? String(s.id.dropFirst("section:".count)) : s.id
                let menu = NSMenu()
                let title = s.name
                let item = ClosureMenuItem(title: "Notes") { [weak model] in
                    guard let model, let board = model.canvasBoardKey else { return }
                    model.showClusterNotes(board: board, id: clusterId, title: title)
                }
                item.image = NSImage(systemSymbolName: "note.text", accessibilityDescription: nil)
                menu.addItem(item)
                return menu
            }
            guard let cv = collectionView else { return nil }
            if !model.selection.contains(TileKey.item(s.id)) {
                applying = true
                cv.selectionIndexPaths = [IndexPath(item: index, section: 0)]
                applying = false
                model.selectForContextMenu([TileKey.item(s.id)])
            }
            return model.itemContextMenu(anchor: s, canvas: false)
        }

        // MARK: Drag out

        func collectionView(_ cv: NSCollectionView, pasteboardWriterForItemAt indexPath: IndexPath) -> NSPasteboardWriting? {
            guard let s = items[safe: indexPath.item] else { return nil }
            let url = model.originalURL(for: s)
            let onDisk = url.map { FileManager.default.fileExists(atPath: $0.path) } ?? false
            guard let drag = GridItemDrag.offer(itemID: TileKey.item(s.id), isSection: s.kind == .section, original: url, fileOnDisk: onDisk) else { return nil }
            (cv as? GrailsCollectionView)?.dragBegan = true
            let pb = NSPasteboardItem()
            if let ids = try? JSONEncoder().encode([drag.itemID]) {
                pb.setData(ids, forType: NSPasteboard.PasteboardType(UTType.grailsItems.identifier))
            }
            if let file = drag.fileURL {
                pb.setString(file.absoluteString, forType: .fileURL)
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
