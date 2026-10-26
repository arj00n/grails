import GrailsDesign
import GrailsKit
import SwiftUI

struct PromptCard: View {
    var model: AppModel
    let request: PromptRequest
    @State private var text = ""
    @State private var focused = false
    @State private var sent = false

    var body: some View {
        GrailsModal(title: request.title, subtitle: request.message.isEmpty ? nil : request.message, step: "prompt", onClose: { model.prompt = nil }) {
            GrailsFieldChrome(request.placeholder, focused: focused) {
                GrailsCommandField(
                    text: $text, placeholder: "", identifier: "prompt-field",
                    size: 15, onSubmit: submit, onEscape: { model.prompt = nil }, onFocus: { focused = $0 }
                )
                .frame(height: 22)
            }
        } footer: {
            HStack {
                Spacer()
                GrailsButton("Cancel", kind: .secondary) { model.prompt = nil }
                    .keyboardShortcut(.cancelAction)
                GrailsButton(request.confirmTitle, kind: .primary, identifier: "prompt-confirm", enabled: !text.trimmingCharacters(in: .whitespaces).isEmpty, action: submit)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .onAppear { text = request.initial }
    }

    private func submit() {
        let t = text.trimmingCharacters(in: .whitespaces)
        guard !sent, !t.isEmpty else { return }
        sent = true
        model.prompt = nil
        request.onSubmit(t)
    }
}

struct ConfirmCard: View {
    var model: AppModel
    let request: ConfirmRequest

    var body: some View {
        GrailsModal(title: request.title, step: "confirm", onClose: { model.confirm = nil }) {
            if !request.message.isEmpty {
                Text(request.message)
                    .font(.grailsBody(13))
                    .foregroundStyle(Ink.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } footer: {
            HStack {
                Spacer()
                GrailsButton("Cancel", kind: .secondary) { model.confirm = nil }
                    .keyboardShortcut(.cancelAction)
                GrailsButton(request.confirmTitle, kind: .primary) { model.confirm = nil
                    request.onConfirm() }
                .keyboardShortcut(.defaultAction)
                .accessibilityIdentifier("confirm-button")
            }
        }
    }
}

struct ToastView: View {
    let text: String
    var mark: LibraryNotice.Mark?

    var body: some View {
        // The mark's own symbol name and Holy Grail flag are what LibraryNoticeTests checks, so the screen cannot drift from them.
        Group {
            if let struck = mark?.holyGrailStruck {
                GrailsToast(text, holyGrailStruck: struck)
            } else {
                GrailsToast(text, symbol: mark?.symbolName ?? "checkmark.circle")
            }
        }
        .accessibilityIdentifier("toast")
    }
}
