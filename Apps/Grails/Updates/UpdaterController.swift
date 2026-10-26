import Foundation
import Observation
import Sparkle

/// Sparkle behind one object: the app menu's Check for Updates… and the Updates row in Settings.
/// Feed, key and schedule live in Info.plist (`SUFeedURL`, `SUPublicEDKey`, …), set from Config/Base.xcconfig; see SECURITY.md.
/// A build with an empty feed URL or key (a fork that ships no updates) never starts Sparkle.
@MainActor @Observable
final class UpdaterController {
    static let shared = UpdaterController()

    /// Nil in the headless demo modes (any `GRAILS_*_DEMO`) and in a build with no feed: they never check or show an update window.
    @ObservationIgnored private let controller: SPUStandardUpdaterController?
    @ObservationIgnored private var observations: [NSKeyValueObservation] = []

    private(set) var canCheck = false
    private(set) var lastChecked: Date?
    private(set) var checksAutomatically = false
    private(set) var installsAutomatically = false

    var isAvailable: Bool { controller != nil }

    private init() {
        let demo = ProcessInfo.processInfo.environment.keys.contains { $0.hasPrefix("GRAILS_") && $0.hasSuffix("_DEMO") }
        guard !demo, Self.hasFeed else { controller = nil; return }
        let controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
        self.controller = controller
        let updater = controller.updater
        refresh()
        observations = [
            updater.observe(\.canCheckForUpdates) { [weak self] _, _ in Task { @MainActor in self?.refresh() } },
            updater.observe(\.lastUpdateCheckDate) { [weak self] _, _ in Task { @MainActor in self?.refresh() } },
            updater.observe(\.automaticallyChecksForUpdates) { [weak self] _, _ in Task { @MainActor in self?.refresh() } },
            updater.observe(\.automaticallyDownloadsUpdates) { [weak self] _, _ in Task { @MainActor in self?.refresh() } },
        ]
    }

    /// Both the feed URL and the public key must be set; Sparkle refuses an update it can't verify anyway.
    static var hasFeed: Bool {
        func value(_ key: String) -> String {
            ((Bundle.main.object(forInfoDictionaryKey: key) as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let feed = value("SUFeedURL"), key = value("SUPublicEDKey")
        return URL(string: feed)?.scheme == "https" && !key.isEmpty
    }

    /// Touch at launch so the updater starts (and schedules its daily check) before any window opens.
    static func start() { _ = shared }

    func checkForUpdates() { controller?.checkForUpdates(nil) }

    func setChecksAutomatically(_ on: Bool) {
        controller?.updater.automaticallyChecksForUpdates = on
        checksAutomatically = on
    }

    /// On by default (`SUAutomaticallyUpdate`): a signed update downloads quietly and installs when Grails quits.
    func setInstallsAutomatically(_ on: Bool) {
        controller?.updater.automaticallyDownloadsUpdates = on
        installsAutomatically = on
    }

    private func refresh() {
        guard let updater = controller?.updater else { return }
        canCheck = updater.canCheckForUpdates
        lastChecked = updater.lastUpdateCheckDate
        checksAutomatically = updater.automaticallyChecksForUpdates
        installsAutomatically = updater.automaticallyDownloadsUpdates
    }
}
