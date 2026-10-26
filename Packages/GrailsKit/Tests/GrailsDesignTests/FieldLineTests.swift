import AppKit
import Testing
@testable import GrailsDesign

@Suite struct FieldLineTests {
    /// A 17 pt field editor uses the font's line. Single-line mode would pin the line to 16 pt with the caret below the text.
    @Test @MainActor func commandLineMatchesTheFieldLine() {
        let font = ChromeNSFont.body(17)
        #expect(font.familyName == NSFont.systemFont(ofSize: 17).familyName, "system font \(font.fontName)")
        let frame = NSRect(x: 0, y: 0, width: 320, height: 48)
        let field = GrailsValueField(frame: frame)
        field.font = font
        field.stringValue = "Ag"
        let window = NSWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.setFrameOrigin(NSPoint(x: -20_000, y: -20_000))
        window.contentView = field
        window.makeKeyAndOrderFront(nil)
        #expect(window.makeFirstResponder(field))
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        field.layoutSubtreeIfNeeded()
        guard let editor = field.currentEditor() as? NSTextView, let layout = editor.layoutManager else {
            Issue.record("17 pt field has no field editor")
            return
        }
        if let container = editor.textContainer { layout.ensureLayout(for: container) }
        #expect(layout.numberOfGlyphs > 0)
        guard layout.numberOfGlyphs > 0 else { return }
        let fragment = layout.lineFragmentRect(forGlyphAt: 0, effectiveRange: nil)
        let expected = FieldLine.line(in: field.bounds, font: font)
        #expect(abs(fragment.height - expected.height) <= 1, "line \(fragment.height) field line \(expected.height)")
        let baseline = layout.location(forGlyphAt: 0).y
        #expect(abs(baseline - font.ascender) <= 1, "baseline \(baseline) ascender \(font.ascender)")
        window.orderOut(nil)
    }
}
