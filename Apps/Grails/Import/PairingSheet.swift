import GrailsDesign
import GrailsKit
import SwiftUI

struct PairingSheet: View {
    var model: AppModel
    let item: PairingSheetItem

    var body: some View {
        GrailsModal(
            title: item.copy.title,
            step: "connect",
            identifier: "pair-prompt",
            onClose: { model.denyPairing(item) }
        ) {
            Text(item.copy.line)
                .font(.grailsBody(13))
                .foregroundStyle(Ink.secondary)
                .fixedSize(horizontal: false, vertical: true)
        } footer: {
            HStack(spacing: CGFloat(Space.xs)) {
                Spacer()
                GrailsButton("Deny", kind: .secondary, identifier: "pair-deny") { model.denyPairing(item) }
                    .keyboardShortcut(.cancelAction)
                GrailsButton("Allow", kind: .primary, identifier: "pair-allow") { model.allowPairing(item) }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .task(id: item.id) {
            while !Task.isCancelled {
                let now = Date()
                if item.expired(now: now) {
                    model.dismissExpiredPairing(item.id, now: now)
                    return
                }
                do { try await Task.sleep(for: .seconds(item.remaining(now: now)), tolerance: .seconds(1)) }
                catch {
                    let now = Date()
                    if item.expired(now: now) { model.dismissExpiredPairing(item.id, now: now) }
                    return
                }
            }
        }
    }
}
