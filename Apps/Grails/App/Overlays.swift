import SwiftUI

struct PromptCard: View {
    var model: AppModel
    let request: PromptRequest
    @State private var text = ""

    var body: some View {
        ZStack {
            Color.black.opacity(0.45).ignoresSafeArea().onTapGesture { model.prompt = nil }
            VStack(alignment: .leading, spacing: 12) {
                Text(request.title).font(.headline)
                if !request.message.isEmpty { Text(request.message).font(.callout).foregroundStyle(.secondary) }
                FocusedTextField(
                    text: $text, placeholder: request.placeholder, identifier: "prompt-field",
                    font: .systemFont(ofSize: 15), onSubmit: submit, onEscape: { model.prompt = nil }
                )
                .frame(height: 22)
                .padding(.horizontal, 8).padding(.vertical, 5)
                .background(Ink.fill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                HStack {
                    Spacer()
                    Button("Cancel") { model.prompt = nil }.keyboardShortcut(.cancelAction)
                    Button(request.confirmTitle, action: submit).keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
                        .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
                        .accessibilityIdentifier("prompt-confirm")
                }
            }
            .padding(18)
            .frame(maxWidth: 380)
            .glassCard(radius: 22)
        }
        .onAppear { text = request.initial }
    }

    private func submit() {
        let t = text.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return }
        model.prompt = nil
        request.onSubmit(t)
    }
}

struct ConfirmCard: View {
    var model: AppModel
    let request: ConfirmRequest

    var body: some View {
        ZStack {
            Color.black.opacity(0.45).ignoresSafeArea().onTapGesture { model.confirm = nil }
            VStack(alignment: .leading, spacing: 12) {
                Text(request.title).font(.headline)
                Text(request.message).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                HStack {
                    Spacer()
                    Button("Cancel") { model.confirm = nil }.keyboardShortcut(.cancelAction)
                    Button(request.confirmTitle, role: request.destructive ? .destructive : nil) {
                        model.confirm = nil
                        request.onConfirm()
                    }
                    .keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("confirm-button")
                }
            }
            .padding(18)
            .frame(maxWidth: 400)
            .glassCard(radius: 22)
        }
    }
}

struct ToastView: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.callout)
            .padding(.horizontal, 14).padding(.vertical, 8)
            .glassPill()
            .accessibilityIdentifier("toast")
    }
}
