import Foundation
import Testing
@testable import StashKit

/// Are.na and Pinterest, with every network call stubbed.
@Suite struct BoardLinkTests {
    @Test func recognisesAreNaChannels() {
        #expect(BoardRef.parse("https://www.are.na/charles-broskoski/arena-influences") == .arena(slug: "arena-influences"))
        #expect(BoardRef.parse("are.na/charles-broskoski/arena-influences/") == .arena(slug: "arena-influences"))
        #expect(BoardRef.parse("  https://www.are.na/channels/arena-influences?foo=1 ") == .arena(slug: "arena-influences"))
        #expect(BoardRef.parse("https://www.are.na/block/12345") == nil)
        #expect(BoardRef.parse("https://www.are.na/explore") == nil)
        #expect(BoardRef.parse("https://www.are.na/charles-broskoski") == nil)           // a profile, not a channel
    }

    @Test func recognisesPinterestBoards() {
        #expect(BoardRef.parse("https://www.pinterest.com/pinterest/pinterest-presents/") == .pinterest(user: "pinterest", board: "pinterest-presents"))
        #expect(BoardRef.parse("https://in.pinterest.com/some.one/dark-interiors/section-x/") == .pinterest(user: "some.one", board: "dark-interiors"))
        #expect(BoardRef.parse("pinterest.co.uk/ana/shoes") == .pinterest(user: "ana", board: "shoes"))
        #expect(BoardRef.parse("https://www.pinterest.com/pin/12345/") == nil)           // a single pin
        #expect(BoardRef.parse("https://www.pinterest.com/ana/") == nil)                 // a profile
        #expect(BoardRef.parse("https://www.pinterest.com/ana/_saved/") == nil)
        #expect(BoardRef.parse("https://example.com/ana/shoes") == nil)
        #expect(BoardRef.parse("hello") == nil)
        #expect(BoardRef.isPinterestShortLink("https://pin.it/abc123"))
        #expect(!BoardRef.isPinterestShortLink("https://www.pinterest.com/a/b"))
    }

    @Test func pinImagesUpgradeToLargerSizesWithFallbacks() {
        let c = BoardImporter.pinImageCandidates("https://i.pinimg.com/236x/f2/c8/3e/abc.jpg")
        #expect(c == ["https://i.pinimg.com/originals/f2/c8/3e/abc.jpg", "https://i.pinimg.com/1200x/f2/c8/3e/abc.jpg",
                      "https://i.pinimg.com/736x/f2/c8/3e/abc.jpg", "https://i.pinimg.com/236x/f2/c8/3e/abc.jpg"])
        #expect(BoardImporter.pinImageCandidates("https://example.com/x.jpg") == ["https://example.com/x.jpg"])
    }
}

@Suite struct BoardImportTests {
    static func response(_ url: URL, _ code: Int = 200, type: String = "application/json") -> URLResponse {
        HTTPURLResponse(url: url, statusCode: code, httpVersion: nil, headerFields: ["Content-Type": type])!
    }

    static func arenaPage(_ blocks: [[String: Any]], length: Int, title: String = "Dark rooms") -> Data {
        try! JSONSerialization.data(withJSONObject: ["title": title, "length": length, "contents": blocks])
    }

    static func image(_ id: Int, _ title: String = "", source: String? = nil) -> [String: Any] {
        var b: [String: Any] = ["id": id, "class": "Image", "title": title, "user": ["full_name": "Ana Rao", "slug": "ana"],
                                "image": ["original": ["url": "https://cdn.test/img\(id).png"], "large": ["url": "https://cdn.test/img\(id)-l.png"]]]
        if let source { b["source"] = ["url": source] }
        return b
    }

    /// A router for the stubbed network: Are.na pages, images, link pages.
    func network(pages: [Data], png: Data, failing: Set<String> = [], counter: Counter = Counter()) -> LinkFetcher.Loader {
        { req in
            let url = req.url!
            counter.add(url.absoluteString)
            if url.host == "api.are.na" {
                let page = Int(URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!.first { $0.name == "page" }!.value!)!
                return (pages[min(page, pages.count) - 1], Self.response(url))
            }
            if failing.contains(url.absoluteString) { return (Data(), Self.response(url, 404)) }
            if url.host == "cdn.test" || url.host == "i.pinimg.com" { return (png, Self.response(url, type: "image/png")) }
            return (Data("<html><head><title>A page</title></head></html>".utf8), Self.response(url, type: "text/html"))
        }
    }

    final class Counter: @unchecked Sendable {
        private var seen: [String] = []; private let lock = NSLock()
        func add(_ s: String) { lock.lock(); seen.append(s); lock.unlock() }
        var all: [String] { lock.lock(); defer { lock.unlock() }; return seen }
    }

    func setup() throws -> (LibraryStore, Data) {
        let (store, _) = try TestSupport.newStore(handle: "ana")
        let png = try Data(contentsOf: TestSupport.makePNG(in: TestSupport.tempDir(), name: "x", rgb: (0.1, 0.5, 0.9)))
        return (store, png)
    }

