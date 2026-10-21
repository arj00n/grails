import Foundation

extension LibraryMigration {
    /// Merges a folder library into the library already stored in the bucket.
    /// The destination `library.json` stays. Items already stored under the same content hash are skipped.
    /// Tags and collections join by name. Added-by and dates are copied through from the folder.
    public static func merge(root: URL, store: any ObjectStore, limit: Int = Int.max) async throws -> MigrationProgress {
        guard try await hasLibrary(store) else { throw MigrationError.destinationHasNoLibrary }
        var ledger = try await load(store)
        var state = ledger.merge ?? MigrationMerge()
        let source = try SourceLibrary(root: root)
        if !state.planned || !source.itemIDs.isSubset(of: state.items.keys) {
            let dest = try await DestIndex.load(store)
            plan(&state, source: source, dest: dest)
            ledger.merge = state
            try await save(ledger, store: store)
        }
        if !state.tagsMerged {
            try await mergeTags(store: store, source: source, canon: state.tagCanon)
            state.tagsMerged = true
            ledger.merge = state
            try await save(ledger, store: store)
        }
        var remoteKeys = Set(try await store.list(prefix: "").map(\.key))
        try await uploadCollections(&state, source: source, store: store, remoteKeys: &remoteKeys)
        ledger.merge = state
        try await save(ledger, store: store)
        let pending = state.items.filter { !$0.value.done && !$0.value.duplicate && $0.value.failure == nil }
            .keys.sorted()
        for id in pending.prefix(max(0, limit)) {
            do {
                try await uploadItem(id, state: state, source: source, store: store, remoteKeys: &remoteKeys)
                state.items[id]?.done = true
            } catch {
                state.items[id]?.failure = failureReason(error)
                state.items[id]?.done = true
            }
            ledger.merge = state
            try await save(ledger, store: store)
        }
        let itemsLeft = state.items.values.contains { !$0.done }
        if !itemsLeft && !state.sideMerged {
            try await uploadSide(&state, source: source, store: store, remoteKeys: &remoteKeys)
            state.sideMerged = true
            ledger.merge = state
            try await save(ledger, store: store)
        }
        return progress(state)
    }

    static func progress(_ state: MigrationMerge) -> MigrationProgress {
        let merged = state.items.values.filter { $0.done && !$0.duplicate && $0.failure == nil }.count
        let duplicates = state.items.values.filter(\.duplicate).count
        let failures = state.items.compactMap { id, item -> MigrationSkip? in
            guard let failure = item.failure else { return nil }
            return MigrationSkip(key: "items/\(id)", reason: failure)
        }.sorted { $0.key < $1.key }
        let remaining = state.items.filter { !$0.value.done }.keys.sorted()
        return MigrationProgress(
            copied: merged + duplicates, total: state.items.count, remaining: remaining,
            merged: merged, duplicates: duplicates, skips: state.skips, failures: failures, rewrites: state.rewrites
        )
    }
}

private struct SourceItem {
    var id: String
    var folder: URL
    var json: Data
    var object: [String: Any]
    var hash: String?
    var addedAt: String
    var deleted: Bool
    var file: String?
}

private struct SourceLibrary {
    var root: URL
    var items: [SourceItem]
    var itemIDs: Set<String>
    var collections: [(id: String, name: String, data: Data)]
    var tags: Data?
    var notes: [(key: String, data: Data)]
    var canvases: [(key: String, data: Data)]
    var members: [(key: String, data: Data)]
    var snapshots: [String]
    var extras: [(key: String, url: URL)]

