import GrailsKit
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

    var stripVisible: Bool { source != .trash && !stripEntries.isEmpty }

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

    var body: some View {
        HStack(spacing: 4) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 2) {
                    StripTab(label: "All", count: nil, selected: model.stripTags.isEmpty) { model.stripTags = [] }
                    ForEach(model.stripEntries) { e in
                        StripTab(label: e.tag, count: e.count, selected: e.active) {
                            model.tapStripTag(e.tag, extend: NSEvent.modifierFlags.contains(.shift))
                        }
                        .contextMenu {
                            if model.pinnedTags.contains(e.tag) { Button("Unpin") { model.unpinTag(e.tag) } }
                            else { Button("Pin to Front") { model.pinTag(e.tag) } }
                        }
                    }
                }
            }
            if !model.moreStripTags.isEmpty {
                Menu {
                    ForEach(model.moreStripTags.prefix(40), id: \.tag) { t in
                        Button("\(t.tag)  \(t.count)") { model.tapStripTag(t.tag, extend: NSEvent.modifierFlags.contains(.shift)) }
                    }
                } label: { BarIcon(symbol: "ellipsis", size: 24) }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
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
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Text(label).font(.grailsBody(13)).foregroundStyle(selected || hovering ? Ink.text : Ink.secondary).lineLimit(1)
                if let count { Text("\(count)").font(.grailsBody(11)).monospacedDigit().foregroundStyle(Ink.secondary) }
            }
                .padding(.horizontal, 10).frame(height: 24)
                .background(RoundedRectangle(cornerRadius: Ink.radius, style: .continuous).fill(selected ? Ink.fillHover : (hovering ? Ink.fill : .clear)))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hoverState($hovering)
        .accessibilityLabel(label)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }
}