    @Test func readsEveryPageAndMapsBlockTypes() async throws {
        let (_, png) = try setup()
        let blocks: [[String: Any]] = [
            Self.image(1, "A chair", source: "https://shop.test/chair"),
            ["id": 2, "class": "Link", "title": "An essay", "source": ["url": "https://essay.test/a"], "user": ["slug": "ben"]],
            ["id": 3, "class": "Text", "content": "words"],
            ["id": 4, "class": "Channel", "title": "nested"],
            ["id": 5, "class": "Attachment", "title": "Spec", "attachment": ["url": "https://cdn.test/spec.pdf", "content_type": "application/pdf"]],
            ["id": 6, "class": "Attachment", "attachment": ["url": "https://cdn.test/a.zip", "content_type": "application/zip"]],
            ["id": 7, "class": "Media", "title": "A film", "source": ["url": "https://youtu.be/x"]],
            ["id": 8, "class": "Image", "image": [:]],
            Self.image(9),
        ]
        let pages = stride(from: 0, to: blocks.count, by: 4).map { Self.arenaPage(Array(blocks[$0..<min($0 + 4, blocks.count)]), length: blocks.count) }
        var importer = BoardImporter(loader: network(pages: pages, png: png))
        importer.pageSize = 4
        let board = try await importer.fetch(.arena(slug: "dark-rooms"))
        #expect(board.name == "Dark rooms" && board.expectedTotal == 9)
        #expect(board.entries.count == 5)                                                  // image, link, pdf, media, image
        #expect(board.entries[0] == .init(mediaUrls: ["https://cdn.test/img1.png", "https://cdn.test/img1-l.png"], pageUrl: "https://shop.test/chair", title: "A chair", author: "Ana Rao"))
        #expect(board.entries[1].mediaUrls.isEmpty && board.entries[1].pageUrl == "https://essay.test/a" && board.entries[1].author == "ben")
        #expect(board.entries[2].mediaUrls == ["https://cdn.test/spec.pdf"])
        #expect(board.entries.last?.pageUrl == "https://www.are.na/block/9" && board.entries.last?.title == nil)   // no source ⇒ links back to the block
        #expect(board.skipped == ["text blocks": 1, "channels inside it": 1, "other attachments": 1, "images without a file": 1])
    }

    @Test func importsIntoACollectionAndAReimportOnlyAddsWhatIsNew() async throws {
        let (store, png) = try setup()
        let counter = Counter()
        let blocks = [Self.image(1, "One"), Self.image(2, "Two"), ["id": 3, "class": "Link", "title": "A page", "source": ["url": "https://page.test/x"]] as [String: Any]]
        let loader = network(pages: [Self.arenaPage(blocks, length: 3)], png: png, counter: counter)
        let importer = BoardImporter(loader: loader)
        let service = LibraryCaptureService(fetcher: LinkFetcher(load: loader), download: loader, store: { store })
        let board = try await importer.fetch(.arena(slug: "dark-rooms"))

        final class Progress: @unchecked Sendable { var last = (0, 0) }
        let p = Progress()
        let s1 = try await importer.run(board, into: store, service: service, progress: { p.last = ($0, $1) })
        #expect(s1.added == 3 && s1.failed == 0 && s1.alreadyHad == 0 && s1.collectionName == "Dark rooms")
        #expect(p.last == (3, 3))
        let colls = try await store.index.collections().filter { $0.name == "Dark rooms" }
        #expect(colls.count == 1)
        var q = ItemQuery(); q.collectionId = colls[0].id
        #expect(try await store.index.count(q) == 3)
        let one = try await store.index.query(q).first { $0.name == "One" }
        let oneId = try #require(one).id
        let item = try #require(try await store.item(id: oneId))
        #expect(item.source?.author == "Ana Rao" && item.source?.pageUrl == "https://www.are.na/block/1" && item.source?.url == "https://cdn.test/img1.png")

        // importing the same channel again: nothing new, same collection, nothing duplicated
        let s2 = try await importer.run(board, into: store, service: service)
        #expect(s2.added == 0 && s2.alreadyHad == 3)
        #expect(try await store.index.collections().filter { $0.name == "Dark rooms" }.count == 1)
        #expect(try await store.index.count(q) == 3)
        #expect(try await store.index.count(ItemQuery()) == 3)
    }

    @Test func aFailingFileFallsBackToTheNextSizeAndCountsRealFailures() async throws {
        let (store, png) = try setup()
        let blocks = [Self.image(1), Self.image(2), Self.image(3)]
        // img1: original 404 but the large version works; img2: both fail; img3: fine
        let loader = network(pages: [Self.arenaPage(blocks, length: 3)], png: png, failing: ["https://cdn.test/img1.png", "https://cdn.test/img2.png", "https://cdn.test/img2-l.png"])
        let service = LibraryCaptureService(fetcher: LinkFetcher(load: loader), download: loader, store: { store })
        let importer = BoardImporter(loader: loader)
        let summary = try await importer.run(try await importer.fetch(.arena(slug: "x")), into: store, service: service)
        #expect(summary.added == 2 && summary.failed == 1)
        #expect(summary.headline == "Added 2 items to “Dark rooms”: 1 failed")
    }

