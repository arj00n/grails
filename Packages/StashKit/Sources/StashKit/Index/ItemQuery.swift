import Foundation

public enum ItemSort: Sendable, Hashable {
    case relevance, addedDesc, addedAsc, nameAsc, nameDesc, sizeDesc, random
}

public struct ItemQuery: Sendable {
    public var text: String?
    public var kinds: Set<ItemKind> = []
    public var likedOnly = false
    public var tag: String?
    public var untagged = false
    public var collectionId: String?
    /// Any of these collections (used to show a folder as the union of everything inside it)
    public var collectionIds: Set<String> = []
    /// Inbox: items that are in no collection
    public var unfiled = false
    /// Pictures that haven't been auto-tagged yet
    public var needsAutoTags = false
    /// Only items saved by this person (the `addedBy` handle)
    public var addedBy: String?
    /// Roughly square images (aspect ratio within 5% of 1:1)
    public var squareOnly = false
    /// Evaluate a smart folder's rules in addition to the other filters
    public var smart: SmartFolder?
    /// true = the Trash view
    public var deleted = false
    public var sort: ItemSort?
    public var limit = 200
    public var offset = 0

    public init(text: String? = nil) { self.text = text }

    var effectiveSort: ItemSort {
        if let sort { return sort }
        return (text?.isEmpty == false) ? .relevance : .addedDesc
    }
}

/// Lightweight row for grids and lists. Full metadata is read from `item.json` when needed.
public struct ItemSummary: Sendable, Hashable, Identifiable {
    public var id: String
    public var kind: ItemKind
    public var name: String
    public var ext: String?
    public var width: Int?
    public var height: Int?
    public var bytes: Int64?
    public var liked: Bool
    public var addedAt: Date
    public var addedBy: String
    public var deletedAt: Date?
    /// Source site (links show it as a badge)
    public var site: String?
    /// Links: "image", "snapshot" or "title"
    public var linkDisplay: String?
    /// Links: a badge such as "figma"
    public var badge: String?
}
