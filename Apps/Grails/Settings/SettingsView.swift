import GrailsDesign
import GrailsKit
import GrailsSync
import SwiftUI
import UniformTypeIdentifiers

extension AppModel {
    /// ⌘,, the sidebar gear, ⌘K. The library stays where it is under the page.
    func openSettings(_ section: SettingsSection? = nil) {
        if !settings.isOpen, !GrailsModalLayer.shared.hasOpenModal, let window = NSApp.keyWindow, window.attachedSheet == nil {
            settingsReturnFocus = window.firstResponder
            // the grid, the canvas or the preview under the page must not take keys meant for Settings
            window.makeFirstResponder(nil)
        }
        workspaceMenuOpen = false
        HoverVideo.shared.cancel(.other)
        settings.open(section)
    }

    /// The back control, Esc, ⌘[. Focus goes back to what had it.
    func closeSettings() {
        guard settings.close() else { return }
        restoreSettingsFocus()
    }

    /// Esc on the page. A modal over it takes Esc first; this is the key the page sees when nothing is.
    func escapeSettings() {
        guard settings.escape(modalOpen: GrailsModalLayer.shared.hasOpenModal) else { return }
        restoreSettingsFocus()
    }

    private func restoreSettingsFocus() {
        let back = settingsReturnFocus
        settingsReturnFocus = nil
        // after the page is gone and the grid is showing again
        DispatchQueue.main.async { [weak self] in
            if let view = back as? NSView, let window = view.window, !view.isHiddenOrHasHiddenAncestor {
                window.makeFirstResponder(view)
            } else {
                self?.focusGridTick_bump()
            }
        }
    }
}

/// Settings as a page of the main window: its own section list where the library sidebar was, the section on the right, and a
/// way back. It covers the library while open; the library under it is untouched.
struct SettingsView: View {
    var model: AppModel
    var updater: UpdaterController
    @State private var libraryNameDraft = ""
    @AppStorage("tileSpacing") private var spacing: Double = 8
    @AppStorage("appearance") private var appearance = "system"
    @AppStorage(GrailsMotionPreference.key) private var motion = GrailsMotionPreference.system.rawValue
    @State private var nameDraft = ""
    @State private var savingName = false
    @State private var nameError: String?
    @State private var nameSaved = false
    @AppStorage("sidebar.showCollections") private var showCollections = true
    @AppStorage("sidebar.showTags") private var showTags = true
    @AppStorage("sidebar.showSmart") private var showSmart = true
    @AppStorage("hideDockIcon") private var hideDockIcon = false
    @AppStorage("showAddedBy") private var showAddedBy = false
    @AppStorage(HoverVideo.settingKey) private var hoverVideos = true
    @AppStorage("autoSnapshotLinks") private var autoSnapshotLinks = true
    @AppStorage("autoTagNew") private var autoTagNew = true
    @AppStorage("canvasPush") private var canvasPush = true
    @AppStorage("autoTagSensitivity") private var autoTagSensitivity = 0.5

    /// The readable width of a section. The window can be much wider than the old Settings window was.
    static let contentWidth: CGFloat = 600
    /// The width of a segmented control or slider on the right of a settings row.
    static let controlWidth: CGFloat = 240

    private var selectedTab: SettingsSection { model.settings.section }

