import XCTest

/// The few screens that need the system's own touches, media or launch settings: sorting pins by a held drag, the
/// video player, the Overview's swipe actions, Markdown tables (sideways scrolling against the menu's swipe; the
/// largest text size is a launch setting) and pairing (a typed return). Everything else moved to
/// Tests/ScreenTests.swift, which drives the screens inside the unit-test process in seconds. Each picture is
/// attached to the test result and, when the runner sets SHOTS_DIR (TEST_RUNNER_SHOTS_DIR for xcodebuild), also
/// written there as a PNG.
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
        XCTAssertTrue(app.buttons["videoClose"].waitForExistence(timeout: 5))
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

    // ci-covers: ProjectOverview.swift OverviewLayer.swift
    func testP06SwipeAndPress() {
        let app = overview()
        drag(app, el(app, "thread-a6"), from: 0.9, to: 0.4)
        XCTAssertTrue(app.buttons["Pause"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Mark done"].exists)
        sleep(1)
        shot("06-swipe")
        app.buttons["Pause"].tap()
        // paused, it moves down to the Idle group
        let a6 = el(app, "thread-a6")
        for _ in 0..<5 where !(a6.exists && a6.isHittable) { app.swipeUp() }
        drag(app, a6, from: 0.9, to: 0.4)
        XCTAssertTrue(app.buttons["Resume"].waitForExistence(timeout: 5))
        app.buttons["Resume"].tap()
        let a4 = el(app, "thread-a4")
        for _ in 0..<3 { app.swipeDown() } // back to the top, where a4 is under Working
        XCTAssertTrue(a4.waitForExistence(timeout: 5))
        a4.press(forDuration: 1.2)
        XCTAssertTrue(app.buttons["Stop\u{2026}"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Open"].exists)
        XCTAssertTrue(app.buttons["Rename\u{2026}"].exists)
        XCTAssertTrue(app.buttons["Archive"].exists)
        XCTAssertTrue(app.buttons["Delete\u{2026}"].exists)
        shot("06-press")
        app.buttons["Stop\u{2026}"].tap()
        XCTAssertTrue(find(app, "Stop \u{201C}Contact page form\u{201D}?").waitForExistence(timeout: 5))
    }

    // MARK: a124: Markdown tables

    /// a124: a table's cells were measured one line tall and drawn wrapped, so long cells ran over the next rows,
    /// and a wide table ran off the screen. Demo chat 17: a 3-column table with long cells fits the screen with
    /// rows as tall as their text; a 6-column one scrolls inside its box (and a swipe back doesn't open the menu).
    // ci-covers: MarkdownViews.swift MainView.swift
    func testTablesWrapAndScroll() {
        checkTables([], shots: true)
    }

    /// the same at the largest accessibility text size
    // ci-covers: MarkdownViews.swift
    func testTablesAtTheLargestTextSize() {
        checkTables(["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"], shots: false)
    }

    private func checkTables(_ extra: [String], shots: Bool) {
        let app = openChat(chat(17), waitFor: "The quick lane is the best next step", extra)
        let screen = app.windows.firstMatch.frame
        let tables = app.descendants(matching: .any).matching(identifier: "table")
        XCTAssertTrue(tables.firstMatch.waitForExistence(timeout: 10), "a table shows")
        onScreen(app, el(app, "chatTitle"), "the title")
        onScreen(app, box(app), "the box")
        onScreen(app, app.buttons["send"], "the send button")

        // the newest reply's 6-column table: wider than the screen, so it scrolls inside its box
        let wide = tables.containing(NSPredicate(format: "label CONTAINS %@", "Hosted runners")).firstMatch
        XCTAssertTrue(wide.exists, "the 6-column table")
        var cells = tableCells(wide, columns: 6, rows: 5)
        onScreen(app, wide, "the wide table's box")
        XCTAssertGreaterThan(wide.frame.width, screen.width * 0.7, "the wide table's box fills the chat's width")
        noOverlap(cells, "the wide table")
        let lastHead = wide.descendants(matching: .any)["cell-0-5"]
        XCTAssertGreaterThan(lastHead.frame.maxX, wide.frame.maxX + 1, "the 6th column starts off to the right")
        if shots { sleep(1); shot("table-wide") }
        for _ in 0..<4 where lastHead.frame.maxX > wide.frame.maxX + 1 {
            wide.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.5))
                .press(forDuration: 0.05, thenDragTo: wide.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.5)),
                       withVelocity: .slow, thenHoldForDuration: 0.3)
        }
        XCTAssertLessThanOrEqual(lastHead.frame.maxX, wide.frame.maxX + 1, "scrolled: the 6th column shows")
        onScreen(app, wide, "the wide table's box, scrolled")
        onScreen(app, box(app), "the box with the table scrolled")
        noOverlap(tableCells(wide, columns: 6, rows: 5), "the wide table, scrolled")
        let first = wide.descendants(matching: .any)["cell-0-0"]
        let scrolledX = first.frame.minX
        if shots { sleep(1); shot("table-wide-scrolled") }
        // back: the table scrolls back, the menu stays shut
        wide.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.5))
            .press(forDuration: 0.05, thenDragTo: wide.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.5)),
                   withVelocity: .slow, thenHoldForDuration: 0.3)
        sleep(1)
        XCTAssertFalse(el(app, "place-projects").exists, "a swipe back on a scrolled table doesn't open the menu")
        XCTAssertGreaterThan(first.frame.minX, scrolledX + 100, "the table scrolled back")

        // the first reply's 3-column table, long cells wrapped, as wide as the chat at most
        scrollUp(app, until: find(app, "start with step 1"))
        let narrow = tables.containing(NSPredicate(format: "label CONTAINS %@", "its own quick check")).firstMatch
        XCTAssertTrue(narrow.exists, "the 3-column table")
        cells = tableCells(narrow, columns: 3, rows: 4)
        onScreen(app, narrow, "the 3-column table's box")
        noOverlap(cells, "the 3-column table")
        for row in cells {
            for c in row {
                XCTAssertLessThanOrEqual(c.maxX, narrow.frame.maxX + 0.5, "every column fits: \(c) in \(narrow.frame)")
            }
        }
        XCTAssertGreaterThan(cells[1][1].height, 40, "a long cell wraps onto more lines: \(cells[1][1])")
        onScreen(app, box(app), "the box with the 3-column table in view")
        if shots { sleep(1); shot("table-3-columns") }
    }

    /// the frames of a table's cells, row by row (row 0 is the header)
    private func tableCells(_ table: XCUIElement, columns: Int, rows: Int) -> [[CGRect]] {
        (0..<rows).map { r in
            (0..<columns).map { c in
                let e = table.descendants(matching: .any)["cell-\(r)-\(c)"]
                XCTAssertTrue(e.exists, "cell \(r), \(c)")
                return e.frame
            }
        }
    }

    /// no two cells overlap, and every row starts below the one above it
    private func noOverlap(_ cells: [[CGRect]], _ what: String) {
        let all = cells.flatMap { $0 }
        for i in all.indices {
            XCTAssertGreaterThan(all[i].height, 10, "\(what): cell \(i) has a size: \(all[i])")
            for j in all.indices where j > i {
                let o = all[i].intersection(all[j])
                XCTAssertFalse(!o.isNull && o.width > 0.5 && o.height > 0.5,
                               "\(what): cells \(i) \(all[i]) and \(j) \(all[j]) overlap")
            }
        }
        for r in cells.indices.dropFirst() {
            let above = cells[r - 1].map(\.maxY).max() ?? 0
            let top = cells[r].map(\.minY).min() ?? 0
            XCTAssertGreaterThanOrEqual(top, above - 0.5, "\(what): row \(r) starts inside the row above")
        }
    }

    /// drags the chat down in short steps until `e` sits in the lower part of the screen (its photos above it show)
    private func scrollUp(_ app: XCUIApplication, until e: XCUIElement) {
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

    private func onScreen(_ app: XCUIApplication, _ e: XCUIElement, _ what: String) {
        let screen = app.windows.firstMatch.frame
        XCTAssertTrue(e.exists, what)
        XCTAssertGreaterThanOrEqual(e.frame.minX, screen.minX - 0.5, "\(what) starts left of the screen: \(e.frame)")
        XCTAssertLessThanOrEqual(e.frame.maxX, screen.maxX + 0.5, "\(what) ends right of the screen: \(e.frame)")
    }

    private func box(_ app: XCUIApplication) -> XCUIElement {
        app.textFields["composer"].exists ? app.textFields["composer"] : app.textViews["composer"]
    }

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
}
