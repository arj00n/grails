import AppKit
import GrailsKit
import QuartzCore

/// The section title stuck to the top of the grid while its section scrolls underneath.
///
/// It sits on the scroll view as a floating subview, not in the scrolling document. During fast and momentum scrolls
/// AppKit moves the document ahead of the main thread (responsive scrolling); a header laid out inside the document
/// rode along for those frames and snapped back on the next layout pass, which read as the title shaking. Up here the
/// stuck title has nothing to catch up with: only the push from the next header follows the scroll. Placement never
/// animates.
final class PinnedSectionHeader: GridSurface {
    /// The shown section's index in the grid's items.
    private(set) var index: Int?
    private var summary: ItemSummary?
    private var noted = false
    /// Same cell the grid uses for its section rows, so the two copies look identical.
    private let cell = ThumbCell()
    var onRename: ((Int) -> Void)?
    var menuProvider: ((Int) -> NSMenu?)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        cell.view.frame = bounds
        cell.view.autoresizingMask = [.width, .height]
        addSubview(cell.view)
        isHidden = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override var isFlipped: Bool { true }

    /// `frame` is in the floating container's coordinates. Called on every scroll tick, so it only touches what changed.
    func show(_ s: ItemSummary, noted: Bool, at index: Int, frame: NSRect) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if s != summary || noted != self.noted {
            cell.configureSection(s, noted: noted)
            summary = s
            self.noted = noted
        }
        self.index = index
        if self.frame != frame { self.frame = frame }
        isHidden = false
        CATransaction.commit()
    }

    func hide() {
        guard !isHidden else { return }
        isHidden = true
        index = nil
    }

    /// Clicks land on the title, not on the tiles scrolling under it.
    override func hitTest(_ point: NSPoint) -> NSView? { !isHidden && frame.contains(point) ? self : nil }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2, let index { onRename?(index) }
    }

    override func menu(for event: NSEvent) -> NSMenu? { index.flatMap { menuProvider?($0) } }

    /// VoiceOver reads the grid's own row for this section; the floating copy would only repeat it.
    override func isAccessibilityElement() -> Bool { false }
    override func accessibilityChildren() -> [Any]? { [] }
}
