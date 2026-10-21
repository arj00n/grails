import Foundation

/// How a sync tells you it brought items in. More than three shows a determinate bar, then one summary. A short sync stays a quiet count.
public enum SyncFeedback: Equatable, Sendable {
    case silent
    case subtle(String)
    case progress(done: Int, total: Int)
    case summary(String)

    public static let bulkCount = 3

    public static func showsProgress(total: Int) -> Bool { total > bulkCount }

    public static func progressLine(done: Int, total: Int) -> String {
        "Syncing \(done) of \(total) items"
    }

    public static func arrival(count: Int) -> SyncFeedback {
        if count <= 0 { return .silent }
        if count <= bulkCount {
            return .subtle(count == 1 ? "1 item" : "\(count) items")
        }
        return .summary("Synced \(count) items")
    }
}

public enum SyncPassLog {
    public static func started(downloads: Int, uploads: Int) -> String {
        "pass started downloads=\(downloads) uploads=\(uploads)"
    }

    public static func progress(done: Int, total: Int) -> String {
        "progress done=\(done) total=\(total)"
    }
}

public enum SyncItems {
    /// `items/<id>/…` is one creative, however many files it has.
    public static func id(in key: String) -> String? {
        let parts = key.split(separator: "/").map(String.init)
        guard parts.count >= 2, parts[0] == "items", !parts[1].isEmpty, !parts[1].hasPrefix(".") else { return nil }
        return parts[1]
    }

    public static func ids(in keys: [String]) -> [String] {
        var seen = Set<String>()
        var order: [String] = []
        for key in keys {
            guard let id = id(in: key), seen.insert(id).inserted else { continue }
            order.append(id)
        }
        return order
    }
}
