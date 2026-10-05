import Foundation

public struct ScanFailure: Sendable, Hashable {
    public var path: String
    public var message: String
}

public struct ScanResult: Sendable {
    public var items: [(item: Item, mtime: Double)] = []
    public var failures: [ScanFailure] = []
}

/// Reads canonical `item.json` files from disk. Never mutates the library.
enum ItemScanner {
    static func itemFolders(in layout: LibraryLayout) -> [URL] {
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: layout.itemsDir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        )) ?? []
        return urls
    }

    static func read(folder: URL) throws -> (item: Item, mtime: Double)? {
        let json = folder.appendingPathComponent("item.json")
        guard let mtime = FileStat.mtime(json) else { return nil }
        let item = try GrailsJSON.decode(Item.self, from: Data(contentsOf: json))
        return (item, mtime)
    }

    /// Parallel read of every item. A corrupt file (for example one caught mid-sync) is reported, not fatal.
    static func scanAll(_ layout: LibraryLayout) async -> ScanResult {
        let folders = itemFolders(in: layout)
        return await scan(folders: folders)
    }

    static func scan(folders: [URL]) async -> ScanResult {
        let chunkSize = 500
        let chunks = stride(from: 0, to: folders.count, by: chunkSize).map { Array(folders[$0..<min($0 + chunkSize, folders.count)]) }
        return await withTaskGroup(of: ScanResult.self) { group in
            for chunk in chunks {
                group.addTask {
                    var r = ScanResult()
                    for folder in chunk {
                        do {
                            if let entry = try read(folder: folder) { r.items.append(entry) }
                        } catch {
                            r.failures.append(ScanFailure(path: folder.path, message: "\(error)"))
                        }
                    }
                    return r
                }
            }
            var all = ScanResult()
            for await r in group {
                all.items.append(contentsOf: r.items)
                all.failures.append(contentsOf: r.failures)
            }
            return all
        }
    }
}
