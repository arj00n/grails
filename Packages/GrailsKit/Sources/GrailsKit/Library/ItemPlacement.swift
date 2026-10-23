import Foundation

/// Where an item can be filed, and how a drop decides a folder is a real target.
///
/// A folder is a `GrailsCollection` with `kind == "folder"`. It holds other collections
/// through `parentId`. The same `add` and `move` calls that file an item in a collection
/// file it in a folder. The file URL on a drag is not part of this decision.
public enum ItemPlacement {
    public struct Destination: Equatable, Sendable, Identifiable {
        public var id: String
        public var name: String
        public var kind: String
        /// Ancestor names, then this one, joined with " / ". A folder inside a folder reads "Campaigns / Spring".
        public var label: String
        public var depth: Int
    }

    public struct Action: Equatable, Sendable {
        public var ids: [String]
        public var from: String?
        public var target: String
        public var isMove: Bool { from != nil }
    }

    /// Tree order when `query` is empty, so a child sits under its parent. A query searches `label` and flattens.
    /// The open collection is omitted. Its children stay.
    public static func destinations(
        _ collections: [GrailsCollection], query: String, openCollection: String?, limit: Int = 40
    ) -> [Destination] {
        let live = collections.filter { !$0.archived }
        let children = Dictionary(grouping: live, by: { $0.parentId ?? "" })
        var seen = Set<String>()
        var built: [Destination] = []

        func visit(_ parent: String, depth: Int) {
            let kids = (children[parent] ?? []).sorted { ($0.order, $0.id) < ($1.order, $1.id) }
            for c in kids {
                guard seen.insert(c.id).inserted else { continue }
                let shown = c.id != openCollection
                if shown {
                    built.append(Destination(id: c.id, name: c.displayName, kind: c.kind, label: path(of: c, in: live), depth: depth))
                }
                visit(c.id, depth: shown ? depth + 1 : depth)
            }
        }

        visit("", depth: 0)
        let loose = live.filter { !seen.contains($0.id) }.sorted { ($0.order, $0.id) < ($1.order, $1.id) }
        for c in loose where seen.insert(c.id).inserted {
            let shown = c.id != openCollection
            if shown {
                built.append(Destination(id: c.id, name: c.displayName, kind: c.kind, label: path(of: c, in: live), depth: 0))
            }
            visit(c.id, depth: shown ? 1 : 0)
        }

        let ranked = FuzzyMatcher.rank(built, query: query, text: \.label, limit: limit)
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { return ranked }
        return ranked.map { Destination(id: $0.id, name: $0.name, kind: $0.kind, label: $0.label, depth: 0) }
    }

    /// Add when nothing is open, or the open collection is the target. Move peels the item off the open collection only.
    public static func action(ids: [String], openCollection: String?, target: String) -> Action {
        let from = (openCollection == nil || openCollection == target) ? nil : openCollection
        return Action(ids: ids, from: from, target: target)
    }

    /// Sidebar item drops. A folder accepts the same item ids a collection does. An empty id list does not.
    public static func acceptsItemDrop(kind: String, itemIDs: [String]) -> Bool {
        !itemIDs.isEmpty && (kind == "folder" || kind == "collection")
    }

    private static func path(of c: GrailsCollection, in live: [GrailsCollection]) -> String {
        var names = [c.displayName]
        var cur = c.parentId
        var seen = Set<String>([c.id])
        var steps = 0
        while let id = cur, steps < 32, seen.insert(id).inserted, let parent = live.first(where: { $0.id == id }) {
            names.insert(parent.displayName, at: 0)
            cur = parent.parentId
            steps += 1
        }
        return names.joined(separator: " / ")
    }
}
