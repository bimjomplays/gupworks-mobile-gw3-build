import Foundation
import XCTest
#if canImport(GupKit)
@testable import GupKit
#else
@testable import GupWorks3
#endif

/// a230: the needs-you card deck's rules (docs/needs-phone-mockups/round1 Option 4; the desktop's src/NeedsQueue).
final class NeedsDeckTests: XCTestCase {
    let now = 1_800_000_000_000.0
    let min = 60_000.0

    func item(_ key: String, _ kind: String = "ask", since: Double, project: String? = "p", source: String = "project",
              options: [String] = ["Now", "Later"], work: String? = nil) -> NeedItem {
        NeedItem(key: key, kind: kind, source: source, projectId: project, askId: nil, chatId: "c", name: "N", title: key,
                 question: "Q?", summary: "S", body: nil,
                 options: options.map { .init(label: $0, detail: "d", n: nil) }, recommended: options.isEmpty ? -1 : 0,
                 other: kind != "permission" && kind != "memory" && kind != "open", otherChoice: nil, since: since, sig: nil,
                 work: work, workTitle: nil, pictures: nil)
    }

    func state(_ items: [NeedItem], parked: [String] = [], snoozed: [String: Double] = [:],
               dismissed: [String: Double] = [:]) -> NeedsState {
        NeedsState(items: items, parked: parked.map { .init(projectId: $0, name: $0.capitalized) }, snoozed: snoozed,
                   dismissed: dismissed)
    }

    func testOldestFirstOverEverySource() {
        let s = state([item("b", since: now - 5 * min), item("a", since: now - 12 * min),
                       item("c", "permission", since: now - 8 * min, project: nil, source: "chat")])
        let deck = NeedsDeck(s, now: now)
        XCTAssertEqual(deck.waiting.map(\.key), ["a", "c", "b"])
        XCTAssertEqual(deck.position(0), "1 of 3")
        XCTAssertTrue(deck.shown)
    }

    func testSnoozeHidesUntilItsTimeAndDismissWhileNotNewer() {
        let s = state([item("a", since: now - 3 * min), item("b", since: now - 2 * min), item("c", since: now - min)],
                      snoozed: ["a": now + 10], dismissed: ["b": now - 2 * min, "c": now - 5 * min])
        XCTAssertEqual(NeedsDeck(s, now: now).waiting.map(\.key), ["c"], "c waits again since it was dismissed")
        XCTAssertEqual(NeedsDeck(s, now: now + 10).waiting.map(\.key), ["a", "c"], "the snooze ran out: back in its place")
    }

    func testDroppedLeavesAtOnce() {
        let s = state([item("a", since: now - 3 * min), item("b", since: now - 2 * min)])
        XCTAssertEqual(NeedsDeck(s, now: now, dropped: ["a"]).waiting.map(\.key), ["b"])
    }

    func testParkedProjectsAreCountedNotShown() {
        let s = state([item("a", since: now - 3 * min, project: "trip"), item("b", since: now - 2 * min, project: "trip"),
                       item("c", since: now - min, project: "home"),
                       item("d", "open", since: now, project: "trip", source: "chat", options: [])],
                      parked: ["trip", "quiet"])
        let deck = NeedsDeck(s, now: now)
        XCTAssertEqual(deck.waiting.map(\.key), ["c", "d"], "a chat is never a project's: never parked")
        XCTAssertEqual(deck.parked.map(\.project.projectId), ["trip", "quiet"])
        XCTAssertEqual(deck.parked.map(\.items), [2, 0])
    }

    func testTheChip() {
        XCTAssertNil(NeedsDeck(nil, now: now).chip, "nothing waiting, nothing parked: no chip")
        XCTAssertFalse(NeedsDeck(.empty, now: now).shown)
        let one = NeedsDeck(state([item("a", since: now)]), now: now)
        XCTAssertEqual(one.chip?.text, "1 needs you")
        XCTAssertEqual(one.chip?.tone, .violet)
        let perm = NeedsDeck(state([item("a", "permission", since: now - min, source: "chat"), item("b", since: now)]), now: now)
        XCTAssertEqual(perm.chip?.text, "2 need you")
        XCTAssertEqual(perm.chip?.tone, .amber, "the oldest decides: a chat waiting for permission")
        let violetFirst = NeedsDeck(state([item("b", since: now - min), item("a", "permission", since: now, source: "chat")]), now: now)
        XCTAssertEqual(violetFirst.chip?.tone, .violet)
        let mem = NeedsDeck(state([item("b", since: now - min), item("m", "memory", since: now, project: nil, source: "memory")]), now: now)
        XCTAssertEqual(mem.chip?.tone, .red, "memory nearly full outranks the rest")
        let parkedOnly = NeedsDeck(state([item("a", since: now, project: "trip")], parked: ["trip"]), now: now)
        XCTAssertEqual(parkedOnly.chip?.text, "1 parked")
        XCTAssertEqual(parkedOnly.chip?.tone, .grey)
        XCTAssertTrue(parkedOnly.shown)
    }

