import GrailsDesign
import SwiftUI

struct PaletteRow: Identifiable {
    let id: String
    var title: String
    var subtitle: String? = nil
    var symbol: String
    var accessory: String? = nil
    var tint: Color? = nil
    /// Stay open after running (e.g. toggling several tags in a row)
    var keepOpen = false
    var run: @MainActor () -> Void
}

/// Spotlight-style panel: a text field over a keyboard-navigable list. Shared by ⌘K, tags and move-to-collection.
struct PaletteView: View {
    let placeholder: String
    var identifier = "palette"
    /// Bump to recompute rows without the query changing (after a tag toggle, say).
    var refreshToken = 0
    let rows: @MainActor (String) async -> [PaletteRow]
    let onClose: @MainActor () -> Void

    @State private var query = ""
    @State private var results: [PaletteRow] = []
    @State private var highlight = RowPointerHighlight()
    /// The query `results` were computed for. Rows are computed asynchronously, so a fast typist can press Return
    /// while `results` still belong to an earlier keystroke; submit must never act on those.
    @State private var resultsFor = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").font(ChromeFont.symbol(14, weight: .regular)).foregroundStyle(Ink.secondary)
                GrailsCommandField(
                    text: $query, placeholder: placeholder, identifier: "\(identifier)-field",
                    onSubmit: { runSelected() },
                    onMove: { d in updateHighlight { $0.move(by: d, count: results.count) } },
                    onEscape: { onClose() }
                )
                .frame(height: 24)
            }
            .padding(14)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(Array(results.enumerated()), id: \.element.id) { i, row in
                            rowView(row, highlighted: i == highlight.index)
                                .id(row.id)
                                .rowPointerHighlight(i, highlight: $highlight)
                                .grailsTapPress { updateHighlight { $0.select(i) }; runSelected(at: i) }
                        }
                        if results.isEmpty {
                            Text("No matches").font(.grailsBody(13)).foregroundStyle(Ink.secondary).padding(20)
                        }
                    }
                    .padding(6)
                }
                .frame(maxHeight: 380)
                .onChange(of: highlight.index) { _, new in
                    if results.indices.contains(new) { proxy.scrollTo(results[new].id) }
                }
            }
        }
        .frame(maxWidth: 600)
        .surfaceCard()
        .task(id: "\(query)|\(refreshToken)") {
            let r = await rows(query)
            guard !Task.isCancelled else { return }
            results = r
            resultsFor = query
            updateHighlight { $0.clamp(to: r.count) }
        }
        .onChange(of: query) { updateHighlight { $0.reset() } }
    }

    private func updateHighlight(_ change: (inout RowPointerHighlight) -> Void) {
        var next = highlight
        change(&next)
        guard next != highlight else { return }
        highlight = next
    }

    private func rowView(_ row: PaletteRow, highlighted: Bool) -> some View {
        HStack(spacing: 10) {
            Group { if row.symbol == CanonMark.symbolName { CanonMark(size: 13) } else { Image(systemName: row.symbol) } }.frame(width: 22).foregroundStyle(row.tint.map { AnyShapeStyle($0) } ?? AnyShapeStyle(Ink.secondary))
            VStack(alignment: .leading, spacing: 1) {
                Text(row.title).font(.grailsBody(13)).lineLimit(1)
                if let sub = row.subtitle { Text(sub).font(.grailsBody(12)).foregroundStyle(Ink.secondary).lineLimit(1) }
            }
            Spacer()
            if let a = row.accessory { Text(a).font(.grailsBody(13)).foregroundStyle(Ink.secondary).monospacedDigit() }
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(InkWash(ink: highlighted ? Ink.fillHover : Ink.clear).clipShape(RoundedRectangle(cornerRadius: Ink.rowRadius, style: .continuous)))
        .contentShape(Rectangle())
    }

    private func runSelected(at index: Int? = nil) {
        if resultsFor == query {
            run(at: index ?? highlight.index, in: results)
        } else {
            // Results are stale: compute rows for exactly what's typed, then run the top one (typing resets the highlight to the top).
            let typed = query
            Task {
                let fresh = await rows(typed)
                guard typed == query else { return }
                run(at: 0, in: fresh)
            }
        }
    }

    private func run(at index: Int, in rows: [PaletteRow]) {
        guard rows.indices.contains(index) else { return }
        let row = rows[index]
        row.run()
        if row.keepOpen { query = ""; updateHighlight { $0.reset() } } else { onClose() }
    }
}
