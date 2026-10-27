import Foundation
import XCTest
#if canImport(GupKit)
@testable import GupKit
#else
@testable import GupWorks3
#endif

// a150: a message sent from the phone shows once. The PC answers a send with its queue as it was then (the message
// "queued", before the chat's mod took it); that answer can land after the stream already showed the message's turn.

@MainActor
final class SendQueueTests: XCTestCase {
    let chat = "00000009-1111-4222-8333-000000000009"

    func ev(_ name: String, _ json: String) -> SSEEvent { SSEEvent(name: name, data: json) }

    func item(_ id: String, _ text: String, ts: Double, _ state: String) -> QueueItem {
        QueueItem(clientId: id, text: text, ts: ts, state: state, error: nil, images: nil, files: nil)
    }

    func queueEvent(_ items: [QueueItem]) -> SSEEvent {
        SSEEvent(name: "queue", data: String(decoding: try! JSONEncoder().encode(["items": items]), as: UTF8.self))
    }

    func turn(_ id: String, _ text: String, start: Double, state: String = "working") -> SSEEvent {
        let t = Turn(id: id, kind: "prompt", start: start, state: state, prompt: Prompt(text: text), open: true,
                     blocks: [], rev: "r-\(id)-\(state)")
        return SSEEvent(name: "turn", data: String(decoding: try! JSONEncoder().encode(t), as: UTF8.self))
    }

    /// what the screen draws: the turns' own prompts, then the queue's and the outbox's bubbles
    func bubbles(_ s: ChatStore) -> [String] {
        s.turns.compactMap(\.prompt.text) + s.waiting.map { "\($0.state): \($0.text)" } + s.sending.map { "sending: \($0.text)" }
    }

    /// A store with one message on its way (the PC not reached yet), as `send` leaves it before the answer.
    func sending(_ text: String, earlier: Bool = true) async -> (ChatStore, String) {
        let s = ChatStore(id: chat, pairing: nil, demo: false)
        if earlier { s.handle(turn("t-0", "Earlier", start: 1_000, state: "done")) }
        await s.send(text: text, attachments: [])  // no PC here: it stays in the outbox
        return (s, s.outbox[0].clientId)
    }

    // The bug: the turn started right away; the stream showed it before the send's answer came back.
    func testALateSendAnswerDoesNotBringBackAQueuedCopy() async {
        let (s, id) = await sending("Go to the main chat")
        let before = Set(s.turns.map(\.id))
        s.handle(queueEvent([item(id, "Go to the main chat", ts: 5_000, "queued")]))
        s.handle(queueEvent([item(id, "Go to the main chat", ts: 5_000, "sent")]))
        s.handle(turn("t-1", "Go to the main chat", start: 6_000))
        s.handle(queueEvent([]))
        s.took(id, before: before, queue: [item(id, "Go to the main chat", ts: 5_000, "queued")])  // the late answer
        XCTAssertEqual(bubbles(s), ["Earlier", "Go to the main chat"])
    }

    // Same, when the stream never listed it (it was on the PC for less than one look of the stream).
    func testALateAnswerWhenTheStreamNeverListedIt() async {
        let (s, id) = await sending("Quick one")
        let before = Set(s.turns.map(\.id))
        s.handle(turn("t-1", "Quick one", start: 6_000))
        s.took(id, before: before, queue: [item(id, "Quick one", ts: 5_000, "queued")])
        XCTAssertEqual(bubbles(s), ["Earlier", "Quick one"])
    }

    // The answer first, then the turn: the queued look goes when the turn shows (no stream queue event needed).
    func testTheAnswerFirstThenTheTurn() async {
        let (s, id) = await sending("Hello")
        let before = Set(s.turns.map(\.id))
        s.took(id, before: before, queue: [item(id, "Hello", ts: 5_000, "queued")])
        XCTAssertEqual(bubbles(s), ["Earlier", "queued: Hello"])
        s.handle(turn("t-1", "Hello", start: 6_000))
        XCTAssertEqual(bubbles(s), ["Earlier", "Hello"])
    }

