import XCTest

/// Screenshots of the app in demo mode (bundled invented fixtures, no PC needed). Each one is attached to the test
/// result and, when the runner sets SHOTS_DIR (TEST_RUNNER_SHOTS_DIR for xcodebuild), also written there as a PNG.
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

    func testD1ChatsList() {
        let app = launch()
        XCTAssertTrue(app.staticTexts["Wallpaper ideas"].waitForExistence(timeout: 20))
        XCTAssertTrue(app.staticTexts["Lumen Studio website"].exists)
        sleep(1)
        shot("d1-chats")
    }

    func testD1Search() {
        let app = launch()
        XCTAssertTrue(app.staticTexts["Wallpaper ideas"].waitForExistence(timeout: 20))
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("re")
        XCTAssertTrue(app.staticTexts["Recipe scaler"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Wallpaper ideas"].exists)
        sleep(1)
        shot("d1-search")
    }

    func testSettings() {
        let app = launch()
        XCTAssertTrue(app.staticTexts["Wallpaper ideas"].waitForExistence(timeout: 20))
        app.buttons["settings"].tap()
        XCTAssertTrue(app.staticTexts["This PC"].waitForExistence(timeout: 5)
                      || app.staticTexts["THIS PC"].waitForExistence(timeout: 1))
        XCTAssertTrue(app.buttons["unpair"].exists)
        sleep(1)
        shot("settings")
    }

    func testPairing() {
        let app = launch(["-unpaired"])
        XCTAssertTrue(app.staticTexts["Pair with your PC"].waitForExistence(timeout: 20))
        let field = app.textFields["pairCode"]
        field.tap()
        field.typeText("https://example.com\n")
        XCTAssertTrue(app.descendants(matching: .any)["pairProblem"].waitForExistence(timeout: 5))
        shot("pairing")
    }
}
