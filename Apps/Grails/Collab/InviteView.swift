import AppKit
import GrailsDesign
import GrailsKit
import SwiftUI

/// Invite, any time (Settings ▸ Library, the sidebar menu): the message, to copy or share anywhere, and who has turned up.
struct InviteView: View {
    var model: AppModel
    var onClose: () -> Void = {}

    private var c: CollabModel { model.collab }
    static let size = CGSize(width: 560, height: 480)

    var body: some View {
        let placement = c.currentPlacement
        let here = c.seen.filter { Handle.normalize($0.handle) != Handle.normalize(model.userHandle) }
        VStack(alignment: .leading, spacing: 16) {
            CollabHeader(title: "Invite", close: onClose)
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(model.libraryName).font(.grailsBody(15, bold: true)).foregroundStyle(Ink.text).lineLimit(1)
                    Text(placement?.label ?? "").font(.grailsBody(12)).foregroundStyle(Ink.secondary).lineLimit(1)
                }
                Spacer()
                if placement?.service == .googleDrive { QuietButton(title: "Open Drive", identifier: "invite-open-drive") { c.openShare() } }
            }
            if let p = placement, !LibraryHintCheck.reachable(p) {
                IssueLine(issue: p.inTrash ? .trash : .local)
            }
            Rectangle().fill(Ink.hairline).frame(height: 1)
            InviteMessageCard(c: c)
            if !here.isEmpty {
                Text("Here: " + here.map(\.handle).joined(separator: " · ")).font(.grailsBody(12)).foregroundStyle(Ink.secondary).lineLimit(2)
            }
            InviteActions(c: c) { QuietButton(title: "Copy link", identifier: "invite-copy-link") { c.copyLink() } }
            Button("") { onClose() }.keyboardShortcut(.cancelAction).frame(width: 0, height: 0).opacity(0)
        }
        .padding(24)
        .frame(width: Self.size.width, height: Self.size.height, alignment: .topLeading)
        .task {
            // who has turned up: now, and every 10 s while this is open (teammates' saves arrive by sync)
            while !Task.isCancelled {
                await c.refreshSeen()
                try? await Task.sleep(for: .seconds(10))
            }
        }
        .accessibilityIdentifier("invite-view")
    }
}

enum LibraryHintCheck {
    /// Can a teammate get to this place at all?
    static func reachable(_ p: Placement) -> Bool { p.isSynced && !p.inTrash && p.kind != .driveTop }
}

/// The message as it will be sent.
struct InviteMessageCard: View {
    var c: CollabModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(c.message?.body ?? "").font(.grailsBody(12)).foregroundStyle(Ink.text).textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading).padding(14)
            Spacer(minLength: 0)
        }
        .background(Ink.fill, in: RoundedRectangle(cornerRadius: Ink.cardRadius, style: .continuous))
        .frame(maxHeight: .infinity, alignment: .top)
        .accessibilityIdentifier("invite-message")
    }
}

/// Copy the message (the main action), or hand it to the share sheet. `sent` runs after either.
struct InviteActions<Leading: View>: View {
    var c: CollabModel
    var sent: () -> Void = {}
    @ViewBuilder var leading: Leading

    var body: some View {
        HStack(spacing: 16) {
            leading
            Spacer()
            if let m = c.message {
                ShareLink(item: m.body, subject: Text(m.subject), message: Text("")) { Text("Share…") }
                    .buttonStyle(.plain).font(.grailsBody(13)).foregroundStyle(Ink.secondary)
                    .simultaneousGesture(TapGesture().onEnded { sent() })
                    .accessibilityIdentifier("invite-share")
            }
            Button("Copy message") { c.copyMessage(); sent() }
                .buttonStyle(PrimaryButtonStyle()).keyboardShortcut(.defaultAction).accessibilityIdentifier("invite-copy")
        }
    }
}
