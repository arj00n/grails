import AppKit
import SwiftUI
import Testing
@testable import GrailsDesign

/// The info title wraps on the left; the Holy Grail mark and the heart sit on its first line, not above it.
@Suite struct TitleActionsAlignmentTests {
    @Test(arguments: ["Lamp", String(repeating: "This may contain: an image of a ceramic lamp. ", count: 3)])
    @MainActor func actionsSitOnTheTitlesFirstLine(_ title: String) {
        let frames = laidOut(title)
        guard let field = frames["title"] else { Issue.record("missing title \(frames)"); return }
        let font = ChromeNSFont.title(CGFloat(TypeScale.title))
        let top = field.minY + FieldLine.topInset(font: font)
        let line = NSLayoutManager().defaultLineHeight(for: font)
        for id in ["mark", "heart"] {
            guard let icon = frames[id] else { Issue.record("missing \(id)"); continue }
            #expect(icon.minY >= top - 0.5, "\(id) \(icon) floats above the first line \(top)")
            #expect(icon.maxY <= top + line + 0.5, "\(id) \(icon) drops below the first line \(top + line)")
            #expect(abs(icon.midY - (top + line / 2)) <= 2, "\(id) \(icon.midY) not centred on the line \(top + line / 2)")
            #expect(icon.minX >= field.maxX, "the title runs under \(id)")
        }
    }

    @MainActor
    private func laidOut(_ title: String) -> [String: CGRect] {
        var frames: [String: CGRect] = [:]
        let host = NSHostingView(rootView: Row(text: title).onPreferenceChange(Frames.self) { frames = $0 })
        host.frame = NSRect(x: 0, y: 0, width: 300, height: 300)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        host.layoutSubtreeIfNeeded()
        return frames
    }
}

private struct Frames: PreferenceKey {
    static let defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) { value.merge(nextValue(), uniquingKeysWith: { $1 }) }
}

private struct Row: View {
    var text: String
    @FocusState private var focus: Bool
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            GrailsPlainField("Item name", text: .constant(text), axis: .vertical, size: TypeScale.title, title: true, focus: $focus, equals: true, idle: false, lineLimit: 1...TitleLines.collapsed)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .report("title")
            HStack(spacing: CGFloat(Space.tight)) {
                CanonMark(size: 13, filled: true).report("mark")
                Image(systemName: "heart").font(ChromeFont.symbol(13)).report("heart")
            }
        }
        .padding(16)
        .frame(width: 300, alignment: .topLeading)
        .coordinateSpace(name: "row")
    }
}

private extension View {
    func report(_ id: String) -> some View {
        background { GeometryReader { Color.clear.preference(key: Frames.self, value: [id: $0.frame(in: .named("row"))]) } }
    }
}
