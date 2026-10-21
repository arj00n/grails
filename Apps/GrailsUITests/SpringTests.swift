import XCTest

final class SpringTests: XCTestCase {
    /// Cmd-K and GRAILS_SCREEN=spring use the same sheet. It has to open at the modal size, with a card, not as a blank strip.
    @MainActor
    func testSpringSheetPresentsAtFullSizeWithACard() {
        let dir = "/private/tmp/grails-ui-tests/\(UUID().uuidString)"
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let app = XCUIApplication()
        app.launchEnvironment["GRAILS_LIBRARY"] = dir + "/Lib.grails"
        app.launchEnvironment["GRAILS_SEED"] = "1"
        app.launchEnvironment["GRAILS_SEED_PLAIN"] = "1"
        app.launchEnvironment["GRAILS_INDEX_PATH"] = dir + "/index.sqlite"
        app.launchEnvironment["GRAILS_NO_MENUBAR"] = "1"
        app.launchEnvironment["GRAILS_API_PORT"] = "47921"
        app.launchEnvironment["GRAILS_SCREEN"] = "spring"
        app.launch()
        let sheet = app.sheets.firstMatch
        XCTAssertTrue(sheet.waitForExistence(timeout: 20), app.debugDescription)
        let frame = sheet.frame
        XCTAssertGreaterThanOrEqual(frame.width, 430, "sheet \(frame)")
        XCTAssertLessThanOrEqual(frame.width, 460, "sheet \(frame)")
        XCTAssertGreaterThanOrEqual(frame.height, 520, "sheet \(frame)")
        let card = sheet.descendants(matching: .any)["spring-card"]
        XCTAssertTrue(card.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertGreaterThanOrEqual(card.frame.width, 380, "card \(card.frame)")
        XCTAssertGreaterThanOrEqual(card.frame.height, 380, "card \(card.frame)")
        XCTAssertLessThanOrEqual(card.frame.height, card.frame.width + 8, "portrait media stays square \(card.frame)")
        let chuck = sheet.buttons["spring-chuck"].frame
        let keep = sheet.buttons["spring-keep"].frame
        if chuck.minX > 0, keep.minX > 0 {
            XCTAssertLessThan(chuck.midX, keep.midX, "chuck sits left of keep")
        }
    }

    /// Left chucks the front card. Right keeps the next one. Both keys have to land on the deck.
    @MainActor
    func testArrowKeysChuckThenKeep() {
        let dir = "/private/tmp/grails-ui-tests/\(UUID().uuidString)"
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let app = XCUIApplication()
        app.launchEnvironment["GRAILS_LIBRARY"] = dir + "/Lib.grails"
        app.launchEnvironment["GRAILS_SEED"] = "1"
        app.launchEnvironment["GRAILS_SEED_PLAIN"] = "1"
        app.launchEnvironment["GRAILS_INDEX_PATH"] = dir + "/index.sqlite"
        app.launchEnvironment["GRAILS_NO_MENUBAR"] = "1"
        app.launchEnvironment["GRAILS_API_PORT"] = "47922"
        app.launchEnvironment["GRAILS_SCREEN"] = "spring"
        app.launch()
        let sheet = app.sheets.firstMatch
        XCTAssertTrue(sheet.waitForExistence(timeout: 20), app.debugDescription)
        let card = sheet.descendants(matching: .any)["spring-card"]
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        sheet.typeKey(.leftArrow, modifierFlags: [])
        XCTAssertTrue(waitForCard(card, label: "Video", timeout: 4), "left arrow should chuck the image \(card.label)")
        sheet.typeKey(.rightArrow, modifierFlags: [])
        XCTAssertTrue(sheet.staticTexts["All tidy. Nothing to clean up."].waitForExistence(timeout: 4), app.debugDescription)
    }

    private func waitForCard(_ card: XCUIElement, label: String, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if card.label == label { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        return card.label == label
    }
}
