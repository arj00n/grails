import GrailsKit
import SwiftUI

/// Dimmed backdrop + the active panel, centred in the window. A palette grows downward as results arrive, so it is centred at its
/// full height and the field stays where it is.
struct PanelHost: View {
    var model: AppModel
    let panel: Panel

    private var fullHeight: CGFloat { panel == .note ? 420 : 460 }

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

/// N: a note on the selection, or on a cluster. Several creatives get the same note, one file each.
struct NotePanel: View {
    var model: AppModel
    @State private var text = ""
    @FocusState private var focused: Bool

    private var ids: [String] { Array(model.selection) }
    private var batch: Bool {
        if case .cluster = model.noteTarget { return false }
        return ids.count > 1
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if case .cluster(let board, let id, let title) = model.noteTarget {
                Text("Note").font(.grailsDisplay(16))
                NoteThread(model: model, cluster: (board, id, title))
            } else if batch {
                Text("Add a note to \(ids.count) items").font(.grailsDisplay(16))
                TextField("Note", text: $text, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.grailsBody(14))
                    .lineLimit(3...8)
                    .focused($focused)
                    .accessibilityIdentifier("note-field")
                HStack {
                    Spacer()
                    Button("Cancel") { model.closePanel() }.keyboardShortcut(.cancelAction)
                    Button("Add") { saveBatch() }.keyboardShortcut(.return, modifiers: .command).buttonStyle(PrimaryButtonStyle())
                        .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            } else {
                Text("Note").font(.grailsDisplay(16))
                NoteThread(model: model, itemID: ids.first)
            }
        }
        .padding(16)
        .frame(maxWidth: 480)
        .surfaceCard()
        .onAppear { if batch { focused = true } }
    }

    private func saveBatch() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let targets = ids
        let people = model.contributors.map(\.who)
        model.closePanel()
        Task {
            await model.perform("Add Note") { store in
                for id in targets {
                    _ = try await store.addNote(text: trimmed, itemId: id, people: people)
                }
            }
        }
    }
}
