import XCTest
@testable import GupWorks3

/// The app's screens in demo mode (bundled invented fixtures, no PC needed), driven inside the unit-test process
/// (ScreenDriver.swift): what each screen shows, what a tap or a press does, and the docs/mobile-shots pictures. Each
/// picture is attached to the test result and, when the runner sets SHOTS_DIR (TEST_RUNNER_SHOTS_DIR for xcodebuild),
/// also written there as a PNG. These were XCUITests (about 20 s each); here a test takes a few seconds. Gestures
/// that need the system's own touches stay in UITests/.
@MainActor
final class ScreenTests: XCTestCase {
    override nonisolated func setUp() {
        continueAfterFailure = false
    }

    override nonisolated func tearDown() {
        MainActor.assumeIsolated {
            // a failed test leaves its last screen and what was on it, to see why
            if let run = testRun, run.failureCount > 0, let app = App.current {
                let name = name.components(separatedBy: " ").last?.trimmingCharacters(in: CharacterSet(charactersIn: "]")) ?? "test"
                app.shot("fail-\(name)")
                print("SCREEN at the failure of \(name):\n\(app.debugDescription)")
            }
            App.current?.close()
        }
    }

    /// waits with the app running (Darwin's sleep would freeze it)
    private func sleep(_ seconds: UInt32) { spin(Double(seconds)) }

    private func launch(_ extra: [String] = []) -> App {
        App(extra, test: self)
    }

    /// any element whose label contains `text` (rows combine their texts into one accessibility element)
    private func find(_ app: App, _ text: String) -> Element {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS[c] %@", text)).firstMatch
    }

    private func shot(_ name: String) {
        App.current?.shot(name)
    }

    // MARK: the overhaul (5a-5h): ChatGPT's layout with GupWorks inside

    /// the box's text field (a vertical TextField is a text view or a text field, by iOS version)
    private func box(_ app: App) -> Element {
        app.textFields["composer"].exists ? app.textFields["composer"] : app.textViews["composer"]
    }

    private func hasFocus(_ e: Element) -> Bool {
        poll(10) { e.hasKeyboardFocus }
    }

