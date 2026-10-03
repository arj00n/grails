import SwiftUI

/// Chips under the toolbar: narrow the current view to images / videos / GIFs / squares / liked, and sort it.
/// The chips scroll horizontally so the bar never demands more width than the grid has (with the info panel open the
/// grid can be narrower than the chips; a rigid bar there sends SwiftUI into a layout loop that AppKit aborts).
struct FilterBar: View {
    @Bindable var model: AppModel

    var body: some View {
        HStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    chip("Images", "photo", $model.filters.images, "filter-images")
                    chip("Videos", "film", $model.filters.videos, "filter-videos")
                    chip("GIFs", "livephoto", $model.filters.gifs, "filter-gifs")
                    chip("Square", "square", $model.filters.square, "filter-square")
                    chip("Liked", "heart", $model.filters.liked, "filter-liked")
                    if model.contributors.count > 1 {
                        Menu {
                            Button("Everyone") { model.addedByFilter = nil }
                            Divider()
                            ForEach(model.contributors, id: \.who) { c in
                                Button("\(c.who) (\(c.count.formatted()))") { model.addedByFilter = c.who }
                            }
                        } label: {
                            Label(model.addedByFilter ?? "Added by", systemImage: "person.2").font(.caption)
                        }
                        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                        .padding(.horizontal, 9).padding(.vertical, 4)
                        .background(model.addedByFilter != nil ? Color.accentColor.opacity(0.25) : Color.primary.opacity(0.07), in: Capsule())
                        .accessibilityIdentifier("filter-added-by")
                    }
                    if model.filters.isActive {
                        Button("Clear") { model.filters = ViewFilters() }.buttonStyle(.borderless).font(.caption)
                    }
                }
                .padding(.vertical, 1)
            }
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)

            Menu {
                Picker("Sort", selection: $model.sort) {
                    ForEach(SortChoice.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.inline)
            } label: {
                Image(systemName: "arrow.up.arrow.down")
            }
            .menuStyle(.borderlessButton).menuIndicator(.hidden)
            .frame(width: 26)
            .help("Sort: \(model.sort.label)")
            .accessibilityLabel("Sort: \(model.sort.label)")
            .accessibilityIdentifier("sort-menu")
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
        .frame(minWidth: 0, maxWidth: .infinity)
        .background(.bar)
    }

    private func chip(_ title: String, _ symbol: String, _ isOn: Binding<Bool>, _ id: String) -> some View {
        Button { isOn.wrappedValue.toggle() } label: {
            Label(title, systemImage: symbol).font(.caption)
                .padding(.horizontal, 9).padding(.vertical, 4)
                .background(isOn.wrappedValue ? Color.accentColor.opacity(0.25) : Color.primary.opacity(0.07), in: Capsule())
                .overlay(Capsule().strokeBorder(isOn.wrappedValue ? Color.accentColor : .clear))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
        .accessibilityAddTraits(isOn.wrappedValue ? .isSelected : [])
    }
}
