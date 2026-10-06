import AppKit
import GrailsDesign
import SwiftUI

/// Feedback goes to a person, not to a server: it opens the person's own mail app with the message written, addressed to the support
/// address. The only extra thing it can carry is the app and macOS version, and only if they leave that on.
enum FeedbackMail {
    static let address = "hi@arjoon.xyz"

    static func diagnostics() -> String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        var sys = utsname(); uname(&sys)
        let arch = withUnsafeBytes(of: &sys.machine) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
        return "Grails \(version) (\(build)) · macOS \(ProcessInfo.processInfo.operatingSystemVersionString) · \(arch)"
    }

    /// `mailto:` encoded so any mail app reads it the same (RFC 6068).
    static func url(message: String, includeDiagnostics: Bool) -> URL? {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
        func enc(_ s: String) -> String { s.addingPercentEncoding(withAllowedCharacters: allowed) ?? "" }
        var body = message.trimmingCharacters(in: .whitespacesAndNewlines)
        if includeDiagnostics { body += "\n\n—\n" + diagnostics() }
        body = body.replacingOccurrences(of: "\n", with: "\r\n")
        return URL(string: "mailto:\(address)?subject=\(enc("Grails feedback"))&body=\(enc(body))")
    }

    /// The whole message as plain text, for when there is no mail app to open.
    static func plainText(message: String, includeDiagnostics: Bool) -> String {
        var t = message.trimmingCharacters(in: .whitespacesAndNewlines)
        if includeDiagnostics { t += "\n\n—\n" + diagnostics() }
        return t
    }
}

/// One card over the window: what's on your mind, a switch for the version line, Send.
struct FeedbackCard: View {
    var model: AppModel
    @State private var text = ""
    @State private var includeDiagnostics = true
    @State private var shown = false
    @FocusState private var focused: Bool

    private var empty: Bool { text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        ZStack {
            Ink.canvas.opacity(0.55).ignoresSafeArea().onTapGesture(perform: close)
            VStack(alignment: .leading, spacing: 14) {
                Text("FEEDBACK").font(.grailsDisplay(16)).foregroundStyle(Ink.text)
                ZStack(alignment: .topLeading) {
                    TextEditor(text: $text)
                        .font(.grailsBody(13)).scrollContentBackground(.hidden).focused($focused).padding(6)
                        .accessibilityIdentifier("feedback-field")
                    if text.isEmpty {
                        Text("What's working, what isn't, what you wish it did").font(.grailsBody(13)).foregroundStyle(Ink.secondary)
                            .padding(.leading, 11).padding(.top, 6).allowsHitTesting(false)
                    }
                }
                .frame(height: 140)
                .background(Ink.fill, in: RoundedRectangle(cornerRadius: Ink.radius, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Ink.radius, style: .continuous).strokeBorder(focused ? Ink.focus : .clear, lineWidth: 1))
                Toggle("Include app and macOS version", isOn: $includeDiagnostics).toggleStyle(.checkbox).font(.grailsBody(12)).foregroundStyle(Ink.secondary)
                HStack(spacing: 12) {
                    Spacer()
                    Button("Cancel", action: close).buttonStyle(.plain).font(.grailsBody(13)).foregroundStyle(Ink.secondary).keyboardShortcut(.cancelAction)
                    Button("Send", action: send).buttonStyle(PrimaryButtonStyle()).disabled(empty).keyboardShortcut(.return, modifiers: .command)
                        .accessibilityIdentifier("feedback-send")
                }
            }
            .padding(20)
            .frame(width: 420)
            .surfaceCard()
            .offset(y: shown || reduceMotionOn ? 0 : 8)
            .opacity(shown ? 1 : 0)
        }
        .onAppear {
            focused = true
            withAnimation(.timingCurve(0.22, 1, 0.36, 1, duration: reduceMotionOn ? 0.12 : 0.24)) { shown = true }
        }
        .accessibilityIdentifier("feedback")
    }

    private func close() { withAnimation(.easeOut(duration: 0.18)) { model.feedbackOpen = false } }

    private func send() {
        guard !empty else { return }
        if let url = FeedbackMail.url(message: text, includeDiagnostics: includeDiagnostics), NSWorkspace.shared.open(url) {
            model.showToast("Opened in your mail app")
        } else {
            // no mail app: the message goes on the clipboard, ready to paste into whatever they do use
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(FeedbackMail.plainText(message: text, includeDiagnostics: includeDiagnostics), forType: .string)
            model.showToast("Copied. Send it to \(FeedbackMail.address)")
        }
        close()
    }
}
