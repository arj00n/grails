import AppKit
import GrailsDesign
import GrailsKit
import GrailsSync
import SwiftUI

enum ConnectionStatus {
    static func current(revoked: Bool, syncing: Bool, connected: Bool) -> (StatusKind, String) {
        if revoked { return (.error, "Disconnected") }
        if syncing { return (.warn, "Syncing") }
        if connected { return (.ok, "Connected") }
        return (.offline, "Offline")
    }

    /// Only a problem: a revoked or dropped shared library, a sync that keeps failing, or no network. One short failure stays quiet.
    static func problem(revoked: Bool, connected: Bool, shared: Bool, reachable: Bool, health: SyncHealth) -> (StatusKind, String)? {
        guard let banner = SyncHealth.banner(revoked: revoked, connected: connected, shared: shared, reachable: reachable, health: health) else { return nil }
        switch banner {
        case .disconnected: return (.error, banner.label)
        case .failing: return (.error, banner.label)
        case .offline: return (.offline, banner.label)
        }
    }
}

/// Pinned under the sidebar: photo, name, role, settings, and a status only when sync needs attention.
struct AccountFooter: View {
    var model: AppModel

    private var problem: (StatusKind, String)? {
        ConnectionStatus.problem(revoked: model.bucket.revoked, connected: model.bucket.connected, shared: model.bucket.team != nil, reachable: model.bucket.reachable, health: model.bucket.syncHealth)
    }

    private var roleTitle: String? {
        guard model.bucket.connected || model.bucket.team != nil else { return nil }
        switch model.bucket.role {
        case .owner: return "Owner"
        case .admin: return "Admin"
        case .member: return "Member"
        }
    }

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            GrailsMemberAvatar(model.myFace, side: 30, showsName: false)
                .accessibilityIdentifier("account-avatar")
            VStack(alignment: .leading, spacing: 2) {
                Text(model.userHandle)
                    .font(.grailsBody(13))
                    .foregroundStyle(Ink.text)
                    .lineLimit(1)
                if let roleTitle {
                    Text(roleTitle)
                        .font(.grailsBody(12))
                        .foregroundStyle(Ink.secondary)
                        .lineLimit(1)
                }
                if let problem {
                    StatusDot(problem.0, problem.1)
                        .accessibilityIdentifier("account-status")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("account-footer")
            GrailsIconButton("gearshape", label: "Settings") {
                model.openSettings()
            }
            .accessibilityIdentifier("account-settings")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Ink.sidebar)
        .overlay(alignment: .top) { Rectangle().fill(Ink.hairline).frame(height: 1) }
    }
}
