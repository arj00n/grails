import AppKit
import GrailsDesign
import GrailsKit
import GrailsSync
import SwiftUI

extension AppModel {
    // MARK: ⌘K

    func commandRows(_ q: String) async -> [PaletteRow] {
        var scored: [(PaletteRow, Int)] = []
        func add(_ row: PaletteRow, boost: Int = 0) {
            if let s = FuzzyMatcher.score(query: q, in: row.title) { scored.append((row, s + boost)) }
        }
        let sc = ShortcutStore.shared
        func key(_ a: ShortcutAction) -> String { sc.shortcut(for: a).display }
        let hasSelection = !selection.isEmpty
        let n = selection.count

        // Commands
        add(.init(id: "cmd-feedback", title: "Send Feedback…", symbol: "envelope") { [self] in feedbackOpen = true })
        if SpringCommand.visible(to: bucket.role) {
            add(.init(id: "cmd-spring", title: SpringCommand.title, symbol: "arrow.left.and.right") { [self] in
                closePanel()
                Task { @MainActor in bucket.showSpring = true }
            })
        }
        if hasSelection {
            add(.init(id: "cmd-like", title: "Like / Unlike \(n) selected", symbol: "heart", accessory: key(.like)) { [self] in run(.like) }, boost: 2)
            add(.init(id: "cmd-tag", title: "Edit Tags…", symbol: "tag", accessory: key(.tag)) { [self] in run(.tag) }, boost: 2)
            add(.init(id: "cmd-move", title: "Move to Collection…", symbol: "rectangle.stack", accessory: key(.move)) { [self] in run(.move) }, boost: 2)
            add(.init(id: "cmd-note", title: "Add Note…", symbol: "note.text", accessory: key(.note)) { [self] in run(.note) }, boost: 2)
            add(.init(id: "cmd-autotag", title: "Auto-tag \(n) selected", symbol: "sparkles") { [self] in autoTagSelection() })
            if n == 1, let id = selection.first {
                add(.init(id: "cmd-similar", title: "Find Similar", symbol: "square.on.square") { [self] in findSimilar(to: id) })
            }
            add(.init(id: "cmd-url", title: "Copy Source URL", symbol: "link", accessory: key(.copyURL)) { [self] in run(.copyURL) })
            if source == .trash {
                add(.init(id: "cmd-restore", title: "Restore \(n) from Trash", symbol: "arrow.uturn.backward") { [self] in restoreSelection() })
            } else {
                add(.init(id: "cmd-trash", title: "Move \(n) to Trash", symbol: "trash", accessory: key(.trash)) { [self] in run(.trash) })
            }
        }
        add(.init(id: "cmd-newc", title: "New Collection…", symbol: "plus.rectangle.on.rectangle", accessory: key(.newCollection)) { [self] in run(.newCollection) })
        add(.init(id: "cmd-newf", title: "New Folder…", symbol: "folder.badge.plus") { [self] in promptNewCollection(kind: "folder", parent: nil) })
        add(.init(id: "cmd-news", title: "New Smart Folder…", symbol: "gearshape.2", accessory: key(.newSmartFolder)) { [self] in run(.newSmartFolder) })
        add(.init(id: "cmd-export-html", title: "Export as HTML File…", symbol: "safari", accessory: "⌥⌘E") { [self] in exportWebPage(format: .html) })
        add(.init(id: "cmd-export-pdf", title: "Export as PDF…", symbol: "doc.richtext") { [self] in exportWebPage(format: .pdf) })
        add(.init(id: "cmd-copy-link", title: "Copy Link to This View", symbol: "link", accessory: "⌥⌘L") { [self] in copyViewLink() })
        add(.init(id: "cmd-merge-tags", title: "Merge Similar Tags", symbol: "tag") { [self] in mergeSimilarTags() })
        add(.init(id: "cmd-import-board", title: "Import Boards…", symbol: "square.and.arrow.down.on.square", accessory: "⇧⌘I") { [self] in promptImportBoard() })
        add(.init(id: "cmd-autotag-all", title: "Auto-tag All Untagged Items", symbol: "sparkles") { [self] in autoTagEverything() })
        add(.init(id: "cmd-shuffle", title: "Shuffle", symbol: "shuffle", accessory: key(.shuffle)) { [self] in run(.shuffle) })
        add(.init(id: "cmd-zin", title: "Zoom In", symbol: "plus.magnifyingglass", accessory: key(.zoomIn)) { [self] in run(.zoomIn) })
        add(.init(id: "cmd-zout", title: "Zoom Out", symbol: "minus.magnifyingglass", accessory: key(.zoomOut)) { [self] in run(.zoomOut) })
        add(.init(id: "cmd-grid", title: "View: Grid", symbol: "square.grid.2x2", accessory: "⌘1") { [self] in viewMode = .grid })
        add(.init(id: "cmd-canvas", title: "View: Canvas", symbol: "rectangle.on.rectangle.angled", accessory: "⌘2") { [self] in viewMode = .canvas })
        add(.init(id: "cmd-square", title: "Grid: Square Tiles", symbol: "square.grid.2x2") { [self] in layoutMode = .square })
        add(.init(id: "cmd-masonry", title: "Grid: Original Proportions", symbol: "rectangle.3.group") { [self] in layoutMode = .masonry })
        if let t = undoTitle { add(.init(id: "cmd-undo", title: t, symbol: "arrow.uturn.backward", accessory: "⌘Z") { [self] in Task { await undo() } }) }
        if let t = redoTitle { add(.init(id: "cmd-redo", title: t, symbol: "arrow.uturn.forward", accessory: "⇧⌘Z") { [self] in Task { await redo() } }) }
        add(.init(id: "cmd-empty", title: "Empty Trash…", symbol: "trash.slash") { [self] in confirmEmptyTrash() })
        add(.init(id: "cmd-open", title: "Open Library…", symbol: "folder", accessory: "⌘O") { LibraryPicker.openExisting(self) })
        add(.init(id: "cmd-settings", title: "Settings…", symbol: "gearshape", accessory: "⌘,") { [self] in openSettings() })

        // Places
        let places: [(String, String, Source)] = [("Inbox", "tray", .inbox), ("All", "square.grid.2x2", .all), ("Liked", "heart", .liked), ("Untagged", "tag.slash", .untagged), ("Trash", "trash", .trash)]
        for (name, sym, src) in places {
            add(.init(id: "go-\(name)", title: name, subtitle: "Go to", symbol: sym) { [self] in goTo(src) })
        }
        for c in collections where !c.archived {
            let row = PaletteRow(id: "go-c-\(c.id)", title: c.displayName, subtitle: path(of: c), symbol: c.isCanon ? CanonMark.symbolName : c.kind == "folder" ? "folder" : "rectangle.stack") { [self] in goTo(.collection(c.id)) }
            var best = FuzzyMatcher.score(query: q, in: c.displayName) ?? Int.min
            if c.name.caseInsensitiveCompare(c.displayName) != .orderedSame, let legacy = FuzzyMatcher.score(query: q, in: c.name) {
                best = max(best, legacy)
            }
            if best != Int.min { scored.append((row, best)) }
        }
        for f in smartFolders { add(.init(id: "go-s-\(f.id)", title: f.name, subtitle: "Smart folder", symbol: "gearshape.2") { [self] in goTo(.smart(f.id)) }) }
        for t in tags { add(.init(id: "go-t-\(t.tag)", title: "#\(t.tag)", subtitle: "\(t.count.formatted()) items", symbol: "number", tint: tagColor(t.tag)) { [self] in goTo(.tag(t.tag)) }) }

        var rows = scored.sorted { $0.1 > $1.1 }.prefix(q.isEmpty ? 12 : 14).map(\.0)

        // Items (full-text)
        if let store, q.trimmingCharacters(in: .whitespaces).count >= 2 {
            var iq = ItemQuery(text: q); iq.limit = 8
            let hits = (try? await store.index.query(iq)) ?? []
            for h in hits {
                rows.append(.init(id: "item-\(h.id)", title: h.name, subtitle: "Item · \(h.kind.rawValue)", symbol: ThumbCell.symbol(for: h.kind)) { [self] in
                    source = .all
                    searchText = ""
                    selection = [h.id]
                    previewID = h.id
                })
            }
        }
        return rows
    }

