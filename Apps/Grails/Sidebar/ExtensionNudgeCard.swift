import GrailsDesign
import GrailsKit
import SwiftUI

struct ExtensionNudgeCard: View {
    var offer: ExtensionNudgeOffer
    var addToChrome: () -> Void
    var enableInSafari: () -> Void
    var notNow: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Save from your browser")
                .font(.grailsTitle(13))
                .foregroundStyle(Ink.text)
                .fixedSize(horizontal: false, vertical: true)
            Text("Send a page here without leaving the tab.")
                .font(.grailsBody(12))
                .foregroundStyle(Ink.secondary)
                .fixedSize(horizontal: false, vertical: true)
            actions
            GrailsButton("Not now", kind: .quiet, identifier: "extension-nudge-later") { notNow() }
                .accessibilityHint("Hides this for 3 days")
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .surfaceCard()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Save from your browser")
        .accessibilityIdentifier("extension-nudge")
    }

    @ViewBuilder private var actions: some View {
        if offer.compact {
            VStack(alignment: .leading, spacing: 8) {
                install(offer.primary, kind: .primary)
                if let secondary = offer.secondary { install(secondary, kind: .secondary) }
            }
        } else {
            VStack(alignment: .leading, spacing: 6) {
                install(offer.primary, kind: .primary)
                if let secondary = offer.secondary { install(secondary, kind: .quiet) }
            }
        }
    }

    private func install(_ action: ExtensionNudgeAction, kind: GrailsButtonKind) -> some View {
        let chrome = action == .addToChrome
        return GrailsButton(chrome ? "Add to Chrome" : "Enable in Safari", kind: kind, identifier: chrome ? "extension-nudge-chrome" : "extension-nudge-safari") {
            if chrome { addToChrome() } else { enableInSafari() }
        }
        .frame(maxWidth: kind == .quiet ? nil : .infinity, alignment: .leading)
    }
}