    init(root: URL) throws {
        let fm = FileManager.default
        self.root = root
        let itemsRoot = root.appendingPathComponent("items", isDirectory: true)
        var items: [SourceItem] = []
        if let folders = try? fm.contentsOfDirectory(at: itemsRoot, includingPropertiesForKeys: [.isDirectoryKey]) {
            for folder in folders {
                var isDir: ObjCBool = false
                guard fm.fileExists(atPath: folder.path, isDirectory: &isDir), isDir.boolValue else { continue }
                let jsonURL = folder.appendingPathComponent("item.json")
                guard fm.fileExists(atPath: jsonURL.path), let data = try? Data(contentsOf: jsonURL),
                      let object = JSONText.object(data) else { continue }
                let id = object["id"] as? String ?? folder.lastPathComponent
                items.append(SourceItem(
                    id: id, folder: folder, json: data, object: object,
                    hash: (object["sha256"] as? String)?.lowercased(),
                    addedAt: object["addedAt"] as? String ?? "",
                    deleted: object["deletedAt"] != nil,
                    file: object["file"] as? String
                ))
            }
        }
        self.items = items
        itemIDs = Set(items.map(\.id))
        collections = Self.collectionFiles(root)
        tags = fm.fileExists(atPath: root.appendingPathComponent("tags.json").path)
            ? try? Data(contentsOf: root.appendingPathComponent("tags.json")) : nil
        notes = Self.dataFiles(root.appendingPathComponent("notes"), prefix: "notes")
        canvases = Self.dataFiles(root.appendingPathComponent("canvas"), prefix: "canvas")
        members = Self.dataFiles(root.appendingPathComponent(".members"), prefix: ".members")
        snapshots = (try? fm.contentsOfDirectory(atPath: root.appendingPathComponent(".snapshots").path))?
            .sorted().map { ".snapshots/\($0)" } ?? []
        let handled: (String) -> Bool = { key in
            key == "library.json" || key == "tags.json" || key.hasPrefix("items/") || key.hasPrefix("collections/")
                || key.hasPrefix("notes/") || key.hasPrefix("canvas/") || key.hasPrefix(".members/")
        }
        extras = sourceKeys(root).filter { !handled($0) }.map { ($0, root.appendingPathComponent($0)) }
    }

    private static func collectionFiles(_ root: URL) -> [(id: String, name: String, data: Data)] {
        let dir = root.appendingPathComponent("collections", isDirectory: true)
        guard let urls = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return [] }
        return urls.compactMap { url in
            guard url.pathExtension == "json", let data = try? Data(contentsOf: url), let object = JSONText.object(data) else { return nil }
            let id = object["id"] as? String ?? url.deletingPathExtension().lastPathComponent
            return (id, object["name"] as? String ?? "", data)
        }.sorted { $0.id < $1.id }
    }

    private static func dataFiles(_ dir: URL, prefix: String) -> [(key: String, data: Data)] {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: dir.path) else { return [] }
        return names.sorted().compactMap { name in
            let url = dir.appendingPathComponent(name)
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), !isDir.boolValue,
                  let data = try? Data(contentsOf: url) else { return nil }
            return ("\(prefix)/\(name)", data)
        }
    }
}

private struct DestCollection {
    var id: String
    var name: String
}

private struct DestIndex {
    var idByHash: [String: String]
    var hashByID: [String: String]
    var deletedIDs: Set<String>
    var itemIDs: Set<String>
    var itemTags: [String]
    var tagKeys: [String]
    var collections: [DestCollection]
    var collectionIDs: Set<String>

    static func load(_ store: any ObjectStore) async throws -> DestIndex {
        let heads = try await store.list(prefix: "")
        var index = DestIndex(idByHash: [:], hashByID: [:], deletedIDs: [], itemIDs: [], itemTags: [], tagKeys: [], collections: [], collectionIDs: [])
        let itemKeys = heads.map(\.key).filter { $0.hasPrefix("items/") && $0.hasSuffix("/item.json") && !$0.hasPrefix("trash/") }.sorted()
        for key in itemKeys {
            let data = try await store.get(key).body
            guard let object = JSONText.object(data) else { continue }
            let id = object["id"] as? String ?? itemID(in: key)
            index.itemIDs.insert(id)
            if object["deletedAt"] != nil { index.deletedIDs.insert(id) }
            if let tags = object["tags"] as? [String] { index.itemTags.append(contentsOf: tags) }
            if let hash = (object["sha256"] as? String)?.lowercased(), !hash.isEmpty {
                index.hashByID[id] = hash
                if let current = index.idByHash[hash] {
                    if index.deletedIDs.contains(current) && object["deletedAt"] == nil {
                        index.idByHash[hash] = id
                    }
                } else {
                    index.idByHash[hash] = id
                }
            }
        }
        if let tags = try? await store.get("tags.json").body, let object = JSONText.object(tags),
           let table = object["tags"] as? [String: Any] {
            index.tagKeys = Array(table.keys)
        }
        let collectionKeys = heads.map(\.key).filter { $0.hasPrefix("collections/") && $0.hasSuffix(".json") }.sorted()
        for key in collectionKeys {
            let data = try await store.get(key).body
            guard let object = JSONText.object(data) else { continue }
            let id = object["id"] as? String ?? key.dropFirst("collections/".count).replacingOccurrences(of: ".json", with: "")
            index.collections.append(DestCollection(id: String(id), name: object["name"] as? String ?? ""))
            index.collectionIDs.insert(String(id))
        }
        return index
    }
}