    func goTo(_ s: Source) {
        searchText = ""
        source = s
        focusGridTick_bump()
    }

    private func path(of c: GrailsCollection) -> String {
        var names: [String] = []
        var cur = c.parentId
        while let id = cur, let p = collections.first(where: { $0.id == id }) { names.insert(p.displayName, at: 0); cur = p.parentId }
        return names.isEmpty ? (c.kind == "folder" ? "Folder" : "Collection") : names.joined(separator: " / ")
    }

    func tagColor(_ tag: String) -> Color? { tagColors[tag.lowercased()].map { GrailsHex.color($0) } }

    // MARK: Tags (T)

    func tagRows(_ q: String) async -> [PaletteRow] {
        let ids = Array(selection)
        guard !ids.isEmpty else { return [] }
        let perItem = await loadTags(for: ids)
        var counts: [String: Int] = [:]
        for tagsForItem in perItem.values { for t in Set(tagsForItem.map { $0.lowercased() }) { counts[t, default: 0] += 1 } }

        var rows: [PaletteRow] = []
        let typed = q.trimmingCharacters(in: .whitespaces)
        if !typed.isEmpty, !tags.contains(where: { $0.tag.caseInsensitiveCompare(typed) == .orderedSame }) {
            rows.append(.init(id: "new-tag", title: "Add tag “\(typed)”", symbol: "plus.circle", keepOpen: true) { [self] in
                toggleTag(typed, on: ids)
            })
        }
        let ranked = FuzzyMatcher.rank(tags, query: typed, text: { $0.tag }, limit: 40)
        // tags already on the selection first
        let ordered = ranked.sorted { (counts[$0.tag.lowercased()] ?? 0) > (counts[$1.tag.lowercased()] ?? 0) }
        for t in ordered {
            let have = counts[t.tag.lowercased()] ?? 0
            let mark = have == ids.count ? "✓" : (have > 0 ? "\(have)/\(ids.count)" : "")
            rows.append(.init(id: "tag-\(t.tag)", title: t.tag, symbol: have == ids.count ? "checkmark.circle.fill" : "circle", accessory: mark.isEmpty ? "\(t.count.formatted())" : mark, tint: tagColor(t.tag), keepOpen: true) { [self] in
                toggleTag(t.tag, on: ids)
            })
        }
        return rows
    }

