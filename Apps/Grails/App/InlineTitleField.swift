import AppKit

/// A name being edited in place: Return keeps it, Escape discards it, clicking elsewhere keeps it.
final class InlineTitleField: NSTextField, NSTextFieldDelegate {
    /// The new text, or nil when the edit was cancelled. Called once, after the field has left its parent.
    var onFinish: ((String?) -> Void)?
    private var finished = false
    /// The widest the box may grow to; it hugs the text up to this.
    private var maxWidth: CGFloat = 400
    private static let padding: CGFloat = 16

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
        maxWidth = frame.width
        self.frame = frame
        fit()
        parent.addSubview(self)
        parent.window?.makeFirstResponder(self)
        if let editor = currentEditor() as? NSTextView {
            editor.insertionPointColor = .ink(.focus)
            editor.selectAll(nil)
        }
    }

    /// Moves the box (the view scrolled or zoomed) without losing its fit to the text.
    func reposition(_ frame: NSRect) {
        maxWidth = frame.width
        self.frame.origin = frame.origin
        self.frame.size.height = frame.height
        fit()
    }

    /// As wide as what is typed, with a little room, never wider than the space it was given.
    private func fit() {
        let current = currentEditor()?.string ?? stringValue
        let text = current.isEmpty ? " " : current
        let w = ceil(NSAttributedString(string: text, attributes: [.font: font as Any]).size().width) + Self.padding
        frame.size.width = min(max(w, 48), maxWidth)
    }

    func controlTextDidChange(_ obj: Notification) { fit() }

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
