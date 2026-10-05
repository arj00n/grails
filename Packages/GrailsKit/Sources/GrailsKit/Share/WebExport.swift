import Foundation
import ImageIO
import UniformTypeIdentifiers

public struct WebExportOptions: Sendable {
    /// Show each item's "Source" link to where it was found.
    public var includeSources = true
    /// Longest edge of the full-size picture in the page.
    public var maxEdge = 1600
    /// JPEG quality of resized pictures.
    public var quality = 0.86
    /// Videos bigger than this show their poster only.
    public var maxVideoBytes: Int64 = 40_000_000
    public var maxGIFBytes: Int64 = 25_000_000
    /// One picture per item instead of a thumbnail and a full-size copy (for a single file, where every byte is carried along).
    public var singleImage = false
    public var makeZip = true
    public init(includeSources: Bool = true, makeZip: Bool = true) { self.includeSources = includeSources; self.makeZip = makeZip }

    /// One HTML file that carries everything: smaller pictures, short clips only.
    public static func singleFile(includeSources: Bool = true) -> WebExportOptions {
        var o = WebExportOptions(includeSources: includeSources, makeZip: false)
        o.maxEdge = 1100; o.quality = 0.78; o.maxVideoBytes = 6_000_000; o.maxGIFBytes = 6_000_000; o.singleImage = true
        return o
    }
}

public struct WebExportReport: Sendable {
    public var folder: URL
    public var zip: URL?
    /// The finished single file or PDF, when one was asked for.
    public var file: URL?
    public var exported = 0
    /// Items whose full-size file wasn't on this Mac (a sync placeholder), so the page has the thumbnail only.
    public var thumbnailOnly = 0
    public var skipped = 0
    public var bytes: Int64 = 0
}

extension LibraryStore {
    private func exportItems(_ ids: [String]) throws -> [Item] {
        var items: [Item] = []
        var seen = Set<String>()
        for id in ids where seen.insert(id).inserted {
            if let item = try item(id: id), item.deletedAt == nil { items.append(item) }
        }
        return items
    }

    /// Writes a web page of `ids` (in order) into a new folder inside `parent`: open `index.html`, or send the zip.
    /// Clusters become titled sections and a canvas view. Nothing is uploaded anywhere.
    public func exportWebPage(
        title: String, ids: [String], clusters: [CanvasCluster] = [], options: WebExportOptions = .init(), to parent: URL,
        progress: @escaping @Sendable (Int, Int) -> Void = { _, _ in }
    ) async throws -> WebExportReport {
        let items = try exportItems(ids), layout = self.layout
        return try await Task.detached(priority: .userInitiated) {
            try WebExporter.writeFolder(title: title, items: items, orderedIDs: ids, clusters: clusters, options: options, layout: layout, parent: parent, progress: progress)
        }.value
    }

    /// The same page as one `.html` file with every picture inside it: send it by mail or chat, open it anywhere.
    public func exportSingleFile(
        title: String, ids: [String], clusters: [CanvasCluster] = [], includeSources: Bool = true, to parent: URL,
        progress: @escaping @Sendable (Int, Int) -> Void = { _, _ in }
    ) async throws -> WebExportReport {
        let items = try exportItems(ids), layout = self.layout
        return try await Task.detached(priority: .userInitiated) {
            try WebExporter.writeSingleFile(title: title, items: items, orderedIDs: ids, clusters: clusters, options: .singleFile(includeSources: includeSources), layout: layout, parent: parent, progress: progress)
        }.value
    }

    /// A PDF: a cover, then each cluster's pictures packed edge to edge, one slide-sized page after another. Source links are clickable.
    public func exportPDF(
        title: String, ids: [String], clusters: [CanvasCluster] = [], includeSources: Bool = true, to parent: URL,
        progress: @escaping @Sendable (Int, Int) -> Void = { _, _ in }
    ) async throws -> WebExportReport {
        let items = try exportItems(ids), layout = self.layout
        return try await Task.detached(priority: .userInitiated) {
            try WebExporter.writePDF(title: title, items: items, orderedIDs: ids, clusters: clusters, includeSources: includeSources, layout: layout, parent: parent, progress: progress)
        }.value
    }
}

enum WebExporter {
    struct Entry {
        var id: String, name: String, kind: String
        var w: Int, h: Int
        var thumb: String, full: String
        var video: String?
        var source: String?, author: String?
    }

