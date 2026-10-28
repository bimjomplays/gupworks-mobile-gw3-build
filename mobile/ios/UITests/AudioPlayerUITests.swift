import XCTest

// ci-covers: AudioPlayer.swift MediaViews.swift Audio.swift
/// a157: audio in a chat, in demo mode ("Synth line from a hum": a voice memo you sent, two synth lines in Claude's
/// reply). Play, the speed menu (shared with the video player) and dragging along the waveform, with the system's own
/// touches and sound.
final class AudioPlayerUITests: XCTestCase {
    private let chat = "00000019-1111-4222-8333-000000000019"

    override func setUp() {
        continueAfterFailure = false
    }

    // VideoPlayerUITests' helpers, copied so the files don't depend on each other

    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "-videoSpeed", "1", "-open", chat]  // 1× whatever an earlier test chose
        app.launch()
        return app
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

    /// the screen changes within 10 s (the waveform fills, the time ticks): read from pixels, as a122 learned
    /// that a live Text's accessibility label can stay stale on CI
    private func screenMoves() -> Bool {
        let first = XCUIScreen.main.screenshot().pngRepresentation
        for _ in 0..<20 {
            usleep(500_000)
            if XCUIScreen.main.screenshot().pngRepresentation != first { return true }
        }
        return false
    }

    func testPlaySpeedAndDrag() {
        let app = launch()
        XCTAssertTrue(el(app, "chatTitle").waitForExistence(timeout: 20))
        let play = app.buttons["Play Synth line"]
        XCTAssertTrue(play.waitForExistence(timeout: 10), "Claude's synth line has a player")
        XCTAssertTrue(app.buttons["Play hum-idea.m4a"].exists, "your voice memo has a player")

        // the speed menu: 1.5× is picked and shows on every card
        let speed = app.buttons.matching(identifier: "audio-speed").firstMatch
        XCTAssertEqual(speed.value as? String, "1×")
        let label1x = speed.screenshot().pngRepresentation
        speed.tap()
        let fast = app.buttons["1.5×"]
        XCTAssertTrue(fast.waitForExistence(timeout: 5), "the speed menu")
        sleep(1)
        shot("a157-audio-speed")
        fast.tap()
        XCTAssertTrue(wait(speed, "value == %@", "1.5×"), "1.5× picked")
        let speeds = app.buttons.matching(identifier: "audio-speed")
        for i in 0..<speeds.count {
            XCTAssertEqual(speeds.element(boundBy: i).value as? String, "1.5×", "every card plays at 1.5×")
        }
        // and shows it: the label's pixels changed (an accessibility value can be right while the drawing is stale)
        sleep(1)
        XCTAssertNotEqual(speeds.firstMatch.screenshot().pngRepresentation, label1x, "the label reads 1.5×")

        // play: the button turns to pause and the waveform fills
        play.tap()
        let pause = app.buttons["Pause Synth line"]
        XCTAssertTrue(pause.waitForExistence(timeout: 8), "it plays")
        XCTAssertTrue(screenMoves(), "the waveform and the time move while it plays")
        shot("a157-audio-playing-fast")

        pause.tap()
        XCTAssertTrue(play.waitForExistence(timeout: 5), "paused")

        // a drag to the right along the waveform scrubs (the menu's swipe leaves it alone) and lands where the finger
        // lets go: 90% of the ~7.5 s line is 0:06-0:07
        let wave = app.descendants(matching: .any).matching(identifier: "audio-wave")
            .allElementsBoundByIndex.sorted { $0.frame.minY < $1.frame.minY }
        XCTAssertGreaterThanOrEqual(wave.count, 2)
        let line = wave[1]
        line.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.5))
            .press(forDuration: 0.05, thenDragTo: line.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)))
        let landed = expectation(for: NSPredicate(format: "value BEGINSWITH '0:06' OR value BEGINSWITH '0:07'"),
                                 evaluatedWith: line)
        XCTAssertEqual(XCTWaiter.wait(for: [landed], timeout: 8), .completed, "near the end: \(line.value ?? "")")
        XCTAssertFalse(el(app, "closeMenu").exists, "the menu stayed shut")
        sleep(1)
        shot("a157-audio-dragged")
    }
}