private func itemID(in key: String) -> String {
    let parts = key.split(separator: "/")
    return parts.count >= 2 ? String(parts[1]) : key
}

private func plan(_ state: inout MigrationMerge, source: SourceLibrary, dest: DestIndex) {
    if !state.planned {
        state.items = [:]
        state.collections = [:]
        state.createdCollections = []
        state.skips = [MigrationSkip(key: "library.json", reason: "kept the destination library")]
        state.skips += source.snapshots.map { MigrationSkip(key: $0, reason: "snapshot stays in the Drive library") }
        var byFold: [String: [(id: String, name: String)]] = [:]
        for collection in dest.collections {
            byFold[foldName(collection.name), default: []].append((collection.id, collection.name))
        }
        var taken = dest.collectionIDs
        for collection in source.collections {
            let matches = byFold[foldName(collection.name)] ?? []
            let exact = matches.filter { $0.name == collection.name }
            if matches.count == 1 {
                state.collections[collection.id] = matches[0].id
            } else if exact.count == 1 {
                state.collections[collection.id] = exact[0].id
            } else if matches.count > 1 {
                let destID = freshID(avoiding: taken)
                taken.insert(destID)
                state.collections[collection.id] = destID
                state.createdCollections.append(destID)
                state.skips.append(MigrationSkip(key: "collections/\(collection.id).json", reason: "collection name \(collection.name) matches more than one"))
            } else if taken.contains(collection.id) {
                let destID = freshID(avoiding: taken)
                taken.insert(destID)
                state.collections[collection.id] = destID
                state.createdCollections.append(destID)
                state.rewrites.append(MigrationSkip(key: "collections/\(collection.id).json", reason: "collection id collided and was written as \(destID)"))
            } else {
                taken.insert(collection.id)
                state.collections[collection.id] = collection.id
                state.createdCollections.append(collection.id)
            }
        }
        state.tagCanon = tagCanon(destTags: dest.itemTags + dest.tagKeys, destLocked: dest.tagKeys, source: source)
    }
    var owner = dest.idByHash
    for existing in source.items {
        guard let decided = state.items[existing.id], decided.failure == nil, !decided.duplicate, let hash = existing.hash else { continue }
        if owner[hash] == nil { owner[hash] = decided.dest }
    }
    var takenIDs = dest.itemIDs.union(state.items.values.map(\.dest))
    let pending = source.items.filter { state.items[$0.id] == nil }.sorted { a, b in
        if a.deleted != b.deleted { return !a.deleted }
        if a.addedAt != b.addedAt { return a.addedAt < b.addedAt }
        return a.id < b.id
    }
    for item in pending {
        if let failure = hashFailure(item) {
            state.items[item.id] = MigrationItem(dest: item.id, duplicate: false, failure: failure, done: true)
            continue
        }
        if let hash = item.hash, let destID = owner[hash] {
            state.items[item.id] = MigrationItem(dest: destID, duplicate: true, done: true)
            state.skips.append(MigrationSkip(key: "items/\(item.id)", reason: "duplicate of \(destID)"))
            continue
        }
        var destID = item.id
        if takenIDs.contains(destID) || dest.hashByID[destID].map({ $0 != item.hash }) == true {
            destID = freshID(avoiding: takenIDs)
            state.rewrites.append(MigrationSkip(key: "items/\(item.id)", reason: "item id collided and was written as \(destID)"))
        }
        takenIDs.insert(destID)
        if let hash = item.hash { owner[hash] = destID }
        state.items[item.id] = MigrationItem(dest: destID, duplicate: false, done: false)
    }
    state.planned = true
}

