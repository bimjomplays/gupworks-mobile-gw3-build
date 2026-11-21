import Foundation
import XCTest
#if canImport(GupKit)
@testable import GupKit
#else
@testable import GupWorks3
#endif

/// a229: ChatScroll's rules on a pretend chat: rows of given heights in a 600-point screen, with what UIKit would do
/// (clamp the offset when the content shrinks) and what the view does with the moves.
final class ChatScrollLogicTests: XCTestCase {
    struct Pretend {
        var rows: [(id: String, height: Double)]
        /// the content's y at the top of the screen
        var offset = 0.0
        let screen = 600.0
        var keeper = ChatScroll()

        init(rows n: Int, height: Double = 100) {
            rows = (0..<n).map { ("r\($0)", height) }
            layout()
            apply(.bottom(animated: false))
        }

        var height: Double { rows.reduce(0) { $0 + $1.height } }
        var bottomOffset: Double { max(0, height - screen) }
        var gap: Double { height - (offset + screen) }

        func top(_ id: String) -> Double {
            var y = 0.0
            for r in rows {
                if r.id == id { return y }
                y += r.height
            }
            return .nan
        }

        /// where a row's top is on screen
        func onScreen(_ id: String) -> Double { top(id) - offset }

        mutating func apply(_ m: ChatScroll.Move) {
            switch m {
            case .none: return
            case .bottom: offset = bottomOffset
            case .by(let d): offset += d
            }
            keeper.scrolled(top: offset)
        }

        /// after the content changed: UIKit keeps the offset (clamped), the rows say where they are now
        mutating func layout() {
            if offset > bottomOffset {
                offset = bottomOffset
                keeper.scrolled(top: offset)
            }
            for r in rows { apply(keeper.row(r.id, top: top(r.id), readingTop: offset)) }
            apply(keeper.resized(gap: gap))
        }

        mutating func grow(_ id: String, by d: Double) {
            guard let i = rows.firstIndex(where: { $0.id == id }) else { return }
            rows[i].height += d
            layout()
        }

        /// a finger that's down moves the view to `to` (UIKit doesn't clamp while it has it: past the end is a bounce)
        mutating func finger(to: Double) {
            offset = to
            keeper.scrolled(top: offset)
            keeper.moved(top: offset, gap: gap)
        }

        /// the last finger lets go with no fling; the view does what the rest says
        mutating func letGo() -> ChatScroll.Move {
            keeper.touchUp()
            let m = keeper.rest(top: offset, gap: gap)
            apply(m)
            return m
        }

        /// a line of the reply arrives (the newest row grows)
        mutating func line(_ h: Double = 65) {
            rows[rows.count - 1].height += h
            layout()
        }

        /// a drag that moves the content up by `d` (negative: older text comes into view), then lets go with no fling
        mutating func drag(_ d: Double) {
            keeper.touchDown(top: offset, gap: gap)
            offset = min(max(0, offset + d), bottomOffset)
            keeper.scrolled(top: offset)
            keeper.moved(top: offset, gap: gap)
            keeper.touchUp()
            apply(keeper.rest(top: offset, gap: gap))
        }
    }

    /// a230: Open chat with the card in view: the card's row near the top, held there while text arrives below and
    /// while rows above it change size
    func testRevealHoldsTheCardInView() {
        var c = Pretend(rows: 20)
        XCTAssertNil(c.keeper.reveal("nope"), "a row that hasn't told its top")
        let want = try! XCTUnwrap(c.keeper.reveal("r8"))
        XCTAssertEqual(want, c.top("r8") - 12)
        c.offset = want
        c.keeper.scrolled(top: c.offset)
        XCTAssertFalse(c.keeper.following)
        c.grow("r19", by: 200)
        XCTAssertEqual(c.onScreen("r8"), 12, accuracy: 0.01, "new text below doesn't move it")
        c.grow("r2", by: 150)
        XCTAssertEqual(c.onScreen("r8"), 12, accuracy: 0.01, "nor a row above changing size")
    }

    func testFollowsAtTheBottom() {
        var c = Pretend(rows: 20)
        XCTAssertTrue(c.keeper.following)
        for _ in 0..<5 {
            c.grow("r19", by: 40)
            XCTAssertEqual(c.gap, 0, accuracy: 0.01, "the newest text stays on screen")
        }
        c.rows.append(("r20", 300))
        c.layout()
        XCTAssertEqual(c.gap, 0, accuracy: 0.01, "a new turn too")
    }

