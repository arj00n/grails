import GrailsDesign
import GrailsKit
import GrailsSync
import SwiftUI

struct BucketBanners: View {
    var model: AppModel

    var body: some View {
        VStack(spacing: 8) {
            if model.bucket.revoked {
                bar("Your access to this library was removed. Ask an admin to invite you again.", symbol: ChromeIcon.error) { EmptyView() }
            }
            if model.bucket.update != nil {
                bar("Update Grails", symbol: "arrow.down.circle") {
                    GrailsButton("Check for Updates", kind: .primary) { UpdaterController.shared.checkForUpdates() }
                }
            }
            if model.bucket.moved != nil {
                bar(MoveNotice.prompt, symbol: "arrow.right.circle") { EmptyView() }
            }
            switch model.bucket.notice {
            case .full:
                bar("The library is full, so new saves are paused.", symbol: ChromeIcon.error) { EmptyView() }
            case .warning:
                bar("Nearly full. Clear out what nobody uses.", symbol: "exclamationmark.triangle") {
                    GrailsButton("Spring Cleaning", kind: .primary) { model.bucket.showSpring = true }
                }
            case .none:
                EmptyView()
            }
        }
        .padding(.top, 12)
        .animation(GrailsPage.animation, value: model.bucket.update?.minAppVersion)
        .animation(GrailsPage.animation, value: model.bucket.notice)
        .animation(GrailsPage.animation, value: model.bucket.moved?.bucket)
    }

    private func bar<Trailing: View>(_ title: String, symbol: String, @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).foregroundStyle(Ink.secondary)
            Text(title).font(.grailsBody(13))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            trailing()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .frame(minHeight: 40)
        .background(Ink.fill, in: RoundedRectangle(cornerRadius: Ink.radius, style: .continuous))
        .padding(.horizontal, 16)
    }
}

struct JoinOverlay: View {
    @Bindable var model: AppModel

    var body: some View {
        GrailsModal(title: model.bucket.onboarding.title, step: "join-\(model.bucket.onboarding.step.id)", error: model.bucket.onboarding.message, identifier: "join-overlay", onClose: { model.bucket.showJoin = false }) {
            TeammateJoinFields(bucket: model.bucket) {}
        } footer: {
            TeammateJoinFooter(bucket: model.bucket, showsChooserBack: false, onChooserBack: {}, onFinished: {
                model.bucket.showJoin = false
                model.onboarding?.finish()
            })
        }
    }
}

struct TeamSettingsTab: View {
    @Bindable var model: AppModel
    var page = "team"
    @State private var cap = "9"
    @State private var maxFile = "200"
    @State private var rate = "500"
    @State private var accountID = ""
    @State private var apiToken = ""
    @State private var secret = ""
    @State private var minVersion = "0.3.5"
    @State private var restoreDay = ""
    @State private var transferTarget = ""
    @State private var recoveryPassword = ""
    @State private var moveEndpoint = ""
    @State private var moveBucket = ""
    @State private var moveRegion = "auto"
    @State private var showMoveRegion = false
    @State private var showBackupRegion = false
    @State private var moveKey = ""
    @State private var moveSecret = ""
    @State private var moveAccount = ""
    @State private var moveToken = ""
    @State private var confirming: DestructiveConfirm?

