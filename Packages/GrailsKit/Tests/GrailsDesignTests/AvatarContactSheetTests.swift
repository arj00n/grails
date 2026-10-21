import AppKit
import Foundation
import Testing
@testable import GrailsDesign

/// Renders 24 sample blobs at 96, 30, 24 and 20 pt, light and dark, for review. Writes PNGs only when
/// `GRAILS_AVATAR_SHEET` names a folder (Scripts/avatar-contact-sheet.sh sets it); otherwise it just draws them.
@Suite struct AvatarContactSheetTests {
    static let ids = (1...24).map { String(format: "sample-member-%02d", $0) }

    @Test func contactSheet() throws {
        let folder = ProcessInfo.processInfo.environment["GRAILS_AVATAR_SHEET"].map { URL(fileURLWithPath: $0, isDirectory: true) }
        if let folder { try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true) }
        for dark in [false, true] {
            let png = try #require(Self.sheet(dark: dark))
            #expect(png.count > 1000)
            if let folder { try png.write(to: folder.appendingPathComponent(dark ? "blobs-dark.png" : "blobs-light.png")) }
        }
    }

    static func sheet(dark: Bool) -> Data? {
        let scale: CGFloat = 2, big: CGFloat = 96, small: [CGFloat] = [30, 24, 20]
        let columns = 6, gap: CGFloat = 28
        let cellW = big + gap, cellH = big + 12 + small[0] + gap
        let width = CGFloat(columns) * cellW + gap, height = CGFloat(ids.count / columns) * cellH + gap
        let px = (w: Int(width * scale), h: Int(height * scale))
        guard let ctx = CGContext(data: nil, width: px.w, height: px.h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.scaleBy(x: scale, y: scale)
        ctx.setFillColor(dark ? CGColor(srgbRed: 0.11, green: 0.11, blue: 0.12, alpha: 1) : CGColor(srgbRed: 0.97, green: 0.965, blue: 0.95, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        ctx.interpolationQuality = .none
        for (i, id) in ids.enumerated() {
            let spec = DitherAvatarSpec(memberID: id, name: id)
            let x = gap + CGFloat(i % columns) * cellW
            let top = height - gap - CGFloat(i / columns) * cellH // CG is y-up
            func draw(_ side: CGFloat, at origin: CGPoint) {
                guard let image = DitherAvatar.image(spec, side: side, scale: scale, dark: dark) else { return }
                let rect = CGRect(origin: origin, size: CGSize(width: side, height: side))
                ctx.saveGState()
                ctx.addEllipse(in: rect)
                ctx.clip()
                ctx.draw(image, in: rect)
                ctx.restoreGState()
            }
            draw(big, at: CGPoint(x: x, y: top - big))
            var sx = x
            for side in small {
                draw(side, at: CGPoint(x: sx, y: top - big - 12 - side))
                sx += side + 8
            }
        }
        guard let cg = ctx.makeImage() else { return nil }
        return NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])
    }
}