private func tagCanon(destTags: [String], destLocked: [String], source: SourceLibrary) -> [String: String] {
    var map: [String: String] = [:]
    var locked: Set<String> = []
    func add(_ spelling: String, lock: Bool) {
        let fold = foldName(spelling)
        guard !fold.isEmpty else { return }
        if locked.contains(fold) { return }
        if lock {
            map[fold] = spelling
            locked.insert(fold)
            return
        }
        if map[fold] == nil { map[fold] = spelling }
    }
    for tag in destTags { add(tag, lock: false) }
    for tag in destLocked { add(tag, lock: true) }
    if let data = source.tags, let object = JSONText.object(data), let table = object["tags"] as? [String: Any] {
        for key in table.keys { add(key, lock: false) }
    }
    for item in source.items {
        for tag in item.object["tags"] as? [String] ?? [] { add(tag, lock: false) }
        for tag in item.object["autoTags"] as? [String] ?? [] { add(tag, lock: false) }
    }
    return map
}

private func hashFailure(_ item: SourceItem) -> String? {
    guard let file = item.file else { return nil }
    let url = item.folder.appendingPathComponent(file)
    guard FileManager.default.fileExists(atPath: url.path) else {
        return item.deleted ? nil : "missing \(file)"
    }
    guard let expected = item.hash else { return nil }
    guard let actual = fileHash(url), actual == expected else { return "content hash does not match \(file)" }
    return nil
}

private func mergeTags(store: any ObjectStore, source: SourceLibrary, canon: [String: String]) async throws {
    let sourceObject = source.tags.flatMap { JSONText.object($0) }
    let sourceTable = sourceObject?["tags"] as? [String: Any] ?? [:]
    var destBody: Data?
    var etag: String?
    do {
        let got = try await store.get("tags.json")
        destBody = got.body
        etag = got.etag
    } catch let error as S3Error where error == .notFound {
        destBody = nil
    }
    var root = destBody.flatMap { JSONText.object($0) } ?? ["schema": 1, "tags": [String: Any]()]
    var table = root["tags"] as? [String: Any] ?? [:]
    let present = Set(table.keys.map(foldName))
    var changed = false
    for (key, meta) in sourceTable {
        let fold = foldName(key)
        guard !present.contains(fold) else { continue }
        let spelling = canon[fold] ?? key
        table[spelling] = meta
        changed = true
    }
    guard changed else { return }
    root["tags"] = table
    let body = try JSONText.data(root)
    if let etag {
        _ = try await store.put("tags.json", body: body, contentType: "application/json", ifMatch: etag, ifNoneMatch: nil)
    } else {
        try await putNew(store, key: "tags.json", body: body)
    }
}

private func uploadCollections(_ state: inout MigrationMerge, source: SourceLibrary, store: any ObjectStore, remoteKeys: inout Set<String>) async throws {
    let links = itemMap(state)
    for collection in source.collections {
        guard let destID = state.collections[collection.id], state.createdCollections.contains(destID) else { continue }
        let key = "collections/\(destID).json"
        var map = state.collections
        map.merge(links) { collection, _ in collection }
        let body = JSONText.replacingIDs(collection.data, map)
        if remoteKeys.contains(key) {
            let got = try await store.get(key)
            if Digests.sha256Hex(got.body) != Digests.sha256Hex(body) {
                record(&state, key: key, reason: "destination already has a different collection")
            }
            continue
        }
        try await putNew(store, key: key, body: body)
        remoteKeys.insert(key)
    }
}

private func uploadItem(_ id: String, state: MigrationMerge, source: SourceLibrary, store: any ObjectStore, remoteKeys: inout Set<String>) async throws {
    guard let item = source.items.first(where: { $0.id == id }), let planned = state.items[id] else { return }
    let destID = planned.dest
    let names = (try? FileManager.default.contentsOfDirectory(atPath: item.folder.path))?.sorted() ?? []
    for name in names where name != "item.json" {
        let url = item.folder.appendingPathComponent(name)
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), !isDir.boolValue else { continue }
        let key = "items/\(destID)/\(name)"
        let body = try Data(contentsOf: url)
        if remoteKeys.contains(key) {
            let got = try await store.get(key)
            if Digests.sha256Hex(got.body) != Digests.sha256Hex(body) { throw MigrationError.conflict(key) }
            continue
        }
        try await putNew(store, key: key, body: body)
        remoteKeys.insert(key)
    }
    let jsonKey = "items/\(destID)/item.json"
    let body = editedItem(item, destID: destID, state: state)
    if remoteKeys.contains(jsonKey) {
        let got = try await store.get(jsonKey)
        if Digests.sha256Hex(got.body) != Digests.sha256Hex(body) {
            throw MigrationError.conflict(jsonKey)
        }
        return
    }
    try await putNew(store, key: jsonKey, body: body)
    remoteKeys.insert(jsonKey)
}

