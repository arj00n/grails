import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct Dropped {
    var itemIDs: [String] = []
    var collectionIDs: [String] = []
    var files: [URL] = []
}

/// Reads whatever a drop carries. Items dragged out of the grid also carry their file URL; the item ids win, so a
/// drag from the grid is never mistaken for new files to import.
enum DropLoader {
    static let accepted: [UTType] = [.grailsItems, .grailsCollection, .fileURL]

    @MainActor
    static func load(_ providers: [NSItemProvider]) async -> Dropped {
        var out = Dropped()
        for p in providers {
            if p.hasItemConformingToTypeIdentifier(UTType.grailsItems.identifier) {
                if let data = await data(p, UTType.grailsItems.identifier), let ids = try? JSONDecoder().decode([String].self, from: data) {
                    out.itemIDs.append(contentsOf: ids)
                }
            } else if p.hasItemConformingToTypeIdentifier(UTType.grailsCollection.identifier) {
                if let data = await data(p, UTType.grailsCollection.identifier), let s = String(data: data, encoding: .utf8) {
                    out.collectionIDs.append(s)
                }
            } else if p.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                if let data = await data(p, UTType.fileURL.identifier), let url = URL(dataRepresentation: data, relativeTo: nil) {
                    out.files.append(url)
                }
            }
        }
        return out
    }

    @MainActor private static func data(_ p: NSItemProvider, _ type: String) async -> Data? {
        await withCheckedContinuation { cont in
            p.loadDataRepresentation(forTypeIdentifier: type) { data, _ in cont.resume(returning: data) }
        }
    }
}

/// The library's content area takes files from outside. Tiles dragged out of the grid are refused, so letting go anywhere on the content
/// sends the picture sliding back to where it was, instead of vanishing as if something had been dropped.
struct ContentDrop: DropDelegate {
    var model: AppModel
    @Binding var targeted: Bool

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [.fileURL]) && !info.hasItemsConforming(to: [.grailsItems, .grailsCollection])
    }

    func dropEntered(info: DropInfo) { targeted = true }
    func dropExited(info: DropInfo) { targeted = false }
    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .copy) }

    func performDrop(info: DropInfo) -> Bool {
        targeted = false
        let providers = info.itemProviders(for: [.fileURL])
        Task { @MainActor in
            let d = await DropLoader.load(providers)
            if !d.files.isEmpty { await model.importFiles(d.files) }
        }
        return true
    }
}
