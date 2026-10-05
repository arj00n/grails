import GrailsKit
import SwiftUI

extension AppModel {
    /// What the strip shows: the pinned tags that still exist, or the most used tags until some are pinned.
    var stripTagList: [String] {
        let known = Set(tags.map(\.tag))
        let pinned = pinnedTags.filter(known.contains)
        return pinned.isEmpty ? tags.prefix(8).map(\.tag) : pinned
    }

    var stripVisible: Bool { !tags.isEmpty && source != .trash }

    func pinTag(_ tag: String) {
        guard !pinnedTags.contains(tag) else { return }
        // pinning from the "most used" default keeps what you were looking at, then adds yours
        pinnedTags = (pinnedTags.isEmpty ? stripTagList : pinnedTags) + [tag]
        savePinned()
    }

    func unpinTag(_ tag: String) {
        pinnedTags = (pinnedTags.isEmpty ? stripTagList : pinnedTags).filter { $0 != tag }
        stripTags.removeAll { $0 == tag }
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
                    StripTab(label: "All", selected: model.stripTags.isEmpty) { model.stripTags = [] }
                    ForEach(model.stripTagList, id: \.self) { t in
                        StripTab(label: t, selected: model.stripTags.contains(t)) {
                            model.tapStripTag(t, extend: NSEvent.modifierFlags.contains(.shift))
                        }
                        .contextMenu { Button("Remove from Strip") { model.unpinTag(t) } }
                    }
                }
            }
            Menu {
                let shown = Set(model.stripTagList)
                ForEach(model.tags.filter { !shown.contains($0.tag) }.prefix(40), id: \.tag) { t in
                    Button(t.tag) { model.pinTag(t.tag) }
                }
                if !model.pinnedTags.isEmpty {
                    Divider()
                    Button("Show Most Used") { model.resetPinnedTags() }
                }
            } label: { BarIcon(symbol: "plus", size: 24) }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                .help("Pin a tag")
                .accessibilityIdentifier("strip-add")
        }
        .padding(.horizontal, 12)
        .frame(height: Self.height)
        .accessibilityIdentifier("tag-strip")
    }
}

private struct StripTab: View {
    let label: String
    let selected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.grailsBody(13))
                .foregroundStyle(selected || hovering ? Ink.text : Ink.secondary)
                .lineLimit(1)
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
