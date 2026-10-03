import StashKit
import SwiftUI

struct RootView: View {
    @Bindable var model: AppModel
    @AppStorage("appearance") private var appearance = "system"
    @AppStorage("gridBackground") private var background = "default"
    @State private var dropTargeted = false

    var body: some View {
        NavigationSplitView {
            SidebarView(model: model)
        } detail: {
            ZStack {
                gridBackground
                if model.items.isEmpty && model.store != nil {
                    ContentUnavailableView(
                        model.source == .trash ? "Trash is empty" : "Nothing here yet",
                        systemImage: "photo.on.rectangle.angled",
                        description: Text("Drop images, videos or folders here to add them.")
                    )
                }
                GridView(model: model)
                if let id = model.previewID { PreviewOverlay(model: model, id: id) }
                if let p = model.importProgress {
                    VStack { Spacer(); ProgressView(value: Double(p.done), total: Double(max(p.total, 1))) { Text("Importing \(p.done) of \(p.total)…") }
                        .padding().background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10)).frame(maxWidth: 320).padding(24) }
                }
            }
            .overlay { if dropTargeted { RoundedRectangle(cornerRadius: 6).strokeBorder(Color.accentColor, lineWidth: 3).padding(4).allowsHitTesting(false) } }
            .dropDestination(for: URL.self) { urls, _ in
                Task { await model.importFiles(urls) }
                return true
            } isTargeted: { dropTargeted = $0 }
            .navigationTitle(model.title)
            .navigationSubtitle("\(model.items.count.formatted()) items")
            .toolbar { toolbar }
            .inspector(isPresented: $model.showInfo) {
                InfoPanel(model: model).inspectorColumnWidth(min: 240, ideal: 300, max: 440)
            }
        }
        .preferredColorScheme(appearance == "light" ? .light : appearance == "dark" ? .dark : nil)
        .alert("Stash", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            Button("OK") { model.errorMessage = nil }
        } message: { Text(model.errorMessage ?? "") }
        .task { await model.openInitialLibrary() }
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
            Picker("Layout", selection: $model.layoutMode) {
                ForEach(GridLayoutMode.allCases) { Label($0.label, systemImage: $0.symbol).tag($0) }
            }
            .pickerStyle(.segmented)
            .help("Square or masonry tiles")
            .accessibilityIdentifier("layout-picker")

            HStack(spacing: 6) {
                Image(systemName: "minus.magnifyingglass").foregroundStyle(.secondary)
                Slider(value: Binding(get: { Double(model.zoomStep) }, set: { model.zoomStep = Int($0.rounded()) }), in: 0...Double(Zoom.maxStep), step: 1)
                    .frame(width: 110)
                    .accessibilityIdentifier("zoom-slider")
                Image(systemName: "plus.magnifyingglass").foregroundStyle(.secondary)
                Text(Zoom.labels[model.zoomStep]).font(.caption.monospaced()).frame(width: 28, alignment: .leading)
            }
            .help("Zoom (⌘ + scroll or pinch)")

            Button { model.showInfo.toggle() } label: { Label("Info", systemImage: "sidebar.right") }
                .help("Show or hide the info panel (I)")
                .accessibilityIdentifier("info-toggle")
        }
    }
}
