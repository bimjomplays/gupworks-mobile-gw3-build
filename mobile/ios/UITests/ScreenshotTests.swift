import XCTest

/// The few screens that need the system's own touches and media: sorting pins by a held drag, the video player, and
/// pairing (a typed return). Everything else moved to Tests/ScreenTests.swift, which drives the screens inside the
/// unit-test process in seconds. Each picture is attached to the test result and, when the runner sets SHOTS_DIR
/// (TEST_RUNNER_SHOTS_DIR for xcodebuild), also written there as a PNG.
final class ScreenshotTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    private func launch(_ extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-demo"] + extra
        app.launch()
        return app
    }

    /// any element whose label contains `text` (rows combine their texts into one accessibility element)
    private func find(_ app: XCUIApplication, _ text: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS[c] %@", text)).firstMatch
    }

    private func shot(_ name: String) {
        let png = XCUIScreen.main.screenshot().pngRepresentation
        let a = XCTAttachment(data: png, uniformTypeIdentifier: "public.png")
        a.name = name
        a.lifetime = .keepAlways
        add(a)
        if let dir = ProcessInfo.processInfo.environment["SHOTS_DIR"], !dir.isEmpty {
            try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            try? png.write(to: URL(fileURLWithPath: dir).appendingPathComponent(name + ".png"))
        }
    }

    /// the menu button, then the menu's first rows
    private func openMenu(_ app: XCUIApplication) {
        let button = app.buttons["menu"]
        XCTAssertTrue(button.waitForExistence(timeout: 20))
        button.tap()
        XCTAssertTrue(el(app, "place-projects").waitForExistence(timeout: 5))
    }

    func test5dSortPins() {
        let app = launch(["-menu"])
        let wallpaper = el(app, "pin-Wallpaper ideas"), lumenRow = el(app, "pin-Lumen Studio website")
        XCTAssertTrue(wallpaper.waitForExistence(timeout: 20))
        XCTAssertLessThan(lumenRow.frame.minY, wallpaper.frame.minY)
        // hold, then drag to the top: it takes the first slot
        wallpaper.press(forDuration: 0.9, thenDragTo: lumenRow, withVelocity: .slow, thenHoldForDuration: 0.4)
        XCTAssertTrue(el(app, "doneSorting").waitForExistence(timeout: 5))
        XCTAssertTrue(find(app, "Drag to reorder").exists, "every pin shows its handle")
        XCTAssertLessThan(wallpaper.frame.minY, lumenRow.frame.minY, "Wallpaper ideas moved to the top")
        sleep(1)
        shot("5d-sorting")
        el(app, "doneSorting").tap()
        XCTAssertTrue(el(app, "doneSorting").waitForNonExistence(timeout: 5))
        // the order is kept: closed and opened again, it's the same
        el(app, "closeMenu").tap()
        openMenu(app)
        XCTAssertLessThan(el(app, "pin-Wallpaper ideas").frame.minY, el(app, "pin-Lumen Studio website").frame.minY)
    }

    func testPairing() {
        let app = launch(["-unpaired"])
        XCTAssertTrue(find(app, "Pair with your PC").waitForExistence(timeout: 20))
        let field = app.textFields["pairCode"]
        field.tap()
        field.typeText("https://example.com\n")
        XCTAssertTrue(app.descendants(matching: .any)["pairProblem"].waitForExistence(timeout: 5))
        shot("pairing")
    }

    /// opens a chat from the menu (Pinned or Recents) by its title and waits for its turns
    private func open(_ app: XCUIApplication, _ title: String, waitFor text: String) {
        openMenu(app)
        let pin = el(app, "pin-\(title)"), chat = el(app, "chat-\(title)")
        XCTAssertTrue(pin.waitForExistence(timeout: 10) || chat.exists, title)
        let row = pin.exists ? pin : chat
        // the last rows sit under New chat until scrolled up
        let bottom = app.windows.firstMatch.frame.height - 110
        for _ in 0..<4 where row.frame.maxY > bottom {
            app.swipeUp()
        }
        row.tap()
        XCTAssertTrue(el(app, "chatTitle").waitForExistence(timeout: 10))
        XCTAssertTrue(find(app, text).waitForExistence(timeout: 10), text)
    }

    func testLiveChatWithPictures() {
        let app = launch()
        open(app, "Wallpaper ideas", waitFor: "Working")
        sleep(2)  // the clock ticks
        shot("chat-live")
        let video = app.descendants(matching: .any)["video"]
        app.swipeDown()
        XCTAssertTrue(video.waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["picture"].exists)
        sleep(1)
        shot("chat-media")
        // its top: the composer may cover the rest
        video.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.15)).tap()
        XCTAssertTrue(app.buttons["Close"].waitForExistence(timeout: 5))
        sleep(2)
        shot("video")
    }

    private func el(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any)[id].firstMatch
    }
}
