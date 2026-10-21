import Foundation

public struct LocalObject: Equatable, Sendable {
    public var key: String
    public var bytes: Int64
    public var digest: String

    public init(key: String, bytes: Int64, digest: String) {
        self.key = key
        self.bytes = bytes
        self.digest = digest
    }
}

public struct ManifestEntry: Codable, Equatable, Sendable {
    public var etag: String
    public var digest: String
    public var size: Int64

    public init(etag: String, digest: String, size: Int64) {
        self.etag = etag
        self.digest = digest
        self.size = size
    }
}

public struct UploadEvent: Codable, Equatable, Sendable {
    public var at: TimeInterval
    public var bytes: Int64

    public init(at: TimeInterval, bytes: Int64) {
        self.at = at
        self.bytes = bytes
    }
}

public struct SyncManifest: Codable, Equatable, Sendable {
    public var entries: [String: ManifestEntry]
    public var usageBytes: Int64
    public var uploadEvents: [UploadEvent]
    public var pinnedOwnerKey: String?
    public var trustedCanonical: String?
    public var trustedSignature: String?
    public var trustedSigner: String?
    public var lastSnapshotDay: String?
    /// Nil until the first pass after an upgrade. Then the keys this Mac already had, plus keys later published on a signed roster.
    public var signingDeviceKeys: [String: String]?
    /// Cloudflare token ids this Mac created. A revoke marker for any other id is left for the Mac that minted it.
    public var mintedTokenIDs: [String]?

    public init(entries: [String: ManifestEntry] = [:], usageBytes: Int64 = 0, uploadEvents: [UploadEvent] = [], pinnedOwnerKey: String? = nil, trustedCanonical: String? = nil, trustedSignature: String? = nil, trustedSigner: String? = nil, lastSnapshotDay: String? = nil, signingDeviceKeys: [String: String]? = nil, mintedTokenIDs: [String]? = nil) {
        self.entries = entries
        self.usageBytes = usageBytes
        self.uploadEvents = uploadEvents
        self.pinnedOwnerKey = pinnedOwnerKey
        self.trustedCanonical = trustedCanonical
        self.trustedSignature = trustedSignature
        self.trustedSigner = trustedSigner
        self.lastSnapshotDay = lastSnapshotDay
        self.signingDeviceKeys = signingDeviceKeys
        self.mintedTokenIDs = mintedTokenIDs
    }

    public var trusted: TrustedTeam? {
        guard let trustedCanonical, let trustedSignature, let trustedSigner, let pinnedOwnerKey,
              let signed = Optional(SignedTeam(canonical: trustedCanonical, signature: trustedSignature, signerPublicKey: trustedSigner)),
              let body = TeamDocument.parse(trustedCanonical) else { return nil }
        return TrustedTeam(pinnedOwnerKey: pinnedOwnerKey, body: body, signed: signed)
    }

    public mutating func store(trusted: TrustedTeam?) {
        guard let trusted else { return }
        pinnedOwnerKey = trusted.pinnedOwnerKey
        trustedCanonical = trusted.signed.canonical
        trustedSignature = trusted.signed.signature
        trustedSigner = trusted.signed.signerPublicKey
    }

    /// Records the owner key from an invite before the first roster is accepted. Does not clear a key already stored.
    public mutating func pinOwner(_ key: String) {
        guard !key.isEmpty else { return }
        pinnedOwnerKey = key
        if signingDeviceKeys == nil { signingDeviceKeys = [:] }
    }

    public mutating func noteMinted(_ id: String) {
        guard !id.isEmpty else { return }
        var ids = mintedTokenIDs ?? []
        if !ids.contains(id) { ids.append(id) }
        mintedTokenIDs = ids
    }

    /// Older builds stored `W/"<hash>` (the trailing quote trimmed, the inner one kept). Listings come back as `"<hash>"`.
    public mutating func canonicalizeETags() {
        for (key, entry) in entries {
            let etag = ETags.canonical(entry.etag)
            if etag != entry.etag {
                entries[key] = ManifestEntry(etag: etag, digest: entry.digest, size: entry.size)
            }
        }
    }
}

/// The sync cursor lives in Application Support, named by the library id, and a copy stays beside the library.
/// A rebuild does not get a new cursor: the path is not the build, the bundle, or the container.
public enum SyncCursor {
    public static func load(cursor: URL, libraryCopy: URL) -> SyncManifest {
        let fromCursor = read(cursor)
        let fromLibrary = read(libraryCopy)
        var chosen: SyncManifest
        switch (fromCursor, fromLibrary) {
        case let (cursorManifest?, libraryManifest?):
            chosen = cursorManifest.entries.count >= libraryManifest.entries.count ? cursorManifest : libraryManifest
        case let (cursorManifest?, nil):
            chosen = cursorManifest
        case let (nil, libraryManifest?):
            chosen = libraryManifest
        case (nil, nil):
            chosen = SyncManifest()
        }
        chosen.canonicalizeETags()
        return chosen
    }

    public static func read(_ url: URL) -> SyncManifest? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(SyncManifest.self, from: data)
    }

    public static func save(_ manifest: SyncManifest, cursor: URL, libraryCopy: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(manifest)
        try FileManager.default.createDirectory(at: cursor.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: cursor, options: .atomic)
        try data.write(to: libraryCopy, options: .atomic)
    }
}

public struct PlannedUpload: Equatable, Sendable {
    public var key: String
    public var ifMatch: String?
    public var ifNoneMatch: String?
    public var bytes: Int64

    public init(key: String, ifMatch: String?, ifNoneMatch: String?, bytes: Int64) {
        self.key = key
        self.ifMatch = ifMatch
        self.ifNoneMatch = ifNoneMatch
        self.bytes = bytes
    }
}

public struct SyncPlan: Equatable, Sendable {
    public var downloads: [String]
    public var uploads: [PlannedUpload]
    public var trashes: [String]
    public var conflicts: [String]
    public var paused: [String]
    public var tooLarge: [String]
    public var rateLimited: [String]
    public var localDeletes: [String]

