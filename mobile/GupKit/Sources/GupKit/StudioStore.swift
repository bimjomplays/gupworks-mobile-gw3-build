import Foundation
import Observation

/// The Studio home and a channel's page (a180): the channels, one channel's videos and style guide. Read from
/// gw3-phone's /v1/studio routes every few seconds while shown; the demo answers from mobile/fixtures/studio/.
@Observable
@MainActor
final class StudioStore {
    private(set) var home: StudioHome?
    private(set) var channels: [String: StudioChannel] = [:]
    private(set) var error: APIError?
    var actionError: String?

    let pairing: Pairing?
    let demo: Bool
    let api = APIClient()

    init(pairing: Pairing?, demo: Bool) {
        self.pairing = pairing
        self.demo = demo
    }

    var baseURL: URL? { pairing.map { Routes.shared.current(for: $0.baseURL) } }

    func refresh() async {
        if demo {
            home = Demo.load("home", in: "fixtures/studio")
            return
        }
        guard let p = pairing else { return }
        do {
            home = try await api.studio(p)
            error = nil
        } catch {
            note(error)
        }
    }

    func refresh(channel pid: String) async {
        if demo {
            channels[pid] = channels[pid] ?? Demo.load(pid, in: "fixtures/studio")
            return
        }
        guard let p = pairing else { return }
        do {
            channels[pid] = try await api.studioChannel(p, pid)
            error = nil
        } catch {
            note(error)
        }
    }

    /// Reads `load` again every `seconds` until the task is cancelled (the screen went away).
    func follow(every seconds: Double = 5, _ load: @escaping () async -> Void) async {
        while !Task.isCancelled {
            await load()
            if demo { return }
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
        }
    }

    /// A new video in a channel; its card, to open it.
    func newVideo(in pid: String, title: String, kind: String) async -> StudioCard? {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return nil }
        if demo {
            let card = StudioCard(id: "v\(Int.random(in: 100...999))", title: title, kind: kind, stage: "brief",
                                  stageIndex: 0, stageName: "Brief", stages: 8, chatId: nil, chatState: "idle",
                                  updated: Date().timeIntervalSince1970 * 1000, jobs: [], readonly: false)
            if var c = channels[pid] {
                if kind == "short" { c.shortsList.insert(card, at: 0) } else { c.videos.insert(card, at: 0) }
                channels[pid] = c
            }
            return card
        }
        guard let p = pairing else { return nil }
        do {
            let card = try await api.studioNewVideo(p, pid, StudioNewVideo(title: title, kind: kind))
            await refresh(channel: pid)
            return card
        } catch {
            actionError = APIError.from(error).message
            return nil
        }
    }

    /// A new channel (a Studio project with its own videos folder and style guide); its id.
    func newChannel(name: String, about: String) async -> String? {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !demo, let p = pairing else { return nil }
        do {
            let r = try await api.studioNewChannel(p, StudioNewChannel(name: name, about: about))
            await refresh()
            return r.projectId
        } catch {
            actionError = APIError.from(error).message
            return nil
        }
    }

    private func note(_ error: Error) {
        let e = APIError.from(error)
        if Task.isCancelled || e.isCancelled { return }
        self.error = e
    }
}

/// One video in Studio (a180): its overview and the stage answers the phone shows, and every action on them. The
/// stage's own calls go to the PC's Studio service as the desktop's stage pages do; what the video chat should do
/// (a rewrite, a deeper look) is sent to the video chat in the desktop's own words. The Edit stage (a181) uses
/// `call` and `send` too.
@Observable
@MainActor
final class StudioVideoStore {
    let projectId: String
    let videoId: String
    private(set) var overview: StudioOverview?
    private(set) var brief: StudioBrief?
    private(set) var research: StudioResearch?
    private(set) var script: StudioScript?
    private(set) var voice: StudioVoice?
    private(set) var visuals: StudioVisuals?
    private(set) var finish: StudioFinish?
    private(set) var error: APIError?
    /// a call the PC refused or never got, for an alert
    var actionError: String?
    /// a short line to show after an action went through ("Sent to the video chat")
    var notice: String?
    /// actions on their way (their buttons show a spinner)
    private(set) var busy: Set<String> = []

    let pairing: Pairing?
    let demo: Bool
    let api = APIClient()

    init(projectId: String, videoId: String, pairing: Pairing?, demo: Bool) {
        self.projectId = projectId
        self.videoId = videoId
        self.pairing = pairing
        self.demo = demo
    }

