import XCTest

final class LaunchTests: XCTestCase {
    @MainActor
    func testAppLaunchesWithSidebar() throws {
        let dir = "/private/tmp/grails-ui-tests/\(UUID().uuidString)"
        let app = XCUIApplication()
        app.launchEnvironment["GRAILS_LIBRARY"] = dir + "/Lib.grails"
        app.launchEnvironment["GRAILS_SEED"] = "3"
        app.launchEnvironment["GRAILS_INDEX_PATH"] = dir + "/index.sqlite"
        app.launchEnvironment["GRAILS_API_PORT"] = "47860"
        app.launchEnvironment["GRAILS_NO_MENUBAR"] = "1"
        app.launch()
        XCTAssertTrue(app.staticTexts["Inbox"].waitForExistence(timeout: 20))
    }
}
