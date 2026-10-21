import GrailsDesign
import GrailsKit
import GrailsSync
import SwiftUI
import UniformTypeIdentifiers

struct RootView: View {
    @Bindable var model: AppModel
    @AppStorage("appearance") private var appearance = "system"
    @Environment(\.grailsReduceMotion) private var reduceMotion
    @State private var dropTargeted = false
    @State private var searchFocused = false

    static let sidebarWidth: CGFloat = 240
    static let infoWidth: CGFloat = GrailsInfoSplit<EmptyView, EmptyView>.columnWidth
    static let barHeight: CGFloat = 44
    /// A little air above the first row, under the bar.
    static let topInset: CGFloat = 10

    var body: some View {
        ZStack(alignment: .topLeading) {
            // The library stays mounted under Settings, so closing Settings finds it exactly as it was left.
            ZStack(alignment: .topLeading) {
                workArea
                sidebar
                workspaceMenu
                libraryOverlays
            }
            .allowsHitTesting(!model.settings.isOpen)
            .accessibilityHidden(model.settings.isOpen)
            settingsPage
            windowOverlays
        }
        .background(Ink.canvas)
        .background(WindowChrome())
        .ignoresSafeArea()
        .preferredColorScheme(AppearanceChoice.scheme(stored: appearance))
        .tint(Ink.text)
        .font(.grailsBody(13))
        .grailsSheet(item: $model.smartEditor) { SmartFolderEditor(model: model, state: $0) }
        .grailsSheet(item: $model.workspaceDraft) { NewWorkspaceSheet(model: model, start: $0) }
        .grailsSheet(isPresented: $model.showTeamHome, onDismiss: { followTeamHome() }) {
            TeamHomeSheet(model: model, onClose: {
                model.showTeamHome = false
                if model.store != nil { model.onboarding?.finish() }
            })
        }
        .grailsSheet(isPresented: $model.showBucketInvite) {
            BucketInviteSheet(model: model, onClose: { model.showBucketInvite = false })
        }
        .grailsSheet(isPresented: $model.showMigrateSheet) {
            MigrateLibrarySheet(model: model)
        }
        .grailsSheet(isPresented: $model.showReconnect) {
            ReconnectBucketSheet(model: model, onClose: { model.showReconnect = false })
        }
        // The window, not the banner. An empty banner is only a few points tall, and a sheet anchored there opens as a blank strip.
        .grailsSheet(isPresented: Binding(get: { model.bucket.showSpring }, set: { model.bucket.showSpring = $0 })) {
            SpringCleaningSheet(model: model)
        }
        .grailsSheet(isPresented: $model.designGallery) {
            GrailsDesignGallery().frame(width: 640, height: 720)
        }
        // Every modal is a grailsSheet: it opens above whatever the person was in (Settings, the library, another modal), so
        // the order on screen is the order they opened in, not the order they are written here.
        .grailsSheet(isPresented: $model.feedbackOpen) { FeedbackCard(model: model) }
        .grailsSheet(isPresented: $model.importPanelOpen) { ImportPanel(model: model) }
        .grailsSheet(isPresented: Binding(get: { model.welcome != nil }, set: { if !$0 { model.welcome = nil } })) {
            if let w = model.welcome { WelcomeCard(model: model, request: w) }
        }
        .grailsSheet(isPresented: Binding(get: { model.keychainNotice }, set: { if !$0 { model.acknowledgeKeychainNotice() } })) {
            GrailsKeychainNotice(onContinue: { model.acknowledgeKeychainNotice() }, onClose: { model.acknowledgeKeychainNotice() })
        }
        .grailsSheet(isPresented: Binding(get: { model.bucket.showJoin }, set: { model.bucket.showJoin = $0 })) {
            JoinOverlay(model: model)
        }
        .grailsSheet(item: $model.prompt) { PromptCard(model: model, request: $0) }
        .grailsSheet(item: $model.confirm) { ConfirmCard(model: model, request: $0) }
        .onChange(of: model.errorMessage) {
            guard let message = model.errorMessage else { return }
            GrailsModalLayer.shared.alert(title: "Grails", message: message) { model.errorMessage = nil }
        }
        // ⌘K and the item panels act on the library: asked for from Settings, the library comes back first. The panel takes the keys.
        .onChange(of: model.panel) {
            guard model.panel != nil, model.settings.isOpen else { return }
            model.settings.close()
            model.settingsReturnFocus = nil
        }
        .task { await model.openInitialLibrary() }
        .onAppear {
            applyAppearance()
            Self.snapshotIfRequested()
            if ProcessInfo.processInfo.environment["GRAILS_PROOF_TEAM"] != nil { seedProofTeam() }
            if ProcessInfo.processInfo.environment["GRAILS_OPEN_FEEDBACK"] != nil { model.feedbackOpen = true }
            if ProcessInfo.processInfo.environment["GRAILS_DESIGN_GALLERY"] != nil { model.designGallery = true }
            if ProcessInfo.processInfo.environment["GRAILS_INVITE_SHEET"] != nil { model.showBucketInvite = true }
            if ProcessInfo.processInfo.environment["GRAILS_SCREEN"] == "sync" {
                model.syncProgress = (3, 8)
            }
            openProofScreen()
        }
        .onChange(of: appearance) { applyAppearance() }
        .onChange(of: model.sidebarVisible) { model.workspaceMenuOpen = false }
        .onChange(of: model.showTeamHome) { if !model.showTeamHome { followTeamHome() } }
    }

