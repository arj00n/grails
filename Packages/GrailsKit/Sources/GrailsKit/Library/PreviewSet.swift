import Foundation

/// The items the preview pages through: an ordered snapshot taken when it opens (grid order without section headers, or the
/// canvas's reading order). Looking up an id or a neighbour is O(1), however big the library.
public struct PreviewSet: Sendable {
    public private(set) var items: [ItemSummary]
    private var index: [String: Int]

    public init(_ source: [ItemSummary]) {
        items = source.filter { $0.kind != .section }
        index = Dictionary(items.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { a, _ in a })
    }

    public var count: Int { items.count }
    public func position(of id: String) -> Int? { index[id] }
    public subscript(i: Int) -> ItemSummary? { items.indices.contains(i) ? items[i] : nil }

    /// Takes out items that are gone (deleted, filtered out) while keeping the order. Returns the position now holding what was at `position`
    /// (the next item, or the last if it was the end), or nil when nothing is left.
    public mutating func drop(where gone: (String) -> Bool, keepingPosition position: Int) -> Int? {
        let kept = items.filter { !gone($0.id) }
        guard !kept.isEmpty else { items = []; index = [:]; return nil }
        // how many removed items sat before `position`
        let removedBefore = items.prefix(position).filter { gone($0.id) }.count
        items = kept
        index = Dictionary(items.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { a, _ in a })
        return min(max(position - removedBefore, 0), items.count - 1)
    }
}
