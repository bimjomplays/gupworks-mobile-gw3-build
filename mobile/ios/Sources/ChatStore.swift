import Foundation
import Observation

/// One open chat: its header, status and turns, kept live from the PC's event stream. Older turns load on demand.
@Observable
@MainActor
final class ChatStore {
    let id: String
    private(set) var header: ChatHeader?
    private(set) var status: ChatStatus?
    private(set) var turns: [Turn] = []
    private(set) var more = false
    private(set) var error: APIError?
    private(set) var gone = false
    private(set) var loadingOlder = false
    /// bumps whenever a turn arrives from the stream, so the view can follow the bottom
    private(set) var liveTick = 0

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

    /// Loads the newest page, then follows the event stream until the view goes away (the task is cancelled).
    func run() async {
        if demo {
            loadDemo()
            return
        }
        guard let p = pairing else { return }
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
                for try await e in api.events(p, "/v1/chats/\(id)/events", query: q) {
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

    // MARK: demo

    private func loadDemo() {
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
