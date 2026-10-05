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
    @State private var selected = 0
    /// The query `results` were computed for. Rows are computed asynchronously, so a fast typist can press Return
    /// while `results` still belong to an earlier keystroke; submit must never act on those.
    @State private var resultsFor = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                FocusedTextField(
                    text: $query, placeholder: placeholder, identifier: "\(identifier)-field",
                    onSubmit: { runSelected() },
                    onMove: { d in selected = min(max(results.count - 1, 0), max(0, selected + d)) },
                    onEscape: { onClose() }
                )
                .frame(height: 24)
            }
            .padding(14)
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(Array(results.enumerated()), id: \.element.id) { i, row in
                            rowView(row, highlighted: i == selected)
                                .id(row.id)
                                .onTapGesture { selected = i; runSelected() }
                        }
                        if results.isEmpty {
                            Text("No matches").foregroundStyle(.secondary).padding(20)
                        }
                    }
                    .padding(6)
                }
                .frame(maxHeight: 380)
                .onChange(of: selected) { _, new in
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
            selected = min(selected, max(r.count - 1, 0))
        }
        .onChange(of: query) { selected = 0 }
    }

    private func rowView(_ row: PaletteRow, highlighted: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: row.symbol).frame(width: 22).foregroundStyle(row.tint ?? Ink.secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(row.title).lineLimit(1)
                if let sub = row.subtitle { Text(sub).font(.grailsBody(11)).foregroundStyle(.secondary).lineLimit(1) }
            }
            Spacer()
            if let a = row.accessory { Text(a).font(.grailsBody(13)).foregroundStyle(.secondary).monospacedDigit() }
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(highlighted ? Ink.fillHover : .clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .contentShape(Rectangle())
    }

    private func runSelected() {
        if resultsFor == query {
            run(at: selected, in: results)
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
        if row.keepOpen { query = ""; selected = 0 } else { onClose() }
    }
}
