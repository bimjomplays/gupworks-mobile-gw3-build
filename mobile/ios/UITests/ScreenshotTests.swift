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

    // MARK: slice 4: answer, pick, command

    private let gallery = "00000009-1111-4222-8333-000000000009"
    private func chat(_ n: Int) -> String { String(format: "%08d-1111-4222-8333-%012d", n, n) }

    /// straight into a demo chat (the slice 4 ones aren't in the list)
    private func openChat(_ id: String, waitFor text: String) -> XCUIApplication {
        let app = launch(["-open", id])
        XCTAssertTrue(app.descendants(matching: .any)["chatTitle"].waitForExistence(timeout: 20))
        XCTAssertTrue(find(app, text).waitForExistence(timeout: 10), text)
        return app
    }

    private func el(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any)[id].firstMatch
    }

    func testNeedsYouPermission() {
        let app = openChat(chat(12), waitFor: "WAITING FOR PERMISSION")
        XCTAssertTrue(find(app, "make_icons.py").exists)
        XCTAssertTrue(app.buttons["choice-2"].exists)
        XCTAssertTrue(app.buttons["choice-3"].exists)
        XCTAssertGreaterThanOrEqual(app.buttons["choice-1"].frame.height, 44)
        sleep(1)
        shot("needs-permission")
        app.buttons["choice-1"].tap()
        XCTAssertTrue(el(app, "dialog-permission").waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.buttons["stop"].waitForExistence(timeout: 5), "Claude works on")
        sleep(1)
        shot("needs-permission-answered")
    }

    func testNeedsYouAskSomethingElse() {
        let app = openChat(chat(13), waitFor: "CLAUDE ASKS")
        XCTAssertTrue(find(app, "Which colour should the Send button be?").exists)
        XCTAssertTrue(find(app, "Warmer").exists)
        XCTAssertTrue(app.buttons["dialogChat"].exists)
        XCTAssertTrue(app.buttons["dialogSkip"].exists)
        sleep(1)
        shot("needs-ask")
        app.buttons["choice-4"].tap()
        let field = el(app, "dialogText")
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("Same green as the header")
        sleep(1)
        shot("needs-ask-typing")
        app.buttons["dialogSend"].tap()
        XCTAssertTrue(el(app, "dialog-ask").waitForNonExistence(timeout: 5))
    }

    func testNeedsYouPlan() {
        let app = openChat(chat(14), waitFor: "PLAN READY")
        XCTAssertTrue(find(app, "Journal page").exists)
        XCTAssertTrue(app.buttons["choice-1"].exists)
        sleep(1)
        shot("needs-plan")
        app.buttons["choice-3"].tap()
        XCTAssertTrue(el(app, "dialogText").waitForExistence(timeout: 5))
        sleep(1)
        shot("needs-plan-keep")
        app.buttons["Back"].tap()
        app.buttons["choice-1"].tap()
        XCTAssertTrue(el(app, "dialog-plan").waitForNonExistence(timeout: 5))
    }

    func testOlderHoldAnswersOnThePC() {
        let app = openChat(chat(15), waitFor: "Answer this on the PC")
        XCTAssertFalse(app.buttons["choice-1"].exists)
        sleep(1)
        shot("needs-on-pc")
    }

    func testD5Details() {
        let app = openChat(gallery, waitFor: "All five pages pass")
        app.buttons["usage"].tap()
        XCTAssertTrue(find(app, "Chat details").waitForExistence(timeout: 5))
        XCTAssertTrue(find(app, "Context").waitForExistence(timeout: 5))
        XCTAssertTrue(find(app, "warm").waitForExistence(timeout: 5))
        sleep(1)
        shot("d5-details")

        // Bypass off, then on again: the red word in the title follows
        let bypass = app.switches["bypass"]
        XCTAssertTrue(bypass.waitForExistence(timeout: 5))
        XCTAssertEqual(bypass.value as? String, "1")
        flip(bypass)
        XCTAssertTrue(waitValue(bypass, "0"))
        sleep(1)
        shot("d5-bypass-off")

        // effort for the next turn
        app.segmentedControls["effort"].buttons["high"].tap()
        XCTAssertTrue(el(app, "pending").waitForExistence(timeout: 5))
        sleep(1)
        shot("d5-effort")

        el(app, "modelRow").tap()
        XCTAssertTrue(find(app, "Sonnet 5.5").waitForExistence(timeout: 5))
        sleep(1)
        shot("d5-models")
        find(app, "Sonnet 5.5").tap()
        XCTAssertTrue(find(app, "Chat details").waitForExistence(timeout: 5))
        app.buttons["closeDetails"].tap()
        let title = el(app, "chatTitle")
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        XCTAssertTrue(title.label.contains("Sonnet 5.5"), title.label)
        XCTAssertFalse(title.label.contains("Bypass"), title.label)
        sleep(1)
        shot("d5-title-after")

        title.tap()
        let again = app.switches["bypass"]
        XCTAssertTrue(again.waitForExistence(timeout: 5))
        flip(again)
        XCTAssertTrue(waitValue(again, "1"))
        app.buttons["closeDetails"].tap()
        XCTAssertTrue(el(app, "chatTitle").label.contains("Bypass"))
    }

    /// a SwiftUI Toggle row: its switch sits at the right end
    private func flip(_ e: XCUIElement) {
        let inner = e.switches.firstMatch
        if inner.exists && inner.frame.width < e.frame.width {
            inner.tap()
        } else {
            e.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        }
    }

    private func waitValue(_ e: XCUIElement, _ v: String) -> Bool {
        let done = expectation(for: NSPredicate(format: "value == %@", v), evaluatedWith: e)
        return XCTWaiter.wait(for: [done], timeout: 5) == .completed
    }

    func testD4CommandsPinAndRun() {
        let app = openChat(gallery, waitFor: "All five pages pass")
        app.buttons["commands"].tap()
        XCTAssertTrue(app.buttons["pinned-compact"].waitForExistence(timeout: 5))
        XCTAssertTrue(find(app, "Recent").exists)
        sleep(1)
        shot("d4-commands")

        app.buttons["pin-context"].tap()
        XCTAssertTrue(app.buttons["pinned-context"].waitForExistence(timeout: 5))
        app.buttons["editPins"].tap()
        XCTAssertTrue(app.buttons["Unpin context"].waitForExistence(timeout: 5))
        sleep(1)
        shot("d4-edit-pins")
        app.buttons["Unpin context"].tap()
        XCTAssertTrue(app.buttons["pinned-context"].waitForNonExistence(timeout: 5))
        app.buttons["editPins"].tap()

        let search = app.searchFields.firstMatch
        search.tap()
        search.typeText("revi")
        XCTAssertTrue(app.buttons["cmd-code-review"].waitForExistence(timeout: 5))
        sleep(1)
        shot("d4-search")
        search.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 4))

        // a pinned command runs in the chat
        XCTAssertTrue(app.buttons["pinned-compact"].waitForExistence(timeout: 5))
        app.buttons["pinned-compact"].tap()
        XCTAssertTrue(app.buttons["pinned-compact"].waitForNonExistence(timeout: 5))
        XCTAssertTrue(find(app, "/compact").waitForExistence(timeout: 5))
        sleep(1)
        shot("d4-ran")
    }

    func testTypingSlashOpensCommands() {
        let app = openChat(gallery, waitFor: "All five pages pass")
        type(app, "/")
        XCTAssertTrue(app.buttons["pinned-compact"].waitForExistence(timeout: 5))
        let search = app.searchFields.firstMatch
        search.tap()
        search.typeText("btw")
        XCTAssertTrue(app.buttons["cmd-btw"].waitForExistence(timeout: 5))
        app.buttons["cmd-btw"].tap()
        let field = app.textFields["composer"].exists ? app.textFields["composer"] : app.textViews["composer"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        XCTAssertEqual(field.value as? String, "/btw ")
    }

    func testD7PressAndRewind() {
        let app = openChat(gallery, waitFor: "All five pages pass")
        let bubble = find(app, "The lightbox opens behind the header")
        XCTAssertTrue(bubble.waitForExistence(timeout: 5))
        bubble.press(forDuration: 1.2)
        let rewind = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Rewind to here'")).firstMatch
        XCTAssertTrue(rewind.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Copy"].exists)
        XCTAssertTrue(app.buttons["Ask btw about it"].exists)
        XCTAssertTrue(app.buttons["Select text"].exists)
        sleep(1)
        shot("d7-press")
        rewind.tap()
        XCTAssertTrue(app.buttons["Restore conversation"].waitForExistence(timeout: 5))
        sleep(1)
        shot("rewind-confirm")
        app.buttons["Restore conversation"].tap()
        let field = app.textFields["composer"].exists ? app.textFields["composer"] : app.textViews["composer"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        let back = expectation(for: NSPredicate(format: "value BEGINSWITH 'The lightbox opens'"), evaluatedWith: field)
        wait(for: [back], timeout: 5)
        // it lands on that prompt: the prompt and Claude's answer after it are gone from the chat
        XCTAssertFalse(find(app, "All five pages pass").exists)
        sleep(1)
        shot("rewind-restored")
    }

    func testD7AnswerSelectText() {
        let app = openChat(gallery, waitFor: "All five pages pass")
        find(app, "All five pages pass").press(forDuration: 1.2)
        XCTAssertTrue(app.buttons["Copy"].waitForExistence(timeout: 5))
        XCTAssertFalse(find(app, "Rewind to here").exists, "Claude's replies aren't rewind points")
        app.buttons["Select text"].tap()
        XCTAssertTrue(el(app, "selectText").waitForExistence(timeout: 5))
        sleep(1)
        shot("select-text")
        app.buttons["doneSelecting"].tap()
    }

    func testThreadNeedsYouAnswers() {
        let app = launch()
        open(app, "Lumen Studio website", waitFor: "THREAD NEEDS YOU")
        let first = app.buttons["askOption-0"]
        XCTAssertTrue(first.waitForExistence(timeout: 5))
        XCTAssertGreaterThanOrEqual(first.frame.height, 44)
        first.tap()
        XCTAssertTrue(find(app, "a6: Land it as is").waitForExistence(timeout: 5))
        XCTAssertTrue(find(app, "You answered").exists)
        sleep(1)
        shot("thread-answered")
    }

    // MARK: slice 5: voice (the demo's PC hears "Also let a swipe down close the lightbox on phones.")

    private let said = "Also let a swipe down close the lightbox on phones"

    /// waits until the recorder has given the box back and the words are in it
    private func expectInBox(_ app: XCUIApplication) {
        XCTAssertTrue(app.buttons["attach"].waitForExistence(timeout: 10), "the box is back")
        let field = app.textFields["composer"], view = app.textViews["composer"]
        XCTAssertTrue(field.waitForExistence(timeout: 2) || view.exists)
        let box = field.exists ? field : view
        expectation(for: NSPredicate(format: "value CONTAINS[c] %@", said), evaluatedWith: box)
        waitForExpectations(timeout: 10)
    }

    func testD8Recording() {
        let app = launch()
        open(app, "Gallery lightbox fix", waitFor: "All five pages pass")
        unfoldLast(app)
        XCTAssertTrue(find(app, "Checked all five pages").waitForExistence(timeout: 5))
        let mic = app.buttons["mic"]
        XCTAssertTrue(mic.waitForExistence(timeout: 5))
        XCTAssertGreaterThanOrEqual(mic.frame.width, 44)
        mic.tap()
        XCTAssertTrue(find(app, "Listening").waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["voiceCancel"].exists)
        XCTAssertTrue(app.buttons["voiceStop"].exists)
        XCTAssertFalse(app.buttons["attach"].exists, "the recorder takes the whole bottom")
        XCTAssertFalse(app.buttons["usage"].exists)
        // the timer at 0:04, as the mockup (the label changes once a second)
        _ = find(app, "Recording, 4 seconds").waitForExistence(timeout: 8)
        shot("d8-voice")
        // ■: the words go in the box to check first
        app.buttons["voiceStop"].tap()
        expectInBox(app)
        XCTAssertTrue(app.buttons["send"].exists)
        XCTAssertFalse(app.buttons["mic"].exists, "words in the box: ↑ instead of the mic")
        sleep(1)
        shot("d8-into-box")
    }

    func testD8SendStraightAway() {
        let app = launch()
        open(app, "Gallery lightbox fix", waitFor: "All five pages pass")
        app.buttons["mic"].tap()
        XCTAssertTrue(find(app, "Listening").waitForExistence(timeout: 5))
        sleep(2)
        app.buttons["mic"].tap()  // ↑ now
        XCTAssertTrue(find(app, said).waitForExistence(timeout: 10))
        XCTAssertTrue(find(app, "This is the demo").waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["mic"].waitForExistence(timeout: 5), "the box is empty again")
        sleep(1)
        shot("d8-sent")
    }

    func testD8Cancel() {
        let app = launch()
        open(app, "Gallery lightbox fix", waitFor: "All five pages pass")
        app.buttons["mic"].tap()
        XCTAssertTrue(find(app, "Listening").waitForExistence(timeout: 5))
        sleep(1)
        app.buttons["voiceCancel"].tap()
        XCTAssertTrue(app.buttons["attach"].waitForExistence(timeout: 5))
        XCTAssertFalse(find(app, "Listening").exists)
        sleep(2)  // nothing comes in later
        XCTAssertFalse(find(app, said).exists)
        XCTAssertTrue(app.buttons["mic"].exists)
    }

    func testD8HoldToTalk() {
        let app = launch()
        open(app, "Gallery lightbox fix", waitFor: "All five pages pass")
        app.buttons["mic"].press(forDuration: 2.5)
        expectInBox(app)
        XCTAssertFalse(find(app, "Listening").exists, "letting go ends the recording")
        XCTAssertFalse(find(app, "This is the demo").exists, "push-to-talk doesn't send")
        sleep(1)
        shot("d8-hold")
    }

    func testD8OnDeviceFallback() {
        let app = launch(["-voice-offline"])
        open(app, "Gallery lightbox fix", waitFor: "All five pages pass")
        app.buttons["mic"].tap()
        XCTAssertTrue(find(app, "Listening").waitForExistence(timeout: 5))
        sleep(2)
        app.buttons["voiceStop"].tap()
        XCTAssertTrue(find(app, "Transcribing on this iPhone").waitForExistence(timeout: 5))
        shot("d8-on-iphone")
        let note = app.descendants(matching: .any)["voiceNote"]
        XCTAssertTrue(note.waitForExistence(timeout: 10))
        XCTAssertTrue(find(app, "Transcribed on this iPhone").exists)
        expectInBox(app)
        // the note stays readable: above the box, clear of the keyboard
        let box = app.buttons["attach"].frame
        XCTAssertLessThanOrEqual(note.frame.maxY, box.minY + 1)
        let keyboard = app.keyboards.firstMatch
        if keyboard.exists { XCTAssertLessThanOrEqual(note.frame.maxY, keyboard.frame.minY) }
        XCTAssertTrue(note.exists)
        shot("d8-on-iphone-done")
    }
}
