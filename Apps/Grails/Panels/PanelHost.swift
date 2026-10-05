import GrailsKit
import SwiftUI

/// Dimmed backdrop + the active panel, centred in the window. A palette grows downward as results arrive, so it is centred at its
/// full height and the field stays where it is.
struct PanelHost: View {
    var model: AppModel
    let panel: Panel

    private var fullHeight: CGFloat { panel == .note ? 230 : 460 }

    var body: some View {
        GeometryReader { geo in
          ZStack(alignment: .top) {
            Ink.canvas.opacity(0.55).ignoresSafeArea().onTapGesture { model.closePanel() }
            Group {
                switch panel {
                case .commandK:
                    PaletteView(placeholder: "Search commands, collections, tags and items…", identifier: "palette",
                                rows: { await model.commandRows($0) }, onClose: { model.closePanel() })
                case .tags:
                    PaletteView(placeholder: "Tag \(model.selection.count) \(model.selection.count == 1 ? "item" : "items")…", identifier: "tag-panel",
                                refreshToken: model.itemsVersion, rows: { await model.tagRows($0) }, onClose: { model.closePanel() })
                case .move:
                    PaletteView(placeholder: "Move \(model.selection.count) \(model.selection.count == 1 ? "item" : "items") to…", identifier: "move-panel",
                                rows: { await model.moveRows($0) }, onClose: { model.closePanel() })
                case .note:
                    NotePanel(model: model)
                }
            }
            .padding(.top, max((geo.size.height - fullHeight) / 2, 24))
            .padding(.horizontal, 16)
          }
          .frame(width: geo.size.width, height: geo.size.height)
        }
        .ignoresSafeArea()
        .transition(.opacity)
    }
}

/// N: edit one item's note, or append a note to every selected item.
struct NotePanel: View {
    var model: AppModel
    @State private var text = ""
    @State private var original = ""
    @FocusState private var focused: Bool

    private var ids: [String] { Array(model.selection) }
    private var batch: Bool { ids.count > 1 }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(batch ? "Add a note to \(ids.count) items" : "Note").font(.grailsDisplay(16))
            TextEditor(text: $text)
                .font(.grailsBody(14))
                .frame(height: 140)
                .focused($focused)
                .scrollContentBackground(.hidden)
                .padding(6)
                .background(Ink.fill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .accessibilityIdentifier("note-field")
            HStack {
                Spacer()
                Button("Cancel") { model.closePanel() }.keyboardShortcut(.cancelAction)
                Button("Save") { save() }.keyboardShortcut(.return, modifiers: .command).buttonStyle(PrimaryButtonStyle())
                    .disabled(batch && text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(16)
        .frame(maxWidth: 480)
        .surfaceCard()
        .task {
            if !batch, let id = ids.first, let item = try? await model.store?.item(id: id) { text = item.note; original = item.note }
            focused = true
        }
    }

    private func save() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let targets = ids
        let isBatch = batch
        model.closePanel()
        Task {
            await model.perform(isBatch ? "Add Note" : "Edit Note") { store in
                if isBatch {
                    try await store.updateItems(ids: targets) { $0.note = $0.note.isEmpty ? trimmed : $0.note + "\n\n" + trimmed }
                } else {
                    try await store.setNote(trimmed, ids: targets)
                }
            }
        }
    }
}
