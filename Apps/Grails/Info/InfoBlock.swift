import AppKit
import GrailsKit
import SwiftUI

/// Everything about one item, always visible: used as the inspector and as the preview's right-hand column. Name, tags and note are
/// edited right here; tags, collections and people take you to their pages.
struct InfoBlock: View {
    var model: AppModel
    let itemID: String?
    @State private var item: Item?
    @State private var name = ""
    @State private var note = ""
    @State private var newTag = ""
    @FocusState private var focus: Field?
    private enum Field { case name, note, tag }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let item {
                let info = ItemInfo.make(item: item) { id in model.collections.first { $0.id == id }?.name }
                header(item, info)
                provenance(info)
                if !info.facts.isEmpty { Text(info.facts).font(.grailsBody(12)).monospacedDigit().foregroundStyle(Ink.secondary) }
                if !info.palette.isEmpty { palette(info.palette) }
                tags(info)
                collections(info)
                noteField
                if !info.camera.isEmpty { camera(info.camera) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .task(id: itemID) { await load() }
        .onChange(of: model.itemsVersion) { Task { await load() } }
    }

    private func load() async {
        guard let id = itemID, let store = model.store else { item = nil; return }
        let loaded = try? await store.item(id: id)
        item = loaded
        if focus != .name { name = loaded?.name ?? "" }
        if focus != .note { note = loaded?.note ?? "" }
    }

    // MARK: Pieces

    private func header(_ item: Item, _ info: ItemInfo) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            TextField("Name", text: $name, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.grailsDisplay(16))
                .lineLimit(1...3)
                .focused($focus, equals: .name)
                .onSubmit { commitName(item) }
                .onChange(of: focus) { old, new in if old == .name, new != .name { commitName(item) } }
            Spacer(minLength: 0)
            Button { model.toggleLike(ids: [item.id]) } label: {
                Image(systemName: item.liked ? "heart.fill" : "heart").font(.system(size: 13)).foregroundStyle(item.liked ? Ink.text : Ink.secondary)
            }
            .buttonStyle(.plain)
            .help("Like (L)")
            .accessibilityLabel(item.liked ? "Unlike" : "Like")
        }
    }

    private func provenance(_ info: ItemInfo) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            if info.site != nil || info.author != nil {
                HStack(spacing: 6) {
                    if let url = info.sourceURL, let site = info.site {
                        Link(destination: url) { Text("\(site) ↗").foregroundStyle(Ink.link) }.help(url.absoluteString)
                    } else if let site = info.site { Text(site).foregroundStyle(Ink.link) }
                    if let author = info.author { Text("· \(author)").foregroundStyle(Ink.secondary) }
                }
                .font(.grailsBody(13)).lineLimit(1)
            }
            HStack(spacing: 4) {
                Text("Added by").foregroundStyle(Ink.secondary)
                PersonLink(name: info.addedBy) { model.showContributions(of: info.addedBy) }
                Text("· \(info.addedAt.formatted(.dateTime.day().month(.abbreviated).year()))").foregroundStyle(Ink.secondary)
            }
            .font(.grailsBody(12))
            if let editor = info.editedBy {
                HStack(spacing: 4) {
                    Text("Edited by").foregroundStyle(Ink.secondary)
                    PersonLink(name: editor) { model.showContributions(of: editor) }
                }
                .font(.grailsBody(12))
            }
        }
    }

    private func palette(_ hexes: [String]) -> some View {
        HStack(spacing: 4) {
            ForEach(hexes, id: \.self) { hex in
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(hex.uppercased(), forType: .string)
                    model.showToast("Copied \(hex.uppercased())")
                } label: {
                    RoundedRectangle(cornerRadius: Ink.tileRadius, style: .continuous).fill(Color(hex: hex)).frame(width: 22, height: 22)
                        .overlay(RoundedRectangle(cornerRadius: Ink.tileRadius, style: .continuous).strokeBorder(Ink.hairline, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .help(hex.uppercased())
            }
        }
    }

    private func tags(_ info: ItemInfo) -> some View {
        section("Tags") {
            FlowLayout(spacing: 4) {
                ForEach(info.tags, id: \.name) { t in
                    TagToken(label: t.name, automatic: t.automatic) { model.showTag(t.name) }
                        .contextMenu { Button("Remove Tag") { removeTag(t.name) } }
                }
                TextField("Add tag", text: $newTag)
                    .textFieldStyle(.plain)
                    .font(.grailsBody(12))
                    .frame(width: 70)
                    .focused($focus, equals: .tag)
                    .onSubmit { addTag() }
            }
        }
    }

    @ViewBuilder private func collections(_ info: ItemInfo) -> some View {
        section("Collections") {
            FlowLayout(spacing: 4) {
                ForEach(info.collections, id: \.id) { c in
                    LinkChip(label: c.name) { model.showCollection(c.id) } content: { Text(c.name) }
                }
                Button {
                    if let id = itemID { model.selection = [id]; model.panel = .move }
                } label: {
                    Image(systemName: "plus").font(.system(size: 10, weight: .medium)).foregroundStyle(Ink.secondary)
                        .frame(width: 22, height: 22).chipSurface()
                }
                .buttonStyle(.plain)
                .help("Move to collection (M)")
            }
        }
    }

    private var noteField: some View {
        section("Note") {
            TextField("Note", text: $note, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.grailsBody(13))
                .lineLimit(1...8)
                .focused($focus, equals: .note)
                .onChange(of: focus) { old, new in if old == .note, new != .note { commitNote() } }
        }
    }

    private func camera(_ rows: [(label: String, value: String)]) -> some View {
        section("Camera") {
            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 3) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, r in
                    GridRow { Text(r.label).foregroundStyle(Ink.secondary); Text(r.value).monospacedDigit() }
                }
            }
            .font(.grailsBody(12))
        }
    }

    private func section(_ title: String, @ViewBuilder _ body: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.grailsBody(11)).foregroundStyle(Ink.secondary)
            body()
        }
    }

    // MARK: Edits (one undo step each)

    private func commitName(_ item: Item) {
        let t = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, t != item.name else { name = item.name; return }
        Task { await model.perform("Rename") { try await $0.rename(id: item.id, to: t) } }
    }

    private func commitNote() {
        guard let item, note != item.note else { return }
        let text = note
        Task { await model.perform("Edit Note") { try await $0.setNote(text, ids: [item.id]) } }
    }

    private func addTag() {
        let t = newTag.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        newTag = ""
        guard let id = itemID, !t.isEmpty else { return }
        Task { await model.perform("Add Tag") { try await $0.addTags([t], to: [id]) } }
        focus = .tag
    }

    private func removeTag(_ tag: String) {
        guard let id = itemID else { return }
        Task { await model.perform("Remove Tag") { try await $0.removeTags([tag], from: [id]) } }
    }
}

