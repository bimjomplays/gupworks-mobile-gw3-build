import XCTest

/// a141: the project Overview is a page pushed in from the right. A swipe left in the main chat (or its Overview
/// button) slides it in; a swipe right (or its ‹) slides it back out to the chat.
// ci-covers: OverviewLayer.swift MainView.swift ChatView.swift ProjectOverview.swift
final class OverviewSwipeUITests: XCTestCase {
    private var app: XCUIApplication!
    private let lumen = "00000066-1111-4222-8333-000000000066"

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-demo", "-place", "projects", "-push", lumen]
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

    /// a flick across the window from x0 to x1 at height y
    private func swipe(_ x0: CGFloat, _ x1: CGFloat, y: CGFloat) {
        let win = app.windows.firstMatch
        win.coordinate(withNormalizedOffset: CGVector(dx: x0, dy: y))
            .press(forDuration: 0.05, thenDragTo: win.coordinate(withNormalizedOffset: CGVector(dx: x1, dy: y + 0.01)),
                   withVelocity: XCUIGestureVelocity(rawValue: 1500), thenHoldForDuration: 0)
    }

    /// swipes, and once more a little lower when nothing happened (a slow runner drops part of a drag)
    private func swipeUntil(_ x0: CGFloat, _ x1: CGFloat, _ done: () -> Bool) {
        swipe(x0, x1, y: 0.45)
        if !done() { swipe(x0, x1, y: 0.6) }
    }

    private func mainChat() {
        let pill = el("projectPill")
        XCTAssertTrue(pill.waitForExistence(timeout: 30), "the project's main chat")
        waitStill(pill)
        XCTAssertFalse(el("overviewGlance").exists)
    }

    func testSwipeLeftOpensAndSwipeRightCloses() {
        mainChat()
        swipeUntil(0.85, 0.1) { self.el("overviewGlance").waitForExistence(timeout: 5) }
        XCTAssertTrue(el("overviewGlance").exists, "the Overview slid in")
        XCTAssertTrue(el("overviewTab-library").exists)
        waitStill(el("overviewClose"))
        XCTAssertLessThan(el("overviewClose").frame.minX, app.windows.firstMatch.frame.width / 3, "fully in")
        shot("a141-swiped-in")
        swipeUntil(0.15, 0.9) { self.el("overviewGlance").waitForNonExistence(timeout: 5) }
        XCTAssertTrue(el("overviewGlance").waitForNonExistence(timeout: 5), "the Overview slid back out")
        XCTAssertTrue(el("projectPill").exists, "on the main chat")
        XCTAssertFalse(el("closeMenu").exists, "the swipe didn't open the menu")
        shot("a141-swiped-out")
    }

    func testButtonOpensAndBackCloses() {
        mainChat()
        el("overviewButton").tap()
        XCTAssertTrue(el("overviewGlance").waitForExistence(timeout: 5))
        el("overviewTab-scheduled").tap()
        XCTAssertTrue(el("schedule-s1").waitForExistence(timeout: 5))
        el("overviewClose").tap()
        XCTAssertTrue(el("overviewGlance").waitForNonExistence(timeout: 5))
        XCTAssertTrue(el("projectPill").exists)
    }
}