private func editedItem(_ item: SourceItem, destID: String, state: MigrationMerge) -> Data {
    var map = state.collections
    map[item.id] = destID
    var data = JSONText.replacingIDs(item.json, map)
    if let tags = item.object["tags"] as? [String] {
        let rewritten = tags.map { state.tagCanon[foldName($0)] ?? $0 }
        if rewritten != tags, let updated = JSONText.replacingStringArray(in: data, key: "tags", values: rewritten) {
            data = updated
        }
    }
    if let auto = item.object["autoTags"] as? [String] {
        let rewritten = auto.map { state.tagCanon[foldName($0)] ?? $0 }
        if rewritten != auto, let updated = JSONText.replacingStringArray(in: data, key: "autoTags", values: rewritten) {
            data = updated
        }
    }
    return data
}

private func uploadSide(_ state: inout MigrationMerge, source: SourceLibrary, store: any ObjectStore, remoteKeys: inout Set<String>) async throws {
    let map = itemMap(state).merging(state.collections) { item, _ in item }
    let dropped = Set(state.items.filter { $0.value.failure != nil }.keys)
    for member in source.members {
        if remoteKeys.contains(member.key) {
            record(&state, key: member.key, reason: "member already in the library")
            continue
        }
        try await putNew(store, key: member.key, body: member.data)
        remoteKeys.insert(member.key)
    }
    for note in source.notes {
        if remoteKeys.contains(note.key) {
            record(&state, key: note.key, reason: "note already in the library")
            continue
        }
        if let object = JSONText.object(note.data), let itemID = object["itemId"] as? String, dropped.contains(itemID) {
            record(&state, key: note.key, reason: "note item was not merged")
            continue
        }
        let body = JSONText.replacingIDs(note.data, map)
        try await putNew(store, key: note.key, body: body)
        remoteKeys.insert(note.key)
    }
    for canvas in source.canvases {
        let destKey = canvasDestKey(canvas.key, collections: state.collections)
        let rewritten = JSONText.replacingIDs(canvas.data, map)
        if !remoteKeys.contains(destKey) {
            let body = JSONText.dropping(ids: dropped, inCanvas: rewritten) ?? rewritten
            try await putNew(store, key: destKey, body: body)
            remoteKeys.insert(destKey)
            continue
        }
        let got = try await store.get(destKey)
        guard let merged = JSONText.spliceCanvas(dest: got.body, source: rewritten, drop: dropped) else { continue }
        _ = try await store.put(destKey, body: merged, contentType: "application/json", ifMatch: got.etag, ifNoneMatch: nil)
        remoteKeys.insert(destKey)
    }
    for extra in source.extras {
        if remoteKeys.contains(extra.key) {
            record(&state, key: extra.key, reason: "already in the library")
            continue
        }
        let body = try Data(contentsOf: extra.url)
        try await putNew(store, key: extra.key, body: body)
        remoteKeys.insert(extra.key)
    }
}

private func canvasDestKey(_ key: String, collections: [String: String]) -> String {
    let name = key.split(separator: "/").last.map(String.init) ?? key
    guard name != "library.json", name != "inbox.json" else { return "canvas/\(name)" }
    let id = name.replacingOccurrences(of: ".json", with: "")
    return "canvas/\(collections[id] ?? id).json"
}

private func record(_ state: inout MigrationMerge, key: String, reason: String) {
    guard !state.skips.contains(where: { $0.key == key && $0.reason == reason }) else { return }
    state.skips.append(MigrationSkip(key: key, reason: reason))
}

private func itemMap(_ state: MigrationMerge) -> [String: String] {
    var map: [String: String] = [:]
    for (sourceID, item) in state.items where item.failure == nil && sourceID != item.dest {
        map[sourceID] = item.dest
    }
    return map
}

private func putNew(_ store: any ObjectStore, key: String, body: Data) async throws {
    do {
        _ = try await store.put(key, body: body, contentType: S3Client.contentType(key), ifMatch: nil, ifNoneMatch: "*")
    } catch let error as S3Error where error == .preconditionFailed {
        let got = try await store.get(key)
        if Digests.sha256Hex(got.body) != Digests.sha256Hex(body) {
            throw MigrationError.conflict(key)
        }
    }
}