    func testStreamingWhileScrolledUp() {
        var c = Pretend(rows: 20)
        c.drag(-300)
        XCTAssertFalse(c.keeper.following)
        let read = c.onScreen("r15")
        for _ in 0..<10 { c.grow("r19", by: 60) }
        c.rows.append(("r20", 400))
        c.layout()
        XCTAssertEqual(c.onScreen("r15"), read, accuracy: 0.01, "what is being read stays put")
    }

    func testAFingerResting() {
        var c = Pretend(rows: 20)
        c.keeper.touchDown(top: c.offset, gap: c.gap)
        let read = c.onScreen("r17")
        c.grow("r19", by: 120)
        XCTAssertEqual(c.onScreen("r17"), read, accuracy: 0.01, "nothing moves under the finger")
        XCTAssertGreaterThan(c.gap, 100)
        c.keeper.touchUp()
        XCTAssertEqual(c.keeper.rest(top: c.offset, gap: c.gap), .bottom(animated: true),
                       "let go where following left it: to the new text")
        c.apply(.bottom(animated: true))
        c.grow("r19", by: 50)
        XCTAssertEqual(c.gap, 0, accuracy: 0.01, "and following again")
    }

    func testBackToTheBottomFollowsAgain() {
        var c = Pretend(rows: 20)
        c.drag(-400)
        c.grow("r19", by: 200)
        XCTAssertFalse(c.keeper.following)
        c.drag(10_000)
        XCTAssertTrue(c.keeper.following, "at the bottom after letting go")
        c.grow("r19", by: 80)
        XCTAssertEqual(c.gap, 0, accuracy: 0.01)
    }

    /// scrolled down to the bottom while the reply streams: a line arrives between reaching the bottom and the scroll
    /// coming to rest, so the content's end is a little below the screen by then; letting go still follows again
    func testReachingTheBottomWhileTextArrives() {
        var c = Pretend(rows: 20)
        c.drag(-400)
        XCTAssertFalse(c.keeper.following)
        c.keeper.touchDown(top: c.offset, gap: c.gap)
        c.offset = c.bottomOffset
        c.keeper.scrolled(top: c.offset)
        c.keeper.moved(top: c.offset, gap: c.gap)
        c.grow("r19", by: 45)
        c.keeper.touchUp()
        XCTAssertEqual(c.keeper.rest(top: c.offset, gap: c.gap), .bottom(animated: true), "to the line that just came")
        XCTAssertTrue(c.keeper.following)
        c.apply(.bottom(animated: true))
        c.grow("r19", by: 50)
        XCTAssertEqual(c.gap, 0, accuracy: 0.01, "and following again")
    }

    /// dragged past the end and let go: a line arrives while it bounces back, so the bounce's last steps are above the
    /// new end; it was let go at the bottom, so it follows again
    func testALineArrivesDuringTheBounce() {
        var c = Pretend(rows: 20)
        c.drag(-400)
        c.keeper.touchDown(top: c.offset, gap: c.gap)
        c.offset = c.bottomOffset + 80
        c.keeper.scrolled(top: c.offset)
        c.keeper.moved(top: c.offset, gap: c.gap)
        c.keeper.touchUp()
        c.rows[19].height += 120
        for _ in 0..<3 {
            c.offset -= 10
            c.keeper.scrolled(top: c.offset)
            c.keeper.moved(top: c.offset, gap: c.gap)
        }
        XCTAssertGreaterThan(c.gap, ChatScroll.slack)
        XCTAssertEqual(c.keeper.rest(top: c.offset, gap: c.gap), .bottom(animated: true), "to the line that came")
        XCTAssertTrue(c.keeper.following)
    }

    /// reached the bottom, then pulled back up a little before letting go: not following
    func testReachedTheBottomThenBackUp() {
        var c = Pretend(rows: 20)
        c.drag(-400)
        c.keeper.touchDown(top: c.offset, gap: c.gap)
        c.offset = c.bottomOffset
        c.keeper.moved(top: c.offset, gap: c.gap)
        c.offset -= 120
        c.keeper.scrolled(top: c.offset)
        c.keeper.moved(top: c.offset, gap: c.gap)
        c.keeper.touchUp()
        XCTAssertEqual(c.keeper.rest(top: c.offset, gap: c.gap), .none)
        XCTAssertFalse(c.keeper.following)
    }

