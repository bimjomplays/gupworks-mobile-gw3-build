import Foundation
import XCTest
#if canImport(GupKit)
@testable import GupKit
#else
@testable import GupWorks3
#endif

/// a234: the Apple Watch app's rules (docs/watch-mockups/round2 Option 7): the card, the deck, the 5 s Undo, the
/// iPhone relay and the notification's real answers.
final class WatchTests: XCTestCase {
    let now = 1_792_000_000_000.0
    let min = 60_000.0

    var demo: WatchDemo {
        let d: WatchDemo? = Demo.load("needs", in: "fixtures/watch")
        return d!
    }

    func card(_ key: String, memory: Bool = false) -> WatchCard {
        let l = demo.list(now: 0, memory: memory)
        return WatchCard(l.needs.items.first { $0.key.hasPrefix(key) }!)
    }

    // MARK: the card

    func testAskCardShowsEverythingRecommendedFirst() {
        var item = demo.list.needs.items[0]
        item.recommended = 1  // "Leave it as is" recommended: it moves to the top
        let c = WatchCard(item)
        XCTAssertEqual(c.kind, .ask)
        XCTAssertEqual(c.source, "Home server")
        XCTAssertEqual(c.thread, "a14 · Memory limits")
        XCTAssertEqual(c.question, "Add 32 GB of real swap on the SSD as a safety net?")
        XCTAssertTrue(c.summary.hasSuffix("A swap file on the SSD is used only after that."))
        XCTAssertEqual(c.answers.map(\.label), ["Leave it as is", "Add disk swap", "Do it later"])
        XCTAssertEqual(c.answers.map(\.option), [1, 0, 2])
        XCTAssertEqual(c.answers[0].detail, "Rely on sleeping chats, memory limits and the warning.")
        XCTAssertEqual(c.primary?.label, "Leave it as is")
        XCTAssertTrue(c.doubleTap)
        XCTAssertTrue(c.bar)
        XCTAssertTrue(c.voice)
        XCTAssertEqual(c.to, "Home server · a14")
        XCTAssertEqual(c.head(now: now), "Home server · 12m")
    }

    func testPictureCardKeepsBothPictures() {
        let c = card("ask:lumen")
        XCTAssertEqual(c.pictures.map(\.caption), ["Before · One per row", "After · The new grid"])
        XCTAssertEqual(c.primary?.label, "Ship the grid")
        XCTAssertEqual(c.head(now: now), "Lumen Studio website · 8m")
    }

    func testPermissionIsTapOnlyWithCommandAndWhy() {
        let c = card("chat:00000009")
        XCTAssertEqual(c.kind, .permission)
        XCTAssertEqual(c.command, "npm run build")
        XCTAssertEqual(c.summary, "Builds the site to check the lightbox fix.")
        XCTAssertEqual(c.allow?.option, 0)
        XCTAssertEqual(c.deny?.option, 2)
        XCTAssertEqual(c.primary?.label, "Allow once")
        XCTAssertFalse(c.doubleTap, "a command is never allowed by a stray pinch")
        XCTAssertTrue(c.bar)
        XCTAssertTrue(c.voice, "the mic denies and tells the chat what to do instead")
        XCTAssertTrue(c.chat)
        XCTAssertEqual(c.tone, .amber)
    }

    func testPermissionWithoutAllowOnceOrDenyOpensOnIPhone() {
        var item = demo.list.needs.items[2]
        item.options = [.init(label: "Yes", detail: nil, n: 1), .init(label: "No", detail: nil, n: 2)]
        XCTAssertEqual(WatchCard(item).kind, .phone)
    }

    func testSeveralQuestionsOpenOnIPhone() {
        let c = card("chat:00000003")
        XCTAssertEqual(c.kind, .phone)
        XCTAssertFalse(c.bar)
        XCTAssertEqual(c.question, "Units and servings")
        XCTAssertEqual(c.summary, "Several questions at once: answer them on your iPhone.")
    }

    func testMemoryCard() {
        let c = card("memory:", memory: true)
        XCTAssertEqual(c.kind, .memory)
        XCTAssertEqual(c.source, "The PC")
        XCTAssertEqual(c.question, "Nearly full: 58 of 62 GB in use, swap 80%")
        XCTAssertEqual(c.sleep?.label, "Sleep idle chats")
        XCTAssertFalse(c.bar)
        XCTAssertEqual(c.head(now: now), "The PC · now")
        XCTAssertEqual(c.tone, .red)
    }

