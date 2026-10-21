import AppKit
import SwiftUI
import Testing
@testable import GrailsDesign

@Suite struct SpringSheetTests {
    /// The deck is presented from the window, the way the app does, and comes up at the modal size with a card in it.
    @Test @MainActor func sheetPresentsAtFullSizeWithACard() {
        let measure = SpringMeasure()
        let host = NSHostingView(rootView: SpringSheetHost(measure: measure))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1100, height: 800),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.layoutIfNeeded()
        window.makeKeyAndOrderFront(nil)
        let deadline = Date().addingTimeInterval(2.5)
        var presented: NSWindow?
        while Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
            presented = window.sheets.first ?? window.attachedSheet
            if presented == nil {
                presented = NSApp.windows.first { candidate in
                    candidate !== window && candidate.isVisible && candidate.frame.width > 80 && candidate.frame.height > 80
                }
            }
            if let presented, presented.frame.width > 200, presented.frame.height > SpringSheetLayout.cardSide, measure.card.height > 200 {
                break
            }
        }
        let sheet = presented
        let width = sheet?.contentView?.bounds.width ?? sheet?.frame.width ?? 0
        let height = sheet?.contentView?.bounds.height ?? sheet?.frame.height ?? 0
        #expect(sheet != nil, "sheet did not present")
        #expect(width + 0.5 >= CGFloat(ModalMetrics.width), "sheet width \(width)")
        #expect(height + 0.5 >= SpringSheetLayout.deckHeight, "sheet height \(height)")
        #expect(measure.card.width + 0.5 >= SpringSheetLayout.cardSide, "card \(measure.card)")
        #expect(measure.card.height + 0.5 >= SpringSheetLayout.cardSide, "card \(measure.card)")
        window.orderOut(nil)
    }

    /// A portrait original fills the square and does not stretch the card.
    @Test @MainActor func aPortraitBitmapStaysSquare() {
        let image = portrait()
        let measure = SpringMeasure()
        let host = NSHostingView(rootView: PortraitHost(image: image, measure: measure))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 900),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.layoutIfNeeded()
        window.makeKeyAndOrderFront(nil)
        let deadline = Date().addingTimeInterval(1.5)
        while Date() < deadline, abs(measure.card.width - SpringSheetLayout.cardSide) > 0.5 {
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        #expect(abs(measure.card.width - SpringSheetLayout.cardSide) < 1, "width \(measure.card)")
        #expect(abs(measure.card.height - SpringSheetLayout.cardSide) < 1, "height \(measure.card)")
        #expect(image.size.height > image.size.width)
        window.orderOut(nil)
    }

    /// Arrow keys reach the deck's key view, and that view draws no system ring.
    @Test @MainActor func theDeckKeyViewTakesArrowsWithoutASystemRing() {
        let view = GrailsKeyView(frame: NSRect(x: 0, y: 0, width: 200, height: 200))
        #expect(view.focusRingType == .none)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 200),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = view
        window.makeKeyAndOrderFront(nil)
        view.claimFocus()
        #expect(window.firstResponder === view)
        var codes: [UInt16] = []
        view.onKey = { code in
            codes.append(code)
            return true
        }
        for code in [UInt16(123), 124, 51, 36] {
            let event = NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                windowNumber: window.windowNumber, context: nil, characters: "",
                charactersIgnoringModifiers: "", isARepeat: false, keyCode: code
            )
            if let event { view.keyDown(with: event) }
        }
        #expect(codes == [123, 124, 51, 36])
        #expect(view.focusRingType == .none)
        window.orderOut(nil)
    }

    private func portrait() -> NSImage {
        let image = NSImage(size: NSSize(width: 80, height: 140))
        image.lockFocus()
        NSColor.black.setFill()
        NSRect(x: 0, y: 0, width: 80, height: 140).fill()
        image.unlockFocus()
        return image
    }
}

@MainActor
private final class SpringMeasure {
    var card = CGSize.zero
}

private struct PortraitHost: View {
    var image: NSImage
    var measure: SpringMeasure

    var body: some View {
        GrailsSquareMedia(side: SpringSheetLayout.cardSide) {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
        }
        .background {
            GeometryReader { proxy in
                Color.clear.preference(key: SpringCardSizeKey.self, value: proxy.size)
            }
        }
        .onPreferenceChange(SpringCardSizeKey.self) { measure.card = $0 }
    }
}

private struct SpringSheetHost: View {
    var measure: SpringMeasure
    @State private var show = false

    var body: some View {
        Color.clear
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .sheet(isPresented: $show) {
                SpringProbe(measure: measure)
            }
            .onAppear { show = true }
    }
}

private struct SpringProbe: View {
    var measure: SpringMeasure

    var body: some View {
        GrailsModal(title: "Spring Cleaning", step: "spring", identifier: "spring-cleaning", onClose: {}) {
            ZStack {
                RoundedRectangle(cornerRadius: CGFloat(RadiusToken.card), style: .continuous)
                    .fill(GrailsColor.fill)
                SpringZeroHost()
            }
            .frame(width: SpringSheetLayout.cardSide, height: SpringSheetLayout.cardSide)
            .accessibilityIdentifier("spring-card")
            .background {
                GeometryReader { proxy in
                    Color.clear.preference(key: SpringCardSizeKey.self, value: proxy.size)
                }
            }
        } footer: {
            HStack {
                Text("Keep")
                Spacer()
                Text("Chuck")
            }
        }
        .onPreferenceChange(SpringCardSizeKey.self) { measure.card = $0 }
    }
}

/// A media view with no intrinsic size. The card frame, not this view, has to decide the sheet.
private struct SpringZeroHost: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.wantsLayer = true
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

private struct SpringCardSizeKey: PreferenceKey {
    static let defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        let next = nextValue()
        if next.width > value.width { value = next }
    }
}
