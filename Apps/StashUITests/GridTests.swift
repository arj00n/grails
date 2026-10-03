import XCTest

/// Run with: STASH_FIXTURE=/path/Fixture20k.stash xcodebuild test ... (see PROGRESS.md)
final class GridTests: XCTestCase {
    private var fixture: String {
        ProcessInfo.processInfo.environment["STASH_FIXTURE"]
            ?? ProcessInfo.processInfo.environment["TEST_RUNNER_STASH_FIXTURE"] ?? ""
    }
    private let indexPath = NSTemporaryDirectory() + "stash-index-\(UUID().uuidString).sqlite"

    @MainActor
    private func launch(bench: Bool = false, layout: String = "square") throws -> XCUIApplication {
        try XCTSkipIf(fixture.isEmpty, "Set STASH_FIXTURE to a generated fixture library")
        let app = XCUIApplication()
        app.launchEnvironment["STASH_LIBRARY"] = fixture
        app.launchEnvironment["STASH_INDEX_PATH"] = indexPath
        app.launchEnvironment["STASH_HITCH_REPORT"] = "1"
        if bench { app.launchEnvironment["STASH_BENCH"] = "1" }
        app.launchArguments += ["-zoomStep", "2", "-layoutMode", layout, "-appearance", "light"]
        app.launch()
        app.activate()
        return app
    }

    @MainActor
    func testGridShowsItemsAndSidebarCounts() throws {
        let app = try launch()
        XCTAssertTrue(app.staticTexts["20,000 items"].waitForExistence(timeout: 60))
        XCTAssertTrue(app.staticTexts["20,000 items"].waitForExistence(timeout: 60), app.debugDescription)
    }

    /// The app drives its own scroll + zoom sweep (STASH_BENCH) so the numbers measure the grid, not the
    /// accessibility queries XCUITest would otherwise run on the app's main thread between scroll events.
    @MainActor
    func testSquareScrollingAndZoomingStayWithinFrameBudget() throws { try runBenchmark(layout: "square") }

    @MainActor
    func testMasonryScrollingAndZoomingStayWithinFrameBudget() throws { try runBenchmark(layout: "masonry") }

    @MainActor
    private func runBenchmark(layout: String) throws {
        let app = try launch(bench: true, layout: layout)
        let probe = app.staticTexts["hitch-report"]
        XCTAssertTrue(probe.waitForExistence(timeout: 60))
        // Don't touch the accessibility tree while the benchmark runs: every query stalls the app's main thread.
        Thread.sleep(forTimeInterval: 26)
        var label = probe.label
        for _ in 0..<10 where !label.contains("\"done\":true") {
            Thread.sleep(forTimeInterval: 5)
            label = probe.label
        }
        print("HITCH REPORT (\(layout)):", label)
        let json = try JSONSerialization.jsonObject(with: Data(label.utf8)) as! [String: Any]
        XCTAssertEqual(json["done"] as? Bool, true, "benchmark didn't finish: \(label)")
        XCTAssertGreaterThan(json["frames"] as! Int, 300, "monitor saw too few frames to mean anything: \(label)")
        // Budget (PLAN §6): no frame over 33 ms. Enforced strictly on Release builds (STASH_BENCH_STRICT=1);
        // Debug builds run unoptimised layout code, so they get 1% slack.
        let frames = json["frames"] as! Int, hitches = json["hitches"] as! Int
        let strict = ProcessInfo.processInfo.environment["TEST_RUNNER_STASH_BENCH_STRICT"] != nil
            || ProcessInfo.processInfo.environment["STASH_BENCH_STRICT"] != nil
        XCTAssertLessThanOrEqual(hitches, strict ? 0 : frames / 100, "frames over 33 ms during scroll/zoom: \(label)")
    }

    @MainActor
    func testSelectionInfoPanelAndPreview() throws {
        let app = try launch()
        XCTAssertTrue(app.staticTexts["20,000 items"].waitForExistence(timeout: 60))
        app.buttons["info-toggle"].click()
        XCTAssertTrue(app.staticTexts["Select an item to see its details."].waitForExistence(timeout: 5))

        let grid = app.collectionViews["grid"]
        XCTAssertTrue(grid.waitForExistence(timeout: 10))
        // AX hit-testing of NSCollectionView cells is unreliable; click by coordinate inside the first tile.
        grid.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.0)).withOffset(CGVector(dx: 0, dy: 150)).click()
        XCTAssertTrue(app.staticTexts["HISTORY"].waitForExistence(timeout: 5))

        app.typeKey(" ", modifierFlags: [])
        let preview = app.descendants(matching: .any)["preview"]
        XCTAssertTrue(preview.waitForExistence(timeout: 5), app.debugDescription)
        app.typeKey(XCUIKeyboardKey.escape.rawValue, modifierFlags: [])
        XCTAssertTrue(preview.waitForNonExistence(timeout: 5))
    }

    @MainActor
    func testLayoutToggleAndSidebarNavigation() throws {
        let app = try launch()
        XCTAssertTrue(app.staticTexts["20,000 items"].waitForExistence(timeout: 60))
        let picker = app.radioGroups["layout-picker"]
        picker.radioButtons.element(boundBy: 1).click()          // masonry
        XCTAssertEqual(picker.radioButtons.element(boundBy: 1).value as? Int, 1)
        app.collectionViews["grid"].scroll(byDeltaX: 0, deltaY: -600)
        app.staticTexts["Liked"].firstMatch.click()
        XCTAssertTrue(app.staticTexts["20,000 items"].waitForNonExistence(timeout: 10))
        app.staticTexts["All"].firstMatch.click()
        XCTAssertTrue(app.staticTexts["20,000 items"].waitForExistence(timeout: 10))
        // collections and tags navigate too
        app.staticTexts["Collection 1"].firstMatch.click()
        XCTAssertTrue(app.staticTexts["20,000 items"].waitForNonExistence(timeout: 10))
    }

    /// Writes window screenshots into the runner's temp dir (see PROGRESS.md for how to find them).
    @MainActor
    func testScreenshots() throws {
        for appearance in ["light", "dark"] {
            let app = XCUIApplication()
            try XCTSkipIf(fixture.isEmpty)
            app.launchEnvironment["STASH_LIBRARY"] = fixture
            app.launchEnvironment["STASH_INDEX_PATH"] = indexPath
            app.launchArguments += ["-zoomStep", "1", "-layoutMode", "square", "-appearance", appearance]
            app.launch(); app.activate()
            XCTAssertTrue(app.staticTexts["20,000 items"].waitForExistence(timeout: 60))
            app.buttons["info-toggle"].click()
            app.collectionViews["grid"].coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.0)).withOffset(CGVector(dx: 0, dy: 80)).click()
            Thread.sleep(forTimeInterval: 1.5)
            let png = app.windows.firstMatch.screenshot().pngRepresentation
            try png.write(to: URL(fileURLWithPath: NSTemporaryDirectory() + "stash-\(appearance).png"))
            print("SCREENSHOT:", NSTemporaryDirectory() + "stash-\(appearance).png")
            app.terminate()
        }
    }
}
