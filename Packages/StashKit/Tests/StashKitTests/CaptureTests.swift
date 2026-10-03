import Foundation
import Network
import Security
import Testing
@testable import StashKit

@Suite struct HTMLMetaTests {
    @Test func openGraphWithRelativeImageAndEntities() {
        let html = """
        <html><head>
        <title>Fallback title</title>
        <meta property="og:title" content="Tom &amp; Jerry&#39;s &quot;Dhaba&quot;">
        <meta property='og:site_name' content='Foodie'>
        <meta property="og:description" content="Best biryani in town">
        <meta property="og:image" content="/img/hero.jpg?v=2">
        <meta name="author" content="Ana">
        </head><body>ignored</body></html>
        """
        let m = HTMLMeta.parse(html: html, baseURL: URL(string: "https://foodie.example/posts/1"))
        #expect(m.title == "Tom & Jerry's \"Dhaba\"")
        #expect(m.siteName == "Foodie")
        #expect(m.description == "Best biryani in town")
        #expect(m.author == "Ana")
        #expect(m.imageURL?.absoluteString == "https://foodie.example/img/hero.jpg?v=2")
    }

    @Test func twitterCardAndTitleTagFallbacks() {
        let twitter = HTMLMeta.parse(html: #"<meta name="twitter:title" content="T"><meta name="twitter:image" content="https://x.test/a.png">"#, baseURL: nil)
        #expect(twitter.title == "T" && twitter.imageURL?.absoluteString == "https://x.test/a.png")
        let titleOnly = HTMLMeta.parse(html: "<title>\n  Spaced   out\n title </title>", baseURL: nil)
        #expect(titleOnly.title == "Spaced out title" && titleOnly.imageURL == nil)
        let linkRel = HTMLMeta.parse(html: #"<link rel="image_src" href="//cdn.test/i.jpg">"#, baseURL: URL(string: "https://a.test/"))
        #expect(linkRel.imageURL?.absoluteString == "https://cdn.test/i.jpg")
        #expect(HTMLMeta.parse(html: "<p>nothing</p>", baseURL: nil) == LinkMetadata())
    }

    @Test func attributeOrderQuotingAndNumericEntities() {
        let m = HTMLMeta.parse(html: #"<meta content=Unquoted property=og:title><meta content="caf&#233; &#x2603;" name="description">"#, baseURL: nil)
        #expect(m.title == "Unquoted")
        #expect(m.description == "café ☃")
    }

    @Test func classifier() {
        #expect(CaptureClassifier.classify("https://x.com/a/b.JPG?w=1").kind == .image)
        #expect(CaptureClassifier.classify("  https://x.com/clip.mp4 ").kind == .video)
        #expect(CaptureClassifier.classify("https://www.pinterest.com/pin/123/").kind == .page)
        #expect(CaptureClassifier.classify("hello world").kind == .text)
        #expect(CaptureClassifier.classify("ftp://x.com/a.png").kind == .text)
        #expect(CaptureClassifier.classify("https://a.com\nhttps://b.com").kind == .text)
        #expect(CaptureClassifier.isFigma(URL(string: "https://www.figma.com/design/abc/My-File?node-id=1")!))
        #expect(CaptureClassifier.isFigma(URL(string: "https://figma.com/proto/abc")!))
        #expect(!CaptureClassifier.isFigma(URL(string: "https://www.figma.com/pricing")!))
        #expect(!CaptureClassifier.isFigma(URL(string: "https://notfigma.com/design/x")!))
        #expect(CaptureClassifier.siteName(for: URL(string: "https://www.Behance.net/x")!) == "behance.net")
    }

    @Test func mediaSniffing() throws {
        let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        #expect(MediaSniffer.fileExtension(forData: png) == "png")
        #expect(MediaSniffer.fileExtension(forData: Data([0xFF, 0xD8, 0xFF, 0xE0])) == "jpg")
        #expect(MediaSniffer.fileExtension(forData: Data("GIF89a....".utf8)) == "gif")
        #expect(MediaSniffer.fileExtension(forData: Data("RIFF0000WEBPVP8 ".utf8)) == "webp")
        #expect(MediaSniffer.fileExtension(forData: Data([0, 0, 0, 0x20] + Array("ftypisom".utf8))) == "mp4")
        #expect(MediaSniffer.fileExtension(forData: Data([0, 0, 0, 0x20] + Array("ftypqt  ".utf8))) == "mov")
        #expect(MediaSniffer.fileExtension(forData: Data(#"<?xml version="1.0"?><svg xmlns="http://www.w3.org/2000/svg"/>"#.utf8)) == "svg")
        #expect(MediaSniffer.fileExtension(forData: Data("hello world".utf8)) == nil)
        #expect(MediaSniffer.fileExtension(forMIME: "image/webp") == "webp")
    }
}

@Suite struct HTTPParserTests {
    @Test func parsesRequestArrivingInPieces() {
        var p = HTTPRequestParser()
        #expect(p.append(Data("POST /api/v1/items?x=1 HTTP/1.1\r\nHost: l".utf8)) == .needMore)
        #expect(p.append(Data("ocalhost\r\nContent-Length: 5\r\nAuthorization: Bearer abc\r\n\r\nhe".utf8)) == .needMore)
        #expect(p.append(Data("llo".utf8)) == .complete)
        let r = p.request
        #expect(r?.method == "POST" && r?.path == "/api/v1/items" && r?.query == "x=1")
        #expect(r?.header("authorization") == "Bearer abc")
        #expect(r.map { String(decoding: $0.body, as: UTF8.self) } == "hello")
    }

    @Test func limitsAndGarbage() {
        var big = HTTPRequestParser(maxBody: 10)
        #expect(big.append(Data("POST / HTTP/1.1\r\nContent-Length: 11\r\n\r\n".utf8)) == .tooLarge)
        var bad = HTTPRequestParser()
        #expect(bad.append(Data("NOT HTTP\r\n\r\n".utf8)) == .malformed)
        var badLen = HTTPRequestParser()
        #expect(badLen.append(Data("GET / HTTP/1.1\r\nContent-Length: abc\r\n\r\n".utf8)) == .malformed)
        var noEnd = HTTPRequestParser()
        #expect(noEnd.append(Data(repeating: 0x41, count: HTTPRequestParser.maxHeaderBytes + 10)) == .malformed)
        var get = HTTPRequestParser()
        #expect(get.append(Data("GET /api/v1/ping HTTP/1.1\r\nOrigin: chrome-extension://abc\r\n\r\n".utf8)) == .complete)
        #expect(get.request?.header("ORIGIN") == "chrome-extension://abc")
    }
}

// MARK: Capture service

func tinyPNG() -> Data {
    let url = TestSupport.makePNG(in: TestSupport.tempDir(), name: "p", width: 64, height: 48, rgb: (0.2, 0.5, 0.9))
    return try! Data(contentsOf: url)
}

final class Recorder: @unchecked Sendable {
    private let lock = NSLock()
    var requests: [URLRequest] = []
    func add(_ r: URLRequest) { lock.lock(); requests.append(r); lock.unlock() }
}

@Suite struct CaptureServiceTests {
    func service(store: LibraryStore, recorder: Recorder = Recorder(), pages: [String: String] = [:], files: [String: Data] = [:]) -> LibraryCaptureService {
        let loader: LinkFetcher.Loader = { req in
            recorder.add(req)
            let url = req.url!
            let ok = { (data: Data, mime: String) in (data, HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": mime])!) }
            if let html = pages[url.absoluteString] { return ok(Data(html.utf8), "text/html") }
            if let data = files[url.absoluteString] { return ok(data, "image/png") }
            return (Data(), HTTPURLResponse(url: url, statusCode: 404, httpVersion: nil, headerFields: nil)!)
        }
        return LibraryCaptureService(fetcher: LinkFetcher(load: loader), download: loader, store: { store })
    }

    @Test func downloadsMediaWithRefererAndStoresSource() async throws {
        let (store, _) = try TestSupport.newStore()
        let rec = Recorder()
        let svc = service(store: store, recorder: rec, files: ["https://cdn.example.com/pics/biryani.png": tinyPNG()])
        let r = try await svc.save(SaveRequest(mediaUrl: "https://cdn.example.com/pics/biryani.png", pageUrl: "https://www.pinterest.com/pin/1/", title: nil, tags: ["food"]))
        #expect(!r.duplicate && r.kind == "image" && r.name == "biryani")
        let item = try #require(try await store.item(id: r.id))
        #expect(item.source?.url == "https://cdn.example.com/pics/biryani.png" && item.source?.pageUrl == "https://www.pinterest.com/pin/1/")
        #expect(item.source?.site == "pinterest.com" && item.tags == ["food"])
        #expect(item.width == 64 && item.height == 48)
        #expect(rec.requests.first?.value(forHTTPHeaderField: "Referer") == "https://www.pinterest.com/pin/1/")
        #expect(try await svc.save(SaveRequest(mediaUrl: "https://cdn.example.com/pics/biryani.png")).duplicate)
    }

    @Test func base64DataIsSniffedAndInboxVsCollection() async throws {
        let (store, _) = try TestSupport.newStore()
        let c = try await store.createCollection(name: "Refs")
        let svc = service(store: store)
        let r = try await svc.save(SaveRequest(pageUrl: "https://a.test/post", title: "A shot", dataBase64: tinyPNG().base64EncodedString(), collectionId: c.id))
        let item = try #require(try await store.item(id: r.id))
        #expect(item.ext == "png" && item.name == "A shot" && item.collections.keys.contains(c.id))
        var inbox = ItemQuery(); inbox.unfiled = true
        #expect(try await store.index.count(inbox) == 0)
    }

    @Test func linkCardGetsTitleSiteAndPreviewThumb() async throws {
        let (store, root) = try TestSupport.newStore()
        let page = "https://blog.example.com/post"
        let html = #"<meta property="og:title" content="Great post"><meta property="og:site_name" content="Blog"><meta property="og:image" content="/hero.png">"#
        let svc = service(store: store, pages: [page: html], files: ["https://blog.example.com/hero.png": tinyPNG()])
        let r = try await svc.save(SaveRequest(pageUrl: page))
        #expect(r.kind == "link" && r.name == "Great post" && !r.duplicate)
        let item = try #require(try await store.item(id: r.id))
        #expect(item.file == nil && item.source?.pageUrl == page && item.source?.site == "Blog")
        #expect(item.extras["linkDisplay"] == "image")
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("items/\(r.id)/thumb.jpg").path))
        let summary = try #require(try await store.index.query(ItemQuery()).first)
        #expect(summary.kind == .link && summary.site == "Blog" && summary.linkDisplay == "image")
        #expect(try await svc.save(SaveRequest(pageUrl: page)).duplicate)             // same URL ⇒ same card
    }

    @Test func linkWithoutImageUsesSnapshotThenTitle() async throws {
        let (store, root) = try TestSupport.newStore()
        let svc = service(store: store, pages: ["https://a.test/1": "<title>One</title>", "https://a.test/2": "<title>Two</title>"])
        let withSnap = try await svc.save(SaveRequest(pageUrl: "https://a.test/1", snapshotBase64: tinyPNG().base64EncodedString()))
        #expect(try await store.item(id: withSnap.id)?.extras["linkDisplay"] == "snapshot")
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("items/\(withSnap.id)/snapshot.jpg").path))
        let plain = try await svc.save(SaveRequest(pageUrl: "https://a.test/2"))
        #expect(try await store.item(id: plain.id)?.extras["linkDisplay"] == "title")
        try await store.setLinkDisplay("title", for: withSnap.id)
        #expect(try await store.index.query(ItemQuery()).first { $0.id == withSnap.id }?.linkDisplay == "title")
        let big = try Data(contentsOf: TestSupport.makePNG(in: TestSupport.tempDir(), name: "big", width: 2560, height: 1920))
        try await store.setSnapshot(big, for: plain.id)
        #expect(try await store.item(id: plain.id)?.extras["linkDisplay"] == "snapshot")
        let stored = try Data(contentsOf: root.appendingPathComponent("items/\(plain.id)/snapshot.jpg"))
        #expect(stored.starts(with: [0xFF, 0xD8]))                                       // a real JPEG, whatever came in
        let dims = Thumbnailer.imageInfo(at: root.appendingPathComponent("items/\(plain.id)/snapshot.jpg"))
        #expect(dims?.width == 1280 && dims?.height == 960)
        await #expect(throws: CaptureError.self) { try await store.setSnapshot(Data("not an image".utf8), for: plain.id) }
    }

    @Test func figmaLinkUsesOEmbedAndGetsBadge() async throws {
        let (store, _) = try TestSupport.newStore()
        let oembed = #"{"title":"Swish App Redesign","author_name":"Arjun","thumbnail_url":"https://s3.figma.test/thumb.png"}"#
        let figmaURL = "https://www.figma.com/design/AbC123/Swish-App?node-id=1-2"
        let endpoint = "https://www.figma.com/api/oembed?url=" + figmaURL.addingPercentEncoding(withAllowedCharacters: .alphanumerics)!
        let loader: LinkFetcher.Loader = { req in
            let u = req.url!.absoluteString
            func resp(_ d: Data) -> (Data, URLResponse) { (d, HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!) }
            if u.hasPrefix("https://www.figma.com/api/oembed") { return resp(Data(oembed.utf8)) }
            if u == "https://s3.figma.test/thumb.png" { return resp(tinyPNG()) }
            return (Data(), HTTPURLResponse(url: req.url!, statusCode: 404, httpVersion: nil, headerFields: nil)!)
        }
        _ = endpoint
        let svc = LibraryCaptureService(fetcher: LinkFetcher(load: loader), store: { store })
        let r = try await svc.save(SaveRequest(pageUrl: figmaURL))
        let item = try #require(try await store.item(id: r.id))
        #expect(item.name == "Swish App Redesign" && item.source?.site == "Figma" && item.source?.author == "Arjun")
        #expect(item.extras["badge"] == "figma" && item.extras["linkDisplay"] == "image")
        #expect(try await store.index.query(ItemQuery()).first?.badge == "figma")
    }

    @Test func errorsAreSpecific() async throws {
        let (store, _) = try TestSupport.newStore()
        let svc = service(store: store)
        await #expect(throws: CaptureError.nothingToSave) { try await svc.save(SaveRequest()) }
        await #expect(throws: CaptureError.self) { try await svc.save(SaveRequest(mediaUrl: "not a url")) }
        await #expect(throws: CaptureError.self) { try await svc.save(SaveRequest(mediaUrl: "https://gone.example/x.png")) }      // 404
        await #expect(throws: CaptureError.unsupported("unrecognised file type")) { try await svc.save(SaveRequest(dataBase64: Data("plain text".utf8).base64EncodedString())) }
        let none = LibraryCaptureService(store: { nil })
        await #expect(throws: CaptureError.noLibrary) { try await none.save(SaveRequest(pageUrl: "https://a.test")) }
        #expect(try await store.index.count(ItemQuery()) == 0)
    }

    @Test func serviceListsCollectionsAndFiresCallback() async throws {
        let (store, _) = try TestSupport.newStore()
        let a = try await store.createCollection(name: "Alpha"), b = try await store.createCollection(name: "Beta")
        try await store.archiveCollection(id: b.id, true)
        let svc = service(store: store)
        #expect(await svc.collections().map(\.name) == ["Alpha"])
        #expect(await svc.libraryName == "Test")
        final class Hits: @unchecked Sendable { var n = 0 }
        let hits = Hits()
        svc.onSaved = { _ in hits.n += 1 }
        _ = try await svc.save(SaveRequest(dataBase64: tinyPNG().base64EncodedString(), collectionId: a.id))
        #expect(hits.n == 1)
    }
}

// MARK: Local API server

actor FakeService: CaptureService {
    var saved: [SaveRequest] = []
    var nextError: CaptureError?
    var libraryName: String { "Fake Library" }
    func setError(_ e: CaptureError?) { nextError = e }
    func save(_ r: SaveRequest) async throws -> SaveResult {
        if let e = nextError { throw e }
        saved.append(r)
        return SaveResult(id: "ID\(saved.count)", kind: "image", duplicate: r.title == "dup", name: r.title ?? "x")
    }
    func collections() async -> [CollectionInfo] { [CollectionInfo(id: "C1", name: "Packaging", kind: "collection", parentId: nil)] }
}

@Suite(.serialized) struct LocalAPITests {
    let token = "test-token-123"

