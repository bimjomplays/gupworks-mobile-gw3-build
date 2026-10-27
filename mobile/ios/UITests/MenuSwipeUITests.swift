import XCTest

// ci-covers: MenuView.swift MainView.swift
/// Closing the side menu by a swipe left, from wherever the finger starts: the menu's rows on the left, its empty
/// space in the middle, the dimmed chat strip on the right; a short flick closes too, a short slow drag snaps back.
/// The menu still scrolls up and down, and a lifted pin moved sideways sorts instead of closing it.
///
/// CI's runners are sometimes very slow (9 s "checking for interrupting elements" before a drag) and then drop part
/// of a synthesized drag: the chat moved a fifth of the way and went back. So the tests wait for the menu to stand
/// still instead of sleeping, allow 10 s or more, and try a close swipe or the menu button once more when its result
/// didn't show up at all. A gesture the app gets wrong fails both times, so nothing checked here got weaker. The
/// pin's long press has no second try: a 0.9 s press that doesn't lift is a bug.
final class MenuSwipeUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    private var app: XCUIApplication!

    private func el(_ id: String) -> XCUIElement {
        app.descendants(matching: .any)[id].firstMatch
    }

    private var menuShown: XCUIElement { el("place-projects") }

    private func launchWithMenu(_ extra: [String] = []) {
        app = XCUIApplication()
        app.launchArguments = ["-demo", "-menu"] + extra
        app.launch()
        XCTAssertTrue(menuShown.waitForExistence(timeout: 30))
        settle()
    }

    /// waits until `e` stops moving (0.3 s with the same frame, or gone), at most `timeout`
    private func waitStill(_ e: XCUIElement, timeout: TimeInterval = 10) {
        let end = Date().addingTimeInterval(timeout)
        var last = e.exists ? e.frame : CGRect.null
        while Date() < end {
            usleep(300_000)
            let now = e.exists ? e.frame : CGRect.null
            if now == last { return }
            last = now
        }
    }

    /// the menu is open and done sliding
    private func settle() {
        XCTAssertTrue(el("closeMenu").waitForExistence(timeout: 10), "the chat is pushed aside")
        waitStill(el("closeMenu"))
        waitStill(menuShown)
    }

    /// a swipe that should close the menu; once more if the menu stayed open (a dropped drag), then the checks
    private func swipeCloses(_ x0: CGFloat, to x1: CGFloat, y: CGFloat, slow: Bool, _ what: String,
                             file: StaticString = #filePath, line: UInt = #line) {
        swipe(x0, to: x1, y: y, slow: slow)
        if !menuShown.waitForNonExistence(timeout: 10) && !el("comingSoon").exists {
            XCTContext.runActivity(named: "\(what): the menu stayed open, swiping once more") { _ in }
            settle()
            swipe(x0, to: x1, y: y, slow: slow)
        }
        assertCloses(what, file: file, line: line)
    }

    private func openMenu() {
        let button = app.buttons["menu"]
        XCTAssertTrue(button.waitForExistence(timeout: 20))
        waitStill(button)
        button.tap()
        if !menuShown.waitForExistence(timeout: 10) {
            XCTContext.runActivity(named: "the menu button's tap was dropped, tapping once more") { _ in }
            button.tap()
        }
        XCTAssertTrue(menuShown.waitForExistence(timeout: 10))
        settle()
    }

    /// a swipe across the window from (x0, y) to (x1, y + a little), by fractions of the window. Velocities are in
    /// pixels per second (.fast is only 750, 250 pt/s on a 3x screen): fast is 1000 pt/s, a flick; slow ones are
    /// 50 pt/s and stop before the finger lifts, so only the distance counts.
    private func swipe(_ x0: CGFloat, to x1: CGFloat, y: CGFloat, slow: Bool) {
        let win = app.windows.firstMatch
        win.coordinate(withNormalizedOffset: CGVector(dx: x0, dy: y))
            .press(forDuration: 0.05,
                   thenDragTo: win.coordinate(withNormalizedOffset: CGVector(dx: x1, dy: y + 0.01)),
                   withVelocity: XCUIGestureVelocity(rawValue: slow ? 150 : 3000),
                   thenHoldForDuration: slow ? 0.4 : 0)
    }

    private func assertCloses(_ what: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(menuShown.waitForNonExistence(timeout: 10), "\(what) closes the menu", file: file, line: line)
        // and it was only a swipe: the row it started on didn't open (the old menu opened Gup Bot here)
        XCTAssertFalse(el("comingSoon").exists, "\(what) opened a page (\(el("comingSoon").exists ? (el("comingSoon").value as? String ?? "?") : ""))", file: file, line: line)
        XCTAssertTrue(app.buttons["menu"].waitForExistence(timeout: 10), "\(what): back on the chat",
                      file: file, line: line)
    }

    private func assertStaysOpen(_ what: String, file: StaticString = #filePath, line: UInt = #line) {
        waitStill(el("closeMenu"))
        waitStill(menuShown)
        XCTAssertTrue(menuShown.exists, "\(what) leaves the menu open", file: file, line: line)
        XCTAssertTrue(el("closeMenu").exists, "\(what): the chat is still pushed aside", file: file, line: line)
    }

    func testClosesFromTheLeftMiddleAndRight() {
        launchWithMenu()
        // left: a flick starting on the menu's rows
        swipeCloses(0.3, to: 0.02, y: 0.3, slow: false, "a flick from a row on the left")
        openMenu()
        // middle: a slow drag through the empty space beside the GupWorks title, past half the menu's width
        swipeCloses(0.5, to: 0.1, y: 0.1, slow: true, "a slow drag from the middle")
        openMenu()
        // right: the dimmed chat strip
        swipeCloses(0.93, to: 0.45, y: 0.5, slow: true, "a slow drag from the chat strip on the right")
        openMenu()
        swipeCloses(0.97, to: 0.6, y: 0.75, slow: false, "a flick from the far right edge")
    }

    /// a131 diagnostic (to be dropped): the first flick after a cold launch, eight times
    func testZDiagRowFlicks() {
        continueAfterFailure = true
        var bad = 0
        for i in 1...8 {
            launchWithMenu()
            swipe(0.3, to: 0.02, y: 0.3, slow: false)
            let closed = menuShown.waitForNonExistence(timeout: 10)
            let page = el("comingSoon")
            let opened = page.waitForExistence(timeout: 2)
            print("a131 diag flick \(i): closed=\(closed) opened=\(opened) log=\(opened ? (page.value as? String ?? "") : "")")
            if opened || !closed { bad += 1 }
        }
        XCTAssertEqual(bad, 0, "flicks that opened a page or didn't close")
    }

    func testShortFlickClosesAndShortDragSnapsBack() {
        launchWithMenu()
        // about a fifth of the way, slowly: it goes back open
        swipe(0.6, to: 0.45, y: 0.5, slow: true)
        assertStaysOpen("a short slow drag")
        // a slow drag that passes 35% (about 45% here): closed, as the chat moved point for point with the finger
        swipeCloses(0.6, to: 0.25, y: 0.5, slow: true, "a slow drag past a third")
        openMenu()
        // a short flick
        swipeCloses(0.6, to: 0.48, y: 0.45, slow: false, "a short flick")
    }

    func testMenuStillScrollsAndSortsPins() {
        launchWithMenu()
        // up and down: the list scrolls and the menu stays
        let win = app.windows.firstMatch
        let top = menuShown.frame.minY
        func scrollUp() {
            win.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.75))
                .press(forDuration: 0.05, thenDragTo: win.coordinate(withNormalizedOffset: CGVector(dx: 0.32, dy: 0.4)),
                       withVelocity: XCUIGestureVelocity(rawValue: 400), thenHoldForDuration: 0.3)
            waitStill(menuShown)
        }
        scrollUp()
        if menuShown.exists && menuShown.frame.minY == top {
            XCTContext.runActivity(named: "the list didn't move at all, scrolling once more") { _ in }
            scrollUp()
        }
        XCTAssertLessThan(menuShown.frame.minY, top - 60, "the menu scrolled up")
        assertStaysOpen("scrolling up")
        win.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.3))
            .press(forDuration: 0.05, thenDragTo: win.coordinate(withNormalizedOffset: CGVector(dx: 0.28, dy: 0.8)),
                   withVelocity: .default, thenHoldForDuration: 0.3)
        assertStaysOpen("scrolling down")

        // a lifted pin moved sideways and up sorts, the menu stays
        let (wallpaper, lumen) = liftWallpaperOverLumen()
        waitStill(wallpaper)
        XCTAssertLessThan(wallpaper.frame.minY, lumen.frame.minY, "Wallpaper ideas moved to the top")
        assertStaysOpen("a lifted pin moved left")
        el("doneSorting").tap()
        XCTAssertTrue(el("doneSorting").waitForNonExistence(timeout: 10), "Done puts the pin down")
        waitStill(menuShown)
        // and the swipe works again once it's put down
        swipeCloses(0.6, to: 0.1, y: 0.5, slow: false, "a swipe after sorting")
    }

    /// long-presses the Wallpaper ideas pin and drags it left and up over Lumen Studio website: the pin lifts and the
    /// menu stays where it is (the drag is sideways, so the menu's close swipe must not start under it)
    private func liftWallpaperOverLumen(file: StaticString = #filePath, line: UInt = #line)
        -> (XCUIElement, XCUIElement) {
        let wallpaper = el("pin-Wallpaper ideas"), lumen = el("pin-Lumen Studio website")
        XCTAssertTrue(wallpaper.waitForExistence(timeout: 10), file: file, line: line)
        waitStill(wallpaper)
        let chatX = el("closeMenu").frame.minX
        let to = lumen.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.5))
        wallpaper.coordinate(withNormalizedOffset: CGVector(dx: 0.6, dy: 0.5))
            .press(forDuration: 0.9, thenDragTo: to, withVelocity: .slow, thenHoldForDuration: 0.4)
        let after = XCTAttachment(screenshot: app.screenshot())
        after.name = "after the pin drag"
        after.lifetime = .keepAlways
        add(after)
        XCTAssertTrue(el("doneSorting").waitForExistence(timeout: 10), "a long press lifts the pin",
                      file: file, line: line)
        // CI once had the chat slide part way with the pin and stick there, then the menu closed by itself
        XCTAssertTrue(menuShown.exists && el("closeMenu").exists, "the menu stayed open while the pin moved",
                      file: file, line: line)
        waitStill(el("closeMenu"))
        XCTAssertEqual(el("closeMenu").frame.minX, chatX, accuracy: 2, "the chat didn't move with the pin",
                       file: file, line: line)
        return (wallpaper, lumen)
    }

    /// a busy phone: the menu's news that a pin lifted reaches the main view a second late (-slowLift). The pin's
    /// drag starts before then, and the menu must still not slide with it.
    func testPinLiftOnABusyPhone() {
        launchWithMenu(["-slowLift"])
        let (wallpaper, lumen) = liftWallpaperOverLumen()
        waitStill(wallpaper)
        XCTAssertLessThan(wallpaper.frame.minY, lumen.frame.minY, "Wallpaper ideas moved to the top")
        assertStaysOpen("a lifted pin moved left")
    }
}
