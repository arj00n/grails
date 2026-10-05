import SwiftUI

/// First run: join the team's shared library, start a new one, or keep one on this Mac.
struct WelcomeView: View {
    var model: AppModel

    var body: some View {
        ZStack {
            Rectangle().fill(.background).ignoresSafeArea()
            VStack(spacing: 22) {
                Image(systemName: "square.stack.3d.down.right").font(.system(size: 44)).foregroundStyle(Ink.text)
                Text("Welcome to Grails").font(.grailsDisplay(34))
                VStack(spacing: 10) {
                    choice("Join the team library", "person.2.fill", "welcome-join") {
                        model.chooseLibrary { model.openLibrary(at: $0) }
                    }
                    choice("Create a new library", "plus.rectangle.on.folder", "welcome-create") {
                        LibraryPicker.createNew(model)
                    }
                    choice("Keep one on this Mac", "house", "welcome-default") {
                        model.openLibrary(at: AppModel.defaultLibraryURL)
                    }
                }
                .frame(maxWidth: 440)
            }
            .padding(32)
        }
    }

    private func choice(_ title: String, _ symbol: String, _ id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: symbol).font(.title2).frame(width: 34).foregroundStyle(Ink.text)
                Text(title).font(.grailsDisplay(16))
                Spacer()
            }
            .padding(14)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
    }
}