    func start(maxBody: Int = 64 * 1024 * 1024) async throws -> (LocalAPIServer, FakeService, String) {
        let svc = FakeService()
        let server = LocalAPIServer(service: svc, tokens: InMemoryTokenStorage(token), maxBody: maxBody)
        let port = try await server.start(port: 0)
        return (server, svc, "http://127.0.0.1:\(port)")
    }

    func call(_ base: String, _ method: String = "GET", _ path: String, token: String? = "test-token-123", origin: String? = nil, body: Data? = nil) async throws -> (Int, [String: String], Data) {
        var req = URLRequest(url: URL(string: base + path)!)
        req.httpMethod = method
        if let token { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        if let origin { req.setValue(origin, forHTTPHeaderField: "Origin") }
        if let body { req.httpBody = body; req.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        let (data, resp) = try await URLSession.shared.data(for: req)
        let http = resp as! HTTPURLResponse
        var headers: [String: String] = [:]
        for (k, v) in http.allHeaderFields { headers["\(k)".lowercased()] = "\(v)" }
        return (http.statusCode, headers, data)
    }

    @Test func tokenIsRequired() async throws {
        let (server, _, base) = try await start()
        defer { server.stop() }
        #expect(try await call(base, "GET", "/api/v1/ping", token: nil).0 == 401)
        #expect(try await call(base, "GET", "/api/v1/ping", token: "wrong").0 == 401)
        #expect(try await call(base, "GET", "/api/v1/collections", token: nil).0 == 401)
        #expect(try await call(base, "POST", "/api/v1/items", token: nil, body: Data("{}".utf8)).0 == 401)
        let ok = try await call(base, "GET", "/api/v1/ping")
        #expect(ok.0 == 200)
        let json = try JSONSerialization.jsonObject(with: ok.2) as? [String: Any]
        #expect(json?["ok"] as? Bool == true && json?["library"] as? String == "Fake Library" && json?["app"] as? String == "Stash")
    }

    @Test func savesItemsAndReportsErrors() async throws {
        let (server, svc, base) = try await start()
        defer { server.stop() }
        let body = try JSONEncoder().encode(SaveRequest(mediaUrl: "https://x.test/a.png", pageUrl: "https://x.test/", title: "Pic", tags: ["a"]))
        let created = try await call(base, "POST", "/api/v1/items", body: body)
        #expect(created.0 == 201)
        let createdResult = try JSONDecoder().decode(SaveResult.self, from: created.2)
        #expect(createdResult.id == "ID1")
        let saved = await svc.saved
        #expect(saved.count == 1 && saved[0].mediaUrl == "https://x.test/a.png" && saved[0].tags == ["a"])

        let dup = try await call(base, "POST", "/api/v1/items", body: JSONEncoder().encode(SaveRequest(mediaUrl: "https://x.test/a.png", title: "dup")))
        #expect(dup.0 == 200)
        #expect(try await call(base, "POST", "/api/v1/items", body: Data("not json".utf8)).0 == 400)
        await svc.setError(.nothingToSave)
        #expect(try await call(base, "POST", "/api/v1/items", body: Data("{}".utf8)).0 == 400)
        await svc.setError(.downloadFailed("boom"))
        #expect(try await call(base, "POST", "/api/v1/items", body: Data("{}".utf8)).0 == 502)
        await svc.setError(.noLibrary)
        #expect(try await call(base, "POST", "/api/v1/items", body: Data("{}".utf8)).0 == 503)

        let cols = try await call(base, "GET", "/api/v1/collections")
        let colList = try JSONDecoder().decode([CollectionInfo].self, from: cols.2)
        #expect(cols.0 == 200 && colList.map(\.name) == ["Packaging"])
        #expect(try await call(base, "GET", "/api/v1/nope").0 == 404)
        #expect(try await call(base, "DELETE", "/api/v1/items").0 == 405)
    }

    @Test func corsOnlyForExtensionOrigins() async throws {
        let (server, _, base) = try await start()
        defer { server.stop() }
        let ext = "chrome-extension://abcdefghijklmnop"
        let preflight = try await call(base, "OPTIONS", "/api/v1/items", token: nil, origin: ext)
        #expect(preflight.0 == 204)
        #expect(preflight.1["access-control-allow-origin"] == ext)
        #expect(preflight.1["access-control-allow-headers"]?.contains("authorization") == true)
        let withOrigin = try await call(base, "GET", "/api/v1/ping", origin: ext)
        #expect(withOrigin.0 == 200 && withOrigin.1["access-control-allow-origin"] == ext)
        // a web page (even with the right token) is refused
        #expect(try await call(base, "GET", "/api/v1/ping", origin: "https://evil.example").0 == 403)
        #expect(try await call(base, "OPTIONS", "/api/v1/items", token: nil, origin: "http://localhost:3000").0 == 403)
        #expect(try await call(base, "GET", "/api/v1/ping", origin: "moz-extension://uuid").0 == 200)
    }

    @Test func oversizedBodiesAreRejected() async throws {
        let (server, _, base) = try await start(maxBody: 1024)
        defer { server.stop() }
        let r = try await call(base, "POST", "/api/v1/items", body: Data(repeating: 0x20, count: 4096))
        #expect(r.0 == 413)
        #expect(try await call(base, "GET", "/api/v1/ping").0 == 200)     // still serving
    }

    @Test func largeBodiesArriveIntact() async throws {
        let (server, svc, base) = try await start()
        defer { server.stop() }
        let big = String(repeating: "A", count: 3_000_000)
        let body = try JSONEncoder().encode(SaveRequest(pageUrl: "https://x.test", title: "big", dataBase64: big))
        #expect(try await call(base, "POST", "/api/v1/items", body: body).0 == 201)
        #expect(await svc.saved.first?.dataBase64?.count == 3_000_000)
    }

    @Test func listensOnLoopbackOnly() {
        #expect(LocalAPIServer.isLoopback(.ipv4(.loopback)))
        #expect(LocalAPIServer.isLoopback(.ipv6(.loopback)))
        #expect(LocalAPIServer.isLoopback(.name("localhost", nil)))
        #expect(LocalAPIServer.isLoopback(.ipv4(IPv4Address("127.0.0.5")!)))
        #expect(!LocalAPIServer.isLoopback(.ipv4(IPv4Address("192.168.1.20")!)))
        #expect(!LocalAPIServer.isLoopback(.ipv4(IPv4Address("10.0.0.2")!)))
        #expect(!LocalAPIServer.isLoopback(.ipv6(IPv6Address("fe80::1")!)))
        #expect(!LocalAPIServer.isLoopback(.name("example.com", nil)))
        #expect(LocalAPIServer.constantTimeEquals("abc", "abc") && !LocalAPIServer.constantTimeEquals("abc", "abd") && !LocalAPIServer.constantTimeEquals("abc", "ab"))
    }

    @Test func serverIsBoundToLoopbackInterface() async throws {
        let (server, _, _) = try await start()
        defer { server.stop() }
        // Connect to the machine's non-loopback address on the same port: nothing may answer.
        var addrs: [String] = []
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        if getifaddrs(&ifaddr) == 0 {
            var p = ifaddr
            while let cur = p {
                if cur.pointee.ifa_addr.pointee.sa_family == UInt8(AF_INET) {
                    var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    getnameinfo(cur.pointee.ifa_addr, socklen_t(cur.pointee.ifa_addr.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST)
                    let ip = String(cString: host)
                    if !ip.hasPrefix("127.") { addrs.append(ip) }
                }
                p = cur.pointee.ifa_next
            }
            freeifaddrs(ifaddr)
        }
        guard let lan = addrs.first else { return }       // no other interface (rare): nothing to prove
        var req = URLRequest(url: URL(string: "http://\(lan):\(server.port)/api/v1/ping")!, timeoutInterval: 3)
        req.setValue("Bearer test-token-123", forHTTPHeaderField: "Authorization")
        await #expect(throws: (any Error).self) { _ = try await URLSession.shared.data(for: req) }
    }

    @Test func keychainTokenIsStableUntilRegenerated() {
        let storage = KeychainTokenStorage(service: "in.justswish.stash.tests.\(UUID().uuidString)")
        let t1 = storage.token()
        #expect(t1.count >= 40 && storage.token() == t1)
        let t2 = storage.regenerate()
        #expect(t2 != t1 && storage.token() == t2)
        _ = storage.regenerate()
        SecItemDelete([kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "in.justswish.stash.tests"] as CFDictionary)
    }
}