private func failureReason(_ error: Error) -> String {
    if let migration = error as? MigrationError, case .conflict(let key) = migration {
        return "destination already has a different \(key)"
    }
    guard let s3 = error as? S3Error else { return "couldn't copy" }
    switch s3 {
    case .notFound: return "not found"
    case .preconditionFailed: return "already changed"
    case .badResponse: return "bad response"
    case .status(let code, _): return "failed (\(code))"
    }
}

private func foldName(_ name: String) -> String {
    name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(with: Locale(identifier: "en_US_POSIX"))
}

private func freshID(avoiding taken: Set<String>) -> String {
    let alphabet = Array("0123456789ABCDEFGHJKMNPQRSTVWXYZ")
    var ms = UInt64(max(0, Date().timeIntervalSince1970) * 1000)
    var chars = [Character](repeating: "0", count: 26)
    repeat {
        for i in stride(from: 9, through: 0, by: -1) {
            chars[i] = alphabet[Int(ms & 31)]
            ms >>= 5
        }
        for i in 10..<26 { chars[i] = alphabet[Int.random(in: 0..<32)] }
        ms = UInt64(max(0, Date().timeIntervalSince1970) * 1000)
    } while taken.contains(String(chars))
    return String(chars)
}

private func fileHash(_ url: URL) -> String? {
    guard let data = try? Data(contentsOf: url) else { return nil }
    return Digests.sha256Hex(data)
}

private func sourceKeys(_ root: URL) -> [String] {
    let resolved = root.resolvingSymlinksInPath().standardizedFileURL
    guard let enumerator = FileManager.default.enumerator(at: resolved, includingPropertiesForKeys: [.isRegularFileKey]) else { return [] }
    var keys: [String] = []
    while let url = enumerator.nextObject() as? URL {
        guard let key = LibraryScanner.relativeKey(of: url, root: resolved), LibraryScanner.shouldSync(key) else { continue }
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), !isDir.boolValue else { continue }
        keys.append(key)
    }
    return keys.sorted()
}

