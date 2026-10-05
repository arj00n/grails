import AppKit

/// A name being edited in place: Return keeps it, Escape discards it, clicking elsewhere keeps it.
final class InlineTitleField: NSTextField, NSTextFieldDelegate {
    /// The new text, or nil when the edit was cancelled. Called once, after the field has left its parent.
    var onFinish: ((String?) -> Void)?
    private var finished = false

    init(text: String, font: NSFont) {
        super.init(frame: .zero)
        stringValue = text
        self.font = font
        textColor = .ink(.text)
        isBordered = false
        isBezeled = false
        drawsBackground = true
        backgroundColor = .ink(.fill)
        focusRingType = .none
        usesSingleLineMode = true
        cell?.isScrollable = true
        lineBreakMode = .byClipping
        wantsLayer = true
        layer?.cornerRadius = Ink.radius
        delegate = self
    }

    required init?(coder: NSCoder) { fatalError() }

    /// Puts the field in its parent, focuses it and selects the whole name.
    func begin(in parent: NSView, frame: NSRect) {
        self.frame = frame
        parent.addSubview(self)
        parent.window?.makeFirstResponder(self)
        if let editor = currentEditor() as? NSTextView {
            editor.insertionPointColor = .ink(.focus)
            editor.selectAll(nil)
        }
    }

    func finish(commit: Bool) {
        guard !finished else { return }
        finished = true
        let text = stringValue
        removeFromSuperview()
        onFinish?(commit ? text : nil)
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.insertNewline(_:)): finish(commit: true); return true
        case #selector(NSResponder.cancelOperation(_:)): finish(commit: false); return true
        default: return false
        }
    }

    func controlTextDidEndEditing(_ obj: Notification) { finish(commit: true) }
}
