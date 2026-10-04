import StashKit
import SwiftUI

/// Everything about one item: picture (optionally), facts, colours, tags, collections, source, note, history. Tags,
/// collections and "added by" are links: they take you to that tag, collection or person's contributions.
struct ItemDetails: View {
    var model: AppModel
    let itemID: String?
    var showsPicture = true
    var emptyText = "Select an item to see its details."
    @State private var item: Item?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let item { content(item) } else { Text(emptyText).foregroundStyle(.secondary) }
        }
        .task(id: itemID) { await load() }
        .onChange(of: model.itemsVersion) { Task { await load() } }
    }

    private func load() async {
        guard let id = itemID, let store = model.store else { item = nil; return }
        item = try? await store.item(id: id)
    }

    @ViewBuilder
    private func content(_ item: Item) -> some View {
        if showsPicture, let layout = model.layout, let img = NSImage(contentsOf: layout.thumbURL(item.id)) {
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
                        LinkChip(label: isAuto ? "#\(t), automatic" : "#\(t)") { model.showTag(t) } content: {
                            HStack(spacing: 3) {
                                if isAuto { Image(systemName: "sparkle").font(.system(size: 8)) }
                                Text("#\(t)")
                            }
                        }
                    }
                }
            }
        }
        let places = item.collections.keys.compactMap { id in model.collections.first { $0.id == id } }.sorted { $0.name < $1.name }
        if !places.isEmpty {
            section("Collections") {
                FlowLayout(spacing: 6) {
                    ForEach(places) { c in
                        LinkChip(label: c.name) { model.showCollection(c.id) } content: { Text(c.name) }
                    }
                }
            }
        }

        if let src = item.source, src.url != nil || src.pageUrl != nil || src.site != nil {
            section("Source") {
                if let site = src.site { Text(site) }
                if let s = src.pageUrl ?? src.url, let url = URL(string: s) { Link(s, destination: url).lineLimit(2) }
                if let author = src.author { Text(author).foregroundStyle(.secondary) }
            }
        }
        if !item.note.isEmpty { section("Note") { Text(item.note).textSelection(.enabled) } }
        if case .object(let cam)? = item.camera { section("Camera") { camera(cam) } }

        section("Added by") {
            HStack(spacing: 6) {
                PersonLink(name: item.addedBy) { model.showContributions(of: item.addedBy) }
                Text("· \(item.addedAt.formatted(date: .abbreviated, time: .shortened))").foregroundStyle(.secondary)
            }
            if item.updatedAt != item.addedAt {
                HStack(spacing: 6) {
                    Text("Edited by").foregroundStyle(.secondary)
                    PersonLink(name: item.updatedBy) { model.showContributions(of: item.updatedBy) }
                    Text("· \(item.updatedAt.formatted(date: .abbreviated, time: .shortened))").foregroundStyle(.secondary)
                }
            }
        }
    }

    private func facts(_ item: Item) -> some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
            if let w = item.width, let h = item.height { fact("Dimensions", "\(w) × \(h)") }
            if let d = item.durationSec, d > 0 { fact("Length", String(format: "%d:%02d", Int(d) / 60, Int(d) % 60)) }
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

/// A pill that takes you somewhere (a tag, a collection). Brightens under the pointer.
struct LinkChip<Content: View>: View {
    let label: String
    let action: () -> Void
    @ViewBuilder var content: () -> Content
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            content()
                .font(.caption)
                .foregroundStyle(hovering ? Ink.text : Ink.secondary)
                .padding(.horizontal, 9).padding(.vertical, 4)
                .background(hovering ? Ink.fillHover : Ink.fill, in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityLabel(label)
    }
}

/// A person's name that opens everything they added.
struct PersonLink: View {
    let name: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(name).underline(hovering).foregroundStyle(hovering ? Ink.text : Ink.text.opacity(0.85)).fontWeight(.medium)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

