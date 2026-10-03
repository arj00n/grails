import StashKit
import SwiftUI

struct InfoPanel: View {
    var model: AppModel
    @State private var item: Item?

    private var selectedID: String? { model.selection.count == 1 ? model.selection.first : nil }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if model.selection.count > 1 {
                    Text("\(model.selection.count) items selected").font(.headline)
                } else if let item {
                    content(item)
                } else {
                    Text("Select an item to see its details.").foregroundStyle(.secondary)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityIdentifier("info-panel")
        .task(id: selectedID) { await load() }
        .onChange(of: model.itemsVersion) { Task { await load() } }
    }

    private func load() async {
        guard let id = selectedID, let store = model.store else { item = nil; return }
        item = try? await store.item(id: id)
    }

    @ViewBuilder
    private func content(_ item: Item) -> some View {
        if let layout = model.layout, let img = NSImage(contentsOf: layout.thumbURL(item.id)) {
            Image(nsImage: img).resizable().scaledToFit().clipShape(RoundedRectangle(cornerRadius: 8))
        }
        Text(item.name).font(.headline).textSelection(.enabled)

        facts(item)

        if !item.palette.isEmpty {
            section("Colors") {
                HStack(spacing: 4) {
                    ForEach(item.palette, id: \.hex) { p in
                        RoundedRectangle(cornerRadius: 4).fill(Color(hex: p.hex)).frame(height: 24)
                            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(.primary.opacity(0.15)))
                            .help(p.hex)
                    }
                }
            }
        }
        if !item.tags.isEmpty {
            let auto = Set(item.autoTags.map { $0.lowercased() })
            section("Tags") {
                FlowLayout(spacing: 6) {
                    ForEach(item.tags, id: \.self) { t in
                        let isAuto = auto.contains(t.lowercased())
                        HStack(spacing: 3) {
                            if isAuto { Image(systemName: "sparkle").font(.system(size: 8)) }
                            Text("#\(t)")
                        }
                        .font(.caption).padding(.horizontal, 8).padding(.vertical, 3)
                        .background(.quaternary, in: Capsule())
                        .help(isAuto ? "Added automatically" : "")
                        .accessibilityLabel(isAuto ? "#\(t), automatic" : "#\(t)")
                    }
                }
            }
        }
        let names = item.collections.keys.compactMap { id in model.collections.first { $0.id == id }?.name }.sorted()
        if !names.isEmpty { section("Collections") { chips(names) } }

        if let src = item.source, src.url != nil || src.pageUrl != nil || src.site != nil {
            section("Source") {
                if let site = src.site { Text(site) }
                if let s = src.pageUrl ?? src.url, let url = URL(string: s) { Link(s, destination: url).lineLimit(2) }
                if let author = src.author { Text(author).foregroundStyle(.secondary) }
            }
        }
        if !item.note.isEmpty { section("Note") { Text(item.note).textSelection(.enabled) } }
        if case .object(let cam)? = item.camera { section("Camera") { camera(cam) } }

        section("History") {
            Text("Added by \(item.addedBy) · \(item.addedAt.formatted(date: .abbreviated, time: .shortened))")
            if item.updatedAt != item.addedAt {
                Text("Edited by \(item.updatedBy) · \(item.updatedAt.formatted(date: .abbreviated, time: .shortened))").foregroundStyle(.secondary)
            }
        }
    }

    private func facts(_ item: Item) -> some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
            if let w = item.width, let h = item.height { fact("Dimensions", "\(w) × \(h)") }
            if let b = item.bytes { fact("Size", ByteCountFormatter.string(fromByteCount: b, countStyle: .file)) }
            fact("Type", (item.ext ?? item.kind.rawValue).uppercased())
        }
        .font(.callout)
    }

    private func fact(_ k: String, _ v: String) -> some View {
        GridRow { Text(k).foregroundStyle(.secondary); Text(v).monospacedDigit() }
    }

    private func section(_ title: String, @ViewBuilder _ body: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased()).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
            body().font(.callout)
        }
    }

    private func chips(_ labels: [String]) -> some View {
        FlowLayout(spacing: 6) {
            ForEach(labels, id: \.self) { l in
                Text(l).font(.caption).padding(.horizontal, 8).padding(.vertical, 3)
                    .background(.quaternary, in: Capsule())
            }
        }
    }

    private func camera(_ c: [String: JSONValue]) -> some View {
        func s(_ k: String) -> String? { if case .string(let v)? = c[k] { v } else { nil } }
        func d(_ k: String) -> Double? { switch c[k] { case .double(let v): v; case .int(let v): Double(v); default: nil } }
        return Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
            if let make = s("make") ?? s("model") { fact("Camera", [s("make"), s("model")].compactMap { $0 }.joined(separator: " ").isEmpty ? make : [s("make"), s("model")].compactMap { $0 }.joined(separator: " ")) }
            if let l = s("lens") { fact("Lens", l) }
            if let f = d("focalLength") { fact("Focal length", "\(Int(f)) mm") }
            if let a = d("aperture") { fact("Aperture", "ƒ/\(String(format: "%g", a))") }
            if let t = d("shutter") { fact("Shutter", t < 1 ? "1/\(Int((1 / t).rounded())) s" : "\(t) s") }
            if let i = d("iso") { fact("ISO", "\(Int(i))") }
            if let e = d("exposureBias"), e != 0 { fact("Exposure", String(format: "%+.1f EV", e)) }
            if let c = s("capturedAt") { fact("Captured", c) }
        }
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
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0, maxX: CGFloat = 0
        var origins: [CGPoint] = []
        for s in subviews {
            let sz = s.sizeThatFits(.unspecified)
            if x > 0, x + sz.width > width { x = 0; y += rowH + spacing; rowH = 0 }
            origins.append(CGPoint(x: x, y: y))
            x += sz.width + spacing; rowH = max(rowH, sz.height); maxX = max(maxX, x - spacing)
        }
        return (CGSize(width: maxX, height: y + rowH), origins)
    }
}

extension Color {
    init(hex: String) {
        var s = hex; if s.hasPrefix("#") { s.removeFirst() }
        let v = UInt32(s, radix: 16) ?? 0x888888
        self.init(red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
    }
}
