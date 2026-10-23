import XCTest

/// Screenshots of the app in demo mode (bundled invented fixtures, no PC needed). Each one is attached to the test
/// result and, when the runner sets SHOTS_DIR (TEST_RUNNER_SHOTS_DIR for xcodebuild), also written there as a PNG.
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

    func testD1ChatsList() {
        let app = launch()
        XCTAssertTrue(find(app, "Wallpaper ideas").waitForExistence(timeout: 20))
        XCTAssertTrue(find(app, "Lumen Studio website").exists)
        sleep(1)
        shot("d1-chats")
    }

    func testD1Search() {
        let app = launch()
        XCTAssertTrue(find(app, "Wallpaper ideas").waitForExistence(timeout: 20))
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("re")
        XCTAssertTrue(find(app, "Recipe scaler").waitForExistence(timeout: 5))
        XCTAssertFalse(find(app, "Wallpaper ideas").exists)
        sleep(1)
        shot("d1-search")
    }

    func testSettings() {
        let app = launch()
        XCTAssertTrue(find(app, "Wallpaper ideas").waitForExistence(timeout: 20))
        app.buttons["settings"].tap()
        XCTAssertTrue(find(app, "This PC").waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["unpair"].exists)
        sleep(1)
        shot("settings")
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

    // MARK: slice 2: chats

    /// opens a chat from the list by its row title and waits for its turns
    private func open(_ app: XCUIApplication, _ title: String, waitFor text: String) {
        XCTAssertTrue(find(app, "Wallpaper ideas").waitForExistence(timeout: 20))
        let row = find(app, title)
        // the list is lazy: rows below the screen only exist once scrolled to
        for _ in 0..<8 where !(row.exists && row.isHittable) {
            app.swipeUp()
        }
        XCTAssertTrue(row.waitForExistence(timeout: 5), title)
        row.tap()
        XCTAssertTrue(app.descendants(matching: .any)["chatTitle"].waitForExistence(timeout: 10))
        XCTAssertTrue(find(app, text).waitForExistence(timeout: 10), text)
    }

    /// unfolds the newest turn (its handle is the last one)
    private func unfoldLast(_ app: XCUIApplication) {
        let handles = app.buttons.matching(identifier: "handle")
        XCTAssertTrue(handles.firstMatch.waitForExistence(timeout: 5))
        handles.element(boundBy: handles.count - 1).tap()
    }

    func testD2Chat() {
        let app = launch()
        open(app, "Gallery lightbox fix", waitFor: "All five pages pass")
        XCTAssertTrue(find(app, "Bypass").exists)
        unfoldLast(app)
        XCTAssertTrue(find(app, "Fixed style.css").waitForExistence(timeout: 5))
        XCTAssertTrue(find(app, "Checked all five pages").exists)
        sleep(1)
        shot("d2-chat")
    }

    func testD2Folded() {
        let app = launch()
        open(app, "Gallery lightbox fix", waitFor: "All five pages pass")
        sleep(1)
        shot("d2-folded")
    }

    func testStepCard() {
        let app = launch()
        open(app, "Gallery lightbox fix", waitFor: "All five pages pass")
        unfoldLast(app)
        let card = find(app, "Fixed style.css")
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        card.tap()
        XCTAssertTrue(find(app, "style.css").waitForExistence(timeout: 5))
        XCTAssertTrue(find(app, "Done").waitForExistence(timeout: 5))
        sleep(1)
        shot("d2-card")
    }

    func testD11MainChat() {
        let app = launch()
        open(app, "Lumen Studio website", waitFor: "THREAD NEEDS YOU")
        XCTAssertTrue(find(app, "Main chat").exists)
        XCTAssertTrue(find(app, "Land it as is").exists)
        sleep(1)
        shot("d11-main")
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
        video.tap()
        XCTAssertTrue(app.buttons["Close"].waitForExistence(timeout: 5))
        sleep(2)
        shot("video")
    }

    func testFailedCard() {
        let app = launch()
        open(app, "Photo backup script", waitFor: "The backup didn")
        unfoldLast(app)
        XCTAssertTrue(find(app, "Tried the backup once").waitForExistence(timeout: 5))
        sleep(1)
        shot("chat-failed")
        find(app, "Tried the backup once").tap()
        XCTAssertTrue(find(app, "Failed").waitForExistence(timeout: 5))
        sleep(1)
        shot("card-failed")
    }
}
