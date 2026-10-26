import XCTest

/// a122: the video player in demo mode ("Wallpaper ideas" has a short clip without sound). The glass controls,
/// play and pause, skipping, speed, loop, full screen and their fading away while it plays.
final class VideoPlayerUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    override func tearDown() {
        XCUIDevice.shared.orientation = .portrait
        super.tearDown()
    }

    // ScreenshotTests' helpers, copied so the files don't depend on each other

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

    private func wait(_ e: XCUIElement, _ format: String, _ arg: String, timeout: Double = 8) -> Bool {
        let x = expectation(for: NSPredicate(format: format, arg), evaluatedWith: e)
        return XCTWaiter.wait(for: [x], timeout: timeout) == .completed
    }

    private func exists(_ e: XCUIElement, _ yes: Bool, timeout: Double = 8) -> Bool {
        let x = expectation(for: NSPredicate(format: yes ? "exists == true" : "exists == false"), evaluatedWith: e)
        return XCTWaiter.wait(for: [x], timeout: timeout) == .completed
    }

    /// the screen changes within 10 s (the clip's bands fade, the time ticks). Read from pixels, not from the time's
    /// label: on CI the accessibility snapshot kept saying 0:00 for 10 s while the recording showed 0:01 and 0:02.
    private func screenMoves() -> Bool {
        let first = XCUIScreen.main.screenshot().pngRepresentation
        for _ in 0..<20 {
            usleep(500_000)
            if XCUIScreen.main.screenshot().pngRepresentation != first { return true }
        }
        return false
    }

    /// the chat's video, opened full screen
    private func openVideo(_ extra: [String] = []) -> XCUIApplication {
        let app = launch(extra)
        let button = app.buttons["menu"]
        XCTAssertTrue(button.waitForExistence(timeout: 20))
        button.tap()
        let pin = el(app, "pin-Wallpaper ideas"), chat = el(app, "chat-Wallpaper ideas")
        XCTAssertTrue(pin.waitForExistence(timeout: 10) || chat.exists)
        let row = pin.exists ? pin : chat
        let bottom = app.windows.firstMatch.frame.height - 110
        for _ in 0..<4 where row.frame.maxY > bottom { app.swipeUp() }
        row.tap()
        XCTAssertTrue(el(app, "chatTitle").waitForExistence(timeout: 10))
        let video = el(app, "video")
        app.swipeDown()
        XCTAssertTrue(video.waitForExistence(timeout: 5))
        video.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.15)).tap()
        XCTAssertTrue(el(app, "videoPlayer").waitForExistence(timeout: 5), "the player opens")
        return app
    }

    func testGlassControls() {
        let app = openVideo(["-keepControls"])
        let play = app.buttons["playPause"]
        XCTAssertTrue(play.waitForExistence(timeout: 5))
        XCTAssertTrue(wait(play, "label == %@", "Pause"), "it plays at once")
        for id in ["videoClose", "skipBack", "skipForward", "mute", "speed", "loop", "rotate", "videoMore", "airplay"] {
            XCTAssertTrue(el(app, id).exists, id)
        }
        XCTAssertTrue(el(app, "scrubber").exists)
        XCTAssertTrue(exists(el(app, "noSound"), true), "the clip has no sound, and says so")
        XCTAssertEqual(el(app, "loop").value as? String, "On", "a 2 s clip loops")
        XCTAssertTrue(el(app, "videoTime").exists)
        XCTAssertTrue(screenMoves(), "the picture and the time move while it plays")
        shot("a122-player")

        play.tap()
        XCTAssertTrue(wait(play, "label == %@", "Play"), "pause")
        let speed = el(app, "speed")
        speed.tap()
        let fast = app.buttons["1.5×"]
        XCTAssertTrue(fast.waitForExistence(timeout: 5), "the speed menu")
        sleep(1)
        shot("a122-player-speed")
        fast.tap()
        XCTAssertTrue(wait(speed, "value == %@", "1.5×"))
        // plays again while it still loops: the 2 s clip at 1.5× would be over before a slow runner looks
        play.tap()
        XCTAssertTrue(wait(play, "label == %@", "Pause"), "plays again")
        el(app, "loop").tap()
        XCTAssertTrue(wait(el(app, "loop"), "value == %@", "Off"))

        el(app, "rotate").tap()
        XCTAssertTrue(wait(el(app, "rotate"), "label == %@", "Exit full screen"), "turned sideways")
        sleep(2)
        shot("a122-player-landscape")
        el(app, "rotate").tap()
        XCTAssertTrue(wait(el(app, "rotate"), "label == %@", "Full screen"), "upright again")
        app.buttons["videoClose"].tap()
        XCTAssertTrue(exists(el(app, "videoPlayer"), false), "closed")
        XCTAssertTrue(el(app, "chatTitle").exists, "back in the chat")
    }

    func testControlsFadeWhilePlayingAndATapBringsThemBack() {
        let app = openVideo()
        let play = app.buttons["playPause"]
        XCTAssertTrue(play.waitForExistence(timeout: 5))
        XCTAssertTrue(exists(play, false, timeout: 10), "the controls fade while it plays")
        el(app, "videoPlayer").tap()
        XCTAssertTrue(play.waitForExistence(timeout: 3), "a tap shows them")
        // swipe down closes, like the photo viewer
        el(app, "videoPlayer").swipeDown()
        XCTAssertTrue(exists(el(app, "videoPlayer"), false), "swipe down closes")
    }
}
