import XCTest

/// Organizing flows on a small synthetic library the app creates itself (STASH_SEED), so the shared 20k fixture
/// is never modified.
///
/// XCUITest quirk on this OS: `typeText` can leave a stuck ⌘ flag on later key events (letters stop inserting, and a
/// 'q' becomes ⌘Q and quits the app). Sending each character with `typeKey(_, modifierFlags: [])` is reliable, so
/// all typing goes through `type(_:in:)`.
final class OrganizeTests: XCTestCase {
    @MainActor
    private func launch(items: Int = 40, panel: String? = nil) -> XCUIApplication {
        let dir = "/private/tmp/stash-ui-tests/\(UUID().uuidString)"
        let app = XCUIApplication()
        app.launchEnvironment["STASH_LIBRARY"] = dir + "/Lib.stash"
        app.launchEnvironment["STASH_SEED"] = "\(items)"
        app.launchEnvironment["STASH_SEED_PLAIN"] = "1"      // no collections, nothing liked
        app.launchEnvironment["STASH_INDEX_PATH"] = dir + "/index.sqlite"
        if let panel { app.launchEnvironment["STASH_PANEL"] = panel }
        // Pin persisted UI state: a previous run's click on a sidebar header can leave a section collapsed.
        app.launchArguments += ["-viewMode", "grid", "-tileWidth", "90", "-layoutMode", "square", "-appearance", "light",
                                "-sidebar.expandCollections", "1", "-sidebar.expandTags", "1", "-sidebar.expandSmart", "1"]
        app.launch()
        app.activate()
        return app
    }

    @MainActor
    private func type(_ text: String, in app: XCUIApplication) {
        for ch in text { app.typeKey(String(ch), modifierFlags: []) }
    }