    private func followTeamHome() {
        guard let next = model.teamHomeNext else { return }
        model.teamHomeNext = nil
        Task { @MainActor in
            switch next {
            case .migrate: model.showMigrateSheet = true
            case .bucket: model.workspaceDraft = .bucket
            case .join:
                model.bucket.resetOnboarding()
                model.workspaceDraft = .invite
            }
        }
    }

    private func applyAppearance() {
        let name: NSAppearance.Name? = switch AppearanceChoice.scheme(stored: appearance) {
        case .light: .aqua
        case .dark: .darkAqua
        case nil: nil
        @unknown default: nil
        }
        NSApp.appearance = name.flatMap { NSAppearance(named: $0) }
    }

    /// Dev: GRAILS_SCREEN opens one surface for a window capture. The library, when needed, is GRAILS_LIBRARY.
    private func openProofScreen() {
        guard let screen = ProcessInfo.processInfo.environment["GRAILS_SCREEN"] else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(900))
            switch screen {
            case "invite-email", "invite-create", "invite-share":
                model.bucket.connected = true
                model.bucket.role = .owner
                model.showBucketInvite = true
            case "team":
                seedProofTeam()
                model.showTeamHome = true
            case "confirm":
                model.confirmEmptyTrash()
            case "spring":
                await seedSpringProof()
                model.bucket.showSpring = true
            case "join":
                model.bucket.showJoin = true
            case "search":
                model.searchText = "studio"
            case "settings", "library", "team-tab":
                if screen == "team-tab" || ProcessInfo.processInfo.environment["GRAILS_SETTINGS_TAB"] == "team" {
                    seedProofTeam()
                    if ProcessInfo.processInfo.environment["GRAILS_PROOF_ACTION"] == "removing" {
                        _ = model.bucket.actions.begin("cam@company.com", label: "Removing…")
                    }
                }
                NSApp.activate(ignoringOtherApps: true)
                try? await Task.sleep(for: .milliseconds(400))
                model.openSettings()
                // a modal asked for from inside Settings, the way its buttons ask: it must open above the page, not behind it
                try? await Task.sleep(for: .milliseconds(800))
                switch ProcessInfo.processInfo.environment["GRAILS_PROOF_ACTION"] {
                case "feedback": model.feedbackOpen = true
                case "feedback-confirm":
                    model.feedbackOpen = true
                    try? await Task.sleep(for: .milliseconds(800))
                    model.confirmEmptyTrash()
                case "workspace": model.workspaceDraft = .choose
                default: break
                }
            case "sync":
                model.syncProgress = (3, 8)
            case "workspace":
                model.workspaceDraft = .choose
            case "bucket":
                model.workspaceDraft = .bucket
            case "info":
                model.sidebarVisible = true
                // Opening the library clears the selection once. Keep putting it back until the picture is taken.
                let longTitle = String(repeating: "Hand-thrown ceramic lamp on a linen table, warm evening light, a Pinterest description that keeps going. ", count: 4)
                var renamed = false
                for _ in 0..<45 {
                    if let first = model.items.first {
                        if !renamed, ProcessInfo.processInfo.environment["GRAILS_LIBRARY"] != nil, first.name.count < 300 {
                            renamed = true
                            let id = first.id
                            Task { await model.perform("Rename") { try await $0.rename(id: id, to: longTitle) } }
                        }
                        if model.selection != [first.id] { model.selection = [first.id] }
                    }
                    try? await Task.sleep(for: .milliseconds(200))
                }
            default:
                break
            }
        }
    }

    /// A stand-in team so the People page can be captured without a bucket.
    private func seedProofTeam() {
        model.bucket.connected = true
        model.bucket.role = .owner
        model.bucket.email = "ada@company.com"
        model.bucket.team = TeamBody(
            generation: 1,
            ownerEmail: "ada@company.com",
            ownerPublicKey: "proof",
            members: [
                TeamMember(email: "ada@company.com", role: .owner),
                TeamMember(email: "bea@company.com", role: .admin),
                TeamMember(email: "cam@company.com", role: .member),
            ]
        )
    }

    /// Two local cards so a capture can show an image and a video without a bucket.
    private func seedSpringProof() async {
        model.bucket.connected = true
        model.bucket.role = .owner
        let root: URL?
        if let layout = model.layout {
            root = layout.root
        } else if let path = ProcessInfo.processInfo.environment["GRAILS_LIBRARY"] {
            root = URL(fileURLWithPath: path)
        } else {
            root = nil
        }
        guard let root else { return }
        let layout = LibraryLayout(root: root)
        let imageID = "spring-image"
        let videoID = "spring-video"
        let imageDir = layout.itemDir(imageID)
        let videoDir = layout.itemDir(videoID)
        try? FileManager.default.createDirectory(at: imageDir, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: videoDir, withIntermediateDirectories: true)
        try? SpringProofMedia.writeImage(to: imageDir.appendingPathComponent("original.png"))
        if let clip = await SpringProofMedia.writeVideo() {
            let destination = videoDir.appendingPathComponent("original.mp4")
            try? FileManager.default.removeItem(at: destination)
            try? FileManager.default.copyItem(at: clip, to: destination)
        }
        let image = UnopenedReference(key: "items/\(imageID)/item.json", name: "Image", addedAt: 1, kind: "image", ext: "png")
        let video = UnopenedReference(key: "items/\(videoID)/item.json", name: "Video", addedAt: 2, kind: "video", ext: "mp4")
        let videoFirst = ProcessInfo.processInfo.environment["GRAILS_SPRING_TOP"] == "video"
        model.bucket.deck = SpringDeck(cards: videoFirst ? [video, image] : [image, video])
    }

    // MARK: Content

    /// The space between the docked panels and under the top bar.
    private var mentionBar: CGFloat {
        model.shownSource == .mentions && !model.mentionClusters.isEmpty && !model.items.isEmpty ? 32 : 0
    }

    /// The tag strip and the mention bar, under the top bar. They come and go with a page.
    private var chromeTop: CGFloat { (model.stripVisible ? TagStrip.height : 0) + mentionBar }

    /// Everything right of the sidebar: the bar across the top, then the content column and the info panel column side by side.
    /// The panel is a column of this layout, never an overlay: opening it narrows the content and its tag strip together.
    private var workArea: some View {
        VStack(spacing: 0) {
            // the rule closing the bar: here when there is no strip, under the strip (and over the panel) when there is
            barRow
                .background(Ink.canvas)
                .overlay(alignment: .bottom) { if !model.stripVisible { Rectangle().fill(Ink.hairline).frame(height: 1) } }
            GrailsInfoSplit(isOpen: model.showInfo, width: Self.infoWidth) {
                contentColumn
            } panel: {
                // only the canvas has a library panel; the grid never builds one
                if model.viewMode == .canvas {
                    InfoPanel(model: model)
                        .overlay(alignment: .top) { if model.stripVisible { Rectangle().fill(Ink.hairline).frame(height: 1) } }
                }
            }
        }
        .padding(.leading, model.sidebarVisible ? Self.sidebarWidth : 0)
        .overlay { if dropTargeted { RoundedRectangle(cornerRadius: Ink.radius, style: .continuous).strokeBorder(Ink.focus, lineWidth: 2).padding(4).allowsHitTesting(false) } }
        .onDrop(of: [.fileURL, .grailsItems], delegate: ContentDrop(model: model, targeted: $dropTargeted))
    }

    /// The page and the chrome that comes and goes with it (tag strip, mention bar), under the bar.
    private var contentColumn: some View {
        ZStack(alignment: .topLeading) {
            content
            if model.stripVisible {
                TagStrip(model: model)
                    .frame(maxWidth: .infinity)
                    .background(Ink.canvas)
                    .overlay(alignment: .bottom) { Rectangle().fill(Ink.hairline).frame(height: 1) }
            }
            if mentionBar > 0 { mentionChips.padding(.leading, 12).padding(.top, model.stripVisible ? TagStrip.height : 0) }
        }
    }

    /// The grid's frame stays put across a page switch: it takes `chromeTop` inside, so the crossfade fades the previous page
    /// out where it was instead of moving it.
    private var content: some View {
        ZStack {
            switch model.viewMode {
            case .grid:
                GridView(model: model, topInset: Self.topInset, chromeTop: chromeTop, dormant: model.settings.isOpen, memberDirectory: model.memberDirectory)
            case .canvas:
                CanvasView(model: model, dormant: model.settings.isOpen)
                    .padding(.top, chromeTop)
            }
            if model.items.isEmpty && model.itemsReady && model.store != nil && model.onboarding == nil {
                // wherever there is nothing to show: ink rising through pixels at the foot of the window.
                // not during onboarding: Paste already has this band, and a second one starting underneath is the hitch between the two screens
                FluidBand(active: true)
                    .frame(height: 240)
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .padding(.top, chromeTop)
                    .allowsHitTesting(false)
                    .transition(.grailsPageFade(reduceMotion: reduceMotion))
                // part of the page: it crossfades with the grid it replaces, and does not rise on its own
                emptyState
                    .transition(.grailsPageFade(reduceMotion: reduceMotion))
                    .padding(.top, chromeTop)
            }
        }
    }

    private var mentionChips: some View {
        HStack(spacing: 6) {
            ForEach(model.mentionClusters) { c in
                GrailsControl { model.showClusterNotes(board: c.board, id: c.id, title: c.title) } label: {
                    Text(c.title.isEmpty ? "Untitled" : c.title).font(.grailsBody(12)).foregroundStyle(Ink.text)
                        .padding(.horizontal, 8).frame(height: 24)
                        .background(Ink.fill, in: Capsule())
                }
            }
        }
    }

    /// Nothing in the library at all, and no search or filter in the way.
    private var libraryIsEmpty: Bool {
        model.source == .all && model.totalCount == 0 && !model.isSearching && !model.filters.isActive && model.stripTags.isEmpty
    }

    /// Plain words, centred. Only the two states with something to do carry buttons.
    @ViewBuilder private var emptyState: some View {
        VStack(spacing: 14) {
            if model.isSearching {
                Text("No results for “\(model.searchText)”")
            } else if model.filters.isActive || !model.stripTags.isEmpty {
                Text("No matches")
                GrailsButton("Clear Filters", kind: .primary) { model.filters = ViewFilters(); model.addedByFilter = nil; model.stripTags = [] }
            } else if model.source == .trash {
                Text("Trash is empty")
            } else if model.source == .mentions && model.items.isEmpty {
                Text(model.mentionClusters.isEmpty ? "Nothing for you yet" : "On a cluster")
                if !model.mentionClusters.isEmpty { mentionChips }
            } else if libraryIsEmpty {
                Text("Nothing here yet").font(.grailsDisplay(CGFloat(TypeScale.page))).tracking(TypeScale.pageTracking).foregroundStyle(Ink.text)
                Text("Bring in a board you already love, or paste anything worth keeping.")
                    .font(.grailsBody(14)).foregroundStyle(Ink.secondary).multilineTextAlignment(.center).frame(maxWidth: 360)
                HStack(spacing: 8) {
                    GrailsButton("Import a board", kind: .primary) { model.promptImportBoard() }.accessibilityIdentifier("empty-import")
                    GrailsButton("Add files…", kind: .secondary) { model.promptAddFiles() }.accessibilityIdentifier("empty-add")
                }
                .padding(.top, 6)
            } else if model.source == .all {
                Text("Empty")
            } else {
                Text("Nothing here yet")
            }
        }
        .font(.grailsDisplay(CGFloat(TypeScale.page)))
        .tracking(TypeScale.pageTracking)
        .foregroundStyle(Ink.secondary)
    }

    // MARK: Chrome

    /// The sidebar is docked: a flat surface from the top of the window to the bottom, with a hairline against the content.
    private var sidebar: some View {
        HStack(alignment: .top, spacing: 0) {
            if model.sidebarVisible {
                SidebarView(model: model)
                    .padding(.top, Self.barHeight)
                    .frame(width: Self.sidebarWidth)
                    .frame(maxHeight: .infinity)
                    .background(Ink.sidebar)
                    .overlay(alignment: .trailing) { Rectangle().fill(Ink.separator).frame(width: 1) }
                    .transition(.grailsSlide(x: -12, reduceMotion: reduceMotion))
            }
            Spacer(minLength: 0).allowsHitTesting(false)
        }
        .animation(.grails(.grailsStandard, reduceMotion: reduceMotion), value: model.sidebarVisible)
    }

    /// The workspace menu hangs under the pinned switcher at the top of the sidebar; a click anywhere else closes it.
    @ViewBuilder private var workspaceMenu: some View {
        if model.workspaceMenuOpen, model.sidebarVisible {
            Color.clear.contentShape(Rectangle()).ignoresSafeArea().onTapGesture { model.workspaceMenuOpen = false }
            WorkspaceMenu(model: model)
                .grailsOverlayEntrance(anchor: .top)
                .transition(.grailsFade)
                .frame(width: Self.sidebarWidth - 16)
                .padding(.leading, 8)
                .padding(.top, Self.barHeight + 8 + WorkspaceSwitcher.height + 4)
        }
    }

    private var barRow: some View {
        HStack(spacing: 6) {
            BarButton(symbol: "sidebar.left", selected: model.sidebarVisible, help: "Show or hide the sidebar (⌃⌘S)", identifier: "sidebar-toggle") {
                model.sidebarVisible.toggle()
            }
            if model.canGoBack {
                BarButton(symbol: "chevron.left", help: "Back (⌘[)", identifier: "back") { model.goBack() }
            }
            titleBlock
            Spacer(minLength: 8)
            searchField
            ViewTabs(model: model).padding(.horizontal, 10)
            FilterMenu(model: model)
            ColorFilterButton(model: model)
            ShareMenu(model: model)
        }
        .padding(.leading, model.sidebarVisible ? 12 : TrafficLightMetrics.shared.leading)
        .padding(.trailing, 12)
        .frame(height: Self.barHeight)
    }

    /// Where you are and how many items: the filter (with a way to clear it) or the view's name, then the count.
    private var titleBlock: some View {
        HStack(spacing: 8) {
            if let chip = model.viewChip {
                HStack(spacing: 6) {
                    Image(systemName: chip.symbol).font(ChromeFont.symbol(11, weight: .medium)).foregroundStyle(Ink.secondary)
                    Text(chip.label).font(.grailsBody(13)).foregroundStyle(Ink.text).lineLimit(1)
                    GrailsControl(press: .icon) { model.clearViewChip() } label: {
                        Image(systemName: "xmark").font(ChromeFont.symbol(9, weight: .bold)).foregroundStyle(Ink.secondary)
                            .frame(width: 16, height: 16).background(Ink.fill, in: Circle())
                    }
                    .help("Clear")
                    .accessibilityIdentifier("clear-filter")
                }
                .padding(.leading, 10).padding(.trailing, 5).frame(height: 28)
                .background(Ink.fill, in: RoundedRectangle(cornerRadius: Ink.radius, style: .continuous))
            } else {
                Text(model.title).font(.grailsDisplay(CGFloat(TypeScale.title))).foregroundStyle(Ink.text).lineLimit(1)
            }
            Text(model.countLabel).font(.grailsBody(12)).foregroundStyle(Ink.tertiary).lineLimit(1).layoutPriority(-1)
        }
        .padding(.leading, 6)
        .frame(maxWidth: 360, alignment: .leading)
    }

    private var searchField: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass").font(ChromeFont.symbol(12, weight: .medium)).foregroundStyle(searchFocused ? Ink.text : Ink.secondary)
            GrailsSearchField(text: $model.searchText, focusTick: model.focusSearchTick, isFocused: $searchFocused)
                .frame(height: 22)
            if !model.searchText.isEmpty {
                GrailsControl(press: .icon) { model.searchText = "" } label: { Image(systemName: "xmark.circle.fill").font(ChromeFont.symbol(12)).foregroundStyle(Ink.tertiary) }
                    .help("Clear search")
            }
        }
        .padding(.horizontal, 10)
        .frame(minWidth: 130, idealWidth: 250, maxWidth: 250)
        .frame(height: 30)
        .background(Ink.surface, in: RoundedRectangle(cornerRadius: Ink.radius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Ink.radius, style: .continuous).strokeBorder(searchFocused ? Ink.focus : Ink.hairline, lineWidth: 1))
        .overlay {
            if searchFocused {
                RoundedRectangle(cornerRadius: Ink.radius, style: .continuous).inset(by: -1.5).stroke(Ink.text.opacity(0.08), lineWidth: 3)
            }
        }
    }

    /// What belongs to the library and stays under Settings with it: onboarding, its banners, an open preview.
    @ViewBuilder private var libraryOverlays: some View {
        if let onboarding = model.onboarding { OnboardingView(model: onboarding) }
        BucketBanners(model: model)
        if model.previewID != nil { PreviewPage(model: model) }
    }

    /// Settings in place of the library. The page slides in on the spring while it fades in on the ease; Reduce Motion leaves the fade.
    private var settingsPage: some View {
        ZStack {
            if model.settings.isOpen {
                SettingsView(model: model, updater: UpdaterController.shared)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .transition(.grailsSlide(x: Self.settingsSlide, reduceMotion: reduceMotion))
            }
        }
        .animation(.grails(.grailsStandard, reduceMotion: reduceMotion), value: model.settings.isOpen)
    }

    static let settingsSlide: CGFloat = 16

    /// Above whichever page is showing: the pairing ask (often answered from Settings ▸ Extensions), ⌘K, toasts and progress.
    @ViewBuilder private var windowOverlays: some View {
        if let req = model.pairRequest, !model.importPanelOpen, !model.extensionSetup.isOpen { PairPrompt(model: model, request: req) }
        if let panel = model.panel { PanelHost(model: model, panel: panel) }
        // every toast, error or not, and the progress cards under it: one column centred across the whole window
        VStack(spacing: CGFloat(ToastPlacement.stackSpacing)) {
            if let t = model.toast { ToastView(text: t).grailsToastEntrance().id(t).transition(.grailsFade) }
            if let p = model.importProgress {
                ProgressCard(label: "Importing \(p.done) of \(p.total)…", done: p.done, total: p.total)
            }
            if let p = model.boardImport {
                ProgressCard(label: p.total > 0 ? "\(p.label) \(p.done) of \(p.total)…" : p.label, done: p.done, total: p.total)
                    .accessibilityIdentifier("board-import-progress")
            }
            if let p = model.autoTagProgress {
                ProgressCard(label: "Auto-tagging \(p.done) of \(p.total)…", done: p.done, total: p.total)
                    .accessibilityIdentifier("autotag-progress")
            }
            if let p = model.renameProgress {
                ProgressCard(label: "Updating tags… \(p.done) of \(p.total)", done: p.done, total: p.total)
            }
            if let p = model.syncProgress, SyncFeedback.showsProgress(total: p.total) {
                ProgressCard(label: SyncFeedback.progressLine(done: p.done, total: p.total), done: p.done, total: p.total)
                    .accessibilityIdentifier("sync-progress")
            }
        }
        .padding(.horizontal, CGFloat(Space.xl))
        .grailsToastPlacement()
        .animation(.grails(.grailsStandard, reduceMotion: reduceMotion), value: model.toast)
        .allowsHitTesting(false)
    }
}