    func testNoRecommendedAnswerLeavesTheMicAlone() {
        var item = demo.list.needs.items[0]
        item.recommended = -1
        let c = WatchCard(item)
        XCTAssertNil(c.primary)
        XCTAssertFalse(c.doubleTap)
        XCTAssertTrue(c.bar)
        item.other = false
        XCTAssertFalse(WatchCard(item).bar)
    }

    func testWait() {
        XCTAssertEqual(WatchCard.wait(30_000), "now")
        XCTAssertEqual(WatchCard.wait(12 * min), "12m")
        XCTAssertEqual(WatchCard.wait(65 * min), "1h 5m")
    }

    // MARK: the deck

    func testDeckOrderMemoryFirstThenOldestWithoutParked() {
        let l = demo.list(now: 0, memory: true)
        let deck = WatchDeck(l.needs, now: l.pc(at: 0))
        XCTAssertEqual(deck.cards.map(\.source), ["The PC", "Home server", "Lumen Studio website", "Gallery lightbox fix",
                                                  "Garden planner", "Recipe scaler"])
        XCTAssertEqual(deck.parked, [WatchParked(projectId: "trip-planner-2c4e", name: "Trip planner", items: 1)])
        XCTAssertEqual(deck.title(0), "Memory")
        XCTAssertEqual(deck.title(1), "1 of 5")
        XCTAssertEqual(deck.title(3), "3 of 5")
        XCTAssertEqual(deck.cards.map(\.listTitle), ["Memory nearly full", "a14: Add 32 GB of real swap?",
                                                     "a21: Ship the new gallery grid?", "Run npm run build?",
                                                     "What's next?", "Several answers: open the chat"])
    }

    func testDeckCurrentAfterAnAnswer() {
        let l = demo.list(now: 0, memory: false)
        let before = WatchDeck(l.needs, now: l.pc(at: 0))
        let after = WatchDeck(l.needs, now: l.pc(at: 0), off: [before.cards[0].key])
        XCTAssertEqual(after.cards.count, 4)
        // the answered card was first: the next one (Lumen) takes its place, "1 of 4"
        let i = after.current(after: before.cards[0].key, was: 0)
        XCTAssertEqual(i, 0)
        XCTAssertEqual(after.cards[i!].source, "Lumen Studio website")
        XCTAssertNil(WatchDeck(nil, now: now).current(after: nil, was: nil))
    }

    // MARK: Undo

    func testUndoHoldsFiveSecondsThenGoes() {
        var box = WatchOutbox()
        let c = card("ask:home")
        let s = WatchSend.answer(c.primary!, on: c, at: 100)
        box.add(s)
        XCTAssertEqual(box.holding, s)
        XCTAssertEqual(box.left(now: 100), 5)
        XCTAssertEqual(box.left(now: 101.2), 4)
        XCTAssertTrue(box.off.contains(c.key), "the card leaves at once")
        box.tick(now: 104.9)
        XCTAssertTrue(box.ready.isEmpty, "nothing leaves before 5 s")
        box.tick(now: 105)
        XCTAssertNil(box.holding)
        XCTAssertEqual(box.ready, [s])
        box.handed(s.id, now: 106)
        XCTAssertTrue(box.ready.isEmpty)
        XCTAssertTrue(box.off.contains(c.key), "off until the PC's list drops it")
        box.listed([c.key], now: 110)
        XCTAssertTrue(box.off.contains(c.key))
        box.listed([], now: 111)
        XCTAssertFalse(box.off.contains(c.key))
    }

    func testUndoTakesItBackAndTheCardReturns() {
        var box = WatchOutbox()
        let c = card("ask:home")
        box.add(.answer(c.answers[1], on: c, at: 0))
        XCTAssertEqual(box.undo()?.label, "Leave it as is")
        box.tick(now: 10)
        XCTAssertTrue(box.ready.isEmpty)
        XCTAssertTrue(box.off.isEmpty)
    }

    func testASecondAnswerSendsTheFirstAtOnce() {
        var box = WatchOutbox()
        let a = card("ask:home"), b = card("ask:lumen")
        box.add(.answer(a.primary!, on: a, at: 0))
        box.add(.answer(b.primary!, on: b, at: 2))
        XCTAssertEqual(box.ready.map(\.key), [a.key])
        XCTAssertEqual(box.holding?.key, b.key)
    }

