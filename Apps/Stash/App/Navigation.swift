import StashKit

/// Jumps from a detail (a tag chip, a name) to the view it names.
extension AppModel {
    /// Everything with this tag, across the library.
    func showTag(_ tag: String) {
        closePreview()
        searchText = ""
        filters = ViewFilters()
        addedByFilter = nil
        source = .tag(tag)
    }

    /// Everything this person added to the library.
    func showContributions(of who: String) {
        closePreview()
        searchText = ""
        filters = ViewFilters()
        source = .all
        addedByFilter = who
    }

    func showCollection(_ id: String) {
        closePreview()
        searchText = ""
        filters = ViewFilters()
        addedByFilter = nil
        source = .collection(id)
    }
}