    /// Click inside the first tile, then extend the selection with ⇧→ until `count` tiles are selected.
    @MainActor
    private func selectFirstTiles(_ app: XCUIApplication, count: Int = 1) {
        let grid = app.collectionViews["grid"]
        XCTAssertTrue(grid.waitForExistence(timeout: 20))
        grid.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0)).withOffset(CGVector(dx: 50, dy: 50)).click()
        for _ in 1..<max(count, 1) { app.typeKey(.rightArrow, modifierFlags: .shift) }
    }

    @MainActor
    func testMoveToNewCollectionThenTagThenUndoAndRedo() throws {
        let app = launch()
        XCTAssertTrue(app.staticTexts["40 items"].waitForExistence(timeout: 30))

        // M → type a new collection name → Enter creates it and moves the 3 selected items in
        selectFirstTiles(app, count: 3)
        app.typeKey("m", modifierFlags: [])
        let moveField = app.textFields["move-panel-field"]
        XCTAssertTrue(moveField.waitForExistence(timeout: 5))
        type("zzbox", in: app)
        XCTAssertTrue(app.staticTexts["New collection “zzbox”"].waitForExistence(timeout: 5))
        app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(app.staticTexts["zzbox"].waitForExistence(timeout: 10), "new collection shows in the sidebar")

        // back to All, T → new tag → Enter applies it
        app.staticTexts["All"].firstMatch.click()
        XCTAssertTrue(app.staticTexts["40 items"].waitForExistence(timeout: 10))
        selectFirstTiles(app, count: 3)
        app.typeKey("t", modifierFlags: [])
        let tagField = app.textFields["tag-panel-field"]
        XCTAssertTrue(tagField.waitForExistence(timeout: 5))
        type("zzhero", in: app)
        app.typeKey(.return, modifierFlags: [])
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(app.staticTexts["zzhero"].waitForExistence(timeout: 10), "new tag shows in the sidebar")

        // ⌘Z undoes the tag, ⌘Z again undoes the collection; ⇧⌘Z brings the collection back
        app.typeKey("z", modifierFlags: .command)
        XCTAssertTrue(app.staticTexts["zzhero"].waitForNonExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["zzbox"].exists)
        app.typeKey("z", modifierFlags: .command)
        XCTAssertTrue(app.staticTexts["zzbox"].waitForNonExistence(timeout: 10))
        app.typeKey("z", modifierFlags: [.command, .shift])
        XCTAssertTrue(app.staticTexts["zzbox"].waitForExistence(timeout: 10))
    }

    @MainActor
    func testLikeWithKeyboardThenSidebarAndFilterChip() throws {
        let app = launch()
        XCTAssertTrue(app.staticTexts["40 items"].waitForExistence(timeout: 30))
        selectFirstTiles(app, count: 2)
        app.typeKey("l", modifierFlags: [])
        app.staticTexts["Liked"].firstMatch.click()
        XCTAssertTrue(app.staticTexts["2 items"].waitForExistence(timeout: 10))
        app.staticTexts["All"].firstMatch.click()
        XCTAssertTrue(app.staticTexts["40 items"].waitForExistence(timeout: 10))
        // the filter menu narrows the same way
        app.menuButtons["filter-menu"].click()
        app.menuItems["Liked"].click()
        XCTAssertTrue(app.staticTexts["2 items"].waitForExistence(timeout: 10))
        app.menuButtons["filter-menu"].click()
        app.menuItems["Liked"].click()
        XCTAssertTrue(app.staticTexts["40 items"].waitForExistence(timeout: 10))
    }

    @MainActor
    func testCommandPaletteNavigates() throws {
        let app = launch(panel: "commandK")
        let field = app.textFields["palette-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 20))
        type("liked", in: app)
        app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(app.staticTexts["0 items"].waitForExistence(timeout: 10), "went to Liked (the plain seed has no liked items)")
        XCTAssertTrue(app.textFields["palette-field"].waitForNonExistence(timeout: 5))
    }

    @MainActor
    func testCommandPaletteRunsCommandThatNeedsAName() throws {
        let app = launch(panel: "commandK")
        let field = app.textFields["palette-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 20))
        type("new coll", in: app)
        app.typeKey(.return, modifierFlags: [])
        let prompt = app.textFields["prompt-field"]
        XCTAssertTrue(prompt.waitForExistence(timeout: 5))
        type("zzpalette", in: app)
        app.buttons["prompt-confirm"].click()
        XCTAssertTrue(app.staticTexts["zzpalette"].waitForExistence(timeout: 10))
    }

    @MainActor
    func testSearchFiltersLibraryThenClears() throws {
        let app = launch()
        XCTAssertTrue(app.staticTexts["40 items"].waitForExistence(timeout: 30))
        let search = app.searchFields.firstMatch
        search.click()
        type("zzznomatch", in: app)
        app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(app.staticTexts["0 items"].waitForExistence(timeout: 10))
        app.typeKey("a", modifierFlags: .command)
        app.typeKey(.delete, modifierFlags: [])
        XCTAssertTrue(app.staticTexts["40 items"].waitForExistence(timeout: 10))
    }

    @MainActor
    func testSmartFolderEditorCreatesFolder() throws {
        let app = launch()
        XCTAssertTrue(app.staticTexts["40 items"].waitForExistence(timeout: 30))
        app.menuButtons["sidebar-add"].click()
        app.menuItems["New Smart Folder…"].click()
        let name = app.textFields["smart-name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.click()
        type("zz", in: app)                      // appended to the default name
        app.buttons["smart-save"].click()
        XCTAssertTrue(app.staticTexts["Untitled smart folderzz"].waitForExistence(timeout: 10))
    }

    @MainActor
    func testNotePanelSavesSearchableNote() throws {
        let app = launch()
        XCTAssertTrue(app.staticTexts["40 items"].waitForExistence(timeout: 30))
        selectFirstTiles(app)
        app.typeKey("n", modifierFlags: [])
        let note = app.textViews["note-field"]
        XCTAssertTrue(note.waitForExistence(timeout: 5))
        type("zzuniquenote", in: app)
        app.buttons["Save"].click()
        // the note is searchable
        let search = app.searchFields.firstMatch
        search.click()
        type("zzuniquenote", in: app)
        app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(app.staticTexts["1 item"].waitForExistence(timeout: 10))
    }

    @MainActor
    func testShortcutSettingsDetectConflictsAndRebind() throws {
        let app = launch()
        XCTAssertTrue(app.staticTexts["40 items"].waitForExistence(timeout: 30))
        app.typeKey(",", modifierFlags: .command)                 // Settings
        let tab = app.toolbars.buttons["Shortcuts"]
        XCTAssertTrue(tab.waitForExistence(timeout: 5))
        tab.click()
        let like = app.buttons["shortcut-like"]
        XCTAssertTrue(like.waitForExistence(timeout: 5))
        XCTAssertEqual(like.label, "L")

        // "i" already toggles the info panel → refused with an explanation
        like.click()
        app.typeKey("i", modifierFlags: [])
        XCTAssertTrue(app.staticTexts["Already used by “Show or hide info panel”"].waitForExistence(timeout: 5))
        // Space is fixed → refused
        app.typeKey(" ", modifierFlags: [])
        XCTAssertTrue(app.staticTexts["Space opens the preview"].waitForExistence(timeout: 5))
        // a free key is accepted
        app.typeKey("j", modifierFlags: [])
        XCTAssertTrue(app.buttons["shortcut-like"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["shortcut-like"].label, "J")
        // leave the app's persisted defaults clean for the next test run
        app.buttons["Reset all to defaults"].click()
        XCTAssertEqual(app.buttons["shortcut-like"].label, "L")
    }

    @MainActor
    func testZoomShortcutsResizeTiles() throws {
        let app = launch()
        XCTAssertTrue(app.staticTexts["40 items"].waitForExistence(timeout: 30))
        let grid = app.collectionViews["grid"]
        XCTAssertTrue(grid.waitForExistence(timeout: 10))
        // tiles are the grid's Group children; the first matches the whole content, so look at the second
        func tileWidth() -> CGFloat { grid.groups.element(boundBy: 2).frame.width }
        let small = tileWidth()
        XCTAssertGreaterThan(small, 20)
        func waitForWidth(_ test: (CGFloat) -> Bool) -> CGFloat {
            for _ in 0..<40 { let w = tileWidth(); if test(w) { return w }; Thread.sleep(forTimeInterval: 0.1) }
            return tileWidth()
        }
        // ⌘+ is a smooth animated zoom (×1.25 each) that settles with tiles filling the row
        app.typeKey("=", modifierFlags: .command)
        app.typeKey("=", modifierFlags: .command)
        let bigger = waitForWidth { $0 > small * 1.3 }
        XCTAssertGreaterThan(bigger, small * 1.3, "tiles grew after zooming in (\(small) → \(bigger))")
        app.typeKey("-", modifierFlags: .command)
        app.typeKey("-", modifierFlags: .command)
        let back = waitForWidth { $0 < bigger * 0.85 }
        XCTAssertLessThan(back, bigger * 0.85, "and shrank again (\(bigger) → \(back))")
        XCTAssertFalse(app.sliders.firstMatch.exists, "no zoom slider any more")
    }

    /// ⌘ + two-finger scroll zooms continuously (a pinch takes the same path; XCUITest can't synthesize one on macOS).
    @MainActor
    func testCommandScrollZoomsTheGrid() throws {
        let app = launch(items: 60)
        XCTAssertTrue(app.staticTexts["60 items"].waitForExistence(timeout: 30))
        let grid = app.collectionViews["grid"]
        XCTAssertTrue(grid.waitForExistence(timeout: 10))
        func tileWidth() -> CGFloat { grid.groups.element(boundBy: 2).frame.width }
        func settled() -> CGFloat {
            var last = tileWidth()
            for _ in 0..<30 { Thread.sleep(forTimeInterval: 0.15); let w = tileWidth(); if abs(w - last) < 0.5 { return w }; last = w }
            return last
        }
        let before = settled()
        XCUIElement.perform(withKeyModifiers: .command) { grid.scroll(byDeltaX: 0, deltaY: 120) }
        let zoomedIn = settled()
        XCTAssertGreaterThan(zoomedIn, before * 1.3, "⌘-scroll up made tiles bigger (\(before) → \(zoomedIn))")
        XCUIElement.perform(withKeyModifiers: .command) { grid.scroll(byDeltaX: 0, deltaY: -240) }
        let zoomedOut = settled()
        XCTAssertLessThan(zoomedOut, zoomedIn * 0.8, "⌘-scroll down made them smaller (\(zoomedIn) → \(zoomedOut))")
    }
}
