import GrailsDesign
import GrailsKit
import SwiftUI

enum TeamHomeNext: Equatable {
    case migrate
    case bucket
    case join
}

/// Team setup. Cloud bucket first. The shared-folder wizard is the second card, not the front door.
struct TeamHomeSheet: View {
    @Bindable var model: AppModel
    var onClose: () -> Void
    @State private var shared = false

    var body: some View {
        if shared {
            CollabSetupView(model: model, onDone: onClose)
        } else {
            GrailsModal(title: "Team library", step: "choose", identifier: "team-home", showsFooter: false, onClose: onClose) {
                VStack(alignment: .leading, spacing: CGFloat(Space.xs)) {
                    ForEach(TeamHomeChoice.order, id: \.self) { choice in
                        card(choice)
                    }
                }
            } footer: {
                EmptyView()
            }
        }
    }

    @ViewBuilder private func card(_ choice: TeamHomeChoice) -> some View {
        switch choice {
        case .bucket:
            GrailsChoiceCard(choice.title, identifier: "team-home-bucket", symbol: ChromeIcon.bucket) {
                model.teamHomeNext = model.store != nil && !model.bucket.connected ? .migrate : .bucket
                model.showTeamHome = false
            }
        case .sharedFolder:
            GrailsChoiceCard(choice.title, identifier: "team-home-folder", symbol: ChromeIcon.folder) {
                shared = true
            }
        case .join:
            GrailsChoiceCard(choice.title, identifier: "team-home-join", symbol: ChromeIcon.invite) {
                model.teamHomeNext = .join
                model.showTeamHome = false
            }
        }
    }
}
