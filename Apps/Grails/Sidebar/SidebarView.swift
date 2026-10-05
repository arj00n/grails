import GrailsKit
import SwiftUI
import UniformTypeIdentifiers

struct SidebarView: View {
    @Bindable var model: AppModel
    @AppStorage("sidebar.showCollections") private var showCollections = true
    @AppStorage("sidebar.showSmart") private var showSmart = true
    @AppStorage("sidebar.showTags") private var showTags = true
    @AppStorage("sidebar.expandCollections") private var expandCollections = true
    @AppStorage("sidebar.expandSmart") private var expandSmart = true
    @AppStorage("sidebar.expandTags") private var expandTags = true
    @State private var showAllTags = false
    @State private var targeted: String?

    private var topLevel: [GrailsCollection] { model.collections.filter { $0.parentId == nil && !$0.archived } }
    private var archived: [GrailsCollection] { model.collections.filter { $0.archived } }

    var body: some View {
        List(selection: Binding(get: { model.source }, set: { model.source = $0 ?? .all })) {
            Section { WorkspaceSwitcher(model: model) }
            Section {
                SidebarRow(title: "Inbox", symbol: "tray").tag(Source.inbox)
                SidebarRow(title: "All", symbol: "square.grid.2x2", count: model.totalCount).tag(Source.all)
                SidebarRow(title: "Liked", symbol: "heart").tag(Source.liked)
                SidebarRow(title: "Untagged", symbol: "tag.slash").tag(Source.untagged)
                SidebarRow(title: "Trash", symbol: "trash")
                    .tag(Source.trash)
                    .dropTarget(model: model, id: "trash", targeted: $targeted, target: .trash)
                    .contextMenu {
                        Button("Empty Trash…") { model.confirmEmptyTrash() }
                        if model.source == .trash { Button("Restore Selected") { model.restoreSelection() } }
                    }
            }

            if showCollections {
                Section(isExpanded: $expandCollections) {
                    if topLevel.isEmpty { Text("No collections yet").foregroundStyle(Ink.tertiary).font(.callout).listRowSeparator(.hidden) }
                    ForEach(topLevel) { CollectionNode(model: model, collection: $0, targeted: $targeted) }
                    if !archived.isEmpty {
                        DisclosureGroup("Archived") {
                            ForEach(archived) { c in
                                SidebarRow(title: c.name, symbol: "archivebox").tag(Source.collection(c.id))
                                    .contextMenu { Button("Unarchive") { model.archiveCollection(c, false) } }
                            }
                        }
                    }
                } header: {
                    HStack {
                        Text("Collections")
                        Spacer()
                        Menu {
                            Button("New Collection…") { model.promptNewCollection(kind: "collection", parent: nil) }
                            Button("New Folder…") { model.promptNewCollection(kind: "folder", parent: nil) }
                            Button("New Smart Folder…") { model.run(.newSmartFolder) }
                        } label: { Image(systemName: "plus") }
                            .menuStyle(.borderlessButton).menuIndicator(.hidden).frame(width: 22)
                            .accessibilityIdentifier("sidebar-add")
                    }
                }
            }

            if showSmart && !model.smartFolders.isEmpty {
                Section("Smart Folders", isExpanded: $expandSmart) {
                    ForEach(model.smartFolders) { f in
                        SidebarRow(title: f.name, symbol: "gearshape.2").tag(Source.smart(f.id))
                            .contextMenu {
                                Button("Edit…") { model.editSmartFolder(f) }
                                Divider()
                                Button("Delete", role: .destructive) { model.deleteSmartFolder(f) }
                            }
                    }
                }
            }

            if showTags {
                Section(isExpanded: $expandTags) {
                    if model.tags.isEmpty { Text("No tags yet").foregroundStyle(Ink.tertiary).font(.callout).listRowSeparator(.hidden) }
                    ForEach(showAllTags ? model.tags : Array(model.tags.prefix(14)), id: \.tag) { t in
                        SidebarRow(title: t.tag, symbol: model.tagColors[t.tag.lowercased()] == nil ? "number" : "circle.fill",
                                   tint: model.tagColor(t.tag), count: t.count)
                            .tag(Source.tag(t.tag))
                            .dropTarget(model: model, id: "tag-\(t.tag)", targeted: $targeted, target: .tag(t.tag))
                            .contextMenu {
                                Button("Copy Link") { model.copyLink(.tag(t.tag)) }
                                Button("Rename…") { model.promptRenameTag(t.tag) }
                                Menu("Color") {
                                    ForEach(TagPalette.colors, id: \.name) { c in
                                        Button(c.name) { model.setTagColor(c.hex, for: t.tag) }
                                    }
                                    Divider()
                                    Button("None") { model.setTagColor(nil, for: t.tag) }
                                }
                                Divider()
                                Button("Delete Tag…", role: .destructive) { model.confirmDeleteTag(t.tag) }
                            }
                    }
                    if model.tags.count > 14 {
                        Button(showAllTags ? "Show fewer" : "Show all \(model.tags.count)") { showAllTags.toggle() }
                            .buttonStyle(.plain).font(.callout).foregroundStyle(Ink.secondary)
                            .listRowSeparator(.hidden)
                    }
                } header: {
                    HStack(spacing: 6) {
                        Button { withAnimation(.smooth(duration: 0.2)) { expandTags.toggle() } } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "chevron.right").font(.system(size: 9, weight: .bold))
                                    .rotationEffect(.degrees(expandTags ? 90 : 0)).frame(width: 10)
                                Text("Tags")
                                if !expandTags, !model.tags.isEmpty { Text("\(model.tags.count)").foregroundStyle(Ink.tertiary) }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("sidebar-tags-toggle")
                        Spacer()
                        Menu {
                            Button("Merge Similar Tags") { model.mergeSimilarTags() }
                        } label: { Image(systemName: "ellipsis") }
                            .menuStyle(.borderlessButton).menuIndicator(.hidden).frame(width: 22)
                            .accessibilityIdentifier("sidebar-tags-menu")
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .listRowSeparator(.hidden)
        .listSectionSeparator(.hidden)
        .environment(\.defaultMinListRowHeight, 30)
        .accessibilityIdentifier("sidebar")
    }
}

enum TagPalette {
    static let colors: [(name: String, hex: String)] = [
        ("Red", "#E5484D"), ("Orange", "#F76B15"), ("Yellow", "#E5B800"), ("Green", "#30A46C"),
        ("Teal", "#12A594"), ("Blue", "#3E63DD"), ("Purple", "#8E4EC6"), ("Pink", "#D6409F"), ("Grey", "#8B8D98"),
    ]
}

struct SidebarRow: View {
    let title: String
    let symbol: String
    var tint: Color?
    var count: Int?
    @State private var hovering = false
    @State private var bump = 0

    var body: some View {
        Label {
            HStack {
                Text(title).lineLimit(1).foregroundStyle(Ink.text)
                Spacer()
                if let count { Text(count.formatted()).foregroundStyle(hovering ? Ink.secondary : Ink.tertiary).font(.caption).monospacedDigit() }
            }
        } icon: {
            Image(systemName: symbol).foregroundStyle(tint ?? (hovering ? Ink.text : Ink.secondary))
                .symbolEffect(.bounce, options: .speed(1.4), value: bump)
        }
        .padding(.vertical, 2)
        .background(RoundedRectangle(cornerRadius: Ink.radius, style: .continuous).fill(hovering ? Ink.fill : .clear).padding(.horizontal, -6))
        .onHover { h in hovering = h; if h { bump += 1 } }
        .animation(.easeOut(duration: 0.12), value: hovering)
        .listRowSeparator(.hidden)
    }
}

/// One collection in the sidebar; folders recurse into their children.
private struct CollectionNode: View {
    var model: AppModel
    let collection: GrailsCollection
    @Binding var targeted: String?

    var body: some View {
        let children = model.collections.filter { $0.parentId == collection.id && !$0.archived }
        if collection.kind == "folder" || !children.isEmpty {
            DisclosureGroup {
                ForEach(children) { CollectionNode(model: model, collection: $0, targeted: $targeted) }
            } label: { label }
        } else {
            label
        }
    }

    @ViewBuilder private var libraryTransferMenu: some View {
        Menu("Move to Library") {
            ForEach(model.workspaces.filter { $0.path != model.layout?.root.path && $0.exists }) { lib in
                Button(lib.name) { model.confirmMoveCollection(collection, to: lib) }
            }
            Button("Choose…") { model.chooseLibrary { url in model.confirmMoveCollection(collection, to: Workspace(path: url.path, name: url.deletingPathExtension().lastPathComponent)) } }
        }
        Menu("Copy to Library") {
            ForEach(model.workspaces.filter { $0.path != model.layout?.root.path && $0.exists }) { lib in
                Button(lib.name) { model.transferCollection(collection, to: URL(fileURLWithPath: lib.path), move: false) }
            }
            Button("Choose…") { model.chooseLibrary { model.transferCollection(collection, to: $0, move: false) } }
        }
        Divider()
    }

    private var label: some View {
        SidebarRow(title: collection.name, symbol: collection.kind == "folder" ? "folder" : "rectangle.stack")
            .tag(Source.collection(collection.id))
            .onDrag {
                NSItemProvider(item: Data(collection.id.utf8) as NSData, typeIdentifier: UTType.grailsCollection.identifier)
            }
            .collectionDropTarget(model: model, collection: collection, targeted: $targeted)
            .contextMenu {
                libraryTransferMenu
                Button("Copy Link") { model.copyLink(.collection(collection.id)) }
                Button("Rename…") { model.promptRenameCollection(collection) }
                if collection.kind == "folder" {
                    Button("New Collection Inside…") { model.promptNewCollection(kind: "collection", parent: collection.id) }
                    Button("New Folder Inside…") { model.promptNewCollection(kind: "folder", parent: collection.id) }
                }
                Button("Duplicate") { model.duplicateCollection(collection) }
                if collection.kind != "folder" { Button("Use Selected Item as Cover") { model.setCoverFromSelection(collection) } }
                Divider()
                Button("Archive") { model.archiveCollection(collection, true) }
                Button("Delete…", role: .destructive) { model.confirmDeleteCollection(collection) }
            }
    }
}

extension View {
    /// Accepts items (add), files (import) onto a tag or the Trash row.
    func dropTarget(model: AppModel, id: String, targeted: Binding<String?>, target: AppModel.DropTarget) -> some View {
        onDrop(of: DropLoader.accepted, isTargeted: Binding(get: { targeted.wrappedValue == id }, set: { targeted.wrappedValue = $0 ? id : nil })) { providers in
            Task { @MainActor in
                let d = await DropLoader.load(providers)
                if !d.itemIDs.isEmpty { model.dropItems(ids: d.itemIDs, onto: target) }
                else if !d.files.isEmpty, case .tag(let t) = target { await model.importFiles(d.files, tag: t) }
            }
            return true
        }
        .listRowBackground(targeted.wrappedValue == id ? Ink.fillHover : nil)
    }

    /// Collections accept items (add), files (import), and other collections (reorder / move into a folder).
    func collectionDropTarget(model: AppModel, collection: GrailsCollection, targeted: Binding<String?>) -> some View {
        let id = "c-\(collection.id)"
        return onDrop(of: DropLoader.accepted, isTargeted: Binding(get: { targeted.wrappedValue == id }, set: { targeted.wrappedValue = $0 ? id : nil })) { providers in
            Task { @MainActor in
                let d = await DropLoader.load(providers)
                if !d.itemIDs.isEmpty {
                    if collection.kind != "folder" { model.dropItems(ids: d.itemIDs, onto: .collection(collection.id)) }
                } else if let moved = d.collectionIDs.first, moved != collection.id {
                    if collection.kind == "folder" { model.moveCollection(moved, intoFolder: collection.id) }
                    else if let c = model.collections.first(where: { $0.id == moved }) { _ = c; model.moveCollection(moved, after: collection) }
                } else if !d.files.isEmpty, collection.kind != "folder" {
                    await model.importFiles(d.files, collectionId: collection.id)
                }
            }
            return true
        }
        .listRowBackground(targeted.wrappedValue == id ? Ink.fillHover : nil)
    }
}

