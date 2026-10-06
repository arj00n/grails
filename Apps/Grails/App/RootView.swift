import GrailsKit
import SwiftUI
import UniformTypeIdentifiers

struct RootView: View {
    @Bindable var model: AppModel
    @AppStorage("appearance") private var appearance = "system"
    @State private var dropTargeted = false
    @State private var searchFocused = false

    static let sidebarWidth: CGFloat = 240
    static let infoWidth: CGFloat = 300
    static let barHeight: CGFloat = 44
    /// A little air above the first row, under the bar.
    static let topInset: CGFloat = 10

    var body: some View {
        ZStack(alignment: .topLeading) {
            content
            panels
            topBar
            workspaceMenu
            overlays
        }
        .background(Ink.canvas)
        .background(WindowChrome())
        .ignoresSafeArea()
        .preferredColorScheme(appearance == "light" ? .light : appearance == "dark" ? .dark : nil)
        .tint(Ink.text)
        .font(.grailsBody(13))
        .sheet(item: $model.smartEditor) { SmartFolderEditor(model: model, state: $0) }
        .alert("Grails", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            Button("OK") { model.errorMessage = nil }
        } message: { Text(model.errorMessage ?? "") }
        .task { await model.openInitialLibrary() }
        .onAppear { applyAppearance(); Self.snapshotIfRequested() }
        .onChange(of: appearance) { applyAppearance() }
        .onChange(of: model.sidebarVisible) { model.workspaceMenuOpen = false }
    }

    /// Layers and AppKit views read the app's appearance when they resolve a colour, so keep it in step with the setting.
    private func applyAppearance() {
        NSApp.appearance = appearance == "light" ? NSAppearance(named: .aqua) : appearance == "dark" ? NSAppearance(named: .darkAqua) : nil
    }

    // MARK: Content

    /// The space between the docked panels and under the top bar.
    private var contentInsets: EdgeInsets {
        EdgeInsets(top: Self.barHeight + (model.stripVisible ? TagStrip.height : 0), leading: model.sidebarVisible ? Self.sidebarWidth : 0, bottom: 0, trailing: 0)
    }

