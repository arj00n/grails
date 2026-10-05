import Foundation
import GRDB

public struct IndexStats: Sendable, Hashable {
    public var items: Int
    public var tags: Int
}

/// Per-machine SQLite index over a library. Disposable: `rebuild(from:)` recreates all of it from disk.
/// Lives in Application Support, never inside the library (SQLite files corrupt on sync drives).
public final class LibraryIndex: Sendable {
    private let db: any DatabaseWriter
    /// true if an unreadable index file was discarded on open; callers should rebuild.
    public let wasReset: Bool

    public init(path: URL?) throws {
        var reset = false
        func open() throws -> any DatabaseWriter {
            var config = Configuration()
            config.prepareDatabase { db in db.add(collation: .grailsNumeric) }
            guard let path else { return try DatabaseQueue(configuration: config) }
            try FileManager.default.createDirectory(at: path.deletingLastPathComponent(), withIntermediateDirectories: true)
            return try DatabasePool(path: path.path, configuration: config)
        }
        func migrated(_ w: any DatabaseWriter) throws -> any DatabaseWriter {
            try Self.migrator.migrate(w)
            return w
        }
        do {
            db = try migrated(open())
        } catch {
            guard let path else { throw error }
            for suffix in ["", "-wal", "-shm"] { try? FileManager.default.removeItem(atPath: path.path + suffix) }
            reset = true
            db = try migrated(open())
        }
        wasReset = reset
    }

    private static var migrator: DatabaseMigrator {
        var m = DatabaseMigrator()
        m.registerMigration("v1") { db in
            try db.execute(sql: """
            CREATE TABLE items (
              id TEXT PRIMARY KEY, kind TEXT NOT NULL, name TEXT NOT NULL, ext TEXT, bytes INTEGER,
              width INTEGER, height INTEGER, durationSec REAL, sha256 TEXT,
              sourceUrl TEXT, sourcePageUrl TEXT, sourceSite TEXT, sourceAuthor TEXT, sourceTitle TEXT,
              liked INTEGER NOT NULL DEFAULT 0, note TEXT NOT NULL DEFAULT '', ocrText TEXT NOT NULL DEFAULT '',
              addedAt REAL NOT NULL, addedBy TEXT NOT NULL, updatedAt REAL NOT NULL, updatedBy TEXT NOT NULL,
              deletedAt REAL, mtime REAL NOT NULL
            );
            CREATE INDEX items_added ON items(addedAt);
            CREATE INDEX items_sha ON items(sha256);
            CREATE INDEX items_kind ON items(kind);
            CREATE TABLE item_tags (
              itemId TEXT NOT NULL, tag TEXT NOT NULL COLLATE NOCASE, PRIMARY KEY (itemId, tag)
            ) WITHOUT ROWID;
            CREATE INDEX item_tags_tag ON item_tags(tag);
            CREATE TABLE item_collections (
              itemId TEXT NOT NULL, collectionId TEXT NOT NULL, orderKey TEXT NOT NULL,
              PRIMARY KEY (itemId, collectionId)
            ) WITHOUT ROWID;
            CREATE INDEX item_collections_coll ON item_collections(collectionId, orderKey);
            CREATE TABLE palette (
              itemId TEXT NOT NULL, hex TEXT NOT NULL, weight REAL NOT NULL, l REAL, a REAL, b REAL
            );
            CREATE INDEX palette_item ON palette(itemId);
            CREATE TABLE embeddings (
              itemId TEXT PRIMARY KEY, model TEXT NOT NULL, vec BLOB NOT NULL
            ) WITHOUT ROWID;
            CREATE TABLE collections (
              id TEXT PRIMARY KEY, kind TEXT NOT NULL, name TEXT NOT NULL, parentId TEXT,
              orderKey TEXT NOT NULL, archived INTEGER NOT NULL DEFAULT 0, mtime REAL NOT NULL
            );
            CREATE VIRTUAL TABLE items_fts USING fts5(
              name, tags, note, ocrText, source,
              prefix='2 3 4', tokenize='unicode61 remove_diacritics 2'
            );
            """)
        }
        m.registerMigration("v2-link-display") { db in
            try db.execute(sql: """
            ALTER TABLE items ADD COLUMN linkDisplay TEXT;
            ALTER TABLE items ADD COLUMN badge TEXT;
            """)
        }
        m.registerMigration("v3-autotag") { db in
            try db.execute(sql: "ALTER TABLE items ADD COLUMN autoTaggedAt REAL")
        }
        m.registerMigration("v4-autotag-model") { db in
            try db.execute(sql: "ALTER TABLE items ADD COLUMN autoTagModel TEXT")      // which engine tagged it: a better engine can redo it
        }
        return m
    }

