import AppKit
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