    private var content: some View {
        ZStack {
            switch model.viewMode {
            case .grid:
                GridView(model: model, topInset: Self.topInset)
                    .padding(contentInsets)
            case .canvas:
                CanvasView(model: model)
                    .padding(contentInsets)
            }
            if model.items.isEmpty && model.store != nil {
                // wherever there is nothing to show: ink rising through pixels at the foot of the window
                FluidBand(active: true)
                    .frame(height: 240)
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .padding(contentInsets)
                    .allowsHitTesting(false)
                    .transition(.opacity)
                emptyState
                    .padding(contentInsets)
            }
        }
        .overlay { if dropTargeted { RoundedRectangle(cornerRadius: Ink.radius, style: .continuous).strokeBorder(Ink.focus, lineWidth: 2).padding(4).allowsHitTesting(false) } }
        .onDrop(of: [.fileURL, .grailsItems], delegate: ContentDrop(model: model, targeted: $dropTargeted))
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
                Button("Clear Filters") { model.filters = ViewFilters(); model.addedByFilter = nil; model.stripTags = [] }.buttonStyle(PrimaryButtonStyle())
            } else if model.source == .trash {
                Text("Trash is empty")
            } else if libraryIsEmpty {
                Text("Nothing here yet").font(.grailsDisplay(24)).foregroundStyle(Ink.text)
                Text("Bring in a board you already love, or paste anything worth keeping.")
                    .font(.grailsBody(14)).foregroundStyle(Ink.secondary).multilineTextAlignment(.center).frame(maxWidth: 360)
                HStack(spacing: 8) {
                    Button("Import a board") { model.promptImportBoard() }.buttonStyle(PrimaryButtonStyle()).accessibilityIdentifier("empty-import")
                    Button("Add files…") { model.promptAddFiles() }.buttonStyle(OutlineButtonStyle()).accessibilityIdentifier("empty-add")
                }
                .padding(.top, 6)
            } else if model.source == .all {
                Text("Empty")
            } else {
                Text("Nothing here yet")
            }
        }
        .font(.grailsDisplay(24))
        .foregroundStyle(Ink.secondary)
    }

    // MARK: Chrome

    /// Sidebar and info panel are docked: flat surfaces from the top of the window to the bottom, with a hairline against the content.
    private var panels: some View {
        HStack(alignment: .top, spacing: 0) {
            if model.sidebarVisible {
                SidebarView(model: model)
                    .padding(.top, Self.barHeight)
                    .frame(width: Self.sidebarWidth)
                    .frame(maxHeight: .infinity)
                    .background(Ink.surface)
                    .overlay(alignment: .trailing) { Rectangle().fill(Ink.hairline).frame(width: 1) }
                    
            }
            Spacer(minLength: 0).allowsHitTesting(false)
            // the info panel floats over the right edge while something is selected: the grid never reflows when it comes and goes
            if model.showInfo {
                InfoPanel(model: model)
                    .padding(.top, Self.barHeight)
                    .frame(width: Self.infoWidth)
                    .frame(maxHeight: .infinity)
                    .background(Ink.surface)
                    .overlay(alignment: .leading) { Rectangle().fill(Ink.hairline).frame(width: 1) }
                    .transition(.opacity.combined(with: .offset(x: 12)))
            }
        }
        .animation(reduceMotionOn ? .easeOut(duration: 0.1) : .timingCurve(0.22, 1, 0.36, 1, duration: 0.2), value: model.showInfo)
    }

    /// The workspace menu hangs under the pinned switcher at the top of the sidebar; a click anywhere else closes it.
    @ViewBuilder private var workspaceMenu: some View {
        if model.workspaceMenuOpen, model.sidebarVisible {
            Color.clear.contentShape(Rectangle()).ignoresSafeArea().onTapGesture { model.workspaceMenuOpen = false }
            WorkspaceMenu(model: model)
                .frame(width: Self.sidebarWidth - 16)
                .padding(.leading, 8)
                .padding(.top, Self.barHeight + 8 + WorkspaceSwitcher.height + 4)
        }
    }

    private var topBar: some View {
        VStack(spacing: 0) {
            // above the tag strip, so the search field's recent searches drop over it instead of under it
            barRow.zIndex(1)
            if model.stripVisible { TagStrip(model: model) }
        }
        .background(Ink.canvas)
        .overlay(alignment: .bottom) { Rectangle().fill(Ink.hairline).frame(height: 1) }
        .padding(.leading, model.sidebarVisible ? Self.sidebarWidth : 0)
        .frame(maxHeight: .infinity, alignment: .top)
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
            ShareMenu(model: model)
        }
        .padding(.leading, model.sidebarVisible ? 12 : ChromeMetrics.shared.leading)
        .padding(.trailing, 12)
        .frame(height: Self.barHeight)
    }

    /// Where you are and how many items: the filter (with a way to clear it) or the view's name, then the count.
    private var titleBlock: some View {
        HStack(spacing: 8) {
            if let chip = model.viewChip {
                HStack(spacing: 6) {
                    Image(systemName: chip.symbol).font(.system(size: 11, weight: .medium)).foregroundStyle(Ink.secondary)
                    Text(chip.label).font(.grailsBody(13)).foregroundStyle(Ink.text).lineLimit(1)
                    Button { model.clearViewChip() } label: {
                        Image(systemName: "xmark").font(.system(size: 9, weight: .bold)).foregroundStyle(Ink.secondary)
                            .frame(width: 16, height: 16).background(Ink.fill, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .help("Clear")
                    .accessibilityIdentifier("clear-filter")
                }
                .padding(.leading, 10).padding(.trailing, 5).frame(height: 28)
                .background(Ink.fill, in: RoundedRectangle(cornerRadius: Ink.radius, style: .continuous))
            } else {
                Text(model.title).font(.grailsDisplay(14)).foregroundStyle(Ink.text).lineLimit(1)
            }
            Text(model.countLabel).font(.grailsBody(12)).foregroundStyle(Ink.tertiary).lineLimit(1).layoutPriority(-1)
        }
        .padding(.leading, 6)
        .frame(maxWidth: 360, alignment: .leading)
    }

    private var searchField: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass").font(.system(size: 12, weight: .medium)).foregroundStyle(searchFocused ? Ink.text : Ink.secondary)
            SearchField(text: $model.searchText, focusTick: model.focusSearchTick, isFocused: $searchFocused, onSubmit: { model.rememberSearch() })
                .frame(height: 22)
            if !model.searchText.isEmpty {
                Button { model.searchText = "" } label: { Image(systemName: "xmark.circle.fill").font(.system(size: 12)).foregroundStyle(Ink.tertiary) }
                    .buttonStyle(.plain).help("Clear search")
            }
        }
        .padding(.horizontal, 10)
        .frame(minWidth: 130, idealWidth: 250, maxWidth: 250)
        .frame(height: 30)
        .background(Ink.fill, in: RoundedRectangle(cornerRadius: Ink.radius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Ink.radius, style: .continuous).strokeBorder(searchFocused ? Ink.focus : .clear, lineWidth: 1))
        .overlay(alignment: .topLeading) { recentSearches.offset(y: 36) }
    }

    @ViewBuilder private var recentSearches: some View {
        if searchFocused, model.searchText.isEmpty, !model.recentSearches.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(model.recentSearches.prefix(6), id: \.self) { q in
                    Button { model.searchText = q } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "clock").font(.system(size: 11)).foregroundStyle(Ink.tertiary)
                            Text(q).foregroundStyle(Ink.text).lineLimit(1)
                            Spacer()
                        }
                        .padding(.horizontal, 14).padding(.vertical, 8).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 6)
            .frame(width: 250)
            .surfaceCard()
        }
    }

    @ViewBuilder private var overlays: some View {
        if let onboarding = model.onboarding { OnboardingView(model: onboarding) }
        if model.previewID != nil { PreviewPage(model: model) }
        if model.importPanelOpen { ImportPanel(model: model) }
        if let w = model.welcome { WelcomeCard(model: model, request: w).transition(.opacity) }
        if model.extensionSetup.isOpen { ExtensionModal(model: model) }
        if let req = model.pairRequest, !model.importPanelOpen, !model.extensionSetup.isOpen { PairPrompt(model: model, request: req) }
        if let panel = model.panel { PanelHost(model: model, panel: panel) }
        if let p = model.prompt { PromptCard(model: model, request: p) }
        if let c = model.confirm { ConfirmCard(model: model, request: c) }
        VStack(spacing: 10) {
            Spacer()
            if let t = model.toast { ToastView(text: t).transition(.move(edge: .bottom).combined(with: .opacity)) }
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
        }
        .padding(24)
        .animation(.default, value: model.toast)
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
                print("FLUID window \(String(describing: band.window?.frame)) occlusion \(String(describing: band.window?.occlusionState)) visible \(band.window?.isVisible ?? false)")
            }
            if let root, let band = fluid(root), let image = band.lastImage {
                try? NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
                print("SNAPSHOT: \(path)")
                if env["GRAILS_SNAPSHOT_QUIT"] != nil { NSApp.terminate(nil) }
                return
            }
            if let root, let v = find(root), let rep = v.bitmapImageRepForCachingDisplay(in: v.bounds) {
                v.cacheDisplay(in: v.bounds, to: rep)
                try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
                print("SNAPSHOT: \(path)")
            }
            if env["GRAILS_SNAPSHOT_QUIT"] != nil { NSApp.terminate(nil) }
        }
    }
}