    var body: some View {
        HStack(spacing: 0) {
            settingsSidebar
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    pageHeader
                    tabBody
                }
                .frame(maxWidth: Self.contentWidth, alignment: .topLeading)
                .padding(.top, 44)
                .padding(.horizontal, 40)
                .padding(.bottom, 40)
                .frame(maxWidth: .infinity, alignment: .top)
            }
            .background(Ink.canvas)
        }
        .font(.grailsBody(13))
        .tint(Ink.text)
        .background(Ink.canvas)
        // the page is opaque and takes every click, so nothing reaches the library under it
        .contentShape(Rectangle())
        .background {
            GrailsControl("") { model.escapeSettings() }.keyboardShortcut(.cancelAction).frame(width: 0, height: 0).opacity(0)
        }
        .accessibilityIdentifier("settings-page")
        .onAppear {
            libraryNameDraft = model.libraryName
            nameDraft = model.userHandle
            if ProcessInfo.processInfo.environment["GRAILS_PROOF_SAVE"] == "saving" {
                nameDraft = model.userHandle + " Chen"
                savingName = true
            }
        }
        .onDisappear { Task { await saveName() } }
        .onChange(of: model.libraryName) { libraryNameDraft = model.libraryName }
        .task { await model.refreshAutoTagSkipped() }
    }

    private var sections: [SettingsSection] {
        model.settings.visibleSections(teamConnected: model.bucket.connected, seesStorage: model.bucket.seesControls)
    }

    /// Where the library sidebar was: the same width and fill, the traffic lights and the way back on top, then the sections.
    private var settingsSidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            backBar
            VStack(alignment: .leading, spacing: 2) {
                ForEach(sections, id: \.self) { settingsTabButton($0) }
            }
            .grailsSelectionTrack { RoundedRectangle(cornerRadius: Ink.sidebarRadius, style: .continuous).fill(Ink.fillHover) }
            .padding(.horizontal, 10)
            .padding(.top, 6)
            Spacer(minLength: 0)
        }
        .frame(width: RootView.sidebarWidth, alignment: .top)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Ink.sidebar)
        .overlay(alignment: .trailing) { Rectangle().fill(Ink.separator).frame(width: 1) }
    }

    /// Past the traffic lights, like the library's own back button and title.
    private var backBar: some View {
        HStack(spacing: 6) {
            BarButton(symbol: "chevron.left", help: "Back to the library (Esc)", identifier: "settings-back") { model.closeSettings() }
            Text("Settings").font(.grailsDisplay(CGFloat(TypeScale.title))).foregroundStyle(Ink.text).lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.leading, TrafficLightMetrics.shared.leading)
        .frame(height: RootView.barHeight)
    }

    private func settingsTabButton(_ section: SettingsSection) -> some View {
        let on = selectedTab == section
        return GrailsControl(press: .row) { model.settings.select(section) } label: {
            HStack(spacing: 10) {
                Image(systemName: section.symbol).font(ChromeFont.symbol(14, weight: .regular)).frame(width: 16)
                Text(section.title).font(.grailsBody(13))
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .frame(height: 30)
            .foregroundStyle(on ? Ink.text : Ink.secondary)
            .grailsSelectionTarget(on)
            .contentShape(Rectangle())
        }
        .accessibilityIdentifier("settings-tab-\(section.rawValue)")
    }

    @ViewBuilder private var pageHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(selectedTab.title).font(.grailsDisplay(CGFloat(TypeScale.page))).tracking(TypeScale.pageTracking).foregroundStyle(Ink.text)
            Text(selectedTab.summary).font(.grailsBody(13)).foregroundStyle(Ink.secondary)
        }
        .padding(.bottom, 36)
    }

    @ViewBuilder private var tabBody: some View {
        switch selectedTab {
        case .general: generalPage
        case .library: libraryPage
        case .shortcuts: ShortcutsSettings()
        case .extensions: ExtensionsSettings(model: model)
        case .team: TeamSettingsTab(model: model, page: "team")
        case .storage: TeamSettingsTab(model: model, page: "storage")
        }
    }

    private var generalPage: some View {
        VStack(alignment: .leading, spacing: CGFloat(SettingsGroupMetrics.groupGap)) {
            GrailsSettingsGroup("Appearance") {
                GrailsSettingsRow("Theme") {
                    GrailsSegmented(options: [
                        .init(id: "system", title: "System"),
                        .init(id: "light", title: "Light"),
                        .init(id: "dark", title: "Dark"),
                    ], selection: appearance) { appearance = $0 }
                    .frame(width: Self.controlWidth)
                }
                GrailsSettingsRow("Motion") {
                    GrailsSegmented(options: [
                        .init(id: GrailsMotionPreference.system.rawValue, title: "System"),
                        .init(id: GrailsMotionPreference.reduce.rawValue, title: "Reduced"),
                        .init(id: GrailsMotionPreference.full.rawValue, title: "Full"),
                    ], selection: motion) { motion = $0 }
                    .frame(width: Self.controlWidth)
                }
            }
            GrailsSettingsGroup("Grid") {
                GrailsSettingsToggle("Show who added each item", isOn: $showAddedBy)
                GrailsSettingsToggle("Play videos on hover", isOn: $hoverVideos)
                GrailsSettingsRow("Tiles") {
                    GrailsSegmented(options: [
                        .init(id: GridLayoutMode.square.rawValue, title: "Squares"),
                        .init(id: GridLayoutMode.masonry.rawValue, title: "Original"),
                    ], selection: model.layoutMode.rawValue) { model.layoutMode = GridLayoutMode(rawValue: $0) ?? .square }
                    .frame(width: Self.controlWidth)
                }
                GrailsSettingsRow("Tile spacing") {
                    Slider(value: $spacing, in: 0...32, step: 1) { EmptyView() } minimumValueLabel: { Text("0") } maximumValueLabel: { Text("32") }
                        .accessibilityLabel("Tile spacing")
                        .frame(width: Self.controlWidth)
                }
            }
            GrailsSettingsGroup("Capture") {
                GrailsSettingsToggle("Add a picture to links that don't have one", isOn: $autoSnapshotLinks)
                GrailsSettingsToggle("Hide Dock icon", isOn: $hideDockIcon)
                    .onChange(of: hideDockIcon) { model.applyDockPolicy() }
            }
            GrailsSettingsGroup("Canvas") {
                GrailsSettingsToggle("Push clusters aside when moving", isOn: $canvasPush)
            }
            GrailsSettingsGroup("Auto-tagging") {
                GrailsSettingsToggle("Tag my new items automatically", isOn: $autoTagNew)
                    .onChange(of: autoTagNew) { if autoTagNew { model.kickAutoTag() } else { model.cancelAutoTag() } }
                GrailsSettingsRow("Tags per item") {
                    Slider(value: $autoTagSensitivity, in: 0...1) { EmptyView() } minimumValueLabel: { Text("Fewer") } maximumValueLabel: { Text("More") }
                        .accessibilityLabel("Tags per item")
                        .frame(width: Self.controlWidth)
                }
                GrailsSettingsRow("Existing items") {
                    if let p = model.autoTagProgress { Text("\(p.done) of \(p.total)").foregroundStyle(Ink.secondary).monospacedDigit() }
                    GrailsButton("Tag existing items now", kind: .secondary) { model.autoTagEverything() }
                }
                if !model.autoTagSkipped.isEmpty {
                    GrailsSettingsRow("Skipped tags", detail: model.autoTagSkipped.joined(separator: ", ")) {
                        GrailsButton("Reset skipped tags", kind: .secondary) { model.resetAutoTagSkipped() }
                    }
                }
            }
            GrailsSettingsGroup("Sidebar") {
                GrailsSettingsToggle("Collections", isOn: $showCollections)
                GrailsSettingsToggle("Smart Folders", isOn: $showSmart)
                GrailsSettingsToggle("Tags", isOn: $showTags)
            }
        }
    }

    /// The avatar large, with Shuffle, the colours and the photo action under it. Every choice saves to the profile and syncs.
    private var avatarChooser: some View {
        GrailsSettingsBlock {
            GrailsAvatarEditor(
                model.myFace,
                onShuffle: { model.shuffleAvatar() },
                onPickTone: { model.setAvatarTone($0) },
                onUploadPhoto: { model.chooseAvatar() },
                onRemovePhoto: { model.removeAvatarPhoto() }
            )
        }
    }

    private var libraryPage: some View {
        VStack(alignment: .leading, spacing: CGFloat(SettingsGroupMetrics.groupGap)) {
            GrailsSettingsGroup("Profile") {
                avatarChooser
                GrailsSettingsBlock {
                    GrailsTextField("Username", text: $nameDraft, required: true, error: nameError, identifier: "settings-username", corrects: false, onSubmit: { Task { await saveName() } })
                    HStack(spacing: 12) {
                        Spacer(minLength: 0)
                        if nameSaved {
                            Text("Saved")
                                .font(.grailsBody(12))
                                .foregroundStyle(Ink.secondary)
                                .accessibilityIdentifier("settings-username-saved")
                        }
                        GrailsButton("Save", kind: .primary, loading: savingName, identifier: "settings-username-save", enabled: canSaveName && !savingName) { Task { await saveName() } }
                    }
                }
            }
            GrailsSettingsGroup("Library") {
                GrailsSettingsBlock {
                    GrailsTextField("Library name", text: $libraryNameDraft, identifier: "settings-library-name", corrects: false, onSubmit: saveLibraryName)
                        .disabled(!model.canRenameLibrary)
                    HStack {
                        Spacer(minLength: 0)
                        GrailsButton("Save", kind: .secondary, identifier: "settings-library-save", enabled: model.canRenameLibrary && !libraryNameDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) { saveLibraryName() }
                    }
                }
                GrailsSettingsRow("Folder", detail: model.layout?.root.path ?? "—") {
                    GrailsButton("Reveal in Finder", kind: .secondary) {
                        if let u = model.layout?.root { NSWorkspace.shared.activateFileViewerSelecting([u]) }
                    }
                }
                GrailsSettingsRow("Other libraries") {
                    GrailsButton("Open another library…", kind: .secondary) { LibraryPicker.openExisting(model) }
                    GrailsButton("New library…", kind: .secondary) { LibraryPicker.createNew(model) }
                }
            }
            GrailsSettingsGroup("Team") {
                if model.libraryPlace.needsReconnect {
                    GrailsSettingsRow("Storage") {
                        GrailsButton("Reconnect storage…", kind: .secondary, identifier: "reconnect-bucket") { model.showReconnect = true }
                    }
                } else if model.store != nil, !model.bucket.connected {
                    GrailsSettingsRow("Storage") {
                        GrailsButton("Move this library to cloud storage", kind: .secondary, identifier: "migrate-folder") { model.showMigrateSheet = true }
                    }
                }
                GrailsSettingsRow("Shared through") {
                    Text(model.layout == nil && !model.bucket.connected ? "—" : model.libraryPlace.label).foregroundStyle(Ink.secondary).lineLimit(1)
                }
                GrailsSettingsRow("People") {
                    if model.libraryPlace.offersTeamSetup {
                        GrailsButton("Set up team library…", kind: .secondary, identifier: "settings-team-setup") { model.collab.presentSetup() }
                    }
                    GrailsButton("Invite…", kind: .secondary, identifier: "settings-invite") { model.collab.presentInvite() }
                }
            }
            GrailsSettingsGroup("Updates") {
                GrailsSettingsToggle("Check automatically", isOn: Binding(get: { updater.checksAutomatically }, set: { updater.setChecksAutomatically($0) }))
                GrailsSettingsRow("Last checked") {
                    if let d = updater.lastChecked {
                        Text(d.formatted(.relative(presentation: .named))).foregroundStyle(Ink.secondary).monospacedDigit()
                    }
                    GrailsButton("Check now", kind: .secondary, enabled: updater.canCheck) { updater.checkForUpdates() }
                }
            }
            .disabled(!updater.isAvailable)
            GrailsSettingsGroup("Feedback") {
                GrailsSettingsRow("Something wrong or missing?") {
                    GrailsButton("Send Feedback…", kind: .secondary, identifier: "settings-feedback") { model.feedbackOpen = true }
                }
            }
        }
    }

    private var canSaveName: Bool { DisplayName.canSave(draft: nameDraft, current: model.userHandle) }

    private func saveName() async {
        let draft = nameDraft
        guard DisplayName.normalized(draft) != nil else {
            nameError = "Enter a name"
            nameSaved = false
            return
        }
        guard canSaveName, !savingName else { return }
        savingName = true
        nameError = nil
        nameSaved = false
        let saved = await model.commitDisplayName(draft)
        savingName = false
        if saved {
            nameDraft = model.userHandle
            nameSaved = true
        } else {
            nameError = "Enter a name"
            nameDraft = model.userHandle
        }
    }

    private func saveLibraryName() {
        Task { await saveName() }
        let draft = libraryNameDraft
        Task { @MainActor in await model.renameLibrary(to: draft) }
    }
}