    /// Prepares every picture and clip into `folder` and says what exported.
    static func gather(
        items: [Item], options: WebExportOptions, layout: LibraryLayout, folder: URL, progress: @Sendable (Int, Int) -> Void
    ) throws -> (entries: [String: Entry], report: WebExportReport) {
        let fm = FileManager.default
        try fm.createDirectory(at: folder.appendingPathComponent("media"), withIntermediateDirectories: true)
        try fm.createDirectory(at: folder.appendingPathComponent("thumbs"), withIntermediateDirectories: true)
        var report = WebExportReport(folder: folder)
        var entries: [String: Entry] = [:]
        progress(0, items.count)
        for (i, item) in items.enumerated() {
            try Task.checkCancellation()
            if let e = prepare(item, layout: layout, folder: folder, options: options, report: &report) { entries[item.id] = e } else { report.skipped += 1 }
            progress(i + 1, items.count)
        }
        report.exported = entries.count
        guard !entries.isEmpty else { throw CaptureError.nothingToSave }
        return (entries, report)
    }

    /// Sections (one per cluster, or a single untitled one) and the canvas placements, as the page's data.
    static func pageData(
        title: String, entries: [String: Entry], orderedIDs: [String], clusters: [CanvasCluster], resolve: (String) -> String
    ) throws -> (json: String, sections: [(title: String, ids: [String])]) {
        let order = orderedIDs.filter { entries[$0] != nil }.reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
        var sections: [(title: String, ids: [String])] = []
        var canvas: [String: Any]?
        let live = clusters.map { c in (c, c.items.filter { entries[$0] != nil }) }.filter { !$0.1.isEmpty }
        if !live.isEmpty {
            var ordered: [String] = []
            var clusterJSON: [[String: Any]] = []
            var minX = Double.infinity, minY = Double.infinity, maxX = -Double.infinity, maxY = -Double.infinity
            for (c, members) in live {
                ordered += members
                sections.append((c.title, members))
                let packed = ClusterLayout.pack(members.map { id in
                    let e = entries[id]!
                    return ClusterLayout.Entry(id: id, aspect: e.h > 0 ? Double(e.w) / Double(e.h) : 1)
                }, width: c.width, tile: c.tile)
                let top = c.y + ClusterLayout.headerHeight
                let rects: [[String: Any]] = members.compactMap { id in
                    guard let r = packed.rects[id] else { return nil }
                    return ["id": id, "x": c.x + r.minX, "y": top + r.minY, "w": r.width, "h": r.height]
                }
                clusterJSON.append(["title": c.title, "x": c.x, "y": c.y, "w": max(c.width, ClusterLayout.minWidth), "headerH": ClusterLayout.headerHeight, "items": rects])
                minX = min(minX, c.x); minY = min(minY, c.y); maxX = max(maxX, c.x + max(c.width, ClusterLayout.minWidth)); maxY = max(maxY, top + packed.height)
            }
            let rest = order.filter { !ordered.contains($0) }
            if !rest.isEmpty { sections.append(("", rest)) }
            canvas = ["clusters": clusterJSON, "bounds": ["x": minX, "y": minY, "w": max(maxX - minX, 1), "h": max(maxY - minY, 1)]]
        } else {
            sections = [("", order)]
        }
        let flat = sections.flatMap(\.ids)
        var itemsJSON: [String: Any] = [:]
        for (id, e) in entries {
            var o: [String: Any] = ["name": e.name, "kind": e.kind, "w": e.w, "h": e.h, "thumb": resolve(e.thumb)]
            if e.full != e.thumb { o["full"] = resolve(e.full) }
            if let v = e.video { o["video"] = resolve(v) }
            if let s = e.source { o["source"] = s }
            if let a = e.author { o["author"] = a }
            itemsJSON[id] = o
        }
        var data: [String: Any] = ["title": title, "order": flat, "sections": sections.map { ["title": $0.title, "ids": $0.ids] as [String: Any] }, "items": itemsJSON]
        if let canvas { data["canvas"] = canvas }
        let json = try JSONSerialization.data(withJSONObject: data, options: [.sortedKeys, .withoutEscapingSlashes])
        return (String(decoding: json, as: UTF8.self).replacingOccurrences(of: "</", with: "<\\/"), sections)
    }

    static func uniqueURL(_ parent: URL, name: String, ext: String? = nil) -> URL {
        let fm = FileManager.default
        func url(_ n: Int) -> URL {
            let base = n == 1 ? name : "\(name) \(n)"
            return ext.map { parent.appendingPathComponent(base).appendingPathExtension($0) } ?? parent.appendingPathComponent(base, isDirectory: true)
        }
        var n = 1
        while fm.fileExists(atPath: url(n).path) { n += 1 }
        return url(n)
    }

