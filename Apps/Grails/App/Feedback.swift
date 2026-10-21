import AppKit
import GrailsDesign
import SwiftUI

/// Feedback goes to a person, not to a server: it opens the person's own mail app with the message written, addressed to the support
/// address. The only extra thing it can carry is the app and macOS version, and only if they leave that on.
enum FeedbackMail {
    /// `GRAILS_FEEDBACK_EMAIL` via Info.plist. Empty in a fork that sets none: the mail opens with no recipient.
    static let address = ((Bundle.main.object(forInfoDictionaryKey: "GrailsFeedbackEmail") as? String) ?? "")
        .trimmingCharacters(in: .whitespacesAndNewlines)

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

/// One modal over whatever asked for it (Settings, the library, ⌘K): what's on your mind, a switch for the version line, Send.
struct FeedbackCard: View {
    var model: AppModel
    @State private var text = ""
    @State private var includeDiagnostics = true
    @FocusState private var focused: Bool

    private var empty: Bool { text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        GrailsModal(title: "Feedback", step: "feedback", onClose: close) {
            VStack(alignment: .leading, spacing: CGFloat(Space.sm)) {
                GrailsFieldChrome("Message", focused: focused) {
                    GrailsMultilineField("What's working, what isn't, what you wish it did", text: $text, identifier: "feedback-field", focused: $focused)
                        .frame(height: 140)
                }
                Toggle("Include app and macOS version", isOn: $includeDiagnostics).toggleStyle(GrailsToggleStyle()).font(.grailsBody(12)).foregroundStyle(Ink.secondary)
            }
        } footer: {
            HStack(spacing: CGFloat(Space.sm)) {
                Spacer()
                GrailsButton("Cancel", kind: .secondary, action: close).keyboardShortcut(.cancelAction)
                GrailsButton("Send", kind: .primary, identifier: "feedback-send", enabled: !empty, action: send).keyboardShortcut(.return, modifiers: .command)
            }
        }
        .onAppear { focused = true }
        .accessibilityIdentifier("feedback")
    }

    private func close() { withAnimation(.grailsQuick) { model.feedbackOpen = false } }

    private func send() {
        guard !empty else { return }
        if let url = FeedbackMail.url(message: text, includeDiagnostics: includeDiagnostics), NSWorkspace.shared.open(url) {
            model.showToast("Opened in your mail app")
        } else {
            // no mail app: the message goes on the clipboard, ready to paste into whatever they do use
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(FeedbackMail.plainText(message: text, includeDiagnostics: includeDiagnostics), forType: .string)
            model.showToast(FeedbackMail.address.isEmpty ? "Copied" : "Copied. Send it to \(FeedbackMail.address)")
        }
        close()
    }
}
