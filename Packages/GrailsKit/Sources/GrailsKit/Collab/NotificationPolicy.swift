import Foundation

/// Who a collection belongs to. The owner and the members hear about items placed in it.
public struct CollectionStake: Equatable, Sendable {
    public var owner: String
    public var members: [String]

    public init(owner: String, members: [String] = []) {
        self.owner = owner
        self.members = members
    }

    public func includes(_ viewer: String) -> Bool {
        let who = NotificationPolicy.key(viewer)
        guard !who.isEmpty else { return false }
        if NotificationPolicy.key(owner) == who { return true }
        return members.contains { NotificationPolicy.key($0) == who }
    }
}

public enum CollectionStakeRead {
    public static func stake(owner: String, extras: [String: JSONValue]) -> CollectionStake {
        let members: [String]
        if case .array(let values) = extras["members"] {
            members = values.compactMap { value in
                if case .string(let name) = value { return name }
                return nil
            }
        } else {
            members = []
        }
        return CollectionStake(owner: owner, members: members)
    }
}

/// Something another person did. Adding an item, by itself, is not a notice.
public enum ActivityEvent: Equatable, Sendable {
    case itemAdded(by: String)
    case mentioned(by: String, handle: String)
    case tagged(by: String, handle: String)
    case addedToCollection(by: String, stake: CollectionStake)
}

public enum ActivityNotice: Equatable, Sendable {
    case mention
    case tag
    case collection
}

/// Who hears about a change. The person who made it does not. Everyone else hears only a mention, a tag, or a collection they belong to.
public enum NotificationPolicy {
    public static func notice(viewer: String, event: ActivityEvent) -> ActivityNotice? {
        let who = key(viewer)
        guard !who.isEmpty else { return nil }
        switch event {
        case .itemAdded:
            return nil
        case .mentioned(let by, let handle):
            guard key(handle) == who, key(by) != who else { return nil }
            return .mention
        case .tagged(let by, let handle):
            guard key(handle) == who, key(by) != who else { return nil }
            return .tag
        case .addedToCollection(let by, let stake):
            guard key(by) != who, stake.includes(viewer) else { return nil }
            return .collection
        }
    }

    public static func lines(viewer: String, events: [ActivityEvent]) -> [String] {
        var out: [String] = []
        var seen = Set<ActivityNotice>()
        for event in events {
            guard let notice = notice(viewer: viewer, event: event), seen.insert(notice).inserted else { continue }
            switch notice {
            case .mention: out.append("You were mentioned")
            case .tag: out.append("You were tagged")
            case .collection: out.append("An item was added to your collection")
            }
        }
        return out
    }

    public static func key(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
