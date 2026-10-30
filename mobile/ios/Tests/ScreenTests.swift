import XCTest
import UIKit
@testable import GupWorks3

/// The app's screens in demo mode (bundled invented fixtures, no PC needed), driven inside the unit-test process
/// (ScreenDriver.swift): what each screen shows, what a tap or a press does, and the docs/mobile-shots pictures. Each
/// picture is attached to the test result and, when the runner sets SHOTS_DIR (TEST_RUNNER_SHOTS_DIR for xcodebuild),
/// also written there as a PNG. These were XCUITests (about 20 s each); here a test takes a few seconds. Gestures
/// that need the system's own touches stay in UITests/.
@MainActor
final class ScreenTests: XCTestCase {
    private nonisolated(unsafe) var started = Date()

    override nonisolated func setUp() {
        started = Date()
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
            Timing.report(name, Date().timeIntervalSince(started))
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

    /// a155: a GPT chat's card shows the ChatGPT plan's limits (the weekly one; ChatGPT reports no 5-hour one)
    func test5gUsageOnAGPTChat() {
        let app = openChat(chat(8), waitFor: "The backup didn")
        app.buttons["usage"].tap()
        XCTAssertTrue(el(app, "usageCard").waitForExistence(timeout: 5))
        XCTAssertTrue(el(app, "usage-ctx").label.contains("18K"), el(app, "usage-ctx").label)
        XCTAssertTrue(el(app, "usage-wk").label.contains("ChatGPT weekly limit"), el(app, "usage-wk").label)
        XCTAssertTrue(el(app, "usage-wk").label.contains("3%"), el(app, "usage-wk").label)
        XCTAssertTrue(el(app, "usage-5h").label.contains("Not reported by ChatGPT"), el(app, "usage-5h").label)
        sleep(1)
        shot("a155-gpt-usage")
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
        spin(1.5)  // the Overview used to slide in after the push settled
        XCTAssertFalse(el(app, "overviewGlance").exists, "the Projects page opens the main chat, not the Overview")
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

    /// the filter button, until its menu shows `item`. Right after the menu closed, its fading backdrop can still
    /// take the touch for a moment (it only closes the menu again), so a second tap follows when the first did nothing.
    private func openFilter(_ app: App, showing item: String) {
        for _ in 0..<2 where !el(app, item).exists {
            el(app, "projectFilter").tap()
            if el(app, item).waitForExistence(timeout: 1.5) { return }
        }
        XCTAssertTrue(el(app, item).waitForExistence(timeout: 3), item)
    }

    /// 02: the filter: Pinned, All, Archived and the folders switch
    func testP02Filter() {
        let app = projects(["-filter"])
        XCTAssertTrue(el(app, "filter-archived").waitForExistence(timeout: 5))
        sleep(1)
        shot("02-filter")
        el(app, "filter-archived").tap()
        XCTAssertTrue(el(app, "project-old-blog-6e7f").waitForExistence(timeout: 5))
        // the list fades the others out
        XCTAssertTrue(el(app, "project-lumen-studio").waitForNonExistence(timeout: 5))
        openFilter(app, showing: "filter-all")
        el(app, "filter-all").tap()
        XCTAssertTrue(el(app, "project-lumen-studio").waitForExistence(timeout: 5))
        openFilter(app, showing: "filter-folders")
        el(app, "filter-folders").tap()
        if el(app, "closeFilter").exists { el(app, "closeFilter").tap() }
        XCTAssertTrue(el(app, "folder-At home").waitForExistence(timeout: 5))
        // put it back for the other tests (the switch is remembered)
        openFilter(app, showing: "filter-folders")
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
        for p in ["scheduled", "bot"] {
            if !el(app, "place-\(p)").exists { openMenu(app) }
            XCTAssertTrue(el(app, "place-\(p)").waitForExistence(timeout: 20))
            el(app, "place-\(p)").tap()
            XCTAssertTrue(el(app, "comingSoon").waitForExistence(timeout: 5), p)
            if p == "bot" { sleep(1); shot("coming-soon") }
            app.navigationBars.buttons.element(boundBy: 0).tap()
            XCTAssertTrue(el(app, "comingSoon").waitForNonExistence(timeout: 5))
        }
    }

    /// a142: Quick actions from the menu: Away mode and Dillon's game bot as the PC reads them, Restart PC asks first
    private func quickPage(_ flags: [String] = []) -> App {
        let app = launch(["-menu"] + flags)
        if !el(app, "place-quick").exists { openMenu(app) }
        XCTAssertTrue(el(app, "place-quick").waitForExistence(timeout: 20))
        el(app, "place-quick").tap()
        XCTAssertTrue(app.switches["quick-away"].waitForExistence(timeout: 10), app.debugDescription)
        return app
    }

    func testQuickActions() {
        let app = quickPage()
        XCTAssertFalse(el(app, "comingSoon").exists)
        XCTAssertTrue(find(app, "Away mode").exists)
        XCTAssertTrue(find(app, "Dillon's game bot").exists)
        XCTAssertTrue(find(app, "Restart PC").exists)
        let away = app.switches["quick-away"], bot = app.switches["quick-game-bot"]
        XCTAssertEqual(away.value as? String, "0")
        XCTAssertEqual(bot.value as? String, "1")
        sleep(1)
        shot("quick-actions")

        flip(away)
        XCTAssertTrue(waitValue(away, "1"))
        XCTAssertTrue(app.buttons["quickRestart"].isEnabled)
        app.buttons["quickRestart"].tap()
        XCTAssertTrue(app.alerts["Restart the PC now?"].waitForExistence(timeout: 5))
        sleep(1)
        shot("quick-restart-confirm")
        app.alerts.buttons["Cancel"].tap()
        XCTAssertTrue(app.alerts["Restart the PC now?"].waitForNonExistence(timeout: 5))
        XCTAssertFalse(find(app, "Restarting").exists, "Cancel restarts nothing")
        app.buttons["quickRestart"].tap()
        XCTAssertTrue(app.alerts["Restart the PC now?"].waitForExistence(timeout: 5))
        app.alerts.buttons["Restart"].tap()
        XCTAssertTrue(find(app, "Restarting").waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["quickRestart"].isEnabled)
    }

    /// the PC's errors and warnings under their switch; Restart PC off with logind's reason
    func testQuickActionsErrors() {
        let app = quickPage(["-quickError"])
        XCTAssertTrue(el(app, "quick-away-warning").waitForExistence(timeout: 5))
        XCTAssertTrue(find(app, "gupworks-away.service isn't running").exists)
        XCTAssertTrue(find(app, "tmux: no server running").exists)
        XCTAssertTrue(find(app, "logind CanReboot").exists)
        XCTAssertFalse(app.buttons["quickRestart"].isEnabled)
        let away = app.switches["quick-away"]
        flip(away)
        XCTAssertTrue(el(app, "quick-away-error").waitForExistence(timeout: 5))
        XCTAssertTrue(waitValue(away, "0"), "the switch stays where the PC is")
        sleep(1)
        shot("quick-actions-errors")
    }

    // MARK: a151: the PC part of Quick actions

    /// drags the page in short steps until `e` shows whole between the top bar and the bottom
    private func reveal(_ app: App, _ e: Element) {
        let screen = app.windows.firstMatch.frame
        for _ in 0..<20 {
            if e.exists, e.frame.minY > screen.height * 0.12, e.frame.maxY < screen.height * 0.9 { return }
            let above = e.exists && e.frame.minY <= screen.height * 0.12  // went past it: back a little
            let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: above ? 0.4 : 0.65))
            let to = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: above ? 0.6 : 0.4))
            from.press(forDuration: 0.05, thenDragTo: to, withVelocity: Velocity(rawValue: 1500), thenHoldForDuration: 0.2)
        }
    }

    /// puts the keyboard away (it covers the Open button at the end of the page) and taps Open
    private func tapOpen(_ app: App) {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5), "the keyboard went away")
        reveal(app, el(app, "quick-open-button"))
        XCTAssertTrue(el(app, "quick-open-button").isHittable, app.debugDescription)
        el(app, "quick-open-button").tap()
    }

    /// the health line on top (a tap shows the details), then media, volume, Open on the PC and the Discord call
    func testQuickPc() {
        let app = quickPage()
        XCTAssertTrue(find(app, "Services all up").waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(find(app, "CPU 61°C").exists)
        el(app, "quick-health").tap()
        XCTAssertTrue(find(app, "Coolant").waitForExistence(timeout: 5), "a tap shows the details")
        XCTAssertTrue(find(app, "Model routing").exists)
        sleep(1)
        shot("quick-pc-health")
        el(app, "quick-health").tap()
        XCTAssertTrue(find(app, "Coolant").waitForNonExistence(timeout: 5), "and hides them")

        let media = el(app, "quick-media")
        reveal(app, media)
        XCTAssertTrue(find(app, "Northern Lights — Aurora Hall").exists, app.debugDescription)
        el(app, "quick-media-play-pause").tap()
        XCTAssertTrue(find(app, "Spotify · Paused").waitForExistence(timeout: 5), "play/pause, read back")
        el(app, "quick-media-play-pause").tap()
        XCTAssertTrue(find(app, "Spotify · Playing").waitForExistence(timeout: 5))
        reveal(app, el(app, "quick-volume"))
        el(app, "quick-volume-mute").tap()
        XCTAssertTrue(find(app, "Desk Speakers · Muted").waitForExistence(timeout: 5), "mute")
        el(app, "quick-volume-mute").tap()
        XCTAssertTrue(find(app, "Desk Speakers · 42%").waitForExistence(timeout: 5))
        reveal(app, el(app, "quick-discord"))
        XCTAssertTrue(find(app, "In a voice call").exists)
        let picker = el(app, "quick-open-browser")
        XCTAssertTrue((picker.value as? String)?.contains("Chrome · Your Chrome") == true || find(app, "Chrome · Your Chrome").exists,
                      "the PC's last pick: \(String(describing: picker.value)) \(app.debugDescription)")
        sleep(1)
        shot("quick-pc")

        let field = app.textFields["quick-open-url"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("https://example.com/a")
        tapOpen(app)
        XCTAssertTrue(find(app, "Opened in Chrome · Your Chrome").waitForExistence(timeout: 5), app.debugDescription)
        field.tap()
        field.typeText("file:///etc/passwd")
        tapOpen(app)
        XCTAssertTrue(el(app, "quick-open-error").waitForExistence(timeout: 5))
        XCTAssertTrue(find(app, "Only http:// and https:// links open on the PC.").exists)
        XCTAssertFalse(find(app, "Opened in").exists, "a refused link opened nothing")
        reveal(app, el(app, "quick-discord"))
        sleep(1)
        shot("quick-pc-open")
    }

    /// every PC row with its own error: a temperature that didn't read, PipeWire down, a browser that didn't open
    func testQuickPcErrors() {
        let app = quickPage(["-quickError"])
        XCTAssertTrue(el(app, "quick-health").waitForExistence(timeout: 5))
        XCTAssertTrue(find(app, "nvidia-smi: couldn't talk to the driver").waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(find(app, "Projects down").exists)
        reveal(app, el(app, "quick-discord"))
        XCTAssertTrue(find(app, "Nothing is playing on the PC").exists)
        XCTAssertFalse(el(app, "quick-media-play-pause").isEnabled)
        XCTAssertTrue(find(app, "Could not connect to PipeWire").exists)
        XCTAssertTrue(find(app, "pw-dump: can't connect to PipeWire").exists)
        let field = app.textFields["quick-open-url"]
        field.tap()
        field.typeText("https://example.com")
        tapOpen(app)
        XCTAssertTrue(find(app, "google-chrome-stable: not responding (demo)").waitForExistence(timeout: 5))
        reveal(app, el(app, "quick-discord"))
        sleep(1)
        shot("quick-pc-errors")
    }

    // MARK: a144: File transfer

    /// the chat with the PC: the phone's own on the right, the PC's on the left, pictures, a video and files
    func testTransferChat() {
        let app = launch(["-place", "transfer"])
        XCTAssertTrue(find(app, "perfect, ordering it now").waitForExistence(timeout: 20))
        XCTAssertTrue(el(app, "tab-chat").exists && el(app, "tab-library").exists)
        XCTAssertFalse(el(app, "gauge").exists, "no model here")
        let screen = app.windows.firstMatch.frame
        let mine = find(app, "perfect, ordering it now"), pc = find(app, "got it, thanks")
        XCTAssertGreaterThan(mine.frame.midX, screen.midX, "the phone's own on the right")
        XCTAssertTrue(pc.exists)
        XCTAssertLessThan(pc.frame.midX, screen.midX, "the PC's on the left")
        XCTAssertTrue(el(app, "transferFile").exists)
        sleep(2)
        shot("transfer-chat")
        // the menu button opens the menu; File transfer is a place in it
        openMenu(app)
        XCTAssertTrue(el(app, "place-transfer").exists)
    }

    /// a note typed here goes up and shows on the right
    func testTransferSendText() {
        let app = launch(["-place", "transfer"])
        XCTAssertTrue(find(app, "perfect, ordering it now").waitForExistence(timeout: 20))
        type(app, "leaving at six")
        app.buttons["send"].tap()
        // first the outbox's bubble, then (the demo PC took it) the message itself
        let sent = app.descendants(matching: .any).matching(identifier: "transferMine")
            .matching(NSPredicate(format: "label CONTAINS[c] %@", "leaving at six")).firstMatch
        XCTAssertTrue(sent.waitForExistence(timeout: 10))
        XCTAssertGreaterThan(sent.frame.midX, app.windows.firstMatch.frame.midX)
    }

    /// a big video on its way: its bar and how much is up
    func testTransferUploading() {
        let app = launch(["-place", "transfer", "-transferUploading"])
        XCTAssertTrue(el(app, "transferProgress").waitForExistence(timeout: 20))
        XCTAssertTrue(find(app, "of 94 MB").exists)
        sleep(2)
        shot("transfer-uploading")
    }

    /// stopped on the way: why, Retry and Discard
    func testTransferFailed() {
        let app = launch(["-place", "transfer", "-transferFailed"])
        XCTAssertTrue(el(app, "transferRetry").waitForExistence(timeout: 20))
        XCTAssertTrue(el(app, "transferDiscard").exists)
        XCTAssertTrue(find(app, "Not sent").exists)
        el(app, "transferDiscard").tap()
        XCTAssertTrue(el(app, "transferRetry").waitForNonExistence(timeout: 5))
    }

    /// the Library: photos and videos as a grid, other files as a list, newest first
    func testTransferLibrary() {
        let app = launch(["-place", "transfer"])
        XCTAssertTrue(el(app, "tab-library").waitForExistence(timeout: 20))
        el(app, "tab-library").tap()
        XCTAssertTrue(el(app, "transferLibPicture").waitForExistence(timeout: 10))
        XCTAssertTrue(el(app, "transferLibVideo").exists)
        XCTAssertTrue(find(app, "Shelf cut list.pdf").exists)
        XCTAssertTrue(find(app, "backyard-notes.txt").exists)
        // newest first: the notes (sent last) above the cut list
        XCTAssertLessThan(find(app, "backyard-notes.txt").frame.minY, find(app, "Shelf cut list.pdf").frame.minY)
        sleep(2)
        shot("transfer-library")
        el(app, "tab-chat").tap()
        XCTAssertTrue(find(app, "perfect, ordering it now").waitForExistence(timeout: 10))
    }

    /// a149: a project pinned in the menu opens its main chat, with the Overview closed (it opens only by a swipe
    /// left or its button)
    func testProjectFromMenuOpensChat() {
        let app = launch(["-menu"])
        let pin = el(app, "pin-Lumen Studio website")
        XCTAssertTrue(pin.waitForExistence(timeout: 10))
        pin.tap()
        XCTAssertTrue(el(app, "projectPill").waitForExistence(timeout: 20), "the project's main chat")
        XCTAssertTrue(el(app, "overviewButton").waitForExistence(timeout: 5))
        spin(1.5)  // the Overview used to slide in after the push settled
        XCTAssertFalse(el(app, "overviewGlance").exists, "the Overview stays closed")
        XCTAssertFalse(el(app, "overviewClose").exists, "no Overview page in the tree")
        shot("a149-project-main-chat")
        // and its button still opens it
        el(app, "overviewButton").tap()
        XCTAssertTrue(el(app, "overviewGlance").waitForExistence(timeout: 5), "the button opens the Overview")
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
            // held at the end: no fling, so each step moves the chat by about the drag
            from.press(forDuration: 0.05, thenDragTo: to, withVelocity: Velocity(rawValue: 1500), thenHoldForDuration: 0.2)
        }
    }

    /// a122's photo zoom with real fingers (Hammer): double-tap zooms in and back, a two-finger pinch zooms, swipe
    /// down closes. These steps were in PhotoViewerUITests, where XCUITest's synthesized pinch now and then left
    /// CI's simulator not delivering the next gestures (a131); the paging swipes stay there.
    func testPhotoZoom() {
        let six = "Here are six photos of the living room"
        let app = openChat(chat(16), waitFor: six)
        let pictures = app.buttons.matching(identifier: "yourPicture")
        XCTAssertGreaterThanOrEqual(pictures.count, 6)
        pictures.element(boundBy: pictures.count - 5).tap()
        let viewer = el(app, "photoViewer")
        XCTAssertTrue(viewer.waitForExistence(timeout: 5), "the viewer opens")
        XCTAssertTrue(poll(5) { el(app, "photoCounter").label == "26 of 30" }, el(app, "photoCounter").label)
        let page = el(app, "photoPage")
        func zoom(_ value: String) -> Bool { poll(5) { (page.value as? String) == value } }
        XCTAssertTrue(zoom("fit"), page.label)

        page.doubleTap()
        XCTAssertTrue(zoom("zoomed"), "double-tap zooms in; \(page.label)")
        idle(1)
        shot("a122-photo-zoomed")
        page.doubleTap()
        XCTAssertTrue(zoom("fit"), "double-tap again: back to fit; \(page.label)")
        let f = page.frame
        Finger.zoom(at: CGPoint(x: f.midX, y: f.midY), distance: 200)
        XCTAssertTrue(zoom("zoomed"), "a pinch zooms; \(page.label)")
        page.doubleTap()
        XCTAssertTrue(zoom("fit"), page.label)

        page.swipeDown()
        XCTAssertTrue(viewer.waitForNonExistence(timeout: 5), "swipe down closes; \(page.label)")
        XCTAssertTrue(find(app, six).exists, "back in the chat")
    }

    // MARK: a157: audio plays in the chat

    /// the waveform cards top to bottom: your voice memo, then Claude's two synth lines
    private func audioWaves(_ app: App) -> [Element] {
        let q = app.descendants(matching: .any).matching(identifier: "audio-wave")
        return (0..<q.count).map { q.element(boundBy: $0) }.sorted { $0.frame.minY < $1.frame.minY }
    }

    /// Claude's audio sits in its reply as waveform cards as wide as the column (a path with spaces too); the voice
    /// memo you sent sits on the right, above your words. A tap on the waveform before playing moves the place; play
    /// plays from there and the time moves; one sound at a time.
    func testA157AudioInAChat() {
        let app = openChat(AudioDemo.chat, waitFor: "Turn this hum into a synth line")
        let plays = app.buttons.matching(identifier: "audio-play")
        XCTAssertTrue(poll(10) { plays.count >= 3 }, "your memo and Claude's two sounds: \(plays.count)")
        let mine = app.buttons["Play hum-idea.m4a"], synth = app.buttons["Play Synth line"]
        XCTAssertTrue(mine.exists, "your memo has a player")
        XCTAssertTrue(synth.exists, "Claude's sound has a player")
        XCTAssertTrue(app.buttons["Play Synth line, slow"].exists, "the path with spaces plays too")
        XCTAssertFalse(find(app, "synth line slow.m4a>").exists, "no raw link")
        let words = find(app, "Turn this hum into a synth line")
        let waves = audioWaves(app)
        XCTAssertEqual(waves.count, 3)
        let width = app.windows.firstMatch.frame.width
        XCTAssertLessThan(waves[0].frame.maxY, words.frame.minY, "your memo above your words")
        XCTAssertGreaterThan(waves[0].frame.minX, width * 0.2, "yours sits on the right")
        XCTAssertGreaterThan(waves[1].frame.width, waves[0].frame.width, "Claude's as wide as the column")
        for w in waves { onScreen(app, w, "a waveform") }
        XCTAssertEqual(el(app, "audio-speed").value as? String, "1×")
        idle(1)
        shot("a157-audio")

        // a tap halfway along the synth line's waveform, before it plays: it starts from there
        let line = MediaLink.url("demo:media/synth-line.m4a", base: nil)
        waves[1].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(poll(3) { abs(AudioPlayback.shared.place(of: line) - 4) < 0.6 },
                      "moved to the middle: \(AudioPlayback.shared.place(of: line))")
        synth.tap()
        let pause = app.buttons["Pause Synth line"]
        XCTAssertTrue(pause.waitForExistence(timeout: 8), "it plays")
        XCTAssertTrue(poll(6) { AudioPlayback.shared.place(of: line) > 4.6 }, "from the middle on")
        idle(1)
        shot("a157-audio-playing")

        // your memo starts: the synth line pauses and keeps its place
        mine.tap()
        XCTAssertTrue(app.buttons["Pause hum-idea.m4a"].waitForExistence(timeout: 8), "your memo plays")
        XCTAssertTrue(app.buttons["Play Synth line"].waitForExistence(timeout: 3), "the other one stopped")
        XCTAssertGreaterThan(AudioPlayback.shared.place(of: line), 4.5, "and kept its place")
        app.buttons["Pause hum-idea.m4a"].tap()
        XCTAssertTrue(app.buttons["Play hum-idea.m4a"].waitForExistence(timeout: 5), "paused")
    }

    // MARK: a133: a mockup set, and pictures in the order the text has them

    private let mockups = "00000018-1111-4222-8333-000000000018"

    /// drags the chat in short steps until `e` sits between `top` and `bottom` of the screen (or, taller than that,
    /// starts in the upper part); an element not built yet is taken to be further up
    private func bring(_ app: App, _ e: Element, top: CGFloat = 0.12, bottom: CGFloat = 0.88) {
        let h = app.windows.firstMatch.frame.height
        for _ in 0..<40 {
            let f: CGRect? = e.exists ? e.frame : nil
            if let f, f.minY >= h * top, f.maxY <= h * bottom || f.minY <= h * 0.4 { return }
            let up = f.map { $0.minY > h * 0.4 } ?? false     // below: move the chat up
            let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: up ? 0.6 : 0.35))
            let to = app.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: up ? 0.4 : 0.55))
            from.press(forDuration: 0.05, thenDragTo: to, withVelocity: Velocity(rawValue: 1500), thenHoldForDuration: 0.2)
        }
        XCTFail("couldn't bring \(e.identifier.isEmpty ? e.label : e.identifier) into view")
    }

    /// a ```mockups block is one set card: its name, what's the same, each option numbered with its name, how it
    /// differs and its screens (1a, 1b ...) to swipe through, then "How they differ" as a list; a tap on a screen
    /// opens the viewer on the set's pictures in set order, each titled in words
    func testA133MockupSet() {
        let app = openChat(mockups, waitFor: "Here are the three Overview screens again")
        let set = el(app, "mockupSet")
        bring(app, el(app, "mockupTitle"))
        XCTAssertTrue(set.exists, "the set shows as a card")
        XCTAssertTrue(el(app, "mockupTitle").label.contains("Phone project Overview · round 1"), el(app, "mockupTitle").label)
        XCTAssertTrue(find(app, "Same in all: slides in from the right").exists, "what's the same in all")
        XCTAssertFalse(find(app, "Mockup set: Phone project Overview").exists, "the older apps' copy isn't drawn")
        XCTAssertFalse(find(app, "```mockups").exists, "no raw block")
        let one = el(app, "mockupOption-1")
        XCTAssertTrue(one.exists)
        XCTAssertTrue(find(app, "the desktop's right bar group by group").exists, "option 1's difference")
        // in words first (bare codes like "1b" were confusing); the code stays as a small tag
        XCTAssertTrue(el(app, "mockupOptionTitle-1").label.contains("Option 1 · Sections"), el(app, "mockupOptionTitle-1").label)
        XCTAssertEqual(el(app, "mockupShot-1b").label, "Option 1 · Sections — Overview")
        XCTAssertTrue(el(app, "mockupShot-1a").exists && el(app, "mockupShot-1b").exists, "1a and 1b side by side")
        onScreen(app, el(app, "mockupShot-1a"), "1a")
        XCTAssertLessThan(el(app, "mockupShot-1a").frame.maxX, el(app, "mockupShot-1b").frame.minX, "1a before 1b")
        idle(1)
        shot("a133-set")
        // sideways through option 1's screens
        let row = el(app, "mockupScreens-1")
        let x0 = el(app, "mockupShot-1a").frame.minX
        for _ in 0..<2 {
            row.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.5))
                .press(forDuration: 0.05, thenDragTo: row.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.5)))
        }
        let third = el(app, "mockupShot-1c")
        settle { third.exists ? third.frame : nil }
        XCTAssertTrue(el(app, "mockupShot-1c").exists, "swiped on to 1c")
        XCTAssertLessThan(el(app, "mockupShot-1c").frame.minX, x0 + 300, "1c came into view")
        idle(1)
        shot("a133-set-swiped")
        // option 2, then its 2b full screen
        bring(app, el(app, "mockupShot-2b"), top: 0.15, bottom: 0.95)
        XCTAssertTrue(find(app, "roomy; questions as swipeable cards").exists, "option 2's difference")
        idle(1)
        shot("a133-set-option-2")
        el(app, "mockupShot-2b").tap()
        XCTAssertTrue(el(app, "photoViewer").waitForExistence(timeout: 5), "the viewer opens")
        XCTAssertTrue(poll(5) { el(app, "photoTitle").label == "Option 2 · Cards — Overview" }, el(app, "photoTitle").label)
        XCTAssertEqual(el(app, "photoCounter").label, "8 of 20", "the set's 20 screens, 2b the 8th")
        idle(1)
        shot("a133-set-viewer")
        let viewer = el(app, "photoViewer")
        viewer.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.5))
            .press(forDuration: 0.05, thenDragTo: viewer.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.5)))
        XCTAssertTrue(poll(5) { el(app, "photoTitle").label == "Option 2 · Cards — Scrolled" }, el(app, "photoTitle").label)
        XCTAssertEqual(el(app, "photoCounter").label, "9 of 20")
        el(app, "photoClose").tap()
        XCTAssertTrue(el(app, "photoViewer").waitForNonExistence(timeout: 5))
        // the table as a list
        bring(app, el(app, "mockupDifferences"), top: 0.1, bottom: 0.95)
        XCTAssertTrue(find(app, "HOW THEY DIFFER").exists)
        XCTAssertTrue(find(app, "Cards you answer in place").exists, "a table cell as a line")
        XCTAssertFalse(find(app, "|---|").exists, "no raw table")
        idle(1)
        shot("a133-set-differences")
    }

    // a163: generated and edited images inline, followed by two variations in a set.
    func testA163GeneratedImageSet() {
        let app = openChat("00000020-1111-4222-8333-000000000020", waitFor: "Garden variations")
        let generated = find(app, "Picture Generated robot")
        bring(app, generated)
        XCTAssertTrue(generated.exists, "generated image is inline")
        idle(1)
        shot("a163-generated")

        let edited = find(app, "Picture Edited robot")
        bring(app, edited)
        XCTAssertTrue(edited.exists, "edited image is inline")
        idle(1)
        shot("a163-edited")

        bring(app, el(app, "mockupTitle"))
        XCTAssertTrue(el(app, "mockupSet").exists)
        XCTAssertTrue(el(app, "mockupTitle").label.contains("Garden variations"))
        XCTAssertTrue(el(app, "mockupShot-1").exists, "first variation")
        idle(1)
        shot("a163-variations")
        bring(app, el(app, "mockupShot-2"))
        XCTAssertTrue(el(app, "mockupShot-2").exists, "second variation")
        idle(1)
        shot("a163-variations-two")
        el(app, "mockupShot-2").tap()
        XCTAssertTrue(el(app, "photoViewer").waitForExistence(timeout: 5))
        XCTAssertEqual(el(app, "photoCounter").label, "2 of 2", "both variations belong to one set")
    }

    /// a129's reply with four captioned pictures (1b, 2b, 3b, then 3a): each picture right under its own words,
    /// in the text's order, none grouped into a grid
    func testA133PicturesInTheTextsOrder() {
        let app = openChat(mockups, waitFor: "Here are the three Overview screens again")
        let words = ["closest to the desktop's right bar", "the roomiest", "dense and flat, with filter chips",
                     "how it slides in from the right", "My pick is 3, because"]
        let pictures = ["Picture 1 Sections", "Picture 2 Cards", "Picture 3 Ledger", "Picture Slide in"]
        bring(app, find(app, words[0]))
        idle(1)
        shot("a133-pictures-1")
        for i in 0..<pictures.count {
            let above = find(app, words[i]), picture = find(app, pictures[i]), below = find(app, words[i + 1])
            if !(above.exists && picture.exists && below.exists) { bring(app, picture) }
            XCTAssertTrue(above.exists && picture.exists && below.exists, "\(pictures[i]) and the words around it")
            XCTAssertLessThanOrEqual(above.frame.maxY, picture.frame.minY + 0.5, "\(pictures[i]) under its words")
            XCTAssertLessThanOrEqual(picture.frame.maxY, below.frame.minY + 0.5, "\(pictures[i]) before the next words")
            XCTAssertGreaterThan(picture.frame.width, app.windows.firstMatch.frame.width * 0.5,
                                 "\(pictures[i]) on its own, not a grid tile")
        }
        bring(app, find(app, pictures[2]))
        idle(1)
        shot("a133-pictures-2")
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

    // MARK: a161: a voice memo from the + menu, sent as an audio file

    /// + › Voice memo, the recorder bar, ■ to a preview that plays, then sent: his bubble plays it
    func testA161VoiceMemo() {
        let app = openChat(gallery, waitFor: "All five pages pass")
        app.buttons["attach"].tap()
        let item = app.buttons["Voice memo"]
        XCTAssertTrue(item.waitForExistence(timeout: 5), "Voice memo in the + menu")
        XCTAssertTrue(app.buttons["Photos"].exists)
        sleep(1)
        shot("a161-plus-menu")
        item.tap()
        XCTAssertTrue(el(app, "memoRecording").waitForExistence(timeout: 5), "the box is the memo's recorder")
        XCTAssertTrue(app.buttons["memoCancel"].exists)
        XCTAssertTrue(app.buttons["memoStop"].exists)
        XCTAssertFalse(app.buttons["mic"].exists, "the transcribe mic stays out of the way while recording")
        XCTAssertFalse(app.buttons["send"].exists)
        XCTAssertFalse(app.buttons["attach"].exists)
        XCTAssertTrue(find(app, "Recording, 3 seconds").waitForExistence(timeout: 8), "the clock runs")
        shot("a161-recording")
        app.buttons["memoStop"].tap()
        XCTAssertTrue(el(app, "memoPreview").waitForExistence(timeout: 8), "a preview to play first")
        let play = app.buttons["Play Voice memo"]
        XCTAssertTrue(play.waitForExistence(timeout: 5), "the preview has a player")
        XCTAssertTrue(app.buttons["memoRerecord"].exists)
        XCTAssertTrue(app.buttons["memoDelete"].exists)
        XCTAssertTrue(app.buttons["mic"].exists, "the transcribe mic is back")
        XCTAssertTrue(app.buttons["send"].isEnabled, "a memo alone can be sent")
        play.tap()
        XCTAssertTrue(app.buttons["Pause Voice memo"].waitForExistence(timeout: 8), "it plays")
        sleep(1)
        shot("a161-preview")
        type(app, "Here's the idea")
        app.buttons["send"].tap()
        XCTAssertTrue(find(app, "This is the demo").waitForExistence(timeout: 10))
        XCTAssertFalse(el(app, "memoPreview").exists, "the box is empty again")
        let mine = app.buttons["Play Voice memo"]
        XCTAssertTrue(mine.waitForExistence(timeout: 5), "his bubble plays the memo")
        XCTAssertTrue(find(app, "Here's the idea").exists)
        let width = app.windows.firstMatch.frame.width
        // his side: the card starts past the 60 pt gap (Claude's text starts at about 20); its play key is its left end
        XCTAssertGreaterThan(mine.frame.minX, width * 0.15, "in his bubble, on the right")
        sleep(1)
        shot("a161-sent")
    }

    /// ✕ while recording drops it; Re-record and Delete on the preview
    func testA161MemoCancelAndRerecord() {
        let app = openChat(gallery, waitFor: "All five pages pass")
        app.buttons["attach"].tap()
        app.buttons["Voice memo"].tap()
        XCTAssertTrue(el(app, "memoRecording").waitForExistence(timeout: 5))
        sleep(1)
        app.buttons["memoCancel"].tap()
        XCTAssertTrue(app.buttons["attach"].waitForExistence(timeout: 5), "cancelled: the box is back")
        XCTAssertFalse(el(app, "memoPreview").exists, "nothing kept")
        XCTAssertFalse(app.buttons["send"].isEnabled)

        app.buttons["attach"].tap()
        app.buttons["Voice memo"].tap()
        XCTAssertTrue(el(app, "memoRecording").waitForExistence(timeout: 5))
        sleep(1)
        app.buttons["memoStop"].tap()
        XCTAssertTrue(el(app, "memoPreview").waitForExistence(timeout: 8))
        app.buttons["memoRerecord"].tap()
        XCTAssertTrue(el(app, "memoRecording").waitForExistence(timeout: 5), "re-recording")
        XCTAssertFalse(el(app, "memoPreview").exists)
        sleep(1)
        app.buttons["memoStop"].tap()
        XCTAssertTrue(el(app, "memoPreview").waitForExistence(timeout: 8), "the new memo to preview")
        app.buttons["memoDelete"].tap()
        XCTAssertTrue(poll(3) { !el(app, "memoPreview").exists }, "deleted")
        XCTAssertFalse(app.buttons["send"].isEnabled)
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
        // a150: once, as queued (no second "Sending…" copy of it)
        XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "queued").count, 1)
        XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "sending").count, 0)
        shot("queued")
        app.buttons["stop"].tap()
        XCTAssertTrue(find(app, "This is the demo").waitForExistence(timeout: 5))
        XCTAssertFalse(find(app, "queued · sends").exists)
        // it went: now its own turn, still once
        let copies = app.descendants(matching: .staticText)
            .matching(NSPredicate(format: "label == %@", "Then make a lock screen version too"))
        XCTAssertEqual(copies.count, 1, "the message shows once")
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

    /// the Overview up and still (its slide in has ended), on whichever tab -tab picked
    private func overview(_ extra: [String] = []) -> App {
        let app = project(["-sheet"] + extra)
        let back = el(app, "overviewClose")
        XCTAssertTrue(back.waitForExistence(timeout: 10))
        // (the slide's own animation: the frame reads off screen until it starts, so wait for it rather than for stillness)
        XCTAssertTrue(poll(8) { back.frame.minX < 40 }, "the Overview slid all the way in (‹ at \(back.frame.minX))")
        settle { back.frame }
        return app
    }

    /// a141: a tab of the glass pill (Overview, Library, Scheduled)
    private func place(_ app: App, _ tab: String) {
        let t = el(app, "overviewTab-\(tab)")
        XCTAssertTrue(t.waitForExistence(timeout: 5))
        t.tap()
    }

    /// scrolls the page (half a screen at a time, no fling) until `id` is fully between the glass top and the
    /// bottom edge (a List only makes the rows it shows)
    @discardableResult
    private func reveal(_ app: App, _ id: String) -> Element {
        let e = el(app, id)
        let h = app.frame.height, top: CGFloat = 190, x = app.frame.midX
        for _ in 0..<12 {
            if e.exists && e.isHittable && e.frame.minY >= top && e.frame.maxY <= h - 50 { break }
            let down = e.exists && e.frame.minY < top
            let a = CGPoint(x: x, y: down ? h * 0.35 : h * 0.75), b = CGPoint(x: x, y: down ? h * 0.75 : h * 0.35)
            settle()
            Finger.press(a, seconds: 0, thenDragTo: b, speed: 700, hold: 0.25)
            idle(0.4)
        }
        XCTAssertTrue(e.exists, id)
        return e
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

    /// a127: drag the chat down a little (older turns come into view) so text passes under the glass top bar
    private func scrollUnderBar(_ app: App, by fraction: CGFloat = 0.18) {
        let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35))
        let to = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35 + fraction))
        from.press(forDuration: 0.1, thenDragTo: to)
        sleep(1)
    }

    /// a127: no band across the top; the glass pills float and the chat shows blurred behind them
    func testA127GlassBarProject() {
        let app = project()
        XCTAssertTrue(find(app, "NEEDS YOU").waitForExistence(timeout: 10))
        XCTAssertTrue(el(app, "overviewButton").exists)
        scrollUnderBar(app)
        shot("a127-project-chat")
        scrollUnderBar(app, by: 0.3)
        shot("a127-project-chat-2")
    }

    func testA127GlassBarThread() {
        let app = launch(["-place", "projects", "-push", contact])
        XCTAssertTrue(el(app, "threadPill").waitForExistence(timeout: 20))
        XCTAssertTrue(el(app, "taskCard").waitForExistence(timeout: 10))
        scrollUnderBar(app)
        shot("a127-thread")
    }

    func testA127GlassBarChat() {
        let app = openChat(gallery, waitFor: "All five pages pass")
        unfoldLast(app)
        scrollUnderBar(app)
        shot("a127-chat")
        scrollUnderBar(app, by: 0.3)
        shot("a127-chat-2")
    }

    /// a130: the same scrolled chats, with the turns showing through dimmed under the status bar (no black strip)
    func testA130SeeThroughProject() {
        let app = project()
        XCTAssertTrue(find(app, "NEEDS YOU").waitForExistence(timeout: 10))
        scrollUnderBar(app)
        shot("a130-project-chat")
        scrollUnderBar(app, by: 0.3)
        shot("a130-project-chat-2")
    }

    func testA130SeeThroughThread() {
        let app = launch(["-place", "projects", "-push", contact])
        XCTAssertTrue(el(app, "threadPill").waitForExistence(timeout: 20))
        XCTAssertTrue(el(app, "taskCard").waitForExistence(timeout: 10))
        scrollUnderBar(app)
        shot("a130-thread")
    }

    func testA130SeeThroughChat() {
        let app = openChat(gallery, waitFor: "All five pages pass")
        unfoldLast(app)
        scrollUnderBar(app)
        shot("a130-chat")
        scrollUnderBar(app, by: 0.3)
        shot("a130-chat-2")
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

    /// a141 1a: the Overview slides in from the right over the main chat, which moves left and dims
    func testP06Slide() {
        let app = project(["-sheet", "-slide", "0.55"])
        XCTAssertTrue(el(app, "overviewGlance").waitForExistence(timeout: 10))
        XCTAssertTrue(el(app, "overviewTab-overview").exists)
        sleep(1)
        shot("06-slide")
    }

    /// a141 1b/1c: the glass top (‹, name, +, three tabs), the main chat row with its subagents, every group,
    /// thread rows with their subagents, Done and Archived, usage by model and the plan
    func testP06Overview() {
        let app = overview()
        XCTAssertTrue(el(app, "overviewGlance").waitForExistence(timeout: 5))
        XCTAssertTrue(el(app, "overviewClose").exists)
        XCTAssertTrue(el(app, "overviewName").exists)
        XCTAssertTrue(el(app, "newThread").exists)
        for t in ["overview", "library", "scheduled"] { XCTAssertTrue(el(app, "overviewTab-\(t)").exists, t) }
        XCTAssertFalse(el(app, "overviewTab-ideas").exists, "ideas live in the Library tab")
        XCTAssertTrue(el(app, "mainChat").exists)
        XCTAssertTrue(find(app, "Review a7").exists, "the main chat's running subagent")
        XCTAssertTrue(el(app, "needsMain").exists)
        XCTAssertTrue(el(app, "thread-a6").exists)
        XCTAssertTrue(el(app, "thread-a4").exists)
        XCTAssertTrue(find(app, "Check the form on a small phone").exists, "a4's running subagent")
        sleep(1)
        shot("06-overview")
        reveal(app, "usagePlan")
        XCTAssertTrue(el(app, "doneThreads").exists)
        XCTAssertTrue(el(app, "archivedThreads").exists)
        XCTAssertTrue(find(app, "weekly 41%").exists)
        sleep(1)
        shot("06-overview-scrolled")
    }

    /// a thread's row opens its chat inside the Overview; Back returns to the Overview
    func testP06OpenThread() {
        let app = overview()
        el(app, "thread-a4").tap()
        XCTAssertTrue(el(app, "taskCard").waitForExistence(timeout: 10))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(el(app, "overviewGlance").waitForExistence(timeout: 5), "back on the Overview")
    }

    /// the main chat's row and ‹ both go back to the main chat
    func testP06BackToChat() {
        let app = overview()
        el(app, "overviewClose").tap()
        XCTAssertTrue(el(app, "overviewGlance").waitForNonExistence(timeout: 5))
        XCTAssertTrue(el(app, "projectPill").exists)
    }

    /// Done opens every done thread
    func testP06Done() {
        let app = overview()
        reveal(app, "doneThreads").tap()
        XCTAssertTrue(el(app, "thread-a1").waitForExistence(timeout: 5))
        XCTAssertTrue(find(app, "Home page hero").exists)
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

    /// 08 (a141 1d): Library: the Ideas on top, then the filter, pinned, notes, from threads; notes open to read
    /// and edit
    func testP08Library() {
        let app = overview()
        place(app, "library")
        XCTAssertTrue(el(app, "ideasTitle").waitForExistence(timeout: 5))
        XCTAssertTrue(el(app, "ideaText").exists)
        XCTAssertTrue(find(app, "Booking straight from the gallery").exists)
        XCTAssertTrue(el(app, "libraryAdd").exists)
        XCTAssertFalse(el(app, "lib-Ideas").exists, "the Ideas note isn't a row of its own")
        sleep(2)
        shot("08-library")
        reveal(app, "libraryKind-images").tap()
        XCTAssertTrue(reveal(app, "lib-contact-form.png").exists)
        XCTAssertFalse(el(app, "lib-Palette").exists)
        reveal(app, "libraryKind-all").tap()
        reveal(app, "lib-Palette").tap()
        XCTAssertTrue(el(app, "noteText").waitForExistence(timeout: 5))
        app.buttons["noteEdit"].tap()
        let editor = app.textViews["noteEditor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        editor.typeText("\n- Sand for the footer")
        app.buttons["noteSave"].tap()
        XCTAssertTrue(el(app, "noteSaved").waitForExistence(timeout: 5))
        XCTAssertTrue(find(app, "Sand for the footer").exists)
    }

    func testP08LibraryScrolled() {
        let app = overview(["-tab", "library"])
        XCTAssertTrue(el(app, "ideasTitle").waitForExistence(timeout: 5))
        reveal(app, "lib-gallery-tour.mp4")
        XCTAssertTrue(find(app, "From threads").exists)
        sleep(1)
        shot("08-library-scrolled")
    }

    func testP08FolderAndPicture() {
        let app = overview()
        place(app, "library")
        reveal(app, "lib-Memory").tap()
        XCTAssertTrue(el(app, "lib-MEMORY").waitForExistence(timeout: 5))
        let app2 = overview()
        place(app2, "library")
        reveal(app2, "lib-contact-form.png").tap()
        XCTAssertTrue(el(app2, "libraryPicture").waitForExistence(timeout: 5))
    }

    func testP08NoteConflict() {
        let app = overview(["-noteConflict"])
        place(app, "library")
        reveal(app, "lib-Palette").tap()
        app.buttons["noteEdit"].tap()
        let editor = app.textViews["noteEditor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        editor.typeText("\n- A night mode")
        app.buttons["noteSave"].tap()
        XCTAssertTrue(app.alerts["This note changed on the PC"].waitForExistence(timeout: 5))
        app.alerts.buttons["Keep mine"].tap()
        XCTAssertTrue(el(app, "noteSaved").waitForExistence(timeout: 5))
    }

    /// 09 (a141 1e): Ideas at the top of the Library: sections, AI suggestions, add one
    func testP09Ideas() {
        let app = overview(["-tab", "library"])
        XCTAssertTrue(el(app, "ideasTitle").waitForExistence(timeout: 5))
        XCTAssertTrue(find(app, "Booking straight from the gallery").exists)
        XCTAssertTrue(reveal(app, "idea-Lazy-load the gallery pictures").exists, "an AI suggestion")
        let field = reveal(app, "ideaText")
        field.tap()
        field.typeText("Gift cards for portrait sessions")
        el(app, "ideaAdd").tap()
        XCTAssertTrue(el(app, "idea-Gift cards for portrait sessions").waitForExistence(timeout: 5))
        sleep(1)
        shot("09-ideas")
    }

    /// 10 (a141 1f): Scheduled: next runs, a skipped one, one running now, paused, past runs
    func testP10Scheduled() {
        let app = overview()
        place(app, "scheduled")
        XCTAssertTrue(el(app, "schedule-s1").waitForExistence(timeout: 5))
        XCTAssertTrue(el(app, "newSchedule").exists)
        XCTAssertTrue(find(app, "PC was off").exists)
        XCTAssertTrue(find(app, "Running as b5").exists)
        sleep(1)
        shot("10-scheduled")
        el(app, "schedule-s1").tap()
        XCTAssertTrue(el(app, "scheduleRun").waitForExistence(timeout: 5))
        XCTAssertTrue(el(app, "schedulePause").exists)
    }

    func testP10ScheduledPast() {
        let app = overview(["-tab", "scheduled"])
        XCTAssertTrue(el(app, "schedule-s1").waitForExistence(timeout: 5))
        var n = 0
        while !find(app, "Past runs").exists && n < 6 {
            app.swipeUp()
            n += 1
        }
        XCTAssertTrue(find(app, "Past runs").exists)
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

    // MARK: a181 · the Studio's Edit stage (docs/studio-phone-mockups 15-28)

    /// the Edit stage of the demo's test video, loaded, with `flags`
    private func studio(_ flags: [String] = []) -> App {
        let app = launch(["-studioEdit"] + flags)
        XCTAssertTrue(el(app, "studioPlayer").waitForExistence(timeout: 20))
        XCTAssertTrue(el(app, "studioTitle").waitForExistence(timeout: 10))
        XCTAssertTrue(find(app, "The Keeper of Gull Point").waitForExistence(timeout: 10))
        return app
    }

    func testStudio15Overview() {
        let app = studio(["-studioTime", "25"])
        for id in ["toolAudio", "toolText", "toolPhoto", "toolShots", "toolMix", "toolChat", "studioPlay", "studioAdd"] {
            XCTAssertTrue(el(app, id).exists, id)
        }
        XCTAssertFalse(el(app, "toolSplit").exists, "no clip tools with nothing selected")
        sleep(2)
        shot("studio-15-edit")
    }

    func testStudio16Shot() {
        let app = studio(["-studioTime", "25", "-studioSelect", "v6"])
        XCTAssertTrue(el(app, "toolSplit").waitForExistence(timeout: 10))
        for id in ["toolTrim", "toolReplace", "toolTransition", "toolDelete", "toolBack"] { XCTAssertTrue(el(app, id).exists, id) }
        sleep(2)
        shot("studio-16-shot")
        el(app, "toolBack").tap()
        XCTAssertTrue(el(app, "toolAudio").waitForExistence(timeout: 5))
    }

    func testStudio17Trim() {
        let app = studio(["-studioTime", "25", "-studioTrim", "v6:right:-0.6"])
        XCTAssertTrue(el(app, "studioPeek").waitForExistence(timeout: 10), "the picture shows the frame at the handle")
        sleep(1)
        shot("studio-17-trim")
    }

    func testStudio18Split() {
        let app = studio(["-studioTime", "25", "-studioSelect", "v6"])
        XCTAssertTrue(el(app, "toolSplit").waitForExistence(timeout: 10))
        XCTAssertFalse(el(app, "studioUndo").isEnabled)
        el(app, "toolSplit").tap()
        XCTAssertTrue(find(app, "Split shot 6").waitForExistence(timeout: 5))
        XCTAssertTrue(el(app, "studioUndo").isEnabled)
        sleep(1)
        shot("studio-18-split")
        el(app, "studioToastUndo").tap()
        XCTAssertTrue(poll(5) { !el(app, "studioUndo").isEnabled }, "the split is undone")
    }

    func testStudio19Voice() {
        let app = studio(["-studioTime", "25", "-studioSelect", "voice:c5"])
        XCTAssertTrue(el(app, "sheetVoice").waitForExistence(timeout: 10))
        XCTAssertTrue(find(app, "Voice line c5").exists)
        sleep(1)
        shot("studio-19-voice")
    }

    func testStudio20Sounds() {
        let app = studio(["-studioTime", "25", "-studioSheet", "sounds", "-studioSearch", "rain"])
        XCTAssertTrue(el(app, "sheetSounds").waitForExistence(timeout: 10))
        XCTAssertTrue(find(app, "FREESOUND · CC0 ONLY").waitForExistence(timeout: 10))
        XCTAssertTrue(el(app, "soundsToGenerate").exists)
        sleep(1)
        shot("studio-20-sounds")
        // a generation shows its price and waits for a yes
        el(app, "soundsToGenerate").tap()
        XCTAssertTrue(el(app, "generatePrice").waitForExistence(timeout: 5))
        el(app, "generatePrice").tap()
        XCTAssertTrue(el(app, "generateEstimate").waitForExistence(timeout: 10))
        XCTAssertTrue(el(app, "generateConfirm").exists)
        shot("studio-20b-generate")
    }

    func testStudio21Text() {
        let app = studio(["-studioTime", "20", "-studioSelect", "t2"])
        XCTAssertTrue(el(app, "sheetText").waitForExistence(timeout: 10))
        XCTAssertTrue(el(app, "seg-lower").exists)
        sleep(1)
        shot("studio-21-text")
    }

    func testStudio22Transition() {
        let app = studio(["-studioTime", "26.2", "-studioSelect", "v7", "-studioSheet", "transition"])
        XCTAssertTrue(el(app, "sheetTransition").waitForExistence(timeout: 10))
        XCTAssertTrue(find(app, "Into shot 7").exists)
        el(app, "transition-crossfade").tap()
        XCTAssertTrue(el(app, "studioUndo").isEnabled)
        sleep(1)
        shot("studio-22-transition")
    }

    func testStudio23Photo() {
        let app = studio(["-studioTime", "25", "-studioSheet", "photo"])
        XCTAssertTrue(el(app, "sheetPhoto").waitForExistence(timeout: 10))
        XCTAssertTrue(el(app, "photo-p2").waitForExistence(timeout: 5))
        el(app, "photo-p2").tap()
        sleep(1)
        shot("studio-23-photo")
        el(app, "photoAdd").tap()
        XCTAssertTrue(el(app, "toolKenBurns").waitForExistence(timeout: 5), "the new photo is selected with its tools")
    }

    func testStudio24KenBurns() {
        let app = studio(["-studioAddPhoto", "p1", "-studioTime", "25", "-studioSheet", "kenburns"])
        XCTAssertTrue(el(app, "sheetKenBurns").waitForExistence(timeout: 10))
        XCTAssertTrue(el(app, "kb-in").exists)
        sleep(2)
        shot("studio-24-ken-burns")
    }

    func testStudio25Mix() {
        let app = studio(["-studioTime", "25", "-studioSheet", "mix"])
        XCTAssertTrue(el(app, "sheetMix").waitForExistence(timeout: 10))
        XCTAssertTrue(el(app, "mixLoudness").exists)
        XCTAssertTrue(el(app, "mixOutOfDate").exists)
        XCTAssertTrue(el(app, "mixdownMake").exists)
        sleep(1)
        shot("studio-25-mix")
    }

    func testStudio26Zoom() {
        _ = studio(["-studioTime", "25", "-studioZoom", "7"])
        sleep(2)
        shot("studio-26-zoom")
    }

    func testStudio27Reorder() {
        _ = studio(["-studioTime", "25", "-studioLift", "v6:1"])
        sleep(2)
        shot("studio-27-reorder")
    }

    func testStudio28Chat() {
        let app = launch(["-studioEdit", "-studioChat"])
        XCTAssertTrue(el(app, "chatContext").waitForExistence(timeout: 20))
        XCTAssertTrue(find(app, "Edit · shot 6 selected").exists)
        XCTAssertTrue(find(app, "Cut to the weather log").waitForExistence(timeout: 10))
        sleep(1)
        shot("studio-28-chat")
    }
}
