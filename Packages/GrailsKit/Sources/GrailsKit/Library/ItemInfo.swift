import Foundation

/// What the preview and the inspector say about one item, in the order they say it. Pure data: the views only draw it.
public struct ItemInfo: Equatable, Sendable {
    public struct Tag: Equatable, Sendable { public var name: String; public var automatic: Bool }
    public struct Place: Equatable, Sendable { public var id: String; public var name: String }

    public var title: String
    /// "kunsthalle.ch" and the link it came from.
    public var site: String?
    public var sourceURL: URL?
    public var author: String?
    public var addedBy: String
    public var addedAt: Date
    public var editedBy: String?
    /// "0:42 · 1920 × 1080 · MP4 · 24 MB": a video leads with its length.
    public var facts: String
    public var palette: [String]
    public var tags: [Tag]
    public var collections: [Place]
    public var note: String
    public var camera: [(label: String, value: String)]

    public static func == (a: ItemInfo, b: ItemInfo) -> Bool {
        a.title == b.title && a.site == b.site && a.sourceURL == b.sourceURL && a.author == b.author && a.addedBy == b.addedBy && a.addedAt == b.addedAt
            && a.editedBy == b.editedBy && a.facts == b.facts && a.palette == b.palette && a.tags == b.tags && a.collections == b.collections
            && a.note == b.note && a.camera.map { "\($0.label)=\($0.value)" } == b.camera.map { "\($0.label)=\($0.value)" }
    }

    public static func make(item: Item, collectionName: (String) -> String?) -> ItemInfo {
        let auto = Set(item.autoTags.map { $0.lowercased() })
        let link = (item.source?.pageUrl ?? item.source?.url).flatMap(URL.init(string:))
        let site = item.source?.site ?? link?.host.map { $0.hasPrefix("www.") ? String($0.dropFirst(4)) : $0 }

        var facts: [String] = []
        if let d = item.durationSec, d > 0 { facts.append(String(format: "%d:%02d", Int(d) / 60, Int(d) % 60)) }
        if let w = item.width, let h = item.height { facts.append("\(w) × \(h)") }
        facts.append((item.ext ?? item.kind.rawValue).uppercased())
        if let b = item.bytes { facts.append(ByteCountFormatter.string(fromByteCount: b, countStyle: .file)) }

        let places = item.collections.keys.compactMap { id in collectionName(id).map { Place(id: id, name: $0) } }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        var camera: [(String, String)] = []
        if case .object(let c)? = item.camera {
            func s(_ k: String) -> String? { if case .string(let v)? = c[k], !v.isEmpty { v } else { nil } }
            func d(_ k: String) -> Double? { switch c[k] { case .double(let v): v; case .int(let v): Double(v); default: nil } }
            let body = [s("make"), s("model")].compactMap { $0 }.joined(separator: " ")
            if !body.isEmpty { camera.append(("Camera", body)) }
            if let l = s("lens") { camera.append(("Lens", l)) }
            var shot: [String] = []
            if let f = d("focalLength") { shot.append("\(Int(f)) mm") }
            if let a = d("aperture") { shot.append("ƒ/\(String(format: "%g", a))") }
            if let t = d("shutter") { shot.append(t < 1 ? "1/\(Int((1 / t).rounded())) s" : "\(t) s") }
            if let i = d("iso") { shot.append("ISO \(Int(i))") }
            if !shot.isEmpty { camera.append(("Exposure", shot.joined(separator: " · "))) }
            if let at = s("capturedAt") { camera.append(("Captured", at)) }
        }

        return ItemInfo(
            title: item.name, site: site, sourceURL: link, author: item.source?.author?.isEmpty == false ? item.source?.author : nil,
            addedBy: item.addedBy, addedAt: item.addedAt,
            editedBy: item.updatedAt != item.addedAt && item.updatedBy != item.addedBy ? item.updatedBy : nil,
            facts: facts.joined(separator: " · "), palette: item.palette.map(\.hex),
            tags: item.tags.map { Tag(name: $0, automatic: auto.contains($0.lowercased())) },
            collections: places, note: item.note, camera: camera
        )
    }
}
