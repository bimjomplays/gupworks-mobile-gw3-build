import Foundation
import Observation
#if canImport(UIKit)
import UIKit
#endif

/// A photo or file picked in the composer, sent to the PC before the message that names it.
struct Attachment: Identifiable, Equatable {
    let id = UUID()
    var name: String
    var type: String            // MIME type
    var data: Data
    #if canImport(UIKit)
    var image: UIImage?         // photos: shown as a thumbnail
    #else
    var image: Never?           // no pictures in the Linux tests
    #endif
    var uploaded: String?       // its path on the PC once uploaded
    var duration: Double? = nil // a voice memo: its length in seconds (a161)
    var peaks: [Int]? = nil     // and its loudness across it, 0-100 each, for the player
    var local: URL? = nil       // and its file on the phone, played in the bubble while it sends

    static func == (a: Attachment, b: Attachment) -> Bool { a.id == b.id && a.uploaded == b.uploaded }
}

/// A message from this phone the PC's stream hasn't listed yet: being uploaded or sent, or one that couldn't be sent.
struct Outgoing: Identifiable, Equatable {
    let clientId: String
    var text: String
    var attachments: [Attachment]
    var failed: String?
    /// the PC took it: it goes once the stream's queue lists it or its turn shows (turns seen before it was sent
    /// don't count)
    var accepted = false
    var turnsBefore: Set<String> = []
    /// how the send's answer listed it (queued or sent): drawn as that until the stream says more
    var listed: QueueItem?

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
    /// the phone's messages the PC has queued or just sent, as its stream's `queue` event lists them (only the
    /// stream: a send's answer can be older than what the stream already said)
    private(set) var queue: [QueueItem] = []
    /// the phone's messages on their way (not yet in `queue`)
    private(set) var outbox: [Outgoing] = []

    /// The phone's messages to draw after the turns, each once: the stream's queue without the sent ones whose turn
    /// already shows, then the ones the PC took that the stream hasn't listed yet.
    var waiting: [QueueItem] {
        queue.filter { !hasTurn($0) } + outbox.compactMap { $0.accepted ? $0.listed : nil }
    }

    /// the phone's messages still being sent, or not sent (Retry)
    var sending: [Outgoing] {
        outbox.filter { !($0.accepted && $0.listed != nil) }
    }
    private(set) var stopping = false
    /// a send, stop or edit that didn't work, for an alert
    var actionError: String?

    // slice 4
    /// the composer's words (a rewind, Ask btw or a command with words put text here)
    var draft = ""
    /// bumps when something put words in the box: the composer takes the keyboard
    private(set) var focusTick = 0
    /// an answer on its way: the dialog's buttons wait
    private(set) var answering = false
    /// a Bypass flip on its way (Shift+Tab on the PC takes a moment)
    private(set) var switchingMode = false
    private(set) var models: [ModelInfo] = []
    /// what a new chat starts on (the PC's default), until one is picked in the gauge's sheet
    private(set) var defaultPick: PickBody?
    /// a new chat's model and effort, picked before its first message
    private(set) var newPick: PickBody?
    /// a temporary chat: made with `temporary`, deleted for good when you leave it (5b)
    var temporary = false
    /// the chat was made by its first message (the shell keeps its id, to show it in the menu or delete it)
    var onMade: ((String) -> Void)?
    private(set) var commands: CommandsReply?
    /// /rewind's confirm page, open on the PC for the prompt `rewindText`
    private(set) var rewindDialog: Dialog?
    private(set) var rewindText = ""
    /// the turn the open confirm page rewinds to
    private var rewindTurn = ""
    private(set) var rewinding = false
    /// the dialog just answered: an older status that still has it doesn't bring it back
    private var answered: (sig: String, at: Date)?

    private let pairing: Pairing?
    private let demo: Bool
    private let api = APIClient()
    /// D8: the composer's recorder
    #if canImport(AVFoundation)
    let voice: VoiceController
    #endif
    private var demoCards: [String: CardDetail] = [:]
    private var loaded = false