    public init(downloads: [String] = [], uploads: [PlannedUpload] = [], trashes: [String] = [], conflicts: [String] = [], paused: [String] = [], tooLarge: [String] = [], rateLimited: [String] = [], localDeletes: [String] = []) {
        self.downloads = downloads
        self.uploads = uploads
        self.trashes = trashes
        self.conflicts = conflicts
        self.paused = paused
        self.tooLarge = tooLarge
        self.rateLimited = rateLimited
        self.localDeletes = localDeletes
    }
}

public enum SyncRank {
    public static func thumbnail(_ key: String) -> Bool { key.hasSuffix("/thumb.jpg") || key == "thumb.jpg" }

    public static func sort(_ keys: [String]) -> [String] {
        keys.sorted { lhs, rhs in
            let left = thumbnail(lhs) ? 0 : 1
            let right = thumbnail(rhs) ? 0 : 1
            if left != right { return left < right }
            return lhs < rhs
        }
    }
}

public enum UploadMeter {
    public static let window: TimeInterval = 60

    public static func used(_ events: [UploadEvent], at: Date, window: TimeInterval = window) -> Int64 {
        let cutoff = at.timeIntervalSince1970 - window
        return events.filter { $0.at >= cutoff }.reduce(0) { $0 + $1.bytes }
    }

    public static func pruned(_ events: [UploadEvent], at: Date, window: TimeInterval = window) -> [UploadEvent] {
        let cutoff = at.timeIntervalSince1970 - window
        return events.filter { $0.at >= cutoff }
    }
}

public enum Capacity {
    public enum Level: Equatable, Sendable { case ok, warning, full }

    public static func level(used: Int64, cap: Int64) -> Level {
        guard cap > 0 else { return .full }
        if used >= cap { return .full }
        if used * 10 >= cap * 8 { return .warning }
        return .ok
    }
}

public enum StorageNotice: Equatable, Sendable {
    case none
    case warning(used: Int64, cap: Int64)
    case full(used: Int64, cap: Int64)
}

public enum StoragePolicy {
    public static func notice(used: Int64, cap: Int64, role: LibraryRole) -> StorageNotice {
        switch Capacity.level(used: used, cap: cap) {
        case .ok: return .none
        case .warning: return role == .member ? .none : .warning(used: used, cap: cap)
        case .full: return .full(used: used, cap: cap)
        }
    }
}

public struct UpdateNotice: Equatable, Sendable {
    public var minAppVersion: String
    public var appVersion: String
    public var title: String { "Update Grails" }

    public init(minAppVersion: String, appVersion: String) {
        self.minAppVersion = minAppVersion
        self.appVersion = appVersion
    }
}

public enum AppVersion {
    public static func compare(_ lhs: String, _ rhs: String) -> ComparisonResult {
        let left = parts(lhs)
        let right = parts(rhs)
        let count = max(left.count, right.count)
        for index in 0..<count {
            let a = index < left.count ? left[index] : 0
            let b = index < right.count ? right[index] : 0
            if a < b { return .orderedAscending }
            if a > b { return .orderedDescending }
        }
        return .orderedSame
    }

    public static func allowsSync(app: String, minimum: String?) -> Bool {
        guard let minimum, !minimum.isEmpty else { return true }
        return compare(app, minimum) != .orderedAscending
    }

    private static func parts(_ value: String) -> [Int] {
        value.split(separator: ".").map { Int($0) ?? 0 }
    }
}

public enum SyncStop: Equatable, Sendable {
    case revoked
}

public struct SyncReport: Equatable, Sendable {
    public var downloaded: [String]
    public var uploaded: [String]
    public var trashed: [String]
    public var conflicts: [String]
    public var paused: [String]
    public var tooLarge: [String]
    public var rateLimited: [String]
    public var usageBytes: Int64
    public var capBytes: Int64
    public var blocked: UpdateNotice?
    public var moved: MoveNotice?
    public var stopped: SyncStop?

    public init(downloaded: [String] = [], uploaded: [String] = [], trashed: [String] = [], conflicts: [String] = [], paused: [String] = [], tooLarge: [String] = [], rateLimited: [String] = [], usageBytes: Int64 = 0, capBytes: Int64 = 0, blocked: UpdateNotice? = nil, moved: MoveNotice? = nil, stopped: SyncStop? = nil) {
        self.downloaded = downloaded
        self.uploaded = uploaded
        self.trashed = trashed
        self.conflicts = conflicts
        self.paused = paused
        self.tooLarge = tooLarge
        self.rateLimited = rateLimited
        self.usageBytes = usageBytes
        self.capBytes = capBytes
        self.blocked = blocked
        self.moved = moved
        self.stopped = stopped
    }
}

public enum SyncTiming {
    public static let poll: Duration = .seconds(15)
    /// The poll while the app is in the background: nobody is looking, and local edits still nudge a pass straight away. Coming
    /// back to the app nudges one too.
    public static let backgroundPoll: Duration = .seconds(60)
    /// How late a poll may wake, so the system can coalesce it with other work instead of waking the CPU just for it.
    public static let tolerance: Duration = .seconds(5)
    public static func pause(appActive: Bool) -> Duration { appActive ? poll : backgroundPoll }
    /// Polls trust file stamps. This often, a pass re-reads and re-hashes every file anyway, in case a stamp lied.
    public static let fullScan: TimeInterval = 60 * 60
}

public protocol ObjectMerger: Sendable {
    func merge(key: String, local: Data, remote: Data) -> Data
}

public struct ClosureMerger: ObjectMerger, Sendable {
    public var mergeBody: @Sendable (String, Data, Data) -> Data
    public init(mergeBody: @escaping @Sendable (String, Data, Data) -> Data) { self.mergeBody = mergeBody }
    public func merge(key: String, local: Data, remote: Data) -> Data { mergeBody(key, local, remote) }
}

/// What a scan remembers about a file between polls. Size, content date, and attribute date (ctime) together change on any write or atomic replace.
public struct FileStamp: Equatable, Sendable {
    public var size: Int64
    public var modified: TimeInterval
    public var changed: TimeInterval

