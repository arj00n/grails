#if os(macOS)
import AppKit
import Foundation
import Testing
@testable import GrailsDesign

@Suite struct DesignSnapshotTests {
    @Test @MainActor func rendersGalleryAndBucketSheet() throws {
        let dir = ProcessInfo.processInfo.environment["GRAILS_DESIGN_ARTIFACTS"].map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? FileManager.default.temporaryDirectory.appendingPathComponent("grails-design-\(UUID().uuidString)", isDirectory: true)
        try DesignSnapshot.write(to: dir)
        for name in ["bucket-light", "bucket-dark", "gallery-light", "gallery-dark", "avatar-settings-light", "avatar-settings-dark"] {
            let url = dir.appendingPathComponent(name + ".png")
            let data = try Data(contentsOf: url)
            #expect(data.count > 1000, "\(name) was empty")
        }
    }

    /// A short sheet separates the footer with space. A scrolling sheet draws one hairline.
    @Test @MainActor func footerDividerOnlyBetweenBodyAndFooter() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("grails-divider-\(UUID().uuidString)", isDirectory: true)
        try DesignSnapshot.write(to: dir)
        let both = try dividerRuns(dir.appendingPathComponent("modal-both.png"))
        let body = try dividerRuns(dir.appendingPathComponent("modal-body.png"))
        let footer = try dividerRuns(dir.appendingPathComponent("modal-footer.png"))
        let scroll = try dividerRuns(dir.appendingPathComponent("modal-scroll.png"))
        #expect(both == 0, "a short body draws no rule")
        #expect(body == 0, "an empty footer draws no rule")
        #expect(footer == 0, "an empty body draws no rule")
        #expect(scroll == 1, "a scrolling body draws one rule")
    }

    /// Dark mode draws the gray hairline token on a scrolling sheet, and a short invite draws none.
    @Test @MainActor func darkHairlineIsTheToken() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("grails-dark-rule-\(UUID().uuidString)", isDirectory: true)
        try DesignSnapshot.write(to: dir)
        let url = dir.appendingPathComponent("modal-scroll-dark.png")
        let invite = dir.appendingPathComponent("invite-dark.png")
        #expect(try dividerRuns(url, dark: true) >= 1, "dark scrolling sheet draws the hairline token")
        #expect(try dividerRuns(url, dark: false) == 0, "dark sheet does not draw the light hairline")
        #expect(try whiteRuns(url) == 0, "dark sheet has no white rule")
        let inviteRuns = try dividerRuns(invite, dark: true)
        #expect(inviteRuns == 0, "a short invite draws no rule (\(inviteRuns))")
    }

    /// Rows that are mostly the hairline colour. A divider is only a 1- or 2-point run with a different row above and below.
    /// The PNG is 2x, and a one-point line is antialiased. Match a point-row, not every device pixel.
    private func dividerRuns(_ url: URL, dark: Bool = false) throws -> Int {
        let data = try Data(contentsOf: url)
        guard let rep = NSBitmapImageRep(data: data) else { return -1 }
        let target = Palette.rgb(.hairline, dark: dark)
        // The rendered dark window sits close to the hairline hex. A pixel counts only when it is the rule, not the fill.
        let fill = dark ? rep.colorAt(x: rep.pixelsWide / 2, y: min(48, rep.pixelsHigh - 1))?.usingColorSpace(.sRGB) : nil
        let fromSize = max(1, Int((Double(rep.pixelsHigh) / max(Double(rep.size.height), 1)).rounded()))
        // A 2x bitmap sometimes reports its pixel size as points. The modal is 440pt, so a wider image is 2x.
        let scale = rep.pixelsWide > Int(ModalMetrics.width) + 40 ? max(fromSize, 2) : fromSize
        var hairline: [Bool] = []
        var y = 0
        while y < rep.pixelsHigh {
            let band = min(scale, rep.pixelsHigh - y)
            var best = 0
            for offset in 0..<band {
                var hits = 0
                for x in 0..<rep.pixelsWide {
                    guard let color = rep.colorAt(x: x, y: y + offset)?.usingColorSpace(.sRGB) else { continue }
                    if isHairline(color, target: target, fill: fill, dark: dark) { hits += 1 }
                }
                best = max(best, hits)
            }
            // A field border is inset. The footer rule runs the full width of the sheet.
            hairline.append(rep.pixelsWide > 0 && Double(best) / Double(rep.pixelsWide) > 0.92)
            y += band
        }
        return ModalDividerScan.runs(hairline)
    }

    /// Dark fills render a little lighter than the hex, close enough to the hairline that a gap would count as a rule.
    private func isHairline(_ color: NSColor, target: (r: Double, g: Double, b: Double), fill: NSColor?, dark: Bool) -> Bool {
        let dh = max(abs(color.redComponent - target.r), abs(color.greenComponent - target.g), abs(color.blueComponent - target.b))
        guard dh < (dark ? 0.08 : 0.04) else { return false }
        guard dark, let fill else { return true }
        let df = max(
            abs(color.redComponent - fill.redComponent),
            abs(color.greenComponent - fill.greenComponent),
            abs(color.blueComponent - fill.blueComponent)
        )
        return dh + 0.02 < df
    }

    private func whiteRuns(_ url: URL) throws -> Int {
        let data = try Data(contentsOf: url)
        guard let rep = NSBitmapImageRep(data: data) else { return -1 }
        var white: [Bool] = []
        white.reserveCapacity(rep.pixelsHigh)
        for y in 0..<rep.pixelsHigh {
            var hits = 0
            for x in 0..<rep.pixelsWide {
                guard let color = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
                if color.redComponent > 0.96, color.greenComponent > 0.96, color.blueComponent > 0.96 {
                    hits += 1
                }
            }
            white.append(rep.pixelsWide > 0 && Double(hits) / Double(rep.pixelsWide) > 0.85)
        }
        return ModalDividerScan.runs(white)
    }
}
#endif
