import Foundation

/// One board (or post, or pin) that the import panel is about to bring in: what it is called, how big it is, what it looks like.
public struct BoardCandidate: Identifiable, Codable, Sendable, Equatable {
    public enum Via: String, Codable, Sendable { case api, latest, browser, collector }

    /// Stable across re-pastes: "arena:slug", "pinterest:user/board", "pin:id", "x:id".
    public var id: String
    public var ref: BoardRef
    public var name: String
    public var count: Int?
    public var covers: [URL]
    /// Who owns it, when that isn't the person whose boards were listed.
    public var owner: String?
    /// The profile row this came from.
    public var parent: String?
    public var selected = true
    /// How much of it can be reached: everything (the API, or the in-app reader for a big Pinterest board), only the latest 50 (the widget, by choice or
    /// as the fallback), or everything via the browser extension.
    public var via: Via = .api
    /// Listed on a profile as secret: only readable signed in.
    public var secret: Bool?

    public init(ref: BoardRef, name: String, count: Int? = nil, covers: [URL] = [], owner: String? = nil, parent: String? = nil, selected: Bool = true, via: Via = .api) {
        self.id = Self.id(for: ref)
        self.ref = ref; self.name = name; self.count = count; self.covers = covers; self.owner = owner; self.parent = parent; self.selected = selected; self.via = via
    }

    /// How many pictures an import of this will bring: Pinterest without the browser stops at its latest 50.
    public var reachableCount: Int { via == .latest ? min(count ?? 0, 50) : (count ?? 0) }
    /// A Pinterest board over this size can't come whole from the widget.
    public static let widgetLimit = 50

    public static func id(for ref: BoardRef) -> String {
        switch ref {
        case .arena(let slug): "arena:\(slug)"
        case .pinterest(let user, let board): "pinterest:\(user)/\(board)"
        case .pinterestPin(let id): "pin:\(id)"
        case .tweet(let id, _): "x:\(id)"
        }
    }
}

/// What is known about a board before it is imported: enough to show a row made of pictures.
public enum BoardPreflight {
    public static func check(_ ref: BoardRef, loader: @escaping LinkFetcher.Loader = { try await URLSession.shared.data(for: $0) }) async throws -> BoardCandidate {
        switch ref {
        case .arena(let slug): return try await arena(slug, loader: loader)
        case .pinterest(let user, let board):
            let s = try await PinterestBoardWidget.summary(user: user, board: board, loader: loader)
            let partial = (s.pinCount ?? 0) > s.pins.count
            return BoardCandidate(ref: ref, name: s.name, count: s.pinCount ?? s.pins.count, covers: s.covers, via: partial ? .collector : .api)
        case .pinterestPin, .tweet:
            let board = try await BoardImporter(loader: loader).fetch(ref)
            return BoardCandidate(ref: ref, name: board.name, count: board.entries.count, covers: board.entries.prefix(3).compactMap { $0.mediaUrls.first.flatMap(URL.init(string:)) })
        }
    }

