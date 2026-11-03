import GrailsDesign
import GrailsKit
import SwiftUI

struct ExtensionNudgeCard: View {
    var offer: ExtensionNudgeOffer
    var addToChrome: () -> Void
    var enableInSafari: () -> Void
    var notNow: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            VStack(alignment: .leading, spacing: Space.xs) {
                Text("Save from your browser")
                    .font(.grailsTitle(13))
                    .foregroundStyle(Ink.text)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Send a page here without leaving the tab.")
                    .font(.grailsBody(12))
                    .foregroundStyle(Ink.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            // One CTA group: installs, then Not now, one gap apart.
            VStack(alignment: .leading, spacing: Space.xxs) {
                install(offer.primary, kind: .primary)
                if let secondary = offer.secondary { install(secondary, kind: offer.compact ? .secondary : .quiet) }
                GrailsButton("Not now", kind: .quiet, identifier: "extension-nudge-later") { notNow() }
                    .accessibilityHint("Hides this for 3 days")
                    .alignQuietLabel()
            }
        }
        .padding(Space.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .surfaceCard()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Save from your browser")
        .accessibilityIdentifier("extension-nudge")
    }

    @ViewBuilder private func install(_ action: ExtensionNudgeAction, kind: GrailsButtonKind) -> some View {
        let chrome = action == .addToChrome
        let button = GrailsButton(chrome ? "Add to Chrome" : "Enable in Safari", kind: kind, identifier: chrome ? "extension-nudge-chrome" : "extension-nudge-safari") {
            if chrome { addToChrome() } else { enableInSafari() }
        }
        if kind == .quiet { button.alignQuietLabel() } else { button.frame(maxWidth: .infinity, alignment: .leading) }
    }
}
