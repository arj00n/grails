import GrailsKit
import SwiftUI

struct SettingsView: View {
    var model: AppModel
    @AppStorage("tileSpacing") private var spacing: Double = 8
    @AppStorage("appearance") private var appearance = "system"
    @AppStorage("userHandle") private var handle = GrailsPathsShim.handle
    @AppStorage("linkPage") private var linkPage = ""
    @AppStorage("sidebar.showCollections") private var showCollections = true
    @AppStorage("sidebar.showTags") private var showTags = true
    @AppStorage("sidebar.showSmart") private var showSmart = true
    @AppStorage("hideDockIcon") private var hideDockIcon = false
    @AppStorage("showAddedBy") private var showAddedBy = false
    @AppStorage("autoSnapshotLinks") private var autoSnapshotLinks = true
    @AppStorage("autoTagNew") private var autoTagNew = true
    @AppStorage("canvasPush") private var canvasPush = true
    @AppStorage("autoTagSensitivity") private var autoTagSensitivity = 0.5

    var body: some View {
        TabView {
            Form {
                Picker("Appearance", selection: $appearance) {
                    Text("System").tag("system"); Text("Light").tag("light"); Text("Dark").tag("dark")
                }
                Toggle("Show who added each item", isOn: $showAddedBy)
                Picker("Grid tiles", selection: Binding(get: { model.layoutMode }, set: { model.layoutMode = $0 })) {
                    Text("Squares").tag(GridLayoutMode.square); Text("Original proportions").tag(GridLayoutMode.masonry)
                }
                Slider(value: $spacing, in: 0...32, step: 1) { Text("Tile spacing") } minimumValueLabel: { Text("0") } maximumValueLabel: { Text("32") }
                Section("Capture") {
                    Toggle("Snapshot links without a preview", isOn: $autoSnapshotLinks)
                    Toggle("Hide Dock icon", isOn: $hideDockIcon)
                        .onChange(of: hideDockIcon) { model.applyDockPolicy() }
                }
                Section("Canvas") {
                    Toggle("Push clusters aside when moving", isOn: $canvasPush)
                }
                Section("Auto-tagging") {
                    Toggle("Tag my new items automatically", isOn: $autoTagNew)
                        .onChange(of: autoTagNew) { if autoTagNew { model.kickAutoTag() } else { model.cancelAutoTag() } }
                    Slider(value: $autoTagSensitivity, in: 0...1) { Text("Tags per item") } minimumValueLabel: { Text("Fewer") } maximumValueLabel: { Text("More") }
                    HStack {
                        Button("Tag existing items now") { model.autoTagEverything() }
                        if let p = model.autoTagProgress { Text("\(p.done) of \(p.total)").foregroundStyle(.secondary).monospacedDigit() }
                    }
                    if !model.autoTagSkipped.isEmpty {
                        LabeledContent("Skipped here") {
                            Text(model.autoTagSkipped.joined(separator: ", ")).lineLimit(3).multilineTextAlignment(.trailing)
                        }
                        Button("Reset skipped tags") { model.resetAutoTagSkipped() }
                    }
                }
                Section("Sidebar sections") {
                    Toggle("Collections", isOn: $showCollections)
                    Toggle("Smart Folders", isOn: $showSmart)
                    Toggle("Tags", isOn: $showTags)
                }
            }
            .tabItem { Label("Appearance", systemImage: "paintbrush") }

            Form {
                TextField("Your name", text: $handle)
                TextField("Link page", text: $linkPage, prompt: Text("https://example.com/grails/open"))
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

            ShortcutsSettings()
                .tabItem { Label("Shortcuts", systemImage: "keyboard") }

            ExtensionsSettings(model: model)
                .tabItem { Label("Extensions", systemImage: "puzzlepiece.extension") }
        }
        .formStyle(.grouped)
        .frame(width: 560, height: 520)
        .task { await model.refreshAutoTagSkipped() }
    }
}

enum GrailsPathsShim { static var handle: String { NSUserName() } }

@MainActor
enum LibraryPicker {
    static func openExisting(_ model: AppModel) {
        let p = NSOpenPanel()
        p.canChooseDirectories = true
        p.canChooseFiles = false
        p.treatsFilePackagesAsDirectories = false
        if p.runModal() == .OK, let url = p.url { model.openLibrary(at: url) }
    }

    static func createNew(_ model: AppModel) {
        let p = NSSavePanel()
        p.nameFieldStringValue = "Grails Library.grails"
        if p.runModal() == .OK, var url = p.url {
            if url.pathExtension != "grails" { url.appendPathExtension("grails") }
            Task { await model.openOrCreate(at: url) }
        }
    }
}

struct ShortcutsSettings: View {
    @State private var store = ShortcutStore.shared
    @State private var recording: ShortcutAction?
    @State private var message: String?
    @State private var monitor: Any?

    var body: some View {
        Form {
            Section {
                ForEach(ShortcutAction.allCases) { a in
                    LabeledContent(a.title) {
                        HStack {
                            Button(recording == a ? "Press a key…" : store.shortcut(for: a).display) { startRecording(a) }
                                .frame(minWidth: 96)
                                .accessibilityIdentifier("shortcut-\(a.rawValue)")
                            if store.isCustomized(a) {
                                Button { store.reset(a) } label: { Image(systemName: "arrow.uturn.backward") }.buttonStyle(.borderless).help("Reset to default")
                            }
                        }
                    }
                }
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    if let message { Text(message).foregroundStyle(.red) }
                    Button("Reset all to defaults") { store.resetAll(); message = nil }
                }
            }
        }
        .onDisappear { stopRecording() }
    }

    private func startRecording(_ a: ShortcutAction) {
        stopRecording()
        recording = a
        message = nil
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let code = event.keyCode
            let shortcut = Shortcut(event: event)
            MainActor.assumeIsolated {
                if code == 53 { stopRecording(); return }       // Esc cancels
                guard let s = shortcut else { return }
                if let conflict = store.set(s, for: a) { message = conflict.message } else { message = nil; stopRecording() }
            }
            return nil   // swallow every key while recording
        }
    }

    private func stopRecording() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        recording = nil
    }
}

struct ExtensionsSettings: View {
    var model: AppModel
    @State private var confirmDisconnect = false

    var body: some View {
        Form {
            Section("Browser extension") {
                LabeledContent("Status") { Text(model.extensionPaired ? "Connected" : "Not connected") }
                LabeledContent("Library") { Text(model.libraryName) }
                HStack {
                    Button(model.extensionPaired ? "Add to another browser…" : "Install extension…") { model.extensionSetup.open() }
                        .accessibilityIdentifier("settings-install-extension")
                    if model.extensionPaired { Button("Disconnect…") { confirmDisconnect = true } }
                }
            }
        }
        .confirmationDialog("Disconnect the browser extension?", isPresented: $confirmDisconnect) {
            Button("Disconnect", role: .destructive) { model.disconnectExtensions() }
        } message: { Text("It asks to connect again the next time it runs.") }
    }
}