    init(id: String, pairing: Pairing?, demo: Bool) {
        self.id = id
        self.pairing = pairing
        self.demo = demo
        #if canImport(AVFoundation)
        self.voice = VoiceController(pairing: pairing, demo: demo)
        #endif
    }

    var baseURL: URL? { pairing.map { Routes.shared.current(for: $0.baseURL) } }  // where pictures load now

    var isNew: Bool { id.isEmpty }

    /// Claude is on a turn: the composer offers stop, and a message sent now waits as *queued*
    var working: Bool {
        if stopping { return false }
        if let s = status { return s.state == "working" }
        return header?.state == "working"
    }

    /// what Claude asks on its screen now, for the needs-you card
    var dialog: Dialog? {
        guard let s = status, s.live, let d = s.dialog, d.kind != "rewind" else { return nil }
        if let a = answered, a.sig == d.sig, Date().timeIntervalSince(a.at) < 6 { return nil }
        return d
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
        case "cut":
            if let c = try? dec.decode(CutEvent.self, from: data) { cut(c.ids) }
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

    /// Turns rewound away (a Restore here or on the PC) leave the list.
    func cut(_ ids: [String]) {
        let gone = Set(ids)
        if turns.contains(where: { gone.contains($0.id) }) { turns.removeAll { gone.contains($0.id) } }
    }

    /// A Restore lands on the chosen prompt: it and everything after it go (the PC says the same a moment later).
    func cutFrom(_ id: String) {
        guard let i = turns.firstIndex(where: { $0.id == id }) else { return }
        cut(turns[i...].map(\.id))
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
                let pick = newPick
                let made = try await api.newChat(p, NewChatBody(clientId: clientId, text: body.text, files: body.files,
                                                               model: pick?.model, effort: pick?.effort,
                                                               temporary: temporary ? true : nil))
                update(clientId) { $0.accepted = true; $0.turnsBefore = [] }
                id = made.id  // the view's task starts following the new chat
                onMade?(made.id)
            } else {
                let before = Set(turns.map(\.id))
                let reply = try await api.send(p, chat: id, body)
                took(clientId, before: before, queue: reply.queue)
            }
        } catch let e as APIError {
            fail(clientId, e.message)
        } catch {
            fail(clientId, APIError.from(error).message)
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

    // MARK: answering, picking, commands (slice 4)

    /// Answers the needs-you card as the desktop's button would. A chat on an older hold turns the card into
    /// "Answer this on the PC"; a question that changed meanwhile shows the new one.
    func answer(_ a: DialogAnswer) async {
        guard !answering else { return }
        answering = true
        defer { answering = false }
        if demo { return demoAnswer(a) }
        guard let p = pairing else { return }
        do {
            let reply = try await api.answer(p, chat: id, a)
            answered = (a.sig, Date())
            showDialog(reply.dialog)
        } catch APIError.refused(let text, let old, let newer) {
            if old {
                markOld()
            } else {
                if let newer { showDialog(newer) }
                actionError = text
            }
        } catch let e as APIError {
            actionError = e.message
        } catch {
            actionError = APIError.from(error).message
        }
    }

    /// the dialog on the PC's screen after an answer: the next tab of a question, or none (Claude goes on)
    private func showDialog(_ d: Dialog?) {
        guard var s = status else { return }
        s.dialog = d
        if d == nil {
            s.waiting = nil
            s.state = "working"
            header?.state = "working"
        }
        status = s
        liveTick += 1
    }

    private func markOld() {
        guard var s = status, var d = s.dialog else { return }
        d.answerable = false
        s.dialog = d
        status = s
        header?.door = false
    }

    /// Bypass on or off: the red word in the title follows once the PC's mode line says so.
    func setBypass(_ on: Bool) async {
        guard !switchingMode, header?.bypass != on else { return }
        switchingMode = true
        defer { switchingMode = false }
        if demo {
            try? await Task.sleep(nanoseconds: 400_000_000)
            header?.bypass = on
            header?.mode = on ? "bypass" : "manual"
            return
        }
        guard let p = pairing else { return }
        do {
            let r = try await api.setBypass(p, chat: id, on)
            header?.bypass = r.bypass
            header?.mode = r.mode
        } catch APIError.refused(_, true, _) {
            header?.door = false
            actionError = "This chat runs on an older GupWorks. Change Bypass on the PC, or restart the chat there."
        } catch let e as APIError {
            actionError = e.message
        } catch {
            actionError = APIError.from(error).message
        }
    }

    func loadModels() async {
        if demo {
            if models.isEmpty, let m: ModelsReply = Demo.load("models") {
                models = m.models
                defaultPick = m.default
            }
            return
        }
        guard let p = pairing, let m = try? await api.models(p) else { return }
        models = m.models
        defaultPick = m.default
    }

    /// The model the next turn runs on: the chat's, or a new chat's pick (else the PC's default).
    var currentModel: ModelInfo? {
        if isNew {
            let want = newPick?.model ?? defaultPick?.model
            return models.first { $0.id == want } ?? models.first
        }
        guard let h = header else { return nil }
        return models.first { $0.id == h.modelId } ?? models.first { $0.label == h.model }
    }

    /// the effort the next turn runs at
    var currentEffort: String? {
        if isNew {
            guard let m = currentModel else { return newPick?.effort ?? defaultPick?.effort }
            let want = newPick?.effort ?? (m.id == defaultPick?.model ? defaultPick?.effort : nil)
            return want.flatMap { m.efforts.contains($0) ? $0 : nil } ?? Self.defaultEffort(m.efforts)
        }
        return header?.effort
    }

    /// The model and effort for the next turn, as the desktop's picker sets them.
    func pick(model: ModelInfo, effort: String?) async {
        let effort = effort.flatMap { model.efforts.contains($0) ? $0 : nil } ?? Self.defaultEffort(model.efforts)
        if isNew {  // kept on the phone; the first message makes the chat on it
            newPick = PickBody(model: model.id, effort: effort)
            return
        }
        let before = header
        header?.model = model.label
        header?.modelId = model.id
        header?.provider = model.provider
        header?.effort = effort
        header?.pending = true
        if demo { return }
        guard let p = pairing else { return }
        do {
            let r = try await api.pick(p, chat: id, PickBody(model: model.id, effort: effort))
            header?.effort = r.effort
        } catch let e as APIError {
            header = before
            actionError = e.message
        } catch {
            header = before
            actionError = APIError.from(error).message
        }
    }

    /// the desktop's choice when a model has no effort picked: high, else medium, else the first
    nonisolated static func defaultEffort(_ efforts: [String]) -> String {
        efforts.contains("high") ? "high" : efforts.contains("medium") ? "medium" : efforts.first ?? ""
    }

    func loadCommands() async {
        if demo {
            if commands == nil { commands = Demo.load("commands") }
            return
        }
        guard let p = pairing else { return }
        let c: CommandsReply?
        if isNew { c = try? await api.commands(p) } else { c = try? await api.commands(p, chat: id) }
        if let c { commands = c }
    }

    /// Pins a command, or unpins it: the desktop's palette has the same pins.
    func togglePin(_ name: String) async {
        guard var c = commands else { return }
        let before = c.pinned
        if let i = c.pinned.firstIndex(of: name) { c.pinned.remove(at: i) } else { c.pinned.append(name) }
        commands = c
        if demo { return }
        guard let p = pairing else { return }
        do {
            let r = try await api.setPins(p, c.pinned)
            commands?.pinned = r.pinned
            commands?.recent = r.recent
        } catch let e as APIError {
            commands?.pinned = before
            actionError = e.message
        } catch {
            commands?.pinned = before
            actionError = APIError.from(error).message
        }
    }

    /// A command from D4: one that needs words goes into the box with the keyboard up; the rest runs now.
    func run(_ cmd: CommandInfo) async {
        if cmd.needsArgs {
            put("/\(cmd.name) ")
            return
        }
        if var c = commands {  // first in Recent, as the PC lists it next time
            c.recent.removeAll { $0 == cmd.name }
            c.recent.insert(cmd.name, at: 0)
            commands = c
        }
        await send(text: "/\(cmd.name)", attachments: [])
    }

    /// words into the composer, keyboard up
    func put(_ text: String) {
        draft = text
        focusTick += 1
    }

    /// the box takes the keyboard (5a: a new chat opens with it up)
    func focus() {
        focusTick += 1
    }

    /// D7's Rewind to here: opens /rewind on the PC at that prompt; its confirm page comes back to answer.
    func startRewind(_ turn: Turn) async {
        guard !rewinding, turn.rewind == true else { return }
        rewinding = true
        defer { rewinding = false }
        if demo {
            if let r: RewindReply = Demo.load("rewind") {
                rewindText = turn.prompt.text ?? r.text
                rewindTurn = turn.id
                rewindDialog = r.dialog
            }
            return
        }
        guard let p = pairing else { return }
        do {
            let r = try await api.rewind(p, chat: id, turn: turn.id)
            rewindText = r.text
            rewindTurn = turn.id
            rewindDialog = r.dialog
        } catch APIError.refused(_, true, _) {
            actionError = "This chat runs on an older GupWorks. Rewind it on the PC, or restart the chat there."
        } catch let e as APIError {
            actionError = e.message
        } catch {
            actionError = APIError.from(error).message
        }
    }

    /// One of the confirm page's choices: Restore puts the message back in the phone's box to edit and send.
    func finishRewind(_ c: Dialog.Choice?) async {
        guard let d = rewindDialog else { return }
        rewindDialog = nil
        let restore = c.map { $0.label.hasPrefix("Restore") && $0.label.lowercased().contains("conversation") } ?? false
        let lines = rewindText.components(separatedBy: "\n").count
        if demo {
            if restore { put(rewindText); cutFrom(rewindTurn) }
            return
        }
        guard let p = pairing, let sig = d.sig else { return }
        let a = c.map { DialogAnswer(sig: sig, choice: $0.n, lines: lines) } ?? DialogAnswer(sig: sig, action: "skip")
        do {
            _ = try await api.answer(p, chat: id, a)
            if restore { put(rewindText); cutFrom(rewindTurn) }
        } catch let e as APIError {
            actionError = e.message
        } catch {
            actionError = APIError.from(error).message
        }
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

    /// The PC took a message: its answer lists the queue as it was then. Only this message's own entry is kept, on
    /// the outbox copy, which goes as soon as the stream lists it or its turn shows (that may already be so: the
    /// answer can come back after the stream showed the turn). The answer never replaces the stream's queue.
    func took(_ clientId: String, before: Set<String>, queue items: [QueueItem]) {
        update(clientId) {
            $0.accepted = true
            $0.failed = nil
            $0.turnsBefore = before
            $0.listed = items.first { $0.clientId == clientId }
        }
        settleOutbox()
    }

    /// the stream's queue (each stream starts with an empty one)
    func setQueue(_ items: [QueueItem]) {
        if items != queue { queue = items }
        settleOutbox()
    }

    /// Drops the outbox's messages the stream lists (it has them, even when the send's answer was lost) and the
    /// taken ones whose turn shows.
    func settleOutbox() {
        let listed = Set(queue.map(\.clientId))
        let left = outbox.filter { m in
            if listed.contains(m.clientId) { return false }
            guard m.accepted else { return true }
            return !turns.contains { $0.kind == "prompt" && !m.turnsBefore.contains($0.id) }
        }
        if left != outbox { outbox = left }
    }

    /// A sent message whose turn the stream already showed (a prompt with its words that started after the PC
    /// got it; the PC drops it a moment later, or not at all when its words came out different).
    private func hasTurn(_ q: QueueItem) -> Bool {
        let words = q.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard q.state == "sent", !words.isEmpty else { return false }
        return turns.contains { t in
            t.kind == "prompt" && t.start >= q.ts
                && (t.prompt.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix(words)
        }
    }

    // MARK: demo

    /// The demo answers itself: the card goes and Claude works on (nothing leaves the phone).
    private func demoAnswer(_ a: DialogAnswer) {
        answered = (a.sig, Date())
        showDialog(nil)
    }

    /// The demo has no PC: a message waits as *queued* while the chat works (taken as a PC's answer lists it), else it
    /// shows as a turn with a short made-up answer. Nothing leaves the phone.
    private func demoDeliver(_ clientId: String) {
        guard let m = outbox.first(where: { $0.clientId == clientId }) else { return }
        if working {
            took(clientId, before: Set(turns.map(\.id)),
                 queue: [QueueItem(clientId: clientId, text: m.text, ts: Date().timeIntervalSince1970 * 1000,
                                   state: "queued", error: nil, images: nil, files: nil)])
            liveTick += 1
            return
        }
        outbox.removeAll { $0.clientId == clientId }
        if isNew {
            let m0 = currentModel, effort = currentEffort ?? "medium"
            id = "demo-new"
            loaded = true
            header = ChatHeader(id: id, title: m.text.isEmpty ? "New chat" : String(m.text.prefix(40)), role: "chat",
                                model: m0?.label ?? "Opus 5.5", modelId: m0?.id ?? "claude-opus-5-5",
                                provider: m0?.provider ?? "Claude", effort: effort,
                                bypass: false, usage: [], branch: nil, folder: nil, running: true, state: "idle",
                                project: nil, pinned: false)
            status = ChatStatus(state: "idle", ts: Date().timeIntervalSince1970 * 1000, live: true, running: true)
            onMade?(id)
        }
        demoTurn(m.text, audio: Self.demoAudio(m.attachments))
        liveTick += 1
    }

    /// the demo's sent sounds as the PC lists them (a161): each written to a temporary file the bubble plays
    static func demoAudio(_ attachments: [Attachment]) -> [MDItem]? {
        let items: [MDItem] = attachments.filter { MemoMath.isAudio(type: $0.type, name: $0.name) }.compactMap { a in
            let file = FileManager.default.temporaryDirectory.appendingPathComponent("demo-sent-" + a.name)
            guard (try? a.data.write(to: file)) != nil else { return nil }
            return MDItem(kind: "audio", url: file.absoluteString, name: a.name, duration: a.duration, peaks: a.peaks)
        }
        return items.isEmpty ? nil : items
    }

    private func demoTurn(_ text: String, audio: [MDItem]? = nil) {
        let now = Date().timeIntervalSince1970 * 1000
        let answer = Block(type: "text", id: "demo-a-\(turns.count)", answer: true,
                           md: [MD(t: "p", text: "This is the demo, so nothing went to a PC. Paired with your PC, "
                                   + "Claude answers here as it does on the desktop.")])
        upsert([Turn(id: "demo-t-\(turns.count)", kind: "prompt", start: now, state: "done",
                     prompt: Prompt(text: text, audio: audio), open: false, blocks: [answer], rev: "demo")])
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
        let waited = waiting
        queue = []
        outbox.removeAll { $0.accepted }
        for q in waited { demoTurn(q.text) }
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
        if let at = f.header.cache?.at { header?.cache?.at = at + shift }
        header?.usage = Demo.shiftResets(f.header.usage, by: shift)
        status = f.status
        turns = f.turns.turns.map { $0.shifted(shift) }
        more = false
        demoCards = f.cards.mapValues { $0.shifted(shift) }
    }
}

private struct CutEvent: Decodable {
    var ids: [String]
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
