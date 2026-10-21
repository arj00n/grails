import Foundation

/// Where a library is shared. A bucket is a fact about the library, not a guess from the cache path.
/// Application Support looks local to `Placement.of`. Rename changes the library name and leaves this alone.
public enum LibraryPlace: Equatable, Sendable {
    case bucket
    /// The folder is a bucket library, and this Mac has no access key for it.
    case reconnect
    case folder(Placement)

    public enum Invite: Equatable, Sendable {
        /// Email, a single-use link, and a 6-digit code.
        case bucket
        /// `open#lib` for a folder a teammate can open.
        case sharedFolder
        /// The folder is only on this Mac, or otherwise unreachable. The folder warning applies.
        case localFolder
        /// Ask for the bucket key again. Do not offer a Drive invite.
        case reconnect
    }

    public static func resolve(path: URL?, isBucket: Bool, home: URL = FileManager.default.homeDirectoryForCurrentUser) -> LibraryPlace {
        if isBucket { return .bucket }
        if let path, lostBucket(path, home: home) { return .reconnect }
        guard let path else { return .folder(Placement(kind: .local)) }
        return .folder(Placement.of(path, home: home))
    }

    /// No keychain access, and the folder is the bucket cache or already has a bucket manifest.
    static func lostBucket(_ path: URL, home: URL) -> Bool {
        if isBucketCache(path, home: home) { return true }
        return FileManager.default.fileExists(atPath: path.appendingPathComponent(".grails-sync.json").path)
    }

    /// `~/Library/Application Support/Grails/bucket/<id>.grails`.
    static func isBucketCache(_ path: URL, home: URL) -> Bool {
        let root = home.appendingPathComponent("Library/Application Support/Grails/bucket").standardizedFileURL.path
        let folder = path.standardizedFileURL.path
        return folder == root || folder.hasPrefix(root + "/")
    }

    public var invite: Invite {
        switch self {
        case .bucket: .bucket
        case .reconnect: .reconnect
        case .folder(let placement):
            LibraryHint(placement: placement) == nil ? .localFolder : .sharedFolder
        }
    }

    public var label: String {
        switch self {
        case .bucket: "Cloud storage"
        case .reconnect: "Reconnect storage"
        case .folder(let placement): placement.label
        }
    }

    /// Team setup is how a folder library becomes shared. A bucket library is already shared.
    public var offersTeamSetup: Bool {
        switch invite {
        case .sharedFolder, .localFolder: true
        case .bucket, .reconnect: false
        }
    }

    /// A folder invite link is the same for everyone. A bucket invite is not.
    public var copiesFolderInvite: Bool { invite == .sharedFolder }

    public var opensPersonInvite: Bool { invite == .bucket }

    public var needsReconnect: Bool { self == .reconnect }
}

/// The team-library front door. A shared folder is the second choice.
public enum TeamHomeChoice: String, Equatable, Sendable, CaseIterable {
    case bucket
    case sharedFolder
    case join

    public static let order: [TeamHomeChoice] = [.bucket, .sharedFolder, .join]

    public var title: String {
        switch self {
        case .bucket: "Cloud storage (Cloudflare)"
        case .sharedFolder: "Shared folder (Drive, Dropbox)"
        case .join: "Join with invite…"
        }
    }
}
