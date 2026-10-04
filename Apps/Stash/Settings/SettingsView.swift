import StashKit
import SwiftUI

struct SettingsView: View {
    var model: AppModel
    @AppStorage("tileSpacing") private var spacing: Double = 8
    @AppStorage("cornerRadius") private var cornerRadius: Double = 8
    @AppStorage("appearance") private var appearance = "dark"
    @AppStorage("gridBackground") private var background = "black"
    @AppStorage("userHandle") private var handle = StashPathsShim.handle
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
                Picker("Grid background", selection: $background) {
                    Text("Default").tag("default"); Text("Black").tag("black"); Text("White").tag("white"); Text("Grey").tag("grey")
                }
                Toggle("Show who added each item (initials on tiles)", isOn: $showAddedBy)
                Picker("Grid tiles", selection: Binding(get: { model.layoutMode }, set: { model.layoutMode = $0 })) {
                    Text("Squares").tag(GridLayoutMode.square); Text("Original proportions").tag(GridLayoutMode.masonry)
                }
                Slider(value: $spacing, in: 0...32, step: 1) { Text("Tile spacing") } minimumValueLabel: { Text("0") } maximumValueLabel: { Text("32") }
                Slider(value: $cornerRadius, in: 0...24, step: 1) { Text("Corner radius") } minimumValueLabel: { Text("0") } maximumValueLabel: { Text("24") }
                Section("Capture") {
                    Toggle("Take a page snapshot for links without a preview image", isOn: $autoSnapshotLinks)
                    Toggle("Hide Dock icon (use the menu bar item)", isOn: $hideDockIcon)
                        .onChange(of: hideDockIcon) { model.applyDockPolicy() }
                }
                Section("Canvas") {
                    Toggle("Push items out of the way when dragging", isOn: $canvasPush)
                    Text("Drop an item onto others and they slide aside to make room. Hold ⌥ while dragging to let items overlap.")
                        .font(.caption).foregroundStyle(.secondary)
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
                        .help("Tags the recognizer put on so many of your items that they stopped being useful. Learned from this library.")
                        Button("Reset skipped tags") { model.resetAutoTagSkipped() }
                    }
                    Text((AutoTagger.engineName == "apple-on-device-vlm"
                          ? "Uses Apple's on-device model, which looks at each image and names the subject, kind of asset, style and colours."
                          : "Uses Apple's on-device image recognition (this Mac can't run the richer model). Best on photos.")
                         + " Nothing leaves this Mac. Tags are ordinary tags: edit or remove any of them and they stay gone.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("Sidebar sections") {
                    Toggle("Collections", isOn: $showCollections)
                    Toggle("Smart Folders", isOn: $showSmart)
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

enum StashPathsShim { static var handle: String { NSUserName() } }

@MainActor
enum LibraryPicker {
    static func openExisting(_ model: AppModel) {
        let p = NSOpenPanel()
        p.canChooseDirectories = true
        p.canChooseFiles = false
        p.treatsFilePackagesAsDirectories = false
        p.message = "Choose a Stash library (a folder ending in .stash)"
        if p.runModal() == .OK, let url = p.url { model.openLibrary(at: url) }
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
                    Text("Single-key shortcuts only work while the grid has focus, so they never interfere with typing. Press Esc while recording to cancel.")
                        .foregroundStyle(.secondary)
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
    @State private var token = ""
    @State private var reveal = false
    @State private var confirmRegenerate = false

    private var extensionFolder: URL? { Bundle.main.resourceURL?.appendingPathComponent("chrome", isDirectory: true) }

    var body: some View {
        Form {
            Section("Browser extension") {
                LabeledContent("Status") { Text(model.apiStatus).textSelection(.enabled) }
                LabeledContent("Library") { Text(model.libraryName) }
                LabeledContent("Pairing code") {
                    HStack {
                        Text(reveal ? token : String(repeating: "•", count: 24)).font(.system(.callout, design: .monospaced)).lineLimit(1).truncationMode(.middle)
                        Button(reveal ? "Hide" : "Show") { reveal.toggle() }
                        Button("Copy") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(token, forType: .string)
                        }
                        .accessibilityIdentifier("copy-pairing-code")
                    }
                }
                Button("Generate a new code…") { confirmRegenerate = true }
            }
            Section("Install the Chrome extension") {
                VStack(alignment: .leading, spacing: 6) {
                    Text("1. Open chrome://extensions and turn on Developer mode.")
                    Text("2. Click Load unpacked and choose the folder below.")
                    Text("3. Click the Stash toolbar button, paste the pairing code, and you're set.")
                    HStack {
                        Button("Show extension folder") {
                            if let u = extensionFolder { NSWorkspace.shared.activateFileViewerSelecting([u]) }
                        }
                        .disabled(extensionFolder.map { !FileManager.default.fileExists(atPath: $0.path) } ?? true)
                        Button("Copy folder path") {
                            if let u = extensionFolder { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(u.path, forType: .string) }
                        }
                    }
                }
                .font(.callout)
            }
            Section("Safe by design") {
                Text("The extension talks to Stash over 127.0.0.1 only, and every request must carry the pairing code. Web pages can't call it.")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
        .onAppear { token = model.tokens.token() }
        .confirmationDialog("Generate a new pairing code?", isPresented: $confirmRegenerate) {
            Button("Generate", role: .destructive) { token = model.tokens.regenerate() }
        } message: { Text("Extensions using the old code will stop working until you paste the new one.") }
    }
}
