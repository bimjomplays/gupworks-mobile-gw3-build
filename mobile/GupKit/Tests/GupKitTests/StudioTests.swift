import Foundation
import XCTest
#if canImport(GupKit)
@testable import GupKit
#else
@testable import GupWorks3
#endif

// YouTube Studio on the phone (a180): the bridge's answers read into the models, the demo's fixtures, and what the
// script's selection bar sends the video chat.

final class StudioModelTests: XCTestCase {
    func decode<T: Decodable>(_ t: T.Type, _ url: URL) throws -> T {
        do {
            return try JSONDecoder().decode(T.self, from: Data(contentsOf: url))
        } catch {
            XCTFail("\(url.lastPathComponent): \(error)")
            throw error
        }
    }

    /// STUDIO_DUMP=<folder> checks answers dumped from a real gw3-phone (made-up test channel) too
    func testDumpedAnswers() throws {
        guard let dir = ProcessInfo.processInfo.environment["STUDIO_DUMP"] else { throw XCTSkip("no STUDIO_DUMP") }
        let d = URL(fileURLWithPath: dir)
        let home = try decode(StudioHome.self, d.appendingPathComponent("home.json"))
        XCTAssertEqual(home.stages.count, 8)
        let ch = try decode(StudioChannel.self, d.appendingPathComponent("channel.json"))
        XCTAssertEqual(ch.row.name, "Studio Test")
        _ = try decode(StudioOverview.self, d.appendingPathComponent("overview.json"))
        _ = try decode(StudioBrief.self, d.appendingPathComponent("brief.json"))
        let r = try decode(StudioResearch.self, d.appendingPathComponent("research.json"))
        XCTAssertNotNil(r.items.media.first?.fileUrl)
        let s = try decode(StudioScript.self, d.appendingPathComponent("script.json"))
        XCTAssertEqual(s.pending.count, 1)
        _ = try decode(StudioVoice.self, d.appendingPathComponent("voice.json"))
        _ = try decode(StudioVisuals.self, d.appendingPathComponent("visuals.json"))
        _ = try decode(StudioFinish.self, d.appendingPathComponent("finish.json"))
        _ = try decode(StudioNotes.self, d.appendingPathComponent("notes.json"))
    }

    func testDemoFixturesRead() throws {
        let home: StudioHome? = Demo.load("home", in: "fixtures/studio")
        let h = try XCTUnwrap(home)
        XCTAssertFalse(h.needs.isEmpty)
        for c in h.channels {
            let ch: StudioChannel? = Demo.load(c.projectId, in: "fixtures/studio")
            let channel = try XCTUnwrap(ch, c.projectId)
            for v in channel.videos + channel.shortsList {
                let folder = "fixtures/studio/\(c.projectId)/\(v.id)"
                guard Demo.file("overview", ext: "json", in: folder) != nil else { continue }
                let o: StudioOverview? = Demo.load("overview", in: folder)
                XCTAssertNotNil(o, folder)
                func check<T: Decodable>(_ name: String, _ t: T.Type) {
                    guard Demo.file(name, ext: "json", in: folder) != nil else { return }
                    let x: T? = Demo.load(name, in: folder)
                    XCTAssertNotNil(x, "\(folder)/\(name).json")
                }
                check("brief", StudioBrief.self)
                check("research", StudioResearch.self)
                check("script", StudioScript.self)
                check("voice", StudioVoice.self)
                check("visuals", StudioVisuals.self)
                check("finish", StudioFinish.self)
                check("speak", StudioSpeech.self)
            }
        }
        let demoHome: Home? = Demo.load("home")
        XCTAssertEqual(demoHome?.studioNeeds?.first?.options.count, 2)
    }

    func testScriptAsksTheChatInTheDesktopsWords() {
        let p = StudioVideoStore.scriptAsk("punchier", ids: ["c6"], text: "His hand shook")
        XCTAssertTrue(p.hasPrefix("Make this part of the script punchier (script line c6): \"His hand shook\""))
        XCTAssertTrue(p.contains("script_change"))
        let w = StudioVideoStore.scriptAsk("why", ids: ["c6", "c7"], text: "x")
        XCTAssertTrue(w.hasPrefix("Why is this part of the script written this way (script lines c6, c7)?"))
        XCTAssertFalse(w.contains("script_change"))
    }

    func testStudioValueEncodes() throws {
        let b: [String: StudioValue] = ["line": .string("c1"), "take": .null, "n": .int(2), "sel": .object(["a": .bool(true)])]
        let o = try JSONSerialization.jsonObject(with: JSONEncoder().encode(b)) as? [String: Any]
        XCTAssertEqual(o?["line"] as? String, "c1")
        XCTAssertTrue(o?["take"] is NSNull)
        XCTAssertEqual((o?["sel"] as? [String: Any])?["a"] as? Bool, true)
    }
}
