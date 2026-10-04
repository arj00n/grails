import StashKit
import SwiftUI
import UniformTypeIdentifiers

struct RootView: View {
    @Bindable var model: AppModel
    @AppStorage("appearance") private var appearance = "dark"
    @AppStorage("gridBackground") private var background = "black"
    @State private var dropTargeted = false
    @State private var searchFocused = false

    static let sidebarWidth: CGFloat = 244
    static let infoWidth: CGFloat = 308
    static let edge: CGFloat = 12
    /// Space the grid keeps clear above its first row (the floating top bar sits there, tiles scroll beneath it).
    static let topInset: CGFloat = 72

    var body: some View {
        ZStack(alignment: .topLeading) {
            content
            panels
            topBar
            captionPill
            overlays
        }
        .background(gridBackground)
        .background(WindowChrome())
        .ignoresSafeArea()
        .preferredColorScheme(appearance == "light" ? .light : .dark)
        .tint(.white)
        .sheet(item: $model.smartEditor) { SmartFolderEditor(model: model, state: $0) }
        .alert("Stash", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            Button("OK") { model.errorMessage = nil }
        } message: { Text(model.errorMessage ?? "") }
        .task { await model.openInitialLibrary() }
        .onAppear {
            model.startCheatSheetMonitor()
            Self.snapshotIfRequested()
        }
        .animation(.smooth(duration: 0.25), value: model.sidebarVisible)
        .animation(.smooth(duration: 0.25), value: model.showInfo)
    }

    // MARK: Content

    private var content: some View {
        ZStack {
            switch model.viewMode {
            case .grid:
                GridView(model: model, topInset: Self.topInset)
                    .padding(.leading, model.sidebarVisible ? Self.sidebarWidth + Self.edge * 2 : 0)
                    .padding(.trailing, model.showInfo ? Self.infoWidth + Self.edge * 2 : 0)
            case .canvas:
                CanvasView(model: model)
            }
            // above the canvas (which paints its own black), centred in the space the floating panels leave free
            if model.items.isEmpty && model.store != nil {
                emptyState
                    .padding(.leading, model.sidebarVisible ? Self.sidebarWidth + Self.edge * 2 : 0)
                    .padding(.trailing, model.showInfo ? Self.infoWidth + Self.edge * 2 : 0)
                    .allowsHitTesting(false)
            }
        }
        .overlay { if dropTargeted { RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(.white.opacity(0.7), lineWidth: 2).padding(6).allowsHitTesting(false) } }
        .onDrop(of: [.fileURL, .stashItems], isTargeted: $dropTargeted) { providers in
            Task { @MainActor in
                let d = await DropLoader.load(providers)
                // Tiles dragged within the grid carry their ids: nothing to import.
                if d.itemIDs.isEmpty, !d.files.isEmpty { await model.importFiles(d.files) }
            }
            return true
        }
    }

    @ViewBuilder private var emptyState: some View {
        if model.isSearching {
            ContentUnavailableView.search(text: model.searchText)
        } else if model.filters.isActive {
            ContentUnavailableView("No matches", systemImage: "line.3.horizontal.decrease.circle", description: Text("Try clearing a filter."))
        } else {
            ContentUnavailableView(
                model.source == .trash ? "Trash is empty" : "Nothing here yet",
                systemImage: "photo.on.rectangle.angled",
                description: Text(model.source == .all || model.source == .inbox ? "Drop images, videos or folders here to add them." : "Nothing matches this view yet.")
            )
        }
    }

    // MARK: Floating chrome

    /// Sidebar and info panel float over the content as glass cards; the grid makes room for them, the canvas goes beneath.
    private var panels: some View {
        HStack(alignment: .top, spacing: 0) {
            if model.sidebarVisible {
                SidebarView(model: model)
                    .frame(width: Self.sidebarWidth)
                    .glassCard()
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }
            Spacer(minLength: 0).allowsHitTesting(false)
            if model.showInfo {
                InfoPanel(model: model)
                    .frame(width: Self.infoWidth)
                    .glassCard()
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .padding(.horizontal, Self.edge)
        .padding(.top, 64)
        .padding(.bottom, Self.edge)
    }

    private var topBar: some View {
        ZStack {
            searchPill
            HStack(spacing: 0) {
                GlassIconButton(symbol: "sidebar.left", selected: model.sidebarVisible, help: "Show or hide the sidebar (⌃⌘S)", identifier: "sidebar-toggle") {
                    model.sidebarVisible.toggle()
                }
                .padding(3).glassPill(interactive: true)
                .padding(.leading, 78)
                Spacer(minLength: 0)
                HStack(spacing: 2) {
                    ForEach(ViewMode.allCases) { mode in
                        GlassIconButton(symbol: mode.symbol, selected: model.viewMode == mode, help: "\(mode.label) (⌘\(mode == .grid ? 1 : 2))", identifier: "view-\(mode.rawValue)") {
                            model.viewMode = mode
                        }
                    }
                    Rectangle().fill(Ink.hairline).frame(width: 1, height: 16).padding(.horizontal, 3)
                    FilterMenu(model: model)
                    GlassIconButton(symbol: "sidebar.right", selected: model.showInfo, help: "Show or hide the info panel (I)", identifier: "info-toggle") {
                        model.showInfo.toggle()
                    }
                }
                .padding(3).glassPill(interactive: true)
            }
            .padding(.trailing, Self.edge)
        }
        .padding(.top, 10)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private var searchPill: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").font(.system(size: 13, weight: .medium)).foregroundStyle(Ink.secondary)
            GlassSearchField(text: $model.searchText, focusTick: model.focusSearchTick, isFocused: $searchFocused, onSubmit: { model.rememberSearch() })
                .frame(height: 22)
            if !model.searchText.isEmpty {
                Button { model.searchText = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Ink.tertiary) }
                    .buttonStyle(.plain).help("Clear search")
            }
        }
        .padding(.horizontal, 14)
        .frame(width: 380, height: 40)
        .glassPill()
        .overlay(alignment: .top) { recentSearches.offset(y: 46) }
    }

