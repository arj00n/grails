import AppKit
import SwiftUI
import GrailsDesign
import GrailsKit

@main
struct GrailsApp: App {
    @NSApplicationDelegateAdaptor(GrailsAppDelegate.self) private var delegate
    @State private var model = AppModel()
    @State private var shortcuts = ShortcutStore.shared
    @State private var updater = UpdaterController.shared

    init() {
        UpdaterController.start()
        #if DEBUG
        installDebugCrashLog()
        #endif
    }

    var body: some Scene {
        WindowGroup {
            RootView(model: model)
                .grailsMotionRoot()
                .frame(minWidth: 900, minHeight: 600)
                .onAppear { GrailsAppDelegate.connect(model) }
        }
        .handlesExternalEvents(matching: [])
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(after: .appInfo) {
                GrailsMenuItem("Check for Updates…", enabled: updater.canCheck) { updater.checkForUpdates() }
            }
            // Settings is a page of the main window, not a window of its own
            CommandGroup(replacing: .appSettings) {
                GrailsMenuItem("Settings…", shortcut: Shortcut(",", .command)) { model.openSettings() }
            }
            CommandGroup(replacing: .newItem) {
                GrailsMenuItem("New Collection…", shortcut: shortcuts.shortcut(for: .newCollection)) { model.run(.newCollection) }
                GrailsMenuItem("New Folder…") { model.promptNewCollection(kind: "folder", parent: nil) }
                GrailsMenuItem("New Smart Folder…", shortcut: shortcuts.shortcut(for: .newSmartFolder)) { model.run(.newSmartFolder) }
                Divider()
                GrailsMenuItem("Import Boards…", shortcut: Shortcut("i", [.command, .shift])) { model.promptImportBoard() }
                Divider()
                GrailsMenuItem("New Library…") { LibraryPicker.createNew(model) }
                GrailsMenuItem("Open Library…", shortcut: Shortcut("o", .command)) { LibraryPicker.openExisting(model) }
                Divider()
                Menu("Export View As") {
                    ForEach(ShareFormat.allCases) { f in
                        if f == .html {
                            GrailsMenuItem(f.menuTitle, shortcut: Shortcut("e", [.command, .option])) { model.exportWebPage(format: f) }
                        } else {
                            GrailsMenuItem(f.menuTitle) { model.exportWebPage(format: f) }
                        }
                    }
                }
                Menu("Export Selection As") {
                    ForEach(ShareFormat.allCases) { f in
                        GrailsMenuItem(f.menuTitle) { model.exportWebPage(selectionOnly: true, format: f) }
                    }
                }.disabled(model.selection.isEmpty)
                GrailsMenuItem("Copy Link to This View", shortcut: Shortcut("l", [.command, .option])) { model.copyViewLink() }
                GrailsMenuItem(model.libraryPlace.needsReconnect ? "Reconnect storage…" : "Invite…") { model.collab.presentInvite() }
                GrailsMenuItem("Copy Invite Link", enabled: model.libraryPlace.copiesFolderInvite) { model.copyInviteLink() }
                GrailsMenuItem("Join with invite…") {
                    model.bucket.resetOnboarding()
                    model.workspaceDraft = .invite
                }
            }
            CommandMenu("Workspace") {
                GrailsMenuItem("Command Palette…", shortcut: shortcuts.shortcut(for: .commandPalette)) { model.run(.commandPalette) }
                Divider()
                ForEach(Array(model.workspaces.prefix(9).enumerated()), id: \.element.id) { index, w in
                    GrailsMenuItem(w.name, shortcut: Shortcut(String(index + 1), .control)) { model.switchWorkspace(w) }
                }
            }
            CommandGroup(after: .help) {
                GrailsMenuItem("Send Feedback…") { model.feedbackOpen = true }
                GrailsMenuItem("Design Gallery") { model.designGallery = true }
            }
            CommandGroup(after: .textEditing) {
                GrailsMenuItem("Find", shortcut: Shortcut("f", .command)) {
                    model.closeSettings()
                    model.focusSearchTick += 1
                }
                GrailsMenuItem(
                    "Back",
                    shortcut: Shortcut("[", .command),
                    enabled: model.canGoBack || model.settings.isOpen
                ) {
                    if model.settings.isOpen { model.closeSettings() } else { model.goBack() }
                }
            }
            CommandGroup(after: .sidebar) {
                GrailsMenuItem("Toggle Sidebar", shortcut: Shortcut("s", [.command, .control])) { model.sidebarVisible.toggle() }
                GrailsMenuItem("Hide or Show Both Panels", shortcut: Shortcut("\\", .command)) { model.togglePanels() }
            }
            CommandGroup(after: .pasteboard) {
                GrailsMenuItem("Paste as Link", shortcut: Shortcut("v", [.command, .option])) { model.paste(forceLink: true) }
                GrailsMenuItem("Save Clipboard to Inbox", shortcut: Shortcut("v", [.command, .shift])) { model.paste(toInbox: true) }
            }
            CommandGroup(replacing: .undoRedo) {
                GrailsMenuItem(model.undoTitle ?? "Undo", shortcut: Shortcut("z", .command), enabled: model.undoTitle != nil) {
                    Task { await model.undo() }
                }
                GrailsMenuItem(
                    model.redoTitle ?? "Redo",
                    shortcut: Shortcut("z", [.command, .shift]),
                    enabled: model.redoTitle != nil
                ) {
                    Task { await model.redo() }
                }
            }
            CommandGroup(after: .toolbar) {
                GrailsMenuItem("Refresh Library", shortcut: Shortcut("r", .command)) { Task { await model.refreshLibrary() } }
                Divider()
                GrailsMenuItem("Zoom In", shortcut: shortcuts.shortcut(for: .zoomIn)) { model.run(.zoomIn) }
                GrailsMenuItem("Zoom Out", shortcut: shortcuts.shortcut(for: .zoomOut)) { model.run(.zoomOut) }
                GrailsMenuItem("Zoom to Fit", shortcut: Shortcut("0", .command)) { model.canvasRequest = CanvasRequest(kind: .fit) }
                GrailsMenuItem("Tidy Clusters", shortcut: Shortcut("a", [.command, .option])) {
                    model.canvasRequest = CanvasRequest(kind: .tidyClusters)
                }
                GrailsMenuItem("Group Selection into Cluster", shortcut: Shortcut("g", .command)) {
                    model.canvasRequest = CanvasRequest(kind: .groupSelection)
                }
                GrailsMenuItem("Grid", shortcut: Shortcut("1", .command)) { model.viewMode = .grid }
                GrailsMenuItem("Canvas", shortcut: Shortcut("2", .command)) { model.viewMode = .canvas }
                Divider()
                GrailsMenuItem("Square Tiles") { model.layoutMode = .square }
                GrailsMenuItem("Original Proportions") { model.layoutMode = .masonry }
                GrailsMenuItem("Shuffle") { model.run(.shuffle) }
            }
            CommandMenu("Item") {
                GrailsMenuItem("Like / Unlike", enabled: !noVisibleSelection) { model.run(.like) }
                GrailsMenuItem("Edit Tags…", enabled: !noVisibleSelection) { model.run(.tag) }
                GrailsMenuItem("Move to Collection…", enabled: !noVisibleSelection) { model.run(.move) }
                GrailsMenuItem("Add Note…", enabled: !noVisibleSelection) { model.run(.note) }
                GrailsMenuItem("Copy Source URL", enabled: !noVisibleSelection) { model.run(.copyURL) }
                Divider()
                GrailsMenuItem("Move to Trash", enabled: !noVisibleSelection && model.source != .trash) { model.run(.trash) }
                GrailsMenuItem("Restore from Trash", enabled: !noVisibleSelection && model.source == .trash) { model.restoreSelection() }
                GrailsMenuItem("Empty Trash…") { model.confirmEmptyTrash() }
            }
        }
    }

    private var noVisibleSelection: Bool { model.selection.isEmpty || model.settings.isOpen }
}
