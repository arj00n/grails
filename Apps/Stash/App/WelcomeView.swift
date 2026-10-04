import SwiftUI

/// First run: join the team's shared library, start a new one, or keep one on this Mac.
struct WelcomeView: View {
    var model: AppModel

    var body: some View {
        ZStack {
            Rectangle().fill(.background).ignoresSafeArea()
            VStack(spacing: 22) {
                Image(systemName: "square.stack.3d.down.right").font(.system(size: 44)).foregroundStyle(Ink.text)
                Text("Welcome to Stash").font(.largeTitle.weight(.semibold))
                Text("Save inspiration, find it again, and share it with your team.").foregroundStyle(.secondary)
                VStack(spacing: 10) {
                    choice("Join the team library", "Pick the shared .stash folder on Google Drive (or any synced folder).", "person.2.fill", "welcome-join") {
                        model.chooseLibrary { model.openLibrary(at: $0) }
                    }
                    choice("Create a new library", "Start fresh, anywhere you like. You can move it onto a shared drive later.", "plus.rectangle.on.folder", "welcome-create") {
                        LibraryPicker.createNew(model)
                    }
                    choice("Keep one on this Mac", "A private library in your Pictures folder.", "house", "welcome-default") {
                        model.openLibrary(at: AppModel.defaultLibraryURL)
                    }
                }
                .frame(maxWidth: 440)
            }
            .padding(32)
        }
    }

    private func choice(_ title: String, _ detail: String, _ symbol: String, _ id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: symbol).font(.title2).frame(width: 34).foregroundStyle(Ink.text)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.headline)
                    Text(detail).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
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
