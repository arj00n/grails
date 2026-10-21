import AppKit
import SwiftUI
import Testing
@testable import GrailsDesign

@Suite struct SettingsGroupTests {
    /// The card stands off the page in both themes, and its rows are separated by space: a column through the card crosses
    /// the page, the card's edge and the card fill, never a rule between rows.
    @Test @MainActor func cardStandsOffThePageWithNoRuleBetweenRows() {
        for scheme in [ColorScheme.light, .dark] {
            // Tokens as this renderer draws them, so a colour-space shift does not count as a different colour.
            let card = swatch(.group, scheme: scheme), page = swatch(.canvas, scheme: scheme)
            #expect(!same(card, page), "the card and the page differ in \(scheme)")
            let column = column(of: group(), scheme: scheme)
            let onCard = column.filter { same($0, card) }
            let onPage = column.filter { same($0, page) }
            #expect(onCard.count > column.count / 2, "the card fills the group in \(scheme)")
            #expect(!onPage.isEmpty, "the page shows around the card in \(scheme)")
            #expect(ModalDividerScan.runs(column.map { !same($0, card) }) == 0, "no rule between rows in \(scheme)")

            // The same scan finds a rule when one is drawn, so the check above is not passing by accident.
            let ruled = self.column(of: ruledCard(), scheme: scheme)
            #expect(ModalDividerScan.runs(ruled.map { !same($0, card) }) == 1, "a drawn rule is found in \(scheme)")
        }
    }

    @Test func groupTokenIsAStepOffTheCanvas() {
        for dark in [false, true] {
            #expect(Palette.hex(.group, dark: dark) != Palette.hex(.canvas, dark: dark))
            #expect(Palette.contrast(.group, .canvas, dark: dark) < 1.2)
        }
        // Dark mode raises the card a step lighter than the page.
        let lum = { (t: Token) in Palette.rgb(t, dark: true) }
        #expect(lum(.group).r > lum(.canvas).r)
    }

    private let size = CGSize(width: 480, height: 220)

    @MainActor private func group() -> some View {
        GrailsSettingsGroup("Sidebar") {
            GrailsSettingsToggle("Collections", isOn: .constant(true))
            GrailsSettingsToggle("Smart Folders", isOn: .constant(false))
            GrailsSettingsToggle("Tags", isOn: .constant(true))
        }
    }

    @MainActor private func ruledCard() -> some View {
        VStack(spacing: 0) {
            GrailsSettingsRow("Collections")
            Rectangle().fill(GrailsColor.hairline).frame(height: 1)
            GrailsSettingsRow("Tags")
        }
        .background(GrailsInk(.group))
        .padding(.vertical, 20)
    }

    /// One column of pixels at 70% of the width, clear of the row labels and the controls.
    @MainActor private func column<V: View>(of view: V, scheme: ColorScheme) -> [NSColor] {
        let root = view
            .frame(width: size.width, height: size.height, alignment: .top)
            .background(GrailsColor.canvas)
            .environment(\.colorScheme, scheme)
        let host = NSHostingView(rootView: root)
        host.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return [] }
        host.cacheDisplay(in: host.bounds, to: rep)
        let x = Int(Double(rep.pixelsWide) * 0.7)
        return (0..<rep.pixelsHigh).compactMap { rep.colorAt(x: x, y: $0)?.usingColorSpace(.sRGB) }
    }

    @MainActor private func swatch(_ token: Token, scheme: ColorScheme) -> NSColor {
        let pixels = column(of: Rectangle().fill(GrailsInk(token)), scheme: scheme)
        return pixels[pixels.count / 2]
    }

    private func same(_ a: NSColor, _ b: NSColor) -> Bool {
        let tolerance = 1.5 / 255
        return abs(a.redComponent - b.redComponent) < tolerance && abs(a.greenComponent - b.greenComponent) < tolerance && abs(a.blueComponent - b.blueComponent) < tolerance
    }
}