    func testStillListedAfterGraceComesBackAndFailuresReturnAtOnce() {
        var box = WatchOutbox()
        let c = card("ask:home")
        let s = WatchSend.answer(c.primary!, on: c, at: 0)
        box.add(s)
        box.tick(now: 5)
        box.handed(s.id, now: 5)
        box.listed([c.key], now: 5 + WatchOutbox.grace)
        XCTAssertFalse(box.off.contains(c.key))
        box.add(s)
        box.tick(now: 200)
        box.handed(s.id, now: 200)
        box.failed(c.key)
        XCTAssertFalse(box.off.contains(c.key))
    }

    func testMemoryStaysAfterSleepIdleChats() {
        var box = WatchOutbox()
        let c = card("memory:", memory: true)
        let s = WatchSend.answer(c.sleep!, on: c, at: 0)
        box.add(s)
        XCTAssertFalse(box.off.contains(c.key))
        box.tick(now: 5)
        box.handed(s.id, now: 5)
        XCTAssertFalse(box.off.contains(c.key))
        box.add(WatchSend(what: .dismiss, key: c.key, to: c.source, label: "Dismiss", at: 6))
        XCTAssertTrue(box.off.contains(c.key), "Dismiss takes it off")
    }

    func testParkAndOpenGoAtOnce() {
        var box = WatchOutbox()
        box.add(WatchSend(what: .park, key: "park:p", projectId: "p", parked: false, to: "Trip planner", label: "", at: 0))
        XCTAssertNil(box.holding)
        XCTAssertEqual(box.ready.count, 1)
    }

    func testVoiceWords() {
        let c = card("ask:home")
        XCTAssertNil(WatchSend.words("  \n ", on: c, at: 0))
        let s = WatchSend.words(" Yes, but make it 16 GB ", on: c, at: 0)!
        XCTAssertEqual(s.text, "Yes, but make it 16 GB")
        XCTAssertNil(s.option)
        XCTAssertEqual(s.headline, "Sent to Home server")
        XCTAssertEqual(s.detail, "“Yes, but make it 16 GB”")
    }

    // MARK: the relay

    func testListAndSendRoundTripAndMapOntoThePhonesRoutes() {
        let l = demo.list(now: 50, memory: true)
        let ctx = WatchRelay.encode(WatchRelay.listKey, l)
        XCTAssertEqual(WatchRelay.decode(WatchRelay.listKey, ctx), l)
        XCTAssertEqual(l.pc(at: 51), l.pcNow + 1000)

        let c = card("ask:home")
        let s = WatchSend.answer(c.answers[2], on: c, at: 1)
        let msg = WatchRelay.encode(WatchRelay.sendKey, s)
        let back: WatchSend? = WatchRelay.decode(WatchRelay.sendKey, msg)
        XCTAssertEqual(back, s)
        XCTAssertEqual(PushAction(s), .answer(key: c.key, option: 2))
        XCTAssertEqual(PushAction(WatchSend.words("Hi", on: c, at: 0)!), .text(key: c.key, words: "Hi"))
        let snooze = WatchSend(what: .snooze, key: c.key, to: "", label: "", at: 0)
        XCTAssertEqual(PushAction(snooze), .snooze(key: c.key))
        XCTAssertEqual(PushAction(snooze)?.path, "/v1/needs/snooze")
        let park = PushAction(WatchSend(what: .park, key: "", projectId: "trip", parked: false, to: "", label: "", at: 0))
        XCTAssertEqual(park, .park(project: "trip", parked: false))
        XCTAssertEqual(park?.path, "/v1/needs/park")
        XCTAssertEqual(park?.body, NeedsAction(projectId: "trip", parked: false))
        XCTAssertNil(PushAction(WatchSend(what: .open, key: c.key, to: "", label: "", at: 0)))
    }

    func testReplies() {
        XCTAssertNil(WatchRelay.error(in: WatchRelay.reply(error: nil)))
        XCTAssertEqual(WatchRelay.error(in: WatchRelay.reply(error: "PC offline")), "PC offline")
        XCTAssertEqual(WatchRelay.error(in: [:]), "The iPhone couldn't send it.")
    }

    func testSilentPushTakesItemsOffTheWatch() {
        let l = demo.list(now: 0, memory: false)
        let keys = l.needs.items.map(\.key)
        XCTAssertEqual(l.without(gone: [keys[0]], live: nil).needs.items.map(\.key), Array(keys.dropFirst()))
        XCTAssertEqual(l.without(gone: [], live: [keys[1]]).needs.items.map(\.key), [keys[1]])
    }

