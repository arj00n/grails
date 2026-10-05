import AppKit
import GrailsKit
import WebKit

/// Reads a whole public Pinterest board inside the app, the way the board's own page does: a web view (never on screen) loads the board once,
/// then asks Pinterest's board feed for it page by page, 100 pins at a time, a little over a second apart. Nothing is installed, no browser or
/// Finder window opens. The web view keeps nothing (a throwaway store, no sign-in); Grails reads only the JSON its own requests return.
@MainActor
final class PinterestCollector: NSObject, WKNavigationDelegate {
    static let shared = PinterestCollector()

    /// Where Pinterest is. Dev demos point it at a stand-in server.
    var origin = URL(string: "https://www.pinterest.com")!
    static let pageSize = 100

    private var web: WKWebView?
    private var navigation: CheckedContinuation<Void, Error>?
    private let world = WKContentWorld.world(name: "grails")


    // MARK: The web view

    private func view() -> WKWebView {
        if let web { return web }
        let cfg = WKWebViewConfiguration()
        cfg.websiteDataStore = .nonPersistent()          // nothing is kept between boards: no cookies, no sign-in
        cfg.applicationNameForUserAgent = "Grails/\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0")"
        let v = WKWebView(frame: NSRect(x: 0, y: 0, width: 1, height: 1), configuration: cfg)
        v.navigationDelegate = self
        v.alphaValue = 0.01
        // inside the visible window, so WebKit treats the page as visible and doesn't slow it down
        NSApp.windows.first(where: { $0.isVisible })?.contentView?.addSubview(v)
        web = v
        return v
    }

    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { Task { @MainActor in self.finish(nil) } }
    nonisolated func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { Task { @MainActor in self.finish(error) } }
    nonisolated func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { Task { @MainActor in self.finish(error) } }

    private func finish(_ error: Error?) {
        guard let c = navigation else { return }
        navigation = nil
        if let error { c.resume(throwing: error) } else { c.resume() }
    }

    private var navigationID = 0

    private func load(_ url: URL) async throws {
        let v = view()
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
            navigationID += 1
            let id = navigationID
            navigation = c
            v.load(URLRequest(url: url))
            // a page that never finishes shouldn't hang the import
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(40))
                if let self, self.navigationID == id { self.finish(BoardImportError.network("Pinterest took too long to answer")) }
            }
        }
        // let the page's own scripts settle (the board's id and the first cookies)
        try? await Task.sleep(for: .milliseconds(600))
    }

    private func run(_ js: String, _ args: [String: Any] = [:]) async throws -> [String: Any] {
        let r = try await view().callAsyncJavaScript(js, arguments: args, in: nil, contentWorld: world)
        return r as? [String: Any] ?? [:]
    }

    // MARK: A board

    /// The reader ImportRunner uses for boards the widget can't give whole.
    nonisolated static func reader() -> PageReader {
        { board, cursor, deliver in try await PinterestCollector.shared.read(board, cursor: cursor, deliver: deliver) }
    }

    func read(_ board: BoardCandidate, cursor: String?, deliver: @Sendable ([RemoteBoard.Entry], String?) async -> Void) async throws -> CollectorOutcome {
        guard case .pinterest(let user, let slug) = board.ref else { return .changed }
        let activity = ProcessInfo.processInfo.beginActivity(options: .userInitiated, reason: "Reading a Pinterest board")
        defer { ProcessInfo.processInfo.endActivity(activity) }
        let enc = { (s: String) in s.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? s }
        try await load(origin.appendingPathComponent(enc(user)).appendingPathComponent(enc(slug)).appendingPathComponent(""))

        let info = try await run(Self.bootstrapJS)
        guard let boardID = info["board"] as? String else { return cursor == nil ? .gated : .changed }

        var plan = CollectorPlan()
        var bookmark = cursor
        while !Task.isCancelled {
            let reply = try await run(Self.feedJS, ["boardID": boardID, "bookmark": bookmark ?? NSNull(), "pageSize": Self.pageSize])
            let status = (reply["status"] as? Int) ?? 0
            let page = PinterestBoardFeed.parsePage(reply, author: user)
            switch plan.record(status: status, page: page, retryAfter: (reply["retryAfter"] as? String).flatMap(Int.init), jitter: Double.random(in: 0...1)) {
            case .next(let delay):
                if let page, status == 200 { await deliver(page.entries, page.bookmark); bookmark = page.bookmark }
                try await Task.sleep(for: .seconds(delay))
            case .done:
                if let page, status == 200 { await deliver(page.entries, nil) }
                // a board with sections shows only its loose pins in the main feed: each section's pins come after
                await readSections(boardID: boardID, user: user, deliver: deliver)
                return .complete
            case .wait(let seconds): try await Task.sleep(for: .seconds(seconds))
            case .gated: return .gated
            case .changed: return .changed
            }
        }
        return .complete
    }

    /// The pins filed in the board's sections, section by section (best effort: a board without sections, or an answer Pinterest changed, adds nothing).
    private func readSections(boardID: String, user: String, deliver: @Sendable ([RemoteBoard.Entry], String?) async -> Void) async {
        guard let list = try? await run(Self.sectionsJS, ["boardID": boardID]), (list["status"] as? Int) == 200, let ids = list["ids"] as? [String] else { return }
        for id in ids.prefix(200) where !Task.isCancelled {
            var bookmark: String?
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(1200))
                guard let reply = try? await run(Self.sectionPinsJS, ["sectionID": id, "bookmark": bookmark ?? NSNull(), "pageSize": Self.pageSize]),
                      (reply["status"] as? Int) == 200, let page = PinterestBoardFeed.parsePage(reply, author: user) else { break }
                await deliver(page.entries, nil)
                guard !page.ended, page.rawCount > 0 else { break }
                bookmark = page.bookmark
            }
        }
    }

    // MARK: A person's boards

    /// The boards on a profile, 100 a request, read the same way (no browser needed).
    func listBoards(user: String) async throws -> [PinterestBoardFeed.ListedBoard] {
        let enc = user.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? user
        try await load(origin.appendingPathComponent(enc).appendingPathComponent(""))
        var out: [PinterestBoardFeed.ListedBoard] = []
        var bookmark: String?
        for _ in 0..<40 {
            let reply = try await run(Self.boardsJS, ["user": user, "bookmark": bookmark ?? NSNull(), "pageSize": Self.pageSize])
            guard (reply["status"] as? Int) == 200 else { break }
            let r = PinterestBoardFeed.parseBoards(reply)
            out += r.boards
            guard let next = r.bookmark else { break }
            bookmark = next
            try await Task.sleep(for: .milliseconds(1200))
        }
        return out
    }

    // MARK: Scripts (run in Grails' own content world; the page can't see or change them)

    private static let bootstrapJS = """
    return { board: (document.documentElement.innerHTML.match(/board_id\\\\?",\\\\?"(\\d+)/) || [])[1] || null };
    """

    private static let headers = """
    {"X-Requested-With": "XMLHttpRequest", "Accept": "application/json", "X-CSRFToken": csrf, "X-Pinterest-AppState": "active", "X-Pinterest-PWS-Handler": "www/[username]/[slug].js"}
    """

    private static let feedJS = """
    const options = {board_id: boardID, board_url: location.pathname, field_set_key: "react_grid_pin", filter_section_pins: false, is_react: true, prepend: false, page_size: pageSize, redux_normalize_feed: true, add_vase: true};
    if (bookmark) options.bookmarks = [bookmark];
    const csrf = (document.cookie.match(/csrftoken=([^;]+)/) || [])[1] || "";
    const r = await fetch("/resource/BoardFeedResource/get/?source_url=" + encodeURIComponent(location.pathname) + "&data=" + encodeURIComponent(JSON.stringify({options, context: {}})),
        {headers: \(headers), credentials: "include"});
    let j = null; try { j = await r.json(); } catch (e) {}
    const rr = (j && j.resource_response) || {};
    const rows = rr.data || [];
    const data = rows.filter(p => p && p.type === "pin").map(p => ({type: "pin", id: p.id, description: p.description, link: p.link,
        pinner: p.pinner ? {username: p.pinner.username, full_name: p.pinner.full_name} : null, images: p.images, videos: p.videos, story_pin_data: p.story_pin_data}));
    return {status: r.status, data: data, raw: rows.length, bookmark: rr.bookmark || null, retryAfter: r.headers.get("retry-after")};
    """

    private static let sectionsJS = """
    const csrf = (document.cookie.match(/csrftoken=([^;]+)/) || [])[1] || "";
    const options = {board_id: boardID, redux_normalize_feed: true};
    const r = await fetch("/resource/BoardSectionsResource/get/?source_url=" + encodeURIComponent(location.pathname) + "&data=" + encodeURIComponent(JSON.stringify({options, context: {}})),
        {headers: \(headers), credentials: "include"});
    let j = null; try { j = await r.json(); } catch (e) {}
    const rr = (j && j.resource_response) || {};
    return {status: r.status, ids: (rr.data || []).filter(x => x && x.id).map(x => String(x.id))};
    """

    private static let sectionPinsJS = """
    const options = {section_id: sectionID, page_size: pageSize, redux_normalize_feed: true};
    if (bookmark) options.bookmarks = [bookmark];
    const csrf = (document.cookie.match(/csrftoken=([^;]+)/) || [])[1] || "";
    const r = await fetch("/resource/BoardSectionPinsResource/get/?source_url=" + encodeURIComponent(location.pathname) + "&data=" + encodeURIComponent(JSON.stringify({options, context: {}})),
        {headers: \(headers), credentials: "include"});
    let j = null; try { j = await r.json(); } catch (e) {}
    const rr = (j && j.resource_response) || {};
    const rows = rr.data || [];
    const data = rows.filter(p => p && p.type === "pin").map(p => ({type: "pin", id: p.id, description: p.description, link: p.link,
        pinner: p.pinner ? {username: p.pinner.username, full_name: p.pinner.full_name} : null, images: p.images, videos: p.videos, story_pin_data: p.story_pin_data}));
    return {status: r.status, data: data, raw: rows.length, bookmark: rr.bookmark || null};
    """

    private static let boardsJS = """
    const options = {username: user, page_size: pageSize, privacy_filter: "all", sort: "last_pinned_to", field_set_key: "profile_grid_item", group_by: "visibility", include_archived: true, redux_normalize_feed: true};
    if (bookmark) options.bookmarks = [bookmark];
    const csrf = (document.cookie.match(/csrftoken=([^;]+)/) || [])[1] || "";
    const r = await fetch("/resource/BoardsResource/get/?source_url=" + encodeURIComponent("/" + user + "/") + "&data=" + encodeURIComponent(JSON.stringify({options, context: {}})),
        {headers: \(headers), credentials: "include"});
    let j = null; try { j = await r.json(); } catch (e) {}
    const rr = (j && j.resource_response) || {};
    const data = (rr.data || []).filter(b => b && b.name && b.url).map(b => ({name: b.name, url: b.url, pin_count: b.pin_count, privacy: b.privacy, image_cover_url: b.image_cover_url}));
    return {status: r.status, data: data, bookmark: rr.bookmark || null};
    """
}