    func testToneOfEachKind() {
        XCTAssertEqual(NeedsDeck.tone(of: item("a", "ask", since: 0)), .violet)
        XCTAssertEqual(NeedsDeck.tone(of: item("a", "next", since: 0)), .violet)
        XCTAssertEqual(NeedsDeck.tone(of: item("a", "question", since: 0)), .violet)
        XCTAssertEqual(NeedsDeck.tone(of: item("a", "plan", since: 0)), .violet)
        XCTAssertEqual(NeedsDeck.tone(of: item("a", "permission", since: 0)), .amber)
        XCTAssertEqual(NeedsDeck.tone(of: item("a", "open", since: 0)), .amber)
        XCTAssertEqual(NeedsDeck.tone(of: item("a", "memory", since: 0)), .red)
    }

    func testTheCurrentCardAfterTheListChanged() {
        let deck = NeedsDeck(state([item("a", since: 1), item("b", since: 2), item("c", since: 3)]), now: now)
        XCTAssertEqual(deck.current(after: "b", was: 1), 1)
        let gone = NeedsDeck(state([item("a", since: 1), item("c", since: 3)]), now: now)
        XCTAssertEqual(gone.current(after: "b", was: 1), 1, "answered: the next one slides into its place")
        let last = NeedsDeck(state([item("a", since: 1)]), now: now)
        XCTAssertEqual(last.current(after: "c", was: 2), 0)
        XCTAssertNil(NeedsDeck(.empty, now: now).current(after: "a", was: 0))
        XCTAssertEqual(deck.current(after: nil, was: nil), 0)
    }

    func testWaitTimes() {
        XCTAssertEqual(NeedsDeck.wait(40_000), "40s")
        XCTAssertEqual(NeedsDeck.wait(12 * min), "12m")
        XCTAssertEqual(NeedsDeck.wait(65 * min), "1h 5m")
        XCTAssertEqual(NeedsDeck.wait(120 * min), "2h")
        XCTAssertEqual(NeedsDeck.wait(26 * 60 * min), "1d 2h")
        XCTAssertEqual(NeedsDeck.wait(-5), "0s")
    }

    func testWhatEachCardOffers() {
        let ask = NeedCard(item("a", since: 0, options: ["Add disk swap", "Leave it", "Later"]))
        XCTAssertEqual(ask.answers.map(\.label), ["Add disk swap", "Leave it", "Later"])
        XCTAssertEqual(ask.answers.map(\.recommended), [true, false, false], "the first is the recommended one, blue")
        XCTAssertTrue(ask.somethingElse)
        XCTAssertEqual(ask.prefix, "")
        XCTAssertFalse(ask.openOnly)

        let thread = NeedCard(item("t", since: 0, work: "a21"))
        XCTAssertEqual(thread.prefix, "a21: ", "Something else starts with the thread for a thread's question")
        XCTAssertEqual(thread.text, "a21: Q?")
        XCTAssertEqual(item("t", since: 0, work: "a21").listTitle, "a21: t")

        var permItem = item("p", "permission", since: 0, source: "chat", options: ["Allow once", "Always", "Deny"])
        permItem.recommended = -1
        permItem.body = ["npm run build"]
        let perm = NeedCard(permItem)
        XCTAssertEqual(perm.answers.map(\.label), ["Allow once", "Always", "Deny"])
        XCTAssertFalse(perm.answers.contains { $0.recommended })
        XCTAssertFalse(perm.somethingElse)
        XCTAssertEqual(perm.body, ["npm run build"])

        let open = NeedCard(item("o", "open", since: 0, source: "chat", options: []))
        XCTAssertTrue(open.openOnly, "several answers or no dialog: Open chat only")
        XCTAssertTrue(open.answers.isEmpty)
        XCTAssertFalse(open.somethingElse)

        let mem = NeedCard(item("m", "memory", since: 0, project: nil, source: "memory", options: ["Sleep idle chats", "Show memory"]))
        XCTAssertTrue(mem.memory)
        XCTAssertFalse(mem.openOnly)
        XCTAssertFalse(mem.somethingElse)
        XCTAssertEqual(mem.answers.first?.recommended, true)
        XCTAssertNil(item("m", "memory", since: 0).openChat, "the memory warning opens the Memory sheet, not a chat")
    }

