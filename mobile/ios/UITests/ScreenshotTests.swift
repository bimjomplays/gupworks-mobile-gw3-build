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
        XCTAssertTrue(app.descendants(matching: .any)["cardDetail"].waitForExistence(timeout: 10))
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
        // its top: the composer may cover the rest
        video.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.15)).tap()
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
        XCTAssertTrue(app.descendants(matching: .any)["cardDetail"].waitForExistence(timeout: 10))
        XCTAssertTrue(find(app, "change_dir").waitForExistence(timeout: 5))
        sleep(1)
        shot("card-failed")
    }

    // MARK: slice 3: talking

    private func type(_ app: XCUIApplication, _ text: String) {
        let field = app.textFields["composer"].exists ? app.textFields["composer"] : app.textViews["composer"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText(text)
    }

    func testD3Typing() {
        let app = launch()
        open(app, "Gallery lightbox fix", waitFor: "All five pages pass")
        type(app, "Also make the close button bigger on phones")
        XCTAssertTrue(app.buttons["send"].waitForExistence(timeout: 5))
        sleep(1)
        shot("d3-typing")
        app.buttons["send"].tap()
        XCTAssertTrue(find(app, "This is the demo").waitForExistence(timeout: 5))
        sleep(1)
        shot("chat-sent")
    }

    func testAttachMenu() {
        let app = launch()
        open(app, "Gallery lightbox fix", waitFor: "All five pages pass")
        app.buttons["attach"].tap()
        XCTAssertTrue(app.buttons["Photos"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Files"].exists)
        XCTAssertTrue(app.buttons["Camera"].exists)
        sleep(1)
        shot("attach-menu")
    }

    func testQueuedThenStop() {
        let app = launch()
        open(app, "Wallpaper ideas", waitFor: "Working")
        XCTAssertTrue(app.buttons["stop"].waitForExistence(timeout: 5))
        sleep(1)
        shot("working-stop")
        type(app, "Then make a lock screen version too")
        app.buttons["send"].tap()
        XCTAssertTrue(find(app, "queued").waitForExistence(timeout: 5))
        sleep(1)
        shot("queued")
        app.buttons["stop"].tap()
        XCTAssertTrue(find(app, "This is the demo").waitForExistence(timeout: 5))
        XCTAssertFalse(find(app, "queued · sends").exists)
        XCTAssertFalse(app.buttons["stop"].exists)
        sleep(1)
        shot("stopped")
    }

    func testNewChat() {
        let app = launch()
        XCTAssertTrue(find(app, "Wallpaper ideas").waitForExistence(timeout: 20))
        app.buttons["newChat"].tap()
        XCTAssertTrue(find(app, "A new chat on your PC").waitForExistence(timeout: 5))
        type(app, "Plan a picnic for six")
        sleep(1)
        shot("new-chat")
        app.buttons["send"].tap()
        XCTAssertTrue(find(app, "This is the demo").waitForExistence(timeout: 5))
        XCTAssertTrue(find(app, "Plan a picnic for six").exists)
        sleep(1)
        shot("new-chat-sent")
    }

    func testD6MoreRenameAndDelete() {
        let app = launch()
        open(app, "Gallery lightbox fix", waitFor: "All five pages pass")
        app.buttons["more"].tap()
        XCTAssertTrue(app.buttons["Rename"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Pin to top"].exists)
        XCTAssertTrue(app.buttons["Archive"].exists)
        XCTAssertTrue(app.buttons["Delete\u{2026}"].exists)
        sleep(1)
        shot("d6-more")

        app.buttons["Rename"].tap()
        let alert = app.alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 5), app.debugDescription)
        let field = alert.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5), app.debugDescription)
        // the cursor to the end, then the old title out
        field.coordinate(withNormalizedOffset: CGVector(dx: 0.97, dy: 0.5)).tap()
        if let old = field.value as? String {
            field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: old.count))
        }
        field.typeText("Lightbox on phones")
        sleep(1)
        shot("rename")
        alert.buttons["Rename"].tap()
        XCTAssertTrue(find(app, "Lightbox on phones").waitForExistence(timeout: 5))

        app.buttons["more"].tap()
        app.buttons["Delete\u{2026}"].tap()
        XCTAssertTrue(find(app, "Delete this chat?").waitForExistence(timeout: 5))
        sleep(1)
        shot("delete-confirm")
        app.buttons["Delete"].firstMatch.tap()
        // back on the list, without it
        XCTAssertTrue(app.descendants(matching: .any)["chatTitle"].waitForNonExistence(timeout: 10))
        XCTAssertFalse(find(app, "Lightbox on phones").exists)
    }

    /// a slow partial drag across a row, so its swipe buttons show (a quick full swipe would run the first one)
    private func drag(_ app: XCUIApplication, _ row: XCUIElement, from: CGFloat, to: CGFloat) {
        let win = app.windows.firstMatch
        let y = row.frame.midY / win.frame.height
        let start = win.coordinate(withNormalizedOffset: CGVector(dx: from, dy: y))
        let end = win.coordinate(withNormalizedOffset: CGVector(dx: to, dy: y))
        start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.3)
    }

    func testD1Swipes() {
        let app = launch()
        let row = find(app, "Carrot picture")
        XCTAssertTrue(row.waitForExistence(timeout: 20))
        drag(app, row, from: 0.1, to: 0.4)
        XCTAssertTrue(app.buttons["Pin"].waitForExistence(timeout: 5))
        sleep(1)
        shot("d1-swipe-pin")
        app.buttons["Pin"].tap()
        sleep(1)
        let recipe = find(app, "Recipe scaler")
        drag(app, recipe, from: 0.9, to: 0.45)
        XCTAssertTrue(app.buttons["Archive"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Delete"].exists)
        sleep(1)
        shot("d1-swipe-left")
        app.buttons["Delete"].tap()
        XCTAssertTrue(find(app, "Delete \u{201C}Recipe scaler\u{201D}?").waitForExistence(timeout: 5))
        sleep(1)
        shot("d1-delete-confirm")
    }

    func testD1LongPress() {
        let app = launch()
        let row = find(app, "Recipe scaler")
        XCTAssertTrue(row.waitForExistence(timeout: 20))
        row.press(forDuration: 1.2)
        XCTAssertTrue(app.buttons["Rename"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Delete\u{2026}"].exists)
        sleep(1)
        shot("d1-press")
    }
}