extension RootView {
    /// Dev: GRAILS_SNAPSHOT=<png path> renders the window's contents to that file a few seconds after launch (and quits when
    /// GRAILS_SNAPSHOT_QUIT is set). No screen access, so it works while the app is in the background.
    @MainActor
    static func snapshotIfRequested() {
        let env = ProcessInfo.processInfo.environment
        guard let path = env["GRAILS_SNAPSHOT"] else { return }
        let delay = Double(env["GRAILS_SNAPSHOT_DELAY"] ?? "") ?? 5
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(delay))
            func find(_ v: NSView) -> NSView? {
                if v is GrailsCollectionView { return v.enclosingScrollView ?? v }
                for s in v.subviews { if let hit = find(s) { return hit } }
                return nil
            }
            // the AppKit grid renders offscreen; a SwiftUI window does not
            let root = NSApp.windows.compactMap(\.contentView).first
            func fluid(_ v: NSView) -> FluidDitherView? {
                if let f = v as? FluidDitherView { return f }
                for s in v.subviews { if let hit = fluid(s) { return hit } }
                return nil
            }
            if let root, let band = fluid(root) {
                var chain: [String] = []
                var v: NSView? = band
                while let x = v { chain.append("\(type(of: x)) a=\(x.alphaValue) h=\(x.isHidden) f=\(x.frame.integral)"); v = x.superview }
                print("FLUID chain:\n" + chain.joined(separator: "\n"))
                if let win = band.window, let cg = CGWindowListCreateImage(.null, .optionIncludingWindow, CGWindowID(win.windowNumber), [.boundsIgnoreFraming]) {
                    try? NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path + ".window.png"))
                }
                if let win = band.window, let content = win.contentView {
                    // dev: which view would take a click on the back chevron (99 pt from the left, 22 pt from the top)?
                    let p = NSPoint(x: 99, y: content.bounds.height - 22)
                    var hit = content.hitTest(content.convert(p, from: nil)); var chain: [String] = []
                    while let x = hit { chain.append("\(type(of: x))"); hit = x.superview }
                    print("HITTEST chevron:", chain.joined(separator: " < "))
                    print("HITTEST titlebar height", win.frame.height - win.contentLayoutRect.height, "contentLayoutRect", win.contentLayoutRect)
                }
                print("FLUID window \(String(describing: band.window?.frame)) occlusion \(String(describing: band.window?.occlusionState)) visible \(band.window?.isVisible ?? false)")
            }
            @MainActor func captureWindows() {
                let base = URL(fileURLWithPath: path).deletingPathExtension()
                for (index, win) in NSApp.windows.enumerated() where win.isVisible {
                    guard let content = win.contentView, content.bounds.width > 2, content.bounds.height > 2,
                          let rep = content.bitmapImageRepForCachingDisplay(in: content.bounds) else { continue }
                    content.cacheDisplay(in: content.bounds, to: rep)
                    let url = base.appendingPathExtension("window-\(index).png")
                    try? rep.representation(using: .png, properties: [:])?.write(to: url)
                    print("SNAPSHOT window: \(url.path)")
                }
            }
            if let root, let band = fluid(root), let image = band.lastImage {
                try? NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
                print("SNAPSHOT: \(path)")
                captureWindows()
                finishSnapshot(env)
                return
            }
            if let root, let v = find(root), let rep = v.bitmapImageRepForCachingDisplay(in: v.bounds) {
                v.cacheDisplay(in: v.bounds, to: rep)
                try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
                print("SNAPSHOT: \(path)")
            }
            captureWindows()
            finishSnapshot(env)
        }
    }

    /// The Spring sheet keeps the quit. The picture is already on disk, so the proof launch has to end.
    @MainActor
    private static func finishSnapshot(_ env: [String: String]) {
        guard env["GRAILS_SNAPSHOT_QUIT"] != nil else { return }
        for window in NSApp.windows {
            if let sheet = window.attachedSheet { window.endSheet(sheet) }
        }
        NSApp.terminate(nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { exit(0) }
    }
}