struct MigrateLibrarySheet: View {
    @Bindable var model: AppModel
    private func dismiss() { model.showMigrateSheet = false }
    @State private var draft = BucketDraft()
    @State private var showRegion = false
    @State private var error: String?

    var body: some View {
        GrailsModal(title: "Move this library to cloud storage", step: model.bucket.migrating ? "copy" : "credentials", error: error, identifier: "migrate-library-sheet", onClose: { dismiss() }) {
            VStack(alignment: .leading, spacing: CGFloat(Space.md)) {
                GrailsSection(BucketDraft.bucketSection, symbol: ChromeIcon.bucket) {
                    VStack(alignment: .leading, spacing: CGFloat(ChromeMetrics.groupGap)) {
                        GrailsTextField("Endpoint", text: $draft.endpoint, required: true, error: draft.endpointError, placeholder: BucketDraft.field("endpoint").placeholder, identifier: "migrate-endpoint", corrects: false, autofocus: true, onSubmit: start)
                        GrailsTextField("Bucket", text: $draft.bucket, required: true, placeholder: BucketDraft.field("bucket").placeholder, identifier: "migrate-bucket", corrects: false, onSubmit: start)
                        GrailsDisclosure("Region", value: draft.regionForSave, expanded: $showRegion) {
                            GrailsInlineField(text: $draft.region, placeholder: "auto", identifier: "migrate-region", onSubmit: start)
                        }
                        GrailsTextField("Access key", text: $draft.accessKey, required: true, identifier: "migrate-key", corrects: false, onSubmit: start)
                        GrailsSecureField("Secret", text: $draft.secret, required: true, identifier: "migrate-secret", showsPaste: true, onSubmit: start)
                        GrailsTextField("Your email", text: $draft.email, required: true, error: draft.emailError, placeholder: "name@company.com", identifier: "migrate-email", corrects: false, onSubmit: start)
                    }
                }
                if let migration = model.bucket.migration {
                    Text("\(migration.copied) of \(migration.total)")
                        .font(.grailsBody(13))
                        .foregroundStyle(Ink.secondary)
                }
            }
        } footer: {
            HStack {
                Spacer()
                GrailsButton("Copy", kind: .primary, loading: model.bucket.migrating, identifier: "migrate-copy", enabled: draft.canCreate) { start() }
            }
        }
    }