    // MARK: Writes

    public func upsert(_ item: Item, mtime: Double) async throws {
        try await db.write { db in try Self.write(item, mtime: mtime, fresh: false, in: db) }
    }

    public func upsert(_ entries: [(item: Item, mtime: Double)]) async throws {
        try await db.write { db in
            for e in entries { try Self.write(e.item, mtime: e.mtime, fresh: false, in: db) }
        }
    }

    public func remove(ids: [String]) async throws {
        try await db.write { db in
            for id in ids { try Self.delete(id: id, in: db) }
        }
    }

    public func upsertCollection(_ c: GrailsCollection, mtime: Double) async throws {
        try await db.write { db in
            try db.execute(sql: """
            INSERT INTO collections (id, kind, name, parentId, orderKey, archived, mtime) VALUES (?,?,?,?,?,?,?)
            ON CONFLICT(id) DO UPDATE SET kind=excluded.kind, name=excluded.name, parentId=excluded.parentId,
              orderKey=excluded.orderKey, archived=excluded.archived, mtime=excluded.mtime
            """, arguments: [c.id, c.kind, c.name, c.parentId, c.order, c.archived, mtime])
        }
    }

    /// Drops everything and re-reads the library from disk. Returns files that could not be read.
    @discardableResult
    public func rebuild(from layout: LibraryLayout) async throws -> [ScanFailure] {
        let scan = await ItemScanner.scanAll(layout)
        let collections = Self.readCollections(layout)
        try await db.write { db in
            for table in ["items", "item_tags", "item_collections", "palette", "collections"] {
                try db.execute(sql: "DELETE FROM \(table)")
            }
            try db.execute(sql: "DELETE FROM items_fts")
            for e in scan.items { try Self.write(e.item, mtime: e.mtime, fresh: true, in: db) }
            for c in collections {
                try db.execute(sql: """
                INSERT INTO collections (id, kind, name, parentId, orderKey, archived, mtime) VALUES (?,?,?,?,?,?,?)
                """, arguments: [c.value.id, c.value.kind, c.value.name, c.value.parentId, c.value.order, c.value.archived, c.mtime])
            }
        }
        return scan.failures
    }

    static func readCollections(_ layout: LibraryLayout) -> [(value: GrailsCollection, mtime: Double)] {
        let urls = (try? FileManager.default.contentsOfDirectory(at: layout.collectionsDir, includingPropertiesForKeys: nil)) ?? []
        return urls.compactMap { url in
            let name = url.lastPathComponent
            guard name.hasSuffix(".json"), !AtomicFile.isTemp(name), ULID.isValid(String(name.dropLast(5))),
                  let data = try? Data(contentsOf: url), let c = try? GrailsJSON.decode(GrailsCollection.self, from: data),
                  let m = FileStat.mtime(url) else { return nil }
            return (c, m)
        }
    }

    // MARK: Reads

    public func stats() async throws -> IndexStats {
        try await db.read { db in
            IndexStats(
                items: try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM items") ?? 0,
                tags: try Int.fetchOne(db, sql: "SELECT COUNT(DISTINCT tag) FROM item_tags") ?? 0
            )
        }
    }