struct ProgressCard: View {
    let label: String
    let done: Int
    let total: Int

    var body: some View {
        GrailsProgressBar(done: done, total: max(total, 0), label: label)
            .padding(.horizontal, 16).padding(.vertical, 12)
            .frame(maxWidth: 340, alignment: .leading)
            .surfaceCard()
    }
}

/// Everything that narrows or orders the view, in one place: type filters, liked, who added it, and sort.
struct FilterMenu: View {
    @Bindable var model: AppModel

    var body: some View {
        GrailsMenu {
            Toggle("Images", isOn: $model.filters.images)
            Toggle("Videos", isOn: $model.filters.videos)
            Toggle("GIFs", isOn: $model.filters.gifs)
            Toggle("Square", isOn: $model.filters.square)
            Toggle("Liked", isOn: $model.filters.liked)
            if model.contributors.count > 1 {
                Divider()
                Menu("Added by") {
                    GrailsControl { model.addedByFilter = nil } label: { Label("Everyone", systemImage: model.addedByFilter == nil ? "checkmark" : "") }
                    ForEach(model.contributors, id: \.who) { c in
                        GrailsControl { model.addedByFilter = c.who } label: {
                            Label("\(model.personName(c.who)) (\(c.count.formatted()))", systemImage: model.addedByFilter == c.who ? "checkmark" : "")
                        }
                    }
                }
            }
            Divider()
            Picker("Sort", selection: $model.sort) {
                ForEach(SortChoice.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.inline)
            if model.filters.isActive || model.addedByFilter != nil {
                Divider()
                GrailsControl("Clear Filters") { model.filters = ViewFilters(); model.addedByFilter = nil }
            }
        } label: {
            BarIcon(symbol: "line.3.horizontal.decrease", active: model.filters.isActive || model.addedByFilter != nil)
        }
        .help("Filter and sort")
        .accessibilityLabel("Filter and sort")
        .accessibilityIdentifier("filter-menu")
    }
}

struct ColorFilterButton: View {
    @Bindable var model: AppModel
    @State private var open = false

