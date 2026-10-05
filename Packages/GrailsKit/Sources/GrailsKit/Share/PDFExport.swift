import CoreGraphics
import CoreText
import Foundation
import ImageIO

extension WebExporter {
    private static let pageW = 1920.0, pageH = 1080.0, margin = 64.0

    static func writePDF(
        title: String, items: [Item], orderedIDs: [String], clusters: [CanvasCluster], includeSources: Bool,
        layout: LibraryLayout, parent: URL, progress: @Sendable (Int, Int) -> Void
    ) throws -> WebExportReport {
        let fm = FileManager.default
        let work = fm.temporaryDirectory.appendingPathComponent("grails-pdf-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: work) }
        var options = WebExportOptions(includeSources: includeSources, makeZip: false)
        options.maxEdge = 1600; options.quality = 0.82; options.singleImage = true
        options.maxVideoBytes = 0; options.maxGIFBytes = 0       // a page can't play: videos and GIFs show their poster
        var (entries, report) = try gather(items: items, options: options, layout: layout, folder: work, progress: progress)
        let data = try pageData(title: title, entries: entries, orderedIDs: orderedIDs, clusters: clusters, resolve: { $0 })
        let sections = data.sections

        let file = uniqueURL(parent, name: safeName(title), ext: "pdf")
        var box = CGRect(x: 0, y: 0, width: pageW, height: pageH)
        let info: [CFString: Any] = [kCGPDFContextTitle: title, kCGPDFContextCreator: "Grails"]
        guard let ctx = CGContext(file as CFURL, mediaBox: &box, info as CFDictionary) else { throw CaptureError.nothingToSave }

        var pageNumber = 0
        func beginPage() {
            ctx.beginPDFPage(nil)
            ctx.setFillColor(CGColor(gray: 0, alpha: 1))
            ctx.fill(box)
            pageNumber += 1
        }
        func endPage(footer: Bool = true) {
            if footer {
                draw("\(title)", at: CGPoint(x: margin, y: 30), size: 15, gray: 0.4, ctx: ctx, maxWidth: pageW - margin * 3)
                draw("\(pageNumber)", at: CGPoint(x: pageW - margin - 40, y: 30), size: 15, gray: 0.4, ctx: ctx, maxWidth: 40, rightAligned: true)
            }
            ctx.endPDFPage()
        }

        // cover
        beginPage()
        draw(title, at: CGPoint(x: margin + 20, y: pageH / 2 + 10), size: 84, weight: 0.4, gray: 0.95, ctx: ctx, maxWidth: pageW - margin * 2 - 40)
        let when = DateFormatter.localizedString(from: Date(), dateStyle: .long, timeStyle: .none)
        draw("\(entries.count) \(entries.count == 1 ? "item" : "items")  ·  \(when)", at: CGPoint(x: margin + 20, y: pageH / 2 - 56), size: 26, gray: 0.5, ctx: ctx, maxWidth: pageW - margin * 2)
        draw("Made with Grails", at: CGPoint(x: margin + 20, y: 56), size: 16, gray: 0.35, ctx: ctx, maxWidth: 400)
        endPage(footer: false)

        // pictures, section by section
        let headerH = 120.0
        let contentW = pageW - margin * 2
        let contentH = pageH - margin - headerH - 40
        for (si, section) in sections.enumerated() {
            let members = section.ids.filter { entries[$0] != nil }
            guard !members.isEmpty else { continue }
            let packed = ClusterLayout.pack(members.map { id in
                let e = entries[id]!
                return ClusterLayout.Entry(id: id, aspect: e.h > 0 ? Double(e.w) / Double(e.h) : 1)
            }, width: contentW, tile: 270)
            // pages of whole rows
            var pages: [[[String]]] = []
            var current: [[String]] = [], used = 0.0
            for row in packed.rows {
                let h = row.first.flatMap { packed.rects[$0]?.height } ?? 0
                if !current.isEmpty, used + h > contentH { pages.append(current); current = []; used = 0 }
                current.append(row); used += h
            }
            if !current.isEmpty { pages.append(current) }

            for (pi, rows) in pages.enumerated() {
                beginPage()
                let label = section.title.isEmpty ? (sections.count > 1 ? "Untitled" : "") : section.title
                if !label.isEmpty {
                    let suffix = pages.count > 1 ? "  \(pi + 1)/\(pages.count)" : ""
                    draw(label + suffix, at: CGPoint(x: margin, y: pageH - margin - 36), size: 34, weight: 0.4, gray: 0.92, ctx: ctx, maxWidth: contentW)
                }
                let top = pageH - margin - (label.isEmpty ? 0 : headerH)
                var y = 0.0
                let firstY = packed.rects[rows[0][0]]?.minY ?? 0
                for row in rows {
                    for id in row {
                        guard let r = packed.rects[id], let e = entries[id] else { continue }
                        let rect = CGRect(x: margin + r.minX, y: top - (r.minY - firstY) - r.height, width: r.width, height: r.height)
                        drawPicture(e, in: rect.insetBy(dx: 2, dy: 2), folder: work, includeSources: includeSources, ctx: ctx)
                        y = max(y, r.maxY)
                    }
                }
                endPage()
            }
            _ = si
        }
        ctx.closePDF()
        entries = [:]
        report.file = file
        report.bytes = (try? fm.attributesOfItem(atPath: file.path)[.size] as? Int64) ?? 0
        return report
    }

    private static func drawPicture(_ e: Entry, in rect: CGRect, folder: URL, includeSources: Bool, ctx: CGContext) {
        let url = folder.appendingPathComponent(e.thumb)
        ctx.saveGState()
        ctx.addPath(CGPath(roundedRect: rect, cornerWidth: 6, cornerHeight: 6, transform: nil))
        ctx.clip()
        ctx.setFillColor(CGColor(gray: 0.1, alpha: 1))
        ctx.fill(rect)
        if let src = CGImageSourceCreateWithURL(url as CFURL, nil), let img = CGImageSourceCreateImageAtIndex(src, 0, nil) {
            // fill the tile, cropping the overflow
            let scale = max(rect.width / CGFloat(img.width), rect.height / CGFloat(img.height))
            let w = CGFloat(img.width) * scale, h = CGFloat(img.height) * scale
            ctx.draw(img, in: CGRect(x: rect.midX - w / 2, y: rect.midY - h / 2, width: w, height: h))
        }
        ctx.restoreGState()
        let badge = e.kind == "video" ? "▶" : e.kind == "gif" ? "GIF" : ""
        if !badge.isEmpty {
            ctx.setFillColor(CGColor(gray: 0, alpha: 0.6))
            let b = CGRect(x: rect.minX + 10, y: rect.minY + 10, width: badge == "▶" ? 30 : 42, height: 24)
            ctx.addPath(CGPath(roundedRect: b, cornerWidth: 6, cornerHeight: 6, transform: nil)); ctx.fillPath()
            draw(badge, at: CGPoint(x: b.minX + 8, y: b.minY + 6), size: 12, gray: 1, ctx: ctx, maxWidth: 40)
        }
        if includeSources, let s = e.source, let link = URL(string: s) { ctx.setURL(link as CFURL, for: rect) }
    }

    private static func draw(_ text: String, at p: CGPoint, size: CGFloat, weight: CGFloat = 0, gray: CGFloat, ctx: CGContext, maxWidth: CGFloat, rightAligned: Bool = false) {
        let font = CTFontCreateUIFontForLanguage(weight > 0.2 ? .emphasizedSystem : .system, size, nil) ?? CTFontCreateWithName("Helvetica" as CFString, size, nil)
        let attrs: [NSAttributedString.Key: Any] = [.init(kCTFontAttributeName as String): font, .init(kCTForegroundColorAttributeName as String): CGColor(gray: gray, alpha: 1)]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attrs))
        let token = CTLineCreateWithAttributedString(NSAttributedString(string: "…", attributes: attrs))
        let fitted = CTLineCreateTruncatedLine(line, Double(maxWidth), .end, token) ?? line
        let width = CTLineGetTypographicBounds(fitted, nil, nil, nil)
        ctx.textPosition = CGPoint(x: rightAligned ? p.x + maxWidth - CGFloat(width) : p.x, y: p.y)
        CTLineDraw(fitted, ctx)
    }
}
