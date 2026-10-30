import XCTest
import UIKit
@testable import GupWorks3

/// a180: YouTube Studio on the phone, in demo mode (the invented Night Stories channel in fixtures/studio), one test
/// per mockup in docs/studio-phone-mockups (01-14). The pictures are named after the mockups they match.
@MainActor
final class StudioScreenTests: XCTestCase {
    private nonisolated(unsafe) var started = Date()
    private let chan = "night-stories"
    private let videoChat = "00000091-3333-4222-8333-000000000091"

    override nonisolated func setUp() {
        started = Date()
        continueAfterFailure = false
    }

    override nonisolated func tearDown() {
        MainActor.assumeIsolated {
            if let run = testRun, run.failureCount > 0, let app = App.current {
                let name = name.components(separatedBy: " ").last?.trimmingCharacters(in: CharacterSet(charactersIn: "]")) ?? "test"
                app.shot("fail-\(name)")
                print("SCREEN at the failure of \(name):\n\(app.debugDescription)")
            }
            App.current?.close()
            Timing.report(name, Date().timeIntervalSince(started))
        }
    }

    private func sleep(_ seconds: UInt32) { spin(Double(seconds)) }

    private func shot(_ name: String) { App.current?.shot(name) }

    private func find(_ app: App, _ text: String) -> Element {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS[c] %@", text)).firstMatch
    }

    private func el(_ app: App, _ id: String) -> Element {
        app.descendants(matching: .any)[id].firstMatch
    }

    /// Studio opened at a channel, a video or one of its stages (`-studio pid[/vid[/stage]]`)
    private func studio(_ at: String? = nil, _ extra: [String] = []) -> App {
        App(["-place", "studio"] + (at.map { ["-studio", $0] } ?? []) + extra, test: self)
    }

    /// scrolls up until the element is on screen (or gives up)
    private func reveal(_ app: App, _ e: Element) {
        let bottom = app.windows.firstMatch.frame.height - 120
        for _ in 0..<6 where !e.exists || e.frame.maxY > bottom { app.swipeUp() }
    }

    // MARK: 01-03 channels, a channel, a video

    func testS01Channels() {
        let app = studio()
        let card = el(app, "channel-\(chan)")
        XCTAssertTrue(card.waitForExistence(timeout: 20))
        XCTAssertTrue(find(app, "Draft of shot 6 is ready").exists, "the channel card shows the question that needs you")
        XCTAssertTrue(el(app, "newChannel").exists)
        sleep(1)
        shot("s01-channels")
        card.tap()
        XCTAssertTrue(el(app, "video-lantern").waitForExistence(timeout: 10))
    }

    func testS02ChannelAndStyleGuide() {
        let app = studio(chan)
        XCTAssertTrue(el(app, "video-lantern").waitForExistence(timeout: 20))
        XCTAssertTrue(el(app, "newVideo").exists)
        sleep(1)
        shot("s02-channel")
        el(app, "tab-Style guide").tap()
        XCTAssertTrue(el(app, "styleGuide").waitForExistence(timeout: 5))
        sleep(1)
        shot("s02-style-guide")
        el(app, "tab-Videos").tap()
        el(app, "newVideo").tap()
        XCTAssertTrue(el(app, "createVideo").waitForExistence(timeout: 5))
        sleep(1)
        shot("s02-new-video")
    }

    func testS03VideoOverview() {
        let app = studio("\(chan)/lantern")
        XCTAssertTrue(el(app, "needsYou").waitForExistence(timeout: 20), "the question sits at the top of the video")
        XCTAssertTrue(el(app, "open-brief").exists)
        XCTAssertTrue(el(app, "open-finish").exists || find(app, "Final cut").exists)
        sleep(1)
        shot("s03-video")
        el(app, "open-brief").tap()
        XCTAssertTrue(el(app, "brief-topic").waitForExistence(timeout: 10))
        sleep(1)
        shot("s04-brief")
    }

    // MARK: 05-06 research

