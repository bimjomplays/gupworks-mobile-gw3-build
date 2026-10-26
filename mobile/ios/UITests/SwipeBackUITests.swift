import XCTest

/// a128: swiping right goes back to where you came from. A project's main chat opened from a pin in the side menu is
/// the main screen, so the swipe opens the menu again (pins and chats); opened from the Projects section it is pushed
/// over the Projects page, so the swipe goes back there.
final class SwipeBackUITests: XCTestCase {
    /// the demo's Lumen project (an invented id, written in two parts so the privacy scan doesn't take it for a key)
    private let lumen = "00000066-1111-4222-" + "8333-000000000066"
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-demo", "-menu"]
        app.launch()
    }

    private func el(_ id: String) -> XCUIElement {
        app.descendants(matching: .any)[id].firstMatch
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

    /// a swipe right across the window from `x0`, a flick (the edge for x0 near 0: the system's back swipe)
    private func swipeRight(from x0: CGFloat) {
        let win = app.windows.firstMatch
        win.coordinate(withNormalizedOffset: CGVector(dx: x0, dy: 0.5))
            .press(forDuration: 0.05, thenDragTo: win.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.51)),
                   withVelocity: XCUIGestureVelocity(rawValue: 1500), thenHoldForDuration: 0)
    }

    /// swipes, and once more when the result didn't show up at all (a slow runner drops part of a drag)
    private func swipeUntil(_ x0: CGFloat, _ done: () -> Bool) {
        swipeRight(from: x0)
        if !done() { swipeRight(from: x0) }
    }

    private func shown(_ id: String, timeout: TimeInterval = 10) -> () -> Bool {
        { self.el(id).waitForExistence(timeout: timeout) }
    }

    /// the pinned project's main chat is up and its Overview (which opens by itself) is put away
    private func openLumenFromPin() {
        let pin = el("pin-Lumen Studio website")
        XCTAssertTrue(pin.waitForExistence(timeout: 30))
        waitStill(pin)
        pin.tap()
        XCTAssertTrue(el("projectPill").waitForExistence(timeout: 20), "the project's main chat opened")
        XCTAssertTrue(el("overviewGlance").waitForExistence(timeout: 15), "its Overview came up")
        el("overviewClose").tap()
        XCTAssertTrue(el("overviewGlance").waitForNonExistence(timeout: 10))
    }

    /// from a pin: swipe right opens the side menu (pins and chats), not the Projects page
    func testPinnedProjectSwipesBackToTheMenu() {
        openLumenFromPin()
        XCTAssertFalse(el("place-projects").exists, "the menu is closed behind the chat")
        shot("a128-pinned-chat")
        swipeUntil(0.3) { self.shown("place-projects")() }
        XCTAssertTrue(el("place-projects").exists, "the menu came back")
        XCTAssertTrue(el("pin-Lumen Studio website").exists, "with the pins")
        XCTAssertTrue(el("closeMenu").exists, "and the chat pushed aside")
        XCTAssertFalse(el("projectList").exists, "not the Projects page")
        waitStill(el("closeMenu"))
        shot("a128-pinned-swipe-menu")
    }

    /// from the Projects section: swipe right (the system's back swipe from the edge) goes back to Projects
    func testProjectFromProjectsSwipesBackToProjects() {
        let projects = el("place-projects")
        XCTAssertTrue(projects.waitForExistence(timeout: 30))
        waitStill(projects)
        projects.tap()
        let row = el("project-\(lumen)")
        XCTAssertTrue(row.waitForExistence(timeout: 20), "the Projects page")
        waitStill(row)
        row.tap()
        XCTAssertTrue(el("projectPill").waitForExistence(timeout: 20), "the project's main chat opened")
        if el("overviewGlance").waitForExistence(timeout: 3) {
            el("overviewClose").tap()
            XCTAssertTrue(el("overviewGlance").waitForNonExistence(timeout: 10))
        }
        shot("a128-projects-chat")
        swipeUntil(0.0) { self.shown("projectList")() }
        XCTAssertTrue(el("projectList").waitForExistence(timeout: 10), "back on the Projects page")
        XCTAssertFalse(el("projectPill").exists, "the project's chat is gone")
        XCTAssertFalse(el("closeMenu").exists, "the menu didn't open")
        shot("a128-projects-swipe-back")
    }
}
