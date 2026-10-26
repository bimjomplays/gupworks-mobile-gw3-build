import Foundation
import XCTest
#if canImport(GupKit)
@testable import GupKit
#else
@testable import GupWorks3
#endif

// A ```mockups block as gw3-phone sends it (gw3_mockups.as_block, then the older apps' copy marked `fallback`).

final class MockupSetTests: XCTestCase {
    let json = """
    [{"t": "p", "text": "Here they are."},
     {"t": "mockups", "set": {"title": "Notebook look · round 1", "same": "Same contacts in each.",
       "options": [
         {"n": 1, "name": "Ledger", "differs": "Light and plain", "shots": [{"badge": "1", "label": "", "url": "u1"}]},
         {"n": 2, "name": "Paper", "differs": "Warm off-white", "shots": [
           {"badge": "2a", "label": "Contacts", "url": "u2a"}, {"badge": "2b", "label": "Contact page", "url": "u2b"}]},
         {"n": 3, "name": "Night desk", "differs": "Dark with amber", "shots": [{"badge": "3", "label": "", "missing": "c.png"}]}],
       "head": ["", "1 Ledger", "2 Paper", "3 Night desk"],
       "rows": [["Colours", "Light", "Warm", "Dark"], ["Opens", "In a panel", "", "On a page"]]}},
     {"t": "p", "text": "**Mockup set: Notebook look · round 1**", "fallback": true},
     {"t": "media", "items": [{"kind": "image", "url": "u1", "name": "1 · Ledger"}], "fallback": true},
     {"t": "p", "text": "I would pick 2."}]
    """

    func blocks() throws -> [MD] { try JSONDecoder().decode([MD].self, from: Data(json.utf8)) }

    func testDecodesTheSetAndMarksTheOlderAppsCopy() throws {
        let b = try blocks()
        XCTAssertEqual(b.map(\.t), ["p", "mockups", "p", "media", "p"])
        XCTAssertEqual(b.map(\.isFallback), [false, false, true, true, false])
        let s = try XCTUnwrap(b[1].set)
        XCTAssertEqual(s.title, "Notebook look · round 1")
        XCTAssertEqual(s.optionsLine, "3 options")
        XCTAssertEqual(s.options.map(\.n), [1, 2, 3])
        XCTAssertEqual(s.options[1].shots.map(\.badge), ["2a", "2b"])
        XCTAssertEqual(s.options[2].shots[0].missing, "c.png")
    }

    func testPhotosInSetOrderWithTitles() throws {
        let s = try XCTUnwrap(try blocks()[1].set)
        let p = s.photos(scope: "t1/b0/m1")
        XCTAssertEqual(p.map(\.title), ["1 · Ledger", "2a · Paper · Contacts", "2b · Paper · Contact page"])
        XCTAssertEqual(p.map(\.link), ["u1", "u2a", "u2b"])
        XCTAssertEqual(p.map(\.id), ["t1/b0/m1/set/1", "t1/b0/m1/set/2a", "t1/b0/m1/set/2b"])
        XCTAssertEqual(p[2].detail, "Warm off-white")
    }

    func testDifferencesAsAList() throws {
        let s = try XCTUnwrap(try blocks()[1].set)
        XCTAssertEqual(s.differences, [
            MockupDifference(label: "Colours", values: [.init(key: "1", text: "Light"), .init(key: "2", text: "Warm"),
                                                        .init(key: "3", text: "Dark")]),
            MockupDifference(label: "Opens", values: [.init(key: "1", text: "In a panel"), .init(key: "3", text: "On a page")]),
        ])
        XCTAssertEqual(MockupSet.key("12 Night"), "12")
        XCTAssertEqual(MockupSet.key("Night"), "Night")
        XCTAssertEqual(MockupSet(title: "x", options: []).differences, [])
    }

    func testPlainText() throws {
        let s = try XCTUnwrap(try blocks()[1].set)
        XCTAssertEqual(s.plain, """
        Mockup set: Notebook look · round 1

        Same contacts in each.

        1 Ledger: Light and plain

        2 Paper: Warm off-white
        Screens: 2a Contacts, 2b Contact page

        3 Night desk: Dark with amber

        How they differ
        Colours
          1 Light
          2 Warm
          3 Dark
        Opens
          1 In a panel
          3 On a page
        """)
    }
}