    static func arena(_ slug: String, loader: LinkFetcher.Loader) async throws -> BoardCandidate {
        let enc = slug.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? slug
        guard let url = URL(string: "https://api.are.na/v2/channels/\(enc)?per=3&page=1") else { throw BoardImportError.notABoardLink }
        let (data, response): (Data, URLResponse)
        do { (data, response) = try await loader(BoardImporter.arenaRequest(url)) } catch { throw BoardImportError.network(error.localizedDescription) }
        if let http = response as? HTTPURLResponse {
            if http.statusCode == 404 || http.statusCode == 401 { throw BoardImportError.notFoundOrPrivate("that Are.na channel") }
            if http.statusCode == 403 {
                if String(decoding: data.prefix(400), as: UTF8.self).localizedCaseInsensitiveContains("blocked") {
                    throw BoardImportError.blocked("Are.na is blocking automated requests from this connection right now. Try again later, or from another network.")
                }
                throw BoardImportError.notFoundOrPrivate("that Are.na channel")
            }
            if http.statusCode == 429 { throw BoardImportError.blocked("Are.na is asking us to slow down. Try again in a minute.") }
            if !(200..<300).contains(http.statusCode) { throw BoardImportError.network("HTTP \(http.statusCode)") }
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw BoardImportError.network("unexpected reply") }
        let title = (json["title"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? slug
        let covers = (json["contents"] as? [[String: Any]] ?? []).compactMap { b -> URL? in
            guard let image = b["image"] as? [String: Any] else { return nil }
            for k in ["thumb", "square", "display"] { if let u = (image[k] as? [String: Any])?["url"] as? String { return URL(string: u) } }
            return nil
        }
        return BoardCandidate(ref: .arena(slug: slug), name: title, count: json["length"] as? Int, covers: covers)
    }
}

/// An Are.na person's channels, from the public v3 API (the older one answers guests with 401).
public struct ArenaDirectory: Sendable {
    let loader: LinkFetcher.Loader
    /// Guests may make 30 requests a minute: stay under it.
    public var pause: Duration = .milliseconds(2100)

    public init(loader: @escaping LinkFetcher.Loader = { try await URLSession.shared.data(for: $0) }) { self.loader = loader }

    /// Channels the person made come first and ticked; channels they only connected to follow, unticked, named for their owner.
    public func channels(user: String) async throws -> [BoardCandidate] {
        let enc = user.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? user
        var owned: [BoardCandidate] = [], others: [BoardCandidate] = []
        var page = 1
        while page <= 60 {
            guard let url = URL(string: "https://api.are.na/v3/users/\(enc)/contents?type=Channel&per=100&page=\(page)") else { throw BoardImportError.notABoardLink }
            let (data, response): (Data, URLResponse)
            do { (data, response) = try await loader(BoardImporter.arenaRequest(url)) } catch { throw BoardImportError.network(error.localizedDescription) }
            if let http = response as? HTTPURLResponse {
                if http.statusCode == 404 { throw BoardImportError.notFoundOrPrivate("that Are.na profile") }
                if http.statusCode == 403 || http.statusCode == 429 { throw BoardImportError.blocked("Are.na is asking us to slow down. Try again in a minute.") }
                if !(200..<300).contains(http.statusCode) { throw BoardImportError.network("HTTP \(http.statusCode)") }
            }
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw BoardImportError.network("unexpected reply") }
            for c in json["data"] as? [[String: Any]] ?? [] {
                guard let slug = c["slug"] as? String, (c["visibility"] as? String ?? "public") != "private" else { continue }
                let owner = (c["owner"] as? [String: Any])?["slug"] as? String
                let isOwn = owner == nil || owner?.lowercased() == user.lowercased()
                let count = ((c["counts"] as? [String: Any])?["contents"] as? Int) ?? ((c["counts"] as? [String: Any])?["blocks"] as? Int)
                let item = BoardCandidate(ref: .arena(slug: slug), name: (c["title"] as? String) ?? slug, count: count, owner: isOwn ? nil : owner, parent: "arena-user:\(user)", selected: isOwn)
                if isOwn { owned.append(item) } else { others.append(item) }
            }
            let meta = json["meta"] as? [String: Any]
            guard meta?["has_more_pages"] as? Bool == true else { break }
            page += 1
            try await Task.sleep(for: pause)
        }
        return owned + others
    }
}


/// Which explanation, if any, the import screen shows under the rows (one at a time, the more pressing first).
public enum ImportBannerRule {
    public enum Variant: Equatable, Sendable {
        /// A big Pinterest board: the whole board is read in the app by default, or just its latest 50 if the person chooses.
        case wholeBoard(latestOnly: Bool)
        /// A secret board and no Pinterest sign-in yet.
        case secret
    }

    /// `boards` are the ready boards (rows and ticked children); `secretRows` counts rows that came back secret; `latestOnly` is the person's toggle.
    public static func variant(boards: [BoardCandidate], secretRows: Int, signedIn: Bool, latestOnly: Bool) -> Variant? {
        if secretRows > 0, !signedIn { return .secret }
        let big = boards.contains { b in
            if case .pinterest = b.ref { return (b.count ?? 0) > BoardCandidate.widgetLimit && (b.via == .collector || b.via == .latest) }
            return false
        }
        return big ? .wholeBoard(latestOnly: latestOnly) : nil
    }
}
