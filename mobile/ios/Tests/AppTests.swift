import XCTest
@testable import GupWorks3

final class PairLinkTests: XCTestCase {
    let code = String(repeating: "aB3-_", count: 9)  // 45 base64url characters

    func link(_ url: String, code: String? = nil, v: String = "1") -> String {
        var c = URLComponents()
        c.scheme = "gupworks3"
        c.host = "pair"
        c.queryItems = [URLQueryItem(name: "v", value: v), URLQueryItem(name: "url", value: url),
                        URLQueryItem(name: "code", value: code ?? self.code)]
        return c.string!
    }

    func testGoodLink() throws {
        let parsed = try PairLink.parse(link("https://desktop.example.ts.net:10005")).get()
        XCTAssertEqual(parsed.baseURL.absoluteString, "https://desktop.example.ts.net:10005")
        XCTAssertEqual(parsed.code, code)
    }

    func testRejectsOtherLinks() {
        XCTAssertEqual(PairLink.parse("https://example.com").failure, .notOurs)
        XCTAssertEqual(PairLink.parse("gupworks3://other?v=1").failure, .notOurs)
        XCTAssertEqual(PairLink.parse(link("https://desktop.example.ts.net", v: "2")).failure, .newerVersion)
        XCTAssertEqual(PairLink.parse(link("https://desktop.example.ts.net") + "&code=x").failure, .notOurs)
    }

    func testOnlyTailnetHttpsAddresses() {
        for bad in ["http://desktop.example.ts.net:10005", "https://example.com", "https://ts.net",
                    "https://desktop.ts.net", "https://user" + "@" + "desktop.example.ts.net",
                    "https://desktop.example.ts.net/path", "https://desktop.example.ts.net/?x=1",
                    "https://desktop.example.ts.net.evil.com"] {
            XCTAssertEqual(PairLink.parse(link(bad)).failure, .badAddress, bad)
        }
    }

    func testCodeShape() {
        XCTAssertEqual(PairLink.parse(link("https://desktop.example.ts.net", code: "short")).failure, .badCode)
        XCTAssertEqual(PairLink.parse(link("https://desktop.example.ts.net", code: code + "!")).failure, .badCode)
    }
}

final class FormatTests: XCTestCase {
    var cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()
    let en = Locale(identifier: "en_US")
    let now = Date(timeIntervalSince1970: 1_792_000_000)  // Oct 14 2026, 17:46 UTC

    func ms(_ secondsAgo: Double) -> Double { (now.timeIntervalSince1970 - secondsAgo) * 1000 }

    func testTimes() {
        XCTAssertEqual(Format.time(ms(20), now: now, calendar: cal, locale: en), "now")
        XCTAssertEqual(Format.time(ms(86_400), now: now, calendar: cal, locale: en), "Yesterday")
        XCTAssertEqual(Format.time(ms(86_400 * 5), now: now, calendar: cal, locale: en), "Oct 9")
        XCTAssertEqual(Format.time(0, now: now, calendar: cal, locale: en), "")
    }

    func testPlural() {
        XCTAssertEqual(Format.plural(1, "thread"), "1 thread")
        XCTAssertEqual(Format.plural(2, "thread"), "2 threads")
    }
}

final class FixtureTests: XCTestCase {
    func testDemoFixturesDecode() throws {
        let home: Home = try XCTUnwrap(Demo.load("home"))
        XCTAssertFalse(home.projects.isEmpty)
        XCTAssertFalse(home.chats.isEmpty)
        let hello: Hello = try XCTUnwrap(Demo.load("hello"))
        XCTAssertEqual(hello.app, "gw3-phone")
    }
}

private extension Result {
    var failure: Failure? {
        if case .failure(let f) = self { return f }
        return nil
    }
}