    public init(size: Int64, modified: TimeInterval, changed: TimeInterval) {
        self.size = size
        self.modified = modified
        self.changed = changed
    }
}

/// Digests from earlier scans, keyed by library key. A file whose stamp still matches is not read again.
public struct ScanCache: Sendable {
    struct Entry: Sendable {
        var stamp: FileStamp
        var digest: String
        /// A write inside the same timestamp tick as the hash would leave the stamp unchanged, so a file this fresh is hashed again next scan.
        var settled: Bool
    }

    /// A stamp newer than this when hashed is not trusted yet. Covers 1–2 s timestamp filesystems (FAT, SMB, some sync-client mounts).
    public static let settleWindow: TimeInterval = 2

    var entries: [String: Entry] = [:]
    /// Keys the last scan read and hashed. Tests and logs only.
    public private(set) var lastHashed: [String] = []

    public init() {}

    public var isEmpty: Bool { entries.isEmpty }

    mutating func digest(for key: String, stamp: FileStamp, now: Date, rehash: Bool, read: () throws -> Data) throws -> (bytes: Int64, digest: String) {
        if !rehash, let entry = entries[key], entry.settled, entry.stamp == stamp {
            return (stamp.size, entry.digest)
        }
        let data = try read()
        let digest = Digests.sha256Hex(data)
        let settled = now.timeIntervalSince1970 - max(stamp.modified, stamp.changed) > Self.settleWindow
        entries[key] = Entry(stamp: stamp, digest: digest, settled: settled && Int64(data.count) == stamp.size)
        lastHashed.append(key)
        return (Int64(data.count), digest)
    }

    mutating func begin() { lastHashed = [] }

    mutating func keep(only keys: Set<String>) {
        entries = entries.filter { keys.contains($0.key) }
    }
}

public enum LibraryScanner {
    private static let stampKeys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey, .attributeModificationDateKey, .creationDateKey]

    /// Hashes every file. Callers that scan repeatedly pass a `ScanCache` instead.
    public static func scan(root: URL) throws -> [LocalObject] {
        var cache = ScanCache()
        return try scan(root: root, cache: &cache)
    }

    /// Reads and hashes only files whose stamp changed since the cache saw them. `rehash` ignores the cache (the safety-net full scan).
    /// Files that disappeared drop out of the result and the cache, so the planner still sees deletes.
    public static func scan(root: URL, cache: inout ScanCache, rehash: Bool = false, now: Date = Date()) throws -> [LocalObject] {
        let fm = FileManager.default
        let resolvedRoot = root.resolvingSymlinksInPath().standardizedFileURL
        cache.begin()
        guard let enumerator = fm.enumerator(at: resolvedRoot, includingPropertiesForKeys: stampKeys) else {
            cache.keep(only: [])
            return []
        }
        var out: [LocalObject] = []
        while let url = enumerator.nextObject() as? URL {
            guard let relative = relativeKey(of: url, root: resolvedRoot), shouldSync(relative) else { continue }
            let values = try? url.resourceValues(forKeys: Set(stampKeys))
            guard values?.isRegularFile == true else { continue }
            let stamp = FileStamp(
                size: Int64(values?.fileSize ?? -1),
                modified: values?.contentModificationDate?.timeIntervalSince1970 ?? 0,
                // Linux Foundation leaves the attribute date empty. There the creation date follows the inode change time.
                changed: values?.attributeModificationDate?.timeIntervalSince1970 ?? values?.creationDate?.timeIntervalSince1970 ?? 0
            )
            let hashed = try cache.digest(for: relative, stamp: stamp, now: now, rehash: rehash || values?.fileSize == nil) {
                try Data(contentsOf: url, options: .mappedIfSafe)
            }
            out.append(LocalObject(key: relative, bytes: hashed.bytes, digest: hashed.digest))
        }
        cache.keep(only: Set(out.map(\.key)))
        return out.sorted { $0.key < $1.key }
    }

    public static func shouldSync(_ key: String) -> Bool {
        if key == ".grails-sync.json" || key == ".grails-backup.json" || key == MoveNotice.key { return false }
        if key.contains(".tmp-") || key.hasSuffix(".DS_Store") { return false }
        if key.contains(" (") { return false }
        let parts = key.split(separator: "/").map(String.init)
        if parts.contains(where: { $0.hasPrefix(".") && $0 != ".members" }) { return false }
        if key.hasPrefix("trash/") || key.hasPrefix("invites/") { return false }
        return true
    }

    /// `/var` is `/private/var` on macOS. The enumerator returns the resolved path while `root` may still be the symlink, and a string strip then glues `private` onto the key.
    static func relativeKey(of url: URL, root: URL) -> String? {
        let rootParts = resolvedComponents(root)
        let fileParts = resolvedComponents(url)
        guard fileParts.starts(with: rootParts), fileParts.count > rootParts.count else { return nil }
        return fileParts.dropFirst(rootParts.count).joined(separator: "/")
    }

    private static func resolvedComponents(_ url: URL) -> [String] {
        url.resolvingSymlinksInPath().standardizedFileURL.pathComponents
    }
}

