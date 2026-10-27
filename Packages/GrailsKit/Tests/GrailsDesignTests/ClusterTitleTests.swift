import AppKit
import Testing
@testable import GrailsDesign

@Suite struct ClusterTitleTests {
    /// SF Pro Rounded Semibold, the face the app draws titles with.
    private static func title(_ size: CGFloat) -> NSFont { ChromeNSFont.title(size) }

    @Test @MainActor func diwaliIsUprightAndNotClipped() {
        let font = Self.title(20)
        let line = GrailsClusterTitle.lineHeight(for: font)
        #expect(line >= font.ascender + abs(font.descender) - 0.5)

        let host = FlipHost(frame: NSRect(x: 0, y: 0, width: 280, height: 80))
        host.wantsLayer = true
        host.layer?.backgroundColor = NSColor.white.cgColor
        let title = GrailsClusterTitle(frame: NSRect(x: 8, y: 8, width: 240, height: line))
        title.font = font
        title.textColor = .black
        title.stringValue = "Diwali"
        #expect(title.clipsToBounds == false)
        #expect(abs(title.frame.height - line) < 0.5)
        host.addSubview(title)

        let reference = ReferenceLine(frame: host.frame)
        reference.font = font
        reference.string = "Diwali"
        reference.line = line

        let titleRep = render(host)
        let referenceRep = render(reference)
        let titleInk = ink(titleRep)
        let referenceInk = ink(referenceRep)
        #expect(!titleInk.points.isEmpty && !referenceInk.points.isEmpty)
        // The tail of "a" is in the last ink rows. Clipping drops them, so the title would be shorter than the reference.
        #expect(titleInk.rows + 1 >= referenceInk.rows, "title ink \(titleInk.rows) rows, reference \(referenceInk.rows)")
        let upright = mismatch(titleInk, referenceInk)
        let upsideDown = mismatch(titleInk, flipped(referenceInk))
        let mirroredWord = mismatch(titleInk, mirrored(referenceInk))
        #expect(upright < upsideDown, "upright \(upright) vs upside down \(upsideDown)")
        #expect(upright < mirroredWord, "upright \(upright) vs mirrored \(mirroredWord)")
    }

    /// The grid draws a the title name and a the count in one field, then sizes the field to its intrinsic width.
    /// The last digit ("Untitled 2", "All 178") is clipped when that width is only the string box.
    @Test @MainActor func clusterCountIsNotClipped() {
        for sample in [(name: "Untitled", count: 2, noted: false), (name: "All", count: 178, noted: false), (name: "All", count: 178, noted: true)] {
            let line = Self.clusterLine(sample.name, count: sample.count, noted: sample.noted)
            let field = GrailsClusterTitle(frame: .zero)
            field.font = Self.title(CGFloat(TypeScale.page))
            field.textColor = .black
            field.attributedStringValue = line
            let raw = ceil(line.size().width)
            let fitted = field.intrinsicContentSize.width
            #expect(GrailsClusterTitle.sideInset >= 2)
            #expect(fitted == ceil(fitted))
            #expect(fitted + 0.01 >= raw + GrailsClusterTitle.sideInset * 2, "\(sample.name) \(sample.count) fitted \(fitted) raw \(raw)")
            #expect(fitted < raw + 40, "measurement ran away: fitted \(fitted) raw \(raw)")
        }

        let narrow = Self.titleField("All", count: 17)
        let wide = Self.titleField("All", count: 178)
        #expect(wide.intrinsicContentSize.width > narrow.intrinsicContentSize.width + 4)

        for sample in [(name: "Untitled", count: 2), (name: "All", count: 178)] {
            let field = Self.titleField(sample.name, count: sample.count)
            let fitted = field.intrinsicContentSize
            field.frame = NSRect(origin: .zero, size: fitted)
            let host = FlipHost(frame: field.frame)
            host.wantsLayer = true
            host.layer?.masksToBounds = true
            host.layer?.backgroundColor = NSColor.white.cgColor
            host.addSubview(field)
            let reference = WideLine(frame: NSRect(x: 0, y: 0, width: fitted.width + 120, height: max(fitted.height, 40) + 30))
            reference.shown = field.attributedStringValue
            let fieldSpan = inkSpan(render(host))
            let referenceSpan = inkSpan(render(reference))
            #expect(fieldSpan > 8, "\(sample.name) drew no ink")
            #expect(fieldSpan + 2 >= referenceSpan, "\(sample.name) \(sample.count) field \(fieldSpan) reference \(referenceSpan)")
            #expect(fieldSpan < fitted.width - 0.5, "\(sample.name) ink filled the field (\(fieldSpan) of \(fitted.width))")
        }
    }

    /// Same string the grid builds: the title title, three spaces, the count, and an optional note.
    private static func clusterLine(_ name: String, count: Int, noted: Bool = false) -> NSAttributedString {
        let text = NSMutableAttributedString(string: name, attributes: [
            .font: title(CGFloat(TypeScale.page)),
            .foregroundColor: NSColor.black,
        ])
        text.append(NSAttributedString(string: "   \(count)", attributes: [
            .font: body(16),
            .foregroundColor: NSColor.black,
        ]))
        if noted {
            text.append(NSAttributedString(string: "  note", attributes: [
                .font: body(13),
                .foregroundColor: NSColor.black,
            ]))
        }
        return text
    }

