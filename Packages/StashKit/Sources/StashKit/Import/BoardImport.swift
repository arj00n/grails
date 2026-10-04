import Foundation

/// A public Are.na channel or Pinterest board, recognised from the link someone pastes.
public enum BoardRef: Equatable, Sendable {
    case arena(slug: String)
    case pinterest(user: String, board: String)

    public var service: String {
        switch self { case .arena: "Are.na"; case .pinterest: "Pinterest" }
    }

    public var kindName: String {
        switch self { case .arena: "channel"; case .pinterest: "board" }
    }

    /// Where the board lives on the web (stored as the items' page link when nothing better exists).
    public var webURL: URL {
        switch self {
        case .arena(let slug): URL(string: "https://www.are.na/channels/\(slug)")!
        case .pinterest(let user, let board): URL(string: "https://www.pinterest.com/\(user)/\(board)/")!
        }
    }

    private static let arenaReserved: Set<String> = [
        "block", "blocks", "explore", "search", "settings", "notifications", "pricing", "about", "tools", "feed", "login", "sign-up",
        "channel", "user", "users", "groups", "group", "api", "i", "terms", "privacy",
    ]
    private static let pinterestReserved: Set<String> = [
        "pin", "search", "ideas", "today", "business", "settings", "login", "news_hub", "_", "explore", "topics", "shop", "videos",
    ]

    /// `nil` when the text isn't a recognisable Are.na channel or Pinterest board link. `pin.it` short links are
    /// returned as `.pinterestShort` by `BoardImporter` once resolved, so they are not handled here.
    public static func parse(_ text: String) -> BoardRef? {
        var s = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !s.contains("://") { s = "https://" + s }
        guard let url = URL(string: s), let host = url.host?.lowercased() else { return nil }
        let parts = url.path.split(separator: "/").map { String($0).removingPercentEncoding ?? String($0) }
        if host == "are.na" || host == "www.are.na" {
            if parts.count == 2, parts[0] == "channels" { return .arena(slug: parts[1]) }
            if parts.count >= 2, !arenaReserved.contains(parts[0].lowercased()) { return .arena(slug: parts[1]) }
            return nil
        }
        if host.split(separator: ".").contains("pinterest") {   // pinterest.com, in.pinterest.com, pinterest.co.uk …
            guard parts.count >= 2, !pinterestReserved.contains(parts[0].lowercased()), !parts[1].hasPrefix("_") else { return nil }
            return .pinterest(user: parts[0], board: parts[1])
        }
        return nil
    }

    /// `pin.it/abc` and `pinterest.com/…` share links redirect to the board; the importer resolves them.
    public static func isPinterestShortLink(_ text: String) -> Bool {
        let s = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: s.contains("://") ? s : "https://" + s), let host = url.host?.lowercased() else { return false }
        return host == "pin.it" || host == "www.pin.it"
    }
}

public enum BoardImportError: Error, LocalizedError, Equatable {
    case notABoardLink
    case profileNotBoard
    case notFoundOrPrivate(String)
    case blocked(String)
    case network(String)
    case empty(String)

    public var errorDescription: String? {
        switch self {
        case .notABoardLink: "That doesn't look like an Are.na channel or a Pinterest board link."
        case .profileNotBoard: "That's a profile link. Paste a link to one board (pinterest.com/name/board)."
        case .notFoundOrPrivate(let what): "Couldn't find \(what), or it isn't public."
        case .blocked(let why): why
        case .network(let why): "Couldn't reach the site: \(why)"
        case .empty(let what): "\(what) has nothing that can be imported."
        }
    }
}

/// Everything fetched about a board before any file is downloaded.
public struct RemoteBoard: Sendable {
    public struct Entry: Sendable, Equatable {
        /// Direct file URLs, best first; the importer uses the first that downloads.
        public var mediaUrls: [String]
        public var pageUrl: String?
        public var title: String?
        public var author: String?
        public init(mediaUrls: [String] = [], pageUrl: String? = nil, title: String? = nil, author: String? = nil) {
            self.mediaUrls = mediaUrls; self.pageUrl = pageUrl; self.title = title; self.author = author
        }
    }

    public var ref: BoardRef
    public var name: String
    public var entries: [Entry]
    /// Things that can't be imported, by reason ("text blocks": 4).
    public var skipped: [String: Int] = [:]
    /// What the service says the board holds, when it says.
    public var expectedTotal: Int?
    /// Something worth telling the person (e.g. Pinterest only shares recent pins).
    public var note: String?
}

public struct BoardImporter: Sendable {
    let loader: LinkFetcher.Loader
    public var pageSize = 100
    public var maxPages = 100

    public init(loader: @escaping LinkFetcher.Loader = { try await URLSession.shared.data(for: $0) }) { self.loader = loader }

