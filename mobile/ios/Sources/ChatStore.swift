import Foundation
import Observation
import UIKit

/// A photo or file picked in the composer, sent to the PC before the message that names it.
struct Attachment: Identifiable, Equatable {
    let id = UUID()
    var name: String
    var type: String            // MIME type
    var data: Data
    var image: UIImage?         // photos: shown as a thumbnail
    var uploaded: String?       // its path on the PC once uploaded

    static func == (a: Attachment, b: Attachment) -> Bool { a.id == b.id && a.uploaded == b.uploaded }
}

/// A message from this phone the PC hasn't listed yet: being uploaded or sent, or one that couldn't be sent.
struct Outgoing: Identifiable, Equatable {
    let clientId: String
    var text: String
    var attachments: [Attachment]
    var failed: String?
    /// the PC took it: it goes once its queue lists it or its turn shows (turns seen before it was taken don't count)
    var accepted = false
    var turnsBefore: Set<String> = []

    var id: String { clientId }
}

/// One open chat: its header, status and turns, kept live from the PC's event stream. Older turns load on demand.
/// A new chat (id "") has none of these until its first message makes it on the PC.
@Observable
@MainActor
final class ChatStore {
    private(set) var id: String
    private(set) var header: ChatHeader?
    private(set) var status: ChatStatus?
    private(set) var turns: [Turn] = []
    private(set) var more = false
    private(set) var error: APIError?
    private(set) var gone = false
    private(set) var loadingOlder = false
    /// bumps whenever a turn arrives from the stream, so the view can follow the bottom
    private(set) var liveTick = 0
    /// the phone's messages the PC has queued or just sent (from the `queue` event and each send's answer)
    private(set) var queue: [QueueItem] = []
    /// the phone's messages on their way (not yet in `queue`)
    private(set) var outbox: [Outgoing] = []
    private(set) var stopping = false
    /// a send, stop or edit that didn't work, for an alert
    var actionError: String?

    private let pairing: Pairing?
    private let demo: Bool
    private let api = APIClient()
    private var demoCards: [String: CardDetail] = [:]
    private var loaded = false

    init(id: String, pairing: Pairing?, demo: Bool) {
        self.id = id
        self.pairing = pairing
        self.demo = demo
    }

    var baseURL: URL? { pairing?.baseURL }

    var isNew: Bool { id.isEmpty }

    /// Claude is on a turn: the composer offers stop, and a message sent now waits as *queued*
    var working: Bool {
        if stopping { return false }
        if let s = status { return s.state == "working" }
        return header?.state == "working"
    }

    /// a plain chat (not a project's): the phone may rename, pin, archive and delete it
    var editable: Bool {
        guard let h = header else { return false }
        return h.role == "chat" && h.project == nil
    }

    /// Loads the newest page, then follows the event stream until the view goes away (the task is cancelled).
    func run() async {
        if demo {
            loadDemo()
            return
        }
        guard let p = pairing, !isNew else { return }
        var wait: UInt64 = 1
        while !Task.isCancelled && !gone {
            do {
                if !loaded {
                    async let h = api.chat(p, id)
                    async let page = api.turns(p, id)
                    let (hh, pp) = try await (h, page)
                    header = hh
                    upsert(pp.turns)
                    more = pp.more
                    loaded = true
                    error = nil
                }
                var q: [URLQueryItem] = []
                if let newest = turns.last?.id { q.append(URLQueryItem(name: "from", value: newest)) }
                var fresh = true
                for try await e in api.events(p, "/v1/chats/\(id)/events", query: q) {
                    if fresh {
                        // each stream starts with an empty queue (the PC only sends one that has something)
                        fresh = false
                        setQueue([])
                    }
                    handle(e)
                    error = nil
                    wait = 1
                    if gone { return }
                }
            } catch is CancellationError {
                return
            } catch let e as APIError {
                if Task.isCancelled { return }
                error = e
                if e == .notPaired { return }
                if e == .server("No such chat.") { gone = true; return }
            } catch {
                if Task.isCancelled { return }
            }
            try? await Task.sleep(nanoseconds: wait * 1_000_000_000)
            wait = min(wait * 2, 15)
        }
    }

