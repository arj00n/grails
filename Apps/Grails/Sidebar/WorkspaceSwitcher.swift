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
                .font(.grailsDisplay(size * 0.5)).foregroundStyle(hex == nil ? Ink.text : Color.white))
    }
}

/// Top of the sidebar: the current workspace. Its menu (`WorkspaceMenu`) is drawn by the window, in our own style.
struct WorkspaceSwitcher: View {
    var model: AppModel
    @State private var hovering = false

    private var current: Workspace? { model.workspaces.first { $0.id == model.libraryID } }
    static let height: CGFloat = 36

    var body: some View {
        Button { model.workspaceMenuOpen.toggle() } label: {
            HStack(spacing: 8) {
                WorkspaceAvatar(name: model.libraryName, hex: current?.color)
                Text(model.libraryName).font(.grailsDisplay(16)).lineLimit(1).foregroundStyle(Ink.text)
                Spacer(minLength: 4)
                Image(systemName: "chevron.up.chevron.down").font(.system(size: 9)).foregroundStyle(Ink.secondary)
            }
            .padding(.horizontal, 8)
            .frame(height: Self.height)
            .background(RoundedRectangle(cornerRadius: Ink.radius, style: .continuous).fill(model.workspaceMenuOpen ? Ink.fillHover : (hovering ? Ink.fill : .clear)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hoverState($hovering)
        .padding(.horizontal, 8)
        .accessibilityIdentifier("library-switcher")
    }
}

/// The workspace menu: workspaces to switch to, ways to add one, and a few library actions. One row style throughout.
struct WorkspaceMenu: View {
    var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            ForEach(Array(model.workspaces.enumerated()), id: \.element.id) { index, w in workspaceRow(w, index: index) }
            if model.workspaces.isEmpty { Text("No workspaces").font(.grailsBody(13)).foregroundStyle(Ink.secondary).padding(.horizontal, 10).frame(height: 28) }
            rule
            action("Open Folder…", "folder") { LibraryPicker.openExisting(model) }
            action("New Workspace…", "plus") { LibraryPicker.createNew(model) }
            action("Join with Link…", "link") { model.promptJoinWithLink() }
            rule
            action("Invite…", "person.badge.plus") { model.collab.presentInvite() }
            action("Team Setup…", "person.2") { model.collab.presentSetup() }
            action("Copy Invite Link", "doc.on.doc") { model.copyInviteLink() }
            action("Refresh", "arrow.clockwise") { Task { await model.refreshLibrary() } }
            action("Show in Finder", "magnifyingglass") { if let u = model.layout?.root { NSWorkspace.shared.activateFileViewerSelecting([u]) } }
            Button("") { model.workspaceMenuOpen = false }.keyboardShortcut(.cancelAction).frame(width: 0, height: 0).opacity(0)
        }
        .padding(4)
        .surfaceCard()
        .accessibilityIdentifier("workspace-menu")
    }

    private var rule: some View { Rectangle().fill(Ink.hairline).frame(height: 1).padding(.vertical, 3).padding(.horizontal, 4) }

    private func workspaceRow(_ w: Workspace, index: Int) -> some View {
        let isCurrent = w.id == model.libraryID
        return MenuRow(selected: isCurrent) {
            model.workspaceMenuOpen = false
            model.switchWorkspace(w)
        } content: {
            WorkspaceAvatar(name: w.name, hex: w.color, size: 20)
            Text(w.name).font(.grailsBody(13)).foregroundStyle(w.exists ? Ink.text : Ink.secondary).lineLimit(1)
            Spacer(minLength: 4)
            if !w.exists { Text("Locate").font(.grailsBody(11)).foregroundStyle(Ink.secondary) }
            else if !isCurrent, index < 9 { Text("⌃\(index + 1)").font(.grailsBody(11)).foregroundStyle(Ink.secondary) }
        }
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
        MenuRow(selected: false) {
            model.workspaceMenuOpen = false
            run()
        } content: {
            Image(systemName: symbol).font(.system(size: 12)).foregroundStyle(Ink.secondary).frame(width: 20)
            Text(title).font(.grailsBody(13)).foregroundStyle(Ink.text)
            Spacer(minLength: 4)
        }
    }
}

/// A row in one of our menus: same height, inset and states as a sidebar row.
struct MenuRow<Content: View>: View {
    var selected: Bool
    let action: () -> Void
    @ViewBuilder var content: () -> Content
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 8, content: content)
            .padding(.horizontal, 6)
            .frame(height: 28)
            .background(RoundedRectangle(cornerRadius: Ink.radius, style: .continuous).fill(selected ? Ink.fillHover : (hovering ? Ink.fill : .clear)))
            .contentShape(Rectangle())
            .onTapGesture(perform: action)
            .hoverState($hovering)
            .accessibilityAddTraits(.isButton)
    }
}