    /// id → item.json mtime, for cheap change detection on rescan.
    public func allMtimes() async throws -> [String: Double] {
        try await db.read { db in
            var out: [String: Double] = [:]
            let cursor = try Row.fetchCursor(db, sql: "SELECT id, mtime FROM items")
            while let row = try cursor.next() { out[row[0]] = row[1] }
            return out
        }
    }

    /// mtime of `item.json` as last indexed, for the given ids.
    public func mtimes(for ids: [String]) async throws -> [String: Double] {
        try await db.read { db in
            var out: [String: Double] = [:]
            for id in ids { if let m = try Double.fetchOne(db, sql: "SELECT mtime FROM items WHERE id = ?", arguments: [id]) { out[id] = m } }
            return out
        }
    }

    /// Distinct "added by" handles with item counts (not trashed), biggest first.
    public func addedByCounts() async throws -> [(who: String, count: Int)] {
        try await db.read { db in
            try Row.fetchAll(db, sql: "SELECT addedBy AS who, COUNT(*) AS n FROM items WHERE deletedAt IS NULL AND addedBy <> '' GROUP BY addedBy ORDER BY n DESC, addedBy").map { ($0["who"], $0["n"]) }
        }
    }

    public func itemId(withSHA256 sha: String, includeDeleted: Bool = false) async throws -> String? {
        try await db.read { db in
            try String.fetchOne(db, sql: "SELECT id FROM items WHERE sha256 = ?" + (includeDeleted ? "" : " AND deletedAt IS NULL") + " LIMIT 1", arguments: [sha])
        }
    }

    public func maxOrderKey(collectionId: String) async throws -> String? {
        try await db.read { db in
            try String.fetchOne(db, sql: "SELECT MAX(orderKey) FROM item_collections WHERE collectionId = ?", arguments: [collectionId])
        }
    }

    /// Replaces the collections table with what's on disk (picks up deletions made by other machines).
    public func replaceCollections(_ list: [(value: GrailsCollection, mtime: Double)]) async throws {
        try await db.write { db in
            try db.execute(sql: "DELETE FROM collections")
            for c in list {
                try db.execute(sql: """
                INSERT INTO collections (id, kind, name, parentId, orderKey, archived, mtime) VALUES (?,?,?,?,?,?,?)
                """, arguments: [c.value.id, c.value.kind, c.value.name, c.value.parentId, c.value.order, c.value.archived, c.mtime])
            }
        }
    }

    public func removeCollection(id: String) async throws {
        try await db.write { db in
            try db.execute(sql: "DELETE FROM collections WHERE id = ?", arguments: [id])
            try db.execute(sql: "DELETE FROM item_collections WHERE collectionId = ?", arguments: [id])
        }
    }

    /// Ids of every item in the library (including trashed) that currently has `tag` (case-insensitive).
    public func itemIds(withTag tag: String) async throws -> [String] {
        try await db.read { db in
            try String.fetchAll(db, sql: "SELECT itemId FROM item_tags WHERE tag = ?", arguments: [tag])
        }
    }

    public func itemIds(inCollection id: String) async throws -> [String] {
        try await db.read { db in
            try String.fetchAll(db, sql: "SELECT itemId FROM item_collections WHERE collectionId = ?", arguments: [id])
        }
    }

    public func collections() async throws -> [GrailsCollection] {
        try await db.read { db in
            try Row.fetchAll(db, sql: "SELECT * FROM collections ORDER BY orderKey").map { r in
                GrailsCollection(
                    id: r["id"], kind: r["kind"], name: r["name"], parentId: r["parentId"], order: r["orderKey"],
                    archived: r["archived"], updatedAt: Date(timeIntervalSince1970: r["mtime"]), updatedBy: ""
                )
            }
        }
    }

