import XCTest

/// Development aid: renders the main screens of a real-image library to PNGs so the look can be judged.
/// TEST_RUNNER_STASH_SHOWCASE=<path to a .stash made with `stash-fixture --from-folder …`>
/// Output goes to the runner's temporary directory (printed as SHOT: lines).
final class ShotTests: XCTestCase {
    private var showcase: String { ProcessInfo.processInfo.environment["STASH_SHOWCASE"] ?? "" }

    @MainActor
    private func launch(view: String, panel: String? = nil, info: Bool = false, width: Int = 190) -> XCUIApplication {
        let dir = "/private/tmp/stash-ui-tests/\(UUID().uuidString)"
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let app = XCUIApplication()
        app.launchEnvironment["STASH_LIBRARY"] = showcase
        app.launchEnvironment["STASH_INDEX_PATH"] = dir + "/index.sqlite"
        app.launchEnvironment["STASH_NO_MENUBAR"] = "1"
        app.launchEnvironment["STASH_API_PORT"] = "47881"
        if info { app.launchEnvironment["STASH_SHOW_INFO"] = "1" }
        if let panel { app.launchEnvironment["STASH_PANEL"] = panel }
        app.launchArguments += ["-viewMode", view, "-tileWidth", "\(width)", "-layoutMode", "masonry",
                                "-sidebar.expandCollections", "1", "-sidebar.expandTags", "1", "-sidebar.expandSmart", "1"]
        app.launch(); app.activate()
        return app
    }

    @MainActor
    private func shoot(_ app: XCUIApplication, _ name: String) {
        Thread.sleep(forTimeInterval: 2.5)
        let png = app.windows.firstMatch.screenshot().pngRepresentation
        let path = NSTemporaryDirectory() + "shot-\(name).png"
        try? png.write(to: URL(fileURLWithPath: path))
        print("SHOT:", path)
    }

    /// TEST_RUNNER_STASH_SHOT_QUERY=720w: search for it, open the first hit in the preview.
    @MainActor
    func testQueryShot() throws {
        let q = ProcessInfo.processInfo.environment["STASH_SHOT_QUERY"] ?? ""
        try XCTSkipIf(showcase.isEmpty || q.isEmpty)
        let app = launch(view: "grid")
        XCTAssertTrue(app.collectionViews["grid"].waitForExistence(timeout: 30))
        shoot(app, "all")
        let search = app.searchFields.firstMatch
        search.click()
        for ch in q { app.typeKey(String(ch), modifierFlags: []) }
        app.typeKey(.return, modifierFlags: [])
        Thread.sleep(forTimeInterval: 1.5)
        app.collectionViews["grid"].coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0)).withOffset(CGVector(dx: 120, dy: 140)).click()
        shoot(app, "query-grid")
        app.typeKey(" ", modifierFlags: [])
        shoot(app, "query-preview")
        app.terminate()
    }

    @MainActor
    func testSearchShot() throws {
        try XCTSkipIf(showcase.isEmpty)
        let app = launch(view: "grid")
        XCTAssertTrue(app.collectionViews["grid"].waitForExistence(timeout: 30))
        app.searchFields.firstMatch.click()
        shoot(app, "search-focused")
        for ch in "burger" { app.typeKey(String(ch), modifierFlags: []) }
        shoot(app, "search-typed")
        app.terminate()
    }

    @MainActor
    func testShots() throws {
        try XCTSkipIf(showcase.isEmpty)
        var app = launch(view: "grid")
        XCTAssertTrue(app.collectionViews["grid"].waitForExistence(timeout: 30))
        shoot(app, "grid")
        app.collectionViews["grid"].coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0)).withOffset(CGVector(dx: 120, dy: 140)).click()
        app.typeKey("i", modifierFlags: [])
        shoot(app, "grid-info")
        app.typeKey(" ", modifierFlags: [])
        shoot(app, "preview")
        app.typeKey(XCUIKeyboardKey.escape.rawValue, modifierFlags: [])
        app.typeKey("i", modifierFlags: [.command, .shift])
        shoot(app, "import")
        app.terminate()

        app = launch(view: "canvas")
        XCTAssertTrue(app.descendants(matching: .any)["canvas"].waitForExistence(timeout: 30))
        shoot(app, "canvas")
        app.terminate()

        app = launch(view: "grid", panel: "commandK")
        XCTAssertTrue(app.textFields["palette-field"].waitForExistence(timeout: 30))
        shoot(app, "palette")
        app.terminate()
    }
}
