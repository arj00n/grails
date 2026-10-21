import AppKit
import SwiftUI
import Testing
@testable import GrailsDesign

@Suite struct PersonRowTests {
    /// Hidden actions are absent: the row is the same width and the same pixels as a row that has no actions.
    @Test @MainActor func hiddenActionsTakeNoSpaceAndRenderNothing() {
        let subtitle = "Expires tomorrow, 4:02 AM"
        let plain = GrailsPersonRow("member@studio.com", subtitle: subtitle, role: "Member", pending: true)
        let hidden = GrailsPersonRow("member@studio.com", subtitle: subtitle, role: "Member", pending: true) {
            GrailsButton("Copy link", kind: .quiet) {}
            GrailsButton("Resend", kind: .quiet) {}
            GrailsButton("Revoke", kind: .quiet) {}
        }
        let shown = GrailsPersonRow("member@studio.com", subtitle: subtitle, role: "Member", pending: true, revealed: true) {
            GrailsButton("Copy link", kind: .quiet) {}
            GrailsButton("Resend", kind: .quiet) {}
            GrailsButton("Revoke", kind: .quiet) {}
        }

        let plainWidth = fittedWidth(of: plain)
        let hiddenWidth = fittedWidth(of: hidden)
        let shownWidth = fittedWidth(of: shown)
        #expect(plainWidth > 200)
        #expect(hiddenWidth == plainWidth)
        #expect(shownWidth > hiddenWidth + 40)

        let size = CGSize(width: 520, height: 52)
        let plainPixels = pixels(of: plain, size: size)
        let hiddenPixels = pixels(of: hidden, size: size)
        #expect(!plainPixels.isEmpty)
        #expect(hiddenPixels == plainPixels)
        #expect(pixels(of: shown, size: size) != plainPixels)
    }

    @MainActor
    private func fittedWidth<V: View>(of view: V) -> CGFloat {
        let host = NSHostingView(rootView: view.fixedSize())
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 10, height: 10), styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        return host.fittingSize.width
    }

    @MainActor
    private func pixels<V: View>(of view: V, size: CGSize) -> [UInt8] {
        let host = NSHostingView(rootView: view.frame(width: size.width, height: size.height))
        host.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return [] }
        host.cacheDisplay(in: host.bounds, to: rep)
        guard let data = rep.bitmapData else { return [] }
        return Array(UnsafeBufferPointer(start: data, count: rep.bytesPerRow * rep.pixelsHigh))
    }
}