public enum SyncPlanner {
    public static func plan(local: [LocalObject], remote: [ObjectHead], manifest: [String: ManifestEntry], capBytes: Int64, maxFileBytes: Int64, rateRemaining: Int64) -> SyncPlan {
        let localMap = Dictionary(uniqueKeysWithValues: local.map { ($0.key, $0) })
        let remoteMap = Dictionary(uniqueKeysWithValues: remote.filter { !excluded($0.key) }.map { ($0.key, $0) })
        var downloads: [String] = []
        var candidates: [PlannedUpload] = []
        var trashes: [String] = []
        var conflicts: [String] = []
        var localDeletes: [String] = []
        let keys = Set(localMap.keys).union(remoteMap.keys).union(manifest.keys.filter { !excluded($0) })
        for key in keys.sorted() {
            if key.hasPrefix(".members/"), let head = remoteMap[key] {
                guard let file = localMap[key] else {
                    downloads.append(key)
                    continue
                }
                let entry = manifest[key]
                let localChanged = entry.map { file.digest != $0.digest } ?? true
                let remoteChanged = entry.map { !ETags.same(head.etag, $0.etag) } ?? true
                if localChanged && remoteChanged {
                    conflicts.append(key)
                } else if localChanged {
                    candidates.append(PlannedUpload(key: key, ifMatch: entry?.etag, ifNoneMatch: entry == nil ? "*" : nil, bytes: file.bytes))
                } else if remoteChanged {
                    downloads.append(key)
                }
                continue
            }
            let file = localMap[key]
            let head = remoteMap[key]
            let entry = manifest[key]
            switch (file, head, entry) {
            case (nil, let head?, let entry?) where ETags.same(head.etag, entry.etag):
                trashes.append(key)
            case (nil, _?, _):
                downloads.append(key)
            case (_, nil, let entry?) where file?.digest == entry.digest:
                localDeletes.append(key)
            case (let file?, nil, _):
                candidates.append(PlannedUpload(key: key, ifMatch: nil, ifNoneMatch: "*", bytes: file.bytes))
            case (let file?, let head?, nil):
                conflicts.append(key)
                _ = file
                _ = head
            case (let file?, let head?, let entry?):
                let localChanged = file.digest != entry.digest
                let remoteChanged = !ETags.same(head.etag, entry.etag)
                if localChanged && remoteChanged { conflicts.append(key) }
                else if localChanged { candidates.append(PlannedUpload(key: key, ifMatch: entry.etag, ifNoneMatch: nil, bytes: file.bytes)) }
                else if remoteChanged { downloads.append(key) }
            default:
                break
            }
        }
        var used = remoteMap.values.reduce(Int64(0)) { $0 + $1.size }
        for key in trashes { used -= remoteMap[key]?.size ?? 0 }
        if used < 0 { used = 0 }
        var remaining = rateRemaining
        var uploads: [PlannedUpload] = []
        var paused: [String] = []
        var tooLarge: [String] = []
        var rateLimited: [String] = []
        for upload in candidates.sorted(by: { SyncRank.sort([$0.key, $1.key]).first == $0.key }) {
            if upload.bytes > maxFileBytes {
                tooLarge.append(upload.key)
                continue
            }
            let growth = max(Int64(0), upload.bytes - (remoteMap[upload.key]?.size ?? 0))
            if used >= capBytes || used + growth > capBytes {
                paused.append(upload.key)
                continue
            }
            if upload.bytes > remaining {
                rateLimited.append(upload.key)
                continue
            }
            uploads.append(upload)
            used += growth
            remaining -= upload.bytes
        }
        return SyncPlan(
            downloads: SyncRank.sort(downloads),
            uploads: uploads,
            trashes: trashes.sorted(),
            conflicts: conflicts.sorted(),
            paused: paused.sorted(),
            tooLarge: tooLarge.sorted(),
            rateLimited: rateLimited.sorted(),
            localDeletes: localDeletes.sorted()
        )
    }

    private static func excluded(_ key: String) -> Bool {
        key.hasPrefix("trash/") || key.hasPrefix("invites/") || key == ".grails-sync.json" || key == LibraryMigration.ledgerKey
    }
}

public enum BucketTrash {
    public static func key(for live: String) -> String { "trash/" + live }

    public static func empty(store: any ObjectStore, role: LibraryRole) async throws -> [String] {
        guard TeamPermissions.canEmptyTrash(role) else { throw SyncFailure.notAllowed }
        let heads = try await store.list(prefix: "trash/")
        for head in heads { try await store.delete(head.key) }
        return heads.map(\.key).sorted()
    }
}

public enum SyncFailure: Error, Equatable {
    case notAllowed
    case blocked(UpdateNotice)
    case revoked

    /// Clock skew and a bad signature are retried on the next poll. They are not a revoked key.
    public static func isRetryableAuth(_ error: Error) -> Bool {
        guard case S3Error.status(let code, let body) = error, code == 401 || code == 403 else { return false }
        let text = body.lowercased()
        let codes = ["requesttimetooskewed", "requestexpired", "signaturedoesnotmatch", "authorizationheadermalformed", "incompletesignature", "xamzcontentsha256mismatch"]
        return codes.contains { text.contains($0) }
    }

    public static let retryMessage = "Couldn't reach your team storage. Check your Mac's date and time, then try again."

    /// A key the service no longer accepts. Other 401 and 403 responses stay retryable.
    public static func isRevoked(_ error: Error) -> Bool {
        guard case S3Error.status(let code, let body) = error, code == 401 || code == 403 else { return false }
        if isRetryableAuth(error) { return false }
        let text = body.lowercased()
        return text.contains("invalidaccesskeyid") || text.contains("invalidclienttokenid") || text.contains("accessdenied") || text.contains("allaccessdisabled") || text.contains("revoked")
    }

    public static func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        if let url = error as? URLError, url.code == .cancelled { return true }
        return false
    }
}

private final class ErrorBox: @unchecked Sendable {
    let error: Error
    init(_ error: Error) { self.error = error }
}

private enum RaceResult<T: Sendable>: Sendable {
    case value(T)
    case failure(ErrorBox)
}