    var baseURL: URL? { pairing.map { Routes.shared.current(for: $0.baseURL) } }
    var title: String { overview?.card.title ?? "Video" }
    var chatId: String? { overview?.card.chatId }
    var readonly: Bool { overview?.card.readonly ?? false }

    private var demoFolder: String { "fixtures/studio/\(projectId)/\(videoId)" }

    // MARK: reading

    func refresh() async {
        if demo {
            overview = Demo.load("overview", in: demoFolder)
            return
        }
        guard let p = pairing else { return }
        do {
            overview = try await api.studioOverview(p, projectId, videoId)
            error = nil
        } catch {
            note(error)
        }
    }

    /// A stage's answer, read again.
    func load(_ stage: String) async {
        if demo {
            if !loaded(stage) { loadDemo(stage) }
            return
        }
        guard let p = pairing else { return }
        do {
            switch stage {
            case "brief": brief = try await api.studioCall(p, projectId, videoId, "brief")
            case "research": research = try await api.studioCall(p, projectId, videoId, "research")
            case "script": script = try await api.studioCall(p, projectId, videoId, "script")
            case "voice": voice = try await api.studioCall(p, projectId, videoId, "voice")
            case "visuals": visuals = try await api.studioCall(p, projectId, videoId, "visuals")
            case "finish": finish = try await api.studioCall(p, projectId, videoId, "finish")
            default: return
            }
            error = nil
        } catch {
            note(error)
        }
    }

    /// Something loaded already for the stage (the demo keeps its local changes)
    private func loaded(_ stage: String) -> Bool {
        switch stage {
        case "brief": return brief != nil
        case "research": return research != nil
        case "script": return script != nil
        case "voice": return voice != nil
        case "visuals": return visuals != nil
        case "finish": return finish != nil
        default: return true
        }
    }

    private func loadDemo(_ stage: String) {
        switch stage {
        case "brief": brief = Demo.load("brief", in: demoFolder)
        case "research": research = Demo.load("research", in: demoFolder)
        case "script": script = Demo.load("script", in: demoFolder)
        case "voice": voice = Demo.load("voice", in: demoFolder)
        case "visuals": visuals = Demo.load("visuals", in: demoFolder)
        case "finish": finish = Demo.load("finish", in: demoFolder)
        default: break
        }
    }

    /// Reads the stage (and the overview) every few seconds while it is shown: jobs and the chat's changes land.
    func follow(_ stage: String?, every seconds: Double = 4) async {
        if let stage { await open(stage) }
        while !Task.isCancelled {
            if let stage { await load(stage) } else { await refresh() }
            if demo { return }
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
        }
    }

    // MARK: calls

    /// A stage route; nil (with actionError set) when the PC refused it. The Edit stage (a181) calls this too.
    func call<T: Decodable>(_ route: String, _ body: [String: StudioValue] = [:], busyKey: String? = nil) async -> T? {
        guard let p = pairing else { return nil }
        let key = busyKey ?? route
        busy.insert(key)
        defer { busy.remove(key) }
        do {
            return try await api.studioCall(p, projectId, videoId, route, body)
        } catch {
            let e = APIError.from(error)
            if !e.isCancelled { actionError = e.message }
            return nil
        }
    }

    /// You opened a stage: the video chat hears where you are with his next message (as on the desktop).
    func open(_ stage: String) async {
        if demo { return }
        let _: StudioAny? = await call("video/open", ["stage": .string(stage)], busyKey: "open")
    }

    /// What is selected (a script line, a fact): the video chat's context chip and its next message's context.
    func select(stage: String, kind: String, id: String, label: String) async {
        if demo { return }
        let sel: [String: StudioValue] = ["stage": .string(stage), "kind": .string(kind), "id": .string(id),
                                          "label": .string(label)]
        let _: StudioAny? = await call("video/select", ["selection": .object(sel)], busyKey: "select")
    }

    func clearSelection() async {
        if demo { return }
        let _: StudioAny? = await call("video/select", ["selection": .null], busyKey: "select")
    }

    /// Words for the video chat, as your own message (it starts if it isn't running).
    @discardableResult
    func send(_ text: String) async -> Bool {
        if demo {
            notice = "Sent to the video chat"
            return true
        }
        guard let p = pairing, let chat = chatId else {
            actionError = "This video has no chat yet."
            return false
        }
        busy.insert("send")
        defer { busy.remove("send") }
        do {
            _ = try await api.send(p, chat: chat, OutgoingBody(clientId: "studio-" + UUID().uuidString.lowercased(),
                                                               text: text, files: []))
            notice = "Sent to the video chat"
            return true
        } catch {
            actionError = APIError.from(error).message
            return false
        }
    }

