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

    // MARK: the overhaul (5a-5h): ChatGPT's layout with GupWorks inside

    /// the box's text field (a vertical TextField is a text view or a text field, by iOS version)
    private func box(_ app: XCUIApplication) -> XCUIElement {
        app.textFields["composer"].exists ? app.textFields["composer"] : app.textViews["composer"]
    }

    private func hasFocus(_ e: XCUIElement) -> Bool {
        let focus = expectation(for: NSPredicate(format: "hasKeyboardFocus == true"), evaluatedWith: e)
        return XCTWaiter.wait(for: [focus], timeout: 10) == .completed
    }

    /// the menu button, then the menu's first rows
    private func openMenu(_ app: XCUIApplication) {
        let button = app.buttons["menu"]
        XCTAssertTrue(button.waitForExistence(timeout: 20))
        button.tap()
        XCTAssertTrue(el(app, "place-projects").waitForExistence(timeout: 5))
    }

    func test5aOpensOnANewChat() {
        let app = launch()
        let field = app.textFields["composer"]
        XCTAssertTrue(field.waitForExistence(timeout: 20) || app.textViews["composer"].exists)
        XCTAssertTrue(hasFocus(box(app)), "the keyboard is up")
        for id in ["attach", "gauge", "usage", "commands", "mic", "send", "menu", "temporaryChat"] {
            XCTAssertTrue(app.buttons[id].exists, id)
        }
        XCTAssertFalse(el(app, "chatTitle").exists, "a new chat has no title yet")
        XCTAssertTrue(app.buttons["gauge"].value.map { "\($0)" }?.contains("Opus 5.5") ?? false)
        // a fresh simulator's first keyboard shows a slide-to-type tip; it's not part of the app
        if app.buttons["Continue"].waitForExistence(timeout: 2) {
            app.buttons["Continue"].tap()
            XCTAssertTrue(hasFocus(box(app)))
        }
        sleep(1)
        shot("5a-new-chat")
        box(app).typeText("Plan a picnic for six")
        sleep(1)
        shot("new-chat")
        app.buttons["send"].tap()
        XCTAssertTrue(find(app, "This is the demo").waitForExistence(timeout: 5))
        XCTAssertTrue(el(app, "chatTitle").waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["compose"].exists)
        sleep(1)
        shot("new-chat-sent")
        // compose: a fresh new chat again
        app.buttons["compose"].tap()
        XCTAssertTrue(el(app, "chatTitle").waitForNonExistence(timeout: 5))
        XCTAssertFalse(find(app, "This is the demo").exists)
    }

    func test5bTemporaryChat() {
        let app = launch()
        let toggle = app.buttons["temporaryChat"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 20))
        XCTAssertEqual(toggle.value as? String, "Off")
        toggle.tap()
        XCTAssertTrue(el(app, "temporaryNote").waitForExistence(timeout: 5))
        XCTAssertEqual(toggle.value as? String, "On")
        sleep(1)
        shot("5b-temporary")
        box(app).tap()
        box(app).typeText("Quick sum: 17 times 23")
        app.buttons["send"].tap()
        XCTAssertTrue(find(app, "This is the demo").waitForExistence(timeout: 5))
        // leaving deletes it: not in the menu, and the chat behind the menu is a fresh one
        openMenu(app)
        XCTAssertFalse(el(app, "chat-Quick sum: 17 times 23").exists)
        el(app, "closeMenu").tap()
        XCTAssertTrue(el(app, "place-projects").waitForNonExistence(timeout: 5))
        XCTAssertFalse(find(app, "This is the demo").exists)
        XCTAssertEqual(app.buttons["temporaryChat"].value as? String, "Off")
        // off again by its button
        app.buttons["temporaryChat"].tap()
        XCTAssertTrue(el(app, "temporaryNote").waitForExistence(timeout: 5))
        app.buttons["temporaryChat"].tap()
        XCTAssertTrue(el(app, "temporaryNote").waitForNonExistence(timeout: 5))
    }

    func test5cMenu() {
        let app = launch()
        openMenu(app)
        for id in ["place-projects", "place-scheduled", "place-quick", "place-bot", "pin-Lumen Studio website",
                   "pin-Home server", "pin-Wallpaper ideas", "pin-Gallery lightbox fix", "chat-Recipe scaler",
                   "newChat", "settings", "search"] {
            XCTAssertTrue(el(app, id).exists, id)
        }
        // in 5c's order: places, Pinned, Recents
        XCTAssertLessThan(el(app, "place-bot").frame.minY, el(app, "pin-Lumen Studio website").frame.minY)
        XCTAssertLessThan(el(app, "pin-Carrot picture").frame.minY, el(app, "chat-Recipe scaler").frame.minY)
        sleep(1)
        shot("5c-menu")

        el(app, "pin-Gallery lightbox fix").tap()
        XCTAssertTrue(find(app, "All five pages pass").waitForExistence(timeout: 10))
        XCTAssertTrue(el(app, "place-projects").waitForNonExistence(timeout: 5))

        // a swipe right in the chat opens the menu too
        let win = app.windows.firstMatch
        win.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.45))
            .press(forDuration: 0.05, thenDragTo: win.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.47)),
                   withVelocity: .fast, thenHoldForDuration: 0)
        XCTAssertTrue(el(app, "place-projects").waitForExistence(timeout: 5), "the swipe opened the menu")
        sleep(1)
        shot("5c-menu-from-chat")
        el(app, "newChat").tap()
        XCTAssertTrue(el(app, "place-projects").waitForNonExistence(timeout: 5))
        XCTAssertFalse(el(app, "chatTitle").exists, "a new chat")
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

    func test5eChatWithADraft() {
        let app = openChat(gallery, waitFor: "All five pages pass")
        XCTAssertTrue(app.buttons["gauge"].value.map { "\($0)" }?.contains("Bypass") ?? false)
        box(app).tap()
        box(app).typeText("Also make the close button bigger on phones")
        sleep(1)
        shot("5e-chat")
    }

    func test5fModelAndEffort() {
        let app = openChat(gallery, waitFor: "All five pages pass")
        app.buttons["gauge"].tap()
        XCTAssertTrue(find(app, "Model and effort").waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["model-claude-sonnet-5-5"].waitForExistence(timeout: 5))
        XCTAssertTrue(el(app, "effort").exists)
        XCTAssertTrue(app.buttons["moreModels"].exists, "OpenAI folds after two")
        sleep(1)
        shot("5f-model-effort")
        app.buttons["model-claude-sonnet-5-5"].tap()
        XCTAssertTrue(app.buttons["model-claude-sonnet-5-5"].isSelected)
        app.buttons["effort-low"].tap()
        XCTAssertTrue(el(app, "pending").waitForExistence(timeout: 5))
        app.buttons["moreModels"].tap()
        XCTAssertTrue(app.buttons["model-gpt-5.6-luna"].waitForExistence(timeout: 5))
        app.buttons["closeModels"].tap()
        XCTAssertTrue(app.buttons["closeModels"].waitForNonExistence(timeout: 5))
        let value = app.buttons["gauge"].value.map { "\($0)" } ?? ""
        XCTAssertTrue(value.contains("Sonnet 5.5") && value.contains("low"), value)
    }

    func test5gUsage() {
        let app = openChat(gallery, waitFor: "All five pages pass")
        app.buttons["usage"].tap()
        XCTAssertTrue(el(app, "usageCard").waitForExistence(timeout: 5))
        XCTAssertTrue(el(app, "usage-ctx").label.contains("tokens"), el(app, "usage-ctx").label)
        XCTAssertTrue(el(app, "usage-5h").label.contains("18%"), el(app, "usage-5h").label)
        XCTAssertTrue(el(app, "usage-5h").label.contains("resets in"), el(app, "usage-5h").label)
        XCTAssertTrue(el(app, "usage-wk").label.contains("41%"), el(app, "usage-wk").label)
        // small and whole: narrower than the screen, and every row inside the card
        let card = el(app, "usageCard").frame
        XCTAssertLessThanOrEqual(card.width, 340, "\(card)")
        XCTAssertLessThan(card.height, 260, "\(card)")
        for l in ["ctx", "5h", "wk"] {
            let r = el(app, "usage-\(l)").frame
            XCTAssertTrue(card.insetBy(dx: -1, dy: -1).contains(r), "usage-\(l) \(r) outside \(card)")
        }
        sleep(1)
        shot("5g-usage")
        el(app, "closeUsage").tap()
        XCTAssertTrue(el(app, "usageCard").waitForNonExistence(timeout: 5))
    }

    func testMenuSearch() {
        let app = launch(["-menu"])
        XCTAssertTrue(el(app, "search").waitForExistence(timeout: 20))
        el(app, "search").tap()
        let field = app.textFields["searchField"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        XCTAssertTrue(hasFocus(field))
        field.typeText("re")
        XCTAssertTrue(el(app, "found-Recipe scaler").waitForExistence(timeout: 5))
        XCTAssertFalse(el(app, "found-Wallpaper ideas").exists)
        XCTAssertTrue(el(app, "said-Gallery lightbox fix").waitForExistence(timeout: 5), "what was said, from the PC")
        sleep(1)
        shot("menu-search")
        el(app, "said-Gallery lightbox fix").tap()
        XCTAssertTrue(find(app, "All five pages pass").waitForExistence(timeout: 10))
    }

    func testSettings() {
        let app = launch(["-menu"])
        XCTAssertTrue(app.buttons["settings"].waitForExistence(timeout: 20))
        app.buttons["settings"].tap()
        XCTAssertTrue(find(app, "This PC").waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["unpair"].exists)
        sleep(1)
        shot("settings")
    }

    func testRecentsPress() {
        let app = launch(["-menu"])
        let row = el(app, "chat-Recipe scaler")
        XCTAssertTrue(row.waitForExistence(timeout: 20))
        row.press(forDuration: 1.2)
        XCTAssertTrue(app.buttons["Rename"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Pin"].exists)
        XCTAssertTrue(app.buttons["Archive"].exists)
        XCTAssertTrue(app.buttons["Delete\u{2026}"].exists)
        sleep(1)
        shot("menu-press")
        app.buttons["Delete\u{2026}"].tap()
        XCTAssertTrue(find(app, "Delete \u{201C}Recipe scaler\u{201D}?").waitForExistence(timeout: 5))
        sleep(1)
        shot("menu-delete-confirm")
        app.buttons["Delete"].firstMatch.tap()
        XCTAssertTrue(el(app, "chat-Recipe scaler").waitForNonExistence(timeout: 5))
        // a pin from the same menu: it joins Pinned at the top
        el(app, "chat-Trip packing list").press(forDuration: 1.2)
        XCTAssertTrue(app.buttons["Pin"].waitForExistence(timeout: 5))
        app.buttons["Pin"].tap()
        XCTAssertTrue(el(app, "pin-Trip packing list").waitForExistence(timeout: 5))
    }

    func testProjectsPage() {
        let app = launch(["-menu"])
        XCTAssertTrue(el(app, "place-projects").waitForExistence(timeout: 20))
        el(app, "place-projects").tap()
        let folder = el(app, "folder-At home")
        XCTAssertTrue(folder.waitForExistence(timeout: 5))
        XCTAssertTrue(find(app, "Garden planner").exists)
        sleep(1)
        shot("projects")
        folder.tap()
        XCTAssertTrue(find(app, "Garden planner").waitForNonExistence(timeout: 5))
        find(app, "Lumen Studio website").tap()
        XCTAssertTrue(el(app, "tab-threads").waitForExistence(timeout: 10))
    }

    func testComingSoonPlaces() {
        let app = launch(["-menu"])
        for p in ["scheduled", "quick", "bot"] {
            if !el(app, "place-\(p)").exists { openMenu(app) }
            XCTAssertTrue(el(app, "place-\(p)").waitForExistence(timeout: 20))
            el(app, "place-\(p)").tap()
            XCTAssertTrue(el(app, "comingSoon").waitForExistence(timeout: 5), p)
            if p == "bot" { sleep(1); shot("coming-soon") }
            app.navigationBars.buttons.element(boundBy: 0).tap()
            XCTAssertTrue(el(app, "comingSoon").waitForNonExistence(timeout: 5))
        }
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

    /// unfolds the newest turn (its handle is the last one)
    private func unfoldLast(_ app: XCUIApplication) {
        let handles = app.buttons.matching(identifier: "handle")
        XCTAssertTrue(handles.firstMatch.waitForExistence(timeout: 5))
        handles.element(boundBy: handles.count - 1).tap()
    }

    func testD2Chat() {
        let app = openChat(gallery, waitFor: "All five pages pass")
        XCTAssertTrue(find(app, "Bypass").exists)
        unfoldLast(app)
        XCTAssertTrue(find(app, "Fixed style.css").waitForExistence(timeout: 5))
        XCTAssertTrue(find(app, "Checked all five pages").exists)
        sleep(1)
        shot("d2-chat")
    }

    func testD2Folded() {
        let app = openChat(gallery, waitFor: "All five pages pass")
        sleep(1)
        shot("d2-folded")
    }

    func testStepCard() {
        let app = openChat(gallery, waitFor: "All five pages pass")
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
        // straight in (`-open`), so the project sheet that comes up from the list row isn't over the chat
        let app = openChat(lumen, waitFor: "THREAD NEEDS YOU")
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
        let app = openChat(gallery, waitFor: "All five pages pass")
        type(app, "Also make the close button bigger on phones")
        XCTAssertTrue(app.buttons["send"].waitForExistence(timeout: 5))
        sleep(1)
        shot("d3-typing")
        app.buttons["send"].tap()
        XCTAssertTrue(find(app, "This is the demo").waitForExistence(timeout: 5))
        sleep(1)
        shot("chat-sent")
    }

    /// x inside the screen (an element scrolled off still has its real x)
    private func onScreen(_ app: XCUIApplication, _ e: XCUIElement, _ what: String) {
        let screen = app.windows.firstMatch.frame
        XCTAssertTrue(e.exists, what)
        XCTAssertGreaterThanOrEqual(e.frame.minX, screen.minX - 0.5, "\(what) starts left of the screen: \(e.frame)")
        XCTAssertLessThanOrEqual(e.frame.maxX, screen.maxX + 0.5, "\(what) ends right of the screen: \(e.frame)")
    }

    /// a120: a message with six photos once laid them in one row wider than the screen, which widened the whole
    /// chat: the box and its send button went off screen and nothing could be sent. Messages with 1, 3, 12, only
    /// photos and 6 photos: every picture, the words and the box stay inside the screen.
    func testPhotosStayInsideTheScreen() {
        let six = "Here are six photos of the living room"
        let app = openChat(chat(16), waitFor: six)
        let words = find(app, six)
        onScreen(app, words, "the 6-photo message's words")
        XCTAssertGreaterThan(words.frame.height, 40, "the words wrap onto more lines")
        onScreen(app, el(app, "chatTitle"), "the title")
        onScreen(app, box(app), "the box")
        let send = app.buttons["send"]
        onScreen(app, send, "the send button")
        XCTAssertTrue(send.isHittable, "the send button can be tapped")
        let pictures = app.buttons.matching(identifier: "yourPicture")
        // the newest message's six at least (the older ones too when the chat lists them while off screen)
        XCTAssertGreaterThanOrEqual(pictures.count, 6, "the photos show")
        for i in 0..<pictures.count {
            onScreen(app, pictures.element(boundBy: i), "photo \(i + 1)")
        }
        sleep(1)
        shot("photos-6")
        // still typeable and sendable
        box(app).tap()
        box(app).typeText("Fog it is")
        onScreen(app, send, "the send button while typing")
        XCTAssertTrue(send.isHittable)
        sleep(1)
        shot("photos-typing")
        app.buttons["send"].tap()
        XCTAssertTrue(find(app, "This is the demo").waitForExistence(timeout: 5))
        // up to the twelve photos and the message that is only photos
        let twelve = find(app, "Every room, so you can see")
        for _ in 0..<6 where !(twelve.exists && twelve.isHittable) {
            app.swipeDown()
        }
        onScreen(app, twelve, "the 12-photo message's words")
        onScreen(app, send, "the send button with the 12 photos in view")
        sleep(1)
        shot("photos-12")
        let three = find(app, "And these three for the bedroom")
        for _ in 0..<6 where !(three.exists && three.isHittable) {
            app.swipeDown()
        }
        onScreen(app, three, "the 3-photo message's words")
        XCTAssertTrue(app.descendants(matching: .any)["picture"].exists, "Claude's pictures show")
        sleep(1)
        shot("photos-1-3")
    }

    func testAttachMenu() {
        let app = openChat(gallery, waitFor: "All five pages pass")
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

    func testD6MoreRenameAndDelete() {
        let app = openChat(gallery, waitFor: "All five pages pass")
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

    // MARK: slice 4: answer, pick, command

    private let gallery = "00000009-1111-4222-8333-000000000009"
    private func chat(_ n: Int) -> String { String(format: "%08d-1111-4222-8333-%012d", n, n) }

    /// straight into a demo chat (the slice 4 ones aren't in the list)
    private func openChat(_ id: String, waitFor text: String, _ extra: [String] = []) -> XCUIApplication {
        let app = launch(["-open", id] + extra)
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
        el(app, "chatTitle").tap()
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
        // straight in (`-open`), so the project sheet that comes up from the list row isn't over the chat
        let app = openChat(lumen, waitFor: "THREAD NEEDS YOU")
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
        let app = openChat(gallery, waitFor: "All five pages pass")
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
        shot("5h-voice")
        // ■: the words go in the box to check first
        app.buttons["voiceStop"].tap()
        expectInBox(app)
        XCTAssertTrue(app.buttons["send"].exists)
        XCTAssertTrue(app.buttons["mic"].exists, "the mic stays beside ↑ (5a)")
        sleep(1)
        shot("d8-into-box")
    }

    func testD8SendStraightAway() {
        let app = openChat(gallery, waitFor: "All five pages pass")
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
        let app = openChat(gallery, waitFor: "All five pages pass")
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
        let app = openChat(gallery, waitFor: "All five pages pass")
        app.buttons["mic"].press(forDuration: 2.5)
        expectInBox(app)
        XCTAssertFalse(find(app, "Listening").exists, "letting go ends the recording")
        XCTAssertFalse(find(app, "This is the demo").exists, "push-to-talk doesn't send")
        sleep(1)
        shot("d8-hold")
    }

    func testD8OnDeviceFallback() {
        let app = openChat(gallery, waitFor: "All five pages pass", ["-voice-offline"])
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

    // MARK: slice 6: projects (D9)

    private let lumen = "00000066-1111-4222-8333-000000000066"

    /// the Lumen main chat with its sheet at full height (the Threads button)
    private func openThreads(_ extra: [String] = []) -> XCUIApplication {
        let app = launch(["-open", lumen] + extra)
        XCTAssertTrue(app.descendants(matching: .any)["chatTitle"].waitForExistence(timeout: 20))
        let button = app.buttons["threadsButton"]
        XCTAssertTrue(button.waitForExistence(timeout: 10))
        button.tap()
        XCTAssertTrue(el(app, "tab-threads").waitForExistence(timeout: 5))
        XCTAssertTrue(el(app, "thread-a6").waitForExistence(timeout: 5))
        sleep(1)
        return app
    }

    func testD9Project() {
        // from its pin in the menu: the main chat with its sheet at half height
        let app = launch(["-menu"])
        XCTAssertTrue(el(app, "pin-Lumen Studio website").waitForExistence(timeout: 20))
        el(app, "pin-Lumen Studio website").tap()
        XCTAssertTrue(el(app, "tab-threads").waitForExistence(timeout: 10))
        XCTAssertTrue(find(app, "Contrast pass").waitForExistence(timeout: 5))
        XCTAssertTrue(find(app, "Contact page form").exists)
        XCTAssertTrue(find(app, "2 working").exists)
        XCTAssertTrue(app.buttons["threadsButton"].exists)
        sleep(2)
        shot("d9-project")
    }

    func testD9ThreadsFull() {
        let app = openThreads()
        XCTAssertTrue(find(app, "Gallery lightbox fix").exists)
        XCTAssertTrue(find(app, "Usage").exists)
        shot("d9-threads")
        // a folded group opens on tap
        el(app, "group-Done").tap()
        XCTAssertTrue(el(app, "thread-a1").waitForExistence(timeout: 5))
        sleep(1)
        shot("d9-done-open")
    }

    func testD9SwipePauseAndDone() {
        let app = openThreads()
        drag(app, el(app, "thread-a6"), from: 0.9, to: 0.4)
        XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Pause"].exists)
        sleep(1)
        shot("d9-swipe")
        app.buttons["Pause"].tap()
        // a6 leaves Needs you for Idle, with the paused glyph
        XCTAssertTrue(find(app, "Idle").waitForExistence(timeout: 5))
        XCTAssertFalse(find(app, "1 needs you").exists)
        XCTAssertTrue(find(app, "Paused").exists)
        sleep(1)
        shot("d9-paused")
        drag(app, el(app, "thread-a6"), from: 0.9, to: 0.4)
        XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 5))
        app.buttons["Done"].tap()
        XCTAssertTrue(el(app, "thread-a6").waitForNonExistence(timeout: 5))
        XCTAssertTrue(find(app, "Done").exists)
        // the working thread swipes to Pause and Archive (the PC marks only idle or waiting threads done)
        drag(app, el(app, "thread-a4"), from: 0.9, to: 0.4)
        XCTAssertTrue(app.buttons["Pause"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Archive"].exists)
    }

    func testD9LongPressThread() {
        let app = openThreads()
        el(app, "thread-a4").press(forDuration: 1.2)
        XCTAssertTrue(app.buttons["Stop\u{2026}"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Open chat"].exists)
        sleep(1)
        shot("d9-press")
        app.buttons["Stop\u{2026}"].tap()
        XCTAssertTrue(find(app, "Stop \u{201C}Contact page form\u{201D}?").waitForExistence(timeout: 5))
    }

    func testD9NewThread() {
        let app = openThreads()
        app.buttons["newThread"].tap()
        let box = app.textViews["newThreadText"]
        XCTAssertTrue(box.waitForExistence(timeout: 5))
        box.typeText("Add the studio hours to the footer")
        sleep(1)
        shot("d9-new-thread")
        app.buttons["startThread"].tap()
        XCTAssertTrue(find(app, "Add the studio hours to the footer").waitForExistence(timeout: 5))
        XCTAssertTrue(find(app, "3 working").exists)
        sleep(1)
        shot("d9-new-thread-started")
    }

    func testD9OpenThread() {
        let app = openThreads()
        el(app, "thread-a5").tap()
        // the sheet goes and the thread's chat is pushed over the main chat
        XCTAssertTrue(find(app, "All five pages pass").waitForExistence(timeout: 10))
        XCTAssertFalse(el(app, "tab-threads").exists)
        sleep(1)
        shot("d9-open-thread")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(find(app, "THREAD NEEDS YOU").waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["threadsButton"].exists)
    }

    func testD9Library() {
        let app = openThreads()
        el(app, "tab-library").tap()
        XCTAssertTrue(el(app, "lib-Ideas").waitForExistence(timeout: 5))
        XCTAssertTrue(find(app, "Pinned").exists)
        XCTAssertTrue(find(app, "From threads").exists)
        sleep(1)
        shot("d9-library")
        el(app, "lib-Memory").tap()
        XCTAssertTrue(el(app, "lib-MEMORY.md").waitForExistence(timeout: 5))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        el(app, "lib-Palette.md").tap()
        XCTAssertTrue(el(app, "noteText").waitForExistence(timeout: 5))
        sleep(1)
        shot("d9-note")
        app.buttons["noteEdit"].tap()
        let editor = app.textViews["noteEditor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        editor.typeText("\n- Sand for the footer")
        sleep(1)
        shot("d9-note-edit")
        app.buttons["noteSave"].tap()
        XCTAssertTrue(el(app, "noteSaved").waitForExistence(timeout: 5))
        XCTAssertTrue(find(app, "Sand for the footer").exists)
        sleep(1)
        shot("d9-note-saved")
    }

    func testD9LibraryPicture() {
        let app = openThreads()
        el(app, "tab-library").tap()
        let row = el(app, "lib-contact-form.png")
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()
        XCTAssertTrue(el(app, "libraryPicture").waitForExistence(timeout: 5))
        sleep(2)
        shot("d9-library-picture")
    }

    func testD9NoteConflict() {
        let app = openThreads(["-noteConflict"])
        el(app, "tab-library").tap()
        XCTAssertTrue(el(app, "lib-Ideas").waitForExistence(timeout: 5))
        el(app, "lib-Ideas").tap()
        app.buttons["noteEdit"].tap()
        let editor = app.textViews["noteEditor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        editor.typeText("\n- A night mode")
        app.buttons["noteSave"].tap()
        XCTAssertTrue(app.alerts["This note changed on the PC"].waitForExistence(timeout: 5))
        sleep(1)
        shot("d9-note-conflict")
        app.alerts.buttons["Keep mine"].tap()
        XCTAssertTrue(el(app, "noteSaved").waitForExistence(timeout: 5))
    }

    func testD9Scheduled() {
        let app = openThreads()
        el(app, "tab-scheduled").tap()
        XCTAssertTrue(find(app, "Lighthouse report").waitForExistence(timeout: 5))
        XCTAssertTrue(find(app, "Portfolio refresh").exists)
        sleep(1)
        shot("d9-scheduled")
    }

    func testD9ProjectMenu() {
        let app = openChat(lumen, waitFor: "THREAD NEEDS YOU")
        app.buttons["more"].tap()
        XCTAssertTrue(app.buttons["Pause project"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Archive project\u{2026}"].exists)
        sleep(1)
        shot("d9-project-menu")
        app.buttons["Pause project"].tap()
        sleep(1)
        app.buttons["more"].tap()
        XCTAssertTrue(app.buttons["Resume project"].waitForExistence(timeout: 5))
        app.buttons["Project info"].tap()
        XCTAssertTrue(find(app, "A one-page site").waitForExistence(timeout: 5))
        sleep(1)
        shot("d9-project-info")
    }
}
