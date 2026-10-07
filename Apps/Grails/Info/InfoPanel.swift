import GrailsKit
import SwiftUI

/// The inspector: the one selected item in full, a count and size for several, the view's totals for none.
struct InfoPanel: View {
    var model: AppModel

    private var selectedID: String? { model.selection.count == 1 ? model.selection.first : nil }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if let id = selectedID {
                    InfoBlock(model: model, itemID: id)
                } else if model.selection.count > 1 {
                    let chosen = model.selectedSummaries
                    Text("\(model.selection.count) selected").font(.grailsDisplay(16))
                    let bytes = chosen.reduce(Int64(0)) { $0 + ($1.bytes ?? 0) }
                    if bytes > 0 { Text(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)).font(.grailsBody(12)).foregroundStyle(Ink.secondary) }
                } else {
                    Text(model.title).font(.grailsDisplay(16))
                    Text(model.countLabel).font(.grailsBody(12)).foregroundStyle(Ink.secondary)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.never)
        .accessibilityIdentifier("info-panel")
    }
}

/// Simple wrapping row layout for chips.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(width: proposal.width ?? 300, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let r = arrange(width: bounds.width, subviews: subviews)
        for (i, p) in r.origins.enumerated() { subviews[i].place(at: CGPoint(x: bounds.minX + p.x, y: bounds.minY + p.y), proposal: .unspecified) }
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> (size: CGSize, origins: [CGPoint]) {
        var rows: [[CGSize]] = []
        var row: [CGSize] = []
        var x: CGFloat = 0
        for s in subviews {
            let sz = s.sizeThatFits(.unspecified)
            if !row.isEmpty, x + sz.width > width { rows.append(row); row = []; x = 0 }
            row.append(sz)
            x += sz.width + spacing
        }
        if !row.isEmpty { rows.append(row) }
        var origins: [CGPoint] = []
        var y: CGFloat = 0
        var maxX: CGFloat = 0
        for (r, row) in rows.enumerated() {
            let rowH = row.map(\.height).max() ?? 0
            var x: CGFloat = 0
            for sz in row {
                origins.append(CGPoint(x: x, y: y + (rowH - sz.height) / 2))
                x += sz.width + spacing
            }
            maxX = max(maxX, x - spacing)
            y += rowH
            if r < rows.count - 1 { y += spacing }
        }
        return (CGSize(width: max(0, maxX), height: y), origins)
    }
}

extension Color {
    init(hex: String) {
        var s = hex; if s.hasPrefix("#") { s.removeFirst() }
        let v = UInt32(s, radix: 16) ?? 0x888888
        self.init(red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
    }
}
