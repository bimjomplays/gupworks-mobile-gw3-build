import XCTest

/// The few screens that need the system's own touches and media: sorting pins by a held drag, the video player, the
/// Overview's swipe actions, and pairing (a typed return). Everything else moved to Tests/ScreenTests.swift, which
/// drives the screens inside the unit-test process in seconds. Each picture is attached to the test result and, when the runner sets SHOTS_DIR
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

    // ci-covers: MenuView.swift Rows.swift
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

    // ci-covers: PairingView.swift Pairing.swift QRScanner.swift
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

    // ci-covers: MediaViews.swift ChatView.swift
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

    // MARK: the Overview's swipe actions and press menu (a list's swipe needs the system's own touches)

    private let lumen = "00000066-1111-4222-8333-000000000066"

    private func project(_ extra: [String] = []) -> XCUIApplication {
        let app = launch(["-place", "projects", "-push", lumen] + extra)
        XCTAssertTrue(el(app, "projectPill").waitForExistence(timeout: 20))
        return app
    }

    private func overview(_ extra: [String] = []) -> XCUIApplication {
        let app = project(["-sheet"] + extra)
        XCTAssertTrue(el(app, "overviewGlance").waitForExistence(timeout: 10))
        return app
    }

    private func drag(_ app: XCUIApplication, _ row: XCUIElement, from: CGFloat, to: CGFloat) {
        let win = app.windows.firstMatch
        let y = row.frame.midY / win.frame.height
        let start = win.coordinate(withNormalizedOffset: CGVector(dx: from, dy: y))
        let end = win.coordinate(withNormalizedOffset: CGVector(dx: to, dy: y))
        start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.3)
    }

    // ci-covers: ProjectOverview.swift
    func testP06SwipeAndPress() {
        let app = overview()
        drag(app, el(app, "thread-a6"), from: 0.9, to: 0.4)
        XCTAssertTrue(app.buttons["Pause"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Mark done"].exists)
        sleep(1)
        shot("06-swipe")
        app.buttons["Pause"].tap()
        drag(app, el(app, "thread-a6"), from: 0.9, to: 0.4)
        XCTAssertTrue(app.buttons["Resume"].waitForExistence(timeout: 5))
        app.buttons["Resume"].tap()
        el(app, "thread-a4").press(forDuration: 1.2)
        XCTAssertTrue(app.buttons["Stop\u{2026}"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Open thread"].exists)
        app.buttons["Stop\u{2026}"].tap()
        XCTAssertTrue(find(app, "Stop \u{201C}Contact page form\u{201D}?").waitForExistence(timeout: 5))
    }

    private func el(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any)[id].firstMatch
    }
}
