import AppKit
import SwiftUI
import Testing
@testable import GrailsDesign

/// A modal arrives as one piece. The window it sits in draws nothing; the card (frame, fill, shadow and contents) moves together
/// on the sheet spring; the scrim only fades.
@Suite(.serialized) @MainActor struct ModalEntranceTests {
    @Test func theScrimOnlyFadesAndTheCardSettlesFromTheTop() {
        for arrived in [false, true] {
            let scrim = ModalPresentation.scrim(arrived: arrived)
            #expect(scrim.scale == 1 && scrim.offsetY == 0)
            #expect(scrim.opacity == (arrived ? 1 : 0))
        }
        let from = ModalPresentation.card(arrived: false, reduceMotion: false)
        #expect(from.scale == Motion.overlayScale && from.offsetY == -Motion.overlayDrop)
        // the card does not fade in: it is there at once, a little small and high, and springs into place
        #expect(from.opacity == 1)
        #expect(ModalPresentation.card(arrived: true, reduceMotion: false) == .init(scale: 1, offsetY: 0, opacity: 1))
        // Reduce Motion: no scale and no drop, only a fade
        #expect(ModalPresentation.card(arrived: false, reduceMotion: true) == .init(scale: 1, offsetY: 0, opacity: 0))
        #expect(Motion.bounce > 0 && Motion.bounce(reduceMotion: true) == 0)
    }

    @Test func theModalWindowDrawsNothingOfItsOwn() throws {
        _ = NSApplication.shared
        let main = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 600), styleMask: [.titled], backing: .buffered, defer: false)
        main.isReleasedWhenClosed = false
        main.orderFront(nil)
        let layer = GrailsModalLayer()
        #expect(layer.present("feedback", from: main, onCancel: {}) { Text("Feedback").frame(width: 440, height: 200) })
        let w = try #require(layer.modalWindow("feedback"))
        #expect(w.styleMask == [.borderless])
        #expect(!w.isOpaque && w.backgroundColor == .clear && !w.hasShadow)
        // AppKit plays no window animation of its own: the only motion is the card's
        #expect(w.animationBehavior == NSWindow.AnimationBehavior.none)
        #expect(w.frame == main.frame && w.parent === main)
        #expect(!w.ignoresMouseEvents)
        let hostType = String(describing: type(of: w.contentView!))
        #expect(hostType.contains("ModalSurface"), "\(hostType)")
        layer.dismiss("feedback")
        main.close()
    }

    @Test func theCardAndItsContentsMoveAsOnePiece() throws {
        // Contents: a red block inside 20 pt of padding, so the card's own fill shows around it
        let arriving = try render(arrived: false)
        let settled = try render(arrived: true)

        let cardFrom = try #require(arriving.span(row: arriving.cardRow, where: { $0.isCanvasOrRed }))
        let redFrom = try #require(arriving.span(row: arriving.cardRow, where: { $0.isRed }))
        let cardTo = try #require(settled.span(row: settled.cardRow, where: { $0.isCanvasOrRed }))
        let redTo = try #require(settled.span(row: settled.cardRow, where: { $0.isRed }))

        #expect(abs(cardTo.width - 240) <= 2, "settled card \(cardTo)")
        #expect(abs(redTo.width - 200) <= 2, "settled contents \(redTo)")
        // arriving, the frame is scaled exactly as much as its contents: the frame does not stand still around them
        let frameScale = cardFrom.width / cardTo.width
        let contentScale = redFrom.width / redTo.width
        #expect(abs(frameScale - Motion.overlayScale) < 0.02, "frame scale \(frameScale)")
        #expect(abs(contentScale - frameScale) < 0.02, "contents \(contentScale) vs frame \(frameScale)")
        #expect(abs((redFrom.lower - cardFrom.lower) - 20 * frameScale) <= 2, "inset \(redFrom.lower - cardFrom.lower)")
        // the scrim only fades: clear while arriving, the canvas wash once in
        #expect(arriving.alpha(x: 4, y: 4) < 0.02)
        #expect(abs(settled.alpha(x: 4, y: 4) - ModalPresentation.scrimOpacity) < 0.05)
    }

    @Test func aGrailsModalInsideTheLayerDrawsNoSecondCard() throws {
        func fill(inCard: Bool) throws -> Pixels {
            let view = ZStack {
                Color(red: 1, green: 0, blue: 0)
                GrailsModal(title: "Feedback", step: "f") { Color.clear.frame(height: 80) } footer: { EmptyView() }
                    .environment(\.grailsInModalCard, inCard)
            }
            .frame(width: 600, height: 300)
            return try Pixels(view, width: 600, height: 300)
        }
        // inside the modal's side padding, halfway down
        let x = (600 - Int(ModalMetrics.width)) / 2 + 8
        let own = try fill(inCard: false).at(x: x, y: 150)
        let hosted = try fill(inCard: true).at(x: x, y: 150)
        #expect(own.isCanvasOrRed && !own.isRed, "outside the layer the modal draws its card: \(own)")
        #expect(hosted.isRed, "inside the layer it draws none: \(hosted)")
    }

    private func render(arrived: Bool) throws -> Pixels {
        let content = Color(red: 1, green: 0, blue: 0).frame(width: 200, height: 100).padding(20)
        let surface = ModalSurface(content: content, heldArrived: arrived)
            .environment(\.grailsReduceMotion, false)
            .environment(\.colorScheme, .light)
            .frame(width: 600, height: 500)
        var pixels = try Pixels(surface, width: 600, height: 500)
        // halfway down the red block: the card hangs from cardTop and the block starts 20 below the card's top
        pixels.cardRow = Int(ModalPresentation.cardTop(windowHeight: 500)) + 20 + 40
        return pixels
    }
}

struct Pixel {
    var r, g, b, a: Double
    var isRed: Bool { a > 0.9 && r > 0.9 && g < 0.2 && b < 0.2 }
    /// The light canvas (white) or the red contents, both opaque.
    var isCanvasOrRed: Bool { a > 0.9 && (isRed || (r > 0.97 && g > 0.97 && b > 0.97)) }
}

struct Pixels {
    let width: Int, height: Int
    let data: [UInt8]
    var cardRow = 0

    @MainActor init<V: View>(_ view: V, width: Int, height: Int) throws {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        renderer.proposedSize = ProposedViewSize(width: CGFloat(width), height: CGFloat(height))
        let image = try #require(renderer.cgImage)
        self.width = image.width
        self.height = image.height
        var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let ctx = try #require(CGContext(data: &bytes, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4,
                                         space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        data = bytes
    }

    /// `y` from the top.
    func at(x: Int, y: Int) -> Pixel {
        let i = (y * width + x) * 4
        let a = Double(data[i + 3]) / 255
        func c(_ v: UInt8) -> Double { a > 0 ? min(1, Double(v) / 255 / a) : 0 }
        return Pixel(r: c(data[i]), g: c(data[i + 1]), b: c(data[i + 2]), a: a)
    }

    func alpha(x: Int, y: Int) -> Double { at(x: x, y: y).a }

    /// The first and last column on `row` that match, as a range in points.
    func span(row: Int, where match: (Pixel) -> Bool) -> (lower: Double, upper: Double, width: Double)? {
        let hits = (0..<width).filter { match(at(x: $0, y: row)) }
        guard let lo = hits.first, let hi = hits.last else { return nil }
        return (Double(lo), Double(hi), Double(hi - lo + 1))
    }
}
