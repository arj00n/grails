import Foundation

public struct MigrationSkip: Codable, Equatable, Sendable {
    public var key: String
    public var reason: String

    public init(key: String, reason: String) {
        self.key = key
        self.reason = reason
    }
}

public struct MigrationItem: Codable, Equatable, Sendable {
    public var dest: String
    public var duplicate: Bool
    public var failure: String?
    public var done: Bool

    public init(dest: String, duplicate: Bool, failure: String? = nil, done: Bool) {
        self.dest = dest
        self.duplicate = duplicate
        self.failure = failure
        self.done = done
    }
}

/// Decisions for a merge into a library the bucket already has. A later call keeps these instead of deciding again.
public struct MigrationMerge: Codable, Equatable, Sendable {
    public var planned: Bool
    public var collections: [String: String]
    public var createdCollections: [String]
    public var items: [String: MigrationItem]
    /// Lowercased tag name to the spelling kept on the destination.
    public var tagCanon: [String: String]
    public var tagsMerged: Bool
    public var sideMerged: Bool
    public var skips: [MigrationSkip]
    public var rewrites: [MigrationSkip]

    public init(
        planned: Bool = false, collections: [String: String] = [:], createdCollections: [String] = [],
        items: [String: MigrationItem] = [:], tagCanon: [String: String] = [:], tagsMerged: Bool = false,
        sideMerged: Bool = false, skips: [MigrationSkip] = [], rewrites: [MigrationSkip] = []
    ) {
        self.planned = planned
        self.collections = collections
        self.createdCollections = createdCollections
        self.items = items
        self.tagCanon = tagCanon
        self.tagsMerged = tagsMerged
        self.sideMerged = sideMerged
        self.skips = skips
        self.rewrites = rewrites
    }
}

public struct MigrationProgress: Equatable, Sendable {
    public var copied: Int
    public var total: Int
    public var remaining: [String]
    public var merged: Int
    public var duplicates: Int
    public var skips: [MigrationSkip]
    public var failures: [MigrationSkip]
    public var rewrites: [MigrationSkip]

    public init(
        copied: Int, total: Int, remaining: [String], merged: Int = 0, duplicates: Int = 0,
        skips: [MigrationSkip] = [], failures: [MigrationSkip] = [], rewrites: [MigrationSkip] = []
    ) {
        self.copied = copied
        self.total = total
        self.remaining = remaining
        self.merged = merged
        self.duplicates = duplicates
        self.skips = skips
        self.failures = failures
        self.rewrites = rewrites
    }

    public var finished: Bool { remaining.isEmpty }
}

public struct MigrationLedger: Codable, Equatable, Sendable {
    public var digests: [String: String]
    public var merge: MigrationMerge?

    public init(digests: [String: String] = [:], merge: MigrationMerge? = nil) {
        self.digests = digests
        self.merge = merge
    }
}

public enum MigrationError: Error, Equatable {
    case destinationHasNoLibrary
    case conflict(String)
}

public enum LibraryMigration {
    public static let ledgerKey = ".grails-migration.json"

    public static func pending(local: [LocalObject], ledger: MigrationLedger) -> [String] {
        SyncRank.sort(local.filter { ledger.digests[$0.key] != $0.digest }.map(\.key))
    }

    public static func copy(root: URL, store: any ObjectStore, limit: Int = Int.max) async throws -> MigrationProgress {
        if try await hasLibrary(store) {
            return try await merge(root: root, store: store, limit: limit)
        }
        var ledger = try await load(store)
        let todo = pending(local: try LibraryScanner.scan(root: root), ledger: ledger)
        let batch = Array(todo.prefix(max(0, limit)))
        for key in batch {
            let url = root.appendingPathComponent(key)
            let data = try Data(contentsOf: url)
            _ = try await store.put(key, body: data, contentType: S3Client.contentType(key), ifMatch: nil, ifNoneMatch: nil)
            let after = try Data(contentsOf: url)
            if after == data {
                ledger.digests[key] = Digests.sha256Hex(data)
                try await save(ledger, store: store)
            }
        }
        let fresh = try LibraryScanner.scan(root: root)
        let left = pending(local: fresh, ledger: ledger)
        let copied = fresh.filter { ledger.digests[$0.key] == $0.digest }.count
        return MigrationProgress(copied: copied, total: fresh.count, remaining: left)
    }

    static func hasLibrary(_ store: any ObjectStore) async throws -> Bool {
        do {
            _ = try await store.get("library.json")
            return true
        } catch let error as S3Error where error == .notFound {
            return false
        }
    }

    static func load(_ store: any ObjectStore) async throws -> MigrationLedger {
        do {
            let got = try await store.get(ledgerKey)
            return (try? JSONDecoder().decode(MigrationLedger.self, from: got.body)) ?? MigrationLedger()
        } catch let error as S3Error where error == .notFound {
            return MigrationLedger()
        }
    }

    static func save(_ ledger: MigrationLedger, store: any ObjectStore) async throws {
        let body = try JSONEncoder().encode(ledger)
        _ = try await store.put(ledgerKey, body: body, contentType: "application/json", ifMatch: nil, ifNoneMatch: nil)
    }
}
