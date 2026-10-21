import GrailsDesign
import SwiftUI

/// The bucket cache is here and the keychain has no access key. Ask for the key again. Do not make a second library.
struct ReconnectBucketSheet: View {
    @Bindable var model: AppModel
    var onClose: () -> Void
    @State private var draft = BucketDraft()
    @State private var showRegion = false
    @State private var error: String?
    @State private var busy = false

    var body: some View {
        GrailsModal(title: "Reconnect storage", step: "credentials", error: error, identifier: "reconnect-bucket-sheet", onClose: onClose) {
            GrailsBucketForm(draft: $draft, showRegion: $showRegion, onSubmit: reconnect)
        } footer: {
            HStack {
                Spacer()
                GrailsButton("Reconnect", kind: .primary, identifier: "reconnect-bucket-save", enabled: !busy && draft.canCreate) { reconnect() }
            }
        }
    }

    private func reconnect() {
        guard !busy, draft.canCreate, let root = model.layout?.root, !model.libraryID.isEmpty else { return }
        let filled = draft
        draft.secret = ""
        draft.apiToken = ""
        error = nil
        busy = true
        Task {
            let message = await model.bucket.reconnect(
                endpoint: filled.endpoint, region: filled.regionForSave, bucket: filled.bucket,
                accessKeyId: filled.accessKey, secret: filled.secret, email: filled.email,
                libraryID: model.libraryID, root: root
            )
            if message == nil, !filled.accountID.isEmpty, !filled.apiToken.isEmpty {
                try? model.bucket.saveCloudflare(accountID: filled.accountID, token: filled.apiToken)
            }
            busy = false
            if let message {
                draft.secret = filled.secret
                draft.apiToken = filled.apiToken
                error = message
            } else {
                onClose()
            }
        }
    }
}