    // Claude is working: the message really waits. It shows once as queued, then once as its turn.
    func testARealQueuedMessageShowsOnceThenBecomesItsTurn() async {
        let (s, id) = await sending("Next thing")
        s.handle(ev("status", #"{"state":"working","ts":1,"live":true,"running":true}"#))
        let before = Set(s.turns.map(\.id))
        s.took(id, before: before, queue: [item(id, "Next thing", ts: 5_000, "queued")])
        XCTAssertEqual(bubbles(s), ["Earlier", "queued: Next thing"])
        s.handle(queueEvent([item(id, "Next thing", ts: 5_000, "queued")]))
        XCTAssertEqual(bubbles(s), ["Earlier", "queued: Next thing"], "the stream's copy replaces the answer's")
        XCTAssertTrue(s.outbox.isEmpty)
        s.handle(turn("t-0", "Earlier", start: 1_000, state: "working"))  // the running turn changes: not ours
        XCTAssertEqual(bubbles(s), ["Earlier", "queued: Next thing"])
        s.handle(queueEvent([item(id, "Next thing", ts: 5_000, "sent")]))
        XCTAssertEqual(bubbles(s), ["Earlier", "sent: Next thing"])
        s.handle(turn("t-1", "Next thing", start: 9_000))
        XCTAssertEqual(bubbles(s), ["Earlier", "Next thing"], "its turn is there: the sent copy isn't drawn too")
        s.handle(queueEvent([]))
        XCTAssertEqual(bubbles(s), ["Earlier", "Next thing"])
    }

    // The stream listed it before the answer came: the answer adds nothing.
    func testTheStreamFirstThenTheAnswer() async {
        let (s, id) = await sending("Later")
        s.handle(ev("status", #"{"state":"working","ts":1,"live":true,"running":true}"#))
        let before = Set(s.turns.map(\.id))
        s.handle(queueEvent([item(id, "Later", ts: 5_000, "queued")]))
        XCTAssertEqual(bubbles(s), ["Earlier", "queued: Later"], "listed by the PC: the sending copy goes")
        s.took(id, before: before, queue: [item(id, "Later", ts: 5_000, "queued")])
        XCTAssertEqual(bubbles(s), ["Earlier", "queued: Later"])
    }

    // A reconnect: each stream starts with an empty queue, then the PC lists what still waits.
    func testAfterAReconnect() async {
        let (s, id) = await sending("Still waiting")
        let before = Set(s.turns.map(\.id))
        s.took(id, before: before, queue: [item(id, "Still waiting", ts: 5_000, "queued")])
        s.setQueue([])  // a new stream
        XCTAssertEqual(bubbles(s), ["Earlier", "queued: Still waiting"], "not dropped by an empty start")
        s.handle(queueEvent([item(id, "Still waiting", ts: 5_000, "queued")]))
        XCTAssertEqual(bubbles(s), ["Earlier", "queued: Still waiting"])
        s.setQueue([])  // another reconnect, while its turn started
        s.handle(turn("t-1", "Still waiting", start: 7_000))
        XCTAssertEqual(bubbles(s), ["Earlier", "Still waiting"])
    }

    // A send whose answer got lost (it failed on the phone) but the PC has it: the PC's copy wins, no "Not sent".
    func testAFailedSendThePCListsGoes() async {
        let (s, id) = await sending("Lost answer")
        XCTAssertNotNil(s.outbox.first?.failed)
        s.handle(queueEvent([item(id, "Lost answer", ts: 5_000, "queued")]))
        XCTAssertEqual(bubbles(s), ["Earlier", "queued: Lost answer"])
    }

    // An older identical message doesn't hide a newer one that waits; a sent one with no turn yet still shows.
    func testOnlyATurnAfterTheMessageCounts() async {
        let s = ChatStore(id: chat, pairing: nil, demo: false)
        s.handle(turn("t-0", "yes", start: 1_000, state: "done"))
        s.handle(queueEvent([item("c-2", "yes", ts: 5_000, "sent")]))
        XCTAssertEqual(bubbles(s), ["yes", "sent: yes"])
        s.handle(turn("t-1", "yes", start: 6_000))
        XCTAssertEqual(bubbles(s), ["yes", "yes"])
    }
}
