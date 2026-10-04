import Foundation
import StashKit

/// Background auto-tagging. Runs Apple's on-device image classifier over items that haven't been tagged yet.
/// One run at a time; new work while one is running just makes it go round again.
extension AppModel {
    var autoTagEnabled: Bool {
        let env = ProcessInfo.processInfo.environment
        // Dev/UI runs point at throwaway libraries: stay out of them unless a test asks for tagging explicitly.
        if env["STASH_LIBRARY"] != nil, env["STASH_AUTOTAG_STUB"] == nil, env["STASH_AUTOTAG"] == nil { return false }
        return UserDefaults.standard.object(forKey: "autoTagNew") as? Bool ?? true
    }

    var autoTagOptions: ImageTaggerOptions {
        .sensitivity(UserDefaults.standard.object(forKey: "autoTagSensitivity") as? Double ?? 0.5)
    }

    private func makeAutoTagger(_ store: LibraryStore) -> AutoTagger {
        // STASH_AUTOTAG_STUB="a,b": every picture gets these tags (UI tests; no model needed).
        if let stub = ProcessInfo.processInfo.environment["STASH_AUTOTAG_STUB"] {
            let tags = stub.split(separator: ",").map { String($0) }
            return AutoTagger(store: store, options: autoTagOptions, classify: { _, _ in tags.map { TagSuggestion(tag: $0, confidence: 0.9) } })
        }
        return AutoTagger(store: store, options: autoTagOptions)
    }

    /// Tags what's waiting. `ids` forces exactly those items (even if done before). `everyone` includes teammates' items;
    /// by default only your own are tagged, so each Mac doesn't redo what the person who saved the item will do.
    func kickAutoTag(ids: [String]? = nil, everyone: Bool = false, announce: Bool = false) {
        guard let store else { return }
        if ids == nil, !everyone, !announce, !autoTagEnabled { return }
        autoTagSeenTotal = totalCount
        let previous = autoTagTask
        let handle = userHandle
        let tagger = makeAutoTagger(store)
        autoTagGeneration += 1
        let generation = autoTagGeneration
        let model = self
        autoTagTask = Task {
            await previous?.value
            guard !Task.isCancelled else { return }
            let summary = await tagger.run(addedBy: everyone ? nil : handle, ids: ids) { done, total in
                Task { @MainActor in
                    guard model.autoTagGeneration == generation else { return }
                    model.autoTagProgress = done < total ? (done, total) : nil
                    if done > 0, done % 6 == 0 { model.reloadSoon() }          // tags appear as they are added
                }
            }
            if model.autoTagGeneration == generation { self.autoTagProgress = nil; self.autoTagTask = nil }
            guard model.store === store else { return }
            await model.refreshAutoTagSkipped()
            if summary.tagsAdded > 0 || summary.pruned > 0 { await model.reload() }
            if announce {
                model.showToast(summary.tagsAdded > 0
                    ? "Added \(summary.tagsAdded) tag\(summary.tagsAdded == 1 ? "" : "s") to \(summary.tagged) item\(summary.tagged == 1 ? "" : "s")"
                    : "No new tags found")
            }
        }
    }

    func refreshAutoTagSkipped() async {
        guard let store else { autoTagSkipped = []; return }
        autoTagSkipped = await store.autoTagIgnored().sorted()
    }

    func resetAutoTagSkipped() {
        guard let store else { return }
        Task {
            try? await store.resetAutoTagIgnored()
            await refreshAutoTagSkipped()
            showToast("Skipped tags reset")
        }
    }

    func autoTagSelection() {
        guard !selection.isEmpty else { return }
        kickAutoTag(ids: Array(selection), announce: true)
    }

    func autoTagEverything() { kickAutoTag(everyone: true, announce: true) }

    func cancelAutoTag() {
        autoTagTask?.cancel()
        autoTagTask = nil
        autoTagProgress = nil
        autoTagGeneration += 1
    }
}