    func testAPushTowardTheBottomFromFollowing() {
        // following, a drag toward the bottom that ends in a bounce (the content grew meanwhile): follows on
        var c = Pretend(rows: 20)
        c.keeper.touchDown(top: c.offset, gap: c.gap)
        c.grow("r19", by: 300)
        c.offset += 50
        c.keeper.scrolled(top: c.offset)
        c.keeper.touchUp()
        XCTAssertEqual(c.keeper.rest(top: c.offset, gap: c.gap), .bottom(animated: true))
    }

    func testASmallDragUpFromFollowingStops() {
        var c = Pretend(rows: 20)
        c.keeper.touchDown(top: c.offset, gap: c.gap)
        c.grow("r19", by: 200)
        c.offset -= 60
        c.keeper.scrolled(top: c.offset)
        c.keeper.touchUp()
        XCTAssertEqual(c.keeper.rest(top: c.offset, gap: c.gap), .none, "he pulled up to read: it stays")
        XCTAssertFalse(c.keeper.following)
    }

    // MARK: a236: back to the bottom while the reply streams

    /// the finger reaches the end, a line arrives under it, and the finger goes on a little (still toward the end,
    /// now short of the new end) before letting go: it was taken to the bottom, so it follows. Before a236 any
    /// motion after the line forgot the bottom (the CI's flaky "back at the bottom", run 44822162078).
    func testALineArrivesUnderTheFingerAtTheBottom() {
        var c = Pretend(rows: 20)
        c.drag(-400)
        c.keeper.touchDown(top: c.offset, gap: c.gap)
        c.finger(to: c.bottomOffset)
        c.line(120)
        c.finger(to: c.offset + 20)
        XCTAssertGreaterThan(c.gap, ChatScroll.reach)
        XCTAssertEqual(c.letGo(), .bottom(animated: true), "to the line that came")
        XCTAssertTrue(c.keeper.following)
        c.line()
        XCTAssertEqual(c.gap, 0, accuracy: 0.01, "and following again")
    }

    /// the same with a thumb that only trembles by a point (up) after the line came
    func testAThumbTremblingAtTheBottom() {
        var c = Pretend(rows: 20)
        c.drag(-400)
        c.keeper.touchDown(top: c.offset, gap: c.gap)
        c.finger(to: c.bottomOffset + 30)   // a little past the end
        c.line(120)
        c.finger(to: c.offset - 1)
        XCTAssertEqual(c.letGo(), .bottom(animated: true))
        XCTAssertTrue(c.keeper.following)
    }

    /// reached the bottom, a line came, then pulled back up to read: not following
    func testALineArrivesThenPulledBackUp() {
        var c = Pretend(rows: 20)
        c.drag(-400)
        c.keeper.touchDown(top: c.offset, gap: c.gap)
        c.finger(to: c.bottomOffset)
        c.line()
        c.finger(to: c.offset - 30)
        XCTAssertEqual(c.letGo(), .none)
        XCTAssertFalse(c.keeper.following)
    }

    /// dragged down toward an end that keeps moving and let go 20-60 pt short of it (a thumb's miss): follows
    func testLandingJustShortOfAMovingEnd() {
        for short in [20.0, 40.0, ChatScroll.reach] {
            var c = Pretend(rows: 20)
            c.drag(-400)
            c.keeper.touchDown(top: c.offset, gap: c.gap)
            c.finger(to: c.offset + 200)
            c.line()
            c.finger(to: c.bottomOffset - short)
            XCTAssertEqual(c.letGo(), .bottom(animated: true), "\(short) pt short")
            XCTAssertTrue(c.keeper.following, "\(short) pt short")
        }
        var up = Pretend(rows: 20)
        up.drag(-200)
        up.keeper.touchDown(top: up.offset, gap: up.gap)
        up.finger(to: up.bottomOffset - 400)
        up.line()
        up.finger(to: up.bottomOffset - 30 - 65)
        up.finger(to: up.bottomOffset - 30)
        XCTAssertEqual(up.letGo(), .bottom(animated: true), "down again toward the end after going up: follows")
    }