    func testPictures() {
        let l = demo.list(now: 0, memory: false)
        XCTAssertEqual(WatchRelay.pictures(l.needs), ["demo:gallery-before.png", "demo:gallery-after.png"])
        XCTAssertEqual(WatchRelay.pictureName("/v1/media/abc"), WatchRelay.pictureName("/v1/media/abc"))
        XCTAssertNotEqual(WatchRelay.pictureName("/v1/media/abc"), WatchRelay.pictureName("/v1/media/abd"))
        XCTAssertTrue(WatchRelay.pictureName("x").hasSuffix(".jpg"))
        XCTAssertEqual(WatchRelay.pictureName("x").count, 20)
        XCTAssertTrue(WatchRelay.fit(width: 1600, height: 1000) == (832, 520))
        XCTAssertTrue(WatchRelay.fit(width: 300, height: 200) == (300, 200))
    }

    // MARK: the notification

    func testNotificationButtonsAreTheAsksRealAnswers() {
        let c = card("ask:home")
        let b = WatchNotice.buttons(c)
        XCTAssertEqual(b.map(\.title), ["Add disk swap", "Leave it as is", "Do it later", "Say something else…", "Dismiss"])
        XCTAssertEqual(b[0].id, "gw3.opt.0")
        XCTAssertEqual(WatchNotice.send(b[1].id, card: c, at: 0)?.option, 1)
        XCTAssertEqual(WatchNotice.send(WatchNotice.dismiss, card: c, at: 0)?.what, .dismiss)
        XCTAssertNil(WatchNotice.send(WatchNotice.say, card: c, at: 0))
        XCTAssertNil(WatchNotice.send("gw3.opt.9", card: c, at: 0))

        let p = WatchNotice.buttons(card("chat:00000009"))
        XCTAssertEqual(p.map(\.title), ["Deny", "Allow once", "Say what to do instead…"])
        XCTAssertTrue(p[0].destructive, "a double tap on the notification presses the first: Deny, never Allow")
        XCTAssertEqual(WatchNotice.buttons(card("memory:", memory: true)).map(\.title), ["Sleep idle chats", "Dismiss"])
        XCTAssertEqual(WatchNotice.buttons(card("chat:00000003")).map(\.title), ["Open on iPhone"])
    }

    func testThePhoneUnderstandsTheWatchsButtons() {
        let info: [AnyHashable: Any] = ["needs": "ask:p:q1", "gw3": ["kind": "ask", "rec": 0]]
        XCTAssertEqual(PushAction.from(action: "gw3.opt.2", info: info), .answer(key: "ask:p:q1", option: 2))
        XCTAssertNil(PushAction.from(action: "gw3.opt.x", info: info))
    }

    func testNotificationCarriesTheCard() {
        let info: [AnyHashable: Any] = [
            "needs": "ask:home-server-5e6f:q3",
            "gw3": ["kind": "ask", "rec": 0, "chat": "c1",
                    "card": ["n": "Home server", "t": "Add 32 GB of real swap?", "q": "Add 32 GB of real swap on the SSD?",
                             "s": "Your PC only swaps to compressed RAM.", "w": "a14", "wt": "Memory limits",
                             "src": "project", "pid": "home-server-5e6f", "since": now - 12 * min,
                             "o": [["Add disk swap", "One script."], ["Leave it as is", ""]], "r": 0, "x": true] as [String: Any]],
        ]
        let item = WatchNotice.item(info)!
        XCTAssertEqual(item.key, "ask:home-server-5e6f:q3")
        XCTAssertEqual(item.chatId, "c1")
        let c = WatchCard(item)
        XCTAssertEqual(c.kind, .ask)
        XCTAssertEqual(c.thread, "a14 · Memory limits")
        XCTAssertEqual(c.answers.map(\.label), ["Add disk swap", "Leave it as is"])
        XCTAssertEqual(c.answers[0].detail, "One script.")
        XCTAssertTrue(c.voice)
        XCTAssertEqual(c.head(now: now), "Home server · 12m")
        XCTAssertNil(WatchNotice.item(["needs": "x", "gw3": ["kind": "ask"]]), "an older PC sends no card")
    }

    // MARK: what is running (a235)

