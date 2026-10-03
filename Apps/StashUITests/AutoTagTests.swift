import XCTest

/// Auto-tagging with a stub classifier (STASH_AUTOTAG_STUB), so the tests exercise the app wiring (background run,
/// progress, sidebar, info panel, ⌘K) without depending on the model's opinions. The real model is covered by the
/// StashKit tests.
final class AutoTagTests: XCTestCase {
    @MainActor
    private func launch(people: String = "fixture,ben") -> XCUIApplication {
        let dir = "/private/tmp/stash-ui-tests/\(UUID().uuidString)"
        let app = XCUIApplication()
        app.launchEnvironment["STASH_LIBRARY"] = dir + "/Lib.stash"
        app.launchEnvironment["STASH_SEED"] = "40"
        app.launchEnvironment["STASH_SEED_PLAIN"] = "1"
        app.launchEnvironment["STASH_SEED_PEOPLE"] = people          // alternating: 20 items each
        app.launchEnvironment["STASH_INDEX_PATH"] = dir + "/index.sqlite"
        app.launchEnvironment["STASH_AUTOTAG_STUB"] = "stubfruit,stubleaf"
        app.launchEnvironment["STASH_SHOW_INFO"] = "1"
        app.launchArguments += ["-tileWidth", "90", "-layoutMode", "square", "-appearance", "light", "-userHandle", "fixture", "-viewMode", "grid",
                                "-sidebar.expandCollections", "1", "-sidebar.expandTags", "1", "-sidebar.expandSmart", "1"]
        app.launch()
        app.activate()
        return app
    }

    @MainActor
    private func type(_ text: String, in app: XCUIApplication) {
        for ch in text { app.typeKey(String(ch), modifierFlags: []) }
    }

    @MainActor
    func testYourOwnItemsAreTaggedInTheBackgroundAndTeammatesAreLeftAlone() throws {
        let app = launch()
        XCTAssertTrue(app.staticTexts["40 items"].waitForExistence(timeout: 30))

        // the sidebar gains the tags, with a count of only your own 20
        let tag = app.staticTexts["stubfruit"]
        XCTAssertTrue(tag.waitForExistence(timeout: 30), "auto tags appear in the sidebar")
        XCTAssertTrue(app.staticTexts["stubleaf"].exists)
        tag.click()
        XCTAssertTrue(app.staticTexts["20 items"].waitForExistence(timeout: 10), "only the 20 items you added")

        // the info panel marks them as automatic
        let grid = app.collectionViews["grid"]
        XCTAssertTrue(grid.waitForExistence(timeout: 10))
        grid.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0)).withOffset(CGVector(dx: 50, dy: 50)).click()
        let chip = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "#stubfruit, automatic")).firstMatch
        XCTAssertTrue(chip.waitForExistence(timeout: 10), "auto tags are marked in the info panel")
    }

    @MainActor
    func testTagAllCommandAlsoCoversTeammatesItems() throws {
        let app = launch()
        let tag = app.staticTexts["stubfruit"]
        XCTAssertTrue(tag.waitForExistence(timeout: 30))
        app.typeKey("k", modifierFlags: .command)
        let field = app.textFields["palette-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        type("auto-tag all", in: app)
        app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(app.staticTexts["Added 40 tags to 20 items"].waitForExistence(timeout: 30), "teammates' 20 items get the 2 tags each")
        tag.click()
        XCTAssertTrue(app.staticTexts["40 items"].waitForExistence(timeout: 10))
    }

    @MainActor
    func testRemovedAutoTagsStayRemoved() throws {
        let app = launch(people: "fixture")
        let tag = app.staticTexts["stubfruit"]
        XCTAssertTrue(tag.waitForExistence(timeout: 30))
        // select everything and strip the tag with the tag panel's toggle
        XCTAssertTrue(app.collectionViews["grid"].waitForExistence(timeout: 20))
        app.collectionViews["grid"].coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0)).withOffset(CGVector(dx: 50, dy: 50)).click()
        app.typeKey("a", modifierFlags: .command)
        app.typeKey("t", modifierFlags: [])
        XCTAssertTrue(app.textFields["tag-panel-field"].waitForExistence(timeout: 5))
        type("stubfruit", in: app)
        app.typeKey(.return, modifierFlags: [])      // toggles it off for all selected items
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(app.staticTexts["stubfruit"].waitForNonExistence(timeout: 10), "tag removed everywhere")
        // ⌘K "Auto-tag all" must not resurrect it: those items were already auto-tagged once
        app.typeKey("k", modifierFlags: .command)
        XCTAssertTrue(app.textFields["palette-field"].waitForExistence(timeout: 5))
        type("auto-tag all", in: app)
        app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(app.staticTexts["No new tags found"].waitForExistence(timeout: 30))
        XCTAssertFalse(app.staticTexts["stubfruit"].exists)
    }
}
