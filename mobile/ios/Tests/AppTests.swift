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
        XCTAssertEqual(PairLink.parse("https://example.com").problem, .notOurs)
        XCTAssertEqual(PairLink.parse("gupworks3://other?v=1").problem, .notOurs)
        XCTAssertEqual(PairLink.parse(link("https://desktop.example.ts.net", v: "2")).problem, .newerVersion)
        XCTAssertEqual(PairLink.parse(link("https://desktop.example.ts.net") + "&code=x").problem, .notOurs)
    }

    func testOnlyTailnetHttpsAddresses() {
        for bad in ["http://desktop.example.ts.net:10005", "https://example.com", "https://ts.net",
                    "https://desktop.ts.net", "https://user" + "@" + "desktop.example.ts.net",
                    "https://desktop.example.ts.net/path", "https://desktop.example.ts.net/?x=1",
                    "https://desktop.example.ts.net.evil.com"] {
            XCTAssertEqual(PairLink.parse(link(bad)).problem, .badAddress, bad)
        }
    }

    func testCodeShape() {
        XCTAssertEqual(PairLink.parse(link("https://desktop.example.ts.net", code: "short")).problem, .badCode)
        XCTAssertEqual(PairLink.parse(link("https://desktop.example.ts.net", code: code + "!")).problem, .badCode)
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

final class ChatFormatTests: XCTestCase {
    func testClock() {
        XCTAssertEqual(Format.clock(7_000), "0:07")
        XCTAssertEqual(Format.clock(62_000), "1:02")
        XCTAssertEqual(Format.clock(3_723_000), "1:02:03")
        XCTAssertEqual(Format.clock(-5), "0:00")
    }

    func testDuration() {
        XCTAssertEqual(Format.duration(400), "0.4s")
        XCTAssertEqual(Format.duration(12_000), "12s")
        XCTAssertEqual(Format.duration(65_000), "1m 5s")
    }

    func testShortModel() {
        XCTAssertEqual(Format.shortModel("Sonnet 5.5"), "Sonnet")
        XCTAssertEqual(Format.shortModel(""), "")
    }

    func testCardStatsGiveTimeToTheDiff() {
        var b = Block(type: "card")
        b.stats = "2 steps · 4.4s"
        XCTAssertEqual(StepCard.stats(b), "2 steps · 4.4s")
        b.add = 6
        b.del = 2
        XCTAssertEqual(StepCard.stats(b), "2 steps")
        b.stats = "3 steps · 1 failed · 2.4s"
        b.add = nil
        b.del = nil
        XCTAssertEqual(StepCard.stats(b), "3 steps · 1 failed · 2.4s")
    }

    func testSwatchBeforeHexColours() {
        let a = Inline.text("from #b8572a to `x`")
        XCTAssertEqual(String(a.characters), "from \u{25A0}\u{2009}#b8572a to x")
    }
}

final class SSEParserTests: XCTestCase {
    func testEventsKeepalivesAndCRLF() {
        var p = SSEParser()
        let events = p.feed("event: turn\ndata: {\"id\":\"a\"}\n\n: keepalive\n\nevent: status\r\ndata: one\r\ndata: two\r\n\r\ndata: x\n")
        XCTAssertEqual(events, [SSEEvent(name: "turn", data: "{\"id\":\"a\"}"), SSEEvent(name: "status", data: "one\ntwo")])
        XCTAssertEqual(p.feed("\n"), [SSEEvent(name: "message", data: "x")])
    }
}

final class MediaLinkTests: XCTestCase {
    let base = URL(string: "https://desktop.example.ts.net:10005")!

    func testLinks() {
        XCTAssertEqual(MediaLink.url("/v1/media/abc.def", base: base)?.absoluteString,
                       "https://desktop.example.ts.net:10005/v1/media/abc.def")
        XCTAssertNil(MediaLink.url("https://example.com/x.png", base: base))
        XCTAssertNil(MediaLink.url(nil, base: base))
        let demo = MediaLink.url("demo:media/dusk.png", base: nil)
        XCTAssertNotNil(demo)
        XCTAssertTrue(demo?.isFileURL ?? false)
    }
}

@MainActor
final class ChatStoreTests: XCTestCase {
    let gallery = "00000009-1111-4222-8333-000000000009"

    func testDemoChatsDecode() throws {
        for id in ["00000001", "00000008", "00000009", "00000066"].map({ "\($0)-1111-4222-8333-0000\($0)" }) {
            let f: ChatFixture = try XCTUnwrap(Demo.load(id, in: "fixtures/chats"), id)
            XCTAssertEqual(f.header.id, id)
            XCTAssertFalse(f.turns.turns.isEmpty)
            // every card in the turns opens to its own screen
            for t in f.turns.turns {
                for b in t.blocks where b.type == "card" {
                    XCTAssertNotNil(f.cards[b.id ?? ""], "\(id) \(b.id ?? "")")
                }
            }
        }
    }

    func testDemoStoreShiftsTimes() async throws {
        let s = ChatStore(id: "00000001-1111-4222-8333-000000000001", pairing: nil, demo: true)
        await s.run()
        let live = try XCTUnwrap(s.turns.last?.handle?.since)
        let ago = Date().timeIntervalSince1970 * 1000 - live
        XCTAssertTrue(ago > 0 && ago < 120_000, "the live turn started \(ago) ms ago")
        let card = try await s.card("toolu_demo3a110004")
        XCTAssertEqual(card.state, "running")
    }

    func testStreamEventsMergeTurns() async throws {
        let s = ChatStore(id: gallery, pairing: nil, demo: true)
        await s.run()
        let count = s.turns.count
        var last = try XCTUnwrap(s.turns.last)
        last.blocks.append(Block(type: "error", text: "API error"))
        last.rev = "changed"
        let data = String(decoding: try JSONEncoder().encode(last), as: UTF8.self)
        s.handle(SSEEvent(name: "turn", data: data))
        XCTAssertEqual(s.turns.count, count)
        XCTAssertEqual(s.turns.last?.rev, "changed")

        var newer = last
        newer.id = "zz-new"
        newer.start += 1000
        s.handle(SSEEvent(name: "turn", data: String(decoding: try JSONEncoder().encode(newer), as: UTF8.self)))
        XCTAssertEqual(s.turns.count, count + 1)
        XCTAssertEqual(s.turns.last?.id, "zz-new")

        var older = last
        older.id = "aa-old"
        older.start = 0
        s.upsert([older])
        XCTAssertEqual(s.turns.first?.id, "aa-old")

        s.handle(SSEEvent(name: "status", data: "{\"state\":\"working\",\"ts\":1,\"live\":true,\"running\":true}"))
        XCTAssertEqual(s.status?.state, "working")
        s.handle(SSEEvent(name: "gone", data: "{}"))
        XCTAssertTrue(s.gone)
    }
}

private extension Result {
    var problem: Failure? {
        if case .failure(let f) = self { return f }
        return nil
    }
}
