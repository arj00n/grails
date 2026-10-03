import SwiftUI

struct SettingsView: View {
    var model: AppModel
    @AppStorage("tileSpacing") private var spacing: Double = 8
    @AppStorage("cornerRadius") private var cornerRadius: Double = 8
    @AppStorage("appearance") private var appearance = "system"
    @AppStorage("gridBackground") private var background = "default"
    @AppStorage("userHandle") private var handle = StashPathsShim.handle
    @AppStorage("sidebar.showCollections") private var showCollections = true
    @AppStorage("sidebar.showTags") private var showTags = true

    var body: some View {
        TabView {
            Form {
                Picker("Appearance", selection: $appearance) {
                    Text("System").tag("system"); Text("Light").tag("light"); Text("Dark").tag("dark")
                }
                Picker("Grid background", selection: $background) {
                    Text("Default").tag("default"); Text("Black").tag("black"); Text("White").tag("white"); Text("Grey").tag("grey")
                }
                Slider(value: $spacing, in: 0...32, step: 1) { Text("Tile spacing") } minimumValueLabel: { Text("0") } maximumValueLabel: { Text("32") }
                Slider(value: $cornerRadius, in: 0...24, step: 1) { Text("Corner radius") } minimumValueLabel: { Text("0") } maximumValueLabel: { Text("24") }
                Section("Sidebar sections") {
                    Toggle("Collections", isOn: $showCollections)
                    Toggle("Tags", isOn: $showTags)
                }
            }
            .tabItem { Label("Appearance", systemImage: "paintbrush") }

            Form {
                TextField("Your name (shown as “added by”)", text: $handle)
                LabeledContent("Library") {
                    Text(model.layout?.root.path ?? "—").textSelection(.enabled).lineLimit(2)
                }
                HStack {
                    Button("Reveal in Finder") {
                        if let u = model.layout?.root { NSWorkspace.shared.activateFileViewerSelecting([u]) }
                    }
                    Button("Open another library…") { LibraryPicker.openExisting(model) }
                    Button("New library…") { LibraryPicker.createNew(model) }
                }
            }
            .tabItem { Label("Library", systemImage: "books.vertical") }
        }
        .formStyle(.grouped)
        .frame(width: 520, height: 380)
    }
}

enum StashPathsShim { static var handle: String { NSUserName() } }

@MainActor
enum LibraryPicker {
    static func openExisting(_ model: AppModel) {
        let p = NSOpenPanel()
        p.canChooseDirectories = true
        p.canChooseFiles = false
        p.treatsFilePackagesAsDirectories = false
        p.message = "Choose a Stash library (a folder ending in .stash)"
        if p.runModal() == .OK, let url = p.url { Task { await model.openOrCreate(at: url) } }
    }

    static func createNew(_ model: AppModel) {
        let p = NSSavePanel()
        p.nameFieldStringValue = "Stash Library.stash"
        p.message = "Choose where to create the new library"
        if p.runModal() == .OK, var url = p.url {
            if url.pathExtension != "stash" { url.appendPathExtension("stash") }
            Task { await model.openOrCreate(at: url) }
        }
    }
}
