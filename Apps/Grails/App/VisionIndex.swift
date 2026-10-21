import AppKit
import GrailsKit

extension AppModel {
    var skipsVisionOnFixtureLibrary: Bool {
        let env = ProcessInfo.processInfo.environment
        return env["GRAILS_LIBRARY"] != nil && env["GRAILS_VISION"] == nil
    }

    func kickVision() {
        guard !skipsVisionOnFixtureLibrary, let store, visionTask == nil else { return }
        let model = self
        visionTask = Task.detached(priority: .utility) {
            let count = await VisionBackfill.run(store: store)
            await MainActor.run {
                model.visionTask = nil
                if count > 0 { model.reloadSoon() }
            }
        }
    }

    func findSimilar(to id: String) {
        guard let store else { return }
        let model = self
        Task.detached(priority: .userInitiated) {
            let ids = (try? await VisionBackfill.similarIDs(to: id, store: store)) ?? []
            await MainActor.run {
                if ids.isEmpty {
                    model.showToast("Nothing similar yet")
                    return
                }
                model.showSimilar(ids)
            }
        }
    }

    func showSimilar(_ ids: [String]) {
        closePreview()
        closePanel()
        if source != .all { source = .all }
        if !searchText.isEmpty { searchText = "" }
        similarOrder = ids
        reloadSoon()
    }

    func findByColor(_ hex: String) {
        closePreview()
        closePanel()
        similarOrder = nil
        let token = SearchText.normalizeHex(hex) ?? hex
        searchText = "color:\(token)"
    }
}
