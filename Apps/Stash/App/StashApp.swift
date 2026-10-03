import SwiftUI
import StashKit

@main
struct StashApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView(model: model)
                .frame(minWidth: 900, minHeight: 600)
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Library…") { LibraryPicker.createNew(model) }
                Button("Open Library…") { LibraryPicker.openExisting(model) }.keyboardShortcut("o")
            }
            CommandGroup(after: .toolbar) {
                Button("Toggle Info Panel") { model.showInfo.toggle() }.keyboardShortcut("i", modifiers: [])
                Divider()
                Button("Zoom In") { model.zoomStep = min(model.zoomStep + 1, Zoom.maxStep) }.keyboardShortcut("=")
                Button("Zoom Out") { model.zoomStep = max(model.zoomStep - 1, 0) }.keyboardShortcut("-")
                Button("Square Tiles") { model.layoutMode = .square }
                Button("Masonry Tiles") { model.layoutMode = .masonry }
            }
        }
        Settings { SettingsView(model: model) }
    }
}
