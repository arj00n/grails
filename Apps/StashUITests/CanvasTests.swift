import CoreGraphics
import XCTest

/// The canvas: an infinite pan/zoom board where items sit wherever they're put.
final class CanvasTests: XCTestCase {
    @MainActor
    private func launch(items: Int = 40, dir: String? = nil, extra: [String: String] = [:], args: [String] = []) -> (XCUIApplication, String) {
        let base = dir ?? "/private/tmp/stash-ui-tests/\(UUID().uuidString)"
        let app = XCUIApplication()
        app.launchEnvironment["STASH_LIBRARY"] = base + "/Lib.stash"
        app.launchEnvironment["STASH_SEED"] = "\(items)"
        app.launchEnvironment["STASH_SEED_PLAIN"] = "1"
        app.launchEnvironment["STASH_INDEX_PATH"] = base + "/index.sqlite"
        app.launchEnvironment["STASH_API_PORT"] = "47863"
        app.launchEnvironment["STASH_NO_MENUBAR"] = "1"
        app.launchEnvironment["STASH_TRACE"] = "1"
        for (k, v) in extra { app.launchEnvironment[k] = v }
        app.launchArguments += ["-viewMode", "canvas", "-layoutMode", "square", "-appearance", "light",
                                "-sidebar.expandCollections", "1", "-sidebar.expandTags", "0", "-sidebar.expandSmart", "1"] + args
        app.launch()
        app.activate()
        return (app, base)
    }

    // MARK: Helpers

    struct State { var scale: Double, ox: Double, oy: Double, placed: Int, visible: Int, selected: Int, sel: [Double]? }

