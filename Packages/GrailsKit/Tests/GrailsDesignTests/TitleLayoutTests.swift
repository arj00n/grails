import AppKit
import SwiftUI
import Testing
@testable import GrailsDesign

@Suite struct TitleLayoutTests {
    /// Longer than a Pinterest description. It has to wrap past four lines in a 300 pt inspector.
    private static let essay = String(repeating: "A long Pinterest description of a ceramic lamp on a linen table. ", count: 6)

    @Test @MainActor func longTitlePushesMetaAndColorsDown() {
        #expect(Self.essay.count >= 300)
        let collapsed = laidOut(expanded: false)
        let open = laidOut(expanded: true)
        assertClear(collapsed)
        assertClear(open)
        let title = collapsed["title"] ?? .zero
        let opened = open["title"] ?? .zero
        #expect(title.height > 40)
        #expect(opened.height > title.height + 8)
        let font = ChromeNSFont.title(CGFloat(TypeScale.title))
        #expect(TitleLines.needsMore(Self.essay, font: font, width: 268))
        #expect(!TitleLines.needsMore("Lamp", font: font, width: 268))
    }

    /// A tile caption wraps inside its own height. An in-place rename stays one line, so neither paints over the next line.
    @Test @MainActor func captionWrapsAndInlineTitleStaysOneLine() {
        let font = ChromeNSFont.title(13)
        let caption = GrailsCaption(frame: .zero)
        caption.font = font
        caption.stringValue = Self.essay
        caption.cell?.wraps = true
        caption.cell?.isScrollable = false
        caption.maximumNumberOfLines = TitleLines.collapsed
        caption.lineBreakMode = .byTruncatingTail
        let wrapped = caption.sizeThatFits(NSSize(width: 180, height: 800)).height
        let line = font.boundingRectForFont.height
        #expect(wrapped > line * 2)
        #expect(wrapped < line * 6)

        let field = GrailsValueField()
        field.font = ChromeNSFont.title(CGFloat(TypeScale.title))
        field.stringValue = Self.essay
        let single = field.sizeThatFits(NSSize(width: 200, height: 400)).height
        #expect(single < field.font!.boundingRectForFont.height + 8)
    }

    @MainActor
    private func laidOut(expanded: Bool) -> [String: CGRect] {
        let box = FrameBox()
        let host = NSHostingView(rootView: InspectorColumn(text: Self.essay, expanded: expanded).onPreferenceChange(FrameKey.self) { box.value = $0 })
        host.frame = NSRect(x: 0, y: 0, width: 300, height: 800)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        host.layoutSubtreeIfNeeded()
        return box.value
    }

    private func assertClear(_ frames: [String: CGRect], sourceLocation: SourceLocation = #_sourceLocation) {
        let title = frames["title"]
        let meta = frames["meta"]
        let colors = frames["colors"]
        #expect(title != nil, sourceLocation: sourceLocation)
        #expect(meta != nil, sourceLocation: sourceLocation)
        #expect(colors != nil, sourceLocation: sourceLocation)
        guard let title, let meta, let colors else { return }
        #expect(!Self.overlaps(title, meta), "title overlaps meta \(title) \(meta)", sourceLocation: sourceLocation)
        #expect(!Self.overlaps(title, colors), "title overlaps colors \(title) \(colors)", sourceLocation: sourceLocation)
        #expect(!Self.overlaps(meta, colors), "meta overlaps colors \(meta) \(colors)", sourceLocation: sourceLocation)
        #expect(title.maxY <= meta.minY + 0.5, sourceLocation: sourceLocation)
        #expect(meta.maxY <= colors.minY + 0.5, sourceLocation: sourceLocation)
    }

    private static func overlaps(_ a: CGRect, _ b: CGRect) -> Bool {
        let hit = a.intersection(b)
        return hit.width > 0.5 && hit.height > 0.5
    }
}

private final class FrameBox {
    var value: [String: CGRect] = [:]
}

private struct FrameKey: PreferenceKey {
    static let defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

/// The inspector's column at its real width: title, the line under it, then Colors.
private struct InspectorColumn: View {
    var text: String
    var expanded: Bool
    @FocusState private var focus: Bool

    var body: some View {
        let font = ChromeNSFont.title(CGFloat(TypeScale.title))
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                GrailsPlainField("Item name", text: .constant(text), axis: .vertical, size: TypeScale.title, title: true, focus: $focus, equals: true, idle: false, lineLimit: expanded ? 1...32 : 1...TitleLines.collapsed)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .report("title")
                if TitleLines.needsMore(text, font: font, width: 268) {
                    Text(expanded ? "Show less" : "Show more").font(ChromeFont.body(TypeScale.quiet))
                }
            }
            Text("pinterest.com")
                .font(ChromeFont.body(TypeScale.body))
                .report("meta")
            GrailsSection("Colors", symbol: "paintpalette") {
                Text("Clay")
            }
            .report("colors")
        }
        .padding(16)
        .frame(width: 300, alignment: .topLeading)
        .coordinateSpace(name: "column")
    }
}

private extension View {
    func report(_ id: String) -> some View {
        background {
            GeometryReader { proxy in
                Color.clear.preference(key: FrameKey.self, value: [id: proxy.frame(in: .named("column"))])
            }
        }
    }
}
