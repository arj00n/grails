import XCTest

final class LaunchTests: XCTestCase {
    @MainActor
    func testAppLaunchesWithSidebar() throws {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.staticTexts["Inbox"].waitForExistence(timeout: 10))
    }
}