    func testS05ResearchFacts() {
        let app = studio("\(chan)/lantern/research")
        let fact = el(app, "fact-f1")
        XCTAssertTrue(fact.waitForExistence(timeout: 20))
        fact.tap()
        XCTAssertTrue(el(app, "pin-f1").waitForExistence(timeout: 5))
        XCTAssertTrue(el(app, "dig-f1").exists)
        sleep(1)
        shot("s05-research-facts")
    }

    func testS06ResearchMedia() {
        let app = studio("\(chan)/lantern/research", ["-media"])
        XCTAssertTrue(el(app, "media-m1").waitForExistence(timeout: 20))
        XCTAssertTrue(el(app, "rights-all").exists || el(app, "rights-free").exists)
        sleep(1)
        shot("s06-research-media")
    }

    // MARK: 07-09 script, a change, listen

    func testS07ScriptSelectAndChange() {
        let app = studio("\(chan)/lantern/script")
        let line = el(app, "line-c3")
        XCTAssertTrue(line.waitForExistence(timeout: 20))
        line.tap()
        XCTAssertTrue(el(app, "selectionBar").waitForExistence(timeout: 5), "a picked line shows what to ask")
        sleep(1)
        shot("s07-script")
        let change = el(app, "change-x1")
        reveal(app, change)
        XCTAssertTrue(change.exists, "the chat's waiting rewrite shows on the script")
        sleep(1)
        shot("s08-script-change")
        app.buttons["accept-x1"].tap()
        XCTAssertTrue(change.waitForNonExistence(timeout: 5))
    }

    func testS09Listen() {
        let app = studio("\(chan)/lantern/script", ["-listen"])
        XCTAssertTrue(el(app, "listenPlayer").waitForExistence(timeout: 20))
        let speed = app.buttons["listenSpeed"]
        XCTAssertTrue(speed.exists)
        let before = speed.label
        speed.tap()
        XCTAssertTrue(poll(3) { speed.label != before }, "the speed button steps on")
        sleep(1)
        shot("s09-listen")
    }

    // MARK: 10-11 voice

    func testS10VoiceAndRedo() {
        let app = studio("\(chan)/lantern/voice")
        XCTAssertTrue(el(app, "credits").waitForExistence(timeout: 20))
        XCTAssertTrue(el(app, "voice-c1").exists)
        sleep(1)
        shot("s10-voice")
        app.close()
        let redo = studio("\(chan)/lantern/voice", ["-redo"])
        XCTAssertTrue(el(redo, "redoDirection").waitForExistence(timeout: 20))
        sleep(1)
        shot("s11-voice-redo")
    }

    // MARK: 12-13 visuals, final cut

    func testS12Visuals() {
        let app = studio("\(chan)/lantern/visuals")
        XCTAssertTrue(el(app, "renderCard").waitForExistence(timeout: 20))
        XCTAssertTrue(el(app, "shot-sh6").exists || find(app, "shot 6").exists)
        sleep(1)
        shot("s12-visuals")
    }

    func testS13FinalCut() {
        let app = studio("\(chan)/lantern/finish")
        XCTAssertTrue(el(app, "playFinal").waitForExistence(timeout: 20))
        XCTAssertTrue(el(app, "noteAt").exists)
        reveal(app, el(app, "finalChecks"))
        XCTAssertTrue(el(app, "finalNotes").exists)
        sleep(1)
        shot("s13-final-cut")
    }

    // MARK: 14 the video chat

    func testS14VideoChat() {
        let app = App(["-open", videoChat], test: self)
        XCTAssertTrue(el(app, "studioPill").waitForExistence(timeout: 20))
        XCTAssertTrue(find(app, "Video chat").exists)
        XCTAssertTrue(el(app, "selectionChip").waitForExistence(timeout: 10), "the selection rides with the next message")
        XCTAssertTrue(find(app, "line c3 selected").exists)
        XCTAssertTrue(el(app, "chatChange-x1").waitForExistence(timeout: 10), "the rewrite shows as a card")
        XCTAssertTrue(el(app, "job-a12").exists, "the long job shows")
        sleep(1)
        shot("s14-video-chat")
    }
}