    /// Tags on just these items, most used first: what a view of those items has to offer to narrow it further.
    public func tagCounts(among ids: Set<String>) async throws -> [(tag: String, count: Int)] {
        guard !ids.isEmpty else { return [] }
        return try await db.read { db in
            var counts: [String: Int] = [:]
            let rows = try Row.fetchCursor(db, sql: "SELECT t.itemId AS id, t.tag AS tag FROM item_tags t JOIN items i ON i.id = t.itemId WHERE i.deletedAt IS NULL")
            while let row = try rows.next() {
                let id: String = row["id"]
                if ids.contains(id) { counts[row["tag"] as String, default: 0] += 1 }
            }
            return counts.map { (tag: $0.key, count: $0.value) }.sorted { $0.count != $1.count ? $0.count > $1.count : $0.tag < $1.tag }
        }
    }

    public func tagCounts() async throws -> [(tag: String, count: Int)] {
        try await db.read { db in
            try Row.fetchAll(db, sql: """
            SELECT t.tag AS tag, COUNT(*) AS n FROM item_tags t JOIN items i ON i.id = t.itemId
            WHERE i.deletedAt IS NULL GROUP BY t.tag ORDER BY n DESC, t.tag
            """).map { ($0["tag"], $0["n"]) }
        }
    }

    public func query(_ q: ItemQuery) async throws -> [ItemSummary] {
        let (sql, args) = Self.build(q, count: false)
        return try await db.read { db in
            try Row.fetchAll(db, sql: sql, arguments: args).map(Self.summary)
        }
    }

    public func count(_ q: ItemQuery) async throws -> Int {
        let (sql, args) = Self.build(q, count: true)
        return try await db.read { db in try Int.fetchOne(db, sql: sql, arguments: args) ?? 0 }
    }

    // MARK: Internals

    private static func summary(_ r: Row) -> ItemSummary {
        ItemSummary(
            id: r["id"], kind: ItemKind(rawValue: r["kind"]), name: r["name"], ext: r["ext"], width: r["width"],
            height: r["height"], bytes: r["bytes"], liked: r["liked"],
            addedAt: Date(timeIntervalSince1970: r["addedAt"]), addedBy: r["addedBy"],
            deletedAt: (r["deletedAt"] as Double?).map { Date(timeIntervalSince1970: $0) },
            site: r["sourceSite"], linkDisplay: r["linkDisplay"], badge: r["badge"], durationSec: r["durationSec"]
        )
    }