    func testGlanceSaysWorkingCheckingOrIdleInTheProjectsOrder() {
        let l = demo.list(now: 0, memory: false)
        let g = WatchGlance(l.projects)
        XCTAssertEqual(g.rows.map(\.project.name),
                       ["Home server", "Lumen Studio website", "Garden planner", "YouTube Studio"])
        XCTAssertEqual(g.rows.map(\.text), ["2 working", "1 checking", "idle", "1 working"])
        XCTAssertEqual(g.rows.map(\.state), [.working, .checking, .idle, .working])
        XCTAssertEqual(WatchGlance.words(working: 2, checking: 1), "2 working \u{B7} 1 checking")
        XCTAssertTrue(WatchGlance(nil).isEmpty, "an iPhone that sends no projects yet")
    }

    func testListsFromBeforeTheGlanceStillDecode() throws {
        var l = demo.list(now: 0, memory: false)
        l.projects = nil
        let data = try JSONEncoder().encode(l)
        XCTAssertFalse(String(data: data, encoding: .utf8)!.contains("projects"))
        XCTAssertEqual(try JSONDecoder().decode(WatchRelay.List.self, from: data), l)
        let again: WatchRelay.List? = WatchRelay.decode(WatchRelay.listKey, WatchRelay.encode(WatchRelay.listKey, demo.list))
        XCTAssertEqual(again?.projects?.count, 4)
    }

    func testProjectRowsBecomeTheWatchsProjects() {
        let home = Home(now: 0, projects: [ProjectRow(id: "p1", name: "Lumen", state: "working", detail: "", needs: 0,
                                                      permission: 0, working: 1, checking: 2, paused: false,
                                                      mainChatId: "c1")],
                        setups: [], chats: [], archivedCount: 0,
                        studio: ProjectRow(id: "studio", name: "YouTube Studio", state: "idle", detail: "", needs: 0,
                                           permission: 0, working: 0, paused: false, mainChatId: nil))
        XCTAssertEqual(WatchProject.list(home), [WatchProject(id: "p1", name: "Lumen", working: 1, checking: 2, main: true),
                                                  WatchProject(id: "studio", name: "YouTube Studio", working: 0,
                                                               checking: 0, main: false)])
        XCTAssertNil(WatchProject.list(nil))
    }

    func testWordsForAMainChatWaitOutTheUndoLikeAnswers() throws {
        let home = demo.list.projects![0]
        let s = try XCTUnwrap(WatchSend.say("  Please wait until the backup is done  ", to: home, at: 100))
        XCTAssertEqual(s.what, .say)
        XCTAssertEqual(s.projectId, "home-server-5e6f")
        XCTAssertEqual(s.text, "Please wait until the backup is done")
        XCTAssertTrue(s.undoable)
        XCTAssertEqual(s.headline, "Sent to Home server")
        XCTAssertEqual(s.detail, "\u{201C}Please wait until the backup is done\u{201D}")
        var box = WatchOutbox()
        box.add(s)
        XCTAssertEqual(box.left(now: 100), 5)
        XCTAssertTrue(box.ready.isEmpty, "nothing leaves the watch during the Undo")
        XCTAssertEqual(box.undo()?.id, s.id)
        box.tick(now: 200)
        XCTAssertTrue(box.ready.isEmpty, "an undone send never goes")
        box.add(s)
        box.tick(now: 105.5)
        XCTAssertEqual(box.ready.map(\.id), [s.id])
    }

    func testNothingIsSentEmptyOrToAProjectWithoutAMainChat() {
        let l = demo.list.projects!
        XCTAssertNil(WatchSend.say("   ", to: l[0], at: 0))
        XCTAssertNil(WatchSend.say("hello", to: l[3], at: 0), "YouTube Studio has no main chat")
        XCTAssertEqual(WatchSend.say(String(repeating: "x", count: 5000), to: l[0], at: 0)?.text?.count, 4000)
    }

    func testASayTravelsAsOneJSONValueAndIsNotANeedsAction() throws {
        let s = try XCTUnwrap(WatchSend.say("hi", to: demo.list.projects![0], at: 1))
        let back: WatchSend? = WatchRelay.decode(WatchRelay.sendKey, WatchRelay.encode(WatchRelay.sendKey, s))
        XCTAssertEqual(back, s)
        XCTAssertNil(PushAction(s), "the needs-you routes never carry it")
    }

    // MARK: the complication (a235)

