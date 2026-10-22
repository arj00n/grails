import AppKit
import GrailsKit

extension AppModel {
    func refreshExtensionNudgeContext() {
        extensionNudgeBrowser = Self.detectedExtensionBrowser()
        SafariExtension.refreshEnabled { [weak self] enabled in
            self?.safariExtensionEnabled = enabled
        }
    }

    func extensionNudgeOffer(now: Date = Date()) -> ExtensionNudgeOffer? {
        extensionNudge.offer(safariAvailable: SafariExtension.isAvailable, browser: extensionNudgeBrowser, safariEnabled: safariExtensionEnabled, now: now)
    }

    func snoozeExtensionNudge(now: Date = Date()) {
        var record = extensionNudge
        record.snooze(now: now)
        record.save()
        extensionNudge = record
    }

    func rememberExtensionPair(_ origin: PairingOrigin) {
        var record = extensionNudge
        record.note(origin)
        record.save()
        extensionNudge = record
    }

    static func detectedExtensionBrowser() -> ExtensionNudgeBrowser {
        guard let probe = URL(string: "https://example.com"),
              let appURL = NSWorkspace.shared.urlForApplication(toOpen: probe),
              let id = Bundle(url: appURL)?.bundleIdentifier else { return .other }
        if id == "com.apple.Safari" { return .safari }
        if ChromiumBrowser.known.contains(where: { $0.id == id }) { return .chromium }
        return .other
    }
}