    func handle(_ e: SSEEvent) {
        let data = Data(e.data.utf8)
        let dec = JSONDecoder()
        switch e.name {
        case "header":
            if let h = try? dec.decode(ChatHeader.self, from: data) { header = h }
        case "status":
            if let s = try? dec.decode(ChatStatus.self, from: data) { status = s }
        case "turn":
            if let t = try? dec.decode(Turn.self, from: data) {
                upsert([t])
                settleOutbox()
                liveTick += 1
            }
        case "queue":
            if let q = try? dec.decode(QueueEvent.self, from: data) {
                setQueue(q.items)
                liveTick += 1
            }
        case "gone":
            gone = true
        default:
            break
        }
    }

    /// Puts turns in by id (a turn that changed comes again whole) and keeps them in time order.
    func upsert(_ new: [Turn]) {
        var all = turns
        for t in new {
            if let i = all.firstIndex(where: { $0.id == t.id }) {
                if all[i] != t { all[i] = t }
            } else {
                all.append(t)
            }
        }
        all.sort { $0.start < $1.start }
        if all != turns { turns = all }
    }

    func loadOlder() async {
        guard more, !loadingOlder, let oldest = turns.first?.id else { return }
        if demo { more = false; return }
        guard let p = pairing else { return }
        loadingOlder = true
        defer { loadingOlder = false }
        do {
            let page = try await api.turns(p, id, before: oldest)
            upsert(page.turns)
            more = page.more
        } catch let e as APIError {
            error = e
        } catch {}
    }

    func card(_ cardId: String) async throws -> CardDetail {
        if demo {
            guard let c = demoCards[cardId] else { throw APIError.server("No such card.") }
            return c
        }
        guard let p = pairing else { throw APIError.notPaired }
        return try await api.card(p, chat: id, card: cardId)
    }

    /// the turn that holds a card (its `rev` changes when the card does)
    func rev(ofCard cardId: String) -> String? {
        turns.first { $0.blocks.contains { $0.id == cardId } }?.rev
    }

    // MARK: talking (slice 3)

    /// Sends a message: photos and files go up first, then the words naming them. A new chat is made by its first
    /// message. Nothing is lost on a failed send: the bubble stays with Retry.
    func send(text: String, attachments: [Attachment]) async {
        let words = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !words.isEmpty || !attachments.isEmpty else { return }
        let m = Outgoing(clientId: UUID().uuidString.lowercased(), text: words, attachments: attachments)
        outbox.append(m)
        liveTick += 1
        await deliver(m.clientId)
    }

    func retry(_ clientId: String) async {
        guard let i = outbox.firstIndex(where: { $0.clientId == clientId }) else { return }
        outbox[i].failed = nil
        await deliver(clientId)
    }

    func discard(_ clientId: String) {
        outbox.removeAll { $0.clientId == clientId }
    }

    private func deliver(_ clientId: String) async {
        if demo { return demoDeliver(clientId) }
        guard let p = pairing else { return fail(clientId, APIError.notPaired.message) }
        do {
            guard var m = outbox.first(where: { $0.clientId == clientId }) else { return }
            for (i, a) in m.attachments.enumerated() where a.uploaded == nil {
                let up = try await api.upload(p, a.data, name: a.name, type: a.type, chat: isNew ? "new" : id)
                m.attachments[i].uploaded = up.path
                update(clientId) { $0.attachments[i].uploaded = up.path }
            }
            let body = OutgoingBody(clientId: clientId, text: m.text, files: m.attachments.compactMap(\.uploaded))
            if isNew {
                let made = try await api.newChat(p, body)
                update(clientId) { $0.accepted = true; $0.turnsBefore = [] }
                id = made.id  // the view's task starts following the new chat
            } else {
                let before = Set(turns.map(\.id))
                let reply = try await api.send(p, chat: id, body)
                update(clientId) { $0.accepted = true; $0.turnsBefore = before }
                setQueue(reply.queue)
            }
        } catch let e as APIError {
            fail(clientId, e.message)
        } catch {
            fail(clientId, APIError.unreachable.message)
        }
    }

    /// Ends Claude's running turn (a message waiting in the queue goes next).
    func stop() async {
        guard working, !stopping else { return }
        stopping = true
        defer { stopping = false }
        if demo { return demoStop() }
        guard let p = pairing else { return }
        do {
            try await api.stop(p, chat: id)
            // the PC's status turns idle within a tick or two; until then the stop button stays hidden
            try? await Task.sleep(nanoseconds: 2_500_000_000)
        } catch let e as APIError {
            if e != .server("This chat isn't running.") { actionError = e.message }
        } catch {}
    }

    /// what a rename or pin on this phone looks like before the PC's header comes back with it
    func showEdit(_ edit: ChatEdit) {
        guard var h = header else { return }
        if let t = edit.title { h.title = t }
        if let p = edit.pinned { h.pinned = p }
        header = h
    }

