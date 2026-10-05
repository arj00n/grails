import Foundation

/// Something found in pasted text: a board to import, a person whose boards to list, a short link to resolve, or a link we can't use.
public enum LinkCandidate: Hashable, Codable, Sendable {
    case board(BoardRef)
    case arenaUser(slug: String)
    case pinterestUser(user: String)
    case pinterestShort(URL)
    case unrecognised(String)
}

public enum LinkHarvester {
    private static let arenaReserved: Set<String> = ["block", "blocks", "explore", "search", "settings", "notifications", "pricing", "about", "tools", "feed", "login", "sign-up", "channel", "channels", "user", "users", "groups", "group", "api", "i", "terms", "privacy"]
    private static let pinterestReserved: Set<String> = ["pin", "search", "ideas", "today", "business", "settings", "login", "news_hub", "_", "explore", "topics", "shop", "videos"]
    private static let hosts = ["are.na", "pinterest.", "pin.it", "x.com", "twitter.com"]

    /// Every link in `text`, in order, without repeats. Text around them (a Slack message, a Notes list) is ignored.
    public static func harvest(_ text: String) -> [LinkCandidate] {
        var out: [LinkCandidate] = []
        var seen = Set<LinkCandidate>()
        for token in tokens(in: text) {
            guard let c = classify(token), seen.insert(c).inserted else { continue }
            out.append(c)
        }
        return out
    }

    private static func tokens(in text: String) -> [String] {
        let separators = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ",;<>\"'()[]{}|"))
        return text.components(separatedBy: separators).map { $0.trimmingCharacters(in: CharacterSet(charactersIn: ".,:!?")) }.filter { !$0.isEmpty }
    }

    static func classify(_ token: String) -> LinkCandidate? {
        let lower = token.lowercased()
        let withScheme = lower.contains("://") ? token : "https://" + token
        guard let url = URL(string: withScheme), let host = url.host?.lowercased(), host.contains(".") else { return nil }
        let looksLikeAKnownSite = hosts.contains { host == $0 || host.hasSuffix("." + $0) || host.contains($0) }
        guard looksLikeAKnownSite || lower.contains("://") else { return nil }
        if let ref = BoardRef.parse(token) { return .board(ref) }
        if BoardRef.isPinterestShortLink(token) { return .pinterestShort(url) }
        let parts = url.path.split(separator: "/").map { String($0).removingPercentEncoding ?? String($0) }
        if host == "are.na" || host == "www.are.na", parts.count == 1, !arenaReserved.contains(parts[0].lowercased()) { return .arenaUser(slug: parts[0]) }
        if host.split(separator: ".").contains("pinterest"), let user = parts.first, !pinterestReserved.contains(user.lowercased()), !user.hasPrefix("_") {
            if parts.count == 1 || (parts.count == 2 && parts[1].hasPrefix("_")) { return .pinterestUser(user: user) }
        }
        return lower.contains("://") || looksLikeAKnownSite ? .unrecognised(token) : nil
    }
}
