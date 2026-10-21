import Foundation

public struct WorkspaceEntry: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var path: String
    public var name: String
    public var color: String?

    public init(id: String? = nil, path: String, name: String, color: String? = nil) {
        self.id = id ?? path
        self.path = path
        self.name = name
        self.color = color
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        path = try c.decode(String.self, forKey: .path)
        name = try c.decode(String.self, forKey: .name)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? path
        color = try c.decodeIfPresent(String.self, forKey: .color)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(path, forKey: .path)
        try c.encode(name, forKey: .name)
        try c.encodeIfPresent(color, forKey: .color)
    }

    private enum CodingKeys: String, CodingKey { case id, path, name, color }
}

public enum WorkspaceList {
    public static func standardize(_ path: String, home: String, resolve: (String) -> String = { $0 }) -> String {
        let expanded: String
        if path == "~" {
            expanded = home
        } else if path.hasPrefix("~/") {
            expanded = home + String(path.dropFirst(1))
        } else {
            expanded = path
        }
        var lexical = URL(fileURLWithPath: resolve(expanded)).standardizedFileURL.path
        if lexical.count > 1, lexical.hasSuffix("/") { lexical.removeLast() }
        return lexical
    }

    public static func isAvailable(
        path: String, home: String, resolve: (String) -> String = { $0 }, fileExists: (String) -> Bool
    ) -> Bool {
        fileExists(standardize(path, home: home, resolve: resolve) + "/library.json")
    }

    public static func remember(
        _ list: [WorkspaceEntry], id: String, path: String, name: String, home: String, resolve: (String) -> String = { $0 }
    ) -> [WorkspaceEntry] {
        let stored = standardize(path, home: home, resolve: resolve)
        var list = reconcile(list, openID: id, openPath: stored, home: home, resolve: resolve)
        if let i = list.firstIndex(where: {
            $0.id == id || standardize($0.path, home: home, resolve: resolve) == stored
        }) {
            list[i].id = id
            list[i].path = stored
            list[i].name = name
            return list
        }
        list.append(WorkspaceEntry(id: id, path: stored, name: name))
        return list
    }

    public static func reconcile(
        _ list: [WorkspaceEntry], openID: String? = nil, openPath: String? = nil, home: String,
        resolve: (String) -> String = { $0 }
    ) -> [WorkspaceEntry] {
        guard !list.isEmpty else { return [] }
        var parent = Array(list.indices)
        func find(_ start: Int) -> Int {
            var i = start
            while parent[i] != i {
                parent[i] = parent[parent[i]]
                i = parent[i]
            }
            return i
        }
        func unite(_ a: Int, _ b: Int) {
            let ra = find(a), rb = find(b)
            if ra != rb { parent[rb] = ra }
        }
        var byID: [String: Int] = [:]
        var byPath: [String: Int] = [:]
        for (index, entry) in list.enumerated() {
            let path = standardize(entry.path, home: home, resolve: resolve)
            if let previous = byPath[path] { unite(previous, index) }
            byPath[path] = index
            guard isLibraryID(entry.id, path: entry.path, home: home, resolve: resolve) else { continue }
            if let previous = byID[entry.id] { unite(previous, index) }
            byID[entry.id] = index
        }
        var groups: [Int: [Int]] = [:]
        for index in list.indices {
            groups[find(index), default: []].append(index)
        }
        let open = openPath.map { standardize($0, home: home, resolve: resolve) }
        var chosen: [(slot: Int, entry: WorkspaceEntry)] = []
        for indices in groups.values {
            let sorted = indices.sorted()
            let pathHits = sorted.filter { index in
                guard let open else { return false }
                return standardize(list[index].path, home: home, resolve: resolve) == open
            }
            let idHits = sorted.filter { openID != nil && list[$0].id == openID }
            let pick = pathHits.first ?? idHits.first ?? sorted[0]
            var entry = list[pick]
            entry.path = standardize(entry.path, home: home, resolve: resolve)
            if entry.color == nil {
                entry.color = sorted.reversed().compactMap { list[$0].color }.first
            }
            chosen.append((sorted[0], entry))
        }
        return chosen.sorted { $0.slot < $1.slot }.map(\.entry)
    }

    public static func remove(
        _ list: [WorkspaceEntry], id: String, home: String, resolve: (String) -> String = { $0 }
    ) -> [WorkspaceEntry] {
        let paths = Set(list.filter { $0.id == id }.map { standardize($0.path, home: home, resolve: resolve) })
        return list.filter { entry in
            entry.id != id && !paths.contains(standardize(entry.path, home: home, resolve: resolve))
        }
    }

    public static func setColor(_ list: [WorkspaceEntry], hex: String?, id: String) -> [WorkspaceEntry] {
        list.map { entry in
            guard entry.id == id else { return entry }
            var copy = entry
            copy.color = hex
            return copy
        }
    }

    private static func isLibraryID(_ id: String, path: String, home: String, resolve: (String) -> String) -> Bool {
        guard !id.isEmpty, id != path else { return false }
        let folder = standardize(path, home: home, resolve: resolve)
        if standardize(id, home: home, resolve: resolve) == folder { return false }
        if id.hasPrefix("/") || id.hasPrefix("~") { return false }
        return true
    }
}