    /// the same with a fling that runs out short of the end after the finger left
    func testAFlingRunsOutJustShortOfAMovingEnd() {
        var c = Pretend(rows: 20)
        c.drag(-400)
        c.keeper.touchDown(top: c.offset, gap: c.gap)
        c.finger(to: c.offset + 100)
        c.keeper.touchUp()
        c.line()
        for _ in 0..<8 {
            c.offset += 40
            c.keeper.scrolled(top: c.offset)
            c.keeper.moved(top: c.offset, gap: c.gap)
        }
        XCTAssertTrue(c.gap > ChatScroll.slack && c.gap <= ChatScroll.reach, "gap \(c.gap)")
        XCTAssertEqual(c.keeper.rest(top: c.offset, gap: c.gap), .bottom(animated: true))
    }

    /// further short than a thumb's miss, or no text arrived during the drag (an end that holds still is reached
    /// exactly), or the drag went up: it stays where it was let go, as before
    func testLandingShortStaysOtherwise() {
        var far = Pretend(rows: 20)
        far.drag(-400)
        far.keeper.touchDown(top: far.offset, gap: far.gap)
        far.finger(to: far.offset + 100)
        far.line()
        far.finger(to: far.bottomOffset - ChatScroll.reach - 15)
        XCTAssertEqual(far.letGo(), .none, "further than a thumb's miss")

        var still = Pretend(rows: 20)
        still.drag(-400)
        still.keeper.touchDown(top: still.offset, gap: still.gap)
        still.finger(to: still.bottomOffset - 30)
        XCTAssertEqual(still.letGo(), .none, "no text came: 30 pt above an end that holds still is where he stopped")

        var back = Pretend(rows: 20)
        back.drag(-400)
        back.keeper.touchDown(top: back.offset, gap: back.gap)
        back.finger(to: back.bottomOffset - 10)
        back.line(20)
        back.finger(to: back.offset - 20)
        XCTAssertLessThanOrEqual(back.gap, ChatScroll.reach)
        XCTAssertEqual(back.letGo(), .none, "went down, then back up to read")

        var held = Pretend(rows: 20)
        held.drag(-30)
        held.keeper.touchDown(top: held.offset, gap: held.gap)
        held.line(10)
        XCTAssertEqual(held.letGo(), .none, "a finger only resting near the end doesn't take following up")
    }

    func testOlderTurnsLoadAbove() {
        var c = Pretend(rows: 20)
        c.drag(-1_300)
        let read = c.onScreen("r3")
        c.rows.insert(contentsOf: [(id: "o0", height: 250.0), (id: "o1", height: 180.0), (id: "o2", height: 90.0)], at: 0)
        c.layout()
        XCTAssertEqual(c.onScreen("r3"), read, accuracy: 0.01, "older turns come in above without moving the screen")
    }

    /// the CI's older-page test (run 44788957270): the screen moved by the page's height a second time. The rows tell
    /// their new tops one after another; after the first correction, rows further down still had their old tops and
    /// one of them became the kept row, so its own report moved the offset again.
    func testOlderTurnsLoadAboveMovesOnce() {
        var c = Pretend(rows: 20)
        c.drag(-710)
        let read = c.onScreen("r6")
        c.rows.insert(contentsOf: [(id: "o0", height: 250.0), (id: "o1", height: 270.0)], at: 0)
        c.layout()
        XCTAssertEqual(c.onScreen("r6"), read, accuracy: 0.01, "one correction, by the page's height")
    }

    func testAboveChangingSizeWhileScrolledUp() {
        var c = Pretend(rows: 20)
        c.drag(-800)
        let read = c.onScreen("r12")
        c.grow("r4", by: 220)   // a picture far above gets its size
        XCTAssertEqual(c.onScreen("r12"), read, accuracy: 0.01)
        c.grow("r5", by: -60)   // a fold above closes
        XCTAssertEqual(c.onScreen("r12"), read, accuracy: 0.01)
    }

    func testAFoldOpenedAtTheBottomStaysWhereTapped() {
        var c = Pretend(rows: 20)
        // a tap on the newest turn's fold: the app holds the chat, then the fold opens below its row
        c.keeper.touchDown(top: c.offset, gap: c.gap)
        c.keeper.touchUp()
        c.keeper.hold()
        let row = c.onScreen("r18")
        c.grow("r18", by: 500)
        XCTAssertEqual(c.onScreen("r18"), row, accuracy: 0.01, "the fold's row doesn't move")
        XCTAssertEqual(c.keeper.rest(top: c.offset, gap: c.gap), .none, "the tap's letting go doesn't take following up again")
        c.keeper.touchDown(top: c.offset, gap: c.gap)
        c.keeper.touchUp()
        XCTAssertEqual(c.keeper.rest(top: c.offset, gap: c.gap), .none, "nor does another tap")
        c.drag(10_000)
        XCTAssertTrue(c.keeper.following, "reaching the bottom does")
    }

