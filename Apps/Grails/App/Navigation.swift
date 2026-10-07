import GrailsKit

/// A view you can come back to.
struct ViewSnapshot: Equatable {
    var source: Source
    var addedBy: String?
}

/// What the top bar shows when the view is a filter rather than a place: its name, with a ✕ to leave it.
struct ViewChip: Equatable {
    var label: String
    var symbol: String
}

extension AppModel {
    func pushHistory(_ s: ViewSnapshot) {
        guard viewHistory.last != s else { return }
        viewHistory.append(s)
        if viewHistory.count > 30 { viewHistory.removeFirst() }
    }

    /// One navigation = one history entry, however many settings it changes.
    private func navigate(source new: Source, addedBy who: String?) {
        let was = ViewSnapshot(source: source, addedBy: addedByFilter)
        guard was != ViewSnapshot(source: new, addedBy: who) else { return }
        pushHistory(was)
        restoringHistory = true
        defer { restoringHistory = false }
        searchText = ""
        filters = ViewFilters()
        addedByFilter = who
        source = new
    }

    func goBack() {
        guard let last = viewHistory.popLast() else { return }
        restoringHistory = true
        defer { restoringHistory = false }
        searchText = ""
        addedByFilter = last.addedBy
        source = last.source
    }

    /// Everything with this tag, across the library.
    func showTag(_ tag: String) { closePreview(); navigate(source: .tag(tag), addedBy: nil) }

    /// Everything this person added to the library.
    func showContributions(of who: String) { closePreview(); navigate(source: .all, addedBy: who) }

    func showCollection(_ id: String) { closePreview(); navigate(source: .collection(id), addedBy: nil) }

    var viewChip: ViewChip? {
        if case .tag(let t) = source { return ViewChip(label: "#\(t)", symbol: "number") }
        if let who = addedByFilter { return ViewChip(label: who, symbol: "person") }
        switch source {
        case .liked: return ViewChip(label: "Liked", symbol: "heart")
        case .mentions: return ViewChip(label: "For you", symbol: "at")
        case .untagged: return ViewChip(label: "Untagged", symbol: "tag.slash")
        default: return filters.isActive ? ViewChip(label: "Filtered", symbol: "line.3.horizontal.decrease") : nil
        }
    }

    /// The ✕ on the chip: back to where you were, or just drop the filters when that's all there is.
    func clearViewChip() {
        if case .tag = source { leaveFilterView(); return }
        if addedByFilter != nil || source == .liked || source == .untagged || source == .mentions { leaveFilterView(); return }
        filters = ViewFilters()
    }

    private func isFilterView(_ s: ViewSnapshot) -> Bool {
        if case .tag = s.source { return true }
        return s.addedBy != nil || s.source == .liked || s.source == .untagged || s.source == .mentions
    }

    /// Leaves the whole run of filter views at once (tag, then another tag, then a person…): back to the last place that wasn't one,
    /// or to All when there is none. ⌘[ still steps back one view at a time.
    private func leaveFilterView() {
        var target: ViewSnapshot?
        while let last = viewHistory.popLast() {
            if !isFilterView(last) { target = last; break }
        }
        restoringHistory = true
        defer { restoringHistory = false }
        searchText = ""
        addedByFilter = target?.addedBy
        source = target?.source ?? .all
    }
}
