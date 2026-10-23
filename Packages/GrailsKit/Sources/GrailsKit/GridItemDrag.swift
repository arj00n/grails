import Foundation

/// What a grid tile offers a drag.
public struct GridItemDrag: Equatable, Sendable {
    public var itemID: String
    public var fileURL: URL?

    /// Section headers are not items. A missing original still returns a drag, with no file URL.
    public static func offer(itemID: String, isSection: Bool, original: URL?, fileOnDisk: Bool) -> GridItemDrag? {
        guard !isSection else { return nil }
        return GridItemDrag(itemID: itemID, fileURL: fileOnDisk ? original : nil)
    }

    public init(itemID: String, fileURL: URL?) {
        self.itemID = itemID
        self.fileURL = fileURL
    }
}
