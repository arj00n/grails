import Foundation

/// How a sync tells you it brought items in. More than three shows a determinate bar, then one summary. A short sync stays a quiet count.
public enum SyncFeedback: Equatable, Sendable {
    case silent
    case subtle(String)
    case progress(done: Int, total: Int)
    case summary(String)

    public static let bulkCount = 3

    public static func showsProgress(total: Int) -> Bool { total > bulkCount }

    public static let preparing = "Preparing…"

    /// `estimate` is a rounded phrase such as "about 3 min" or "less than a minute".
    public static func progressLine(done: Int, total: Int, estimate: String? = nil) -> String {
        guard let estimate else { return "\(done) of \(total) items" }
        return "\(done) of \(total) items · \(estimate) left"
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

    public static let manifestSaved = "manifest saved"
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

public struct SyncTransferProgress: Equatable, Sendable {
    public var done: Int
    public var total: Int
    public var bytesDone: Int64
    public var bytesTotal: Int64

    public init(done: Int, total: Int, bytesDone: Int64, bytesTotal: Int64) {
        self.done = done
        self.total = total
        self.bytesDone = bytesDone
        self.bytesTotal = bytesTotal
    }

    public static let idle = SyncTransferProgress(done: 0, total: 0, bytesDone: 0, bytesTotal: 0)
}

/// How many files to fetch at once. Roster files stay outside the pool.
public enum SyncDownload {
    public static let width = 6

    public static func isSerial(_ key: String) -> Bool {
        key == "library.json" || key.hasPrefix(".members/")
    }

    public static func schedule(_ keys: [String]) -> (serial: [String], parallel: [String]) {
        var serial: [String] = []
        var parallel: [String] = []
        for key in keys {
            if isSerial(key) { serial.append(key) } else { parallel.append(key) }
        }
        return (serial, parallel)
    }
}

/// The sync record is written after a batch of files, and again when the pass ends.
public enum SyncManifestFlush {
    public static let fileStride = 20
    public static let interval: TimeInterval = 2

    public static func shouldFlush(pending: Int, elapsed: TimeInterval, force: Bool) -> Bool {
        if pending <= 0 { return false }
        if force { return true }
        return pending >= fileStride || elapsed >= interval
    }
}

/// Smoothed time remaining for a bulk download. The view holds one of these so the average survives redraws.
public struct SyncPace: Equatable, Sendable {
    public static let warmSeconds: TimeInterval = 5
    public static let warmBytes: Int64 = 3_000_000
    public static let alpha = 0.25
    public static let boundarySlack: TimeInterval = 20

    public var began: Date?
    public var rate: Double?
    public var shownMinutes: Int?
    public var lastBytes: Int64

    public init() {
        lastBytes = 0
    }

    public mutating func label(_ progress: SyncTransferProgress, at: Date) -> String {
        if began == nil { began = at }
        let elapsed = at.timeIntervalSince(began ?? at)
        let warm = progress.bytesDone > 0 && (elapsed >= Self.warmSeconds || progress.bytesDone >= Self.warmBytes)
        guard warm else { return SyncFeedback.preparing }
        if progress.bytesDone > lastBytes, elapsed > 0 {
            let aggregate = Double(progress.bytesDone) / elapsed
            if let rate {
                self.rate = rate * (1 - Self.alpha) + aggregate * Self.alpha
            } else {
                self.rate = aggregate
            }
            lastBytes = progress.bytesDone
        }
        guard let rate, rate > 0 else { return SyncFeedback.preparing }
        let seconds = Double(max(Int64(0), progress.bytesTotal - progress.bytesDone)) / rate
        let stable = Self.shownMinutes(previous: shownMinutes, seconds: seconds)
        shownMinutes = stable
        let phrase = stable == 0 ? "less than a minute" : "about \(stable) min"
        return SyncFeedback.progressLine(done: progress.done, total: progress.total, estimate: phrase)
    }

    /// A one-minute change waits until the remaining time is clear of the rounding boundary. A jump of two minutes or more updates immediately.
    public static func shownMinutes(previous: Int?, seconds: TimeInterval) -> Int {
        let raw = bucket(seconds)
        guard let previous else { return raw }
        if raw == previous || abs(raw - previous) >= 2 { return raw }
        let edge = Double(min(previous, raw))
        let boundary: TimeInterval = edge <= 0 ? 60 : (edge + 0.5) * 60
        if abs(seconds - boundary) >= boundarySlack { return raw }
        return previous
    }

    public static func bucket(_ seconds: TimeInterval) -> Int {
        if seconds < 60 { return 0 }
        return max(1, Int((seconds / 60).rounded()))
    }
}

/// A bulk pass reloads the library once, when the pass ends. Reloading on every downloaded file keeps the grid empty and busy.
public enum SyncWatch {
    public static func shouldReload(bulkSync: Bool) -> Bool { !bulkSync }
}

public enum SyncProgressVisibility {
    public static func shown(total: Int, reachable: Bool) -> Bool {
        reachable && total > 0
    }
}
