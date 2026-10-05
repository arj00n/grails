import Foundation
import Observation
import Sparkle

/// Sparkle behind one object: the app menu's Check for Updates… and the Updates row in Settings.
/// Feed, key and schedule live in Info.plist (`SUFeedURL`, `SUPublicEDKey`, …); see docs/UPDATES.md.
@MainActor @Observable
final class UpdaterController {
    static let shared = UpdaterController()

    /// Nil in the headless demo modes (any `GRAILS_*_DEMO`): they never check or show an update window.
    @ObservationIgnored private let controller: SPUStandardUpdaterController?
    @ObservationIgnored private var observations: [NSKeyValueObservation] = []

    private(set) var canCheck = false
    private(set) var lastChecked: Date?
    private(set) var checksAutomatically = false

    var isAvailable: Bool { controller != nil }

    private init() {
        let demo = ProcessInfo.processInfo.environment.keys.contains { $0.hasPrefix("GRAILS_") && $0.hasSuffix("_DEMO") }
        guard !demo else { controller = nil; return }
        let controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
        self.controller = controller
        let updater = controller.updater
        refresh()
        observations = [
            updater.observe(\.canCheckForUpdates) { [weak self] _, _ in Task { @MainActor in self?.refresh() } },
            updater.observe(\.lastUpdateCheckDate) { [weak self] _, _ in Task { @MainActor in self?.refresh() } },
            updater.observe(\.automaticallyChecksForUpdates) { [weak self] _, _ in Task { @MainActor in self?.refresh() } },
        ]
    }

    /// Touch at launch so the updater starts (and schedules its daily check) before any window opens.
    static func start() { _ = shared }

    func checkForUpdates() { controller?.checkForUpdates(nil) }

    func setChecksAutomatically(_ on: Bool) {
        controller?.updater.automaticallyChecksForUpdates = on
        checksAutomatically = on
    }

    private func refresh() {
        guard let updater = controller?.updater else { return }
        canCheck = updater.canCheckForUpdates
        lastChecked = updater.lastUpdateCheckDate
        checksAutomatically = updater.automaticallyChecksForUpdates
    }
}