    /// Answers the video chat's question from its card (one of its options).
    func answer(_ need: StudioNeed, choice: Int) async -> Bool {
        if demo {
            if var o = overview { o.needs = nil; o.card.needs = nil; overview = o }
            return true
        }
        guard let p = pairing, let chat = need.chatId, let sig = need.sig else { return false }
        busy.insert("answer")
        defer { busy.remove("answer") }
        do {
            _ = try await api.answer(p, chat: chat, DialogAnswer(sig: sig, choice: choice))
            await refresh()
            return true
        } catch {
            actionError = APIError.from(error).message
            return false
        }
    }

    // MARK: Brief and Research

    func saveBrief(_ patch: [String: String]) async {
        if demo {
            if var b = brief {
                for (k, v) in patch {
                    switch k {
                    case "topic": b.brief.topic = v
                    case "angle": b.brief.angle = v
                    case "audience": b.brief.audience = v
                    case "length": b.brief.length = v
                    case "format": b.brief.format = v
                    default: break
                    }
                }
                brief = b
            }
            return
        }
        let body = patch.mapValues { StudioValue.string($0) }
        if let b: StudioBrief = await call("brief/save", ["patch": .object(body)]) { brief = b }
    }

    /// Research threads for the brief's open questions.
    func startResearch() async {
        if demo { notice = "Started research"; return }
        struct Started: Decodable { var threads: [String] }
        if let r: Started = await call("research/start") {
            notice = "Started \(Format.plural(r.threads.count, "research thread"))"
            await load("research")
            await load("brief")
        }
    }

    /// Pins or rejects a research item (the same mark again takes it back).
    func mark(kind: String, id: String, mark: String?) async {
        if demo {
            demoMark(kind: kind, id: id, mark: mark)
            return
        }
        let _: StudioAny? = await call("research/mark", ["kind": .string(kind), "id": .string(id),
                                                         "mark": mark.map { .string($0) } ?? .null], busyKey: "mark-\(id)")
        await load("research")
    }

    private func demoMark(kind: String, id: String, mark: String?) {
        guard var r = research else { return }
        if kind == "facts", let i = r.items.facts.firstIndex(where: { $0.id == id }) { r.items.facts[i].mark = mark }
        if kind == "media", let i = r.items.media.firstIndex(where: { $0.id == id }) { r.items.media[i].mark = mark }
        if kind == "sources", let i = r.items.sources.firstIndex(where: { $0.id == id }) { r.items.sources[i].mark = mark }
        research = r
    }

    /// "Dig deeper": the video chat looks for more on an item (the desktop's words).
    func digDeeper(_ label: String) async {
        await send("Dig deeper on \(label): find more and better sources, check it against what else we have, and add "
                   + "what you find to the board.")
    }

    // MARK: Script

    /// What the script's selection bar sends the video chat (the desktop's Script stage words).
    nonisolated static func scriptAsk(_ what: String, ids: [String], text: String, extra: String = "") -> String {
        let where_ = "script line\(ids.count > 1 ? "s" : "") \(ids.joined(separator: ", "))"
        let quote = "\"\(String(text.prefix(1500)))\""
        let rewrite = "Rewrite only that part with script_change (keep each line's facts unless the words change what "
            + "it claims); I'll accept or undo it in the script."
        switch what {
        case "change": return "Change this part of the script (\(where_)): \(quote)\n\n\(extra)\n\n\(rewrite)"
        case "punchier":
            return "Make this part of the script punchier (\(where_)): \(quote)\n\nKeep the facts and the channel's "
                + "style guide. \(rewrite)"
        case "why": return "Why is this part of the script written this way (\(where_))? \(quote)\n\nJust explain; don't change it."
        default: return "A comment on the script (\(where_)): \(quote)\n\n\(extra)"
        }
    }

    /// Accepts or undoes the chat's rewrite.
    func resolve(change id: String, accept: Bool) async {
        if demo {
            guard var s = script, let c = s.pending.first(where: { $0.id == id }) else { return }
            if accept {
                for e in c.lines {
                    if let i = s.lines.firstIndex(where: { $0.id == e.id }) { s.lines[i].text = e.new }
                }
            }
            s.pending.removeAll { $0.id == id }
            script = s
            return
        }
        struct Resolved: Decodable { var version: Int? }
        let _: Resolved? = await call("script/resolve", ["change": .string(id), "accept": .bool(accept)],
                                      busyKey: "change-\(id)")
        await load("script")
    }

    // MARK: Listen

