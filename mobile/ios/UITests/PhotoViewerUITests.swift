import XCTest

// ci-covers: PhotoViewer.swift MediaViews.swift
/// a122: the photo viewer in demo mode. Chat 16 ("Paint colours for the flat") has 30 pictures in order: your one,
/// Claude's one, your three, Claude's three, then your twelve, four and six.
final class PhotoViewerUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    // the helpers below are ScreenshotTests' own (kept as copies so the two files don't depend on each other)

    private func launch(_ extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-demo"] + extra
        app.launch()
        return app
    }

    private func find(_ app: XCUIApplication, _ text: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS[c] %@", text)).firstMatch
    }

    private func el(_ app: XCUIApplication, _ id: String) -> XCUIElement {
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

    private func chat(_ n: Int) -> String { String(format: "%08d-1111-4222-8333-%012d", n, n) }

    private func openChat(_ id: String, waitFor text: String) -> XCUIApplication {
        let app = launch(["-open", id])
        XCTAssertTrue(app.descendants(matching: .any)["chatTitle"].waitForExistence(timeout: 20))
        XCTAssertTrue(find(app, text).waitForExistence(timeout: 10), text)
        return app
    }

    private func scrollUp(_ app: XCUIApplication, until e: XCUIElement) {
        let screen = app.windows.firstMatch.frame
        for _ in 0..<20 {
            if e.exists, e.frame.minY > screen.height * 0.5, e.frame.maxY < screen.height * 0.8 { return }
            let down = e.exists && e.frame.minY > screen.height * 0.8
            let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.6, dy: down ? 0.6 : 0.35))
            let to = app.coordinate(withNormalizedOffset: CGVector(dx: 0.6, dy: down ? 0.45 : 0.6))
            from.press(forDuration: 0.05, thenDragTo: to, withVelocity: .slow, thenHoldForDuration: 0.2)
        }
    }

    private func wait(_ e: XCUIElement, _ format: String, _ arg: String) -> Bool {
        let x = expectation(for: NSPredicate(format: format, arg), evaluatedWith: e)
        return XCTWaiter.wait(for: [x], timeout: 6) == .completed
    }

    private func counts(_ app: XCUIApplication, _ text: String) -> Bool {
        wait(el(app, "photoCounter"), "label == %@", text)
    }

    private func zoom(_ page: XCUIElement, _ value: String) -> Bool {
        wait(page, "value == %@", value)
    }

    private func gone(_ e: XCUIElement) -> Bool {
        let x = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: e)
        return XCTWaiter.wait(for: [x], timeout: 6) == .completed
    }

    /// Your photo opens among all the chat's photos: swipe left and right, double-tap and pinch zoom, swipe down
    /// closes.
    func testSwipeZoomAndClose() {
        let six = "Here are six photos of the living room"
        let app = openChat(chat(16), waitFor: six)
        let pictures = app.buttons.matching(identifier: "yourPicture")
        XCTAssertGreaterThanOrEqual(pictures.count, 6)
        // the six-photo message's second photo: the chat's 26th of 30
        pictures.element(boundBy: pictures.count - 5).tap()
        let viewer = el(app, "photoViewer")
        XCTAssertTrue(viewer.waitForExistence(timeout: 5), "the viewer opens")
        XCTAssertTrue(counts(app, "26 of 30"), el(app, "photoCounter").label)
        XCTAssertTrue(app.buttons["photoClose"].exists)
        XCTAssertTrue(app.buttons["photoShare"].exists)
        sleep(1)
        shot("a122-photo-viewer")

        let page = el(app, "photoPage")
        XCTAssertEqual(page.value as? String, "fit")
        page.swipeLeft()
        XCTAssertTrue(counts(app, "27 of 30"), "swipe left: the next photo")
        page.swipeRight()
        XCTAssertTrue(counts(app, "26 of 30"))
        page.swipeRight()
        XCTAssertTrue(counts(app, "25 of 30"), "swipe right: the one before, from the message above")

        page.doubleTap()
        XCTAssertTrue(zoom(page, "zoomed"), "double-tap zooms in")
        sleep(1)
        shot("a122-photo-zoomed")
        page.doubleTap()
        XCTAssertTrue(zoom(page, "fit"), "double-tap again: back to fit")
        page.pinch(withScale: 2.5, velocity: 2)
        XCTAssertTrue(zoom(page, "zoomed"), "a pinch zooms")
        page.doubleTap()
        XCTAssertTrue(zoom(page, "fit"))

        page.swipeDown()
        XCTAssertTrue(gone(viewer), "swipe down closes")
        XCTAssertTrue(find(app, six).exists, "back in the chat")
    }

    /// a131 diagnostic (to be dropped): the whole of testSwipeZoomAndClose from a cold launch, ten times; each step
    /// that doesn't show its result prints the viewer's gesture log
    func testZDiagFullSequence() {
        continueAfterFailure = true
        var bad: [String] = []
        for i in 1...10 {
            let app = openChat(chat(16), waitFor: "Here are six photos of the living room")
            let pictures = app.buttons.matching(identifier: "yourPicture")
            pictures.element(boundBy: pictures.count - 5).tap()
            let viewer = el(app, "photoViewer")
            _ = viewer.waitForExistence(timeout: 5)
            let page = el(app, "photoPage")
            func step(_ name: String, _ ok: Bool) {
                let line = "a131 diag \(i) \(name): \(ok ? "ok" : "FAILED") value=\(page.value as? String ?? "?") counter=\(el(app, "photoCounter").label) log=\(page.label)"
                print(line)
                if !ok { bad.append(line) }
            }
            page.swipeLeft()
            step("swipe left", counts(app, "27 of 30"))
            page.swipeRight()
            step("swipe right", counts(app, "26 of 30"))
            page.swipeRight()
            step("swipe right 2", counts(app, "25 of 30"))
            page.doubleTap()
            step("double tap", zoom(page, "zoomed"))
            sleep(1)
            page.doubleTap()
            step("double tap out", zoom(page, "fit"))
            page.pinch(withScale: 2.5, velocity: 2)
            step("pinch", zoom(page, "zoomed"))
            page.doubleTap()
            step("double tap out 2", zoom(page, "fit"))
            page.swipeDown()
            let ok = gone(viewer)
            print("a131 diag \(i) swipe down: \(ok ? "ok" : "FAILED") log=\(ok ? "" : page.label)")
            if !ok { bad.append("\(i) swipe down: \(page.label)") }
        }
        XCTAssertEqual(bad, [], "steps that didn't show their result")
    }

    /// Claude's picture opens in the same gallery as yours: the chat's second picture, with your first one before it.
    func testClaudesPictureInTheSameGallery() {
        let app = openChat(chat(16), waitFor: "Here are six photos of the living room")
        let claudes = app.buttons.matching(identifier: "picture").firstMatch
        scrollUp(app, until: claudes)
        XCTAssertTrue(claudes.exists, "Claude's first picture")
        claudes.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2)).tap()
        let viewer = el(app, "photoViewer")
        XCTAssertTrue(viewer.waitForExistence(timeout: 5))
        XCTAssertTrue(counts(app, "2 of 30"), el(app, "photoCounter").label)
        el(app, "photoPage").swipeRight()
        XCTAssertTrue(counts(app, "1 of 30"), "your photo before it")
        app.buttons["photoClose"].tap()
        XCTAssertTrue(gone(viewer), "close shuts it")
    }
}
