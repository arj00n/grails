import Foundation

public enum LibraryLanding: Equatable, Sendable {
    case canon
    case all
}

public enum Landing {
    /// Stored collection names that mean Holy Grail. "Baseline" and "Canon" are the names libraries still have on disk and in the bucket.
    public static let canonNames = ["Canon", "Baseline"]

    public static func pick(collectionNames: [String]) -> LibraryLanding {
        collectionNames.contains { name in
            canonNames.contains { name.caseInsensitiveCompare($0) == .orderedSame }
        } ? .canon : .all
    }
}

public enum FirstRunTips {
    public static let lines = ["Paste or drop", "Figma and Chrome", "⌘K"]
}

public enum SyncPhase: Equatable, Sendable {
    case thumbnails
    case files
    case idle

    public static func phase(pendingKeys: [String]) -> SyncPhase {
        if pendingKeys.contains(where: SyncRank.thumbnail) { return .thumbnails }
        if !pendingKeys.isEmpty { return .files }
        return .idle
    }
}

public struct JoinPresenter: Equatable, Sendable {
    public enum Screen: Equatable, Sendable {
        case code
        case welcome(admin: String, library: String, email: String)
        case syncing(done: Int, total: Int, phase: SyncPhase)
        case library(LibraryLanding)
        case tip(Int)
        case inviteTeammates
        case done
    }

    public var screen: Screen
    public var landing: LibraryLanding

    public init() {
        screen = .code
        landing = .all
    }

    public mutating func unlocked(admin: String, library: String, email: String) {
        screen = .welcome(admin: admin, library: library, email: email)
    }

    public mutating func progress(done: Int, total: Int, pendingKeys: [String]) {
        screen = .syncing(done: done, total: total, phase: SyncPhase.phase(pendingKeys: pendingKeys))
    }

    public mutating func finishedSync(collections: [String], role: LibraryRole, tipsSeen: Bool) {
        landing = Landing.pick(collectionNames: collections)
        if !tipsSeen {
            screen = .tip(0)
            return
        }
        finish(role: role)
    }

    public mutating func nextTip(role: LibraryRole) {
        guard case .tip(let index) = screen else { return }
        if index + 1 < FirstRunTips.lines.count {
            screen = .tip(index + 1)
        } else {
            finish(role: role)
        }
    }

    private mutating func finish(role: LibraryRole) {
        screen = TeamPermissions.canInvite(role) ? .inviteTeammates : .library(landing)
    }

    public mutating func dismissInvite() {
        screen = .library(landing)
    }
}