    func testDemoAndRealPayloadsDecode() throws {
        let n: NeedsState = try XCTUnwrap(Demo.load("needs"))
        let deck = NeedsDeck(n, now: 1_792_000_000_000)
        XCTAssertEqual(deck.waiting.map(\.name), ["Home server", "Lumen Studio website", "Gallery lightbox fix",
                                                  "Garden planner", "Recipe scaler"])
        XCTAssertEqual(deck.waiting.map { NeedsDeck.wait(1_792_000_000_000 - $0.since) }, ["12m", "8m", "5m", "3m", "1m"])
        XCTAssertEqual(deck.chip?.text, "5 need you")
        XCTAssertEqual(deck.chip?.tone, .violet)
        XCTAssertEqual(deck.parked.map(\.items), [1])
        XCTAssertEqual(deck.waiting[1].pictures?.count, 2)
        let mem: NeedItem = try XCTUnwrap(Demo.load("needs-memory"))
        XCTAssertEqual(mem.kind, "memory")
        // what gw3-phone sends (tools/test_gw3_needs.py's shapes): extra keys are fine, missing optional ones too
        let raw = #"{"items":[{"key":"chat:c1:f00","kind":"question","source":"chat","chatId":"c1","name":"Fan","title":"Button color","question":"Which?","summary":"","body":[],"options":[{"label":"Blue","detail":"calm","n":1}],"recommended":0,"other":true,"otherChoice":3,"since":5,"sig":"f00","pictures":[],"future":1}],"parked":[],"snoozed":{"x":1},"dismissed":{}}"#
        let s = try JSONDecoder().decode(NeedsState.self, from: Data(raw.utf8))
        XCTAssertEqual(s.items.first?.options.first?.n, 1)
        XCTAssertEqual(s.items.first?.otherChoice, 3)
    }

    func testMemoryWords() throws {
        let m: MemoryView = try XCTUnwrap(Demo.load("memory"))
        XCTAssertEqual(MemoryText.gb(3.8 * Double(1 << 30)), "3.8 GB")
        XCTAssertEqual(MemoryText.gb(58 * Double(1 << 30)), "58 GB")
        XCTAssertEqual(MemoryText.state(m), "Memory is nearly full")
        XCTAssertEqual(MemoryText.ram(m).value, "58 GB of 62 GB in use")
        XCTAssertEqual(MemoryText.level(ram: m), 2)
        XCTAssertEqual(MemoryText.level(swap: m), 2)
        XCTAssertTrue(MemoryText.swap(m).hint.hasPrefix("Compressed swap in RAM (zram)"))
        XCTAssertEqual(MemoryText.share(m).total, "21 GB in all")
        XCTAssertTrue(MemoryText.share(m).parts.contains("6 asleep (no memory)"))
        XCTAssertEqual(MemoryText.hint(try XCTUnwrap(m.chats?.first)), "Thread  ·  2.9 GB of it in swap")
        let one = try JSONDecoder().decode(SleepReply.self, from: Data(#"{"chat":"c","slept":false,"reasons":["turn running"]}"#.utf8))
        XCTAssertEqual(one.words, "Stays awake: turn running")
        let all = try JSONDecoder().decode(SleepReply.self, from: Data(#"{"slept":[{"chat":"a"},{"chat":"b"}],"awake":[{"chat":"c","reasons":["x"]}],"unreadable":[]}"#.utf8))
        XCTAssertEqual(all.words, "2 chats put to sleep; 1 stay awake (busy, used in the last 5 min, or shown)")
    }

    @MainActor
    func testTheDemoDeckAnswersSnoozesDismissesAndBringsBack() async throws {
        let saved = Demo.args
        Demo.args = ["-demo", "-needs"]
        defer { Demo.args = saved }
        let app = AppModel(demo: true)
        await app.refresh()
        XCTAssertEqual(app.needsDeck.waiting.count, 5)
        let first = try XCTUnwrap(app.needsDeck.waiting.first)
        await app.answer(need: first, option: 0)
        XCTAssertEqual(app.needsDeck.waiting.count, 4)
        await app.snooze(need: app.needsDeck.waiting[0])
        await app.dismiss(need: app.needsDeck.waiting[0])
        XCTAssertEqual(app.needsDeck.waiting.map(\.name), ["Garden planner", "Recipe scaler"])
        XCTAssertEqual(app.needsDeck.parked.map(\.items), [1])
        await app.park(project: "trip-planner-2c4e", false)
        XCTAssertEqual(app.needsDeck.waiting.first?.name, "Trip planner", "brought back: its question, oldest, comes first")
        XCTAssertTrue(app.needsDeck.parked.isEmpty)
    }

    @MainActor
    func testNeedsLinks() {
        let app = AppModel(demo: true)
        XCTAssertTrue(app.open(needsLink: URL(string: "gupworks3://needs/ask:home-server-5e6f:q3")!))
        XCTAssertEqual(app.openNeeds, "ask:home-server-5e6f:q3")
        XCTAssertTrue(app.open(needsLink: URL(string: "gupworks3://needs")!))
        XCTAssertEqual(app.openNeeds, "")
        XCTAssertFalse(app.open(needsLink: URL(string: "gupworks3://pair?x=1")!))
    }

    func testOpenChatFindsTheCard() throws {
        let fixture: ChatFixture = try XCTUnwrap(Demo.load("00000066-1111-4222-8333-000000000066", in: "fixtures/chats"))
        let turns = fixture.turns.turns
        let row = try XCTUnwrap(NeedsReveal.row(in: turns, question: "The darker palette is in and every page passes contrast. Is the site ready for your OK?"))
        XCTAssertTrue(row.hasSuffix("/outside/ask-toolu_demo7e110009"))
        XCTAssertEqual(NeedsReveal.row(in: turns, question: "something it never asked"), row, "else its newest open one")
        XCTAssertNil(NeedsReveal.row(in: [], question: "x"))
    }
}
