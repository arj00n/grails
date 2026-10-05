import SwiftUI

struct WelcomeRequest: Equatable {
    var library: String
}

extension AppModel {
    /// Onboarding just handed over the library: the pictures settle into place, and once they have, a short welcome.
    func greetAfterOnboarding() {
        settleTick += 1
        let delay: Duration = reduceMotionOn ? .milliseconds(350) : .milliseconds(1400)
        Task { @MainActor in
            try? await Task.sleep(for: delay)
            guard onboarding == nil else { return }
            withAnimation(.timingCurve(0.22, 1, 0.36, 1, duration: reduceMotionOn ? 0.12 : 0.24)) { welcome = WelcomeRequest(library: libraryName) }
        }
    }
}

/// "You're all set": one card over the library, one button.
struct WelcomeCard: View {
    var model: AppModel
    let request: WelcomeRequest
    @State private var shown = false

    var body: some View {
        ZStack {
            Ink.canvas.opacity(0.55).ignoresSafeArea().onTapGesture(perform: close)
            VStack(alignment: .leading, spacing: 10) {
                Text("YOU'RE ALL SET").font(.grailsDisplay(16)).foregroundStyle(Ink.text)
                Text("Welcome to \(request.library == "Grails Library" ? "Grails" : request.library). Have fun curating.").font(.grailsBody(13)).foregroundStyle(Ink.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Spacer()
                    Button("Let's go", action: close).buttonStyle(PrimaryButtonStyle()).keyboardShortcut(.defaultAction)
                        .accessibilityIdentifier("welcome-go")
                }
                .padding(.top, 8)
                Button("") { close() }.keyboardShortcut(.cancelAction).frame(width: 0, height: 0).opacity(0)
            }
            .padding(20)
            .frame(width: 340)
            .surfaceCard()
            .offset(y: shown || reduceMotionOn ? 0 : 8)
            .opacity(shown ? 1 : 0)
        }
        .onAppear { withAnimation(.timingCurve(0.22, 1, 0.36, 1, duration: reduceMotionOn ? 0.12 : 0.24)) { shown = true } }
        .accessibilityIdentifier("welcome")
    }

    private func close() { withAnimation(.easeOut(duration: 0.18)) { model.welcome = nil } }
}
