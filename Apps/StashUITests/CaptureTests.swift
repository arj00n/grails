import AppKit
import XCTest

/// Capture paths: ⌘V from the clipboard and the local HTTP API the browser extension uses.
final class CaptureTests: XCTestCase {
    private let token = "ui-test-token"

    @MainActor
    private func launch(port: String? = nil) -> XCUIApplication {
        let dir = "/private/tmp/stash-ui-tests/\(UUID().uuidString)"
        let app = XCUIApplication()
        app.launchEnvironment["STASH_LIBRARY"] = dir + "/Lib.stash"
        app.launchEnvironment["STASH_SEED"] = "6"
        app.launchEnvironment["STASH_SEED_PLAIN"] = "1"
        app.launchEnvironment["STASH_INDEX_PATH"] = dir + "/index.sqlite"
        app.launchEnvironment["STASH_API_TOKEN"] = token
        app.launchEnvironment["STASH_NO_MENUBAR"] = "1"
        if let port { app.launchEnvironment["STASH_API_PORT"] = port }
        app.launchArguments += ["-zoomStep", "0", "-layoutMode", "square", "-appearance", "light",
                                "-sidebar.expandCollections", "1", "-sidebar.expandTags", "1", "-sidebar.expandSmart", "1"]
        app.launch()
        app.activate()
        return app
    }

    private func solidImage(_ color: NSColor, size: NSSize = NSSize(width: 240, height: 160)) -> NSImage {
        let img = NSImage(size: size)
        img.lockFocus(); color.setFill(); NSRect(origin: .zero, size: size).fill(); img.unlockFocus()
        return img
    }

    @MainActor
    func testPasteImageFromClipboardCreatesItem() throws {
        let app = launch()
        XCTAssertTrue(app.staticTexts["6 items"].waitForExistence(timeout: 30))
        NSPasteboard.general.clearContents()
        XCTAssertTrue(NSPasteboard.general.writeObjects([solidImage(.systemOrange)]))

        let grid = app.collectionViews["grid"]
        grid.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0)).withOffset(CGVector(dx: 50, dy: 50)).click()   // focus the grid
        app.typeKey("v", modifierFlags: .command)
        XCTAssertTrue(app.staticTexts["7 items"].waitForExistence(timeout: 15), "pasted image became an item")

        // ⌘Z removes it again
        app.typeKey("z", modifierFlags: .command)
        XCTAssertTrue(app.staticTexts["6 items"].waitForExistence(timeout: 10))
    }

    @MainActor
    func testLocalAPIRejectsBadTokenAndSavesImage() async throws {
        let app = launch()
        XCTAssertTrue(app.staticTexts["6 items"].waitForExistence(timeout: 30))
        let base = "http://127.0.0.1:47823"

        var bad = URLRequest(url: URL(string: base + "/api/v1/ping")!)
        bad.setValue("Bearer nope", forHTTPHeaderField: "Authorization")
        let (_, badResp) = try await URLSession.shared.data(for: bad)
        XCTAssertEqual((badResp as? HTTPURLResponse)?.statusCode, 401)

        let tiff = try XCTUnwrap(solidImage(.systemTeal).tiffRepresentation)
        let png = try XCTUnwrap(NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]))
        var post = URLRequest(url: URL(string: base + "/api/v1/items")!)
        post.httpMethod = "POST"
        post.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        post.httpBody = try JSONSerialization.data(withJSONObject: ["dataBase64": png.base64EncodedString(), "title": "from the extension", "pageUrl": "https://example.com/p"])
        let (data, resp) = try await URLSession.shared.data(for: post)
        XCTAssertEqual((resp as? HTTPURLResponse)?.statusCode, 201, String(decoding: data, as: UTF8.self))
        XCTAssertTrue(app.staticTexts["7 items"].waitForExistence(timeout: 15), "the grid picks up items saved over the API")
    }

    /// Needs /private/tmp/stash-e2e/{page.html,page2.html,hero.png} (created by the dev setup in PROGRESS.md).
    @MainActor
    func testLinkCardsRenderAndSnapshotCanBeRetaken() async throws {
        try XCTSkipIf(!FileManager.default.fileExists(atPath: "/private/tmp/stash-e2e/page2.html"), "link fixtures missing")
        let app = launch()
        XCTAssertTrue(app.staticTexts["6 items"].waitForExistence(timeout: 30))
        func post(_ body: [String: Any]) async throws {
            var r = URLRequest(url: URL(string: "http://127.0.0.1:47823/api/v1/items")!)
            r.httpMethod = "POST"
            r.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            r.httpBody = try JSONSerialization.data(withJSONObject: body)
            let (_, resp) = try await URLSession.shared.data(for: r)
            XCTAssertEqual((resp as? HTTPURLResponse)?.statusCode, 201)
        }
        try await post(["pageUrl": "file:///private/tmp/stash-e2e/page.html"])    // og:image → preview card
        try await post(["pageUrl": "file:///private/tmp/stash-e2e/page2.html"])   // no image → title card (+ auto snapshot)
        XCTAssertTrue(app.staticTexts["8 items"].waitForExistence(timeout: 15))
        try await Task.sleep(for: .seconds(9))                                     // let the automatic snapshot finish
        let png = app.windows.firstMatch.screenshot().pngRepresentation
        try? png.write(to: URL(fileURLWithPath: NSTemporaryDirectory() + "links.png"))

        // right-click the newest tile → context menu offers link actions
        let grid = app.collectionViews["grid"]
        grid.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0)).withOffset(CGVector(dx: 50, dy: 50)).rightClick()
        try await Task.sleep(for: .seconds(1))
        // Menu order: Open Preview, Open Link in Browser, Show Link As ▸, Retake Snapshot (popup NSMenu items aren't queryable by title)
        for _ in 0..<4 { app.typeKey(.downArrow, modifierFlags: []) }
        app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(app.staticTexts["Snapshot updated"].waitForExistence(timeout: 40))
    }
}