    static func build(_ q: ItemQuery, count: Bool) -> (String, StatementArguments) {
        var args = StatementArguments()
        var wheres: [String] = []
        var from = "items i"
        let pattern = q.text.flatMap { FTS5Pattern(matchingAllPrefixesIn: $0) }
        if let pattern {
            from = "items_fts f JOIN items i ON i.rowid = f.rowid"
            wheres.append("items_fts MATCH ?")
            args += [pattern.rawPattern]
        } else if let t = q.text, !t.trimmingCharacters(in: .whitespaces).isEmpty {
            wheres.append("0") // text had no searchable tokens
        }
        wheres.append(q.deleted ? "i.deletedAt IS NOT NULL" : "i.deletedAt IS NULL")
        if !q.kinds.isEmpty {
            wheres.append("i.kind IN (\(q.kinds.map { _ in "?" }.joined(separator: ",")))")
            for k in q.kinds.sorted(by: { $0.rawValue < $1.rawValue }) { args += [k.rawValue] }
        }
        if q.likedOnly { wheres.append("i.liked = 1") }
        if let tag = q.tag {
            wheres.append("EXISTS (SELECT 1 FROM item_tags t WHERE t.itemId = i.id AND t.tag = ?)")
            args += [tag]
        }
        for extra in q.extraTags {
            wheres.append("EXISTS (SELECT 1 FROM item_tags t WHERE t.itemId = i.id AND t.tag = ?)")
            args += [extra]
        }
        if q.untagged { wheres.append("NOT EXISTS (SELECT 1 FROM item_tags t WHERE t.itemId = i.id)") }
        if let c = q.collectionId {
            wheres.append("EXISTS (SELECT 1 FROM item_collections ic WHERE ic.itemId = i.id AND ic.collectionId = ?)")
            args += [c]
        }
        if !q.collectionIds.isEmpty {
            wheres.append("EXISTS (SELECT 1 FROM item_collections ic WHERE ic.itemId = i.id AND ic.collectionId IN (\(q.collectionIds.map { _ in "?" }.joined(separator: ","))))")
            for id in q.collectionIds.sorted() { args += [id] }
        }
        if q.needsAutoTags {
            // never tagged, or (when a better engine is available) tagged by a different, older one
            if let engine = q.upgradeAutoTagsTo {
                wheres.append("(i.autoTaggedAt IS NULL OR i.autoTagModel IS NOT ?) AND i.kind IN ('image', 'gif', 'raw', 'link', 'video')")
                args += [engine]
            } else {
                wheres.append("i.autoTaggedAt IS NULL AND i.kind IN ('image', 'gif', 'raw', 'link', 'video')")
            }
        }
        if let who = q.addedBy { wheres.append("i.addedBy = ?"); args += [who] }
        if q.squareOnly { wheres.append("i.width > 0 AND i.height > 0 AND ABS(i.width * 1.0 / i.height - 1.0) <= 0.05") }
        if let smart = q.smart {
            let (sql, a) = SmartRuleCompiler.compile(smart)
            wheres.append("(\(sql))")
            args += a
        }
        if q.unfiled { wheres.append("NOT EXISTS (SELECT 1 FROM item_collections ic WHERE ic.itemId = i.id)") }
        let whereSQL = wheres.joined(separator: " AND ")
        if count { return ("SELECT COUNT(*) FROM \(from) WHERE \(whereSQL)", args) }

        let order: String
        switch q.effectiveSort {
        case .relevance: order = pattern == nil ? "i.addedAt DESC, i.id DESC" : "bm25(items_fts), i.addedAt DESC"
        case .addedDesc: order = "i.addedAt DESC, i.id DESC"
        case .addedAsc: order = "i.addedAt ASC, i.id ASC"
        case .nameAsc: order = "i.name COLLATE grails_numeric ASC, i.id"
        case .nameDesc: order = "i.name COLLATE grails_numeric DESC, i.id"
        case .sizeDesc: order = "i.bytes DESC, i.id"
        case .random: order = "RANDOM()"
        }
        args += [q.limit, q.offset]
        return ("""
        SELECT i.id, i.kind, i.name, i.ext, i.width, i.height, i.bytes, i.liked, i.addedAt, i.addedBy, i.deletedAt, i.sourceSite, i.linkDisplay, i.badge, i.durationSec
        FROM \(from) WHERE \(whereSQL) ORDER BY \(order) LIMIT ? OFFSET ?
        """, args)
    }

    private static let itemColumns = [
        "id", "kind", "name", "ext", "bytes", "width", "height", "durationSec", "sha256", "sourceUrl", "sourcePageUrl",
        "sourceSite", "sourceAuthor", "sourceTitle", "liked", "note", "ocrText", "addedAt", "addedBy", "updatedAt",
        "updatedBy", "deletedAt", "mtime", "linkDisplay", "badge", "autoTaggedAt", "autoTagModel",
    ]
    private static let upsertSQL: String = {
        let cols = itemColumns.joined(separator: ", ")
        let marks = itemColumns.map { _ in "?" }.joined(separator: ", ")
        let updates = itemColumns.dropFirst().map { "\($0)=excluded.\($0)" }.joined(separator: ", ")
        return "INSERT INTO items (\(cols)) VALUES (\(marks)) ON CONFLICT(id) DO UPDATE SET \(updates)"
    }()