    func testFaceShowsTheCountAndTheOldestOne() {
        let l = demo.list(now: 1000, memory: false)
        let c = WatchComplication(l, now: 1000)
        XCTAssertEqual(c.count, 5)
        XCTAssertEqual(c.headline, "5 NEED YOU")
        XCTAssertEqual(c.source, "Home server")
        XCTAssertEqual(c.title, "Add 32 GB of real swap?")
        XCTAssertEqual(c.wait, "12m")
        XCTAssertEqual(c.tone, .violet)
        XCTAssertEqual(c.ring, 0.3, accuracy: 0.001)
        XCTAssertFalse(c.isEmpty)
    }

    func testFaceTurnsAmberForAPermissionAndRedForMemory() {
        var l = demo.list(now: 1000, memory: false)
        l.needs.items.removeAll { $0.key.hasPrefix("ask:") }
        let perm = WatchComplication(l, now: 1000)
        XCTAssertEqual(perm.tone, .amber)
        XCTAssertEqual(perm.count, 2)
        let mem = WatchComplication(demo.list(now: 1000, memory: true), now: 1000)
        XCTAssertEqual(mem.tone, .red)
        XCTAssertEqual(mem.count, 6)
        XCTAssertEqual(mem.source, "Home server", "the face names the oldest question, not the memory warning")
        var only = demo.list(now: 1000, memory: true)
        only.needs.items = [demo.memory]
        let m = WatchComplication(only, now: 1000)
        XCTAssertEqual(m.count, 1)
        XCTAssertEqual(m.tone, .red)
        XCTAssertEqual(m.source, "The PC")
        XCTAssertEqual(m.title, "Memory nearly full")
        XCTAssertEqual(m.headline, "1 NEEDS YOU")
    }

    func testFaceSaysNothingNeedsYouAndFollowsTheClockAndTheOutbox() {
        let none = WatchComplication(nil, now: 1000)
        XCTAssertTrue(none.isEmpty)
        XCTAssertEqual(none.headline, "Open GupWorks", "no list from the iPhone yet is not \"nothing\"")
        XCTAssertFalse(none.known)
        var quiet = demo.list(now: 1000, memory: false)
        quiet.needs.items = []
        let q = WatchComplication(quiet, now: 1000)
        XCTAssertEqual(q.headline, "Nothing needs you")
        XCTAssertTrue(q.known)
        XCTAssertEqual(none.tone, .grey)
        XCTAssertNil(none.source)
        XCTAssertEqual(none.ring, 0)
        let l = demo.list(now: 1000, memory: false)
        XCTAssertEqual(WatchComplication(l, now: 1000 + 3 * 60).wait, "15m", "the wait ticks with the watch's clock")
        // answered on the wrist a moment ago: the count drops before the PC's list does
        let c = WatchComplication(l, now: 1000, off: ["ask:home-server-5e6f:q3"])
        XCTAssertEqual(c.count, 4)
        XCTAssertEqual(c.source, "Lumen Studio website")
    }

    func testTheFaceOpensTheCards() {
        XCTAssertEqual(WatchComplication.url.absoluteString, "gupworksw://cards")
    }

    func testTheWatchAppHandsTheFaceItsDataAndSaysWhenToReload() throws {
        let suite = "gw3.watch.face.test"
        let d = try XCTUnwrap(UserDefaults(suiteName: suite))
        d.removePersistentDomain(forName: suite)
        defer { d.removePersistentDomain(forName: suite) }
        XCTAssertEqual(WatchFace.load(d), WatchFace.Saved(list: nil, off: []))
        let l = demo.list(now: 1000, memory: false)
        XCTAssertTrue(WatchFace.save(list: l, off: [], now: 1000, d), "nothing waited, now five do")
        let got = WatchFace.load(d)
        XCTAssertNil(got.list?.projects, "the face never draws the projects")
        XCTAssertEqual(WatchComplication(got.list, now: 1000).count, 5)
        XCTAssertFalse(WatchFace.save(list: l, off: [], now: 1000, d), "the same list again changes nothing")
        var older = l
        older.at += 60  // a list that only differs in its clock: the face looks the same
        XCTAssertFalse(WatchFace.save(list: older, off: [], now: 1000, d))
        XCTAssertTrue(WatchFace.save(list: older, off: ["ask:home-server-5e6f:q3"], now: 1000, d),
                      "answered on the wrist: the count drops")
        XCTAssertEqual(WatchComplication(WatchFace.load(d).list, now: 1000, off: Set(WatchFace.load(d).off)).count, 4)
    }
}
