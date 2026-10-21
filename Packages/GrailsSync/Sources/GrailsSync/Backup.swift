import Foundation

public struct BackupConfig: Codable, Equatable, Sendable {
    public var endpoint: URL
    public var bucket: String
    public var region: String

    public init(endpoint: URL, bucket: String, region: String) {
        self.endpoint = endpoint
        self.bucket = bucket
        self.region = region
    }
}

public enum SnapshotDay {
    public static func string(from date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year!, parts.month!, parts.day!)
    }
}

public enum SnapshotSchedule {
    /// Nightly snapshots open at 03:00 UTC. A day is due once.
    public static func isDue(lastRunDay: String?, now: Date) -> Bool {
        windowDay(now) != lastRunDay
    }

    public static func windowDay(_ now: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let hour = calendar.component(.hour, from: now)
        let day = hour < 3 ? calendar.date(byAdding: .day, value: -1, to: now)! : now
        return SnapshotDay.string(from: day)
    }
}

public struct SnapshotReport: Equatable, Sendable {
    public var added: [String]
    public var skipped: [String]

    public init(added: [String], skipped: [String]) {
        self.added = added
        self.skipped = skipped
    }
}

public enum LibrarySnapshot {
    public static func prefix(_ day: String) -> String { "snapshots/\(day)/" }

    static func liveKey(_ snapshotKey: String) -> String? {
        let parts = snapshotKey.split(separator: "/", maxSplits: 2, omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 3, parts[0] == "snapshots" else { return nil }
        return parts[2]
    }

    /// Copies a live object unless the newest snapshot of that same key already has this etag.
    /// The destination has no delete operation. Matching bytes under a different key are still copied.
    public static func run(live: [ObjectHead], read: @Sendable (String) async throws -> Data, destination: any SnapshotDestination, existing: [ObjectHead], day: String) async throws -> SnapshotReport {
        var newest: [String: (day: String, etag: String)] = [:]
        for head in existing {
            guard let liveKey = liveKey(head.key), let snapDay = dayOf(head.key) else { continue }
            if let current = newest[liveKey], current.day >= snapDay { continue }
            newest[liveKey] = (snapDay, head.etag)
        }
        var added: [String] = []
        var skipped: [String] = []
        for head in live.sorted(by: { $0.key < $1.key }) where !head.key.hasPrefix("trash/") && !head.key.hasPrefix("invites/") && head.key != MoveNotice.key {
            if newest[head.key]?.etag == head.etag {
                skipped.append(head.key)
                continue
            }
            let body = try await read(head.key)
            let destinationKey = prefix(day) + head.key
            try await destination.put(destinationKey, body: body)
            added.append(destinationKey)
        }
        return SnapshotReport(added: added, skipped: skipped)
    }

    public static func restoreItem(key: String, day: String?, snapshot: [ObjectHead], read: (String) async throws -> Data, write: (String, Data) async throws -> Void) async throws {
        let match: String
        if let day {
            match = prefix(day) + key
        } else {
            let candidates = snapshot.map(\.key).filter { liveKey($0) == key }
            guard let latest = candidates.max() else { throw S3Error.notFound }
            match = latest
        }
        let body = try await read(match)
        try await write(key, body)
    }

    /// The library as of `day`: the newest snapshot of each object on or before that day.
    /// A day's prefix only holds files that changed, so unchanged files live under earlier days.
    public static func restoreDay(_ day: String, snapshot: [ObjectHead], read: @Sendable (String) async throws -> Data, write: @Sendable (String, Data) async throws -> Void) async throws -> [String] {
        var best: [String: (day: String, key: String)] = [:]
        for head in snapshot {
            guard let live = liveKey(head.key), let snapDay = dayOf(head.key), snapDay <= day, !live.isEmpty else { continue }
            if let current = best[live], current.day >= snapDay { continue }
            best[live] = (snapDay, head.key)
        }
        var restored: [String] = []
        for live in best.keys.sorted() {
            let body = try await read(best[live]!.key)
            try await write(live, body)
            restored.append(live)
        }
        return restored
    }

    static func dayOf(_ snapshotKey: String) -> String? {
        let parts = snapshotKey.split(separator: "/", maxSplits: 2, omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 3, parts[0] == "snapshots", parts[1].count == 10 else { return nil }
        return parts[1]
    }
}

public struct SpringPlan: Equatable, Sendable {
    public var largest: [ObjectHead]
    public var trashKeys: [String]

    public init(largest: [ObjectHead], trashKeys: [String]) {
        self.largest = largest
        self.trashKeys = trashKeys
    }
}

public enum SpringCleaning {
    public static func plan(objects: [ObjectHead], limit: Int = 15) -> SpringPlan {
        let trash = objects.map(\.key).filter { $0.hasPrefix("trash/") }.sorted()
        let largest = objects
            .filter { !$0.key.hasPrefix("trash/") && !$0.key.hasPrefix("invites/") && !SyncRank.thumbnail($0.key) && !$0.key.hasSuffix(".json") }
            .sorted { $0.size == $1.size ? $0.key < $1.key : $0.size > $1.size }
        return SpringPlan(largest: Array(largest.prefix(limit)), trashKeys: trash)
    }
}