public actor BucketSyncEngine {
    public static let poll = SyncTiming.poll
    private let store: any ObjectStore
    private let root: URL
    private let merger: any ObjectMerger
    private let appVersion: String
    private let bucketName: String
    private var manifest: SyncManifest
    /// Bumped when a rename starts, so a sync pass that already fetched `library.json` cannot write that stale etag back over the publish.
    private var libraryRevision: UInt64 = 0
    private var devices: [String: String]
    /// Application Support copy, keyed by library id. Nil in tests that only use the library folder.
    private var cursorURL: URL?
    private var dirty = false
    private var sleeper: Task<Void, Never>?
    /// One pass at a time. `passEpoch` bumps when the library is detached so the in-flight pass stops.
    private var passBusy = false
    private var passWaiters: [CheckedContinuation<Void, Error>] = []
    private var passEpoch = 0
    private var failureStep: SyncStep = .sync
    /// Digests from the last scan, so a quiet poll stats files instead of hashing the library.
    private var scanCache = ScanCache()
    private var passLog: (@Sendable (String) -> Void)?
    private var lastFullScan: Date?

    public init(store: any ObjectStore, root: URL, merger: any ObjectMerger, manifest: SyncManifest = SyncManifest(), devices: [String: String] = [:], appVersion: String, bucketName: String = "", cursorURL: URL? = nil) {
        self.store = store
        self.root = root
        self.merger = merger
        var manifest = manifest
        manifest.canonicalizeETags()
        self.manifest = manifest
        self.devices = devices
        self.appVersion = appVersion
        self.bucketName = bucketName
        self.cursorURL = cursorURL
    }

    public func noteLocalChange() {
        dirty = true
        sleeper?.cancel()
    }

    /// Publishes a renamed `library.json`. A stale manifest etag is a 412: read the live object, put the new name on that body, keep its signed team, and retry. Returns the body that landed.
    public func publishLibrary(_ body: Data, role: LibraryRole) async throws -> Data {
        guard TeamPermissions.seesTeamControls(role) else { throw SyncFailure.notAllowed }
        guard let name = LibraryName.read(body) else { throw LibraryNameError.malformed }
        libraryRevision &+= 1
        var attempt = body
        var match = manifest.entries[Self.libraryKey]?.etag
        for tryIndex in 0..<4 {
            do {
                let etag = try await put(Self.libraryKey, body: attempt, contentType: S3Client.contentType(Self.libraryKey), ifMatch: match, ifNoneMatch: match == nil ? "*" : nil)
                manifest.entries[Self.libraryKey] = ManifestEntry(etag: ETags.canonical(etag), digest: Digests.sha256Hex(attempt), size: Int64(attempt.count))
                try saveManifest()
                return attempt
            } catch S3Error.preconditionFailed {
                if tryIndex == 3 { throw S3Error.preconditionFailed }
                let remote = try await get(Self.libraryKey)
                attempt = try renamedRemoteLibrary(remote.body, name: name)
                match = remote.etag
            }
        }
        throw S3Error.preconditionFailed
    }

    public func noteSnapshot(day: String) throws {
        manifest.lastSnapshotDay = day
        try saveManifest()
    }

    public func currentManifest() -> SyncManifest { manifest }

    public func noteMintedToken(_ id: String) throws {
        manifest.noteMinted(id)
        try saveManifest()
    }

    public func revokeContext() -> RevokeContext {
        RevokeContext(
            pinnedOwnerKey: manifest.pinnedOwnerKey ?? manifest.trusted?.pinnedOwnerKey,
            team: manifest.trusted?.body,
            devices: signingDevices(roster: manifest.trusted?.body),
            mintedTokenIDs: Set(manifest.mintedTokenIDs ?? [])
        )
    }

    /// Drops the in-flight pass and its socket. A library switch, sleep, or a network change calls this so a hung GET cannot run out the resource cap.
    public func cancelInFlight() async {
        passEpoch += 1
        if let stop = store as? any SyncStoppable {
            await stop.cancelInFlight()
        }
    }

    /// The step that threw on the last pass. `sync` when the pass did not fail inside list, get, put, or the roster.
    public func consumeFailureStep() -> SyncStep {
        let step = failureStep
        failureStep = .sync
        return step
    }

    public func setPassLog(_ log: @escaping @Sendable (String) -> Void) {
        passLog = log
    }

    public func syncOnce(now: Date = Date(), onProgress: (@Sendable (Int, Int) async -> Void)? = nil, onTransfers: (@Sendable (Bool) async -> Void)? = nil) async throws -> SyncReport {
        let epoch = try await beginPass()
        defer { endPass() }
        do {
            return try await syncPass(now: now, epoch: epoch, onProgress: onProgress, onTransfers: onTransfers)
        } catch SyncFailure.revoked {
            await onTransfers?(false)
            return SyncReport(stopped: .revoked)
        }
    }

    private func beginPass() async throws -> Int {
        let epoch = passEpoch
        if passBusy {
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
                passWaiters.append(cont)
            }
            // The previous pass handed over the lock. passBusy is still true.
            if passEpoch != epoch {
                endPass()
                throw CancellationError()
            }
            return epoch
        }
        passBusy = true
        if passEpoch != epoch {
            endPass()
            throw CancellationError()
        }
        return epoch
    }

    /// Releases the pass, or hands the lock to the next waiter without a gap where a third caller could enter.
    private func endPass() {
        if passWaiters.isEmpty {
            passBusy = false
            return
        }
        let next = passWaiters.removeFirst()
        next.resume()
    }

    private func stillCurrent(_ epoch: Int) throws {
        if passEpoch != epoch || Task.isCancelled { throw CancellationError() }
    }

    private func syncPass(now: Date, epoch: Int, onProgress: (@Sendable (Int, Int) async -> Void)? = nil, onTransfers: (@Sendable (Bool) async -> Void)? = nil) async throws -> SyncReport {
        try stillCurrent(epoch)
        let libraryURL = root.appendingPathComponent("library.json")
        seedSigningKeys()
        loadDevices(roster: manifest.trusted?.body)
        var trusted = manifest.trusted
        let revisionAtFetch = libraryRevision
        let remoteLibraryGet: ObjectGet?
        do {
            remoteLibraryGet = try await get(Self.libraryKey)
        } catch let error as S3Error where error == .notFound {
            remoteLibraryGet = nil
        }
        // A rename awaits inside its PUT. This get may have started before that PUT and would otherwise stamp the old etag.
        let remoteLibrary = libraryRevision == revisionAtFetch ? remoteLibraryGet?.body : nil
        // The get above awaits. A rename can land on disk in that gap, so reconcile the file that is there now, not the bytes read before the request.
        var localLibrary = try markRoster { try reconciledLibrary(remote: remoteLibrary, trusted: &trusted, url: libraryURL) }
        noteTrusted(trusted)
        let minimum = trusted?.body.minAppVersion
        let cap = trusted?.body.capBytes ?? Int64(TeamBody.defaultCapGB) * 1_000_000_000
        if !AppVersion.allowsSync(app: appVersion, minimum: minimum) {
            return SyncReport(capBytes: cap, blocked: UpdateNotice(minAppVersion: minimum ?? "", appVersion: appVersion))
        }
        if let notice = try? await MoveNotice.read(from: store), bucketName.isEmpty || notice.bucket == bucketName {
            return SyncReport(capBytes: cap, moved: notice)
        }
        loadDevices(roster: trusted?.body)
        localLibrary = try markRoster { try reconciledLibrary(remote: remoteLibrary, trusted: &trusted, url: libraryURL) }
        noteTrusted(trusted)
        if libraryRevision == revisionAtFetch {
            if (try? Data(contentsOf: libraryURL)) != localLibrary {
                try localLibrary.write(to: libraryURL, options: .atomic)
            }
            if let remoteLibraryGet, libraryRevision == revisionAtFetch {
                noteLibraryRemote(remoteLibraryGet, local: localLibrary)
                try saveManifest()
            }
        }
        try stillCurrent(epoch)
        let remote = try await listAll()
        try stillCurrent(epoch)
        let local = try scanLocal()
        let rateUsed = UploadMeter.used(manifest.uploadEvents, at: now)
        let rateLimit = trusted?.body.uploadBytesPerMinute ?? Int64(TeamBody.defaultUploadMBPerMinute) * 1_000_000
        let maxFile = trusted?.body.maxFileBytes ?? Int64(TeamBody.defaultMaxFileMB) * 1_000_000
        let plan = SyncPlanner.plan(local: local, remote: remote, manifest: manifest.entries, capBytes: cap, maxFileBytes: maxFile, rateRemaining: rateLimit - rateUsed)
        var report = SyncReport(paused: plan.paused, tooLarge: plan.tooLarge, rateLimited: plan.rateLimited, capBytes: cap)
        func librarySettled(_ key: String) -> Bool {
            key != Self.libraryKey || libraryRevision == revisionAtFetch
        }
        let itemIDs = SyncItems.ids(in: plan.downloads)
        passLog?(SyncPassLog.started(downloads: plan.downloads.count, uploads: plan.uploads.count))
        // Listing, planning, local deletes, and saving the manifest are not transfers. Syncing is only downloads, uploads, conflicts, and trashes.
        let transferring = !plan.downloads.isEmpty || !plan.uploads.isEmpty || !plan.conflicts.isEmpty || !plan.trashes.isEmpty
        if transferring { await onTransfers?(true) }
        var transferError: Error?
        do {
        var remaining: [String: Int] = [:]
        for key in plan.downloads {
            if let id = SyncItems.id(in: key) { remaining[id, default: 0] += 1 }
        }
        if SyncFeedback.showsProgress(total: itemIDs.count) {
            passLog?(SyncPassLog.progress(done: 0, total: itemIDs.count))
            await onProgress?(0, itemIDs.count)
        }
        var finishedItems = 0
        for key in plan.downloads where librarySettled(key) {
            try stillCurrent(epoch)
            guard let url = SyncPath.url(root: root, key: key) else { continue }
            let got = try await get(key)
            guard librarySettled(key) else { continue }
            try stillCurrent(epoch)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            if key == "library.json", try await keepLocalLibraryName(diskAt: url, remote: got.body, ifMatch: got.etag, trusted: &trusted, report: &report) {
                continue
            }
            guard librarySettled(key) else { continue }
            var payload = got.body
            if key.hasPrefix(".members/") {
                let local = try? Data(contentsOf: url)
                payload = MemberFile.incoming(local: local, remote: got.body, authorizedPublicKey: MemberFile.authorizedKey(for: key, team: trusted?.body))
            }
            let etag: String
            if payload != got.body {
                etag = try await put(key, body: payload, contentType: S3Client.contentType(key), ifMatch: got.etag, ifNoneMatch: nil)
            } else {
                etag = got.etag
            }
            try payload.write(to: url, options: .atomic)
            manifest.entries[key] = ManifestEntry(etag: ETags.canonical(etag), digest: Digests.sha256Hex(payload), size: Int64(payload.count))
            try saveManifest()
            report.downloaded.append(key)
            if let id = SyncItems.id(in: key) {
                remaining[id, default: 1] -= 1
                if remaining[id] == 0 {
                    finishedItems += 1
                    if SyncFeedback.showsProgress(total: itemIDs.count) {
                        passLog?(SyncPassLog.progress(done: finishedItems, total: itemIDs.count))
                        await onProgress?(finishedItems, itemIDs.count)
                    }
                }
            }
        }
        for key in plan.conflicts where librarySettled(key) {
            try stillCurrent(epoch)
            guard let url = SyncPath.url(root: root, key: key) else { continue }
            let got = try await get(key)
            try stillCurrent(epoch)
            let localData = (try? Data(contentsOf: url)) ?? Data()
            let merged: Data
            if key == "library.json" {
                merged = try markRoster { try TeamFile.reconcile(local: localData, remote: got.body, trusted: &trusted, devices: devices, inviteOwnerKey: manifest.pinnedOwnerKey) }
            } else if key.hasPrefix(".members/") {
                merged = MemberFile.merge(local: localData, remote: got.body, authorizedPublicKey: MemberFile.authorizedKey(for: key, team: trusted?.body))
            } else {
                merged = merger.merge(key: key, local: localData, remote: got.body)
            }
            noteTrusted(trusted)
            guard librarySettled(key) else { continue }
            let etag = try await put(key, body: merged, contentType: S3Client.contentType(key), ifMatch: got.etag, ifNoneMatch: nil)
            guard librarySettled(key) else { continue }
            try merged.write(to: url, options: .atomic)
            manifest.entries[key] = ManifestEntry(etag: ETags.canonical(etag), digest: Digests.sha256Hex(merged), size: Int64(merged.count))
            try saveManifest()
            report.conflicts.append(key)
        }
        for key in plan.trashes {
            try stillCurrent(epoch)
            let got = try await get(key)
            _ = try await put(BucketTrash.key(for: key), body: got.body, contentType: S3Client.contentType(key), ifMatch: nil, ifNoneMatch: nil)
            try await remove(key)
            manifest.entries[key] = nil
            try saveManifest()
            report.trashed.append(key)
        }
        for key in plan.localDeletes {
            try stillCurrent(epoch)
            if let url = SyncPath.url(root: root, key: key) {
                try? FileManager.default.removeItem(at: url)
            }
            manifest.entries[key] = nil
            try saveManifest()
        }
        for upload in plan.uploads where librarySettled(upload.key) {
            try stillCurrent(epoch)
            guard let file = SyncPath.url(root: root, key: upload.key) else { continue }
            let data = try Data(contentsOf: file)
            guard librarySettled(upload.key) else { continue }
            let etag = try await put(upload.key, body: data, contentType: S3Client.contentType(upload.key), ifMatch: upload.ifMatch, ifNoneMatch: upload.ifNoneMatch)
            guard librarySettled(upload.key) else { continue }
            manifest.entries[upload.key] = ManifestEntry(etag: ETags.canonical(etag), digest: Digests.sha256Hex(data), size: Int64(data.count))
            manifest.uploadEvents.append(UploadEvent(at: now.timeIntervalSince1970, bytes: Int64(data.count)))
            try saveManifest()
            report.uploaded.append(upload.key)
        }
        } catch {
            transferError = error
        }
        if transferring { await onTransfers?(false) }
        if let transferError {
            try? saveManifest()
            throw transferError
        }
        manifest.uploadEvents = UploadMeter.pruned(manifest.uploadEvents, at: now)
        let listed = try await listAll()
        manifest.usageBytes = listed.filter { !$0.key.hasPrefix("trash/") && !$0.key.hasPrefix("invites/") }.reduce(0) { $0 + $1.size }
        report.usageBytes = manifest.usageBytes
        try saveManifest()
        return report
    }

    public func run(interval: Duration = SyncTiming.poll, sleep: @escaping @Sendable (Duration) async -> Void = { try? await Task.sleep(for: $0, tolerance: SyncTiming.tolerance) }) async {
        while !Task.isCancelled {
            if dirty {
                dirty = false
                if await halted() { return }
                continue
            }
            await sleep(interval)
            if Task.isCancelled { break }
            if await halted() { return }
        }
    }

    private func scanLocal() throws -> [LocalObject] {
        let wallClock = Date()
        let full = lastFullScan.map { wallClock.timeIntervalSince($0) >= SyncTiming.fullScan || wallClock < $0 } ?? true
        let local = try LibraryScanner.scan(root: root, cache: &scanCache, rehash: full, now: wallClock)
        if full { lastFullScan = wallClock }
        return local
    }

    private func halted() async -> Bool {
        (try? await syncOnce())?.stopped == .revoked
    }

    private func get(_ key: String) async throws -> ObjectGet {
        let store = self.store
        return try await demand(.get) { try await store.get(key) }
    }

    private func listAll() async throws -> [ObjectHead] {
        let store = self.store
        return try await demand(.list) { try await store.list(prefix: "") }
    }

    private func put(_ key: String, body: Data, contentType: String, ifMatch: String?, ifNoneMatch: String?) async throws -> String {
        let store = self.store
        return try await demand(.put) { try await store.put(key, body: body, contentType: contentType, ifMatch: ifMatch, ifNoneMatch: ifNoneMatch) }
    }

    private func remove(_ key: String) async throws {
        let store = self.store
        try await demand(.put) { try await store.delete(key) }
    }

    private func markRoster<T>(_ body: () throws -> T) rethrows -> T {
        failureStep = .roster
        do {
            let value = try body()
            failureStep = .sync
            return value
        } catch {
            throw error
        }
    }

    /// Runs the store call beside a watch on `passEpoch`. Sleep and a path change bump the epoch, and the watch cancels the call instead of waiting out the resource timeout.
    private func demand<T: Sendable>(_ step: SyncStep, _ work: @escaping @Sendable () async throws -> T) async throws -> T {
        failureStep = step
        let epoch = passEpoch
        do {
            let value = try await race(epoch: epoch, work: work)
            failureStep = .sync
            return value
        } catch {
            if SyncFailure.isCancellation(error) {
                failureStep = .sync
                throw CancellationError()
            }
            if SyncFailure.isRevoked(error) { throw SyncFailure.revoked }
            throw error
        }
    }

    private func epochChanged(_ epoch: Int) -> Bool { passEpoch != epoch }

    private func race<T: Sendable>(epoch: Int, work: @escaping @Sendable () async throws -> T) async throws -> T {
        try await withThrowingTaskGroup(of: RaceResult<T>.self) { group in
            group.addTask {
                do {
                    return .value(try await work())
                } catch {
                    return .failure(ErrorBox(error))
                }
            }
            group.addTask {
                do {
                    while !Task.isCancelled {
                        try await Task.sleep(for: .milliseconds(200), tolerance: .milliseconds(50))
                        if await self.epochChanged(epoch) { return .failure(ErrorBox(CancellationError())) }
                    }
                    return .failure(ErrorBox(CancellationError()))
                } catch {
                    return .failure(ErrorBox(CancellationError()))
                }
            }
            let first = try await group.next() ?? .failure(ErrorBox(CancellationError()))
            group.cancelAll()
            switch first {
            case .value(let value): return value
            case .failure(let box): throw box.error
            }
        }
    }

    public func deleteLibrary(role: LibraryRole) async throws {
        guard TeamPermissions.canDeleteLibrary(role) else { throw SyncFailure.notAllowed }
        let all = try await store.list(prefix: "")
        for head in all { try await store.delete(head.key) }
    }

    private static let libraryKey = "library.json"

    /// The get at the start of a pass used to drop the etag. Reconcile then rewrote `library.json` (sorted keys, signed team) and left the manifest pointing at an older object, so a rename's If-Match 412'd.
    /// A file this Mac did not change keeps its old digest, so a remote edit still downloads. A rewrite records the live etag and the remote digest, so the following upload's If-Match is current.
    private func noteLibraryRemote(_ remote: ObjectGet, local: Data) {
        let localDigest = Digests.sha256Hex(local)
        let remoteDigest = Digests.sha256Hex(remote.body)
        if localDigest == remoteDigest {
            manifest.entries[Self.libraryKey] = ManifestEntry(etag: ETags.canonical(remote.etag), digest: localDigest, size: Int64(local.count))
            return
        }
        guard let previous = manifest.entries[Self.libraryKey], localDigest != previous.digest else { return }
        manifest.entries[Self.libraryKey] = ManifestEntry(etag: ETags.canonical(remote.etag), digest: remoteDigest, size: Int64(remote.body.count))
    }

    /// Name goes on the remote body. The signed team block stays the one reconcile trusts.
    private func renamedRemoteLibrary(_ remote: Data, name: String) throws -> Data {
        let named = try LibraryName.apply(remote, name: name)
        var trusted = manifest.trusted
        loadDevices(roster: trusted?.body)
        let merged = try TeamFile.reconcile(local: named, remote: remote, trusted: &trusted, devices: devices, inviteOwnerKey: manifest.pinnedOwnerKey)
        noteTrusted(trusted)
        return merged
    }

    private func reconciledLibrary(remote: Data?, trusted: inout TrustedTeam?, url: URL) throws -> Data {
        let disk = (try? Data(contentsOf: url)) ?? Data("{}".utf8)
        return try TeamFile.reconcile(local: disk, remote: remote, trusted: &trusted, devices: devices, inviteOwnerKey: manifest.pinnedOwnerKey)
    }

    /// A download of `library.json` must not replace a name this Mac just wrote. The team block still merges.
    private func keepLocalLibraryName(diskAt url: URL, remote: Data, ifMatch: String, trusted: inout TrustedTeam?, report: inout SyncReport) async throws -> Bool {
        let disk = (try? Data(contentsOf: url)) ?? Data()
        let entry = manifest.entries["library.json"]
        let localChanged = entry.map { Digests.sha256Hex(disk) != $0.digest } ?? true
        guard localChanged, let diskName = LibraryName.read(disk), diskName != LibraryName.read(remote) else { return false }
        let merged = try TeamFile.reconcile(local: disk, remote: remote, trusted: &trusted, devices: devices, inviteOwnerKey: manifest.pinnedOwnerKey)
        noteTrusted(trusted)
        let etag = try await put("library.json", body: merged, contentType: S3Client.contentType("library.json"), ifMatch: ifMatch, ifNoneMatch: nil)
        try merged.write(to: url, options: .atomic)
        manifest.entries["library.json"] = ManifestEntry(etag: ETags.canonical(etag), digest: Digests.sha256Hex(merged), size: Int64(merged.count))
        report.conflicts.append("library.json")
        return true
    }

    /// An upgraded Mac seeds from the member files already on disk. A first join seeds nothing, so a file downloaded in this pass cannot become a signing key.
    private func seedSigningKeys() {
        if manifest.signingDeviceKeys != nil { return }
        if manifest.trusted != nil {
            manifest.signingDeviceKeys = DeviceBindings.map(files: DeviceBindings.read(root: root), roster: manifest.trusted?.body)
        } else {
            manifest.signingDeviceKeys = [:]
        }
    }

    private func signingDevices(roster: TeamBody?) -> [String: String] {
        var out = manifest.signingDeviceKeys ?? [:]
        if let roster {
            out[TeamEmail.normalize(roster.ownerEmail)] = roster.ownerPublicKey
            for member in roster.members {
                if let key = member.publicKey, !key.isEmpty {
                    out[TeamEmail.normalize(member.email)] = key
                }
            }
        }
        return out
    }

    private func loadDevices(roster: TeamBody?) {
        devices = signingDevices(roster: roster)
    }

    private func noteTrusted(_ trusted: TrustedTeam?) {
        manifest.store(trusted: trusted)
        guard var keys = manifest.signingDeviceKeys, let body = trusted?.body else { return }
        let owner = TeamEmail.normalize(body.ownerEmail)
        if keys[owner] != body.ownerPublicKey { keys[owner] = body.ownerPublicKey }
        for member in body.members {
            guard let key = member.publicKey, !key.isEmpty else { continue }
            keys[TeamEmail.normalize(member.email)] = key
        }
        manifest.signingDeviceKeys = keys
        devices = signingDevices(roster: trusted?.body)
    }

    private static let manifestEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    /// Writes the cursor only when its bytes changed. An unchanged poll used to rewrite the file, the watcher treated that as a library edit, and the next poll started at once.
    private func saveManifest() throws {
        manifest.canonicalizeETags()
        let data = try Self.manifestEncoder.encode(manifest)
        try writeIfChanged(data, to: root.appendingPathComponent(".grails-sync.json"))
        if let cursorURL {
            try FileManager.default.createDirectory(at: cursorURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try writeIfChanged(data, to: cursorURL)
        }
    }

    private func writeIfChanged(_ data: Data, to url: URL) throws {
        if (try? Data(contentsOf: url)) == data { return }
        try data.write(to: url, options: .atomic)
    }
}

public enum LibraryUploader {
    public static func upload(root: URL, store: any ObjectStore) async throws -> [String] {
        let files = try LibraryScanner.scan(root: root)
        let ordered = SyncRank.sort(files.map(\.key))
        var sent: [String] = []
        for key in ordered {
            let data = try Data(contentsOf: root.appendingPathComponent(key))
            _ = try await store.put(key, body: data, contentType: S3Client.contentType(key), ifMatch: nil, ifNoneMatch: nil)
            sent.append(key)
        }
        return sent
    }
}