    static func writeFolder(
        title: String, items: [Item], orderedIDs: [String], clusters: [CanvasCluster], options: WebExportOptions,
        layout: LibraryLayout, parent: URL, progress: @Sendable (Int, Int) -> Void
    ) throws -> WebExportReport {
        let fm = FileManager.default
        let folder = uniqueURL(parent, name: safeName(title))
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        do {
            var (entries, report) = try gather(items: items, options: options, layout: layout, folder: folder, progress: progress)
            let data = try pageData(title: title, entries: entries, orderedIDs: orderedIDs, clusters: clusters, resolve: { $0 })
            try ("window.GRAILS_SHARE = " + data.json + ";\n").write(to: folder.appendingPathComponent("data.js"), atomically: true, encoding: .utf8)
            try WebExportViewer.html(title: title, inlineData: nil).write(to: folder.appendingPathComponent("index.html"), atomically: true, encoding: .utf8)
            entries = [:]
            report.bytes = directorySize(folder)
            if options.makeZip {
                let zip = folder.deletingLastPathComponent().appendingPathComponent(folder.lastPathComponent + ".zip")
                try? fm.removeItem(at: zip)
                let p = Process()
                p.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
                p.arguments = ["-c", "-k", "--keepParent", folder.path, zip.path]
                try p.run(); p.waitUntilExit()
                if p.terminationStatus == 0 { report.zip = zip }
            }
            return report
        } catch {
            try? fm.removeItem(at: folder)
            throw error
        }
    }

