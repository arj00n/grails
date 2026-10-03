import StashKit
import SwiftUI
import UniformTypeIdentifiers

struct RootView: View {
    @Bindable var model: AppModel
    @AppStorage("appearance") private var appearance = "system"
    @AppStorage("gridBackground") private var background = "default"
    @State private var dropTargeted = false

    var body: some View {
        NavigationSplitView {
            SidebarView(model: model)
        } detail: {
            detail
        }
        .preferredColorScheme(appearance == "light" ? .light : appearance == "dark" ? .dark : nil)
        .sheet(item: $model.smartEditor) { SmartFolderEditor(model: model, state: $0) }
        .alert("Stash", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            Button("OK") { model.errorMessage = nil }
        } message: { Text(model.errorMessage ?? "") }
        .task { await model.openInitialLibrary() }
        .onAppear { model.startCheatSheetMonitor() }
    }

    private var detail: some View {
        ZStack {
            gridBackground
            if model.items.isEmpty && model.store != nil { emptyState }
            switch model.viewMode {
            case .grid: GridView(model: model)
            case .canvas: CanvasView(model: model)
            }
        }
        // Overlays must not take part in layout: a fixed-width panel inside the ZStack would raise the detail pane's
        // minimum width above what's available when the info panel is open, and AppKit aborts the resulting loop.
        .overlay { overlays }
        .overlay { if dropTargeted { RoundedRectangle(cornerRadius: 6).strokeBorder(Color.accentColor, lineWidth: 3).padding(4).allowsHitTesting(false) } }
        .onDrop(of: [.fileURL, .stashItems], isTargeted: $dropTargeted) { providers in
            Task { @MainActor in
                let d = await DropLoader.load(providers)
                // Tiles dragged within the grid carry their ids: nothing to import.
                if d.itemIDs.isEmpty, !d.files.isEmpty { await model.importFiles(d.files) }
            }
            return true
        }
        .navigationTitle(model.title)
        .navigationSubtitle(model.countLabel)
        .searchable(text: $model.searchText, placement: .toolbar, prompt: "Search library")
        .searchSuggestions {
            if model.searchText.isEmpty {
                ForEach(model.recentSearches, id: \.self) { Text($0).searchCompletion($0) }
            }
        }
        .onSubmit(of: .search) { model.rememberSearch() }
        .toolbar { toolbar }
        .inspector(isPresented: $model.showInfo) {
            InfoPanel(model: model).inspectorColumnWidth(min: 240, ideal: 300, max: 440)
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
                ProgressView(value: Double(p.done), total: Double(max(p.total, 1))) { Text("Importing \(p.done) of \(p.total)…") }
                    .padding().background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10)).frame(maxWidth: 320)
            }
            if let p = model.renameProgress {
                ProgressView(value: Double(p.done), total: Double(max(p.total, 1))) { Text("Updating tags… \(p.done) of \(p.total)") }
                    .padding().background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10)).frame(maxWidth: 320)
            }
        }
        .padding(24)
        .animation(.default, value: model.toast)
        .allowsHitTesting(false)
    }

    @ViewBuilder private var gridBackground: some View {
        switch background {
        case "black": Color.black
        case "white": Color.white
        case "grey": Color(white: 0.5)
        default: Color(nsColor: .windowBackgroundColor)
        }
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItemGroup {
            Picker("View", selection: $model.viewMode) {
                ForEach(ViewMode.allCases) { Label($0.label, systemImage: $0.symbol).tag($0) }
            }
            .pickerStyle(.segmented)
            .help("Grid or Canvas (⌘1 / ⌘2)")
            .accessibilityIdentifier("view-switcher")

            FilterMenu(model: model)

            Button { model.showInfo.toggle() } label: { Label("Info", systemImage: "sidebar.right") }
                .help("Show or hide the info panel (I)")
                .accessibilityIdentifier("info-toggle")
        }
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
            Image(systemName: model.filters.isActive || model.addedByFilter != nil
                  ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
        }
        .menuIndicator(.hidden)
        .help("Filter and sort")
        .accessibilityLabel("Filter and sort")
        .accessibilityIdentifier("filter-menu")
    }
}
