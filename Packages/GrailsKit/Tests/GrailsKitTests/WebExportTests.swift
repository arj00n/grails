import Foundation
import Testing
@testable import GrailsKit

@Suite struct WebExportTests {
    @Test func exportsAPageWithSectionsAndCanvas() async throws {
        let (store, _) = try TestSupport.newStore(handle: "ana")
        let dir = TestSupport.tempDir()
        var items: [Item] = []
        for i in 0..<5 { items.append(try await store.addItem(fileAt: TestSupport.makePNG(in: dir, name: "s\(i)", rgb: (Double(i) / 5, 0.3, 0.6)), source: ItemSource(url: "https://example.com/p\(i).png", pageUrl: "https://example.com/post/\(i)", author: "Ana")).item) }
        let trashed = items[4]
        try await store.softDelete(ids: [trashed.id])
        let clusters = [
            CanvasCluster(id: "c1", title: "Light", x: 0, y: 0, width: 800, tile: 200, items: [items[0].id, items[1].id]),
            CanvasCluster(id: "c2", title: "", x: 900, y: 0, width: 600, tile: 200, items: [items[2].id, items[3].id, trashed.id]),
        ]
        let out = TestSupport.tempDir()
        let report = try await store.exportWebPage(title: "Studio: refs/1", ids: items.map(\.id), clusters: clusters, to: out)

        #expect(report.exported == 4)
        #expect(report.folder.lastPathComponent == "Studio refs 1")
        for f in ["index.html", "data.js"] { #expect(FileManager.default.fileExists(atPath: report.folder.appendingPathComponent(f).path)) }
        #expect(FileManager.default.fileExists(atPath: report.folder.appendingPathComponent("media/\(items[0].id).png").path)
                || FileManager.default.fileExists(atPath: report.folder.appendingPathComponent("media/\(items[0].id).jpg").path))
        #expect(FileManager.default.fileExists(atPath: report.folder.appendingPathComponent("thumbs/\(items[0].id).jpg").path))
        #expect(report.zip.map { FileManager.default.fileExists(atPath: $0.path) } == true)

        let js = try String(contentsOf: report.folder.appendingPathComponent("data.js"), encoding: .utf8)
        #expect(js.hasPrefix("window.GRAILS_SHARE = {"))
        let json = try JSONSerialization.jsonObject(with: Data(js.dropFirst("window.GRAILS_SHARE = ".count).dropLast(2).utf8)) as! [String: Any]
        #expect((json["sections"] as? [[String: Any]])?.count == 2)
        #expect((json["order"] as? [String])?.count == 4)
        let canvas = json["canvas"] as? [String: Any]
        #expect((canvas?["clusters"] as? [[String: Any]])?.count == 2)
        let it = (json["items"] as? [String: Any])?[items[0].id] as? [String: Any]
        #expect(it?["source"] as? String == "https://example.com/post/0")

        // a second export never overwrites the first
        let again = try await store.exportWebPage(title: "Studio: refs/1", ids: items.map(\.id), options: .init(includeSources: false, makeZip: false), to: out)
        #expect(again.folder.lastPathComponent == "Studio refs 1 2")
        #expect(again.zip == nil)
        let js2 = try String(contentsOf: again.folder.appendingPathComponent("data.js"), encoding: .utf8)
        #expect(!js2.contains("example.com"))
        #expect(!js2.contains("\"canvas\""))
    }
}
