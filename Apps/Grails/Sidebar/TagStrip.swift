import GrailsKit
import GrailsDesign
import SwiftUI

struct StripEntry: Identifiable {
    var tag: String
    var count: Int
    var active: Bool
    var id: String { tag }
}

extension AppModel {
    private static let stripLimit = 12

    /// What the strip offers for the view you are in (before the strip narrows it): the tags already on first, then the other tags its
    /// items carry (not ones every item has), pinned ones first and then the most common. Clicking another tab switches to it.
    var stripEntries: [StripEntry] {
        let active = stripTags.map { t in StripEntry(tag: t, count: viewTags.first { $0.tag == t }?.count ?? 0, active: true) }
        return active + narrowingTags.prefix(max(0, Self.stripLimit - active.count)).map { StripEntry(tag: $0.tag, count: $0.count, active: false) }
    }

    private var narrowingTags: [(tag: String, count: Int)] {
        let total = viewBaseCount
        let order = Dictionary(pinnedTags.enumerated().map { ($1, $0) }, uniquingKeysWith: { a, _ in a })
        return viewTags.filter { !stripTags.contains($0.tag) && $0.count < total }.sorted { a, b in
            switch (order[a.tag], order[b.tag]) {
            case let (x?, y?): return x < y
            case (.some, nil): return true
            case (nil, .some): return false
            default: return a.count != b.count ? a.count > b.count : a.tag < b.tag
            }
        }
    }

    /// Narrowing tags that didn't fit on the strip, for the + menu.
    var moreStripTags: [(tag: String, count: Int)] {
        let shown = Set(stripEntries.map(\.tag))
        return narrowingTags.filter { !shown.contains($0.tag) }
    }

    var stripVisible: Bool { shownSource != .trash && !stripEntries.isEmpty }

    func pinTag(_ tag: String) {
        guard !pinnedTags.contains(tag) else { return }
        pinnedTags.append(tag)
        savePinned()
    }

    func unpinTag(_ tag: String) {
        pinnedTags.removeAll { $0 == tag }
        savePinned()
    }

    func resetPinnedTags() { pinnedTags = []; savePinned() }

    private func savePinned() { UserDefaults.standard.set(pinnedTags, forKey: "pinnedTags.\(libraryID)") }

    /// Click: that tag alone (or off again if it is the only one). ⇧-click: add it to, or take it off, the ones already on.
    func tapStripTag(_ tag: String, extend: Bool) {
        if extend {
            if let i = stripTags.firstIndex(of: tag) { stripTags.remove(at: i) } else { stripTags.append(tag) }
        } else {
            stripTags = stripTags == [tag] ? [] : [tag]
        }
    }
}

/// A row of tag tabs under the top bar: one click narrows the view to that tag, "All" clears it.
struct TagStrip: View {
    var model: AppModel
    static let height: CGFloat = 36
    @Environment(\.grailsReduceMotion) private var reduceMotion

    var body: some View {
        // one tag on (or none): a single fill springs between tabs. ⇧-click can turn several on; each then carries its own fill.
        let single = model.stripTags.count <= 1
        HStack(spacing: 4) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 2) {
                    StripTab(label: "All", count: nil, selected: model.stripTags.isEmpty, tracked: true) { model.stripTags = [] }
                    ForEach(model.stripEntries) { e in
                        StripTab(label: e.tag, count: e.count, selected: e.active, tracked: single) {
                            model.tapStripTag(e.tag, extend: NSEvent.modifierFlags.contains(.shift))
                        }
                        .contextMenu {
                            if model.pinnedTags.contains(e.tag) { GrailsControl("Unpin") { model.unpinTag(e.tag) } }
                            else { GrailsControl("Pin to Front") { model.pinTag(e.tag) } }
                        }
                        .transition(.grailsChip(reduceMotion: reduceMotion))
                    }
                }
                .grailsSelectionTrack { RoundedRectangle(cornerRadius: Ink.radius, style: .continuous).fill(Ink.fillHover) }
                .animation(.grailsSpring(reduceMotion: reduceMotion), value: model.stripEntries.map(\.id))
            }
            if !model.moreStripTags.isEmpty {
                GrailsMenu {
                    ForEach(model.moreStripTags.prefix(40), id: \.tag) { t in
                        GrailsControl("\(t.tag)  \(t.count)") { model.tapStripTag(t.tag, extend: NSEvent.modifierFlags.contains(.shift)) }
                    }
                } label: { BarIcon(symbol: "ellipsis", size: 24) }
                    .help("More tags in this view")
                    .accessibilityIdentifier("strip-more")
            }
        }
        .padding(.horizontal, 12)
        .frame(height: Self.height)
        .accessibilityIdentifier("tag-strip")
    }
}

private struct StripTab: View {
    let label: String
    let count: Int?
    let selected: Bool
    /// The strip's one sliding fill marks this tab; otherwise the tab draws its own.
    var tracked = true
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        GrailsControl(action: action) {
            HStack(spacing: 5) {
                Text(label).font(.grailsBody(13)).foregroundStyle(selected || hovering ? Ink.text : Ink.secondary).lineLimit(1)
                if let count { Text("\(count)").font(.grailsCount(11)).foregroundStyle(Ink.secondary) }
            }
                .padding(.horizontal, 10).frame(height: 24)
                .background(RoundedRectangle(cornerRadius: Ink.radius, style: .continuous).fill(selected && !tracked ? Ink.fillHover : (hovering && !selected ? Ink.fill : Ink.clear)))
                .grailsSelectionTarget(selected && tracked)
                .contentShape(Rectangle())
        }
        .hoverState($hovering)
        .accessibilityLabel(label)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }
}