    private func update(_ clientId: String, _ change: (inout Outgoing) -> Void) {
        guard let i = outbox.firstIndex(where: { $0.clientId == clientId }) else { return }
        change(&outbox[i])
    }

    private func fail(_ clientId: String, _ why: String) {
        update(clientId) { $0.failed = why }
        liveTick += 1
    }

    func setQueue(_ items: [QueueItem]) {
        if items != queue { queue = items }
        settleOutbox()
    }

    /// Drops the messages the PC has taken once they show in its queue or as a turn.
    func settleOutbox() {
        let listed = Set(queue.map(\.clientId))
        let left = outbox.filter { m in
            guard m.accepted else { return true }
            if listed.contains(m.clientId) { return false }
            return !turns.contains { $0.kind == "prompt" && !m.turnsBefore.contains($0.id) }
        }
        if left != outbox { outbox = left }
    }

    // MARK: demo

    /// The demo has no PC: a message waits as *queued* while the chat works, else it shows as a turn with a short
    /// made-up answer. Nothing leaves the phone.
    private func demoDeliver(_ clientId: String) {
        guard let m = outbox.first(where: { $0.clientId == clientId }) else { return }
        outbox.removeAll { $0.clientId == clientId }
        if isNew {
            id = "demo-new"
            loaded = true
            header = ChatHeader(id: id, title: m.text.isEmpty ? "New chat" : String(m.text.prefix(40)), role: "chat",
                                model: "Opus 5.5", modelId: "claude-opus-5-5", provider: "Claude", effort: "medium",
                                bypass: false, usage: [], branch: nil, folder: nil, running: true, state: "idle",
                                project: nil, pinned: false)
            status = ChatStatus(state: "idle", ts: Date().timeIntervalSince1970 * 1000, live: true, running: true)
        }
        if working {
            queue.append(QueueItem(clientId: clientId, text: m.text, ts: Date().timeIntervalSince1970 * 1000,
                                   state: "queued", error: nil, images: nil, files: nil))
        } else {
            demoTurn(m.text)
        }
        liveTick += 1
    }

    private func demoTurn(_ text: String) {
        let now = Date().timeIntervalSince1970 * 1000
        let answer = Block(type: "text", id: "demo-a-\(turns.count)", answer: true,
                           md: [MD(t: "p", text: "This is the demo, so nothing went to a PC. Paired with your PC, "
                                   + "Claude answers here as it does on the desktop.")])
        upsert([Turn(id: "demo-t-\(turns.count)", kind: "prompt", start: now, state: "done",
                     prompt: Prompt(text: text), open: false, blocks: [answer], rev: "demo")])
    }

    private func demoStop() {
        let now = Date().timeIntervalSince1970 * 1000
        status = ChatStatus(state: "idle", ts: now, live: true, running: true)
        header?.state = "idle"
        if let i = turns.indices.last, turns[i].state == "working" {
            turns[i].state = "done"
            if var h = turns[i].handle {
                h.title = "Stopped"
                h.since = nil
                turns[i].handle = h
            }
        }
        // what waited goes now
        let waiting = queue
        queue = []
        for q in waiting { demoTurn(q.text) }
        liveTick += 1
    }

    private func loadDemo() {
        if isNew || loaded { return }
        loaded = true
        guard let f: ChatFixture = Demo.load(id, in: "fixtures/chats") else {
            error = .server("No such chat.")
            gone = true
            return
        }
        let shift = Date().timeIntervalSince1970 * 1000 - f.now
        header = f.header
        status = f.status
        turns = f.turns.turns.map { $0.shifted(shift) }
        more = false
        demoCards = f.cards.mapValues { $0.shifted(shift) }
    }
}

private struct QueueEvent: Decodable {
    var items: [QueueItem]
}

// The demo fixtures were recorded at `now`; moving every time by the same amount keeps live clocks right.
extension Turn {
    func shifted(_ ms: Double) -> Turn {
        var t = self
        t.start += ms
        t.handle?.since = handle?.since.map { $0 + ms }
        t.blocks = blocks.map { b in
            var b = b
            b.since = b.since.map { $0 + ms }
            return b
        }
        return t
    }
}

extension CardDetail {
    func shifted(_ ms: Double) -> CardDetail {
        var c = self
        c.since = since.map { $0 + ms }
        c.rows = rows.map { r in
            var r = r
            r.since = r.since.map { $0 + ms }
            return r
        }
        return c
    }
}