private enum JSONText {
    static func object(_ data: Data) -> [String: Any]? {
        (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    static func data(_ object: Any) throws -> Data {
        try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
    }

    /// Replaces quoted tokens in one pass, so a new id is not replaced again when it is also a map key.
    static func replacingIDs(_ data: Data, _ map: [String: String]) -> Data {
        guard let text = String(data: data, encoding: .utf8) else { return data }
        var out = ""
        out.reserveCapacity(text.count)
        var index = text.startIndex
        while index < text.endIndex {
            guard text[index] == "\"" else {
                out.append(text[index])
                index = text.index(after: index)
                continue
            }
            let start = index
            index = text.index(after: index)
            var token = ""
            var escape = false
            var closed = false
            while index < text.endIndex {
                let char = text[index]
                index = text.index(after: index)
                if escape {
                    token.append(char)
                    escape = false
                    continue
                }
                if char == "\\" {
                    token.append(char)
                    escape = true
                    continue
                }
                if char == "\"" {
                    closed = true
                    break
                }
                token.append(char)
            }
            if closed, let replacement = map[token], replacement != token {
                out.append("\"\(replacement)\"")
            } else {
                out.append(contentsOf: text[start..<index])
            }
        }
        return Data(out.utf8)
    }

    static func replacingStringArray(in data: Data, key: String, values: [String]) -> Data? {
        guard var text = String(data: data, encoding: .utf8), let range = rangeOfValue(in: text, key: key) else { return nil }
        let multiline = text[range].contains("\n")
        text.replaceSubrange(range, with: formatArray(values, multiline: multiline))
        return Data(text.utf8)
    }

    static func dropping(ids: Set<String>, inCanvas data: Data) -> Data? {
        guard !ids.isEmpty, var text = String(data: data, encoding: .utf8), let range = rangeOfValue(in: text, key: "clusters") else { return nil }
        let parts = elements(ofArray: String(text[range]))
        let kept: [String] = parts.compactMap { part in
            guard let object = object(Data(part.utf8)), var items = object["items"] as? [String] else { return part }
            items.removeAll { ids.contains($0) }
            guard var copy = object as [String: Any]? else { return part }
            copy["items"] = items
            guard let encoded = try? JSONSerialization.data(withJSONObject: copy), let raw = String(data: encoded, encoding: .utf8) else { return part }
            return raw
        }
        text.replaceSubrange(range, with: "[\(kept.joined(separator: ","))]")
        return Data(text.utf8)
    }

    /// Inserts source clusters the destination does not already have. Destination bytes outside that array stay put.
    static func spliceCanvas(dest: Data, source: Data, drop: Set<String>) -> Data? {
        guard var destText = String(data: dest, encoding: .utf8),
              let sourceText = String(data: source, encoding: .utf8),
              let destRange = rangeOfValue(in: destText, key: "clusters"),
              let sourceRange = rangeOfValue(in: sourceText, key: "clusters") else { return nil }
        let destIDs = Set(elements(ofArray: String(destText[destRange])).compactMap { clusterID($0) })
        let fresh = elements(ofArray: String(sourceText[sourceRange])).compactMap { part -> String? in
            guard let id = clusterID(part), !destIDs.contains(id) else { return nil }
            guard !drop.isEmpty, let object = object(Data(part.utf8)), var items = object["items"] as? [String] else { return part }
            let filtered = items.filter { !drop.contains($0) }
            if filtered == items { return part }
            items = filtered
            var copy = object
            copy["items"] = items
            guard let encoded = try? JSONSerialization.data(withJSONObject: copy), let raw = String(data: encoded, encoding: .utf8) else { return nil }
            return raw
        }
        guard !fresh.isEmpty else { return nil }
        var array = String(destText[destRange])
        let inner = array.dropFirst().drop(while: { $0.isWhitespace })
        if inner.first == "]" {
            array = "[\(fresh.joined(separator: ","))]"
        } else if let end = array.lastIndex(of: "]") {
            array.insert(contentsOf: "," + fresh.joined(separator: ","), at: end)
        }
        destText.replaceSubrange(destRange, with: array)
        return Data(destText.utf8)
    }

    private static func clusterID(_ text: String) -> String? {
        guard let object = object(Data(text.utf8)) else { return nil }
        return object["id"] as? String
    }

    private static func elements(ofArray text: String) -> [String] {
        guard let open = text.firstIndex(of: "[") else { return [] }
        var index = text.index(after: open)
        var parts: [String] = []
        while index < text.endIndex {
            while index < text.endIndex, text[index].isWhitespace || text[index] == "," {
                index = text.index(after: index)
            }
            if index >= text.endIndex || text[index] == "]" { break }
            let end = skipValue(text, from: index)
            parts.append(String(text[index..<end]))
            index = end
        }
        return parts
    }

    private static func formatArray(_ values: [String], multiline: Bool) -> String {
        let quoted = values.map(quote)
        guard multiline else { return "[\(quoted.joined(separator: ", "))]" }
        if quoted.isEmpty { return "[\n\n  ]" }
        return "[\n\(quoted.map { "    \($0)" }.joined(separator: ",\n"))\n  ]"
    }

    private static func quote(_ value: String) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: [value]),
              var text = String(data: data, encoding: .utf8) else { return "\"\"" }
        if text.hasPrefix("[") { text.removeFirst() }
        if text.hasSuffix("]") { text.removeLast() }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func rangeOfValue(in text: String, key: String) -> Range<String.Index>? {
        let needle = "\"\(key)\""
        var search = text.startIndex
        while let found = text.range(of: needle, range: search..<text.endIndex) {
            var index = found.upperBound
            while index < text.endIndex, text[index].isWhitespace { index = text.index(after: index) }
            guard index < text.endIndex, text[index] == ":" else {
                search = found.upperBound
                continue
            }
            index = text.index(after: index)
            while index < text.endIndex, text[index].isWhitespace { index = text.index(after: index) }
            guard index < text.endIndex else { return nil }
            return index..<skipValue(text, from: index)
        }
        return nil
    }

    private static func skipValue(_ text: String, from start: String.Index) -> String.Index {
        guard start < text.endIndex else { return text.endIndex }
        let opening = text[start]
        guard opening == "[" || opening == "{" else { return text.endIndex }
        let closing: Character = opening == "[" ? "]" : "}"
        var depth = 0
        var index = start
        var inString = false
        var escape = false
        while index < text.endIndex {
            let char = text[index]
            if inString {
                if escape { escape = false }
                else if char == "\\" { escape = true }
                else if char == "\"" { inString = false }
            } else if char == "\"" {
                inString = true
            } else if char == opening {
                depth += 1
            } else if char == closing {
                depth -= 1
                if depth == 0 { return text.index(after: index) }
            }
            index = text.index(after: index)
        }
        return text.endIndex
    }
}
