import AppKit
import SwiftUI

/// Single-line field that grabs keyboard focus when it appears and reports ↑ ↓ ⎋ ↩ itself.
/// SwiftUI's `@FocusState` can't reliably take focus away from the AppKit grid, so panels use this instead.
struct FocusedTextField: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String
    var identifier: String
    var font: NSFont = .systemFont(ofSize: 17)
    var onSubmit: () -> Void = {}
    var onMove: (Int) -> Void = { _ in }
    var onEscape: () -> Void = {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSTextField {
        let tf = GrabbingTextField()
        tf.isBordered = false
        tf.drawsBackground = false
        tf.focusRingType = .none
        tf.font = font
        tf.placeholderString = placeholder
        tf.cell?.usesSingleLineMode = true
        tf.cell?.isScrollable = true
        tf.delegate = context.coordinator
        tf.setAccessibilityIdentifier(identifier)
        tf.stringValue = text
        return tf
    }

    func updateNSView(_ tf: NSTextField, context: Context) {
        context.coordinator.parent = self
        if tf.stringValue != text { tf.stringValue = text }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: FocusedTextField
        init(_ p: FocusedTextField) { parent = p }

        func controlTextDidChange(_ obj: Notification) {
            if let tf = obj.object as? NSTextField { parent.text = tf.stringValue }
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy sel: Selector) -> Bool {
            switch sel {
            case #selector(NSResponder.moveUp(_:)): parent.onMove(-1); return true
            case #selector(NSResponder.moveDown(_:)): parent.onMove(1); return true
            case #selector(NSResponder.cancelOperation(_:)): parent.onEscape(); return true
            case #selector(NSResponder.insertNewline(_:)): parent.onSubmit(); return true
            default: return false
            }
        }
    }
}

private final class GrabbingTextField: NSTextField {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, let w = self.window else { return }
            w.makeFirstResponder(self)
        }
    }
}
