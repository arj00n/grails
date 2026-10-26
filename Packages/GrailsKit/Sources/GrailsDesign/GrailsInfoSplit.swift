import SwiftUI

/// Where the content column ends and the info panel column begins, for a split `total` points wide.
///
/// `reveal` runs 0 (closed) to 1 (open) and may pass 1 while the spring settles. The panel always starts where the content
/// ends, so the two never overlap; an overshoot narrows the content a little further and the panel fills the extra width.
public struct InfoSplitGeometry: Equatable, Sendable {
    public let contentWidth: Double
    /// The panel's leading edge, from the split's leading edge.
    public let panelX: Double
    /// How much of the panel is on screen.
    public let shownWidth: Double
    /// The width the panel is laid out at: its column width, or more during an overshoot so its fill reaches the edge.
    public let panelWidth: Double

    public init(total: Double, columnWidth: Double, reveal: Double) {
        let shown = min(max(0, total), max(0, reveal) * columnWidth)
        contentWidth = max(0, total) - shown
        panelX = contentWidth
        shownWidth = shown
        panelWidth = max(columnWidth, shown)
    }
}

/// The one container for the info panel, in fullscreen and on the canvas alike: a trailing column in the same layout as the
/// content, never laid over it. Opening it narrows the content (and anything the content column carries, such as the tag
/// strip). The column runs the full height of the split, under the window's bar like the sidebar; the caller insets the
/// panel's contents below the bar.
///
/// The width springs on `grailsSpring`; the panel's contents fade on `grailsStandard`, so the fade never bounces. Reduce Motion
/// opens and closes it at once. The content draws above the panel, so a picture flying back to its tile passes over it.
public struct GrailsInfoSplit<Content: View, Panel: View>: View {
    var isOpen: Bool
    var width: CGFloat
    /// Fades the whole column, its rule included, for a caller that hides it for a moment (the flight back to a tile).
    var panelOpacity: Double
    var content: Content
    var panel: Panel
    @Environment(\.grailsReduceMotion) private var reduceMotion

    public static var columnWidth: CGFloat { 300 }

    public init(
        isOpen: Bool, width: CGFloat = Self.columnWidth, panelOpacity: Double = 1,
        @ViewBuilder content: () -> Content, @ViewBuilder panel: () -> Panel
    ) {
        self.isOpen = isOpen
        self.width = width
        self.panelOpacity = panelOpacity
        self.content = content()
        self.panel = panel()
    }

    public var body: some View {
        InfoSplitLayout(reveal: isOpen ? 1 : 0, columnWidth: width) {
            column
            content.zIndex(1)
        }
        .animation(reduceMotion ? nil : .grailsSpring, value: isOpen)
    }

    private var column: some View {
        panel
            .frame(width: width)
            .frame(maxHeight: .infinity, alignment: .top)
            .opacity(isOpen ? 1 : 0)
            .animation(reduceMotion ? nil : .grailsStandard, value: isOpen)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(GrailsInk(.sidebar))
            .overlay(alignment: .leading) { Rectangle().fill(GrailsInk(.separator)).frame(width: 1) }
            .opacity(panelOpacity)
            .allowsHitTesting(isOpen && panelOpacity > 0.5)
            .accessibilityHidden(!isOpen)
    }
}

/// Places the content and the panel side by side by `InfoSplitGeometry`. `reveal` is animatable, so the spring drives the
/// layout itself and the content reflows on every frame. The first subview is the panel, the second the content.
struct InfoSplitLayout: Layout {
    var reveal: Double
    var columnWidth: CGFloat

    var animatableData: Double {
        get { reveal }
        set { reveal = newValue }
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        proposal.replacingUnspecifiedDimensions()
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard subviews.count == 2 else { return }
        let g = InfoSplitGeometry(total: bounds.width, columnWidth: columnWidth, reveal: reveal)
        subviews[1].place(at: bounds.origin, proposal: ProposedViewSize(width: g.contentWidth, height: bounds.height))
        subviews[0].place(
            at: CGPoint(x: bounds.minX + g.panelX, y: bounds.minY),
            proposal: ProposedViewSize(width: g.panelWidth, height: bounds.height)
        )
    }
}