    private var chips: [GrailsColorChip] {
        NamedColor.allCases.map { GrailsColorChip(name: $0.rawValue, label: $0.label, hex: $0.sampleHex) }
    }

    var body: some View {
        BarButton(symbol: "paintpalette", selected: model.filters.color != nil, help: "Color", identifier: "color-filter") {
            open.toggle()
        }
        .grailsPopover(isPresented: $open, arrowEdge: .bottom) {
            GrailsColorFilter(chips: chips, selected: model.filters.color?.rawValue) { name in
                let picked = NamedColor(rawValue: name)
                model.filters.color = model.filters.color == picked ? nil : picked
            }
            .padding(CGFloat(Space.md))
            .frame(width: 280)
        }
    }
}

/// Grid and Canvas, in the shared segmented control.
struct ViewTabs: View {
    @Bindable var model: AppModel

    var body: some View {
        GrailsSegmented(options: ViewMode.allCases.map { mode in
            GrailsSegmented.Option(id: mode.rawValue, title: mode.label, identifier: "view-\(mode.rawValue)")
        }, selection: model.viewMode.rawValue) { id in
            if let mode = ViewMode(rawValue: id) { model.viewMode = mode }
        }
        .frame(width: 168)
        .help(model.viewMode == .grid ? "Grid (⌘1)" : "Canvas (⌘2)")
    }
}

/// Share and export: the view or the selection as an HTML file or a PDF, and links.
struct ShareMenu: View {
    var model: AppModel

    var body: some View {
        GrailsMenu {
            GrailsControl("Export View as HTML…") { model.exportWebPage(format: .html) }
            GrailsControl("Export View as PDF…") { model.exportWebPage(format: .pdf) }
            Divider()
            GrailsControl("Export Selection as HTML…") { model.exportWebPage(selectionOnly: true, format: .html) }.disabled(model.selection.isEmpty)
            GrailsControl("Export Selection as PDF…") { model.exportWebPage(selectionOnly: true, format: .pdf) }.disabled(model.selection.isEmpty)
            Divider()
            GrailsControl("Copy Link to This View") { model.copyViewLink() }
            GrailsControl(model.libraryPlace.needsReconnect ? "Reconnect storage…" : model.libraryPlace.copiesFolderInvite ? "Copy Invite Link" : "Invite…") { model.copyInviteLink() }
        } label: {
            BarIcon(symbol: "square.and.arrow.up")
        }
        .help("Share and export")
        .accessibilityLabel("Share and export")
        .accessibilityIdentifier("share-menu")
    }
}