    func testYourOwnMessageFollows() {
        var c = Pretend(rows: 20)
        c.drag(-900)
        XCTAssertEqual(c.keeper.follow(), .bottom(animated: true))
        c.apply(.bottom(animated: true))
        c.rows.append(("mine", 80))
        c.layout()
        XCTAssertEqual(c.gap, 0, accuracy: 0.01)
    }

    func testTheKeptRowLeaves() {
        var c = Pretend(rows: 20)
        c.drag(-700)
        guard let kept = c.keeper.anchor else { return XCTFail("no row kept") }
        c.rows.removeAll { $0.id == kept }
        c.keeper.rowGone(kept, readingTop: c.offset)
        XCTAssertNotNil(c.keeper.anchor)
        XCTAssertNotEqual(c.keeper.anchor, kept)
    }

    func testAShortChatSitsAtTheTopAndFollows() {
        var c = Pretend(rows: 3)
        XCTAssertEqual(c.offset, 0)
        c.grow("r2", by: 700)
        XCTAssertEqual(c.gap, 0, accuracy: 0.01)
    }
}

/// a229: which blocks of a reply are drawn as one selectable text
final class MDPieceTests: XCTestCase {
    func testFlowingBlocksJoinOthersStandAlone() {
        let blocks = [MD(t: "h", text: "Plan"), MD(t: "p", text: "One"), MD(t: "list", items: []),
                      MD(t: "code", code: "x"), MD(t: "p", text: "Two"), MD(t: "p", text: "Three"),
                      MD(t: "quote", text: "q"), MD(t: "media", items: []), MD(t: "p", text: "Four")]
        let pieces = MDPiece.split(blocks)
        XCTAssertEqual(pieces.map(\.start), [0, 3, 4, 6, 7, 8])
        XCTAssertEqual(pieces.map(\.text), [true, false, true, false, false, true])
        XCTAssertEqual(pieces[0].blocks.map(\.t), ["h", "p", "list"])
        XCTAssertEqual(pieces[2].blocks.compactMap(\.text), ["Two", "Three"])
    }

    func testFallbackBlocksAreLeftOutButCounted() {
        let blocks = [MD(t: "p", text: "A"), MD(t: "p", text: "old", fallback: true), MD(t: "p", text: "B")]
        let pieces = MDPiece.split(blocks)
        XCTAssertEqual(pieces.count, 1)
        XCTAssertEqual(pieces[0].blocks.compactMap(\.text), ["A", "B"])
        XCTAssertEqual(MDPiece.split([MD(t: "code", code: "c"), MD(t: "p", text: "old", fallback: true),
                                      MD(t: "media", items: [])]).map(\.start), [0, 2])
    }
}

/// a236: the demo reply a test steps line by line (`-stream -stepped`) instead of racing its timer
@MainActor
final class DemoStreamTests: XCTestCase {
    override func tearDown() { Demo.args = ProcessInfo.processInfo.arguments }

    func testSteppedStreamGrowsOnlyWhenAsked() async throws {
        Demo.args = ["-demo", "-stream", "-stepped"]
        let s = ChatStore(id: "00000009-1111-4222-8333-000000000009", pairing: nil, demo: true)
        await s.run()
        XCTAssertTrue(ChatStore.demoStreaming === s)
        XCTAssertTrue(s.working)
        func lines() -> Int { s.turns.last?.blocks.first?.md?.count ?? 0 }
        XCTAssertEqual(lines(), 0)
        try await Task.sleep(nanoseconds: 600_000_000)
        XCTAssertEqual(lines(), 0, "no timer")
        let tick = s.liveTick
        s.demoStreamNext(3)
        XCTAssertEqual(lines(), 3)
        XCTAssertEqual(s.liveTick, tick + 3, "a turn event each")
        XCTAssertEqual(s.turns.last?.blocks.first?.md?.last?.text, ChatStore.demoStep(3))
        s.demoStreamNext(500)
        XCTAssertEqual(lines(), ChatStore.demoStreamTotal)
        XCTAssertFalse(s.working, "done after the last line")
        XCTAssertEqual(s.turns.last?.state, "done")
    }
}
