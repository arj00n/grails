import StashKit
import SwiftUI

/// Dimmed backdrop + the active panel, anchored near the top like Spotlight.
struct PanelHost: View {
    var model: AppModel
    let panel: Panel

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.opacity(0.45).ignoresSafeArea().onTapGesture { model.closePanel() }
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
            .padding(.top, 70)
            .padding(.horizontal, 16)
        }
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
            Text(batch ? "Add a note to \(ids.count) items" : "Note").font(.headline)
            TextEditor(text: $text)
                .font(.body)
                .frame(height: 140)
                .focused($focused)
                .scrollContentBackground(.hidden)
                .padding(6)
                .background(Ink.fill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .accessibilityIdentifier("note-field")
            HStack {
                Spacer()
                Button("Cancel") { model.closePanel() }.keyboardShortcut(.cancelAction)
                Button("Save") { save() }.keyboardShortcut(.return, modifiers: .command).buttonStyle(.borderedProminent)
                    .disabled(batch && text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(16)
        .frame(maxWidth: 480)
        .glassCard(radius: 22)
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
