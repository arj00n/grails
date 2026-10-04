import Foundation

/// Resolves Pinterest pins through the public widget endpoint (the one Pinterest's own embeds use): exact image
/// sizes, the pin's source link, and video renditions. One request covers many pins.
enum PinterestPins {
    struct Resolved {
        var entries: [RemoteBoard.Entry] = []
        var skipped: [String: Int] = [:]
        var boardName: String?
        var boardPinCount: Int?
    }

    static let batchSize = 20

    /// Numeric pin ids only: the widget doesn't know Pinterest's newer alphanumeric ids.
    static func isNumeric(_ id: String) -> Bool { !id.isEmpty && id.allSatisfy(\.isNumber) }

    static func resolve(ids: [String], authorFallback: String?, loader: LinkFetcher.Loader) async throws -> Resolved {
        var out = Resolved()
        let numeric = ids.filter(isNumeric)
        let unresolvable = ids.count - numeric.count
        if unresolvable > 0 { out.skipped["pins Pinterest wouldn't describe"] = unresolvable }
        var byID: [String: [String: Any]] = [:]
        for start in stride(from: 0, to: numeric.count, by: batchSize) {
            let batch = numeric[start..<min(start + batchSize, numeric.count)]
            guard let url = URL(string: "https://widgets.pinterest.com/v3/pidgets/pins/info/?pin_ids=\(batch.joined(separator: ","))") else { continue }
            let (data, response) = try await loader(LinkFetcher.request(url, accept: "application/json"))
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                if http.statusCode == 429 { throw BoardImportError.blocked("Pinterest is asking us to slow down. Try again in a few minutes.") }
                throw BoardImportError.network("Pinterest answered HTTP \(http.statusCode)")
            }
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let list = json["data"] as? [[String: Any]] else {
                throw BoardImportError.network("unexpected reply from Pinterest")
            }
            for pin in list { if let id = pin["id"].map({ "\($0)" }) { byID[id] = pin } }
        }
        var missing = 0
        for id in numeric {
            guard let pin = byID[id] else { missing += 1; continue }
            if out.boardName == nil, let b = pin["board"] as? [String: Any] {
                out.boardName = b["name"] as? String
                out.boardPinCount = b["pin_count"] as? Int
            }
            out.entries += entries(for: pin, id: id, authorFallback: authorFallback)
        }
        if missing > 0 { out.skipped["pins Pinterest no longer shows"] = missing }
        return out
    }

    // MARK: One pin → entries

    static func entries(for pin: [String: Any], id: String, authorFallback: String?) -> [RemoteBoard.Entry] {
        let source = (pin["link"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        let pinPage = "https://www.pinterest.com/pin/\(id)/"
        let title = decodeEntities(pin["description"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        let pinner = pin["pinner"] as? [String: Any]
        let author = (pinner?["full_name"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? (pinner?["username"] as? String) ?? authorFallback
        // an untitled pin would otherwise be named after its file hash
        let name = title ?? (source.flatMap { URL(string: $0)?.host?.replacingOccurrences(of: "www.", with: "") }.map { "\($0) · pin \(id.suffix(6))" } ?? "Pin \(id.suffix(6))")
        func entry(_ media: [String]) -> RemoteBoard.Entry { .init(mediaUrls: media, pageUrl: source ?? pinPage, title: name, author: author) }

        // Story pins (a pin made of pages) carry exact original URLs and may hold videos.
        if let story = pin["story_pin_data"] as? [String: Any], let pages = story["pages"] as? [[String: Any]], !pages.isEmpty {
            var out: [RemoteBoard.Entry] = []
            for page in pages {
                let poster = imageURLs(page["image"] as? [String: Any])
                if let list = (page["video"] as? [String: Any])?["video_list"] as? [String: Any], let videos = videoCandidates(list), !videos.isEmpty {
                    out.append(entry(videos + poster))
                } else if !poster.isEmpty {
                    out.append(entry(poster))
                }
            }
            if !out.isEmpty { return out }
        }
        // Ordinary video pins
        if let list = (pin["videos"] as? [String: Any])?["video_list"] as? [String: Any], let videos = videoCandidates(list), !videos.isEmpty {
            return [entry(videos + pinImageCandidates(pin["images"] as? [String: Any]))]
        }
        let images = pinImageCandidates(pin["images"] as? [String: Any])
        return images.isEmpty ? [] : [entry(images)]
    }

    /// `images` as the widget returns it: sizes keyed "236x", "564x", sometimes "orig"/"originals" with exact URLs.
    static func pinImageCandidates(_ images: [String: Any]?) -> [String] {
        guard let images else { return [] }
        var out: [String] = []
        for key in ["orig", "originals"] { if let u = (images[key] as? [String: Any])?["url"] as? String { out.append(u) } }
        if let any = images.values.compactMap({ ($0 as? [String: Any])?["url"] as? String }).first(where: { $0.contains("i.pinimg.com/") }) {
            out += upgrade(any)
        }
        return dedupe(out)
    }

    /// Exact URLs for one image object ({ "originals": { url }, "736x": { url } … }).
    static func imageURLs(_ node: [String: Any]?) -> [String] {
        guard let images = (node?["images"] as? [String: Any]) ?? node else { return [] }
        var out = ["originals", "orig", "1200x", "750x", "736x", "564x"].compactMap { (images[$0] as? [String: Any])?["url"] as? String }
        if out.isEmpty, let any = images.values.compactMap({ ($0 as? [String: Any])?["url"] as? String }).first { out = upgrade(any) }
        return dedupe(out)
    }

    /// The feed and widget give a 236 px (JPEG) thumbnail; the same image exists larger under the same path. Originals keep
    /// the uploader's format, so the extension isn't necessarily .jpg: try each, then the big resized versions.
    static func upgrade(_ thumb: String) -> [String] {
        guard let r = thumb.range(of: #"i\.pinimg\.com/\d+x/"#, options: .regularExpression) else { return [thumb] }
        let pre = String(thumb[..<r.lowerBound]) + "i.pinimg.com/", post = String(thumb[r.upperBound...])
        let stem = post.contains(".") ? String(post[..<post.lastIndex(of: ".")!]) : post
        let original = ["jpg", "png", "webp", "gif"].map { "\(pre)originals/\(stem).\($0)" }
        // keep the thumbnail's own extension first (most pins), without repeating it
        let first = "\(pre)originals/\(post)"
        return dedupe([first] + original + ["\(pre)1200x/\(post)", "\(pre)736x/\(post)", thumb])
    }

    // MARK: Video

    /// The highest-quality files for a pin's `video_list`, best first. Pinterest lists direct .mp4 renditions for some
    /// pins; for others only an HLS stream, whose top rendition also exists as `…/expMp4/<hash>_<width>w.mp4`.
    static func videoCandidates(_ list: [String: Any]) -> [String]? {
        struct Rendition { var url: String; var width: Int }
        var mp4: [Rendition] = [], hls: [Rendition] = []
        for (_, v) in list {
            guard let d = v as? [String: Any], let url = d["url"] as? String else { continue }
            let w = (d["width"] as? Int) ?? 0
            if url.hasSuffix(".mp4") { mp4.append(Rendition(url: url, width: w)) }
            else if url.hasSuffix(".m3u8") { hls.append(Rendition(url: url, width: w)) }
        }
        var out = mp4.sorted { $0.width > $1.width }.map(\.url)
        let topWidth = hls.map(\.width).max() ?? 0
        for h in hls.sorted(by: { $0.width > $1.width }) {
            guard let m = h.url.range(of: #"videos/([^/]+)/hls/(.+?)([0-9a-f]{32})(?:_v\d+)?\.m3u8$"#, options: .regularExpression) else { continue }
            let tail = String(h.url[m])
            let parts = tail.split(separator: "/").map(String.init)           // videos, <kind>, hls, a, b, c, <hash…>.m3u8
            guard parts.count >= 5, let hash = tail.range(of: #"[0-9a-f]{32}"#, options: .regularExpression).map({ String(tail[$0]) }) else { continue }
            let prefix = String(h.url[..<h.url.range(of: "/hls/")!.lowerBound])
            let dirs = parts.dropFirst(3).dropLast().joined(separator: "/")
            let base = "\(prefix)/expMp4/\(dirs.isEmpty ? "" : dirs + "/")\(hash)"
            let widths = dedupe(([topWidth, 1080, 720, 540, 360, 240].filter { $0 > 0 && $0 <= max(topWidth, 240) })).map { String($0) }
            out += widths.map { "\(base)_\($0)w.mp4" }
        }
        return out.isEmpty ? nil : dedupe(out)
    }

    // MARK: Helpers

    static func dedupe(_ xs: [String]) -> [String] { var seen = Set<String>(); return xs.filter { seen.insert($0).inserted } }
    static func dedupe(_ xs: [Int]) -> [Int] { var seen = Set<Int>(); return xs.filter { seen.insert($0).inserted } }

    static func decodeEntities(_ s: String?) -> String? {
        guard var s else { return nil }
        s = s.trimmingCharacters(in: .whitespacesAndNewlines)
        for (k, v) in ["&amp;": "&", "&quot;": "\"", "&lt;": "<", "&gt;": ">", "&apos;": "'", "&#39;": "'", "&nbsp;": " "] { s = s.replacingOccurrences(of: k, with: v) }
        while let r = s.range(of: #"&#(\d+);"#, options: .regularExpression) {
            let digits = s[r].dropFirst(2).dropLast()
            let ch = UInt32(digits).flatMap(Unicode.Scalar.init).map(String.init) ?? ""
            s.replaceSubrange(r, with: ch)
        }
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
