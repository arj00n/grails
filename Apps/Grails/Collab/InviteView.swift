import AppKit
import GrailsDesign
import GrailsKit
import SwiftUI

/// Invite, any time (Settings ▸ Library, the sidebar menu): the checklist of people, who has joined, the link and the ways to send it.
struct InviteView: View {
    var model: AppModel
    var onClose: () -> Void = {}

    private var c: CollabModel { model.collab }
    static let size = CGSize(width: 560, height: 540)

    var body: some View {
        let roster = c.roster
        let placement = c.currentPlacement
        VStack(alignment: .leading, spacing: 16) {
            CollabHeader(title: "Invite", close: onClose)
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(model.libraryName).font(.grailsBody(15, bold: true)).foregroundStyle(Ink.text).lineLimit(1)
                    Text("\(placement?.label ?? "") · \(roster.joinedCount) of \(roster.rows.count) joined")
                        .font(.grailsBody(12)).foregroundStyle(Ink.secondary).lineLimit(1)
                }
                Spacer()
                if placement?.service == .googleDrive { QuietButton(title: "Open Drive", identifier: "invite-open-drive") { c.openShare() } }
            }
            if let p = placement, !LibraryHintCheck.reachable(p) {
                IssueLine(issue: p.inTrash ? .trash : .local)
            }
            Rectangle().fill(Ink.hairline).frame(height: 1)
            AddTeammateField(c: c)
            TeammateList(c: c, maxRows: 6)
            if !roster.others.isEmpty { OthersList(c: c, others: roster.others) }
            Spacer(minLength: 0)
            Text("Joined means they opened the library or added to it. Grails can't see who Drive shares it with.")
                .font(.grailsBody(11)).foregroundStyle(Ink.secondary).fixedSize(horizontal: false, vertical: true)
            InviteActions(c: c, onFinished: onClose) { QuietButton(title: "Copy link", identifier: "invite-copy-link") { c.copyLink() } }
            Button("") { onClose() }.keyboardShortcut(.cancelAction).frame(width: 0, height: 0).opacity(0)
        }
        .padding(24)
        .frame(width: Self.size.width, height: Self.size.height, alignment: .topLeading)
        .task {
            c.loadInvites()
            // who has turned up: now, and every 10 s while this is open (teammates' saves arrive by sync)
            while !Task.isCancelled {
                await c.refreshSeen()
                try? await Task.sleep(for: .seconds(10))
            }
        }
        .onChange(of: model.contributors.count) { Task { await c.refreshSeen() } }
        .accessibilityIdentifier("invite-view")
    }
}

enum LibraryHintCheck {
    /// Can a teammate get to this place at all?
    static func reachable(_ p: Placement) -> Bool { p.isSynced && !p.inTrash && p.kind != .driveTop }
}

/// The field where people are added: emails or names, comma-separated, Return to add.
struct AddTeammateField: View {
    @Bindable var c: CollabModel

    var body: some View {
        HStack(spacing: 10) {
            CollabField(placeholder: "Emails or names", text: $c.draft, identifier: "invite-field") { c.addDraft() }
            Button("Add") { c.addDraft() }.buttonStyle(.plain).font(.grailsBody(13))
                .foregroundStyle(c.draft.trimmingCharacters(in: .whitespaces).isEmpty ? Ink.secondary : Ink.text)
                .disabled(c.draft.trimmingCharacters(in: .whitespaces).isEmpty)
                .accessibilityIdentifier("invite-add")
        }
    }
}

/// The checklist: one row a person, with where they are (Not sent → Invited → Joined).
struct TeammateList: View {
    var c: CollabModel
    var maxRows: Int

    var body: some View {
        let rows = c.roster.rows
        if rows.isEmpty {
            Text("No one on the list yet").font(.grailsBody(13)).foregroundStyle(Ink.secondary).frame(height: 36)
        } else if rows.count <= maxRows {
            VStack(spacing: 0) { ForEach(rows) { TeammateRow(c: c, row: $0) } }
        } else {
            ScrollView { VStack(spacing: 0) { ForEach(rows) { TeammateRow(c: c, row: $0) } } }
                .frame(height: CGFloat(maxRows) * TeammateRow.height)
        }
    }
}