    private func start() {
        guard draft.canCreate, let root = model.layout?.root else { return }
        let snapshot = draft
        draft.secret = ""
        error = nil
        Task {
            let message = await model.bucket.migrateFolder(
                endpoint: snapshot.endpoint, region: snapshot.regionForSave, bucket: snapshot.bucket,
                accessKeyId: snapshot.accessKey, secret: snapshot.secret, email: snapshot.email, root: root
            )
            error = message
            if message != nil { draft.secret = snapshot.secret }
            else { model.onboarding?.finish() }
        }
    }
}

enum GrailsPathsShim { static var handle: String { NSUserName() } }

@MainActor
enum LibraryPicker {
    /// A `.grails` library is a package, so the panel shows it as a file. Files of that type can be chosen, and so can the folder around one.
    static func panel(message: String) -> NSOpenPanel {
        let p = NSOpenPanel()
        p.canChooseDirectories = true
        p.canChooseFiles = true
        p.treatsFilePackagesAsDirectories = false
        p.allowedContentTypes = [UTType.grailsLibrary].compactMap { $0 }
        p.message = message
        p.prompt = "Open"
        return p
    }

    static func openExisting(_ model: AppModel) {
        let p = panel(message: "Choose a Grails library (a folder ending in .grails)")
        if p.runModal() == .OK, let url = p.url { model.openLibrary(at: url) }
    }