    // MARK: Move (M)

    func moveRows(_ q: String) async -> [PaletteRow] {
        let ids = Array(selection)
        guard !ids.isEmpty else { return [] }
        let from: String?
        if case .collection(let id) = source { from = id } else { from = nil }
        let typed = q.trimmingCharacters(in: .whitespaces)
        var rows: [PaletteRow] = []
        let verb = from == nil ? "Add to" : "Move to"
        let canonID = Canon.collection(in: collections)?.id
        for dest in ItemPlacement.destinations(collections, query: typed, openCollection: from) {
            if dest.id == canonID {
                let offer = Canon.offer(selected: ids, alreadyIn: canonItemIds)
                if !offer.shown { continue }
            }
            let symbol = collections.first { $0.id == dest.id }?.isCanon == true
                ? CanonMark.symbolName
                : (dest.kind == "folder" ? "folder" : "rectangle.stack")
            rows.append(.init(id: "mv-\(dest.id)", title: "\(verb) \(dest.label)", symbol: symbol, depth: dest.depth) { [self] in
                placeItems(ids, in: dest.id)
            })
        }
        let taken = collections.contains { !$0.archived && ($0.displayName.caseInsensitiveCompare(typed) == .orderedSame || $0.name.caseInsensitiveCompare(typed) == .orderedSame) }
        if !typed.isEmpty, !taken {
            rows.append(.init(id: "mv-new", title: "New collection “\(typed)”", subtitle: "Create and \(from == nil ? "add" : "move") \(ids.count) here", symbol: "plus.rectangle.on.rectangle") { [self] in
                Task {
                    await perform("New Collection") { store in
                        let c = try await store.createCollection(name: typed)
                        if let from { try await store.move(ids: ids, from: from, to: c.id) } else { try await store.add(ids: ids, toCollection: c.id) }
                    }
                }
            })
        }
        return rows
    }
}
