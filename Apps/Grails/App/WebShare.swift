import AppKit
import GrailsKit

/// Share a view as a web page: a folder (and zip) anyone can open in a browser, with no Grails and no login.
extension AppModel {
    func exportWebPage(selectionOnly: Bool = false) {
        guard boardImportTask == nil else { showToast("Another job is already running"); return }
        guard let store else { return }
        let ids = selectionOnly ? items.filter { selection.contains($0.id) }.map(\.id) : items.map(\.id)
        guard !ids.isEmpty else { showToast("Nothing to export"); return }

        var name = source == .all && !isSearching ? libraryName : title.replacingOccurrences(of: "#", with: "")
        if selectionOnly { name += " selection" }
        let useClusters = !selectionOnly && !isSearching && !canvasIsDerived && canvasBoardKey != nil
        let clusters: [CanvasCluster] = !useClusters ? [] : (sectionKey == canvasBoardKey ? sectionClusters : (canvasLoadedKey == canvasBoardKey ? canvasClusters : []))

        let p = NSOpenPanel()
        p.canChooseDirectories = true
        p.canChooseFiles = false
        p.canCreateDirectories = true
        p.prompt = "Export Here"
        p.message = "Choose where to save “\(name)”"
        guard p.runModal() == .OK, let parent = p.url else { return }

        let label = "Exporting “\(name)”"
        boardImport = (label, 0, ids.count)
        let model = self
        boardImportTask = Task {
            defer { model.boardImport = nil; model.boardImportTask = nil }
            do {
                let report = try await store.exportWebPage(title: name, ids: ids, clusters: clusters, to: parent) { done, total in
                    Task { @MainActor in model.boardImport = (label, done, total) }
                }
                NSWorkspace.shared.activateFileViewerSelecting([report.zip ?? report.folder])
                var text = "Exported \(report.exported) item\(report.exported == 1 ? "" : "s")"
                if report.thumbnailOnly > 0 { text += ", \(report.thumbnailOnly) as thumbnails (not downloaded on this Mac)" }
                model.showToast(text, seconds: 5)
            } catch is CancellationError {
            } catch {
                model.errorMessage = "Couldn't export: \((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)"
            }
        }
    }
}