    @Test func errorsAreSpecific() async throws {
        let (_, png) = try setup()
        func importer(_ code: Int) -> BoardImporter {
            BoardImporter(loader: { req in (Data(), Self.response(req.url!, code)) })
        }
        await #expect(throws: BoardImportError.notFoundOrPrivate("that Are.na channel")) { _ = try await importer(404).fetch(.arena(slug: "nope")) }
        await #expect(throws: BoardImportError.notFoundOrPrivate("that Are.na channel")) { _ = try await importer(401).fetch(.arena(slug: "secret")) }
        await #expect(throws: BoardImportError.notFoundOrPrivate("that Pinterest board")) { _ = try await importer(404).fetch(.pinterest(user: "a", board: "b")) }
        await #expect(throws: BoardImportError.self) { _ = try await importer(429).fetch(.arena(slug: "x")) }
        let blocked = BoardImporter(loader: { req in (Data("403 - Automated access blocked".utf8), Self.response(req.url!, 403)) })
        do { _ = try await blocked.fetch(.arena(slug: "x")); Issue.record("should have thrown") }
        catch let e as BoardImportError { if case .blocked = e {} else { Issue.record("wrong error \(e)") } }
        let ua = BoardImporter.arenaRequest(URL(string: "https://api.are.na/v2/channels/x")!).value(forHTTPHeaderField: "User-Agent") ?? ""
        #expect(ua.hasPrefix("Stash/") && !ua.contains("Mozilla"))
        let empty = BoardImporter(loader: { req in (Self.arenaPage([], length: 0), Self.response(req.url!)) })
        await #expect(throws: BoardImportError.empty("“Dark rooms”")) { _ = try await empty.fetch(.arena(slug: "x")) }
        await #expect(throws: BoardImportError.notABoardLink) { _ = try await empty.resolve("hello world") }
        await #expect(throws: BoardImportError.profileNotBoard) { _ = try await empty.resolve("https://www.pinterest.com/ana/") }
        _ = png
    }

    @Test func pinterestFeedBecomesEntriesWithBigImages() async throws {
        let (store, png) = try setup()
        let rss = """
        <?xml version="1.0" encoding="utf-8"?><rss xmlns:atom="http://www.w3.org/2005/Atom" version="2.0"><channel>
        <title>Dark Interiors</title><link>https://www.pinterest.com/ana/dark-interiors</link>
        <item><title> </title><link>https://www.pinterest.com/pin/111/</link>
        <description>&lt;a href=&quot;https://www.pinterest.com/pin/111/&quot;&gt;&lt;img src=&quot;https://i.pinimg.com/236x/aa/bb/cc/one.jpg&quot;&gt;&lt;/a&gt; </description></item>
        <item><title>Lamp</title><link>https://www.pinterest.com/pin/222/</link>
        <description>&lt;img src=&quot;https://i.pinimg.com/236x/dd/ee/ff/two.jpg&quot;&gt;</description></item>
        <item><title>No image here</title><link>https://www.pinterest.com/pin/333/</link><description>text only</description></item>
        </channel></rss>
        """
        let counter = Counter()
        let loader: LinkFetcher.Loader = { req in
            let url = req.url!; counter.add(url.absoluteString)
            if url.host == "www.pinterest.com" { return (Data(rss.utf8), Self.response(url, type: "application/rss+xml")) }
            if url.absoluteString.contains("/originals/dd/ee/ff/two.jpg") { return (Data(), Self.response(url, 404)) }     // originals missing ⇒ next size
            return (png, Self.response(url, type: "image/png"))
        }
        let importer = BoardImporter(loader: loader)
        let service = LibraryCaptureService(fetcher: LinkFetcher(load: loader), download: loader, store: { store })
        let board = try await importer.fetch(.pinterest(user: "ana", board: "dark-interiors"))
        #expect(board.name == "Dark Interiors" && board.entries.count == 2)
        #expect(board.entries[0].title == nil && board.entries[1].title == "Lamp")
        #expect(board.entries[0].pageUrl == "https://www.pinterest.com/pin/111/")
        #expect(board.note?.contains("most recent pins") == true)
        let summary = try await importer.run(board, into: store, service: service)
        #expect(summary.added == 2)
        #expect(counter.all.contains("https://i.pinimg.com/1200x/dd/ee/ff/two.jpg"))     // fell back from originals
        #expect(counter.all.contains("https://i.pinimg.com/originals/aa/bb/cc/one.jpg"))
    }

    @Test func resolvesAPinterestShortLink() async throws {
        let loader: LinkFetcher.Loader = { req in
            let final = URL(string: "https://www.pinterest.com/ana/dark-interiors/")!
            return (Data(), HTTPURLResponse(url: final, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        let ref = try await BoardImporter(loader: loader).resolve("https://pin.it/abc")
        #expect(ref == .pinterest(user: "ana", board: "dark-interiors"))
    }
}
