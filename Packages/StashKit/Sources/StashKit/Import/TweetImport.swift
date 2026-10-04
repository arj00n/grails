import Foundation

/// Pictures, GIFs and videos from a public X post, read from the same public data endpoint tweet embeds use
/// (no login), with fxtwitter's public API as a second source.
extension BoardImporter {
    func fetchTweet(id: String, user: String?) async throws -> RemoteBoard {
        var first: Error?
        do { return try await fetchTweetSyndication(id: id, user: user) }
        catch let e as BoardImportError {
            if case .empty = e { throw e }
            first = e
        }
        do { return try await fetchTweetFxTwitter(id: id, user: user) }
        catch { throw first ?? error }
    }

    /// The embed endpoint wants a token derived from the post id.
    static func tweetToken(_ id: String) -> String {
        guard let n = Double(id) else { return "a" }
        let x = n / 1e15 * Double.pi
        let digits = Array("0123456789abcdefghijklmnopqrstuvwxyz")
        var whole = Int(x)
        var fraction = x - Double(whole)
        var out = whole == 0 ? "0" : ""
        while whole > 0 { out = String(digits[whole % 36]) + out; whole /= 36 }
        out += "."
        for _ in 0..<11 {
            fraction *= 36
            let d = Int(fraction)
            out.append(digits[d])
            fraction -= Double(d)
            if fraction == 0 { break }
        }
        return out.replacingOccurrences(of: "[0.]+", with: "", options: .regularExpression)
    }

    func fetchTweetSyndication(id: String, user: String?) async throws -> RemoteBoard {
        guard let url = URL(string: "https://cdn.syndication.twimg.com/tweet-result?id=\(id)&lang=en&token=\(Self.tweetToken(id))") else { throw BoardImportError.notABoardLink }
        let (data, response): (Data, URLResponse)
        do { (data, response) = try await loader(LinkFetcher.request(url, accept: "application/json")) } catch { throw BoardImportError.network(error.localizedDescription) }
        if let http = response as? HTTPURLResponse {
            if http.statusCode == 404 { throw BoardImportError.notFoundOrPrivate("that post") }
            if http.statusCode == 429 { throw BoardImportError.blocked("X is asking us to slow down. Try again in a few minutes.") }
            if !(200..<300).contains(http.statusCode) { throw BoardImportError.network("HTTP \(http.statusCode)") }
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw BoardImportError.notFoundOrPrivate("that post") }
        if (json["__typename"] as? String) == "TweetTombstone" { throw BoardImportError.notFoundOrPrivate("that post") }
        return try Self.tweetBoard(syndication: json, id: id, userHint: user)
    }

    static func tweetBoard(syndication json: [String: Any], id: String, userHint: String?) throws -> RemoteBoard {
        let account = json["user"] as? [String: Any]
        let handle = (account?["screen_name"] as? String) ?? userHint
        let name = (account?["name"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? handle
        let page = "https://x.com/\(handle ?? "i")/status/\(id)"
        let title = tweetTitle(json["text"] as? String, fallback: handle.map { "@\($0)" })
        var entries: [RemoteBoard.Entry] = []
        for m in json["mediaDetails"] as? [[String: Any]] ?? [] {
            let type = (m["type"] as? String) ?? ""
            var urls: [String] = []
            if type == "photo" {
                if let base = m["media_url_https"] as? String { urls = photoVariants(base) }
            } else if let variants = (m["video_info"] as? [String: Any])?["variants"] as? [[String: Any]] {
                urls = variants.filter { ($0["content_type"] as? String) == "video/mp4" }
                    .sorted { (($0["bitrate"] as? Int) ?? 0) > (($1["bitrate"] as? Int) ?? 0) }
                    .compactMap { $0["url"] as? String }
            }
            if !urls.isEmpty { entries.append(.init(mediaUrls: urls, pageUrl: page, title: title, author: name)) }
        }
        guard !entries.isEmpty else { throw BoardImportError.empty("That post") }
        return RemoteBoard(ref: .tweet(id: id, user: handle), name: title ?? "X post", entries: entries)
    }

    /// pbs.twimg.com serves the original upload as `name=orig`; the plain URL is a reduced copy.
    static func photoVariants(_ base: String) -> [String] {
        guard var c = URLComponents(string: base), c.host == "pbs.twimg.com" else { return [base] }
        let ext = (c.path as NSString).pathExtension
        c.path = (c.path as NSString).deletingPathExtension
        func variant(_ name: String) -> String {
            var v = c
            v.queryItems = [URLQueryItem(name: "format", value: ext.isEmpty ? "jpg" : ext), URLQueryItem(name: "name", value: name)]
            return v.string ?? base
        }
        return [variant("orig"), variant("4096x4096"), variant("large"), base]
    }

    /// The post's words without the trailing t.co links, trimmed to something that reads as a name.
    static func tweetTitle(_ text: String?, fallback: String?) -> String? {
        var t = (text ?? "").replacingOccurrences(of: #"https?://t\.co/\S+"#, with: "", options: .regularExpression)
        t = t.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { return fallback }
        return t.count > 100 ? String(t.prefix(100)).trimmingCharacters(in: .whitespaces) + "…" : t
    }

    func fetchTweetFxTwitter(id: String, user: String?) async throws -> RemoteBoard {
        guard let url = URL(string: "https://api.fxtwitter.com/\(user ?? "i")/status/\(id)") else { throw BoardImportError.notABoardLink }
        let (data, response): (Data, URLResponse)
        do { (data, response) = try await loader(LinkFetcher.request(url, accept: "application/json")) } catch { throw BoardImportError.network(error.localizedDescription) }
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw http.statusCode == 404 ? BoardImportError.notFoundOrPrivate("that post") : BoardImportError.network("HTTP \(http.statusCode)")
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let tweet = json["tweet"] as? [String: Any] else {
            throw BoardImportError.notFoundOrPrivate("that post")
        }
        let author = tweet["author"] as? [String: Any]
        let handle = (author?["screen_name"] as? String) ?? user
        let page = "https://x.com/\(handle ?? "i")/status/\(id)"
        let title = Self.tweetTitle(tweet["text"] as? String, fallback: handle.map { "@\($0)" })
        var entries: [RemoteBoard.Entry] = []
        for m in (tweet["media"] as? [String: Any])?["all"] as? [[String: Any]] ?? [] {
            guard let u = m["url"] as? String else { continue }
            let urls = (m["type"] as? String) == "photo" ? Self.photoVariants(u) : [u]
            entries.append(.init(mediaUrls: urls, pageUrl: page, title: title, author: author?["name"] as? String))
        }
        guard !entries.isEmpty else { throw BoardImportError.empty("That post") }
        return RemoteBoard(ref: .tweet(id: id, user: handle), name: title ?? "X post", entries: entries)
    }
}
