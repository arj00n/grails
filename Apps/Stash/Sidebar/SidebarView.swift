import StashKit
import SwiftUI

struct SidebarView: View {
    @Bindable var model: AppModel
    @AppStorage("sidebar.showCollections") private var showCollections = true
    @AppStorage("sidebar.showTags") private var showTags = true

    var body: some View {
        List(selection: Binding(get: { model.source }, set: { model.source = $0 ?? .all })) {
            Section {
                row("Inbox", "tray", .inbox)
                row("All", "square.grid.2x2", .all, count: model.totalCount)
                row("Liked", "heart", .liked)
                row("Untagged", "tag.slash", .untagged)
                row("Trash", "trash", .trash)
            }
            if showCollections {
                Section("Collections") {
                    if model.collections.isEmpty {
                        Text("No collections yet").foregroundStyle(.secondary).font(.callout)
                    }
                    ForEach(model.collections.filter { $0.parentId == nil && !$0.archived }) { c in
                        CollectionNode(model: model, collection: c)
                    }
                }
            }
            if showTags {
                Section("Tags") {
                    if model.tags.isEmpty {
                        Text("No tags yet").foregroundStyle(.secondary).font(.callout)
                    }
                    ForEach(model.tags, id: \.tag) { t in
                        row(t.tag, "number", .tag(t.tag), count: t.count)
                    }
                }
            }
        }
        .navigationSplitViewColumnWidth(min: 180, ideal: 230, max: 340)
        .accessibilityIdentifier("sidebar")
    }

    fileprivate func row(_ title: String, _ symbol: String, _ source: Source, count: Int? = nil) -> some View {
        Label {
            HStack {
                Text(title)
                Spacer()
                if let count { Text(count.formatted()).foregroundStyle(.secondary).font(.caption).monospacedDigit() }
            }
        } icon: { Image(systemName: symbol) }
        .tag(source)
    }
}

/// One collection in the sidebar; folders recurse into their children.
private struct CollectionNode: View {
    var model: AppModel
    let collection: StashCollection

    var body: some View {
        let children = model.collections.filter { $0.parentId == collection.id && !$0.archived }
        if children.isEmpty {
            label
        } else {
            DisclosureGroup {
                ForEach(children) { CollectionNode(model: model, collection: $0) }
            } label: { label }
        }
    }

    private var label: some View {
        Label(collection.name, systemImage: collection.kind == "folder" ? "folder" : "rectangle.stack")
            .tag(Source.collection(collection.id))
    }
}
