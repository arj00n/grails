import Foundation

public struct LinkMetadata: Sendable, Equatable {
    public var title: String?
    public var siteName: String?
    public var description: String?
    public var author: String?
    public var imageURL: URL?
    public init(title: String? = nil, siteName: String? = nil, description: String? = nil, author: String? = nil, imageURL: URL? = nil) {
        self.title = title; self.siteName = siteName; self.description = description; self.author = author; self.imageURL = imageURL
    }
}

/// Reads Open Graph / Twitter card / plain `<title>` metadata out of an HTML page. Regex-based on purpose: we only
/// need the `<head>`, and a full HTML parser would be a new dependency.
public enum HTMLMeta {
    public static func parse(html rawHTML: String, baseURL: URL?) -> LinkMetadata {
        // The metadata we want lives in <head>; don't scan megabytes of body.
        let html = String(rawHTML.prefix(400_000))
        var meta: [String: String] = [:]
        for tag in matches(#"<meta\b[^>]*>"#, in: html) {
            let attrs = attributes(of: tag)
            guard let content = attrs["content"], !content.isEmpty,
                  let key = (attrs["property"] ?? attrs["name"] ?? attrs["itemprop"])?.lowercased() else { continue }
            if meta[key] == nil { meta[key] = decodeEntities(content) }
        }
        var result = LinkMetadata()
        result.title = first(meta, ["og:title", "twitter:title"]) ?? titleTag(html)
        result.siteName = first(meta, ["og:site_name", "application-name"])
        result.description = first(meta, ["og:description", "twitter:description", "description"])
        result.author = first(meta, ["author", "article:author", "twitter:creator"])
        var image = first(meta, ["og:image", "og:image:url", "og:image:secure_url", "twitter:image", "twitter:image:src"])
        if image == nil {
            for tag in matches(#"<link\b[^>]*>"#, in: html) {
                let a = attributes(of: tag)
                if a["rel"]?.lowercased() == "image_src", let href = a["href"] { image = decodeEntities(href); break }
            }
        }
        if let image, !image.isEmpty {
            result.imageURL = URL(string: image, relativeTo: baseURL)?.absoluteURL
        }
        result.title = result.title?.trimmingCharacters(in: .whitespacesAndNewlines)
        return result
    }

    private static func first(_ meta: [String: String], _ keys: [String]) -> String? {
        for k in keys { if let v = meta[k], !v.trimmingCharacters(in: .whitespaces).isEmpty { return v } }
        return nil
    }

    private static func titleTag(_ html: String) -> String? {
        guard let m = matches(#"<title\b[^>]*>([\s\S]*?)</title>"#, in: html, group: 1).first else { return nil }
        let t = decodeEntities(m).replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        return t.isEmpty ? nil : t
    }

    private static func matches(_ pattern: String, in s: String, group: Int = 0) -> [String] {
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }
        let ns = s as NSString
        return re.matches(in: s, range: NSRange(location: 0, length: ns.length)).compactMap { m in
            let r = m.range(at: group)
            return r.location == NSNotFound ? nil : ns.substring(with: r)
        }
    }

    private static func attributes(of tag: String) -> [String: String] {
        var out: [String: String] = [:]
        guard let re = try? NSRegularExpression(pattern: #"([a-zA-Z_:][-a-zA-Z0-9_:.]*)\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s"'>]+))"#) else { return out }
        let ns = tag as NSString
        for m in re.matches(in: tag, range: NSRange(location: 0, length: ns.length)) {
            let name = ns.substring(with: m.range(at: 1)).lowercased()
            for g in 2...4 where m.range(at: g).location != NSNotFound {
                out[name] = ns.substring(with: m.range(at: g)); break
            }
        }
        return out
    }

    static func decodeEntities(_ s: String) -> String {
        guard s.contains("&") else { return s }
        var out = s
        let named = ["&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": "\"", "&apos;": "'", "&#39;": "'", "&nbsp;": " ", "&mdash;": "—", "&ndash;": "–", "&hellip;": "…", "&rsquo;": "’", "&lsquo;": "‘", "&rdquo;": "”", "&ldquo;": "“"]
        for (k, v) in named { out = out.replacingOccurrences(of: k, with: v) }
        if let re = try? NSRegularExpression(pattern: #"&#(x?)([0-9a-fA-F]+);"#) {
            let ns = out as NSString
            var result = ""
            var last = 0
            for m in re.matches(in: out, range: NSRange(location: 0, length: ns.length)) {
                result += ns.substring(with: NSRange(location: last, length: m.range.location - last))
                let isHex = ns.substring(with: m.range(at: 1)) == "x"
                if let code = UInt32(ns.substring(with: m.range(at: 2)), radix: isHex ? 16 : 10), let u = Unicode.Scalar(code) { result.unicodeScalars.append(u) }
                last = m.range.location + m.range.length
            }
            result += ns.substring(from: last)
            out = result
        }
        return out
    }
}

/// What kind of thing a URL or string points at.
public enum CaptureClassifier {
    public enum Kind: Equatable, Sendable { case image, video, page, text }

    static let imageExts: Set<String> = ["jpg", "jpeg", "png", "gif", "webp", "avif", "heic", "heif", "tiff", "tif", "bmp", "svg", "ico"]
    static let videoExts: Set<String> = ["mp4", "mov", "m4v", "webm", "mkv", "avi"]

    public static func classify(_ string: String) -> (kind: Kind, url: URL?) {
        let t = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, !t.contains(where: \.isNewline), let url = URL(string: t),
              let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme), url.host != nil else { return (.text, nil) }
        let ext = url.pathExtension.lowercased()
        if imageExts.contains(ext) { return (.image, url) }
        if videoExts.contains(ext) { return (.video, url) }
        return (.page, url)
    }

    public static func isFigma(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased(), host == "figma.com" || host.hasSuffix(".figma.com") else { return false }
        let first = url.pathComponents.dropFirst().first ?? ""
        return ["file", "design", "proto", "board", "slides", "make", "buzz"].contains(first)
    }

    public static func siteName(for url: URL) -> String? {
        guard var host = url.host?.lowercased() else { return nil }
        if host.hasPrefix("www.") { host.removeFirst(4) }
        return host
    }
}
