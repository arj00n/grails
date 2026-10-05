import Foundation

/// A public Pinterest board through the widget endpoint Pinterest's own embeds use: its name, its total, and the latest 50 pins in the
/// same shape as `PinterestPins` knows. No login; anything more needs the browser extension.
enum PinterestBoardWidget {
    struct Summary {
        var name: String
        var pinCount: Int?
        var covers: [URL]
        var pins: [[String: Any]]
    }

    static func summary(user: String, board: String, loader: LinkFetcher.Loader) async throws -> Summary {
        let enc = { (s: String) in s.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? s }
        guard let url = URL(string: "https://widgets.pinterest.com/v3/pidgets/boards/\(enc(user))/\(enc(board))/pins/") else { throw BoardImportError.notABoardLink }
        let (data, response): (Data, URLResponse)
        do { (data, response) = try await loader(LinkFetcher.request(url, accept: "application/json")) } catch { throw BoardImportError.network(error.localizedDescription) }
        if let http = response as? HTTPURLResponse {
            if http.statusCode == 404 || http.statusCode == 403 { throw BoardImportError.notFoundOrPrivate("that Pinterest board") }
            if http.statusCode == 429 { throw BoardImportError.blocked("Pinterest is asking us to slow down. Try again in a few minutes.") }
            if !(200..<300).contains(http.statusCode) { throw BoardImportError.network("HTTP \(http.statusCode)") }
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let d = json["data"] as? [String: Any],
              let pins = d["pins"] as? [[String: Any]], let b = d["board"] as? [String: Any] else { throw BoardImportError.notFoundOrPrivate("that Pinterest board") }
        let covers = pins.prefix(3).compactMap { pin -> URL? in
            guard let images = pin["images"] as? [String: Any], let u = (images["236x"] as? [String: Any])?["url"] as? String ?? images.values.compactMap({ ($0 as? [String: Any])?["url"] as? String }).first else { return nil }
            return URL(string: u)
        }
        return Summary(name: (b["name"] as? String) ?? board, pinCount: b["pin_count"] as? Int, covers: covers, pins: pins)
    }

    static func read(user: String, board: String, loader: LinkFetcher.Loader) async throws -> RemoteBoard {
        let s = try await summary(user: user, board: board, loader: loader)
        var entries: [RemoteBoard.Entry] = []
        for pin in s.pins {
            guard let id = pin["id"].map({ "\($0)" }) else { continue }
            entries += PinterestPins.entries(for: pin, id: id, authorFallback: user)
        }
        guard !entries.isEmpty else { throw BoardImportError.empty("That board") }
        var out = RemoteBoard(ref: .pinterest(user: user, board: board), name: s.name, entries: entries)
        out.expectedTotal = s.pinCount
        if let total = s.pinCount, total > entries.count { out.note = "Latest \(entries.count) of \(total)" }
        return out
    }
}