    /// Reads the board's contents. `progress(found, expected)` fires after each page.
    public func fetch(_ ref: BoardRef, progress: @Sendable (Int, Int?) -> Void = { _, _ in }) async throws -> RemoteBoard {
        switch ref {
        case .arena(let slug): try await fetchArena(slug: slug, progress: progress)
        case .pinterest(let user, let board): try await fetchPinterest(user: user, board: board, progress: progress)
        }
    }

    /// Accepts anything a person might paste, including Pinterest short links.
    public func resolve(_ text: String) async throws -> BoardRef {
        if let ref = BoardRef.parse(text) { return ref }
        if BoardRef.isPinterestShortLink(text) {
            let s = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let url = URL(string: s.contains("://") ? s : "https://" + s) else { throw BoardImportError.notABoardLink }
            let (_, response): (Data, URLResponse)
            do { (_, response) = try await loader(LinkFetcher.request(url, accept: "text/html")) } catch { throw BoardImportError.network(error.localizedDescription) }
            if let final = response.url?.absoluteString, let ref = BoardRef.parse(final) { return ref }
            throw BoardImportError.profileNotBoard
        }
        if let url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)), let host = url.host?.lowercased(), host.contains("pinterest") {
            throw BoardImportError.profileNotBoard
        }
        throw BoardImportError.notABoardLink
    }

    // MARK: Are.na

    func fetchArena(slug: String, progress: @Sendable (Int, Int?) -> Void) async throws -> RemoteBoard {
        var entries: [RemoteBoard.Entry] = []
        var skipped: [String: Int] = [:]
        var name = slug, total: Int?
        var page = 1
        while page <= maxPages {
            guard let url = URL(string: "https://api.are.na/v2/channels/\(slug.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? slug)?per=\(pageSize)&page=\(page)") else { throw BoardImportError.notABoardLink }
            let (data, response): (Data, URLResponse)
            do { (data, response) = try await loader(Self.arenaRequest(url)) } catch { throw BoardImportError.network(error.localizedDescription) }
            if let http = response as? HTTPURLResponse {
                if http.statusCode == 404 { throw BoardImportError.notFoundOrPrivate("that Are.na channel") }
                if http.statusCode == 403, String(decoding: data.prefix(400), as: UTF8.self).localizedCaseInsensitiveContains("blocked") {
                    throw BoardImportError.blocked("Are.na is blocking automated requests from this connection right now. Try again later, or from another network.")
                }
                if http.statusCode == 401 || http.statusCode == 403 { throw BoardImportError.notFoundOrPrivate("that Are.na channel") }
                if http.statusCode == 429 { throw BoardImportError.blocked("Are.na is asking us to slow down. Try again in a minute.") }
                if !(200..<300).contains(http.statusCode) { throw BoardImportError.network("HTTP \(http.statusCode)") }
            }
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw BoardImportError.network("unexpected reply") }
            if page == 1 {
                name = (json["title"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? slug
                total = json["length"] as? Int
            }
            let blocks = json["contents"] as? [[String: Any]] ?? []
            for b in blocks {
                switch Self.arenaEntry(b) {
                case .entry(let e): entries.append(e)
                case .skipped(let why): skipped[why, default: 0] += 1
                }
            }
            progress(entries.count + skipped.values.reduce(0, +), total)
            if blocks.count < pageSize { break }
            if let total, entries.count + skipped.values.reduce(0, +) >= total { break }
            page += 1
        }
        guard !entries.isEmpty else { throw BoardImportError.empty("“\(name)”") }
        return RemoteBoard(ref: .arena(slug: slug), name: name, entries: entries, skipped: skipped, expectedTotal: total)
    }

    /// Are.na's public API is meant for programs: say what we are rather than pretending to be a browser.
    static func arenaRequest(_ url: URL) -> URLRequest {
        var r = URLRequest(url: url, timeoutInterval: 20)
        r.setValue("Stash/0.1 (open-source inspiration library; reads public channels)", forHTTPHeaderField: "User-Agent")
        r.setValue("application/json", forHTTPHeaderField: "Accept")
        return r
    }

    enum ArenaBlock { case entry(RemoteBoard.Entry), skipped(String) }

    static func arenaEntry(_ b: [String: Any]) -> ArenaBlock {
        let cls = (b["class"] as? String) ?? ""
        let id = b["id"].map { "\($0)" } ?? ""
        let blockPage = "https://www.are.na/block/\(id)"
        let title = (b["title"] as? String).flatMap { $0.trimmingCharacters(in: .whitespaces).isEmpty ? nil : $0 }
        let user = b["user"] as? [String: Any]
        let author = (user?["full_name"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? (user?["slug"] as? String)
        let source = (b["source"] as? [String: Any])?["url"] as? String
        func imageURLs(_ img: [String: Any]?) -> [String] {
            ["original", "large", "display"].compactMap { ((img?[$0] as? [String: Any])?["url"] as? String) }
        }
        switch cls {
        case "Image":
            let urls = imageURLs(b["image"] as? [String: Any])
            guard !urls.isEmpty else { return .skipped("images without a file") }
            return .entry(.init(mediaUrls: urls, pageUrl: source ?? blockPage, title: title, author: author))
        case "Link", "Media":
            guard let source else { return .skipped("links without an address") }
            return .entry(.init(mediaUrls: [], pageUrl: source, title: title, author: author))
        case "Attachment":
            let att = b["attachment"] as? [String: Any]
            let type = (att?["content_type"] as? String) ?? ""
            if let u = att?["url"] as? String, type.hasPrefix("image/") || type.hasPrefix("video/") || type == "application/pdf" {
                return .entry(.init(mediaUrls: [u], pageUrl: blockPage, title: title, author: author))
            }
            return .skipped("other attachments")
        case "Text": return .skipped("text blocks")
        case "Channel": return .skipped("channels inside it")
        default: return .skipped("unsupported blocks")
        }
    }

    // MARK: Pinterest

    func fetchPinterest(user: String, board: String, progress: @Sendable (Int, Int?) -> Void) async throws -> RemoteBoard {
        let enc = { (s: String) in s.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? s }
        guard let url = URL(string: "https://www.pinterest.com/\(enc(user))/\(enc(board)).rss") else { throw BoardImportError.notABoardLink }
        let (data, response): (Data, URLResponse)
        do { (data, response) = try await loader(LinkFetcher.request(url, accept: "application/rss+xml,text/xml,*/*")) } catch { throw BoardImportError.network(error.localizedDescription) }
        if let http = response as? HTTPURLResponse {
            if http.statusCode == 404 || http.statusCode == 403 { throw BoardImportError.notFoundOrPrivate("that Pinterest board") }
            if http.statusCode == 429 { throw BoardImportError.blocked("Pinterest is asking us to slow down. Try again in a few minutes.") }
            if !(200..<300).contains(http.statusCode) { throw BoardImportError.network("HTTP \(http.statusCode)") }
        }
        let feed = PinterestFeedParser.parse(data)
        guard !feed.pins.isEmpty else { throw BoardImportError.empty("That board") }
        let entries = feed.pins.map { RemoteBoard.Entry(mediaUrls: Self.pinImageCandidates($0.image), pageUrl: $0.link, title: $0.title, author: user) }
        progress(entries.count, entries.count)
        var out = RemoteBoard(ref: .pinterest(user: user, board: board), name: feed.title ?? board.replacingOccurrences(of: "-", with: " "), entries: entries)
        out.note = "Pinterest only shares a board's most recent pins publicly, so this brings in the latest \(entries.count)."
        return out
    }

    /// The feed carries a 236 px thumbnail; the same file exists at larger sizes under the same path.
    static func pinImageCandidates(_ thumb: String) -> [String] {
        guard let r = thumb.range(of: #"i\.pinimg\.com/\d+x/"#, options: .regularExpression) else { return [thumb] }
        let pre = String(thumb[..<r.lowerBound]) + "i.pinimg.com/", post = String(thumb[r.upperBound...])
        return ["\(pre)originals/\(post)", "\(pre)1200x/\(post)", "\(pre)736x/\(post)", thumb]
    }
}

struct PinterestFeed { var title: String?; var pins: [(link: String, title: String?, image: String)] }

/// Reads the board's public RSS feed.
final class PinterestFeedParser: NSObject, XMLParserDelegate {
    private var feed = PinterestFeed(title: nil, pins: [])
    private var inItem = false, element = "", text = ""
    private var link = "", title = "", desc = ""

    static func parse(_ data: Data) -> PinterestFeed {
        let p = PinterestFeedParser()
        let parser = XMLParser(data: data)
        parser.delegate = p
        parser.parse()
        return p.feed
    }

    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String] = [:]) {
        element = name; text = ""
        if name == "item" { inItem = true; link = ""; title = ""; desc = "" }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) { text += string }
    func parser(_ parser: XMLParser, foundCDATA data: Data) { text += String(decoding: data, as: UTF8.self) }

    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if inItem {
            switch name {
            case "link": link = t
            case "title": title = t
            case "description": desc = text
            case "item":
                inItem = false
                if let r = desc.range(of: #"src="([^"]+)""#, options: .regularExpression) {
                    let src = String(desc[r]).dropFirst(5).dropLast()
                    feed.pins.append((link: link, title: title.isEmpty ? nil : title, image: String(src)))
                }
            default: break
            }
        } else if name == "title", feed.title == nil, !t.isEmpty { feed.title = t }
        text = ""
    }
}