    @ViewBuilder private var recentSearches: some View {
        if searchFocused, model.searchText.isEmpty, !model.recentSearches.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(model.recentSearches.prefix(6), id: \.self) { q in
                    Button { model.searchText = q } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "clock").font(.caption).foregroundStyle(Ink.tertiary)
                            Text(q).foregroundStyle(Ink.text).lineLimit(1)
                            Spacer()
                        }
                        .padding(.horizontal, 14).padding(.vertical, 8).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 6)
            .frame(width: 380)
            .glassCard(radius: 20)
        }
    }

    /// Where you are and how many items, in a small pill at the bottom.
    private var captionPill: some View {
        HStack(spacing: 8) {
            Text(model.title).foregroundStyle(Ink.text).fontWeight(.medium).lineLimit(1)
            Text(model.countLabel).foregroundStyle(Ink.secondary).lineLimit(1)
        }
        .font(.system(size: 12))
        .padding(.horizontal, 14).padding(.vertical, 7)
        .glassPill()
        .padding(.leading, (model.sidebarVisible ? Self.sidebarWidth + Self.edge : 0) + Self.edge + 4)
        .padding(.bottom, Self.edge + 2)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        .allowsHitTesting(false)
    }

    @ViewBuilder private var overlays: some View {
        if model.needsLibrary { WelcomeView(model: model) }
        if let id = model.previewID { PreviewOverlay(model: model, id: id) }
        if let panel = model.panel { PanelHost(model: model, panel: panel) }
        if let p = model.prompt { PromptCard(model: model, request: p) }
        if let c = model.confirm { ConfirmCard(model: model, request: c) }
        if model.cheatSheetVisible { CheatSheet().transition(.opacity) }
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

    @ViewBuilder private var gridBackground: some View {
        switch background {
        case "white": Color.white
        case "grey": Color(white: 0.16)
        default: Color.black
        }
    }
}

extension RootView {
    /// Dev: STASH_SNAPSHOT=<png path> renders the window's contents to that file a few seconds after launch (and quits when
    /// STASH_SNAPSHOT_QUIT is set). No screen access, so it works while the app is in the background.
    @MainActor
    static func snapshotIfRequested() {
        let env = ProcessInfo.processInfo.environment
        guard let path = env["STASH_SNAPSHOT"] else { return }
        let delay = Double(env["STASH_SNAPSHOT_DELAY"] ?? "") ?? 5
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(delay))
            func find(_ v: NSView) -> NSView? {
                if v is StashCollectionView { return v.enclosingScrollView ?? v }
                for s in v.subviews { if let hit = find(s) { return hit } }
                return nil
            }
            // the AppKit grid renders offscreen; a SwiftUI window does not
            let root = NSApp.windows.compactMap(\.contentView).first
            if let root, let v = find(root), let rep = v.bitmapImageRepForCachingDisplay(in: v.bounds) {
                v.cacheDisplay(in: v.bounds, to: rep)
                try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
                print("SNAPSHOT: \(path)")
            }
            if env["STASH_SNAPSHOT_QUIT"] != nil { NSApp.terminate(nil) }
        }
    }
}

struct ProgressCard: View {
    let label: String
    let done: Int
    let total: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label).font(.system(size: 12)).foregroundStyle(Ink.text).lineLimit(2)
            if total > 0 { ProgressView(value: Double(done), total: Double(max(total, 1))).progressViewStyle(.linear).tint(.white) }
            else { ProgressView().controlSize(.small) }
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .frame(maxWidth: 340, alignment: .leading)
        .glassCard(radius: 18)
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
            Image(systemName: "line.3.horizontal.decrease")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(model.filters.isActive || model.addedByFilter != nil ? Ink.text : Ink.secondary)
                .frame(width: 34, height: 34)
                .background(model.filters.isActive || model.addedByFilter != nil ? Ink.fillHover : .clear, in: Circle())
                .contentShape(Circle())
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
