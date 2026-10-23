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

    func testD1ChatsList() {
        let app = launch()
        XCTAssertTrue(find(app, "Wallpaper ideas").waitForExistence(timeout: 20))
        XCTAssertTrue(find(app, "Lumen Studio website").exists)
        sleep(1)
        shot("d1-chats")
    }

    func testD1Search() {
        let app = launch()
        XCTAssertTrue(find(app, "Wallpaper ideas").waitForExistence(timeout: 20))
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("re")
        XCTAssertTrue(find(app, "Recipe scaler").waitForExistence(timeout: 5))
        XCTAssertFalse(find(app, "Wallpaper ideas").exists)
        sleep(1)
        shot("d1-search")
    }

    func testSettings() {
        let app = launch()
        XCTAssertTrue(find(app, "Wallpaper ideas").waitForExistence(timeout: 20))
        app.buttons["settings"].tap()
        XCTAssertTrue(find(app, "This PC").waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["unpair"].exists)
        sleep(1)
        shot("settings")
    }

    func testPairing() {
        let app = launch(["-unpaired"])
        XCTAssertTrue(find(app, "Pair with your PC").waitForExistence(timeout: 20))
        let field = app.textFields["pairCode"]
        field.tap()
        field.typeText("https://example.com\n")
        XCTAssertTrue(app.descendants(matching: .any)["pairProblem"].waitForExistence(timeout: 5))
        shot("pairing")
    }
}
