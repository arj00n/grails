import GrailsDesign
import SwiftUI

struct WelcomeRequest: Equatable {
    var library: String
}

extension AppModel {
    /// Onboarding just handed over the library: the pictures settle into place, and once they have, a short welcome.
    func greetAfterOnboarding() {
        settleTick += 1
        let delay: Duration = ReduceMotion.isOn ? .milliseconds(350) : .milliseconds(1400)
        Task { @MainActor in
            try? await Task.sleep(for: delay)
            guard onboarding == nil else { return }
            withAnimation(.grails(.grailsStandard, reduceMotion: ReduceMotion.isOn)) { welcome = WelcomeRequest(library: libraryName) }
        }
    }
}

/// "You're all set": one modal over the library, one button.
struct WelcomeCard: View {
    var model: AppModel
    let request: WelcomeRequest

    var body: some View {
        GrailsModal(title: "You're all set", step: "welcome", onClose: close) {
            Text("Welcome to \(request.library == "Grails Library" ? "Grails" : request.library). Have fun curating.")
                .font(.grailsBody(13)).foregroundStyle(Ink.secondary)
                .fixedSize(horizontal: false, vertical: true)
        } footer: {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Spacer()
                    GrailsButton("Let's go", kind: .primary) { close() }.keyboardShortcut(.defaultAction)
                        .accessibilityIdentifier("welcome-go")
                }
                GrailsControl("") { close() }.keyboardShortcut(.cancelAction).frame(width: 0, height: 0).opacity(0)
            }
        }
        .accessibilityIdentifier("welcome")
    }

    private func close() { withAnimation(.grailsQuick) { model.welcome = nil } }
}
