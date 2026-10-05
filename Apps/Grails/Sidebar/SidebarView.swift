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
    @State private var archivedOpen = false
    @State private var targeted: String?

    private var topLevel: [GrailsCollection] { model.collections.filter { $0.parentId == nil && !$0.archived } }
    private var archived: [GrailsCollection] { model.collections.filter { $0.archived } }

    /// One row style for every state: hover is a light fill, the open view a stronger one, same shape and inset.
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 1) {
                WorkspaceSwitcher(model: model).padding(.horizontal, 8).padding(.bottom, 6)

                SidebarRow(model: model, title: "Inbox", symbol: "tray", source: .inbox)
                SidebarRow(model: model, title: "All", symbol: "square.grid.2x2", count: model.totalCount, source: .all)
                SidebarRow(model: model, title: "Liked", symbol: "heart", source: .liked)
                SidebarRow(model: model, title: "Untagged", symbol: "tag.slash", source: .untagged)
                SidebarRow(model: model, title: "Trash", symbol: "trash", source: .trash)
                    .dropTarget(model: model, id: "trash", targeted: $targeted, target: .trash)
                    .contextMenu {
                        Button("Empty Trash…") { model.confirmEmptyTrash() }
                        if model.source == .trash { Button("Restore Selected") { model.restoreSelection() } }
                    }

                if showCollections {
                    SidebarHeader(title: "Collections", expanded: $expandCollections) {
                        Menu {
                            Button("New Collection…") { model.promptNewCollection(kind: "collection", parent: nil) }
                            Button("New Folder…") { model.promptNewCollection(kind: "folder", parent: nil) }
                            Button("New Smart Folder…") { model.run(.newSmartFolder) }
                        } label: { BarIcon(symbol: "plus", size: 22) }
                            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                            .accessibilityIdentifier("sidebar-add")
                    }
                    if expandCollections {
                        ForEach(topLevel) { CollectionNode(model: model, collection: $0, depth: 0, targeted: $targeted) }
                        if !archived.isEmpty {
                            SidebarRow(model: model, title: "Archived", symbol: "archivebox", disclosure: $archivedOpen)
                            if archivedOpen {
                                ForEach(archived) { c in
                                    SidebarRow(model: model, title: c.name, symbol: "archivebox", source: .collection(c.id), indent: 1)
                                        .contextMenu { Button("Unarchive") { model.archiveCollection(c, false) } }
                                }
                            }
                        }
                    }
                }

                if showSmart && !model.smartFolders.isEmpty {
                    SidebarHeader(title: "Smart Folders", expanded: $expandSmart) { EmptyView() }
                    if expandSmart {
                        ForEach(model.smartFolders) { f in
                            SidebarRow(model: model, title: f.name, symbol: "gearshape.2", source: .smart(f.id))
                                .contextMenu {
                                    Button("Edit…") { model.editSmartFolder(f) }
                                    Divider()
                                    Button("Delete", role: .destructive) { model.deleteSmartFolder(f) }
                                }
                        }
                    }
                }

                if showTags {
                    SidebarHeader(title: "Tags", expanded: $expandTags, count: model.tags.isEmpty ? nil : model.tags.count, toggleID: "sidebar-tags-toggle") {
                        Menu {
                            Button("Merge Similar Tags") { model.mergeSimilarTags() }
                        } label: { BarIcon(symbol: "ellipsis", size: 22) }
                            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                            .accessibilityIdentifier("sidebar-tags-menu")
                    }
                    if expandTags {
                        ForEach(showAllTags ? model.tags : Array(model.tags.prefix(14)), id: \.tag) { t in
                            SidebarRow(model: model, title: t.tag, symbol: model.tagColors[t.tag.lowercased()] == nil ? "number" : "circle.fill",
                                       tint: model.tagColor(t.tag), count: t.count, source: .tag(t.tag))
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
                            SidebarRow(model: model, title: showAllTags ? "Show fewer" : "Show all \(model.tags.count)", symbol: showAllTags ? "chevron.up" : "chevron.down", quiet: true) {
                                showAllTags.toggle()
                            }
                        }
                    }
                }
            }
            .padding(.vertical, 8)
        }
        .scrollIndicators(.never)
        .accessibilityIdentifier("sidebar")
    }
}

