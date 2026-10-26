import Foundation

/// Clusters are folders. On a collection's board each folder directly inside it is a cluster named after it, holding
/// everything in that folder and the folders beneath it; on the whole library's board each top-level collection is one.
/// What sits in none of them is the untitled loose cluster. The board only keeps where each cluster is, how wide, its
/// tile size and the order of its pictures; who belongs where is read from the folders every time.
public enum FolderClusters {
    /// The loose cluster's id on every folder board.
    public static let looseID = "loose"

    public struct Folder: Sendable, Equatable {
        public var id: String
        public var title: String
        /// Items in the folder or any folder beneath it.
        public var members: Set<String>
        public init(id: String, title: String, members: Set<String>) { self.id = id; self.title = title; self.members = members }
    }

    /// The board's clusters for `folders` (in sidebar order) and the items in view (`visible`, in the view's order).
    /// A picture in two folders is in both clusters. Saved layout is kept for every cluster that already had one; a folder
    /// new to the board goes to the right of everything. Folders with nothing in view keep their layout but draw nothing.
    public static func reconcile(stored: [CanvasCluster], folders: [Folder], visible: [String], now: Double = Date().timeIntervalSince1970) -> [CanvasCluster] {
        let folderIDs = Set(folders.map(\.id))
        let byID = Dictionary(stored.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        // a board from before folders: its first untitled cluster is where the loose pictures already were
        let looseBase = byID[looseID] ?? stored.first { !folderIDs.contains($0.id) && $0.title.isEmpty }
        var right = stored.filter { folderIDs.contains($0.id) || $0.id == looseBase?.id }.map { $0.x + max($0.width, ClusterLayout.minWidth) }.max()
        let top = stored.map(\.y).min() ?? 0

        func ordered(_ members: [String], after base: CanvasCluster?) -> [String] {
            let wanted = Set(members)
            var seen = Set<String>()
            var out: [String] = []
            for id in base?.items ?? [] where wanted.contains(id) && seen.insert(id).inserted { out.append(id) }
            for id in members where seen.insert(id).inserted { out.append(id) }
            return out
        }
        func cluster(id: String, title: String, members: [String], base: CanvasCluster?) -> CanvasCluster {
            if let base {
                var c = base
                c.id = id; c.title = title; c.items = ordered(members, after: base)
                return c
            }
            let width = ClusterOps.suggestedWidth(count: members.count)
            let x = right.map { $0 + 160 } ?? 0
            right = x + width
            return CanvasCluster(id: id, title: title, x: x, y: top, width: width, items: members, at: now)
        }

        var filed = Set<String>()
        var out: [CanvasCluster] = []
        var folderClusters: [CanvasCluster] = []
        for f in folders {
            let members = visible.filter { f.members.contains($0) }
            filed.formUnion(members)
            folderClusters.append(cluster(id: f.id, title: f.title, members: members, base: byID[f.id]))
        }
        let loose = visible.filter { !filed.contains($0) }
        if !loose.isEmpty || looseBase != nil { out.append(cluster(id: looseID, title: "", members: loose, base: looseBase)) }
        out += folderClusters
        return out
    }

    /// Named clusters from before folders, which become folders of the same name (and id) holding the same pictures.
    public static func strays(_ stored: [CanvasCluster], folders: Set<String>) -> [CanvasCluster] {
        stored.filter { $0.id != looseID && !folders.contains($0.id) && !$0.title.trimmingCharacters(in: .whitespaces).isEmpty && !$0.items.isEmpty }
    }

    /// What an edit on the board means for the folders. Items are item ids, not tile keys.
    public struct Edit: Sendable, Equatable {
        /// Folder id (or `looseID`) → items that left it.
        public var removed: [String: [String]] = [:]
        /// Folder id (or `looseID`) → items that joined it.
        public var added: [String: [String]] = [:]
        /// Clusters made on the board just now: each becomes a folder with the cluster's id.
        public var created: [CanvasCluster] = []
        /// Folder id → new name.
        public var renamed: [String: String] = [:]
        public var isEmpty: Bool { removed.isEmpty && added.isEmpty && created.isEmpty && renamed.isEmpty }
        public init() {}
    }

    public static func edit(from old: [CanvasCluster], to new: [CanvasCluster], folders: Set<String>) -> Edit {
        var e = Edit()
        let before = Dictionary(old.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let known = folders.union([looseID])
        for c in new {
            guard known.contains(c.id) else {
                if !c.items.isEmpty { e.created.append(c) }
                continue
            }
            let was = Set(before[c.id]?.items ?? []), now = Set(c.items)
            let gone = (before[c.id]?.items ?? []).filter { !now.contains($0) }
            let joined = c.items.filter { !was.contains($0) }
            if !gone.isEmpty { e.removed[c.id] = gone }
            if !joined.isEmpty { e.added[c.id] = joined }
            let name = c.title.trimmingCharacters(in: .whitespaces)
            if c.id != looseID, let b = before[c.id], !name.isEmpty, name != b.title { e.renamed[c.id] = name }
        }
        let kept = Set(new.map(\.id))
        for c in old where known.contains(c.id) && !kept.contains(c.id) && !c.items.isEmpty { e.removed[c.id] = c.items }
        return e
    }
}

/// A picture can be in several clusters at once, one for each folder it is in. Each appearance is a tile with its own key:
/// the first keeps the item's id, later ones add their cluster's id after a separator no id contains.
public enum TileKey {
    static let separator: Character = "\u{1F}"

    public static func item(_ key: String) -> String {
        guard let i = key.firstIndex(of: separator) else { return key }
        return String(key[..<i])
    }

    /// Gives every appearance after an item's first its own key.
    public static func keyed(_ clusters: [CanvasCluster]) -> [CanvasCluster] {
        var seen = Set<String>()
        return clusters.map { c in
            var c = c
            c.items = c.items.map { id in seen.insert(id).inserted ? id : id + String(separator) + c.id }
            return c
        }
    }

    /// Back to item ids. A cluster that ended up with the same picture twice (a tile dropped where the item already was) keeps one.
    public static func unkeyed(_ clusters: [CanvasCluster]) -> [CanvasCluster] {
        clusters.map { c in
            var c = c
            var seen = Set<String>()
            c.items = c.items.map(item).filter { seen.insert($0).inserted }
            return c
        }
    }
}
