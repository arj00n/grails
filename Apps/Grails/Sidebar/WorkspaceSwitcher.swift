import GrailsKit
import SwiftUI

/// A workspace's tile: its colour and first letter.
struct WorkspaceAvatar: View {
    var name: String
    var hex: String?
    var size: CGFloat = 22

    var body: some View {
        RoundedRectangle(cornerRadius: Ink.tileRadius, style: .continuous)
            .fill(hex.map { Color(hex: $0) } ?? Ink.fillHover)
            .frame(width: size, height: size)
            .overlay(Text(String(name.trimmingCharacters(in: .whitespaces).prefix(1)).uppercased())
                .font(.system(size: size * 0.5, weight: .semibold)).foregroundStyle(hex == nil ? Ink.text : Color.white))
    }
}

/// Top of the sidebar: the current workspace, and a list to switch to another, add one, or invite someone.
struct WorkspaceSwitcher: View {
    var model: AppModel
    @State private var open = false
    @State private var hovering = false

    private var current: Workspace? { model.workspaces.first { $0.id == model.libraryID } }

    var body: some View {
        Button { open.toggle() } label: {
            HStack(spacing: 8) {
                WorkspaceAvatar(name: model.libraryName, hex: current?.color)
                Text(model.libraryName).fontWeight(.semibold).lineLimit(1).foregroundStyle(Ink.text)
                Spacer()
                Image(systemName: "chevron.up.chevron.down").font(.caption2).foregroundStyle(.secondary)
            }
            .padding(6)
            .background(RoundedRectangle(cornerRadius: Ink.radius, style: .continuous).fill(hovering || open ? Ink.fill : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hoverState($hovering)
        .popover(isPresented: $open, arrowEdge: .bottom) { WorkspaceList(model: model) { open = false } }
        .accessibilityIdentifier("library-switcher")
    }
}

private struct WorkspaceList: View {
    var model: AppModel
    var dismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(model.workspaces.enumerated()), id: \.element.id) { index, w in
                row(w, index: index)
            }
            if model.workspaces.isEmpty { Text("No workspaces yet").foregroundStyle(Ink.tertiary).padding(8) }
            Divider().padding(.vertical, 4)
            action("Copy Invite Link", "link") { model.copyInviteLink() }
            Menu {
                Button("Open Folder…") { LibraryPicker.openExisting(model) }
                Button("New Workspace…") { LibraryPicker.createNew(model) }
                Button("Join with Link…") { model.promptJoinWithLink() }
            } label: {
                Label("Add Workspace", systemImage: "plus").frame(maxWidth: .infinity, alignment: .leading)
            }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).padding(.horizontal, 8).padding(.vertical, 5)
            action("Refresh", "arrow.clockwise") { Task { await model.refreshLibrary() } }
            action("Show in Finder", "folder") { if let u = model.layout?.root { NSWorkspace.shared.activateFileViewerSelecting([u]) } }
        }
        .padding(8)
        .frame(width: 270)
    }

    private func row(_ w: Workspace, index: Int) -> some View {
        let isCurrent = w.id == model.libraryID
        return Button {
            dismiss()
            model.switchWorkspace(w)
        } label: {
            HStack(spacing: 10) {
                WorkspaceAvatar(name: w.name, hex: w.color, size: 26)
                Text(w.name).lineLimit(1).foregroundStyle(w.exists ? Ink.text : Ink.tertiary)
                Spacer()
                if isCurrent { Image(systemName: "checkmark").foregroundStyle(Ink.secondary) }
                else if !w.exists { Text("Locate").foregroundStyle(Ink.secondary) }
                else if index < 9 { Text("⌃\(index + 1)").font(.caption).foregroundStyle(Ink.tertiary) }
            }
            .padding(.horizontal, 8).padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(HoverRowStyle())
        .contextMenu {
            Menu("Color") {
                ForEach(TagPalette.colors, id: \.name) { c in Button(c.name) { model.setWorkspaceColor(c.hex, for: w) } }
                Divider()
                Button("None") { model.setWorkspaceColor(nil, for: w) }
            }
            if w.exists { Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([w.url]) } }
            if !isCurrent { Button("Remove from List", role: .destructive) { model.removeWorkspace(w) } }
        }
    }

    private func action(_ title: String, _ symbol: String, _ run: @escaping () -> Void) -> some View {
        Button { dismiss(); run() } label: {
            Label(title, systemImage: symbol).frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8).padding(.vertical, 5).contentShape(Rectangle())
        }
        .buttonStyle(HoverRowStyle())
    }
}

private struct HoverRowStyle: ButtonStyle {
    @State private var hovering = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(RoundedRectangle(cornerRadius: Ink.radius, style: .continuous).fill(configuration.isPressed ? Ink.fillHover : (hovering ? Ink.fill : .clear)))
            .hoverState($hovering)
    }
}
