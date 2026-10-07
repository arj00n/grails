import Foundation

public enum ItemSort: Sendable, Hashable {
    case relevance, addedDesc, addedAsc, nameAsc, nameDesc, sizeDesc, random
}

public struct ItemQuery: Sendable {
    public var text: String?
    public var kinds: Set<ItemKind> = []
    public var likedOnly = false
    public var tag: String?
    /// More tags that must all be present (the tab strip narrows a view by tag).
    public var extraTags: [String] = []
    public var untagged = false
    public var collectionId: String?
    /// Any of these collections (used to show a folder as the union of everything inside it)
    public var collectionIds: Set<String> = []
    /// Inbox: items that are in no collection
    public var unfiled = false
    /// Pictures that haven't been auto-tagged yet
    public var needsAutoTags = false
    /// With `needsAutoTags`: also match items an older engine tagged, so a better one can redo them.
    public var upgradeAutoTagsTo: String? = nil
    /// Only items saved by this person (the `addedBy` handle)
    public var addedBy: String?
    /// Only these creatives. Empty means none. Nil means no such filter.
    public var onlyIds: Set<String>?
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
    /// Videos: length in seconds
    public var durationSec: Double? = nil
    /// The creative has a note, or a note someone left on it.
    public var noted: Bool = false

    /// A divider row for the grid: the cluster's title, and how many items follow in `bytes`.
    public static func sectionHeader(id: String, title: String, count: Int) -> ItemSummary {
        ItemSummary(id: "section:\(id)", kind: .section, name: title, ext: nil, width: nil, height: nil, bytes: Int64(count), liked: false,
                    addedAt: .distantPast, addedBy: "", deletedAt: nil, site: nil, linkDisplay: nil, badge: nil, durationSec: nil)
    }
}
