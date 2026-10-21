import XCTest

/// ⌘K and ⌘, come from the app menu. A button style on those items drops the key equivalent.
final class MenuShortcutTests: XCTestCase {
    @MainActor
    func testCommandPaletteAndSettingsShortcuts() throws {
        let dir = "/private/tmp/grails-ui-tests/\(UUID().uuidString)"
        let app = XCUIApplication()
        app.launchEnvironment["GRAILS_LIBRARY"] = dir + "/Lib.grails"
        app.launchEnvironment["GRAILS_SEED"] = "3"
        app.launchEnvironment["GRAILS_INDEX_PATH"] = dir + "/index.sqlite"
        app.launch()
        app.activate()
        XCTAssertTrue(app.staticTexts["Inbox"].waitForExistence(timeout: 20))

        app.typeKey(",", modifierFlags: .command)
        let settings = app.descendants(matching: .any)["settings-page"]
        XCTAssertTrue(settings.waitForExistence(timeout: 5), "⌘, opens Settings")
        let back = app.descendants(matching: .any)["settings-back"]
        XCTAssertTrue(back.waitForExistence(timeout: 5))
        back.click()
        XCTAssertTrue(settings.waitForNonExistence(timeout: 5))

        app.typeKey("k", modifierFlags: .command)
        XCTAssertTrue(app.textFields["palette-field"].waitForExistence(timeout: 5), "⌘K opens the command palette")
    }
}