    /// Kokoro reads a line (the PC's draft voice, cached there).
    func speak(_ text: String, voice: String?) async -> StudioSpeech? {
        if demo { return Demo.load("speak", in: demoFolder) }
        guard let p = pairing else { return nil }
        do {
            return try await api.studioSpeak(p, projectId, videoId, text: text, voice: voice)
        } catch {
            let e = APIError.from(error)
            if !e.isCancelled { actionError = e.message }
            return nil
        }
    }

    // MARK: Voice

    func approve(line: String, take: Int?) async {
        if demo {
            guard var v = voice, let i = v.lines.firstIndex(where: { $0.id == line }) else { return }
            v.lines[i].approved = take
            voice = v
            return
        }
        let _: StudioAny? = await call("voice/approve", ["line": .string(line), "take": take.map { .int($0) } ?? .null],
                                       busyKey: "take-\(line)")
        await load("voice")
    }

    /// A new take of one line, with a direction in plain words (from: the take it redoes).
    func redo(line: String, from: Int?, direction: String) async -> Bool {
        if demo { notice = "Making a new take"; return true }
        var b: [String: StudioValue] = ["line": .string(line)]
        if let from { b["from"] = .int(from) }
        if !direction.isEmpty { b["direction"] = .string(direction) }
        let r: StudioAny? = await call("voice/generate", b, busyKey: "redo-\(line)")
        await load("voice")
        return r != nil
    }

    /// Takes for every line of a chapter that has none yet.
    func generate(chapter: Int) async {
        if demo { notice = "Generating the chapter"; return }
        let _: StudioAny? = await call("voice/generate", ["chapter": .int(chapter), "remaining": .bool(true)],
                                       busyKey: "generate")
        await load("voice")
    }

    // MARK: Visuals

    func approve(shot: String, approved: Bool = true) async {
        if demo {
            guard var v = visuals, let i = v.shots.firstIndex(where: { $0.id == shot }) else { return }
            v.shots[i].status = approved ? "approved" : "draft"
            visuals = v
            return
        }
        let _: StudioAny? = await call("visuals/approve", ["shot": .string(shot), "approved": .bool(approved)],
                                       busyKey: "shot-\(shot)")
        await load("visuals")
    }

    /// A new draft of a shot, with what to change in words.
    func redraft(shot: String, direction: String) async {
        if demo { notice = "Redrafting \(shot)"; return }
        var b: [String: StudioValue] = ["shots": .strings([shot])]
        if !direction.isEmpty { b["direction"] = .string(direction) }
        let _: StudioAny? = await call("visuals/draft", b, busyKey: "shot-\(shot)")
        await load("visuals")
    }

    /// Every approved shot into the render queue.
    func renderApproved() async {
        if demo { notice = "Queued the approved shots"; return }
        let _: StudioAny? = await call("visuals/render", ["approved": .bool(true)], busyKey: "render")
        await load("visuals")
    }

    // MARK: Finish

    /// A note at a moment of the final cut; the video chat hears it.
    func addNote(at: Double, text: String) async -> Bool {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return false }
        if demo {
            if var f = finish {
                var n = f.notes ?? StudioNotes(notes: [])
                n.notes.append(.init(id: UUID().uuidString, at: at, text: text, ts: Date().timeIntervalSince1970 * 1000))
                f.notes = n
                finish = f
            }
            notice = "Sent to the video chat"
            return true
        }
        guard let p = pairing else { return false }
        busy.insert("note")
        defer { busy.remove("note") }
        do {
            let n = try await api.studioAddNote(p, projectId, videoId, at: at, text: text)
            if var f = finish { f.notes = n; finish = f }
            notice = n.sent == false ? "Saved; the video has no chat" : "Sent to the video chat"
            return true
        } catch {
            actionError = APIError.from(error).message
            return false
        }
    }

    func looksGood() async {
        if demo {
            if var f = finish { var n = f.notes ?? StudioNotes(notes: []); n.ok = Date().timeIntervalSince1970 * 1000
                f.notes = n; finish = f }
            notice = "Sent to the video chat"
            return
        }
        guard let p = pairing else { return }
        busy.insert("ok")
        defer { busy.remove("ok") }
        do {
            let n = try await api.studioAddNote(p, projectId, videoId, ok: true)
            if var f = finish { f.notes = n; finish = f }
            notice = "Sent to the video chat"
        } catch {
            actionError = APIError.from(error).message
        }
    }

    private func note(_ error: Error) {
        let e = APIError.from(error)
        if Task.isCancelled || e.isCancelled { return }
        self.error = e
    }
}