/// A tag you can click to see everything with it. Your own tags are filled; the machine's are outlined.
struct TagToken: View {
    let label: String
    let automatic: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.grailsBody(12))
                .foregroundStyle(automatic && !hovering ? Ink.secondary : Ink.text)
                .padding(.horizontal, 8).frame(height: 22)
                .background {
                    let shape = RoundedRectangle(cornerRadius: Ink.chipRadius, style: .continuous)
                    if automatic { shape.strokeBorder(hovering ? Ink.secondary : Ink.hairline, lineWidth: 1) }
                    else { shape.fill(hovering ? Ink.fillHover : Ink.fill) }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hoverState($hovering)
        .accessibilityLabel(automatic ? "\(label), automatic" : label)
    }
}

/// A chip that takes you somewhere (a collection). Brightens under the pointer.
struct LinkChip<Content: View>: View {
    let label: String
    let action: () -> Void
    @ViewBuilder var content: () -> Content
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            content()
                .font(.grailsBody(12))
                .foregroundStyle(hovering ? Ink.text : Ink.secondary)
                .padding(.horizontal, 8).frame(height: 22)
                .chipSurface(selected: hovering)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hoverState($hovering)
        .accessibilityLabel(label)
    }
}

/// A person's name that opens everything they added.
struct PersonLink: View {
    let name: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) { Text(name).underline(hovering).foregroundStyle(Ink.link) }
            .buttonStyle(.plain)
            .hoverState($hovering)
    }
}
