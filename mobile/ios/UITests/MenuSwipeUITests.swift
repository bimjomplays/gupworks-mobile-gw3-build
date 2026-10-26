import XCTest

/// Closing the side menu by a swipe left, from wherever the finger starts: the menu's rows on the left, its empty
/// space in the middle, the dimmed chat strip on the right; a short flick closes too, a short slow drag snaps back.
/// The menu still scrolls up and down, and a lifted pin moved sideways sorts instead of closing it.
final class MenuSwipeUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    private var app: XCUIApplication!

    private func el(_ id: String) -> XCUIElement {
        app.descendants(matching: .any)[id].firstMatch
    }

    private var menuShown: XCUIElement { el("place-projects") }

    private func launchWithMenu() {
        app = XCUIApplication()
        app.launchArguments = ["-demo", "-menu"]
        app.launch()
        XCTAssertTrue(menuShown.waitForExistence(timeout: 20))
    }

    private func openMenu() {
        let button = app.buttons["menu"]
        XCTAssertTrue(button.waitForExistence(timeout: 10))
        button.tap()
        XCTAssertTrue(menuShown.waitForExistence(timeout: 5))
        sleep(1)
    }

    /// a swipe across the window from (x0, y) to (x1, y + a little), by fractions of the window. Slow ones stop
    /// before the finger lifts, so only the distance counts.
    private func swipe(_ x0: CGFloat, to x1: CGFloat, y: CGFloat, slow: Bool) {
        let win = app.windows.firstMatch
        win.coordinate(withNormalizedOffset: CGVector(dx: x0, dy: y))
            .press(forDuration: 0.05,
                   thenDragTo: win.coordinate(withNormalizedOffset: CGVector(dx: x1, dy: y + 0.01)),
                   withVelocity: slow ? XCUIGestureVelocity(rawValue: 150) : .fast,
                   thenHoldForDuration: slow ? 0.4 : 0)
    }

    private func assertCloses(_ what: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(menuShown.waitForNonExistence(timeout: 5), "\(what) closes the menu", file: file, line: line)
    }

    private func assertStaysOpen(_ what: String, file: StaticString = #filePath, line: UInt = #line) {
        sleep(1)
        XCTAssertTrue(menuShown.exists, "\(what) leaves the menu open", file: file, line: line)
        XCTAssertTrue(el("closeMenu").exists, "\(what): the chat is still pushed aside", file: file, line: line)
    }

    func testClosesFromTheLeftMiddleAndRight() {
        launchWithMenu()
        // left: a flick starting on the menu's rows
        swipe(0.3, to: 0.02, y: 0.3, slow: false)
        assertCloses("a flick from a row on the left")
        openMenu()
        // middle: a slow drag through the empty space beside the GupWorks title, past half the menu's width
        swipe(0.5, to: 0.1, y: 0.1, slow: true)
        assertCloses("a slow drag from the middle")
        openMenu()
        // right: the dimmed chat strip
        swipe(0.93, to: 0.45, y: 0.5, slow: true)
        assertCloses("a slow drag from the chat strip on the right")
        openMenu()
        swipe(0.97, to: 0.6, y: 0.75, slow: false)
        assertCloses("a flick from the far right edge")
    }

    func testShortFlickClosesAndShortDragSnapsBack() {
        launchWithMenu()
        // about a fifth of the way, slowly: it goes back open
        swipe(0.6, to: 0.45, y: 0.5, slow: true)
        assertStaysOpen("a short slow drag")
        // a slow drag that passes 35% (about 45% here): closed, as the chat moved point for point with the finger
        swipe(0.6, to: 0.25, y: 0.5, slow: true)
        assertCloses("a slow drag past a third")
        openMenu()
        // a short flick
        swipe(0.6, to: 0.48, y: 0.45, slow: false)
        assertCloses("a short flick")
    }

    func testMenuStillScrollsAndSortsPins() {
        launchWithMenu()
        // up and down: the list scrolls and the menu stays
        let win = app.windows.firstMatch
        let top = menuShown.frame.minY
        win.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.75))
            .press(forDuration: 0.05, thenDragTo: win.coordinate(withNormalizedOffset: CGVector(dx: 0.32, dy: 0.4)),
                   withVelocity: XCUIGestureVelocity(rawValue: 400), thenHoldForDuration: 0.3)
        XCTAssertLessThan(menuShown.frame.minY, top - 60, "the menu scrolled up")
        assertStaysOpen("scrolling up")
        win.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.3))
            .press(forDuration: 0.05, thenDragTo: win.coordinate(withNormalizedOffset: CGVector(dx: 0.28, dy: 0.8)),
                   withVelocity: .default, thenHoldForDuration: 0.3)
        assertStaysOpen("scrolling down")

        // a lifted pin moved sideways and up sorts, the menu stays
        let wallpaper = el("pin-Wallpaper ideas"), lumen = el("pin-Lumen Studio website")
        XCTAssertTrue(wallpaper.waitForExistence(timeout: 5))
        let to = lumen.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.5))
        wallpaper.coordinate(withNormalizedOffset: CGVector(dx: 0.6, dy: 0.5))
            .press(forDuration: 0.9, thenDragTo: to, withVelocity: .slow, thenHoldForDuration: 0.4)
        XCTAssertTrue(el("doneSorting").waitForExistence(timeout: 5))
        XCTAssertLessThan(wallpaper.frame.minY, lumen.frame.minY, "Wallpaper ideas moved to the top")
        assertStaysOpen("a lifted pin moved left")
        el("doneSorting").tap()
        // and the swipe works again once it's put down
        swipe(0.6, to: 0.1, y: 0.5, slow: false)
        assertCloses("a swipe after sorting")
    }
}
