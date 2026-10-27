import GrailsKit

/// One titled block of the grid: a canvas cluster, in the order you arranged it.
struct GridSection: Equatable {
    let id: String
    let title: String
    var ids: [String]
    var collapsed = false
}

extension AppModel {
    /// Reads this view's canvas clusters (only when the view changed, or `forceRead`), then works out the grid's sections.
    func refreshSections(forceRead: Bool = false) async {
        guard let store, let key = canvasBoardKey else {
            sectionClusters = []; sectionKey = nil
            rebuildSections()
            return
        }
        // a folder board follows its folders, which any reload may have changed
        if folderBoard != nil {
            if let clusters = await folderClusters(), key == canvasBoardKey {
                sectionClusters = clusters; sectionKey = key
                if viewMode == .canvas, canvasLoadedKey == key, clusters != canvasClusters { canvasClusters = clusters; bumpCanvasVersion() }
            }
            rebuildSections()
            return
        }
        if forceRead || sectionKey != key {
            let board = await store.canvasBoard(key: key)
            // a board from before clusters has one cluster at most, which never makes sections
            sectionClusters = board?.clusters ?? []
            sectionKey = key
        }
        rebuildSections()
    }

    /// Sections show when the board has two or more clusters and the grid is in its natural order (not searching, not
    /// re-sorted); items no cluster holds yet join the first one.
    func rebuildSections() {
        var next: [GridSection]?
        if !canvasIsDerived, sort == .newest, sectionKey == canvasBoardKey, sectionClusters.count >= 2 {
            let visible = Set(items.map(\.id))
            var seen = Set<String>()
            var sections: [GridSection] = []
            // on a folder board a picture in two folders is in both sections, as a second tile (see `TileKey`)
            for c in folderBoard == nil ? sectionClusters : TileKey.keyed(sectionClusters) {
                let ids = c.items.filter { visible.contains(TileKey.item($0)) && !seen.contains($0) }
                seen.formUnion(ids)
                sections.append(GridSection(id: c.id, title: c.title, ids: ids, collapsed: c.collapsed))
            }
            let orphans = items.map(\.id).filter { !seen.contains($0) }
            if !orphans.isEmpty { sections[0].ids += orphans }
            sections = sections.filter { !$0.ids.isEmpty }
            if sections.count >= 2 || sections.contains(where: { !$0.title.isEmpty }) { next = sections }
        }
        if next != gridSections { gridSections = next; sectionsVersion += 1 }
    }
}