struct ProgressCard: View {
    let label: String
    let done: Int
    let total: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label).font(.grailsBody(12)).foregroundStyle(Ink.text).lineLimit(2)
            if total > 0 { ProgressView(value: Double(done), total: Double(max(total, 1))).progressViewStyle(.linear).tint(Ink.text) }
            else { ProgressView().controlSize(.small) }
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .frame(maxWidth: 340, alignment: .leading)
        .surfaceCard()
    }
}

/// Everything that narrows or orders the view, in one place: type filters, liked, who added it, and sort.
struct FilterMenu: View {
    @Bindable var model: AppModel

    var body: some View {
        Menu {
            Toggle("Images", isOn: $model.filters.images)
            Toggle("Videos", isOn: $model.filters.videos)
            Toggle("GIFs", isOn: $model.filters.gifs)
            Toggle("Square", isOn: $model.filters.square)
            Toggle("Liked", isOn: $model.filters.liked)
            if model.contributors.count > 1 {
                Divider()
                Menu("Added by") {
                    Button { model.addedByFilter = nil } label: { Label("Everyone", systemImage: model.addedByFilter == nil ? "checkmark" : "") }
                    ForEach(model.contributors, id: \.who) { c in
                        Button { model.addedByFilter = c.who } label: {
                            Label("\(c.who) (\(c.count.formatted()))", systemImage: model.addedByFilter == c.who ? "checkmark" : "")
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
                Button("Clear Filters") { model.filters = ViewFilters(); model.addedByFilter = nil }
            }
        } label: {
            BarIcon(symbol: "line.3.horizontal.decrease", active: model.filters.isActive || model.addedByFilter != nil)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Filter and sort")
        .accessibilityLabel("Filter and sort")
        .accessibilityIdentifier("filter-menu")
    }
}

/// Grid and Canvas as two plain text tabs; the current one is full-strength.
struct ViewTabs: View {
    @Bindable var model: AppModel

    var body: some View {
        HStack(spacing: 14) {
            ForEach(ViewMode.allCases) { mode in
                ViewTab(label: mode.label, selected: model.viewMode == mode) { model.viewMode = mode }
                    .help("\(mode.label) (⌘\(mode == .grid ? 1 : 2))")
                    .accessibilityIdentifier("view-\(mode.rawValue)")
            }
        }
    }
}

private struct ViewTab: View {
    let label: String
    let selected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.grailsBody(13))
                .foregroundStyle(selected || hovering ? Ink.text : Ink.secondary)
                .frame(height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hoverState($hovering)
    }
}

/// Share and export: the view or the selection as an HTML file or a PDF, and links.
struct ShareMenu: View {
    var model: AppModel

    var body: some View {
        Menu {
            Button("Export View as HTML…") { model.exportWebPage(format: .html) }
            Button("Export View as PDF…") { model.exportWebPage(format: .pdf) }
            Divider()
            Button("Export Selection as HTML…") { model.exportWebPage(selectionOnly: true, format: .html) }.disabled(model.selection.isEmpty)
            Button("Export Selection as PDF…") { model.exportWebPage(selectionOnly: true, format: .pdf) }.disabled(model.selection.isEmpty)
            Divider()
            Button("Copy Link to This View") { model.copyViewLink() }
            Button("Copy Invite Link") { model.copyInviteLink() }
        } label: {
            BarIcon(symbol: "square.and.arrow.up")
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Share and export")
        .accessibilityLabel("Share and export")
        .accessibilityIdentifier("share-menu")
    }
}