/// A section title you can fold away; the count shows while it is folded.
struct SidebarHeader<Trailing: View>: View {
    let title: String
    @Binding var expanded: Bool
    var count: Int?
    var toggleID: String?
    @ViewBuilder var trailing: () -> Trailing
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 4) {
            Button { expanded.toggle() } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.right").font(.system(size: 8, weight: .bold)).rotationEffect(.degrees(expanded ? 90 : 0)).frame(width: 10)
                    Text(title)
                    if !expanded, let count { Text("\(count)").monospacedDigit() }
                }
                .font(.system(size: 11))
                .foregroundStyle(hovering ? Ink.text : Ink.secondary)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .hoverState($hovering)
            .modifier(OptionalID(id: toggleID))
            Spacer()
            trailing()
        }
        .padding(.leading, 16).padding(.trailing, 12)
        .frame(height: 26)
        .padding(.top, 10)
    }
}

private struct OptionalID: ViewModifier {
    let id: String?
    func body(content: Content) -> some View { if let id { content.accessibilityIdentifier(id) } else { content } }
}

/// One line in the sidebar. Hover, the open view and a drop all use the same shape and inset.
struct SidebarRow: View {
    var model: AppModel
    let title: String
    let symbol: String
    var tint: Color?
    var count: Int?
    /// What clicking opens; nil for rows that only expand or run an action.
    var source: Source?
    var indent = 0
    var disclosure: Binding<Bool>?
    var quiet = false
    var action: (() -> Void)?
    @State private var hovering = false

    private var selected: Bool { source != nil && model.source == source }

    var body: some View {
        HStack(spacing: 8) {
            if let disclosure {
                Button { disclosure.wrappedValue.toggle() } label: {
                    Image(systemName: "chevron.right").font(.system(size: 8, weight: .bold)).foregroundStyle(Ink.secondary)
                        .rotationEffect(.degrees(disclosure.wrappedValue ? 90 : 0)).frame(width: 12, height: 20).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            } else if indent > 0 { Color.clear.frame(width: 12) }
            Image(systemName: symbol).font(.system(size: 12)).foregroundStyle(tint ?? (selected || hovering ? Ink.text : Ink.secondary)).frame(width: 16)
            Text(title).font(.system(size: 13, weight: selected ? .medium : .regular)).foregroundStyle(quiet && !hovering ? Ink.secondary : Ink.text).lineLimit(1)
            Spacer(minLength: 4)
            if let count { Text(count.formatted()).font(.system(size: 11)).monospacedDigit().foregroundStyle(Ink.secondary) }
        }
        .padding(.leading, 8 + CGFloat(indent) * 14).padding(.trailing, 8)
        .frame(height: 28)
        .background(RoundedRectangle(cornerRadius: Ink.radius, style: .continuous).fill(selected ? Ink.fillHover : (hovering ? Ink.fill : .clear)))
        .padding(.horizontal, 8)
        .contentShape(Rectangle())
        .onTapGesture {
            if let action { action() } else if let source { model.source = source } else { disclosure?.wrappedValue.toggle() }
        }
        .hoverState($hovering)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }
}

enum TagPalette {
    static let colors: [(name: String, hex: String)] = [
        ("Red", "#E5484D"), ("Orange", "#F76B15"), ("Yellow", "#E5B800"), ("Green", "#30A46C"),
        ("Teal", "#12A594"), ("Blue", "#3E63DD"), ("Purple", "#8E4EC6"), ("Pink", "#D6409F"), ("Grey", "#8B8D98"),
    ]
}

/// One collection in the sidebar; folders recurse into their children.
private struct CollectionNode: View {
    var model: AppModel
    let collection: GrailsCollection
    var depth: Int
    @Binding var targeted: String?
    @State private var open = true

    var body: some View {
        let children = model.collections.filter { $0.parentId == collection.id && !$0.archived }
        let hasChildren = collection.kind == "folder" || !children.isEmpty
        label(hasChildren: hasChildren)
        if hasChildren, open {
            ForEach(children) { CollectionNode(model: model, collection: $0, depth: depth + 1, targeted: $targeted) }
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

    private func label(hasChildren: Bool) -> some View {
        SidebarRow(model: model, title: collection.name, symbol: collection.kind == "folder" ? "folder" : "rectangle.stack",
                   source: .collection(collection.id), indent: depth, disclosure: hasChildren ? $open : nil)
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
        .overlay { if targeted.wrappedValue == id { RoundedRectangle(cornerRadius: Ink.radius, style: .continuous).strokeBorder(Ink.focus, lineWidth: 1.5).padding(.horizontal, 8).allowsHitTesting(false) } }
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
        .overlay { if targeted.wrappedValue == id { RoundedRectangle(cornerRadius: Ink.radius, style: .continuous).strokeBorder(Ink.focus, lineWidth: 1.5).padding(.horizontal, 8).allowsHitTesting(false) } }
    }
}