    var body: some View {
        VStack(alignment: .leading, spacing: CGFloat(SettingsGroupMetrics.groupGap)) {
            GrailsSettingsGroup("Connection") {
                GrailsSettingsRow("Status") { StatusDot(bucketStatus.0, bucketStatus.1) }
            }
            if page == "storage" {
                if model.bucket.seesControls {
                    GrailsSettingsGroup("Storage") { storage }
                    GrailsSettingsGroup("Cleaning") { cleaning }
                }
                if model.bucket.role == .owner {
                    GrailsSettingsGroup("Cloudflare") { cloudflare }
                    GrailsSettingsGroup("Recovery") { recovery }
                    GrailsSettingsGroup("Move") { move }
                    GrailsSettingsGroup("Format") { format }
                    GrailsSettingsGroup("Backup") { backup }
                    GrailsSettingsGroup("Library") { libraryActions }
                }
            } else {
                GrailsSettingsGroup("People") {
                    people
                    GrailsSettingsRow(model.bucket.seesControls ? "Invite people" : nil, detail: "Invites last 24 hours. Invited people see the library as soon as they join.") {
                        if model.bucket.seesControls {
                            GrailsButton("Invite", kind: .primary, symbol: "plus", identifier: "team-invite") {
                                model.collab.presentInvite()
                            }
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .task { await model.bucket.refreshSideData() }
        .grailsSheet(item: $confirming) { confirm in
            GrailsConfirmModal(confirm, onCancel: { confirming = nil }) {
                confirming = nil
                perform(confirm)
            }
        }
    }

    private func perform(_ confirm: DestructiveConfirm) {
        Task {
            switch confirm {
            case .deleteLibrary: await model.bucket.deleteLibrary()
            case .emptyTrash: await model.bucket.emptyTrash()
            case .deleteOldBucket: await model.bucket.deleteRetiredBucket()
            case .restoreDay(let day): await model.bucket.restore(day: day)
            }
        }
    }

    private var bucketStatus: (StatusKind, String) {
        ConnectionStatus.current(revoked: model.bucket.revoked, syncing: model.bucket.syncing, connected: model.bucket.connected)
    }

    private var people: some View {
        // A person row brings its own inset for its hover fill, so the block adds only the rest.
        GrailsSettingsBlock(inset: SettingsGroupMetrics.rowInsetX - Space.sm) {
            if let team = model.bucket.team {
                ForEach(team.members, id: \.email) { member in
                    memberRow(member)
                }
            }
            ForEach(model.bucket.invites, id: \.id) { invite in
                if case .pending = invite.state {
                    inviteRow(invite)
                }
            }
            if let error = model.bucket.inviteError, !model.showBucketInvite {
                Text(error).font(.grailsBody(12)).foregroundStyle(Ink.secondary).padding(.horizontal, CGFloat(Space.sm))
            }
        }
    }

    @ViewBuilder private func memberRow(_ member: TeamMember) -> some View {
        let running = model.bucket.actions.label(member.email)
        let failed = model.bucket.actions.failure(member.email)
        let you = member.email == model.bucket.email ? "You" : ""
        let title = model.personName(member.email)
        if let running {
            GrailsPersonRow(title, subtitle: running, role: roleTitle(member.role), busy: true)
                .accessibilityIdentifier("team-row-\(member.email)")
        } else if memberHasActions(member) || failed != nil {
            GrailsPersonRow(title, subtitle: failed ?? you, role: roleTitle(member.role), revealed: transferTarget == member.email || failed != nil) {
                if failed != nil {
                    GrailsButton("Retry", kind: .quiet, enabled: !model.bucket.actions.isBusy(member.email)) { retry(member) }
                }
                if model.bucket.seesControls, member.role == .member {
                    GrailsButton("Make admin", kind: .quiet, enabled: !model.bucket.actions.isBusy(member.email)) { Task { await model.bucket.makeAdmin(member.email) } }
                }
                if model.bucket.role == .owner, member.role == .admin {
                    GrailsButton(transferTarget == member.email ? "Confirm transfer" : "Transfer", kind: transferTarget == member.email ? .primary : .quiet, enabled: !model.bucket.actions.isBusy(member.email)) {
                        if transferTarget == member.email {
                            let address = member.email
                            transferTarget = ""
                            Task { await model.bucket.transfer(to: address) }
                        } else {
                            transferTarget = member.email
                        }
                    }
                    GrailsButton("Demote", kind: .quiet, enabled: !model.bucket.actions.isBusy(member.email)) { Task { await model.bucket.demote(member.email) } }
                }
                if model.bucket.seesControls, member.role != .owner, model.bucket.role == .owner || member.role == .member {
                    GrailsButton("Remove", kind: .quiet, enabled: !model.bucket.actions.isBusy(member.email)) { Task { await model.bucket.removeMember(member.email) } }
                }
            }
            .accessibilityIdentifier("team-row-\(member.email)")
        } else {
            GrailsPersonRow(title, subtitle: you, role: roleTitle(member.role))
        }
    }

    @ViewBuilder private func inviteRow(_ invite: ListedInvite) -> some View {
        let running = model.bucket.actions.label(invite.id)
        let failed = model.bucket.actions.failure(invite.id)
        if let running {
            GrailsPersonRow(invite.email, subtitle: running, role: "Member", pending: true, busy: true)
        } else {
            GrailsPersonRow(invite.email, subtitle: failed ?? InviteShare.expiry(Date(timeIntervalSince1970: invite.exp), timeZone: .current), role: "Member", pending: failed == nil, revealed: failed != nil) {
                if failed != nil {
                    GrailsButton("Retry", kind: .quiet) { Task { await model.bucket.revoke(invite) } }
                }
                GrailsButton("Copy link", kind: .quiet, enabled: invite.blob != nil && !model.bucket.actions.isBusy(invite.id)) { copyLink(invite) }
                GrailsButton("Resend", kind: .quiet, enabled: !model.bucket.actions.isBusy(invite.id)) { Task { await resend(invite) } }
                GrailsButton("Revoke", kind: .quiet, enabled: !model.bucket.actions.isBusy(invite.id)) { Task { await model.bucket.revoke(invite) } }
            }
        }
    }

    private func retry(_ member: TeamMember) {
        let address = member.email
        switch model.bucket.actions.statusLabel(address) {
        case "Removing…":
            Task { await model.bucket.removeMember(address) }
        case "Transferring…":
            Task { await model.bucket.transfer(to: address) }
        default:
            if member.role == .admin {
                Task { await model.bucket.demote(address) }
            } else {
                Task { await model.bucket.makeAdmin(address) }
            }
        }
    }

    private func memberHasActions(_ member: TeamMember) -> Bool {
        if model.bucket.seesControls, member.role == .member { return true }
        if model.bucket.role == .owner, member.role == .admin { return true }
        if model.bucket.seesControls, member.role != .owner, model.bucket.role == .owner || member.role == .member { return true }
        return false
    }

    private func roleTitle(_ role: LibraryRole) -> String {
        switch role {
        case .owner: "Owner"
        case .admin: "Admin"
        case .member: "Member"
        }
    }

    @ViewBuilder private var storage: some View {
        GrailsSettingsRow("Used") { Text(ByteCountFormatter.string(fromByteCount: model.bucket.usage, countStyle: .file)).foregroundStyle(Ink.secondary).monospacedDigit() }
        GrailsSettingsBlock {
            GrailsTextField("Cap GB", text: $cap, corrects: false)
            GrailsTextField("Max file MB", text: $maxFile, corrects: false)
            GrailsTextField("Upload MB per minute", text: $rate, corrects: false)
        }
        GrailsSettingsRow(detail: model.bucket.actions.failure("limits")) {
            GrailsButton("Save limits", kind: .primary, loading: model.bucket.actions.isBusy("limits"), enabled: !model.bucket.actions.isBusy("limits")) { saveLimits() }
        }
    }

    @ViewBuilder private var cleaning: some View {
        GrailsSettingsRow("Unused items") {
            GrailsButton("Spring Cleaning", kind: .secondary) { model.bucket.showSpring = true }
        }
        GrailsSettingsRow("Trash", detail: model.bucket.actions.failure("trash")) {
            if model.bucket.actions.failure("trash") != nil {
                GrailsButton("Retry", kind: .quiet) { Task { await model.bucket.emptyTrash() } }
            }
            GrailsButton("Empty Trash", kind: .secondary, symbol: ChromeIcon.trash, loading: model.bucket.actions.isBusy("trash"), enabled: model.bucket.canEmptyTrash && !model.bucket.actions.isBusy("trash")) { confirming = .emptyTrash }
        }
    }

    @ViewBuilder private var cloudflare: some View {
        GrailsSettingsBlock {
            if model.bucket.needsCloudflareToken {
                Text("Enter your Cloudflare API token").font(.grailsBody(13)).foregroundStyle(Ink.secondary)
            }
            GrailsTextField("Account", text: $accountID, corrects: false)
            GrailsSecureField("API token", text: $apiToken, showsPaste: true)
        }
        GrailsSettingsRow("API token", detail: model.bucket.cloudflareSaved ? "Token saved" : "No token") {
            GrailsButton("Save token", kind: .primary) { saveToken() }
        }
    }

    @ViewBuilder private var recovery: some View {
        GrailsSettingsBlock {
            GrailsSecureField("Recovery password", text: $recoveryPassword)
        }
        GrailsSettingsRow("Recovery file") {
            GrailsButton("Import recovery file", kind: .secondary) { importRecovery() }
            GrailsButton("Export recovery file", kind: .secondary) { exportRecovery() }
        }
    }

    @ViewBuilder private var move: some View {
        GrailsSettingsBlock {
            GrailsTextField("New endpoint", text: $moveEndpoint, required: true, error: FieldRules.endpointError(moveEndpoint), placeholder: BucketDraft.field("endpoint").placeholder, corrects: false)
            GrailsTextField("New bucket", text: $moveBucket, required: true, placeholder: "grails", corrects: false)
            GrailsDisclosure("Region", value: FieldRules.regionOrDefault(moveRegion), expanded: $showMoveRegion) {
                GrailsInlineField(text: $moveRegion, placeholder: "auto")
            }
            GrailsTextField("Access key", text: $moveKey, required: true, corrects: false)
            GrailsSecureField("Secret", text: $moveSecret, required: true, showsPaste: true)
            GrailsTextField("Account", text: $moveAccount, corrects: false)
            GrailsSecureField("API token", text: $moveToken, showsPaste: true)
        }
        GrailsSettingsRow(detail: model.bucket.reinvite.isEmpty ? nil : "Invite them again. \(model.bucket.reinvite.joined(separator: ", "))") {
            GrailsButton("Move library", kind: .primary) { moveLibrary() }
        }
        if model.bucket.hasRetiredBucket {
            GrailsSettingsRow("Old storage") {
                GrailsButton("Delete old storage", kind: .destructive) { confirming = .deleteOldBucket }
            }
        }
    }

    @ViewBuilder private var format: some View {
        GrailsSettingsBlock {
            GrailsTextField("Minimum app version", text: $minVersion, corrects: false)
        }
        GrailsSettingsRow(detail: model.bucket.actions.failure("format")) {
            GrailsButton("Save gate", kind: .primary, loading: model.bucket.actions.isBusy("format"), enabled: !model.bucket.actions.isBusy("format")) { Task { await model.bucket.setFormatGate(formatVersion: 1, minAppVersion: minVersion) } }
        }
    }

    @ViewBuilder private var backup: some View {
        GrailsSettingsBlock {
            GrailsTextField("Endpoint", text: $model.bucket.backupEndpoint, error: FieldRules.endpointError(model.bucket.backupEndpoint), placeholder: BucketDraft.field("endpoint").placeholder, corrects: false)
            GrailsTextField("Bucket", text: $model.bucket.backupBucket, placeholder: "grails", corrects: false)
            GrailsDisclosure("Region", value: FieldRules.regionOrDefault(model.bucket.backupRegion), expanded: $showBackupRegion) {
                GrailsInlineField(text: $model.bucket.backupRegion, placeholder: "auto")
            }
            GrailsSecureField("Secret", text: $secret, showsPaste: true)
        }
        GrailsSettingsRow {
            GrailsButton("Snapshot now", kind: .secondary) { Task { await model.bucket.snapshotNow() } }
            GrailsButton("Save backup", kind: .primary) { saveBackup() }
        }
        GrailsSettingsBlock {
            GrailsTextField("Restore day", text: $restoreDay, placeholder: "2026-10-12", corrects: false)
        }
        GrailsSettingsRow {
            GrailsButton("Restore day", kind: .secondary, enabled: !restoreDay.trimmingCharacters(in: .whitespaces).isEmpty) {
                confirming = .restoreDay(restoreDay.trimmingCharacters(in: .whitespaces))
            }
        }
    }

    @ViewBuilder private var libraryActions: some View {
        GrailsSettingsRow("Cloud storage", detail: model.bucket.migration.map { "\($0.copied) of \($0.total)" }) {
            GrailsButton("Move this library to cloud storage", kind: .secondary, loading: model.bucket.migrating, identifier: "migrate-library") {
                Task { _ = await model.bucket.migrateOpenLibrary() }
            }
        }
        GrailsSettingsRow("Upload") {
            GrailsButton("Upload this library", kind: .secondary) { Task { await model.bucket.uploadLibrary() } }
        }
        GrailsSettingsRow("Delete", detail: model.bucket.actions.failure("delete-library")) {
            GrailsButton("Delete library", kind: .destructive, loading: model.bucket.actions.isBusy("delete-library"), enabled: !model.bucket.actions.isBusy("delete-library")) { confirming = .deleteLibrary }
        }
        if let note = model.bucket.teamNote {
            GrailsSettingsBlock {
                Text(note).font(.grailsBody(12)).foregroundStyle(Ink.secondary)
            }
        }
    }

    private func saveLimits() {
        Task {
            await model.bucket.setLimits(capGB: Int(cap) ?? 9, maxFileMB: Int(maxFile) ?? 200, uploadMBPerMinute: Int(rate) ?? 500)
        }
    }

    private func copyLink(_ invite: ListedInvite) {
        Task {
            guard let url = await model.bucket.webLink(for: invite) else { return }
            model.bucket.copy(url.absoluteString)
            model.showToast("Link copied")
        }
    }

    private func resend(_ invite: ListedInvite) async {
        await model.bucket.resend(invite)
        if model.bucket.share != nil { model.showBucketInvite = true }
    }

    private func saveToken() {
        let token = apiToken
        apiToken = ""
        try? model.bucket.saveCloudflare(accountID: accountID, token: token)
    }

    private func saveBackup() {
        let typed = secret
        secret = ""
        try? model.bucket.saveBackup(secret: typed)
    }

    private func exportRecovery() {
        let password = recoveryPassword
        recoveryPassword = ""
        model.bucket.exportRecovery(password: password)
    }

    private func importRecovery() {
        let password = recoveryPassword
        recoveryPassword = ""
        model.bucket.importRecovery(password: password)
    }

    private func moveLibrary() {
        let typedSecret = moveSecret
        let token = moveToken
        moveSecret = ""
        moveToken = ""
        let endpoint = moveEndpoint
        let bucket = moveBucket
        let region = moveRegion
        let key = moveKey
        let account = moveAccount
        Task {
            await model.bucket.moveLibrary(
                endpoint: endpoint, bucket: bucket, region: FieldRules.regionOrDefault(region), accessKeyId: key,
                secret: typedSecret, accountID: account, apiToken: token
            )
        }
    }

}
