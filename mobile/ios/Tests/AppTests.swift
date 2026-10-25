import UIKit
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

final class TalkAPITests: XCTestCase {
    func testEditSendsOnlyWhatChanges() throws {
        let one = try JSONSerialization.jsonObject(with: JSONEncoder().encode(ChatEdit(title: "Trip plans"))) as? [String: Any]
        XCTAssertEqual(one?.count, 1)
        XCTAssertEqual(one?["title"] as? String, "Trip plans")
        let pin = try JSONSerialization.jsonObject(with: JSONEncoder().encode(ChatEdit(pinned: false))) as? [String: Any]
        XCTAssertEqual(pin?.keys.sorted(), ["pinned"])
    }

    func testMessageBody() throws {
        let body = OutgoingBody(clientId: "c-1", text: "Look", files: ["/uploads/photo.jpg"])
        let obj = try JSONSerialization.jsonObject(with: JSONEncoder().encode(body)) as? [String: Any]
        XCTAssertEqual(obj?["clientId"] as? String, "c-1")
        XCTAssertEqual(obj?["files"] as? [String], ["/uploads/photo.jpg"])
    }

    func testRepliesDecode() throws {
        let send = #"{"ok":true,"new":true,"started":false,"queue":[{"clientId":"c-1","text":"Look","ts":5,"state":"queued","images":["/v1/media/a.b"]},{"clientId":"c-2","text":"","ts":6,"state":"failed","error":"not sent","files":["notes.txt"]}]}"#
        let r = try JSONDecoder().decode(SendReply.self, from: Data(send.utf8))
        XCTAssertEqual(r.queue.map(\.state), ["queued", "failed"])
        XCTAssertEqual(r.queue[0].images, ["/v1/media/a.b"])
        XCTAssertEqual(r.queue[1].files, ["notes.txt"])
        let up = try JSONDecoder().decode(UploadReply.self, from: Data(#"{"path":"/u/p.jpg","name":"p.jpg","size":3,"image":true}"#.utf8))
        XCTAssertTrue(up.image)
        let made = try JSONDecoder().decode(NewChatReply.self, from: Data(#"{"id":"abc","started":true}"#.utf8))
        XCTAssertEqual(made.id, "abc")
    }

    func testPhotosGoSmallAndJPEG() throws {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let big = UIGraphicsImageRenderer(size: CGSize(width: 4000, height: 3000), format: format).image { c in
            UIColor.orange.setFill()
            c.fill(CGRect(x: 0, y: 0, width: 4000, height: 3000))
        }
        let a = try XCTUnwrap(Attachment.photo(big, name: "photo.jpg"))
        XCTAssertEqual(a.type, "image/jpeg")
        let back = try XCTUnwrap(UIImage(data: a.data))
        XCTAssertEqual(back.size.width * back.scale, 2048)
        XCTAssertEqual(back.size.height * back.scale, 1536)
        XCTAssertTrue(Attachment.readableImage("JPG"))
        XCTAssertFalse(Attachment.readableImage("heic"))
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
    // MARK: slice 3

    let working = "{\"state\":\"working\",\"ts\":1,\"live\":true,\"running\":true}"

    func testQueueEventsAndStreamStart() {
        let s = ChatStore(id: gallery, pairing: nil, demo: false)
        s.handle(SSEEvent(name: "queue", data: #"{"items":[{"clientId":"c-1","text":"Next","ts":5,"state":"queued"}]}"#))
        XCTAssertEqual(s.queue.map(\.clientId), ["c-1"])
        s.handle(SSEEvent(name: "queue", data: #"{"items":[]}"#))
        XCTAssertTrue(s.queue.isEmpty)
    }

    func testWorkingFollowsTheStatus() {
        let s = ChatStore(id: gallery, pairing: nil, demo: false)
        XCTAssertFalse(s.working)
        s.handle(SSEEvent(name: "status", data: working))
        XCTAssertTrue(s.working)
        s.handle(SSEEvent(name: "status", data: "{\"state\":\"idle\",\"ts\":2,\"live\":true,\"running\":true}"))
        XCTAssertFalse(s.working)
    }

    func testAFailedSendStaysWithRetry() async {
        let s = ChatStore(id: gallery, pairing: nil, demo: false)  // no PC: the send can't go
        await s.send(text: "  Hello  ", attachments: [])
        XCTAssertEqual(s.outbox.count, 1)
        XCTAssertEqual(s.outbox.first?.text, "Hello")
        XCTAssertNotNil(s.outbox.first?.failed)
        let id = s.outbox[0].clientId
        await s.retry(id)
        XCTAssertEqual(s.outbox.first?.clientId, id, "a retry is the same message")
        s.discard(id)
        XCTAssertTrue(s.outbox.isEmpty)
        await s.send(text: "   ", attachments: [])
        XCTAssertTrue(s.outbox.isEmpty, "nothing to send")
    }

    func testDemoNewChatQueueAndStop() async throws {
        let s = ChatStore(id: "", pairing: nil, demo: true)
        XCTAssertTrue(s.isNew)
        await s.run()
        XCTAssertTrue(s.turns.isEmpty)
        await s.send(text: "Plan a picnic", attachments: [])
        XCTAssertFalse(s.isNew)
        XCTAssertEqual(s.turns.count, 1)
        XCTAssertEqual(s.turns[0].prompt.text, "Plan a picnic")
        XCTAssertTrue(s.editable)
        await s.run()  // the view's task runs again for the new id: the demo chat stays
        XCTAssertEqual(s.turns.count, 1)
        XCTAssertFalse(s.gone)

        s.handle(SSEEvent(name: "status", data: working))
        await s.send(text: "And a playlist", attachments: [])
        XCTAssertEqual(s.queue.map(\.state), ["queued"])
        await s.stop()
        XCTAssertFalse(s.working)
        XCTAssertTrue(s.queue.isEmpty)
        XCTAssertEqual(s.turns.last?.prompt.text, "And a playlist")
    }

    func testProjectChatsAreNotEditable() async {
        let s = ChatStore(id: "00000066-1111-4222-8333-000000000066", pairing: nil, demo: true)
        await s.run()
        XCTAssertEqual(s.header?.role, "main")
        XCTAssertFalse(s.editable)
        let g = ChatStore(id: gallery, pairing: nil, demo: true)
        await g.run()
        XCTAssertTrue(g.editable)
        g.showEdit(ChatEdit(title: "Renamed", pinned: true))
        XCTAssertEqual(g.header?.title, "Renamed")
        XCTAssertEqual(g.header?.pinned, true)
    }
}

// MARK: slice 4

final class AnswerTests: XCTestCase {
    func chat(_ n: Int) -> String { String(format: "%08d-1111-4222-8333-%012d", n, n) }

    func testDialogFixturesDecode() throws {
        let perm: ChatFixture = try XCTUnwrap(Demo.load(chat(12), in: "fixtures/chats"))
        let d = try XCTUnwrap(perm.status.dialog)
        XCTAssertEqual(d.kind, "permission")
        XCTAssertTrue(d.canAnswer)
        XCTAssertEqual(d.choices?.map(\.words), ["Allow once", "Always for this project", "Deny"])
        XCTAssertEqual(perm.header.door, true)

        let ask: ChatFixture = try XCTUnwrap(Demo.load(chat(13), in: "fixtures/chats"))
        let a = try XCTUnwrap(ask.status.dialog)
        XCTAssertEqual(a.kind, "ask")
        XCTAssertEqual(a.chat, 5)
        XCTAssertEqual(a.choices?.last?.input, true)

        let plan: ChatFixture = try XCTUnwrap(Demo.load(chat(14), in: "fixtures/chats"))
        XCTAssertEqual(plan.status.dialog?.kind, "plan")
        XCTAssertFalse(plan.status.dialog?.plan?.isEmpty ?? true)

        let old: ChatFixture = try XCTUnwrap(Demo.load(chat(15), in: "fixtures/chats"))
        XCTAssertFalse(old.status.dialog?.canAnswer ?? true, "an older hold: Answer this on the PC")
        XCTAssertEqual(old.header.door, false)

        let rewind: RewindReply = try XCTUnwrap(Demo.load("rewind"))
        XCTAssertEqual(rewind.dialog.kind, "rewind")
        XCTAssertTrue(rewind.dialog.choices?.contains { $0.label == "Restore conversation" } ?? false)
    }

    func testSheetsFixturesDecode() throws {
        let c: CommandsReply = try XCTUnwrap(Demo.load("commands"))
        XCTAssertEqual(c.pinned, ["compact", "code-review", "loop"])
        XCTAssertTrue(c.commands.contains { $0.name == "btw" && $0.needsArgs })
        XCTAssertFalse(c.commands.first { $0.name == "compact" }?.needsArgs ?? true, "[focus] is optional")
        let m: ModelsReply = try XCTUnwrap(Demo.load("models"))
        XCTAssertFalse(m.models.isEmpty)
        XCTAssertTrue(m.models.allSatisfy { !$0.id.isEmpty && !$0.label.isEmpty })
    }

    func testAnswerBodies() throws {
        let one = try JSONSerialization.jsonObject(with: JSONEncoder().encode(DialogAnswer(sig: "s1", choice: 2))) as? [String: Any]
        XCTAssertEqual(one?.keys.sorted(), ["choice", "sig"])
        let ticks = try JSONSerialization.jsonObject(with: JSONEncoder().encode(DialogAnswer(sig: "s1", ticks: [1, 3], text: "x"))) as? [String: Any]
        XCTAssertEqual(ticks?["ticks"] as? [Int], [1, 3])
        let skip = try JSONSerialization.jsonObject(with: JSONEncoder().encode(DialogAnswer(sig: "s1", action: "skip"))) as? [String: Any]
        XCTAssertEqual(skip?["action"] as? String, "skip")
    }

    func testDefaultEffort() {
        XCTAssertEqual(ChatStore.defaultEffort(["low", "medium", "high", "max"]), "high")
        XCTAssertEqual(ChatStore.defaultEffort(["low", "medium"]), "medium")
        XCTAssertEqual(ChatStore.defaultEffort(["minimal"]), "minimal")
        XCTAssertEqual(ChatStore.defaultEffort([]), "")
    }

    func testMeterLinesAndCache() {
        let now = Date(timeIntervalSince1970: 1_792_000_000)
        XCTAssertEqual(Format.meterLine(Meter(label: "ctx", percent: 34, tokens: 51_000, switchAt: 150_000), now: now),
                       "51K of 150K · 34%")
        let resets = ISO8601DateFormatter().string(from: now.addingTimeInterval(3 * 3600 + 15 * 60 + 20))
        XCTAssertEqual(Format.meterLine(Meter(label: "5h", percent: 5, resets: resets), now: now), "5% · resets in 3h 15m")
        XCTAssertEqual(Format.meterLine(Meter(label: "wk", percent: 21.4), now: now), "21%")
        let warm = ChatHeader.Cache(at: (now.timeIntervalSince1970 - 15 * 60) * 1000, ttlMin: 60)
        XCTAssertEqual(Format.cacheLeft(warm, now: now), "45m")
        let cold = ChatHeader.Cache(at: (now.timeIntervalSince1970 - 2 * 3600) * 1000, ttlMin: 60)
        XCTAssertNil(Format.cacheLeft(cold, now: now))
        XCTAssertEqual(Format.tokens(1_200_000), "1.2M")
    }

    func testMessageTextForCopy() {
        let md = [MD(t: "p", text: "Fixed it."),
                  MD(t: "list", items: [MDItem(level: 0, text: "one", n: 1), MDItem(level: 1, text: "two")]),
                  MD(t: "code", lang: "sh", code: "ls")]
        XCTAssertEqual(MessageActions.plain(md), "Fixed it.\n\n1. one\n  - two\n\nls")
        XCTAssertEqual(MessageActions.quote("a\nb"), "a b")
        XCTAssertEqual(MessageActions.quote(String(repeating: "x", count: 100)).count, 80)
    }
}

@MainActor
final class AnswerStoreTests: XCTestCase {
    func chat(_ n: Int) -> String { String(format: "%08d-1111-4222-8333-%012d", n, n) }

    func testDemoAnswerTakesTheCardAway() async throws {
        let s = ChatStore(id: chat(12), pairing: nil, demo: true)
        await s.run()
        let d = try XCTUnwrap(s.dialog)
        await s.answer(DialogAnswer(sig: d.sig ?? "", choice: 1))
        XCTAssertNil(s.dialog)
        XCTAssertTrue(s.working)
    }

    func testAnOlderHoldIsAnsweredOnThePC() async throws {
        let s = ChatStore(id: chat(15), pairing: nil, demo: true)
        await s.run()
        let d = try XCTUnwrap(s.dialog)
        XCTAssertFalse(d.canAnswer)
    }

    func testRefusedErrors() {
        XCTAssertEqual(APIError.refused("This chat started on an older GupWorks.", old: true, dialog: nil).message,
                       "This chat started on an older GupWorks.")
    }

    func testPickBypassAndPins() async throws {
        let s = ChatStore(id: "00000009-1111-4222-8333-000000000009", pairing: nil, demo: true)
        await s.run()
        XCTAssertEqual(s.header?.door, true)
        await s.loadModels()
        let m = try XCTUnwrap(s.models.first { $0.id != s.header?.modelId && !$0.efforts.isEmpty })
        await s.pick(model: m, effort: "nonsense")
        XCTAssertEqual(s.header?.modelId, m.id)
        XCTAssertEqual(s.header?.effort, ChatStore.defaultEffort(m.efforts))
        XCTAssertEqual(s.header?.pending, true)

        XCTAssertEqual(s.header?.bypass, true)
        await s.setBypass(false)
        XCTAssertEqual(s.header?.bypass, false)
        await s.setBypass(true)
        XCTAssertEqual(s.header?.bypass, true)

        await s.loadCommands()
        await s.togglePin("btw")
        XCTAssertEqual(s.commands?.pinned.last, "btw")
        await s.togglePin("btw")
        XCTAssertFalse(s.commands?.pinned.contains("btw") ?? true)
    }

    func testCommandsRunOrFillTheBox() async throws {
        let s = ChatStore(id: "00000009-1111-4222-8333-000000000009", pairing: nil, demo: true)
        await s.run()
        await s.loadCommands()
        let btw = try XCTUnwrap(s.commands?.commands.first { $0.name == "btw" })
        await s.run(btw)
        XCTAssertEqual(s.draft, "/btw ")
        let compact = try XCTUnwrap(s.commands?.commands.first { $0.name == "compact" })
        let before = s.turns.count
        await s.run(compact)
        XCTAssertEqual(s.turns.count, before + 1)
        XCTAssertEqual(s.turns.last?.prompt.text, "/compact")
        XCTAssertEqual(s.commands?.recent.first, "compact")
    }

    func testRewindPutsTheMessageBack() async throws {
        let s = ChatStore(id: "00000009-1111-4222-8333-000000000009", pairing: nil, demo: true)
        await s.run()
        let t = try XCTUnwrap(s.turns.last { $0.rewind == true })
        await s.startRewind(t)
        let d = try XCTUnwrap(s.rewindDialog)
        let before = s.turns.map { $0.id }
        await s.finishRewind(d.choices?.first { $0.label == "Restore conversation" })
        XCTAssertNil(s.rewindDialog)
        XCTAssertEqual(s.draft, t.prompt.text)
        // it lands on that prompt: the prompt and the turns after it leave the list
        XCTAssertEqual(s.turns.map { $0.id }, Array(before.prefix { $0 != t.id }))
    }

    func testCutEventDropsRewoundTurns() async throws {
        let s = ChatStore(id: "00000009-1111-4222-8333-000000000009", pairing: nil, demo: true)
        await s.run()
        let ids = s.turns.map { $0.id }
        XCTAssertGreaterThan(ids.count, 1)
        s.handle(SSEEvent(name: "cut", data: "{\"ids\":[\"\(ids.last!)\",\"not-here\"]}"))
        XCTAssertEqual(s.turns.map { $0.id }, Array(ids.dropLast()))
    }
}

private extension Result {
    var problem: Failure? {
        if case .failure(let f) = self { return f }
        return nil
    }
}

final class VoiceTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_000)

    func testTapStartsAndKeepsRecording() {
        var p = MicPress()
        XCTAssertEqual(p.down(at: t0, recording: false), .start)
        XCTAssertEqual(p.down(at: t0.addingTimeInterval(0.05), recording: true), .nothing)  // the gesture repeats
        XCTAssertEqual(p.up(at: t0.addingTimeInterval(0.12), recording: true), .keep)
        XCTAssertFalse(p.isDown)
    }

    func testHoldIsPushToTalk() {
        var p = MicPress()
        XCTAssertEqual(p.down(at: t0, recording: false), .start)
        XCTAssertEqual(p.up(at: t0.addingTimeInterval(1.5), recording: true), .insert)
    }

    func testUpArrowSendsWhileRecording() {
        var p = MicPress()
        _ = p.down(at: t0, recording: false)
        _ = p.up(at: t0.addingTimeInterval(0.1), recording: true)
        XCTAssertEqual(p.down(at: t0.addingTimeInterval(3), recording: true), .nothing)
        XCTAssertEqual(p.up(at: t0.addingTimeInterval(3.1), recording: true), .send)
        // a long press on ↑ sends too
        XCTAssertEqual(p.down(at: t0.addingTimeInterval(5), recording: true), .nothing)
        XCTAssertEqual(p.up(at: t0.addingTimeInterval(6), recording: true), .send)
    }

    func testNothingWhenRecordingNeverStarted() {
        var p = MicPress()
        _ = p.down(at: t0, recording: false)
        XCTAssertEqual(p.up(at: t0.addingTimeInterval(2), recording: false), .nothing)  // no microphone, say
    }

    func testTapWithoutItsTouchDownStillCounts() {
        var p = MicPress()
        XCTAssertEqual(p.up(at: t0, recording: false), .start)
        XCTAssertEqual(p.up(at: t0.addingTimeInterval(2), recording: true), .send)
    }

    func testLevelMatchesTheDesktop() {
        XCTAssertEqual(VoiceMath.level(db: -160), 0)
        XCTAssertEqual(VoiceMath.level(db: -55), 0)
        XCTAssertEqual(VoiceMath.level(db: -32.5), 0.5, accuracy: 0.001)
        XCTAssertEqual(VoiceMath.level(db: -10), 1)
        XCTAssertEqual(VoiceMath.level(db: 0), 1)
        XCTAssertEqual(VoiceMath.level(db: -.infinity), 0)
        XCTAssertEqual(VoiceMath.level(db: .nan), 0)
    }

    func testClock() {
        XCTAssertEqual(VoiceMath.clock(4.7), "0:04")
        XCTAssertEqual(VoiceMath.clock(90), "1:30")
        XCTAssertEqual(VoiceMath.clock(600), "10:00")
        XCTAssertEqual(VoiceMath.clock(-1), "0:00")
    }

    func testMergeAfterWhatsInTheBox() {
        XCTAssertEqual(VoiceMath.merge("", "  Fix the header. "), "Fix the header.")
        XCTAssertEqual(VoiceMath.merge("Look at", "the gallery"), "Look at the gallery")
        XCTAssertEqual(VoiceMath.merge("First line\n", "second"), "First line\nsecond")
        XCTAssertEqual(VoiceMath.merge("Keep this ", "  "), "Keep this")
    }

    func testPCOnlyWhenItKnowsVoice() {
        let old = Hello(app: "gw3-phone", version: "0.4.0", api: 1, pc: "desktop", features: ["home", "chat"])
        var new = old
        new.features.append("voice")
        XCTAssertFalse(VoiceMath.usePC(nil))
        XCTAssertFalse(VoiceMath.usePC(old))
        XCTAssertTrue(VoiceMath.usePC(new))
        XCTAssertTrue(VoiceMath.usePC(Demo.load("hello")))
    }

    func testWhyThePCDidntDoIt() {
        XCTAssertEqual(VoiceMath.why(APIError.unreachable(.unknown)), "your PC couldn't be reached")
        XCTAssertEqual(VoiceMath.why(APIError.server("Voice isn't set up on this PC.")),
                       "the PC said: Voice isn't set up on this PC.")
        XCTAssertEqual(VoiceMath.why(APIError.notPaired), "your PC doesn't know this phone anymore")
        XCTAssertEqual(VoiceMath.why(CancellationError()), "your PC couldn't be reached")
    }

    func testNoAnswerSaysWhichStepFailed() {
        XCTAssertEqual(APIError.from(URLError(.cannotFindHost)), .unreachable(.noName))
        XCTAssertEqual(APIError.from(URLError(.dnsLookupFailed)), .unreachable(.noName))
        XCTAssertEqual(APIError.from(URLError(.timedOut)), .unreachable(.timeout))
        XCTAssertEqual(APIError.from(URLError(.cannotConnectToHost)), .unreachable(.refused))
        XCTAssertEqual(APIError.from(URLError(.notConnectedToInternet)), .unreachable(.offline))
        XCTAssertEqual(APIError.from(URLError(.serverCertificateUntrusted)), .unreachable(.secure))
        XCTAssertEqual(APIError.from(URLError(.unknown)), .unreachable(.unknown))
        XCTAssertEqual(APIError.from(CancellationError()), .unreachable(.unknown))
        XCTAssertEqual(APIError.from(APIError.notPaired), .notPaired)  // the PC's own answers stay as they are
        XCTAssertTrue(APIError.unreachable(.timeout).isUnreachable)
        XCTAssertFalse(APIError.notPaired.isUnreachable)
        XCTAssertTrue(APIError.unreachable(.noName).message.contains("Use Tailscale DNS"))
        XCTAssertTrue(APIError.unreachable(.unknown).message.hasPrefix("Can't reach your PC."))
    }

    func testVoiceReplyDecodes() throws {
        let full = #"{"text": "Hello from the phone.", "engine": "gpu", "seconds": 11.0, "ms": 601}"#
        let r = try JSONDecoder().decode(VoiceReply.self, from: Data(full.utf8))
        XCTAssertEqual(r, VoiceReply(text: "Hello from the phone.", engine: "gpu", seconds: 11, ms: 601))
        let silent = #"{"text": "", "engine": null, "seconds": 0.1, "ms": 12}"#
        let s = try JSONDecoder().decode(VoiceReply.self, from: Data(silent.utf8))
        XCTAssertEqual(s.text, "")
        XCTAssertNil(s.engine)
    }
}

@MainActor
final class ProjectTests: XCTestCase {
    let lumen = "lumen-studio"

    func fixture() throws -> ProjectFixture {
        try XCTUnwrap(Demo.load(lumen, in: "fixtures/projects") as ProjectFixture?)
    }

    func testFixtureDecodesAsD9() throws {
        let f = try fixture()
        XCTAssertEqual(f.view.name, "Lumen Studio website")
        XCTAssertEqual(f.view.groups.map(\.label), ["Needs you", "Working", "Done"])
        XCTAssertEqual(f.view.groups.map(\.folded), [false, false, true])
        XCTAssertEqual(f.view.counts.threads, 3)
        XCTAssertEqual(f.view.quiet.map(\.text), ["1 needs you", "2 working"])
        XCTAssertEqual(f.library.groups.map(\.id), ["pinned", "notes", "threads"])
        XCTAssertEqual(f.schedules.groups.map(\.label), ["Scheduled", "Paused"])
        XCTAssertNotNil(f.files[f.library.groups[0].items[0].path]?.blocks)
    }

    func testPauseResumeDoneArchiveRegroup() throws {
        let v = try fixture().view
        let paused = DemoProject.apply("pause", to: "a4", in: v)
        XCTAssertEqual(paused.groups.map(\.state), ["needs-you", "working", "idle", "done"])
        XCTAssertEqual(paused.counts.working, 1)
        XCTAssertEqual(paused.counts.threads, 3)
        XCTAssertEqual(paused.allThreads.first { $0.id == "a4" }?.glyph, "pause")
        XCTAssertEqual(paused.quiet.map(\.text), ["1 needs you", "1 working"])
        let resumed = DemoProject.apply("resume", to: "a4", in: paused)
        XCTAssertEqual(resumed.groups.map(\.state), ["needs-you", "working", "done"])
        let done = DemoProject.apply("done", to: "a6", in: v)
        XCTAssertEqual(done.counts.needs, 0)
        XCTAssertEqual(done.counts.threads, 2)
        XCTAssertEqual(done.groups.first { $0.state == "done" }?.count, 8)
        XCTAssertEqual(done.groups.first { $0.state == "done" }?.folded, true)
        let archived = DemoProject.apply("archive", to: "a5", in: v)
        XCTAssertEqual(archived.groups.last?.state, "archived")
        XCTAssertEqual(archived.groups.last?.folded, true)
        XCTAssertEqual(DemoProject.apply("nope", to: "a5", in: v), v)
        XCTAssertEqual(DemoProject.apply("pause", to: "zz", in: v), v)
    }

    func testDemoMarkdownKeepsTables() {
        let blocks = DemoProject.blocks("# Palette\n\n| Role | Colour |\n|---|---|\n| Accent | #a84e24 |\n\n- Sand")
        XCTAssertEqual(blocks.map(\.t), ["h", "table", "list"])
        XCTAssertEqual(blocks[1].head, ["Role", "Colour"])
        XCTAssertEqual(blocks[1].rows, [["Accent", "#a84e24"]])
    }

    func testNewThreadShowsWorking() throws {
        let v = DemoProject.add("Add a footer\nwith the address", to: try fixture().view)
        XCTAssertEqual(v.counts.working, 3)
        XCTAssertEqual(v.groups.first { $0.state == "working" }?.threads.first?.title, "Add a footer")
    }

    func testDemoStoreMovesAndSaves() async throws {
        let s = ProjectStore(id: lumen, pairing: nil, demo: true)
        await s.follow()
        XCTAssertEqual(s.view?.counts.threads, 3)
        await s.move("pause", thread: "a5")
        XCTAssertEqual(s.view?.allThreads.first { $0.id == "a5" }?.state, "idle")
        let started = await s.newThread("Write the FAQ")
        let blank = await s.newThread("   ")
        XCTAssertTrue(started)
        XCTAssertFalse(blank)
        await s.setPaused(true)
        XCTAssertEqual(s.view?.paused, true)
        await s.loadLibrary()
        let path = try XCTUnwrap(s.library?.groups[1].items.first?.path)
        let saved = try await s.save(path: path, text: "# Palette\n\n- Ink\n- Fog", version: nil)
        XCTAssertEqual(saved.blocks?.first?.t, "h")
        let reread = try await s.file(path)
        XCTAssertEqual(reread.text, "# Palette\n\n- Ink\n- Fog")
        let memory = try await s.folder("/Notes/Lumen Studio website/Memory")
        XCTAssertFalse(memory.groups.flatMap(\.items).isEmpty)
        await s.loadSchedules()
        XCTAssertEqual(s.schedules?.count, 3)
    }

    func testConflictAndOtherFailures() {
        let conflict = #"{"error": "This note changed on the PC.", "text": "theirs", "version": "abc", "mtime": 1}"#
        XCTAssertEqual(APIClient.failure(409, Data(conflict.utf8)),
                       .conflict("This note changed on the PC.", theirs: "theirs", version: "abc"))
        XCTAssertEqual(APIClient.failure(409, Data(#"{"error": "Busy."}"#.utf8)), .server("Busy."))
        XCTAssertEqual(APIClient.failure(400, Data(#"{"error": "That thread can't be done now."}"#.utf8)),
                       .server("That thread can't be done now."))
        XCTAssertEqual(APIClient.failure(502, Data("nope".utf8)), .server("The PC answered 502."))
    }

    func row(_ id: String) -> ProjectRow {
        ProjectRow(id: id, name: id, state: "idle", detail: "", needs: 0, permission: 0, working: 0, paused: false,
                   mainChatId: nil)
    }

    func testFoldersFollowTheDesktop() {
        let projects = ["a", "b", "c", "d"].map(row)
        let folder = LayoutEntry.Folder(id: "f1", name: "At home", collapsed: false)
        let layout = [LayoutEntry(project: "c"), LayoutEntry(folder: folder, projects: ["a", "gone", "b"])]
        XCTAssertEqual(ProjectLayout.rows(projects, layout: layout, open: [:]).map(\.id),
                       ["p-c", "f-f1", "p-a", "p-b", "p-d"])
        XCTAssertEqual(ProjectLayout.rows(projects, layout: layout, open: ["f1": false]).map(\.id),
                       ["p-c", "f-f1", "p-d"])
        var closed = folder
        closed.collapsed = true
        let shut = [LayoutEntry(folder: closed, projects: ["a"])]
        XCTAssertEqual(ProjectLayout.rows(projects, layout: shut, open: [:]).map(\.id), ["f-f1", "p-b", "p-c", "p-d"])
        XCTAssertEqual(ProjectLayout.rows(projects, layout: shut, open: ["f1": true]).map(\.id),
                       ["f-f1", "p-a", "p-b", "p-c", "p-d"])
        // a folder with nothing left in it isn't shown; no layout keeps the PC's order
        let empty = [LayoutEntry(folder: folder, projects: ["gone"])]
        XCTAssertEqual(ProjectLayout.rows(projects, layout: empty, open: [:]).map(\.id), ["p-a", "p-b", "p-c", "p-d"])
        XCTAssertEqual(ProjectLayout.rows(projects, layout: nil, open: [:]).map(\.id), ["p-a", "p-b", "p-c", "p-d"])
    }

    func testHomeLayoutDecodes() throws {
        let home: Home = try XCTUnwrap(Demo.load("home"))
        let rows = ProjectLayout.rows(home.projects, layout: home.layout, open: [:])
        XCTAssertEqual(rows.first?.id, "p-lumen-studio")
        XCTAssertTrue(rows.contains { if case .folder(let f, 2) = $0 { return f.name == "At home" }; return false })
    }
}

// MARK: the overhaul (5a-5h)

@MainActor
final class MenuAndBoxTests: XCTestCase {
    func testPinnedKeepsItsOrderAndRecentsTheRest() throws {
        let home: Home = try XCTUnwrap(Demo.load("home"))
        let pins = AppModel.pinnedItems(home)
        XCTAssertEqual(pins.map(\.title), ["Lumen Studio website", "Home server", "Wallpaper ideas",
                                           "Gallery lightbox fix", "Carrot picture"])
        let recents = AppModel.recents(home)
        XCTAssertFalse(recents.contains { r in pins.contains { $0.ref == PinRef(kind: "chat", id: r.id) } })
        XCTAssertEqual(recents.map(\.lastActive), recents.map(\.lastActive).sorted(by: >))
        XCTAssertEqual(recents.count + 3, (home.setups + home.chats).count)

        // an older PC without the order: its pinned chats only
        var old = home
        old.pinned = nil
        XCTAssertTrue(AppModel.pinnedItems(old).allSatisfy { if case .chat = $0 { return true } else { return false } })
        XCTAssertEqual(AppModel.pinnedItems(old).count, 3)
    }

    func testOverhaulBodiesAndReplies() throws {
        let body = NewChatBody(clientId: "c", text: "Hi", files: [], model: "claude-sonnet-5-5", effort: "low",
                               temporary: true)
        let obj = try JSONSerialization.jsonObject(with: JSONEncoder().encode(body)) as? [String: Any]
        XCTAssertEqual(obj?["model"] as? String, "claude-sonnet-5-5")
        XCTAssertEqual(obj?["temporary"] as? Bool, true)
        let enc = JSONEncoder()
        enc.outputFormatting = .sortedKeys
        let pinned = try enc.encode(PinnedBody(pinned: [PinRef(kind: "project", id: "p1")]))
        XCTAssertEqual(String(decoding: pinned, as: UTF8.self), #"{"pinned":[{"id":"p1","kind":"project"}]}"#)
        let found: SearchReply = try XCTUnwrap(Demo.load("search"))
        XCTAssertFalse(found.chats.isEmpty)
        let models: ModelsReply = try XCTUnwrap(Demo.load("models"))
        XCTAssertEqual(models.default?.model, "claude-opus-5-5")
    }

    func testNewChatStartsOnTheDefaultThenThePick() async throws {
        let s = ChatStore(id: "", pairing: nil, demo: true)
        await s.loadModels()
        XCTAssertEqual(s.currentModel?.id, "claude-opus-5-5")
        XCTAssertEqual(s.currentEffort, "medium")
        let sonnet = try XCTUnwrap(s.models.first { $0.id == "claude-sonnet-5-5" })
        await s.pick(model: sonnet, effort: "high")
        XCTAssertEqual(s.currentModel?.id, "claude-sonnet-5-5")
        XCTAssertEqual(s.currentEffort, "high")
        var made: String?
        s.onMade = { made = $0 }
        await s.send(text: "Plan a picnic", attachments: [])
        XCTAssertNotNil(made)
        XCTAssertEqual(s.header?.modelId, "claude-sonnet-5-5")
        XCTAssertEqual(s.header?.effort, "high")
    }

    func testModelSheetWords() {
        func m(_ id: String, note: String? = nil) -> ModelInfo {
            ModelInfo(id: id, label: id, provider: "Claude", note: note, efforts: [])
        }
        XCTAssertEqual(ModelEffortSheet.blurb(m("claude-opus-5-5")), "everyday, strong")
        XCTAssertEqual(ModelEffortSheet.blurb(m("claude-haiku-5-5")), "quickest, cheapest")
        XCTAssertNil(ModelEffortSheet.blurb(m("gpt-6-sol", note: "subscription")))
        XCTAssertEqual(ModelEffortSheet.blurb(m("local-qwen", note: "runs on the GPU")), "runs on the GPU")
        XCTAssertEqual(ModelEffortSheet.providerName("local"), "On your PC")
        XCTAssertEqual(Icons.needle("low"), -90)
        XCTAssertEqual(Icons.needle("high"), 0)
        XCTAssertEqual(Icons.needle("max"), 90)
    }

    func testUsageCardRows() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let now = Date(timeIntervalSince1970: 1_792_000_000)  // Wed Oct 14 2026, 17:46:40 UTC
        let iso = ISO8601DateFormatter()
        let usage = [Meter(label: "ctx", percent: 34, tokens: 68_000, switchAt: 200_000),
                     Meter(label: "5h", percent: 18, resets: iso.string(from: now.addingTimeInterval(3 * 3600 + 12 * 60 + 30))),
                     Meter(label: "wk", percent: 41, resets: iso.string(from: now.addingTimeInterval(3 * 86_400 - 6 * 60 - 40)))]
        let rows = UsageCard.rows(usage, now: now, calendar: cal)
        XCTAssertEqual(rows.map(\.label), ["ctx", "5h", "wk"])
        XCTAssertEqual(rows.map(\.percent), [34, 18, 41])
        XCTAssertEqual(rows[0].detail, "68K of 200K tokens")
        XCTAssertEqual(rows[1].detail, "resets in 3h 12m")
        XCTAssertEqual(rows[2].detail, "resets Sat 17:40")

        let fresh = UsageCard.rows([], now: now, calendar: cal)
        XCTAssertEqual(fresh[0].detail, "A new chat starts empty")
        XCTAssertEqual(fresh[0].percent, 0)
        XCTAssertEqual(fresh[1].detail, "Not known yet")
        XCTAssertNil(fresh[2].percent)
        let past = UsageCard.rows([Meter(label: "5h", percent: 99, resets: iso.string(from: now.addingTimeInterval(-60)))],
                                  now: now, calendar: cal)
        XCTAssertEqual(past[1].detail, "Reset")
    }
}
