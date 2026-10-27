import Foundation
import XCTest
#if canImport(GupKit)
@testable import GupKit
#else
@testable import GupWorks3
#endif

/// a151: the PC part of Quick actions (health, media and volume, Open on the PC, Discord) as gw3-phone's /v1/quick/pc answers.
final class QuickPcLogicTests: XCTestCase {
    override func tearDown() { Demo.args = ProcessInfo.processInfo.arguments }

    func testFixtureDecodes() throws {
        let s: QuickPcState = try XCTUnwrap(Demo.load("quick-pc"))
        XCTAssertEqual(s.health?.line?.map(\.id), ["cpu", "gpu", "disk", "services"])
        XCTAssertEqual(s.health?.sections?.map(\.title), ["Temperatures", "Drives", "GupWorks services"])
        XCTAssertEqual(s.media?.player?.nowPlaying, "Northern Lights — Aurora Hall")
        XCTAssertEqual(s.media?.volume?.detail, "Desk Speakers · 42%")
        XCTAssertEqual(s.discord?.inCall, true)
        XCTAssertEqual(s.browsers?.list.map(\.label),
                       ["Chrome · Your Chrome", "Chrome · Work", "Chrome · Studio site", "Firefox"])
    }

    func testBrokenPartsDecode() throws {
        // what tools/gw3_pc.everything() sends when parts broke or didn't answer
        let json = """
        {"health": {"error": "health failed (boom)"}, "media": {"player": null, "players": 0, "volume": null,
          "errors": {"volume": "Could not connect to PipeWire"}},
         "discord": {"running": false, "inCall": null, "mic": null, "detail": "", "how": "PipeWire", "error": "pw-dump: exit 1"},
         "browsers": {"error": "browsers didn't answer"}}
        """
        let s = try JSONDecoder().decode(QuickPcState.self, from: Data(json.utf8))
        XCTAssertEqual(s.health?.problems, ["health failed (boom)"])
        XCTAssertNil(s.health?.line)
        XCTAssertNil(s.media?.player)
        XCTAssertEqual(s.media?.volumeError, "Could not connect to PipeWire")
        XCTAssertNil(s.media?.playerError)
        XCTAssertNil(s.discord?.inCall)
        XCTAssertEqual(s.browsers?.list, [])
        let r = try JSONDecoder().decode(QuickMediaReply.self, from: Data(#"{"error": "That player is gone", "media": {"player": null}}"#.utf8))
        XCTAssertEqual(r.error, "That player is gone")
    }

    func testVolumeBodyLeavesOutWhatIsntSent() throws {
        let mute = String(decoding: try JSONEncoder().encode(QuickVolumeBody(level: nil, muted: true)), as: UTF8.self)
        XCTAssertEqual(mute, #"{"muted":true}"#)
        let level = String(decoding: try JSONEncoder().encode(QuickVolumeBody(level: 0.7, muted: nil)), as: UTF8.self)
        XCTAssertEqual(level, #"{"level":0.7}"#)
    }

    func testLinksAsThePcChecksThem() {
        XCTAssertNil(QuickPcText.linkProblem("https://example.com/a?b=c"))
        XCTAssertNil(QuickPcText.linkProblem("  http://example.org  "))
        XCTAssertEqual(QuickPcText.linkProblem(""), "Paste a link first.")
        XCTAssertEqual(QuickPcText.linkProblem("file:///etc/passwd"), "Only http:// and https:// links open on the PC.")
        XCTAssertEqual(QuickPcText.linkProblem("javascript:alert(1)"), "Only http:// and https:// links open on the PC.")
        XCTAssertEqual(QuickPcText.linkProblem("https://"), "Only http:// and https:// links open on the PC.")
        XCTAssertEqual(QuickPcText.linkProblem("https://a.com b"), "That isn't a single link (spaces or control characters).")
        XCTAssertEqual(QuickPcText.firstLink(in: "Look at this (https://example.com/x)!"), "https://example.com/x")
        XCTAssertEqual(QuickPcText.firstLink(in: " not a link "), "not a link")
        XCTAssertTrue(QuickPcText.readable("No route GET /v1/quick/pc").contains("older"))
    }

    @MainActor
    func testDemoMediaVolumeAndOpen() async throws {
        Demo.args = ["-demo"]
        let s = QuickPcStore(pairing: nil, demo: true)
        await s.refresh()
        XCTAssertEqual(s.media?.player?.playing, true)
        await s.mediaAction("play-pause")
        XCTAssertEqual(s.media?.player?.status, "Paused")
        XCTAssertTrue(s.busy.isEmpty)
        await s.setVolume(0.7)
        XCTAssertEqual(s.media?.volume?.detail, "Desk Speakers · 70%")
        await s.setMuted(true)
        XCTAssertEqual(s.media?.volume?.detail, "Desk Speakers · Muted")

        XCTAssertEqual(s.browser, "chrome:Default", "the PC's last pick")
        s.picked = "firefox"
        let refused = await s.open("file:///etc/passwd")
        XCTAssertFalse(refused)
        XCTAssertEqual(s.errorText("open"), "Only http:// and https:// links open on the PC.")
        let opened = await s.open("see https://example.com")
        XCTAssertTrue(opened)
        XCTAssertNil(s.errorText("open"))
        XCTAssertEqual(s.openNote, "Opened in Firefox")
        XCTAssertEqual(s.browsers?.last, "firefox")
        s.forgetTries()
        XCTAssertNil(s.openNote)
        XCTAssertEqual(s.browser, "firefox", "remembered as the PC does")
    }

    @MainActor
    func testDemoErrorsShowOnTheirRows() async throws {
        Demo.args = ["-demo", "-quickError"]
        let s = QuickPcStore(pairing: nil, demo: true)
        await s.refresh()
        XCTAssertEqual(s.health?.problems, ["nvidia-smi: couldn't talk to the driver"])
        XCTAssertEqual(s.errorText("volume"), "Could not connect to PipeWire")
        XCTAssertNil(s.errorText("media"), "nothing playing is no error")
        XCTAssertNil(s.media?.player)
        XCTAssertEqual(s.errorText("discord"), "pw-dump: can't connect to PipeWire")
        XCTAssertNil(s.discord?.inCall)
        let opened = await s.open("https://example.com")
        XCTAssertFalse(opened)
        XCTAssertEqual(s.errorText("open"), "google-chrome-stable: not responding (demo)")
    }
}
