import SwiftUI
import StashKit

@main
struct StashApp: App {
    @State private var model = AppModel()
    @State private var shortcuts = ShortcutStore.shared

    init() {
        #if DEBUG
        installDebugCrashLog()
        #endif
    }

    var body: some Scene {
        WindowGroup {
            RootView(model: model)
                .frame(minWidth: 900, minHeight: 600)
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Collection…") { model.run(.newCollection) }.shortcut(.newCollection)
                Button("New Folder…") { model.promptNewCollection(kind: "folder", parent: nil) }
                Button("New Smart Folder…") { model.run(.newSmartFolder) }.shortcut(.newSmartFolder)
                Divider()
                Button("New Library…") { LibraryPicker.createNew(model) }
                Button("Open Library…") { LibraryPicker.openExisting(model) }.keyboardShortcut("o")
            }
            CommandGroup(replacing: .undoRedo) {
                Button(model.undoTitle ?? "Undo") { Task { await model.undo() } }
                    .keyboardShortcut("z").disabled(model.undoTitle == nil)
                Button(model.redoTitle ?? "Redo") { Task { await model.redo() } }
                    .keyboardShortcut("z", modifiers: [.command, .shift]).disabled(model.redoTitle == nil)
            }
            CommandGroup(after: .toolbar) {
                Button("Command Palette…") { model.run(.commandPalette) }.shortcut(.commandPalette)
                Button("Toggle Info Panel") { model.run(.toggleInfo) }
                Divider()
                Button("Zoom In") { model.run(.zoomIn) }.shortcut(.zoomIn)
                Button("Zoom Out") { model.run(.zoomOut) }.shortcut(.zoomOut)
                Button("Square Tiles") { model.layoutMode = .square }
                Button("Masonry Tiles") { model.layoutMode = .masonry }
                Button("Shuffle") { model.run(.shuffle) }
            }
            CommandMenu("Item") {
                Button("Like / Unlike") { model.run(.like) }.disabled(model.selection.isEmpty)
                Button("Edit Tags…") { model.run(.tag) }.disabled(model.selection.isEmpty)
                Button("Move to Collection…") { model.run(.move) }.disabled(model.selection.isEmpty)
                Button("Add Note…") { model.run(.note) }.disabled(model.selection.isEmpty)
                Button("Copy Source URL") { model.run(.copyURL) }.disabled(model.selection.isEmpty)
                Divider()
                Button("Move to Trash") { model.run(.trash) }.disabled(model.selection.isEmpty || model.source == .trash)
                Button("Restore from Trash") { model.restoreSelection() }.disabled(model.selection.isEmpty || model.source != .trash)
                Button("Empty Trash…") { model.confirmEmptyTrash() }
            }
        }
        Settings { SettingsView(model: model) }
    }
}