    private static func titleField(_ name: String, count: Int) -> GrailsClusterTitle {
        let field = GrailsClusterTitle(frame: .zero)
        field.font = title(CGFloat(TypeScale.page))
        field.textColor = .black
        field.attributedStringValue = clusterLine(name, count: count)
        return field
    }

    /// SF Pro Rounded with tabular digits, the face the app draws counts with.
    private static func body(_ size: CGFloat) -> NSFont { ChromeNSFont.count(size) }

    @MainActor
    private func render(_ view: NSView) -> NSBitmapImageRep {
        let window = NSWindow(contentRect: view.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.backgroundColor = .white
        window.contentView = view
        view.layoutSubtreeIfNeeded()
        view.display()
        let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
        view.cacheDisplay(in: view.bounds, to: rep)
        return rep
    }

    private struct Ink {
        var points: Set<UInt64>
        var width: Int
        var height: Int
        var rows: Int
    }

    private func isInk(_ rep: NSBitmapImageRep, _ x: Int, _ y: Int) -> Bool {
        guard let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { return false }
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        c.getRed(&r, green: &g, blue: &b, alpha: &a)
        return a > 0.3 && r < 0.45
    }

    /// Dark pixels, origin at the ink's top-left, so a flip or a mirror can be compared without the margin.
    private func ink(_ rep: NSBitmapImageRep) -> Ink {
        var raw: [(Int, Int)] = []
        for y in 0..<rep.pixelsHigh {
            for x in 0..<rep.pixelsWide where isInk(rep, x, y) {
                raw.append((x, y))
            }
        }
        guard let minX = raw.map(\.0).min(), let maxX = raw.map(\.0).max(),
              let minY = raw.map(\.1).min(), let maxY = raw.map(\.1).max() else {
            return Ink(points: [], width: 0, height: 0, rows: 0)
        }
        var points = Set<UInt64>()
        var usedRows = Set<Int>()
        for (x, y) in raw {
            let rx = x - minX
            let ry = y - minY
            points.insert((UInt64(rx) << 32) | UInt64(ry))
            usedRows.insert(ry)
        }
        return Ink(points: points, width: maxX - minX + 1, height: maxY - minY + 1, rows: usedRows.count)
    }

    /// Width of the dark pixels, in points.
    private func inkSpan(_ rep: NSBitmapImageRep) -> CGFloat {
        let marks = ink(rep)
        guard marks.width > 0, rep.pixelsWide > 0 else { return 0 }
        let scale = CGFloat(rep.pixelsWide) / max(CGFloat(rep.size.width), 1)
        return CGFloat(marks.width) / max(scale, 1)
    }

    private func pack(_ x: Int, _ y: Int) -> UInt64 { (UInt64(x) << 32) | UInt64(y) }

    private func mismatch(_ a: Ink, _ b: Ink) -> Int {
        var best = Int.max
        for dy in -4...4 {
            for dx in -4...4 {
                var moved = Set<UInt64>()
                for p in a.points {
                    let x = Int(p >> 32) + dx
                    let y = Int(p & 0xffffffff) + dy
                    if x >= 0, y >= 0 { moved.insert(pack(x, y)) }
                }
                best = min(best, moved.symmetricDifference(b.points).count)
            }
        }
        return best
    }

    private func flipped(_ ink: Ink) -> Ink {
        var points = Set<UInt64>()
        for p in ink.points {
            let x = Int(p >> 32)
            let y = Int(p & 0xffffffff)
            points.insert(pack(x, ink.height - 1 - y))
        }
        return Ink(points: points, width: ink.width, height: ink.height, rows: ink.rows)
    }

    private func mirrored(_ ink: Ink) -> Ink {
        var points = Set<UInt64>()
        for p in ink.points {
            let x = Int(p >> 32)
            let y = Int(p & 0xffffffff)
            points.insert(pack(ink.width - 1 - x, y))
        }
        return Ink(points: points, width: ink.width, height: ink.height, rows: ink.rows)
    }
}

private final class FlipHost: NSView {
    override var isFlipped: Bool { true }
}

/// The cluster string drawn in a wide flipped view, so the comparison can see a digit the field cut off.
private final class WideLine: NSView {
    override var isFlipped: Bool { true }
    var shown = NSAttributedString()
    override func draw(_ dirtyRect: NSRect) {
        NSColor.white.setFill()
        bounds.fill()
        shown.draw(with: NSRect(x: 0, y: 4, width: bounds.width, height: max(1, bounds.height - 4)), options: [.usesLineFragmentOrigin, .usesFontLeading])
    }
}

/// AppKit's own string drawing, in a flipped view: the orientation a title has to match.
private final class ReferenceLine: NSView {
    override var isFlipped: Bool { true }
    var font = NSFont.systemFont(ofSize: 13)
    var string = ""
    var line: CGFloat = 20
    override func draw(_ dirtyRect: NSRect) {
        NSColor.white.setFill()
        bounds.fill()
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.black]
        (string as NSString).draw(in: NSRect(x: 8, y: 8, width: bounds.width - 16, height: line), withAttributes: attrs)
    }
}
