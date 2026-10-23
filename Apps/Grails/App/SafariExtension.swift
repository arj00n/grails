import Foundation
import SafariServices

/// Whether this build ships the Safari web extension.
///
/// True only when Info.plist key `GRAILS_SAFARI_EXTENSION` is the string `YES`.
/// That key is the build setting of the same name (`Config/Base.xcconfig`, default `NO`).
enum SafariExtension {
    static let infoKey = "GRAILS_SAFARI_EXTENSION"

    static var isAvailable: Bool {
        (Bundle.main.object(forInfoDictionaryKey: infoKey) as? String) == "YES"
    }

    static var bundleIdentifier: String {
        (Bundle.main.bundleIdentifier ?? "") + ".safari"
    }

    static func showPreferences() {
        SFSafariApplication.showPreferencesForExtension(withIdentifier: bundleIdentifier) { _ in }
    }

    /// Skips the Safari state lookup while `isAvailable` is false.
    static func refreshEnabled(_ apply: @escaping @MainActor (Bool) -> Void) {
        guard isAvailable else {
            Task { @MainActor in apply(false) }
            return
        }
        SFSafariExtensionManager.getStateOfSafariExtension(withIdentifier: bundleIdentifier) { state, _ in
            let enabled = state?.isEnabled == true
            Task { @MainActor in apply(enabled) }
        }
    }
}