    /// the menu button, then the menu's first rows
    private func openMenu(_ app: App) {
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
        for id in ["place-projects", "place-scheduled", "place-quick", "place-transfer", "place-bot", "pin-Lumen Studio website",
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
        XCTAssertEqual(card.width, 300, accuracy: 1, "the card keeps its fixed width: \(card)")
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

    /// a118: on home (no chat yet) the rings draw empty and the button does nothing; the first message wakes it
    func test5gUsageIsOffOnHome() {
        let app = launch()
        let usage = app.buttons["usage"]
        XCTAssertTrue(usage.waitForExistence(timeout: 20))
        XCTAssertTrue(hasFocus(box(app)), "the keyboard is up, as in the screenshot that showed the sliver")
        XCTAssertEqual(usage.value as? String, "No chat yet", "the rings are empty")
        usage.tap()
        sleep(1)
        XCTAssertFalse(el(app, "usageCard").exists, "the button opens nothing on home")
        XCTAssertFalse(el(app, "closeUsage").exists)
        shot("a118-home-usage-off")
        box(app).typeText("Plan a picnic for six")
        app.buttons["send"].tap()
        XCTAssertTrue(find(app, "This is the demo").waitForExistence(timeout: 5))
        XCTAssertNotEqual(usage.value as? String, "No chat yet", "now there is a chat")
        usage.tap()
        XCTAssertTrue(el(app, "usageCard").waitForExistence(timeout: 5), "the card opens in a chat")
        XCTAssertEqual(el(app, "usageCard").frame.width, 300, accuracy: 1)
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

    // MARK: a121: the Projects pages (docs/projects-mobile-mockups 01-12)

    private func projects(_ extra: [String] = []) -> App {
        let app = launch(["-place", "projects"] + extra)
        XCTAssertTrue(el(app, "project-lumen-studio").waitForExistence(timeout: 20))
        return app
    }

    /// 01: newest first with what each is doing; a tap opens the project's main chat; search finds chats too
    func testP01Projects() {
        let app = projects()
        XCTAssertTrue(find(app, "Needs you").exists)
        XCTAssertLessThan(el(app, "project-lumen-studio").frame.minY, el(app, "project-garden-planner-1a2b").frame.minY)
        XCTAssertFalse(el(app, "project-old-blog-6e7f").exists, "archived stays out of the list")
        sleep(1)
        shot("01-projects")
        el(app, "project-lumen-studio").tap()
        XCTAssertTrue(el(app, "projectPill").waitForExistence(timeout: 10))
        XCTAssertTrue(find(app, "NEEDS YOU").waitForExistence(timeout: 10))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(el(app, "project-lumen-studio").waitForExistence(timeout: 5))
        // the menu also reaches it
        el(app, "searchProjects").tap()
        let field = el(app, "projectSearch")
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.typeText("lu")
        XCTAssertTrue(el(app, "hit-lumen-studio").waitForExistence(timeout: 5))
        XCTAssertFalse(el(app, "project-home-server-5e6f").exists)
        el(app, "closeSearch").tap()
        XCTAssertTrue(el(app, "project-home-server-5e6f").waitForExistence(timeout: 5))
    }

    /// 02: the filter: Pinned, All, Archived and the folders switch
    func testP02Filter() {
        let app = projects(["-filter"])
        XCTAssertTrue(el(app, "filter-archived").waitForExistence(timeout: 5))
        sleep(1)
        shot("02-filter")
        el(app, "filter-archived").tap()
        XCTAssertTrue(el(app, "project-old-blog-6e7f").waitForExistence(timeout: 5))
        XCTAssertFalse(el(app, "project-lumen-studio").exists)
        el(app, "projectFilter").tap()
        XCTAssertTrue(el(app, "filter-all").waitForExistence(timeout: 5))
        el(app, "filter-all").tap()
        XCTAssertTrue(el(app, "project-lumen-studio").waitForExistence(timeout: 5))
        el(app, "projectFilter").tap()
        XCTAssertTrue(el(app, "filter-folders").waitForExistence(timeout: 5))
        el(app, "filter-folders").tap()
        if el(app, "closeFilter").exists { el(app, "closeFilter").tap() }
        XCTAssertTrue(el(app, "folder-At home").waitForExistence(timeout: 5))
        // put it back for the other tests (the switch is remembered)
        el(app, "projectFilter").tap()
        XCTAssertTrue(el(app, "filter-folders").waitForExistence(timeout: 5))
        el(app, "filter-folders").tap()
        if el(app, "closeFilter").exists { el(app, "closeFilter").tap() }
        XCTAssertTrue(el(app, "folder-At home").waitForNonExistence(timeout: 5))
    }

    /// 03: New project: name, goal, files, folder; Create adds it to the list
    func testP03NewProject() {
        let app = projects(["-newProject"])
        let name = el(app, "newName")
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        XCTAssertTrue(el(app, "newGoal").exists)
        XCTAssertTrue(el(app, "newFolder").exists)
        sleep(1)
        shot("03-new-project")
        name.typeText("Film shelf")
        el(app, "newCreate").tap()
        // a project without a main chat yet opens its settings
        XCTAssertTrue(el(app, "settingsClose").waitForExistence(timeout: 10))
        el(app, "settingsClose").tap()
        XCTAssertTrue(find(app, "Film shelf").waitForExistence(timeout: 5))
    }

    /// 04: the icon picker: colours, the grid, search through every Lucide icon
    func testP04ProjectIcon() {
        let app = launch(["-place", "projects", "-newProject", "-iconPicker"])
        XCTAssertTrue(el(app, "icon-clapperboard").waitForExistence(timeout: 20))
        sleep(1)
        shot("04-project-icon")
        let search = app.textFields.matching(NSPredicate(format: "placeholderValue CONTAINS[c] %@", "icon")).firstMatch
        XCTAssertTrue(search.exists)
        search.tap()
        search.typeText("film")
        XCTAssertTrue(el(app, "icon-film").waitForExistence(timeout: 5))
        XCTAssertFalse(el(app, "icon-rocket").exists)
        el(app, "icon-film").tap()
        el(app, "colour-blue").tap()
        el(app, "iconDone").tap()
        XCTAssertTrue(el(app, "newName").waitForExistence(timeout: 5))
    }

    func testComingSoonPlaces() {
        let app = launch(["-menu"])
        for p in ["scheduled", "quick", "transfer", "bot"] {
            if !el(app, "place-\(p)").exists { openMenu(app) }
            XCTAssertTrue(el(app, "place-\(p)").waitForExistence(timeout: 20))
            el(app, "place-\(p)").tap()
            XCTAssertTrue(el(app, "comingSoon").waitForExistence(timeout: 5), p)
            if p == "bot" { sleep(1); shot("coming-soon") }
            app.navigationBars.buttons.element(boundBy: 0).tap()
            XCTAssertTrue(el(app, "comingSoon").waitForNonExistence(timeout: 5))
        }
    }

    // MARK: slice 2: chats

    /// opens a chat from the menu (Pinned or Recents) by its title and waits for its turns
    private func open(_ app: App, _ title: String, waitFor text: String) {
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
    private func unfoldLast(_ app: App) {
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

    private func type(_ app: App, _ text: String) {
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
    private func onScreen(_ app: App, _ e: Element, _ what: String) {
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
        // up the chat: the twelve (in rows of four), the message that is only photos, then the three and the one
        let twelve = find(app, "Every room, so you can see")
        scrollUp(app, until: twelve)
        onScreen(app, twelve, "the 12-photo message's words")
        for i in 0..<pictures.count where pictures.element(boundBy: i).isHittable {
            onScreen(app, pictures.element(boundBy: i), "photo \(i + 1) near the twelve")
        }
        onScreen(app, send, "the send button with the 12 photos in view")
        sleep(1)
        shot("photos-12")
        let three = find(app, "And these three for the bedroom")
        scrollUp(app, until: three)
        onScreen(app, three, "the 3-photo message's words")
        let one = find(app, "Which of these colours would suit the hall")
        if one.exists { onScreen(app, one, "the 1-photo message's words") }
        XCTAssertTrue(app.descendants(matching: .any)["picture"].exists, "Claude's pictures show")
        sleep(1)
        shot("photos-1-3")
        // still typeable and sendable
        box(app).tap()
        box(app).typeText("Fog it is")
        onScreen(app, send, "the send button while typing")
        XCTAssertTrue(send.isHittable)
        sleep(1)
        shot("photos-typing")
        send.tap()
        XCTAssertTrue(find(app, "This is the demo").waitForExistence(timeout: 5))
    }

    /// drags the chat down in short steps until `e` sits in the lower part of the screen (its photos above it show)
    private func scrollUp(_ app: App, until e: Element) {
        let screen = app.windows.firstMatch.frame
        for _ in 0..<20 {
            if e.exists, e.frame.minY > screen.height * 0.5, e.frame.maxY < screen.height * 0.8 { return }
            let down = e.exists && e.frame.minY > screen.height * 0.8  // went past it: back a little
            let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.6, dy: down ? 0.6 : 0.35))
            let to = app.coordinate(withNormalizedOffset: CGVector(dx: 0.6, dy: down ? 0.45 : 0.6))
            // slow and held at the end: no fling, so each step moves the chat by about the drag
            from.press(forDuration: 0.05, thenDragTo: to, withVelocity: .slow, thenHoldForDuration: 0.2)
        }
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
            field.typeText(String(repeating: Key.delete, count: old.count))
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
    // MARK: slice 4: answer, pick, command

    private let gallery = "00000009-1111-4222-8333-000000000009"
    private func chat(_ n: Int) -> String { String(format: "%08d-1111-4222-8333-%012d", n, n) }

    /// straight into a demo chat (the slice 4 ones aren't in the list)
    private func openChat(_ id: String, waitFor text: String, _ extra: [String] = []) -> App {
        let app = launch(["-open", id] + extra)
        XCTAssertTrue(app.descendants(matching: .any)["chatTitle"].waitForExistence(timeout: 20))
        XCTAssertTrue(find(app, text).waitForExistence(timeout: 10), text)
        return app
    }

    private func el(_ app: App, _ id: String) -> Element {
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
    private func flip(_ e: Element) {
        let inner = e.switches.firstMatch
        if inner.exists && inner.frame.width < e.frame.width {
            inner.tap()
        } else {
            e.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        }
    }

    private func waitValue(_ e: Element, _ v: String) -> Bool {
        poll(5) { e.value as? String == v }
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
        search.typeText(String(repeating: Key.delete, count: 4))

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
        XCTAssertTrue(poll(5) { (field.value as? String ?? "").hasPrefix("The lightbox opens") })
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

    // MARK: slice 5: voice (the demo's PC hears "Also let a swipe down close the lightbox on phones.")

    private let said = "Also let a swipe down close the lightbox on phones"

    /// waits until the recorder has given the box back and the words are in it
    private func expectInBox(_ app: App) {
        XCTAssertTrue(app.buttons["attach"].waitForExistence(timeout: 10), "the box is back")
        let field = app.textFields["composer"], view = app.textViews["composer"]
        XCTAssertTrue(field.waitForExistence(timeout: 2) || view.exists)
        let box = field.exists ? field : view
        XCTAssertTrue(poll(10) { (box.value as? String ?? "").localizedCaseInsensitiveContains(said) }, "the words are in the box")
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

    // MARK: a121: a project (05-12)

    private let lumen = "00000066-1111-4222-8333-000000000066"
    private let contact = "00000074-2222-4222-8333-000000000074"

    /// the Lumen main chat pushed over Projects (05); `-sheet` brings its Overview up (06)
    private func project(_ extra: [String] = []) -> App {
        let app = launch(["-place", "projects", "-push", lumen] + extra)
        XCTAssertTrue(el(app, "projectPill").waitForExistence(timeout: 20))
        return app
    }

    private func overview(_ extra: [String] = []) -> App {
        let app = project(["-sheet"] + extra)
        XCTAssertTrue(el(app, "overviewGlance").waitForExistence(timeout: 10))
        return app
    }

    /// Library, Ideas or Scheduled at the foot of the Overview: scrolled to, then tapped
    private func place(_ app: App, _ id: String) {
        let row = el(app, "overview-\(id)")
        var n = 0
        while !(row.exists && row.isHittable) && n < 5 {
            app.collectionViews.firstMatch.swipeUp()
            n += 1
        }
        row.tap()
    }

    /// 05: the main chat with live thread cards and its own question
    func testP05Project() {
        let app = project()
        XCTAssertTrue(find(app, "NEEDS YOU").waitForExistence(timeout: 10))
        XCTAssertTrue(el(app, "threadCard-a4").exists)
        XCTAssertTrue(find(app, "a4 \u{00B7} working").exists)
        XCTAssertTrue(find(app, "a3 \u{00B7} landed").exists)
        XCTAssertTrue(el(app, "overviewButton").exists)
        XCTAssertEqual(el(app, "composer").placeholderValue, "Message the main chat")
        sleep(1)
        shot("05-project")
        let first = app.buttons["askOption-0"]
        XCTAssertGreaterThanOrEqual(first.frame.height, 44)
        first.tap()
        XCTAssertTrue(find(app, "ANSWERED").waitForExistence(timeout: 5))
        XCTAssertTrue(find(app, "Looks good").exists)
    }

    /// 05 → 07: a thread card opens the thread; Back returns to the main chat
    func testP05ThreadCardOpensThread() {
        let app = project()
        let card = el(app, "threadCard-a4")
        XCTAssertTrue(card.waitForExistence(timeout: 10))
        card.tap()
        XCTAssertTrue(el(app, "taskCard").waitForExistence(timeout: 10))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(el(app, "projectPill").waitForExistence(timeout: 5))
    }

    /// 06: the Overview: glance, Needs you, Working, Done, Library / Ideas / Scheduled
    func testP06Overview() {
        let app = overview()
        XCTAssertTrue(el(app, "needsMain").exists)
        XCTAssertTrue(el(app, "thread-a6").exists)
        XCTAssertTrue(el(app, "thread-a4").exists)
        XCTAssertTrue(el(app, "overviewGlance").exists)
        sleep(1)
        shot("06-overview")
        el(app, "thread-a4").tap()
        // the Overview goes and the thread's chat is pushed over the main chat
        XCTAssertTrue(el(app, "taskCard").waitForExistence(timeout: 10))
        XCTAssertFalse(el(app, "overviewGlance").exists)
    }

    func testP06NewThread() {
        let app = overview()
        app.buttons["newThread"].tap()
        let box = app.textViews["newThreadText"]
        XCTAssertTrue(box.waitForExistence(timeout: 5))
        box.typeText("Add the studio hours to the footer")
        sleep(1)
        shot("06-new-thread")
        app.buttons["startThread"].tap()
        XCTAssertTrue(find(app, "Add the studio hours to the footer").waitForExistence(timeout: 5))
    }

    /// 07: a thread: its task, its work, what you told it, live
    func testP07Thread() {
        let app = launch(["-place", "projects", "-push", contact])
        XCTAssertTrue(el(app, "threadPill").waitForExistence(timeout: 20))
        XCTAssertTrue(el(app, "taskCard").waitForExistence(timeout: 10))
        XCTAssertTrue(find(app, "Keep the send button").exists)
        XCTAssertTrue(el(app, "liveLine").exists)
        XCTAssertEqual(el(app, "composer").placeholderValue, "Message this thread")
        XCTAssertFalse(find(app, "Acceptance criteria").exists, "the brief hides behind the task card")
        sleep(1)
        shot("07-thread")
        el(app, "taskCard").tap()
        XCTAssertTrue(el(app, "taskClose").waitForExistence(timeout: 5))
        XCTAssertTrue(find(app, "Every field has a label").exists)
        el(app, "taskClose").tap()
        app.buttons["more"].tap()
        XCTAssertTrue(app.buttons["Pause"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Stop\u{2026}"].exists)
    }

    /// 08: Library: pinned, notes, from threads; filter, folders, notes open to read and edit
    func testP08Library() {
        let app = overview()
        place(app, "library")
        XCTAssertTrue(el(app, "lib-Ideas").waitForExistence(timeout: 5))
        XCTAssertTrue(find(app, "From threads").exists)
        XCTAssertTrue(el(app, "lib-gallery-tour.mp4").exists)
        sleep(2)
        shot("08-library")
        el(app, "libraryKind-images").tap()
        XCTAssertTrue(el(app, "lib-contact-form.png").waitForExistence(timeout: 5))
        XCTAssertFalse(el(app, "lib-Palette").exists)
        el(app, "libraryKind-all").tap()
        XCTAssertTrue(el(app, "lib-Palette").waitForExistence(timeout: 5))
        el(app, "lib-Palette").tap()
        XCTAssertTrue(el(app, "noteText").waitForExistence(timeout: 5))
        app.buttons["noteEdit"].tap()
        let editor = app.textViews["noteEditor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        editor.typeText("\n- Sand for the footer")
        app.buttons["noteSave"].tap()
        XCTAssertTrue(el(app, "noteSaved").waitForExistence(timeout: 5))
        XCTAssertTrue(find(app, "Sand for the footer").exists)
    }

    func testP08FolderAndPicture() {
        let app = overview()
        place(app, "library")
        XCTAssertTrue(el(app, "lib-Memory").waitForExistence(timeout: 5))
        el(app, "lib-Memory").tap()
        XCTAssertTrue(el(app, "lib-MEMORY").waitForExistence(timeout: 5))
        let app2 = overview()
        place(app2, "library")
        XCTAssertTrue(el(app2, "lib-contact-form.png").waitForExistence(timeout: 5))
        el(app2, "lib-contact-form.png").tap()
        XCTAssertTrue(el(app2, "libraryPicture").waitForExistence(timeout: 5))
    }

    func testP08NoteConflict() {
        let app = overview(["-noteConflict"])
        place(app, "library")
        XCTAssertTrue(el(app, "lib-Palette").waitForExistence(timeout: 5))
        el(app, "lib-Palette").tap()
        app.buttons["noteEdit"].tap()
        let editor = app.textViews["noteEditor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        editor.typeText("\n- A night mode")
        app.buttons["noteSave"].tap()
        XCTAssertTrue(app.alerts["This note changed on the PC"].waitForExistence(timeout: 5))
        app.alerts.buttons["Keep mine"].tap()
        XCTAssertTrue(el(app, "noteSaved").waitForExistence(timeout: 5))
    }

    /// 09: Ideas: sections, AI badges, add at the bottom
    func testP09Ideas() {
        let app = overview()
        place(app, "ideas")
        XCTAssertTrue(el(app, "ideasTitle").waitForExistence(timeout: 5))
        XCTAssertTrue(find(app, "Booking straight from the gallery").exists)
        XCTAssertTrue(find(app, "AI suggestions").exists)
        sleep(1)
        shot("09-ideas")
        let field = el(app, "ideaText")
        field.tap()
        field.typeText("Gift cards for portrait sessions")
        el(app, "ideaAdd").tap()
        XCTAssertTrue(el(app, "idea-Gift cards for portrait sessions").waitForExistence(timeout: 5))
    }

    /// 10: Scheduled: next runs, a skipped one, one running now, paused, past runs
    func testP10Scheduled() {
        let app = overview()
        place(app, "scheduled")
        XCTAssertTrue(el(app, "schedule-s1").waitForExistence(timeout: 5))
        XCTAssertTrue(find(app, "Skipped, PC was off").exists)
        XCTAssertTrue(find(app, "Running as b5").exists)
        XCTAssertTrue(find(app, "Past runs").exists)
        sleep(1)
        shot("10-scheduled")
        el(app, "schedule-s1").tap()
        XCTAssertTrue(el(app, "scheduleRun").waitForExistence(timeout: 5))
        XCTAssertTrue(el(app, "schedulePause").exists)
    }

    /// 11: the project pill opens its settings
    func testP11Settings() {
        let app = project()
        el(app, "projectPill").tap()
        XCTAssertTrue(el(app, "settingsName").waitForExistence(timeout: 10))
        XCTAssertTrue(el(app, "settingsUsage").exists)
        sleep(1)
        shot("11-settings")
    }

    /// 12: the project's usage, from its settings
    func testP12Usage() {
        let app = project()
        el(app, "projectPill").tap()
        XCTAssertTrue(el(app, "settingsUsage").waitForExistence(timeout: 10))
        el(app, "settingsUsage").tap()
        XCTAssertTrue(el(app, "usageTotal").waitForExistence(timeout: 10))
        XCTAssertTrue(el(app, "biggest-a6").exists)
        sleep(1)
        shot("12-usage")
    }
}
