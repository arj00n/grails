import Foundation

/// A remote object key turned into a file under the library root. Keys that escape the root are refused.
public enum SyncPath {
    public static func url(root: URL, key: String) -> URL? {
        guard !key.isEmpty, !key.hasPrefix("/"), !key.contains("\\"), !key.contains("\0") else { return nil }
        let parts = key.split(separator: "/", omittingEmptySubsequences: false)
        guard !parts.isEmpty, parts.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else { return nil }
        let root = root.standardizedFileURL
        let file = root.appendingPathComponent(key).standardizedFileURL
        let prefix = root.path.hasSuffix("/") ? root.path : root.path + "/"
        guard file.path == root.path || file.path.hasPrefix(prefix) else { return nil }
        return file
    }
}
