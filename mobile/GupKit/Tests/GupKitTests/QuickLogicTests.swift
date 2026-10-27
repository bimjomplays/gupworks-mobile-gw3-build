import Foundation
import XCTest
#if canImport(GupKit)
@testable import GupKit
#else
@testable import GupWorks3
#endif

/// a142: Quick actions (Away mode, Dillon's game bot, Restart PC) as gw3-phone's /v1/quick answers.
final class QuickLogicTests: XCTestCase {
    override func tearDown() { Demo.args = ProcessInfo.processInfo.arguments }

    func testFixtureDecodesWithTheExactLabels() throws {
        let list: QuickList = try XCTUnwrap(Demo.load("quick"))
        XCTAssertEqual(list.switches.map(\.id), ["away", "game-bot", "restart-pc"])
        XCTAssertEqual(list.switches.map(\.label), ["Away mode", "Dillon's game bot", "Restart PC"])
        XCTAssertEqual(list.switches.map(\.isToggle), [true, true, false])
        XCTAssertEqual(list.switches[1].on, true)
        XCTAssertEqual(list.switches[2].allowed, true)
    }

    func testServerShapeDecodes() throws {
        // what tools/gw3_quick.py sends when a status didn't answer and logind says no
        let json = """
        {"switches": [{"id": "away", "label": "Away mode", "kind": "toggle", "on": null, "detail": "",
          "warning": "gupworks-away.service isn't running", "error": "gw: exit 2"},
          {"id": "restart-pc", "label": "Restart PC", "kind": "button", "allowed": false,
           "reason": "logind CanReboot: no", "error": ""}], "error": "gw away on: exit 1"}
        """
        let list = try JSONDecoder().decode(QuickList.self, from: Data(json.utf8))
        XCTAssertNil(list.switches[0].on)
        XCTAssertEqual(list.switches[0].warning, "gupworks-away.service isn't running")
        XCTAssertEqual(list.switches[1].allowed, false)
        XCTAssertEqual(list.error, "gw away on: exit 1")
        let c = try JSONDecoder().decode(QuickConfirm.self, from: Data(#"{"confirm":"abc","question":"Restart the PC now?","seconds":60}"#.utf8))
        XCTAssertEqual(c.question, "Restart the PC now?")
    }

    @MainActor
    func testDemoTogglesAndRestart() async throws {
        Demo.args = ["-demo"]
        let s = QuickStore(pairing: nil, demo: true)
        await s.refresh()
        XCTAssertEqual(s.state("away")?.on, false)
        await s.set("away", on: true)
        XCTAssertEqual(s.state("away")?.on, true)
        XCTAssertNil(s.errorText("away"))
        XCTAssertTrue(s.busy.isEmpty)
        await s.refresh()  // the demo keeps its state in memory
        XCTAssertEqual(s.state("away")?.on, true)
        let asked = await s.askRestart()
        let c = try XCTUnwrap(asked)
        XCTAssertEqual(c.question, "Restart the PC now?")
        XCTAssertFalse(s.restarting)
        await s.restart(c)
        XCTAssertTrue(s.restarting)
    }

    @MainActor
    func testErrorsStayOnTheirSwitch() async throws {
        Demo.args = ["-demo", "-quickError"]
        let s = QuickStore(pairing: nil, demo: true)
        await s.refresh()
        XCTAssertEqual(s.errorText("game-bot"), "tmux: no server running")
        XCTAssertNil(s.state("game-bot")?.on, "no state guessed when the status didn't answer")
        XCTAssertEqual(s.state("away")?.warning, "gupworks-away.service isn't running")
        XCTAssertEqual(s.state("restart-pc")?.allowed, false)
        await s.set("away", on: true)
        XCTAssertEqual(s.state("away")?.on, false, "a failed switch keeps the PC's state")
        XCTAssertEqual(s.errorText("away"), "Away mode didn't switch: exit 1 (demo)")
        XCTAssertNil(s.tried["game-bot"])
        s.forgetTries()
        XCTAssertNil(s.errorText("away"))
        XCTAssertEqual(s.errorText("game-bot"), "tmux: no server running", "the PC's own error stays")
    }
}
