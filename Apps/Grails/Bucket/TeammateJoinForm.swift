import GrailsDesign
import GrailsSync
import SwiftUI

struct TeammateJoinFields: View {
    @Bindable var bucket: BucketController
    var onSubmit: () -> Void

    var body: some View {
        switch bucket.onboarding.step {
        case .link:
            GrailsTextField("Invite link", text: $bucket.onboardingLink, required: true, error: FieldRules.linkError(bucket.onboardingLink), placeholder: "grails://j/", identifier: "invite-link", showsPaste: true, corrects: false, autofocus: true, onSubmit: onSubmit)
        case .code:
            GrailsTextField("Code", text: $bucket.onboardingCode, required: true, error: codeError, placeholder: "042817", identifier: "join-code", corrects: false, autofocus: true, onSubmit: onSubmit)
        case .name:
            VStack(alignment: .leading, spacing: CGFloat(ChromeMetrics.fieldGap)) {
                GrailsReadOnlyValue("Email", value: bucket.onboarding.invitedEmail, identifier: "join-email")
                GrailsTextField("Username", text: $bucket.onboardingName, required: true, identifier: "join-name", corrects: false, autofocus: true, onSubmit: onSubmit)
            }
        case .blocked, .done:
            EmptyView()
        }
    }

    private var codeError: String? {
        if bucket.onboarding.error == .badCode || bucket.onboarding.error == .locked { return bucket.onboarding.message }
        return FieldRules.codeError(bucket.onboardingCode)
    }
}

struct TeammateJoinFooter: View {
    @Bindable var bucket: BucketController
    var showsChooserBack: Bool
    var onChooserBack: () -> Void
    var onFinished: () -> Void

    var body: some View {
        HStack {
            if showsBack {
                GrailsBackButton { back() }
            }
            Spacer()
            if bucket.onboarding.step == .blocked {
                GrailsButton("Check for Updates", kind: .primary, identifier: "join-update") {
                    UpdaterController.shared.checkForUpdates()
                }
            } else {
                GrailsButton("Continue", kind: .primary, loading: bucket.joining, identifier: "join-continue", enabled: canContinue) { advance() }
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    private var showsBack: Bool {
        if showsChooserBack && bucket.onboarding.step == .link { return true }
        switch bucket.onboarding.step {
        case .code, .name: return true
        case .link, .blocked, .done: return false
        }
    }

    private var canContinue: Bool {
        guard bucket.onboarding.canContinue else { return false }
        switch bucket.onboarding.step {
        case .link: return FieldRules.inviteLink(in: bucket.onboardingLink)
        case .code: return FieldRules.inviteCode(bucket.onboardingCode) != nil
        case .name: return DisplayName.normalized(bucket.onboardingName) != nil
        case .blocked, .done: return false
        }
    }

    private func back() {
        if bucket.onboarding.step == .link {
            onChooserBack()
            return
        }
        bucket.onboarding.back()
    }

    private func advance() {
        switch bucket.onboarding.step {
        case .link:
            Task { await bucket.noteOnboardingLink(bucket.onboardingLink) }
        case .code:
            bucket.noteOnboardingCode(bucket.onboardingCode)
        case .name:
            guard bucket.onboarding.submitName(bucket.onboardingName) else { return }
            let link = bucket.onboarding.link
            let code = bucket.onboarding.code
            let email = bucket.onboarding.invitedEmail
            let name = bucket.onboarding.displayName
            Task {
                guard let link else { return }
                switch await bucket.joinTeammate(link: link, code: code, email: email, name: name) {
                case .joined:
                    bucket.onboarding.finish()
                    onFinished()
                case .failed(let error):
                    bucket.onboarding.fail(error)
                case .inProgress:
                    break
                }
            }
        case .blocked, .done:
            break
        }
    }
}
