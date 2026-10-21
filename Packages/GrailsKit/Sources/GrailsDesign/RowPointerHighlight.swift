import Foundation

/// One list highlight, shared by the pointer and the keyboard.
///
/// `place` records where the pointer is and selects nothing. `pointer(at:over:)` selects that row only when the
/// location has changed, so a row that scrolls or slides under a still pointer does not take the highlight.
public struct RowPointerHighlight: Equatable, Sendable {
    public struct Point: Equatable, Sendable {
        public var x: Double
        public var y: Double

        public init(_ x: Double, _ y: Double) {
            self.x = x
            self.y = y
        }
    }

    public private(set) var index: Int
    private var last: Point?

    public init() {
        index = 0
    }

    /// Records the pointer. A later sample at the same place is not a move. Does nothing once a place is known.
    public mutating func place(_ point: Point) {
        guard last == nil else { return }
        last = point
    }

    /// Selects `row` when the pointer has moved to `point`. The same point leaves the highlight where it is.
    public mutating func pointer(at point: Point, over row: Int) {
        let moved = last.map { $0 != point } ?? false
        last = point
        if moved { index = row }
    }

    public mutating func move(by delta: Int, count: Int) {
        let end = max(count - 1, 0)
        index = min(end, max(0, index + delta))
    }

    public mutating func reset() {
        index = 0
    }

    public mutating func select(_ row: Int) {
        index = max(0, row)
    }

    public mutating func clamp(to count: Int) {
        index = min(index, max(count - 1, 0))
    }
}

#if canImport(SwiftUI) && canImport(AppKit)
import AppKit
import SwiftUI

extension RowPointerHighlight {
    /// Screen location of the pointer. A still pointer reports the same point.
    static var mouse: Point {
        let location = NSEvent.mouseLocation
        return Point(Double(location.x), Double(location.y))
    }
}

public extension View {
    /// Moves the shared highlight to this row when the pointer moves onto it.
    func rowPointerHighlight(_ row: Int, highlight: Binding<RowPointerHighlight>) -> some View {
        modifier(RowPointerHover(row: row, highlight: highlight))
    }
}

private struct RowPointerHover: ViewModifier {
    var row: Int
    @Binding var highlight: RowPointerHighlight

    func body(content: Content) -> some View {
        content
            .onAppear { apply { $0.place(RowPointerHighlight.mouse) } }
            .onContinuousHover { phase in
                guard case .active = phase else { return }
                // The phase point sits in the row and moves when the row scrolls. The screen location stays put.
                apply { $0.pointer(at: RowPointerHighlight.mouse, over: row) }
            }
    }

    private func apply(_ change: (inout RowPointerHighlight) -> Void) {
        var next = highlight
        change(&next)
        guard next != highlight else { return }
        highlight = next
    }
}
#endif