    static func writeSingleFile(
        title: String, items: [Item], orderedIDs: [String], clusters: [CanvasCluster], options: WebExportOptions,
        layout: LibraryLayout, parent: URL, progress: @Sendable (Int, Int) -> Void
    ) throws -> WebExportReport {
        let fm = FileManager.default
        let work = fm.temporaryDirectory.appendingPathComponent("grails-share-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: work) }
        var (entries, report) = try gather(items: items, options: options, layout: layout, folder: work, progress: progress)
        let data = try pageData(title: title, entries: entries, orderedIDs: orderedIDs, clusters: clusters, resolve: { rel in dataURI(work.appendingPathComponent(rel)) })
        entries = [:]
        let file = uniqueURL(parent, name: safeName(title), ext: "html")
        try WebExportViewer.html(title: title, inlineData: data.json).write(to: file, atomically: true, encoding: .utf8)
        report.file = file
        report.bytes = (try? fm.attributesOfItem(atPath: file.path)[.size] as? Int64) ?? 0
        return report
    }

    static func dataURI(_ url: URL) -> String {
        guard let data = try? Data(contentsOf: url) else { return "" }
        let ext = url.pathExtension.lowercased()
        let mime = ["jpg": "image/jpeg", "jpeg": "image/jpeg", "png": "image/png", "gif": "image/gif", "svg": "image/svg+xml", "mp4": "video/mp4", "m4v": "video/mp4", "mov": "video/quicktime", "webm": "video/webm"][ext] ?? "application/octet-stream"
        return "data:\(mime);base64," + data.base64EncodedString()
    }

    // MARK: One item

    static func prepare(_ item: Item, layout: LibraryLayout, folder: URL, options: WebExportOptions, report: inout WebExportReport) -> Entry? {
        let fm = FileManager.default
        let dir = layout.itemDir(item.id)
        let original = item.file.map { dir.appendingPathComponent($0) }
        let originalLocal = original.map { fm.fileExists(atPath: $0.path) && FileAvailability.of($0) == .local } ?? false
        let thumbSrc = layout.thumbURL(item.id)
        let snapshot = layout.snapshotURL(item.id)
        let hasThumb = fm.fileExists(atPath: thumbSrc.path) && FileAvailability.of(thumbSrc) == .local

        let source = options.includeSources ? (item.source?.pageUrl ?? item.source?.url).flatMap { URL(string: $0)?.scheme?.hasPrefix("http") == true ? $0 : nil } : nil
        let author = options.includeSources ? item.source?.author : nil
        var entry = Entry(id: item.id, name: item.name, kind: "image", w: item.width ?? 0, h: item.height ?? 0, thumb: "", full: "", video: nil, source: source, author: author)

        func copy(_ from: URL, to rel: String) -> Bool {
            let dst = folder.appendingPathComponent(rel)
            do { try fm.copyItem(at: from, to: dst); return true } catch { return false }
        }

        // a single file carries one picture per item: the resized original where there is one
        if options.singleImage, item.kind == .image, originalLocal, let o = original, !["gif", "svg"].contains((item.ext ?? o.pathExtension).lowercased()),
           let rel = downscale(o, to: folder.appendingPathComponent("media/\(item.id)"), maxEdge: options.maxEdge, quality: options.quality, forceJPEG: false) {
            entry.thumb = "media/" + rel; entry.full = entry.thumb
            if entry.w == 0 || entry.h == 0, let s = imageSize(folder.appendingPathComponent(entry.thumb)) { entry.w = s.0; entry.h = s.1 }
            return entry
        }

        // the small picture every kind has
        let thumbRel = "thumbs/\(item.id).jpg"
        var haveThumb = false
        switch item.kind {
        case .link:
            let pic = fm.fileExists(atPath: snapshot.path) ? snapshot : thumbSrc
            haveThumb = fm.fileExists(atPath: pic.path) && copy(pic, to: thumbRel)
            entry.kind = "link"
            entry.source = (item.source?.pageUrl ?? item.source?.url).flatMap { URL(string: $0)?.scheme?.hasPrefix("http") == true ? $0 : nil }
        default:
            if hasThumb { haveThumb = copy(thumbSrc, to: thumbRel) }
            else if originalLocal, let o = original { haveThumb = downscale(o, to: folder.appendingPathComponent(thumbRel), maxEdge: 512, quality: options.quality, forceJPEG: true) != nil }
        }
        guard haveThumb else { return nil }
        entry.thumb = thumbRel
        if entry.w == 0 || entry.h == 0, let s = imageSize(folder.appendingPathComponent(thumbRel)) { entry.w = s.0; entry.h = s.1 }
        entry.full = thumbRel

        guard originalLocal, let o = original, item.kind != .link else {
            if item.kind != .link { report.thumbnailOnly += 1 }
            return entry
        }
        let ext = (item.ext ?? o.pathExtension).lowercased()
        let size = (try? fm.attributesOfItem(atPath: o.path)[.size] as? Int64) ?? 0
        switch item.kind {
        case .video:
            entry.kind = "video"
            if ["mp4", "m4v", "mov", "webm"].contains(ext), size <= options.maxVideoBytes, copy(o, to: "media/\(item.id).\(ext)") { entry.video = "media/\(item.id).\(ext)" }
            else { report.thumbnailOnly += 1 }
        case .image:
            if ext == "gif" {
                entry.kind = "gif"
                if size <= options.maxGIFBytes, copy(o, to: "media/\(item.id).gif") { entry.full = "media/\(item.id).gif" } else { report.thumbnailOnly += 1 }
            } else if ext == "svg" {
                if copy(o, to: "media/\(item.id).svg") { entry.full = "media/\(item.id).svg" }
            } else if let rel = downscale(o, to: folder.appendingPathComponent("media/\(item.id)"), maxEdge: options.maxEdge, quality: options.quality, forceJPEG: false) {
                entry.full = "media/" + rel
            } else { report.thumbnailOnly += 1 }
        default:
            report.thumbnailOnly += 1
        }
        return entry
    }

    /// Writes a resized copy (JPEG, or PNG when the picture has transparency); returns the file name written.
    static func downscale(_ src: URL, to base: URL, maxEdge: Int, quality: Double = 0.86, forceJPEG: Bool) -> String? {
        guard let source = CGImageSourceCreateWithURL(src as CFURL, nil) else { return nil }
        let opts: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: maxEdge]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, opts as CFDictionary) else { return nil }
        let alpha: Bool = { switch image.alphaInfo { case .none, .noneSkipFirst, .noneSkipLast: false; default: true } }()
        let png = alpha && !forceJPEG
        let target = png ? base.appendingPathExtension("png") : (base.pathExtension == "jpg" ? base : base.appendingPathExtension("jpg"))
        guard let dest = CGImageDestinationCreateWithURL(target as CFURL, (png ? UTType.png : UTType.jpeg).identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, image, png ? nil : [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        return CGImageDestinationFinalize(dest) ? target.lastPathComponent : nil
    }

    static func imageSize(_ url: URL) -> (Int, Int)? {
        guard let s = CGImageSourceCreateWithURL(url as CFURL, nil), let p = CGImageSourceCopyPropertiesAtIndex(s, 0, nil) as? [CFString: Any],
              let w = p[kCGImagePropertyPixelWidth] as? Int, let h = p[kCGImagePropertyPixelHeight] as? Int else { return nil }
        return (w, h)
    }

    static func safeName(_ title: String) -> String {
        let bad = CharacterSet(charactersIn: "/\\:?*\"<>|").union(.controlCharacters)
        let s = title.components(separatedBy: bad).joined(separator: " ").replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return s.isEmpty ? "Grails Share" : String(s.prefix(80))
    }

    static func directorySize(_ url: URL) -> Int64 {
        guard let e = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
        return e.compactMap { ($0 as? URL).flatMap { try? $0.resourceValues(forKeys: [.fileSizeKey]).fileSize } }.reduce(0) { $0 + Int64($1) }
    }
}
