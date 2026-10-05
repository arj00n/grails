import AppKit
import GrailsKit
import UniformTypeIdentifiers

/// Dev only (GRAILS_IMPORT_DEMO=<dir>): a stand-in network that serves canned Are.na and Pinterest replies and generated pictures, and a
/// script that pastes links into the import model, runs the job and writes what happened to `result.txt`. No network, no screen.
enum ImportFixture {
    static func png(_ n: Int) -> Data {
        let ctx = CGContext(data: nil, width: 200 + n % 977, height: 160 + (n % 3) * 40, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(red: Double((n * 53) % 255) / 255, green: Double((n * 97) % 255) / 255, blue: Double((n * 31) % 255) / 255, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: 240, height: 400))
        let out = NSMutableData()
        let dest = CGImageDestinationCreateWithData(out, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
        CGImageDestinationFinalize(dest)
        return out as Data
    }

    static let loader: LinkFetcher.Loader = { req in
        let url = req.url!
        func ok(_ json: Any) throws -> (Data, URLResponse) { (try JSONSerialization.data(withJSONObject: json), HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!) }
        func channel(_ slug: String, _ n: Int, base: Int) -> [String: Any] {
            ["title": slug.replacingOccurrences(of: "-", with: " ").capitalized, "length": n,
             "contents": (0..<n).map { ["id": base + $0, "class": "Image", "title": "Image \(base + $0)", "user": ["slug": "ana"], "image": ["original": ["url": "https://cdn.test/img\(base + $0).png"], "thumb": ["url": "https://cdn.test/img\(base + $0).png"]]] as [String: Any] }]
        }
        try await Task.sleep(nanoseconds: 15_000_000)
        switch (url.host ?? "", url.path) {
        case ("api.are.na", let p) where p.hasPrefix("/v2/channels/"):
            switch url.lastPathComponent {
            case "demo-one": return try ok(channel("demo-one", 12, base: 100))
            case "demo-two": return try ok(channel("demo-two", 7, base: 200))
            case "other-one": return try ok(channel("other-one", 5, base: 300))
            default: return (Data(), HTTPURLResponse(url: url, statusCode: 404, httpVersion: nil, headerFields: nil)!)
            }
        case ("api.are.na", "/v3/users/demo/contents"):
            func c(_ slug: String, _ owner: String, _ n: Int) -> [String: Any] { ["slug": slug, "title": slug, "visibility": "public", "owner": ["slug": owner], "counts": ["contents": n]] }
            return try ok(["meta": ["has_more_pages": false], "data": [c("demo-one", "demo", 12), c("demo-two", "demo", 7), c("other-one", "friend", 5)]])
        case ("widgets.pinterest.com", let p) where p.contains("/boards/ana/interiors/"):
            let pins: [[String: Any]] = (0..<50).map { ["id": "\(5000 + $0)", "description": "Pin \($0)", "images": ["236x": ["url": "https://i.pinimg.com/236x/aa/bb/cc/pin\($0).jpg"]]] }
            return try ok(["data": ["board": ["name": "Interiors", "pin_count": 1204], "pins": pins]])
        case ("widgets.pinterest.com", let p) where p.contains("/pins/info"): return try ok(["data": [] as [Any]])
        case ("cdn.test", let p), ("i.pinimg.com", let p):
            let digits = p.filter(\.isNumber)
            return (png(Int(digits) ?? 7), HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "image/png"])!)
        default: return (Data(), HTTPURLResponse(url: url, statusCode: 404, httpVersion: nil, headerFields: nil)!)
        }
    }
}

extension ImportModel {
    func runDemo(into dir: String) {
        Task { @MainActor in
            try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            var log: [String] = []
            func say(_ s: String) { log.append(s); try? log.joined(separator: "\n").write(toFile: dir + "/result.txt", atomically: true, encoding: .utf8) }
            func wait(_ ms: Int) async { try? await Task.sleep(for: .milliseconds(ms)) }
            loader = ImportFixture.loader
            fixtureNetwork = true
            await wait(1500)
            ingest("""
            Boards I like: https://www.are.na/ana/demo-one and pinterest.com/ana/interiors/, plus https://www.are.na/demo
            also https://www.are.na/ana/demo-one again, https://example.com/x and pinterest.com/anaprofile
            """)
            say("pasted: \(rows.count) rows")
            for _ in 0..<80 where stillChecking { await wait(100) }
            for r in rows { say("row \(r.title) | \(r.status) | board=\(r.board?.count.map(String.init) ?? "-") via=\(r.board?.via.rawValue ?? "-") children=\(r.children.count)") }
            say("selected: \(selectedBoards.map(\.id)) items \(selectedItemCount)")
            setSelected("arena:other-one", true)
            start()
            say("phase \(phase)")
            for _ in 0..<200 where phase == .running { await wait(100) }
            say("phase \(phase), arrived \(arrivedCount)")
            for id in order { if let t = tasks[id] { let p = RowPresenter.row(t); say("task \(id): \(p.label) \(p.detail ?? "") added \(t.added) had \(t.alreadyHad) failed \(t.failed) collection \(t.collectionId != nil)") } }
            if let store = app?.store {
                let n = (try? await store.index.count(ItemQuery())) ?? -1
                let names = ((try? await store.index.collections()) ?? []).map(\.name).sorted()
                say("library: \(n) items; collections \(names)")
            }
            say("source \(String(describing: app?.source))")

            // the browser extension scrolled two boards (one pin the widget can't describe): they import from the picture the page showed
            let pins1 = (0..<4).map { ExtensionPin(id: "\(9000 + $0)", image: "https://i.pinimg.com/236x/aa/bb/cc/pin\(700 + $0).jpg") }
            let pins2 = [ExtensionPin(id: "AbC123", image: "https://i.pinimg.com/236x/aa/bb/cc/pin800.jpg"), ExtensionPin(id: "Zz9")]
            await receive(BoardImportRequest(boards: [ExtensionBoard(url: "https://www.pinterest.com/ana/full-one/", name: "Full one", pins: pins1),
                                                     ExtensionBoard(url: "https://www.pinterest.com/ana/full-two/", name: "Full two", pins: pins2)]))
            for _ in 0..<80 where phase == .running || phase == .composing { await wait(100) }
            say("ext order \(order) error \(lastReceiveError ?? "none")")
            for id in order { if let t = tasks[id] { say("ext task \(id): added \(t.added) had \(t.alreadyHad) failed \(t.failed) skipped \(t.skipped) state \(t.state)") } }
            say("after extension: \((try? await app?.store?.index.count(ItemQuery())) ?? -1) items")
            say("done")
            if ProcessInfo.processInfo.environment["GRAILS_IMPORT_DEMO_QUIT"] != nil { NSApp.terminate(nil) }
        }
    }
}