    @MainActor
    private func state(_ app: XCUIApplication) throws -> State {
        let raw = try XCTUnwrap(app.descendants(matching: .any)["canvas"].value as? String)
        let j = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(raw.utf8)) as? [String: Any])
        return State(scale: j["scale"] as! Double, ox: j["ox"] as! Double, oy: j["oy"] as! Double, placed: j["placed"] as! Int,
                     visible: j["visible"] as! Int, selected: j["selected"] as! Int, sel: (j["sel"] as? [Any])?.compactMap { ($0 as? NSNumber)?.doubleValue })
    }

    @MainActor
    private func tile(_ app: XCUIApplication, _ number: Int) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", String(format: "Item %05d", number))).firstMatch
    }

    /// A point inside the canvas, in the canvas element's normalized coordinates, for a screen point.
    @MainActor
    private func at(_ app: XCUIApplication, screen p: CGPoint) -> XCUICoordinate {
        let f = app.descendants(matching: .any)["canvas"].frame
        return app.descendants(matching: .any)["canvas"].coordinate(withNormalizedOffset: CGVector(dx: (p.x - f.minX) / f.width, dy: (p.y - f.minY) / f.height))
    }

    @MainActor
    private func center(of e: XCUIElement) -> CGPoint { CGPoint(x: e.frame.midX, y: e.frame.midY) }

    @MainActor
    private func click(_ app: XCUIApplication, _ e: XCUIElement) { at(app, screen: center(of: e)).click() }

    @MainActor
    private func drag(_ app: XCUIApplication, _ e: XCUIElement, by d: CGVector) {
        let c = center(of: e)
        at(app, screen: c).click(forDuration: 0.1, thenDragTo: at(app, screen: CGPoint(x: c.x + d.dx, y: c.y + d.dy)))
    }

    @MainActor
    private func waitForTile(_ app: XCUIApplication, _ number: Int) -> XCUIElement {
        let t = tile(app, number)
        XCTAssertTrue(t.waitForExistence(timeout: 10), "tile \(number) should be visible")
        return t
    }

    @MainActor
    private func waitFor(_ timeout: TimeInterval = 5, _ cond: () throws -> Bool) rethrows -> Bool {
        let end = Date().addingTimeInterval(timeout)
        while Date() < end { if try cond() { return true }; Thread.sleep(forTimeInterval: 0.15) }
        return try cond()
    }

    // MARK: Tests

    @MainActor
    func testOpensFittedWithEveryItemPlaced() throws {
        let (app, _) = launch(items: 40)
        let canvas = app.descendants(matching: .any)["canvas"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 30))
        XCTAssertTrue(try waitFor { try state(app).placed == 40 })
        let s = try state(app)
        XCTAssertLessThan(s.scale, 1, "zoomed out to fit all 40 items")
        XCTAssertEqual(s.visible, 40, "all of them are on screen")
        XCTAssertTrue(tile(app, 39).exists)
    }

    @MainActor
    func testPanAndPointerAnchoredZoom() throws {
        let (app, _) = launch(items: 40)
        let canvas = app.descendants(matching: .any)["canvas"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 30))
        XCTAssertTrue(try waitFor { try state(app).placed == 40 })
        let f = canvas.frame
        let mid = CGPoint(x: f.midX, y: f.midY)
        let before = try state(app)
        canvas.scroll(byDeltaX: -240, deltaY: -180)                              // two-finger scroll pans
        XCTAssertTrue(try waitFor { let s = try state(app); return s.ox != before.ox && s.oy != before.oy })
        let panned = try state(app)
        XCTAssertEqual(panned.scale, before.scale, accuracy: 0.0001, "panning doesn't change the zoom")

        XCUIElement.perform(withKeyModifiers: .command) { canvas.scroll(byDeltaX: 0, deltaY: 240) }   // ⌘ + scroll zooms about the pointer
        XCTAssertTrue(try waitFor { try state(app).scale > panned.scale * 1.3 })
        let zoomed = try state(app)
        // the world point under the pointer stays under the pointer
        func world(_ s: State) -> (Double, Double) { (s.ox + Double(mid.x - f.minX) / s.scale, s.oy + Double(mid.y - f.minY) / s.scale) }
        XCTAssertEqual(world(zoomed).0, world(panned).0, accuracy: 6 / zoomed.scale)
        XCTAssertEqual(world(zoomed).1, world(panned).1, accuracy: 6 / zoomed.scale)

        XCUIElement.perform(withKeyModifiers: .command) { canvas.scroll(byDeltaX: 0, deltaY: -700) }
        XCTAssertTrue(try waitFor { try state(app).scale < zoomed.scale * 0.8 })
        app.typeKey("0", modifierFlags: .command)                                 // Zoom to Fit
        XCTAssertTrue(try waitFor(8) { abs(try state(app).scale - before.scale) < 0.02 }, "⌘0 fits everything again")
    }

    @MainActor
    func testClickSelectsMarqueeSelectsAndSelectAllWorks() throws {
        let (app, _) = launch(items: 40)
        let canvas = app.descendants(matching: .any)["canvas"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 30))
        XCTAssertTrue(try waitFor { try state(app).placed == 40 })
        click(app, tile(app, 39))
        XCTAssertTrue(try waitFor { try state(app).selected == 1 })
        // clicking empty space clears it, then a marquee over the top-left of the board picks up several
        let frame = canvas.frame
        canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.02, dy: 0.02)).click()
        XCTAssertTrue(try waitFor { try state(app).selected == 0 })
        let from = canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.02, dy: 0.02))
        let to = canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.55, dy: 0.45))
        from.click(forDuration: 0.1, thenDragTo: to)
        XCTAssertTrue(try waitFor { try state(app).selected >= 4 }, "marquee selected several items (frame \(frame))")
        app.typeKey("a", modifierFlags: .command)
        XCTAssertTrue(try waitFor { try state(app).selected == 40 })
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(try waitFor { try state(app).selected == 0 })
    }

    @MainActor
    func testDraggingAnItemMovesItUndoRestoresAndItPersists() throws {
        let (app, base) = launch(items: 40)
        let canvas = app.descendants(matching: .any)["canvas"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 30))
        XCTAssertTrue(try waitFor { try state(app).placed == 40 })
        let t = waitForTile(app, 39)
        click(app, t)
        XCTAssertTrue(try waitFor { try state(app).sel != nil })
        let start = try XCTUnwrap(try state(app).sel)

        drag(app, t, by: CGVector(dx: 120, dy: 90))
        XCTAssertTrue(try waitFor { (try state(app).sel?[0] ?? start[0]) != start[0] })
        let moved = try XCTUnwrap(try state(app).sel)
        let scale = try state(app).scale
        XCTAssertEqual(moved[0] - start[0], 120 / scale, accuracy: 6, "moved by the drag distance in world units")
        XCTAssertEqual(moved[1] - start[1], 90 / scale, accuracy: 6)
        XCTAssertEqual(moved[2], start[2], "size unchanged")

        // ⌘Z puts it back
        app.typeKey("z", modifierFlags: .command)
        XCTAssertTrue(try waitFor { abs((try state(app).sel?[0] ?? 0) - start[0]) < 2 })
        // ⇧⌘Z moves it again, and that is what gets saved
        app.typeKey("z", modifierFlags: [.command, .shift])
        XCTAssertTrue(try waitFor { abs((try state(app).sel?[0] ?? 0) - moved[0]) < 2 })
        Thread.sleep(forTimeInterval: 1.0)
        app.terminate()

        // relaunch the same library: the arrangement is on disk, not in memory
        let (again, _) = launch(items: 40, dir: base)
        XCTAssertTrue(again.descendants(matching: .any)["canvas"].waitForExistence(timeout: 30))
        XCTAssertTrue(try waitFor { try state(again).placed == 40 })
        _ = waitForTile(again, 39)
        click(again, tile(again, 39))
        XCTAssertTrue(try waitFor { try state(again).sel != nil })
        let restored = try XCTUnwrap(try state(again).sel)
        XCTAssertEqual(restored[0], moved[0], accuracy: 2)
        XCTAssertEqual(restored[1], moved[1], accuracy: 2)
    }

    @MainActor
    func testDroppingAnItemOnAnotherPushesItAsideAndUndoRestoresBoth() throws {
        let (app, _) = launch(items: 40)
        XCTAssertTrue(app.descendants(matching: .any)["canvas"].waitForExistence(timeout: 30))
        XCTAssertTrue(try waitFor { try state(app).placed == 40 })
        let mover = waitForTile(app, 2), target = waitForTile(app, 6)
        let targetStart = target.frame
        // drag the first onto the second, so that their centres coincide
        let from = center(of: mover), to = center(of: target)
        at(app, screen: from).click(forDuration: 0.1, thenDragTo: at(app, screen: to))
        XCTAssertTrue(try waitFor { tile(app, 6).frame != targetStart }, "the item underneath slid aside")
        // the pushed item ends up clear of the dropped one, with room between them
        XCTAssertTrue(try waitFor {
            let a = tile(app, 2).frame, b = tile(app, 6).frame
            return !a.insetBy(dx: -2, dy: -2).intersects(b)
        }, "no overlap after the drop")

        // one ⌘Z puts both back
        app.typeKey("z", modifierFlags: .command)
        XCTAssertTrue(try waitFor { abs(tile(app, 6).frame.minX - targetStart.minX) < 2 && abs(tile(app, 6).frame.minY - targetStart.minY) < 2 })
        XCTAssertTrue(try waitFor { abs(tile(app, 2).frame.midX - from.x) < 3 && abs(tile(app, 2).frame.midY - from.y) < 3 })
    }

    @MainActor
    func testArrangeAllPutsAStrayItemBackInRows() throws {
        let (app, _) = launch(items: 40, args: ["-canvasPush", "0"])      // this test is about Arrange; pushing would shift the neighbours too
        XCTAssertTrue(app.descendants(matching: .any)["canvas"].waitForExistence(timeout: 30))
        XCTAssertTrue(try waitFor { try state(app).placed == 40 })
        let t = waitForTile(app, 39)
        click(app, t)
        XCTAssertTrue(try waitFor { try state(app).sel != nil })
        let original = try XCTUnwrap(try state(app).sel)
        drag(app, t, by: CGVector(dx: 160, dy: 120))
        XCTAssertTrue(try waitFor { (try state(app).sel?[0] ?? original[0]) != original[0] })
        let stray = try XCTUnwrap(try state(app).sel)

        app.typeKey(.escape, modifierFlags: [])                                   // nothing selected ⇒ Arrange arranges everything
        XCTAssertTrue(try waitFor { try state(app).selected == 0 })
        app.typeKey("a", modifierFlags: [.command, .option])
        Thread.sleep(forTimeInterval: 1.0)
        _ = waitForTile(app, 39)
        click(app, tile(app, 39))
        XCTAssertTrue(try waitFor { try state(app).sel != nil })
        let tidy = try XCTUnwrap(try state(app).sel)
        XCTAssertNotEqual([tidy[0], tidy[1]], [stray[0], stray[1]], "the stray item moved")
        XCTAssertEqual(tidy[2], original[2], "sizes are kept")
        // every item is 240 wide with a 24 gap, so tidy rows put it on a 264-unit grid from the board's top-left
        let pitch = 264.0
        XCTAssertEqual((tidy[0] - original[0]).truncatingRemainder(dividingBy: pitch), 0, accuracy: 1.5, "snapped onto a column")
        XCTAssertEqual((tidy[1] - original[1]).truncatingRemainder(dividingBy: pitch), 0, accuracy: 1.5, "snapped onto a row")
        XCTAssertNotEqual((stray[0] - original[0]).truncatingRemainder(dividingBy: pitch), 0, accuracy: 1.5, "the drop really was off-grid")
    }

    @MainActor
    func testViewSwitcherAndShortcutsMoveBetweenGridAndCanvas() throws {
        let (app, _) = launch(items: 12)
        XCTAssertTrue(app.descendants(matching: .any)["canvas"].waitForExistence(timeout: 30))
        app.typeKey("1", modifierFlags: .command)
        XCTAssertTrue(app.collectionViews["grid"].waitForExistence(timeout: 10))
        app.typeKey("2", modifierFlags: .command)
        XCTAssertTrue(app.descendants(matching: .any)["canvas"].waitForExistence(timeout: 10))
        let switcher = app.radioGroups["view-switcher"]
        switcher.radioButtons.element(boundBy: 0).click()
        XCTAssertTrue(app.collectionViews["grid"].waitForExistence(timeout: 10))
        switcher.radioButtons.element(boundBy: 1).click()
        XCTAssertTrue(app.descendants(matching: .any)["canvas"].waitForExistence(timeout: 10))
    }

    @MainActor
    func testScreenshotCanvas() throws {
        let (app, _) = launch(items: 30)
        XCTAssertTrue(app.descendants(matching: .any)["canvas"].waitForExistence(timeout: 30))
        Thread.sleep(forTimeInterval: 2)
        try? app.windows.firstMatch.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: NSTemporaryDirectory() + "canvas.png"))
        print("CANVAS VALUE:", app.descendants(matching: .any)["canvas"].value ?? "nil")
    }
}
