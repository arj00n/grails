import Foundation

public struct UnopenedReference: Equatable, Sendable {
    public var key: String
    public var name: String
    public var addedAt: TimeInterval
    public var kind: String
    public var ext: String?

    public init(key: String, name: String, addedAt: TimeInterval, kind: String = "image", ext: String? = nil) {
        self.key = key
        self.name = name
        self.addedAt = addedAt
        self.kind = kind
        self.ext = ext
    }
}

/// What a horizontal release does to the top card. Left is chuck, right is keep.
public enum SpringChoice: String, Equatable, Sendable {
    case keep
    case chuck
    case springBack
}

/// Left and Delete chuck. Right and Return keep. The deck handles these itself, so focus navigation cannot eat them.
public enum SpringKeys {
    public static func choice(keyCode: UInt16) -> SpringChoice? {
        switch keyCode {
        case 123, 51, 117: return .chuck
        case 124, 36: return .keep
        default: return nil
        }
    }
}

/// The front card flies off while the next one lifts into its place. Both use the same `lift`, so they move together.
/// The motion is GrailsDesign's `grailsSpring`; `settle` is how long the deck waits for it before the choice is applied.
public enum SpringFlight {
    public static let settle = 0.48
    public static let stackedScale = 0.95

    public static func scale(depth: Int, lift: Double) -> Double {
        if depth <= 0 { return 1 }
        let clamped = min(1, max(0, lift))
        if depth == 1 { return stackedScale + (1 - stackedScale) * clamped }
        return 0.9
    }

    public static func peekOffset(depth: Int, lift: Double, peek: Double) -> Double {
        if depth <= 0 { return 0 }
        let clamped = min(1, max(0, lift))
        if depth == 1 { return peek * (1 - clamped) }
        return peek + 10
    }
}

public enum SpringSwipe {
    /// Points of horizontal travel before a release keeps or chucks.
    public static let threshold: Double = 96
    /// Degrees of tilt at a long drag. The sign matches the drag.
    public static let maxRotation: Double = 14

    public static func choice(translation: Double) -> SpringChoice {
        if translation >= threshold { return .keep }
        if translation <= -threshold { return .chuck }
        return .springBack
    }

    public static func rotation(translation: Double, width: Double) -> Double {
        let reach = max(width, 1) * 0.72
        let degrees = (translation / reach) * maxRotation
        return min(maxRotation, max(-maxRotation, degrees))
    }

    /// Where the card rests after the pointer lets go. A choice flies past the card; a short drag returns to centre.
    public static func rest(translation: Double, width: Double) -> Double {
        switch choice(translation: translation) {
        case .springBack:
            return 0
        case .keep:
            return width + threshold
        case .chuck:
            return -(width + threshold)
        }
    }
}

public enum SpringMedia {
    public static func itemID(for key: String) -> String {
        let parts = key.split(separator: "/").map(String.init)
        guard parts.count >= 3, parts[0] == "items", parts.last == "item.json" else { return "" }
        return parts[1]
    }

    public static func fileName(ext: String?) -> String {
        guard let ext, !ext.isEmpty else { return "original" }
        return "original.\(ext)"
    }

    public static func plays(_ card: UnopenedReference) -> Bool {
        if card.kind == "video" { return true }
        switch card.ext?.lowercased() {
        case "mp4", "mov", "m4v": return true
        default: return false
        }
    }
}

public enum SpringCommand {
    public static let title = "Spring Cleaning"
    public static func visible(to role: LibraryRole) -> Bool { SpringAccess.allows(role) }
}

public struct SpringDeck: Equatable, Sendable {
    public private(set) var cards: [UnopenedReference]

    public init(cards: [UnopenedReference]) {
        self.cards = cards
    }

    public var current: UnopenedReference? { cards.first }

    /// `item.json` keys in a listing, read from the synced library on disk. Only keys with no local copy are left for the caller to fetch.
    public static func localItems(root: URL?, heads: [ObjectHead]) -> (found: [(key: String, json: Data)], missing: [String]) {
        var found: [(key: String, json: Data)] = []
        var missing: [String] = []
        for head in heads where head.key.hasPrefix("items/") && head.key.hasSuffix("/item.json") {
            if let root, let url = SyncPath.url(root: root, key: head.key), let json = try? Data(contentsOf: url) {
                found.append((head.key, json))
            } else {
                missing.append(head.key)
            }
        }
        return (found, missing)
    }

    public static func rank(items: [(key: String, json: Data)]) -> [UnopenedReference] {
        items.compactMap { ReferenceFile.unopened(key: $0.key, json: $0.json) }
            .sorted { $0.addedAt == $1.addedAt ? $0.key < $1.key : $0.addedAt < $1.addedAt }
    }

    public mutating func keep() {
        guard !cards.isEmpty else { return }
        cards.removeFirst()
    }

    /// A short drag leaves the deck. Keep and chuck both reveal the next card.
    @discardableResult
    public mutating func release(translation: Double) -> SpringChoice {
        let choice = SpringSwipe.choice(translation: translation)
        guard choice != .springBack, !cards.isEmpty else { return .springBack }
        cards.removeFirst()
        return choice
    }
}

public enum SpringAccess {
    public static func allows(_ role: LibraryRole) -> Bool { role != .member }
}

public enum SpringTrash {
    public static func move(store: any ObjectStore, key: String, role: LibraryRole) async throws -> [String] {
        guard SpringAccess.allows(role) else { throw SyncFailure.notAllowed }
        let prefix = folderPrefix(for: key)
        let heads = try await store.list(prefix: prefix)
        var moved: [String] = []
        for head in heads.sorted(by: { $0.key < $1.key }) {
            let got = try await store.get(head.key)
            _ = try await store.put(BucketTrash.key(for: head.key), body: got.body, contentType: S3Client.contentType(head.key), ifMatch: nil, ifNoneMatch: nil)
            try await store.delete(head.key)
            moved.append(head.key)
        }
        return moved
    }

    public static func folderPrefix(for key: String) -> String {
        if key.hasSuffix("/item.json") { return String(key.dropLast("item.json".count)) }
        return key
    }
}

enum ReferenceFile {
    static func unopened(key: String, json: Data) -> UnopenedReference? {
        guard key.hasSuffix("/item.json"),
              let object = try? JSONSerialization.jsonObject(with: json) as? [String: Any] else { return nil }
        if present(object["deletedAt"]) || present(object["openedAt"]) { return nil }
        let name = object["name"] as? String ?? key
        let added = seconds(object["addedAt"]) ?? 0
        let kind = object["kind"] as? String ?? "image"
        let ext = object["ext"] as? String
        return UnopenedReference(key: key, name: name, addedAt: added, kind: kind, ext: ext)
    }

    private static func present(_ value: Any?) -> Bool {
        guard let value else { return false }
        return !(value is NSNull)
    }

    private static func seconds(_ value: Any?) -> TimeInterval? {
        if value is NSNull { return nil }
        if let number = value as? Double { return number }
        if let number = value as? Int { return TimeInterval(number) }
        guard let text = value as? String else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: text) { return date.timeIntervalSince1970 }
        let whole = ISO8601DateFormatter()
        whole.formatOptions = [.withInternetDateTime]
        return whole.date(from: text)?.timeIntervalSince1970
    }
}