    static func createNew(_ model: AppModel) {
        model.workspaceDraft = .choose
    }

    static func saveNewFolder(_ model: AppModel) {
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
        VStack(alignment: .leading, spacing: CGFloat(SettingsGroupMetrics.groupGap)) {
            GrailsSettingsGroup("Keys") {
                ForEach(ShortcutAction.allCases) { a in
                    GrailsSettingsRow(a.title) {
                        HStack(spacing: 8) {
                            if store.isCustomized(a) {
                                GrailsIconButton("arrow.uturn.backward", label: "Reset to default") { store.reset(a) }
                            }
                            GrailsButton(recording == a ? "Press a key…" : store.shortcut(for: a).display, kind: .secondary, identifier: "shortcut-\(a.rawValue)") { startRecording(a) }
                        }
                    }
                }
            }
            GrailsSettingsGroup("Defaults") {
                GrailsSettingsRow("All shortcuts", detail: message) {
                    GrailsButton("Reset all to defaults", kind: .secondary) { store.resetAll(); message = nil }
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

    var body: some View {
        GrailsSettingsGroup("Browser extension") {
            GrailsSettingsRow("Status") { StatusDot(model.extensionPaired ? .ok : .error, model.extensionPaired ? "Connected" : "Not connected") }
            GrailsSettingsRow("Saves to") { Text(model.libraryName).foregroundStyle(Ink.secondary).lineLimit(1) }
            GrailsSettingsRow("Browsers") {
                if model.extensionPaired { GrailsButton("Disconnect…", kind: .secondary) { confirmDisconnect() } }
                GrailsButton(model.extensionPaired ? "Add to another browser…" : "Install extension…", kind: .secondary, identifier: "settings-install-extension") { model.extensionSetup.open(app: model) }
            }
        }
    }

    private func confirmDisconnect() {
        model.confirm = ConfirmRequest(title: "Disconnect the browser extension?", message: "It asks to connect again the next time it runs.", confirmTitle: "Disconnect") { [model] in
            model.disconnectExtensions()
        }
    }
}

extension SettingsSection {
    var title: String {
        switch self {
        case .general: "General"
        case .library: "Library"
        case .shortcuts: "Shortcuts"
        case .extensions: "Extensions"
        case .team: "Team"
        case .storage: "Storage"
        }
    }

    var symbol: String {
        switch self {
        case .general: "sun.max"
        case .library: "square.grid.2x2"
        case .shortcuts: "keyboard"
        case .extensions: "puzzlepiece.extension"
        case .team: "person.2"
        case .storage: "cylinder"
        }
    }

    var summary: String {
        switch self {
        case .general: "Appearance, capture, and the sidebar."
        case .library: "Name, folder, and updates."
        case .shortcuts: "Keys for the things you do often."
        case .extensions: "Save from your browser in one click."
        case .team: "Who's in this library, and who curates it."
        case .storage: "Space, clean-up, and backups."
        }
    }
}
