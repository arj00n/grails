import GrailsDesign
import SwiftUI

enum WorkspaceDraft: String, Identifiable {
    case choose
    case bucket
    case invite

    var id: String { rawValue }
}

struct NewWorkspaceSheet: View {
    @Bindable var model: AppModel
    var startedAtChoose: Bool
    @State private var flow: WorkspaceFlow
    @State private var error: String?
    @State private var busy = false
    @State private var showRegion = false

    init(model: AppModel, start: WorkspaceDraft) {
        self.model = model
        let step = WorkspaceStep(rawValue: start.rawValue) ?? .choose
        startedAtChoose = step == .choose
        _flow = State(initialValue: WorkspaceFlow(start: step))
    }

    var body: some View {
        GrailsModal(title: modalTitle, step: modalStep, error: modalError, identifier: "new-workspace", showsFooter: flow.step != .choose, onClose: { model.workspaceDraft = nil }) {
            content
        } footer: {
            if flow.step == .invite {
                TeammateJoinFooter(bucket: model.bucket, showsChooserBack: startedAtChoose, onChooserBack: {
                    error = nil
                    model.bucket.resetOnboarding()
                    flow.go(.choose)
                }, onFinished: {
                    model.workspaceDraft = nil
                    model.onboarding?.finish()
                })
            } else {
                HStack {
                    if flow.step != .choose && startedAtChoose {
                        GrailsBackButton {
                            error = nil
                            flow.go(.choose)
                        }
                    }
                    Spacer()
                    if flow.step != .choose {
                        GrailsButton("Create", kind: .primary, identifier: "bucket-create", enabled: !busy && flow.canSubmit) { submit() }
                            .keyboardShortcut(.defaultAction)
                    }
                }
            }
        }
    }

    @ViewBuilder private var content: some View {
        switch flow.step {
        case .choose:
            VStack(alignment: .leading, spacing: CGFloat(Space.xs)) {
                GrailsChoiceCard("Cloud storage (Cloudflare)", identifier: "new-workspace-bucket", symbol: ChromeIcon.bucket) { flow.go(.bucket) }
                GrailsChoiceCard("Shared folder (Drive, Dropbox)", identifier: "new-workspace-shared", symbol: ChromeIcon.folder) {
                    model.workspaceDraft = nil
                    Task { @MainActor in LibraryPicker.saveNewFolder(model) }
                }
                GrailsChoiceCard("Join with invite…", identifier: "new-workspace-invite", symbol: ChromeIcon.invite) {
                    model.bucket.resetOnboarding()
                    flow.go(.invite)
                }
            }
        case .bucket:
            GrailsBucketForm(draft: $flow.bucket, showRegion: $showRegion, onSubmit: { submit() })
        case .invite:
            TeammateJoinFields(bucket: model.bucket) { submitInvite() }
        }
    }

    private var modalTitle: String {
        flow.step == .invite ? model.bucket.onboarding.title : flow.step.title
    }

    private var modalStep: String {
        flow.step == .invite ? "join-\(model.bucket.onboarding.step.id)" : flow.step.rawValue
    }

    private var modalError: String? {
        flow.step == .invite ? model.bucket.onboarding.message : error
    }

    private func submit() {
        guard !busy else { return }
        error = nil
        switch flow.step {
        case .choose:
            break
        case .bucket:
            guard flow.bucket.canCreate else { return }
            let draft = flow.bucket
            flow.bucket.secret = ""
            flow.bucket.apiToken = ""
            busy = true
            Task {
                let message = await model.createBucketLibrary(
                    endpoint: draft.endpoint, region: draft.regionForSave, bucketName: draft.bucket, accessKeyId: draft.accessKey,
                    secret: draft.secret, email: draft.email, accountID: draft.accountID, apiToken: draft.apiToken
                )
                busy = false
                error = message
                if message != nil {
                    flow.bucket.secret = draft.secret
                    flow.bucket.apiToken = draft.apiToken
                }
            }
        case .invite:
            submitInvite()
        }
    }

    private func submitInvite() {
        switch model.bucket.onboarding.step {
        case .link:
            if model.acceptFolderLink(model.bucket.onboardingLink) { return }
            Task { await model.bucket.noteOnboardingLink(model.bucket.onboardingLink) }
        case .code: model.bucket.noteOnboardingCode(model.bucket.onboardingCode)
        case .name:
            guard model.bucket.onboarding.submitName(model.bucket.onboardingName) else { return }
            let link = model.bucket.onboarding.link
            let code = model.bucket.onboarding.code
            let email = model.bucket.onboarding.invitedEmail
            let name = model.bucket.onboarding.displayName
            Task {
                guard let link else { return }
                switch await model.bucket.joinTeammate(link: link, code: code, email: email, name: name) {
                case .joined:
                    model.bucket.onboarding.finish()
                    model.workspaceDraft = nil
                    model.onboarding?.finish()
                case .failed(let failure):
                    model.bucket.onboarding.fail(failure)
                case .inProgress:
                    break
                }
            }
        case .blocked, .done:
            break
        }
    }
}
