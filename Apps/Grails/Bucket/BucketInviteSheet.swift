import AppKit
import GrailsDesign
import GrailsKit
import GrailsSync
import SwiftUI
import GrailsEndpoints

/// Bucket invite, in three steps: who, mint the key, then the link and the code on separate channels.
struct BucketInviteSheet: View {
    @Bindable var model: AppModel
    var onClose: () -> Void
    @State private var step = "email"
    @State private var email = ""
    @State private var role: LibraryRole = .member
    @State private var pastedKey = ""
    @State private var pastedSecret = ""

    private var needsKey: Bool { model.bucket.cloudflareSaved == false || model.bucket.role != .owner }

    private var grantAdmin: Bool { model.bucket.team?.adminsMayDemoteAdmins ?? false }

    private func clampRole() {
        if !InviteRoles.allows(role, actor: model.bucket.role, adminsMayGrantAdmin: grantAdmin) {
            role = .member
        }
    }

    private var emailBlock: InviteGate.Block? {
        InviteGate.block(
            email: email,
            actorEmail: model.bucket.email,
            ownerEmail: model.bucket.team?.ownerEmail ?? "",
            members: model.bucket.team?.members.map(\.email) ?? [],
            pending: model.bucket.invites.compactMap { invite in
                if case .pending = invite.state { return invite.email }
                return nil
            }
        )
    }

    var body: some View {
        GrailsModal(title: step == "share" ? "Share invite" : "Invite", subtitle: step == "share" ? "Send them the link, then share the code another way, so only they can join." : nil, step: step, error: model.bucket.inviteError, identifier: "bucket-invite", onClose: onClose) {
            switch step {
            case "create": create
            case "share": share
            default: who
            }
        } footer: {
            switch step {
            case "email":
                HStack(spacing: CGFloat(ModalMetrics.buttonGap)) {
                    Spacer()
                    GrailsButton("Cancel", kind: .secondary, identifier: "bucket-invite-cancel") { onClose() }
                    GrailsButton("Create invite", kind: .primary, identifier: "bucket-invite-continue", enabled: emailBlock == nil) { goCreate() }
                }
            case "create":
                HStack {
                    Spacer()
                    GrailsButton(model.bucket.inviteError == nil ? "Create" : "Try again", kind: .primary, identifier: "bucket-invite-create", enabled: !model.bucket.creating && !(needsKey && (pastedKey.isEmpty || pastedSecret.isEmpty))) {
                        Task { await createInvite() }
                    }
                }
            default:
                HStack {
                    Spacer()
                    GrailsButton("Done", kind: .primary, identifier: "bucket-invite-done") { finish() }
                }
            }
        }
        .onAppear {
            model.bucket.refreshRole()
            if let forced = ProcessInfo.processInfo.environment["GRAILS_INVITE_STEP"], !forced.isEmpty {
                step = forced
                if forced == "share", model.bucket.share == nil {
                    model.bucket.share = InviteShare(
                        email: "ada@company.com",
                        role: .member,
                        link: (GrailsEndpoints.site ?? GrailsEndpoints.officialSite).appendingPathComponent("i/sample").absoluteString,
                        message: "Ada invited you to a Grails library.",
                        code: "042817",
                        expires: Date(timeIntervalSinceNow: 7 * 24 * 60 * 60)
                    )
                }
            } else if model.bucket.share != nil {
                step = "share"
            }
            clampRole()
        }
        .onChange(of: model.bucket.role) { _, _ in clampRole() }
        .onChange(of: model.bucket.share?.link) { _, link in
            if link != nil { step = "share" }
        }
        .task(id: step) {
            guard step == "create", !needsKey else { return }
            await createInvite()
        }
    }

