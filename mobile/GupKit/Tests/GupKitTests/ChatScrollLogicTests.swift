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

        /// a drag that moves the content up by `d` (negative: older text comes into view), then lets go with no fling
        mutating func drag(_ d: Double) {
            keeper.touchDown(top: offset)
            offset = min(max(0, offset + d), bottomOffset)
            keeper.scrolled(top: offset)
            keeper.touchUp()
            apply(keeper.rest(top: offset, gap: gap))
        }
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
        c.keeper.touchDown(top: c.offset)
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

    func testAPushTowardTheBottomFromFollowing() {
        // following, a drag toward the bottom that ends in a bounce (the content grew meanwhile): follows on
        var c = Pretend(rows: 20)
        c.keeper.touchDown(top: c.offset)
        c.grow("r19", by: 300)
        c.offset += 50
        c.keeper.scrolled(top: c.offset)
        c.keeper.touchUp()
        XCTAssertEqual(c.keeper.rest(top: c.offset, gap: c.gap), .bottom(animated: true))
    }

    func testASmallDragUpFromFollowingStops() {
        var c = Pretend(rows: 20)
        c.keeper.touchDown(top: c.offset)
        c.grow("r19", by: 200)
        c.offset -= 60
        c.keeper.scrolled(top: c.offset)
        c.keeper.touchUp()
        XCTAssertEqual(c.keeper.rest(top: c.offset, gap: c.gap), .none, "he pulled up to read: it stays")
        XCTAssertFalse(c.keeper.following)
    }

    func testOlderTurnsLoadAbove() {
        var c = Pretend(rows: 20)
        c.drag(-1_300)
        let read = c.onScreen("r3")
        c.rows.insert(contentsOf: [(id: "o0", height: 250.0), (id: "o1", height: 180.0), (id: "o2", height: 90.0)], at: 0)
        c.layout()
        XCTAssertEqual(c.onScreen("r3"), read, accuracy: 0.01, "older turns come in above without moving the screen")
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
        c.keeper.touchDown(top: c.offset)
        c.keeper.touchUp()
        c.keeper.hold()
        let row = c.onScreen("r18")
        c.grow("r18", by: 500)
        XCTAssertEqual(c.onScreen("r18"), row, accuracy: 0.01, "the fold's row doesn't move")
        XCTAssertEqual(c.keeper.rest(top: c.offset, gap: c.gap), .none, "the tap's letting go doesn't take following up again")
        c.keeper.touchDown(top: c.offset)
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
