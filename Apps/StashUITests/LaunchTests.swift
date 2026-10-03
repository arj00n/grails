import XCTest

final class LaunchTests: XCTestCase {
    @MainActor
    func testAppLaunchesWithSidebar() throws {
        let dir = "/private/tmp/stash-ui-tests/\(UUID().uuidString)"
        let app = XCUIApplication()
        app.launchEnvironment["STASH_LIBRARY"] = dir + "/Lib.stash"
        app.launchEnvironment["STASH_SEED"] = "3"
        app.launchEnvironment["STASH_INDEX_PATH"] = dir + "/index.sqlite"
        app.launchEnvironment["STASH_API_PORT"] = "47860"
        app.launchEnvironment["STASH_NO_MENUBAR"] = "1"
        app.launch()
        XCTAssertTrue(app.staticTexts["Inbox"].waitForExistence(timeout: 20))
    }
}