    private var who: some View {
        VStack(alignment: .leading, spacing: CGFloat(ChromeMetrics.groupGap)) {
            GrailsTextField("Email", text: $email, required: true, error: InviteGate.shown(emailBlock, email: email), placeholder: "name@company.com", identifier: "bucket-invite-email", corrects: false, autofocus: true, onSubmit: goCreate)
            VStack(alignment: .leading, spacing: CGFloat(ChromeMetrics.labelGap)) {
                Text("Role")
                    .font(.grailsBody(12))
                    .foregroundStyle(Ink.secondary)
                GrailsSegmented(options: InviteRoles.choices.map { option in
                    GrailsSegmented.Option(
                        id: option.rawValue,
                        title: roleTitle(option),
                        enabled: InviteRoles.allows(option, actor: model.bucket.role, adminsMayGrantAdmin: grantAdmin),
                        help: option == .admin ? InviteRoles.adminHelp(actor: model.bucket.role, adminsMayGrantAdmin: grantAdmin) : nil,
                        identifier: "bucket-invite-role-\(option.rawValue)"
                    )
                }, selection: role.rawValue) { id in
                    if let next = LibraryRole(rawValue: id) { role = next }
                }
                Text(InviteRolePreview.membersHelp)
                    .font(.grailsBody(12))
                    .foregroundStyle(Ink.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
                if let lock = InviteRoles.adminHelp(actor: model.bucket.role, adminsMayGrantAdmin: grantAdmin) {
                    Text(lock)
                        .font(.grailsBody(12))
                        .foregroundStyle(Ink.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: stableBody, alignment: .topLeading)
    }

    private var create: some View {
        VStack(alignment: .leading, spacing: CGFloat(ChromeMetrics.sectionGap)) {
            if model.bucket.creating {
                GrailsPending(model.bucket.mintLine)
                    .accessibilityIdentifier("bucket-invite-progress")
            } else if needsKey {
                GrailsSection("Key", symbol: ChromeIcon.key) {
                    VStack(alignment: .leading, spacing: CGFloat(ChromeMetrics.groupGap)) {
                        GrailsTextField("Access key", text: $pastedKey, identifier: "bucket-invite-key", corrects: false)
                        GrailsSecureField("Secret", text: $pastedSecret, identifier: "bucket-invite-secret", showsPaste: true)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: stableBody, alignment: .topLeading)
    }

    @ViewBuilder private var share: some View {
        if let card = model.bucket.share {
            VStack(alignment: .leading, spacing: CGFloat(ChromeMetrics.groupGap)) {
                GrailsCopyField("Link", value: card.link, mono: true, size: TypeScale.monoLink, tracking: TypeScale.monoLinkTracking, identifier: "invite-copy-link") {
                    model.bucket.copy(card.link)
                    model.showToast("Link copied")
                }
                GrailsCopyField("Code", value: codeShown, mono: true, size: TypeScale.monoCode, tracking: TypeScale.monoCodeTracking, identifier: "invite-copy-code", accessory: codeHidden ? ChromeIcon.reveal : ChromeIcon.conceal, accessoryLabel: codeHidden ? "Show code" : "Hide code", onAccessory: { codeHidden.toggle() }) {
                    model.bucket.copy(card.code)
                    model.showToast("Code copied")
                }
                HStack(spacing: 6) {
                    Image(systemName: "clock").font(ChromeFont.symbol(14, weight: .regular)).foregroundStyle(Ink.tertiary)
                    Text(InviteShare.expiry(card.expires, timeZone: .current))
                        .font(.grailsBody(12))
                        .foregroundStyle(Ink.tertiary)
                }
            }
        }
    }

    @State private var codeHidden = false

    private var codeShown: String {
        guard let code = model.bucket.share?.code else { return "" }
        if codeHidden { return "••• •••" }
        return GrailsCodeDisplay.grouped(code)
    }

    /// The email step is two sections. The mint step keeps that height so the sheet does not collapse.
    private var stableBody: CGFloat { 196 }

    private func goCreate() {
        guard emailBlock == nil else { return }
        model.bucket.inviteError = nil
        if !needsKey { model.bucket.prepareMint() }
        step = "create"
    }

    private func createInvite() async {
        await model.bucket.issueInvite(email: email, role: role, pastedAccess: pastedKey, pastedSecret: pastedSecret)
    }

    private func finish() {
        model.bucket.share = nil
        model.bucket.inviteError = nil
        onClose()
    }

    private func roleTitle(_ role: LibraryRole) -> String {
        switch role {
        case .member: "Member"
        case .admin: "Admin"
        case .owner: "Owner"
        }
    }

}