struct TeammateRow: View {
    var c: CollabModel
    let row: InviteList.Row
    static let height: CGFloat = 44
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 12) {
            Group {
                if row.status == .notInvited { Circle().strokeBorder(Ink.secondary, lineWidth: 1) } else { Circle().fill(dot) }
            }
            .frame(width: 7, height: 7)
            VStack(alignment: .leading, spacing: 1) {
                Text(row.teammate.contact).font(.grailsBody(13)).foregroundStyle(Ink.text).lineLimit(1).truncationMode(.middle)
                Text(status).font(.grailsBody(11)).foregroundStyle(Ink.secondary).lineLimit(1)
            }
            Spacer(minLength: 8)
            CollabMenu {
                if row.status != .joined {
                    if row.teammate.email != nil { Button("Email Invite") { c.emailInvites([row.teammate]) } }
                    Button("Copy Invite") { c.copyMessage(for: [row.teammate]) }
                }
                let handles = c.seen.map(\.handle).filter { $0 != row.handle }
                if !handles.isEmpty {
                    Menu("This Is…") { ForEach(handles, id: \.self) { h in Button(h) { c.link(row.id, handle: h) } } }
                }
                if let h = row.handle { Button("Not \(h)") { c.link(row.id, handle: nil, unlinking: h) } }
                Divider()
                Button("Remove") { c.remove(row.id) }
            } label: {
                Image(systemName: "ellipsis").font(.system(size: 12)).foregroundStyle(Ink.secondary).frame(width: 24, height: 24)
            }
            .accessibilityLabel("More for \(row.teammate.contact)")
        }
        .padding(.horizontal, 10).frame(height: Self.height)
        .background(RoundedRectangle(cornerRadius: Ink.radius, style: .continuous).fill(hovering ? Ink.fill.opacity(0.5) : .clear))
        .overlay(alignment: .bottom) { Rectangle().fill(Ink.hairline).frame(height: 1).padding(.horizontal, 10) }
        .hoverState($hovering)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("invite-row")
    }

    private var dot: Color {
        switch row.status {
        case .joined: Ink.positive
        case .invited: Ink.secondary
        case .notInvited: Ink.fill
        }
    }

    private var status: String {
        switch row.status {
        case .notInvited: return "Not sent"
        case .invited: return "Invited " + (row.teammate.invitedAt?.formatted(.dateTime.day().month(.abbreviated)) ?? "")
        case .joined:
            let what = row.seen.map { $0.items > 0 ? "\($0.items) item\($0.items == 1 ? "" : "s")" : "opened it" } ?? ""
            return "Joined as \(row.handle ?? "")" + (what.isEmpty ? "" : " · \(what)") + (row.guessed ? " · matched by name" : "")
        }
    }
}

/// People in the library who aren't on the list: the owner can say who they are.
private struct OthersList: View {
    var c: CollabModel
    let others: [SeenPerson]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Also here").font(.grailsBody(11)).foregroundStyle(Ink.secondary)
            HStack(spacing: 6) {
                ForEach(others.prefix(6), id: \.handle) { p in
                    CollabMenu {
                        ForEach(c.invites.teammates.filter { $0.handle == nil }) { t in Button(t.contact) { c.link(t.id, handle: p.handle) } }
                    } label: {
                        Text(p.handle).font(.grailsBody(12)).foregroundStyle(Ink.text).padding(.horizontal, 8).frame(height: 22).chipSurface()
                    }
                    .help("Link to someone on the list")
                }
            }
        }
    }
}

/// The ways to send: email everyone not yet invited (primary), copy the message, or the share sheet. When everyone has been sent one,
/// the primary becomes the way on (`onFinished`).
struct InviteActions<Leading: View>: View {
    var c: CollabModel
    var finishTitle = "Done"
    var onFinished: () -> Void
    @ViewBuilder var leading: Leading

    var body: some View {
        let emails = c.pendingEmails
        let pending = c.pending
        HStack(spacing: 16) {
            leading
            if !emails.isEmpty { QuietButton(title: "Copy invite", identifier: "invite-copy") { c.copyMessage() } }
            if let m = c.message(to: pending.count == 1 ? pending[0].contact : nil) {
                ShareLink(item: m.body, subject: Text(m.subject), message: Text("")) { Text("Share…") }
                    .buttonStyle(.plain).font(.grailsBody(13)).foregroundStyle(Ink.secondary)
                    .simultaneousGesture(TapGesture().onEnded { c.markInvited(pending) })
                    .accessibilityIdentifier("invite-share")
            }
            Spacer()
            Group {
                if !emails.isEmpty {
                    Button(emails.count == 1 ? "Email invite" : "Email \(emails.count) invites") { c.emailInvites() }.accessibilityIdentifier("invite-email")
                } else if !pending.isEmpty {
                    Button("Copy invite") { c.copyMessage() }.accessibilityIdentifier("invite-copy")
                } else {
                    Button(finishTitle, action: onFinished).accessibilityIdentifier("invite-next")
                }
            }
            .buttonStyle(PrimaryButtonStyle()).keyboardShortcut(.defaultAction)
        }
    }
}
