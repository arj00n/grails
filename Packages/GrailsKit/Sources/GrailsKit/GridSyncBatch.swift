import AppKit
import Foundation

/// How a grid applies one sync batch. Surviving ids keep their cells. A picture is reloaded only when the file it shows changed.
public enum GridSyncBatch {
    public static let interval: TimeInterval = 0.25

    public struct Plan: Equatable, Sendable {
        /// Indexes in the previous list. Informational: the snapshot applies the same deletes.
        public var deleteIndexes: [Int]
        /// Indexes of ids that were not in the previous list.
        public var insertIndexes: [Int]
        /// Survivors whose thumbnail is a different file. Only these cells are reloaded.
        public var pictureIDs: [String]
        /// Survivors whose row changed and whose thumbnail did not.
        public var chromeIDs: [String]
        /// Ids present before and after, in the new order.
        public var keptIDs: [String]
        /// Survivors did not change order.
        public var stableOrder: Bool
    }

    /// Wait long enough that several sync writes in one quarter-second become one grid update.
    public static func delay(since lastApply: Date, now: Date = Date()) -> TimeInterval {
        max(0, interval - now.timeIntervalSince(lastApply))
    }

    public static func plan(from old: [ItemSummary], to new: [ItemSummary]) -> Plan {
        let oldIDs = old.map(\.id)
        let newIDs = new.map(\.id)
        let oldIndex = Dictionary(uniqueKeysWithValues: old.enumerated().map { ($1.id, $0) })
        let newIDSet = Set(newIDs)
        var kept: [String] = []
        var pictures: [String] = []
        var chrome: [String] = []
        var inserts: [Int] = []
        for (index, item) in new.enumerated() {
            guard let previousIndex = oldIndex[item.id] else {
                inserts.append(index)
                continue
            }
            kept.append(item.id)
            let previous = old[previousIndex]
            if pictureChanged(previous, item) {
                pictures.append(item.id)
            } else if previous != item {
                chrome.append(item.id)
            }
        }
        let deletes = oldIDs.enumerated().compactMap { newIDSet.contains($1) ? nil : $0 }
        let oldKept = oldIDs.filter { newIDSet.contains($0) }
        return Plan(
            deleteIndexes: deletes,
            insertIndexes: inserts,
            pictureIDs: pictures,
            chromeIDs: chrome,
            keptIDs: kept,
            stableOrder: oldKept == kept
        )
    }

    public static func pictureChanged(_ old: ItemSummary, _ new: ItemSummary) -> Bool {
        old.kind != new.kind || old.linkDisplay != new.linkDisplay || old.ext != new.ext || old.width != new.width || old.height != new.height
    }

    /// One snapshot for the whole batch. Built from the snapshot already on screen, so a fresh list is not
    /// swapped in. Inserts, deletes, and moves leave surviving cells alone. Only a changed picture is reloaded.
    @MainActor
    public static func apply(_ plan: Plan, ids: [String], to dataSource: NSCollectionViewDiffableDataSource<Int, String>) {
        var snapshot = dataSource.snapshot()
        let wanted = Set(ids)
        // Same ids, same order, same pictures: do not touch the collection view. A sync that only
        // rewrites a name is applied to the cells already on screen.
        if snapshot.itemIdentifiers == ids && plan.pictureIDs.isEmpty { return }
        if snapshot.sectionIdentifiers.isEmpty {
            snapshot.appendSections([0])
        }
        if snapshot.itemIdentifiers.isEmpty {
            if !ids.isEmpty { snapshot.appendItems(ids, toSection: 0) }
        } else {
            let removed = snapshot.itemIdentifiers.filter { !wanted.contains($0) }
            if !removed.isEmpty { snapshot.deleteItems(removed) }
            var working = snapshot.itemIdentifiers
            for (index, id) in ids.enumerated() {
                if let current = working.firstIndex(of: id) {
                    guard current != index else { continue }
                    if index == 0 {
                        snapshot.moveItem(id, beforeItem: working[0])
                    } else {
                        snapshot.moveItem(id, afterItem: ids[index - 1])
                    }
                    working.remove(at: current)
                    working.insert(id, at: index)
                } else if working.isEmpty || index >= working.count {
                    snapshot.appendItems([id], toSection: working.isEmpty ? 0 : nil)
                    working.append(id)
                } else if index == 0 {
                    snapshot.insertItems([id], beforeItem: working[0])
                    working.insert(id, at: 0)
                } else {
                    snapshot.insertItems([id], afterItem: ids[index - 1])
                    working.insert(id, at: index)
                }
            }
        }
        let reload = plan.pictureIDs.filter(wanted.contains)
        if !reload.isEmpty { snapshot.reloadItems(reload) }
        // `animatingDifferences: false` is a full reload on this OS, which builds new cells. Diff, with no animation.
        NSAnimationContext.beginGrouping()
        NSAnimationContext.current.duration = 0
        dataSource.apply(snapshot, animatingDifferences: true)
        NSAnimationContext.endGrouping()
    }

    /// A page switch: the new page's ids replace the old page's in one apply, with no animation and no per-item move
    /// bookkeeping. The old page's cells are hidden and the new page's laid out in the same pass.
    @MainActor
    public static func replace(ids: [String], in dataSource: NSCollectionViewDiffableDataSource<Int, String>) {
        var snapshot = NSDiffableDataSourceSnapshot<Int, String>()
        snapshot.appendSections([0])
        if !ids.isEmpty { snapshot.appendItems(ids, toSection: 0) }
        dataSource.apply(snapshot, animatingDifferences: false)
    }
}
