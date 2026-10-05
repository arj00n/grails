import Foundation

/// One page of a Pinterest board's own feed, as the in-app reader returns it, turned into import entries.
public struct FeedPage: Sendable, Equatable {
    public var entries: [RemoteBoard.Entry]
    /// Pins on the page before mapping (videos and story pins can make more or fewer entries).
    public var pinCount: Int
    /// Rows on the page of any kind: a page of only non-pins is not the end of the board.
    public var rawCount: Int
    /// Where the next page starts; nil or "-end-" when this was the last.
    public var bookmark: String?
    public var status: Int

    public var ended: Bool { bookmark == nil || bookmark == "-end-" || bookmark?.isEmpty == true }
}

public enum PinterestBoardFeed {
    /// `object` is what the reader's script hands back: `{ status, data: [pin…], bookmark }`. Nil when it isn't that shape.
    public static func parsePage(_ object: [String: Any], author: String? = nil) -> FeedPage? {
        let status = (object["status"] as? Int) ?? 0
        guard let data = object["data"] as? [[String: Any]] else { return status == 200 ? nil : FeedPage(entries: [], pinCount: 0, rawCount: 0, bookmark: nil, status: status) }
        var entries: [RemoteBoard.Entry] = []
        var pins = 0
        for pin in data {
            // sponsored and "more ideas" rows share the feed with pins; only pins have an id and pictures
            guard (pin["type"] as? String ?? "pin") == "pin", let id = (pin["id"] as? String) ?? (pin["id"] as? Int).map(String.init) else { continue }
            pins += 1
            entries += PinterestPins.entries(for: pin, id: id, authorFallback: author)
        }
        return FeedPage(entries: entries, pinCount: pins, rawCount: (object["raw"] as? Int) ?? data.count, bookmark: object["bookmark"] as? String, status: status)
    }

    /// A person's boards from `BoardsResource`: `{ status, data: [board…], bookmark }`. Secret boards are included, marked by `privacy`.
    public struct ListedBoard: Sendable, Equatable {
        public var name: String
        public var path: String            // "/user/slug/"
        public var pinCount: Int
        public var secret: Bool
        public var cover: String?
    }

    public static func parseBoards(_ object: [String: Any]) -> (boards: [ListedBoard], bookmark: String?) {
        let data = object["data"] as? [[String: Any]] ?? []
        var out: [ListedBoard] = []
        for b in data {
            guard let url = b["url"] as? String, let name = b["name"] as? String else { continue }
            let cover = ((b["image_cover_url"] as? String) ?? ((b["images"] as? [String: Any])?.values.compactMap { ($0 as? [String: Any])?["url"] as? String }.first))
            out.append(ListedBoard(name: name, path: url, pinCount: (b["pin_count"] as? Int) ?? 0, secret: (b["privacy"] as? String ?? "public") != "public", cover: cover))
        }
        let bm = object["bookmark"] as? String
        return (out, bm == "-end-" || bm?.isEmpty == true ? nil : bm)
    }
}

/// Decides what the reader does after each page: how long to wait, when to stop, when to give up and fall back to the widget's latest 50.
public struct CollectorPlan: Sendable {
    public enum Step: Equatable, Sendable {
        /// Read the next page after this many seconds.
        case next(delay: Double)
        case done
        /// Pinterest said slow down: wait this long, then try the same page again.
        case wait(seconds: Int)
        /// The board is secret, or Pinterest wants a sign-in for it.
        case gated
        /// Pinterest changed the reply, or kept failing: use the widget.
        case changed
    }

    public static let maxPins = 20_000
    /// Seconds between pages; ±20 % is added by `jitter`.
    public static let gap = 1.2
    public static let failuresBeforeFallback = 3

    public private(set) var pins = 0
    public private(set) var pages = 0
    public private(set) var failures = 0

    public init(resumedPins: Int = 0) { pins = resumedPins }

    /// `page` is nil when the reply wasn't understood. `jitter` is 0...1 (the caller supplies it, so this stays deterministic).
    public mutating func record(status: Int, page: FeedPage?, retryAfter: Int? = nil, jitter: Double = 0.5) -> Step {
        if status == 429 { return .wait(seconds: max(retryAfter ?? 60, 1)) }
        if status == 401 || status == 403 { return .gated }
        guard status == 200, let page else {
            failures += 1
            return failures >= Self.failuresBeforeFallback ? .changed : .next(delay: Self.gap * Double(1 << failures))
        }
        failures = 0
        pages += 1
        pins += page.pinCount
        if page.ended || page.rawCount == 0 || pins >= Self.maxPins { return .done }
        return .next(delay: Self.gap * (0.8 + 0.4 * min(max(jitter, 0), 1)))
    }
}
