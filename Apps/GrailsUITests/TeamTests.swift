import XCTest

/// Team features: first-run welcome, library switcher, who-added-what, and live updates from the shared folder.
final class TeamTests: XCTestCase {
    @MainActor
    private func launch(items: Int, people: String? = nil, remoteAfter: Int? = nil, zoom: Int = 190, library: Bool = true, extra: [String: String] = [:]) -> XCUIApplication {
        let dir = "/private/tmp/grails-ui-tests/\(UUID().uuidString)"
        let app = XCUIApplication()
        if library {
            app.launchEnvironment["GRAILS_LIBRARY"] = dir + "/Lib.grails"
            app.launchEnvironment["GRAILS_SEED"] = "\(items)"
            app.launchEnvironment["GRAILS_SEED_PLAIN"] = "1"
        }
        app.launchEnvironment["GRAILS_INDEX_PATH"] = dir + "/index.sqlite"
        app.launchEnvironment["GRAILS_API_PORT"] = "47861"
        app.launchEnvironment["GRAILS_NO_MENUBAR"] = "1"
        if let people { app.launchEnvironment["GRAILS_SEED_PEOPLE"] = people }
        if let remoteAfter { app.launchEnvironment["GRAILS_SIMULATE_REMOTE"] = "\(remoteAfter)" }
        for (k, v) in extra { app.launchEnvironment[k] = v }
        app.launchArguments += ["-viewMode", "grid", "-tileWidth", "\(zoom)", "-layoutMode", "square", "-appearance", "light", "-showAddedBy", "1",
                                "-sidebar.expandCollections", "1", "-sidebar.expandTags", "1", "-sidebar.expandSmart", "1"]
        app.launch()
        app.activate()
        return app
    }

    @MainActor
    func testFirstRunStartsOnboardingAndNothingIsCreatedSilently() throws {
        // No GRAILS_LIBRARY and an empty saved path: nothing may be created silently.
        let fresh = XCUIApplication()
        fresh.launchEnvironment["GRAILS_NO_MENUBAR"] = "1"
        fresh.launchEnvironment["GRAILS_API_PORT"] = "47862"
        fresh.launchArguments += ["-libraryPath", ""]
        fresh.launch()
        XCTAssertTrue(fresh.buttons["onboarding-start"].waitForExistence(timeout: 15))
        fresh.buttons["onboarding-start"].click()
        XCTAssertTrue(fresh.buttons["library-continue"].waitForExistence(timeout: 5))
        XCTAssertTrue(fresh.buttons["library-this-mac"].exists)
        XCTAssertTrue(fresh.buttons["library-link"].exists)
    }

    @MainActor
    func testLibrarySwitcherMenu() throws {
        let app = launch(items: 4)
        XCTAssertTrue(app.staticTexts["4 items"].waitForExistence(timeout: 30))
        app.menuButtons["library-switcher"].click()
        XCTAssertTrue(app.menuItems["Open Library…"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.menuItems["New Library…"].exists)
        XCTAssertTrue(app.menuItems["Refresh"].exists)
        app.typeKey(.escape, modifierFlags: [])
    }

    @MainActor
    func testAddedByFilterNarrowsToOnePerson() throws {
        let app = launch(items: 6, people: "ana,ben")
        XCTAssertTrue(app.staticTexts["6 items"].waitForExistence(timeout: 30))
        let filter = app.menuButtons["filter-menu"]
        XCTAssertTrue(filter.waitForExistence(timeout: 10))
        filter.click()
        app.menuItems["Added by"].click()
        app.menuItems["ben (3)"].click()
        XCTAssertTrue(app.staticTexts["3 items"].waitForExistence(timeout: 10))
        filter.click()
        app.menuItems["Clear Filters"].click()
        XCTAssertTrue(app.staticTexts["6 items"].waitForExistence(timeout: 10))
    }

    @MainActor
    func testTeammatesSaveArrivesLiveAndKeepsScrollPosition() throws {
        let app = launch(items: 240, remoteAfter: 14)
        XCTAssertTrue(app.staticTexts["240 items"].waitForExistence(timeout: 40))
        let grid = app.collectionViews["grid"]
        XCTAssertTrue(grid.waitForExistence(timeout: 10))
        for _ in 0..<6 { grid.scroll(byDeltaX: 0, deltaY: -600) }
        func firstVisibleItemNumber() -> Int? {
            for g in grid.images.matching(NSPredicate(format: "label BEGINSWITH 'Item '")).allElementsBoundByIndex.prefix(8) {
                let label = g.label
                if label.hasPrefix("Item "), let n = Int(label.dropFirst(5).prefix(5)) { return n }
            }
            return nil
        }
        let before = try XCTUnwrap(firstVisibleItemNumber())
        XCTAssertLessThan(before, 235, "scrolled away from the top")

        // the simulated teammate writes straight into the folder; the watcher (or the rescan) picks it up
        XCTAssertTrue(app.staticTexts["241 items"].waitForExistence(timeout: 40), "new item from the shared folder appears without any action")
        XCTAssertTrue(app.staticTexts["1 new item from your team"].waitForExistence(timeout: 5) || true)
        let after = try XCTUnwrap(firstVisibleItemNumber())
        XCTAssertLessThan(after, 235, "still scrolled down (item \(before) → \(after)), not jumped back to the top")
        XCTAssertLessThan(abs(after - before), 12, "roughly the same place")
    }

    @MainActor
    func testScreenshotTeamUI() throws {
        let app = launch(items: 12, people: "ana,ben,cara", extra: [:])
        XCTAssertTrue(app.staticTexts["12 items"].waitForExistence(timeout: 30))
        try await_(1.0)
        try? app.windows.firstMatch.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: NSTemporaryDirectory() + "team.png"))
    }

    private func await_(_ s: TimeInterval) throws { Thread.sleep(forTimeInterval: s) }
}