    private static func write(_ item: Item, mtime: Double, fresh: Bool, in db: Database) throws {
        let s = item.source
        try db.cachedStatement(sql: upsertSQL).execute(arguments: [
            item.id, item.kind.rawValue, item.name, item.ext, item.bytes, item.width, item.height, item.durationSec,
            item.sha256, s?.url, s?.pageUrl, s?.site, s?.author, s?.title, item.liked, item.note, item.ocrText,
            item.addedAt.timeIntervalSince1970, item.addedBy, item.updatedAt.timeIntervalSince1970, item.updatedBy,
            item.deletedAt?.timeIntervalSince1970, mtime, item.extras["linkDisplay"].flatMap(Self.string), item.extras["badge"].flatMap(Self.string),
            Self.autoTaggedAt(item), Self.autoTagModel(item),
        ])
        let rowid = try Int64.fetchOne(db, sql: "SELECT rowid FROM items WHERE id = ?", arguments: [item.id])!
        if !fresh {
            for table in ["item_tags", "item_collections", "palette"] {
                try db.cachedStatement(sql: "DELETE FROM \(table) WHERE itemId = ?").execute(arguments: [item.id])
            }
            try db.cachedStatement(sql: "DELETE FROM items_fts WHERE rowid = ?").execute(arguments: [rowid])
        }
        let tagStmt = try db.cachedStatement(sql: "INSERT OR IGNORE INTO item_tags (itemId, tag) VALUES (?, ?)")
        for tag in item.tags { try tagStmt.execute(arguments: [item.id, tag]) }
        let collStmt = try db.cachedStatement(sql: "INSERT OR REPLACE INTO item_collections (itemId, collectionId, orderKey) VALUES (?,?,?)")
        for (cid, key) in item.collections { try collStmt.execute(arguments: [item.id, cid, key]) }
        let palStmt = try db.cachedStatement(sql: "INSERT INTO palette (itemId, hex, weight, l, a, b) VALUES (?,?,?,?,?,?)")
        for p in item.palette {
            let lab = ColorMath.lab(fromHex: p.hex)
            try palStmt.execute(arguments: [item.id, p.hex, p.weight, lab?.l, lab?.a, lab?.b])
        }
        let source = [s?.site, s?.title, s?.author].compactMap { $0 }.joined(separator: " ")
        try db.cachedStatement(sql: "INSERT INTO items_fts (rowid, name, tags, note, ocrText, source) VALUES (?,?,?,?,?,?)")
            .execute(arguments: [rowid, item.name, item.tags.joined(separator: " "), item.note, item.ocrText, source])
    }

    private static func autoTagModel(_ item: Item) -> String? {
        guard case .object(let o)? = item.extras["autoTagged"], case .string(let m)? = o["model"] else { return nil }
        return m
    }

    private static func autoTaggedAt(_ item: Item) -> Double? {
        guard case .object(let o)? = item.extras["autoTagged"] else { return nil }
        if case .double(let d)? = o["at"] { return d }
        if case .int(let i)? = o["at"] { return Double(i) }
        return 0      // marked, time unknown
    }

    private static func string(_ v: JSONValue) -> String? { if case .string(let s) = v { s } else { nil } }

    private static func delete(id: String, in db: Database) throws {
        if let rowid = try Int64.fetchOne(db, sql: "SELECT rowid FROM items WHERE id = ?", arguments: [id]) {
            try db.execute(sql: "DELETE FROM items_fts WHERE rowid = ?", arguments: [rowid])
        }
        for table in ["item_tags", "item_collections", "palette", "embeddings"] {
            try db.execute(sql: "DELETE FROM \(table) WHERE itemId = ?", arguments: [id])
        }
        try db.execute(sql: "DELETE FROM items WHERE id = ?", arguments: [id])
    }
}

extension DatabaseCollation {
    /// Case-, diacritic-insensitive, numeric-aware ("2" sorts before "10").
    static let grailsNumeric = DatabaseCollation("grails_numeric") { a, b in
        a.compare(b, options: [.numeric, .caseInsensitive, .diacriticInsensitive])
    }
}
