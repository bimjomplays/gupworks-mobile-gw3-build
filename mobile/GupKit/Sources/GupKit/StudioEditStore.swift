import Foundation
import Observation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// The Edit stage of one video: the PC's view, the model as the phone shows it (a change shows at once and goes to
/// the PC right after, one save at a time over the version it had), the shared undo history, the mix and the
/// sounds. The demo edits a copy of mobile/fixtures/studio/edit.json and keeps its own undo.
@Observable
@MainActor
final class StudioEditStore {
    let ref: StudioRef
    let pairing: Pairing?
    let demo: Bool
    private(set) var view: StudioEditView?
    /// the timeline as shown: the PC's, with the phone's changes not saved yet
    private(set) var model = StudioModel()
    private(set) var error: APIError?
    /// a change the PC turned down, or a sound that failed, for an alert
    var actionError: String?
    var toast: Toast?
    var selected: String? {
        didSet { if selected != oldValue { tellSelection() } }
    }
    /// sound search results and the search running
    private(set) var found: StudioSearchReply?
    private(set) var searching = false
    /// files being fetched from Freesound (their ids)
    private(set) var getting: Set<String> = []
    /// the ElevenLabs estimate waiting for a yes
    var estimate: Pending?
    private(set) var saving = false

    struct Toast: Equatable {
        var text: String
        var undo = false
        var show: String?           // "Show on the timeline": a clip to select
        var n = 0
    }

    struct Pending: Equatable {
        var body: StudioGenerateBody
        var reply: StudioGenerateReply
    }

    private enum Write {
        case save(StudioModel, String)
        case mix(StudioMix, String)
    }

    private let api = APIClient()
    private var queue: [Write] = []
    private var toastN = 0
    private var demoPast: [(StudioModel, StudioMix?, String)] = []
    private var demoFuture: [(StudioModel, StudioMix?, String)] = []

    init(ref: StudioRef, pairing: Pairing?, demo: Bool) {
        self.ref = ref
        self.pairing = pairing
        self.demo = demo
    }

    var readonly: Bool { view?.readonly ?? true }
    var shots: [String: StudioShot] { view?.shotsById ?? [:] }
    var voice: [StudioVoiceLine] { view?.voice ?? [] }
    var mix: StudioMix { view?.mix ?? StudioMix() }
    var chapters: [StudioChapter] {
        if let c = view?.chapters, !c.isEmpty { return c }
        return StudioEdit.chapters(voice)
    }

    /// the length: the PC's, or longer when a clip now runs past it
    var duration: Double {
        let ends = StudioTrack.allCases.flatMap { model[$0].map(\.end) } + voice.map(\.end)
        return max(view?.duration ?? 0, ends.max() ?? 0)
    }

    var canUndo: Bool { demo ? !demoPast.isEmpty : view?.history?.undo != nil }
    var canRedo: Bool { demo ? !demoFuture.isEmpty : view?.history?.redo != nil }

    // MARK: loading

    func load() async {
        if demo { return loadDemo() }
        guard let p = pairing else { return }
        do {
            let r = try await api.studioEdit(p, ref, known: nil)
            if let v = r.view { take(v) }
            error = nil
        } catch {
            let e = APIError.from(error)
            if Task.isCancelled || e.isCancelled { return }
            self.error = e
        }
    }

    /// Checks the PC every few seconds while the stage is open: the chat's edits, the desktop's and jobs.
    func follow() async {
        if view == nil { await load() }
        if demo { return }
        guard let p = pairing else { return }
        while !Task.isCancelled {
            let fast = view?.jobs?.contains { $0.status == "running" } == true
            try? await Task.sleep(nanoseconds: fast ? 1_000_000_000 : 3_000_000_000)
            if Task.isCancelled { return }
            guard queue.isEmpty, !saving else { continue }
            do {
                let r = try await api.studioEdit(p, ref, known: view?.version)
                guard let v = r.view, queue.isEmpty, !saving else { continue }
                let changed = view.map { $0.model != v.model } ?? false
                take(v)
                if changed {
                    show(v.by == "chat" ? "The chat changed the timeline" : "The timeline changed on the PC", undo: true)
                }
                error = nil
            } catch {
                let e = APIError.from(error)
                if e == .notPaired { self.error = e; return }
            }
        }
    }

    private func take(_ v: StudioEditView) {
        view = v
        model = v.model
        if let s = selected, s.hasPrefix("voice:") ? !v.voice.contains(where: { "voice:\($0.id)" == s })
            : StudioEdit.track(of: s, in: v.model) == nil {
            selected = nil
        }
    }

    private func loadDemo() {
        guard view == nil, let v: StudioEditView = Demo.load("edit", in: "fixtures/studio") else { return }
        take(v)
    }

    // MARK: changes

    /// A change to the timeline under `label` (the undo history's name for it); false when nothing changed.
    @discardableResult
    func change(_ label: String, toast: Bool = false, _ f: (inout StudioModel) -> Bool) -> Bool {
        guard !readonly, var m = Optional(model), f(&m), m != model else { return false }
        let before = model
        model = m
        if toast { show(label, undo: true) }
        if demo {
            demoPast.append((before, view?.mix, label))
            demoFuture = []
            view?.model = m
            view?.mixCurrent = false
            return true
        }
        queue.append(.save(m, label))
        Task { await flush() }
        return true
    }

    /// The mix settings (a slider drag is one step: the PC merges the same label made right after).
    func setMix(_ mix: StudioMix, label: String) {
        guard !readonly, view != nil, mix != view?.mix else { return }
        if demo {
            demoPast.append((model, view?.mix, label))
            demoFuture = []
            view?.mix = mix
            view?.mixCurrent = false
            return
        }
        view?.mix = mix
        if case .mix = queue.last { queue.removeLast() }  // the newest settings are enough
        queue.append(.mix(mix, label))
        Task { await flush() }
    }

    /// Sends the waiting changes one by one, each over the version the one before left.
    func flush() async {
        guard !saving, let p = pairing else { return }
        saving = true
        defer { saving = false }
        while !queue.isEmpty {
            let w = queue.removeFirst()
            guard let v = view else { queue = []; return }
            do {
                switch w {
                case .save(let m, let label):
                    let r = try await api.studioSave(p, ref, StudioSaveBody(model: m, base: v.timelineVersion, label: label))
                    view = v.merged(r)
                    view?.mixCurrent = false
                case .mix(let mix, let label):
                    let r = try await api.studioMix(p, ref, StudioMixBody(mix: mix, base: v.timelineVersion, label: label))
                    view = v.merged(r)
                }
                if queue.isEmpty, let v = view { model = v.model }
            } catch {
                queue = []
                actionError = APIError.from(error).message
                await load()
                return
            }
        }
    }

    func undo() async { await travel(back: true) }
    func redo() async { await travel(back: false) }

    private func travel(back: Bool) async {
        if demo {
            guard let (m, mx, label) = back ? demoPast.popLast() : demoFuture.popLast() else { return }
            let now = (model, view?.mix, label)
            if back { demoFuture.append(now) } else { demoPast.append(now) }
            model = m
            view?.model = m
            if let mx { view?.mix = mx }
            show("\(back ? "Undid" : "Redid"): \(label)")
            return
        }
        guard let p = pairing else { return }
        while saving || !queue.isEmpty { await flush(); if saving { try? await Task.sleep(nanoseconds: 50_000_000) } }
        do {
            let r = try await api.studioUndo(p, ref, back: back)
            take(r.view)
            show("\(back ? "Undid" : "Redid"): \(r.label ?? "the last change")")
        } catch {
            actionError = APIError.from(error).message
        }
    }

    /// the next undo's name ("Split v6 at 0:52.4"), for the button's label
    var undoLabel: String? { demo ? demoPast.last?.2 : view?.history?.undo }

    func show(_ text: String, undo: Bool = false, show: String? = nil) {
        toastN += 1
        toast = Toast(text: text, undo: undo && canUndo, show: show, n: toastN)
    }

    // MARK: the video chat

    private var selectTask: Task<Void, Never>?

    /// Tells the video chat what is selected, so "make this one shorter" means it (Edit.tsx's words).
    private func tellSelection() {
        guard !demo, let p = pairing else { return }
        let sel = selected.flatMap { id in
            StudioEdit.selectionLabel(id, model, voice: voice, shots: shots).map {
                StudioSelection(stage: "edit", kind: "clip", id: id, label: $0)
            }
        }
        selectTask?.cancel()
        selectTask = Task { [api, ref] in
            try? await Task.sleep(nanoseconds: 250_000_000)
            if Task.isCancelled { return }
            _ = try? await api.studioSelect(p, ref, sel)
        }
    }

    /// The chat of this video (opening it tells the PC the video is on its Edit stage).
    func chatId() async -> String? {
        if let c = view?.chatId { return c }
        if demo { return "studio-demo-chat" }
        guard let p = pairing else { return nil }
        do {
            let v = try await api.studioOpen(p, ref, stage: "edit")
            view?.chatId = v.chatId
            return v.chatId
        } catch {
            actionError = APIError.from(error).message
            return nil
        }
    }

    // MARK: sounds

    func search(_ q: String) async {
        let q = q.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        searching = true
        defer { searching = false }
        if demo {
            let all: StudioSearchReply? = Demo.load("sounds", in: "fixtures/studio")
            let words = q.lowercased().split(separator: " ")
            let hits = (all?.results ?? []).filter { r in
                words.contains { w in r.title.lowercased().contains(w) || (r.tags ?? []).contains { $0.contains(w) } }
            }
            found = StudioSearchReply(query: q, page: 1, results: hits.isEmpty ? all?.results ?? [] : hits, more: false)
            return
        }
        guard let p = pairing else { return }
        do {
            found = try await api.studioSearch(p, ref, q)
        } catch {
            actionError = APIError.from(error).message
        }
    }

    /// whether a search result is in the video folder already (and its file)
    func fileOf(_ r: StudioFound) -> String? {
        view?.log?.first { $0.source == "freesound" && ($0.url?.contains("/\(r.id)/") ?? false) }?.file
    }

    /// Brings a CC0 sound in from Freesound and puts it on `track` at `at`; returns its clip id.
    func add(_ r: StudioFound, track: StudioTrack, at: Double) async -> String? {
        if let f = fileOf(r) { return place(f, title: r.title, seconds: r.seconds, track: track, at: at) }
        getting.insert(r.id)
        defer { getting.remove(r.id) }
        if demo {
            let f = "sound/freesound/\(r.id).m4a"
            addLog(StudioSound(file: f, source: "freesound", title: r.title, author: r.author,
                                                         url: r.page, licence: r.licence, seconds: r.seconds, clips: []))
            if var media = view?.media, let demoFile = view?.media?["sound/library/rain.m4a"] {
                media[f] = demoFile
                view?.media = media
            }
            return place(f, title: r.title, seconds: r.seconds, track: track, at: at)
        }
        guard let p = pairing else { return nil }
        do {
            let g = try await api.studioGet(p, ref, id: r.id)
            if let s = g.sound { addLog(s) }
            if let m = g.media { for (k, x) in m { view?.media?[k] = x } }
            return place(g.file, title: r.title, seconds: r.seconds ?? g.sound?.seconds, track: track, at: at)
        } catch {
            actionError = APIError.from(error).message
            return nil
        }
    }

    /// A sound of the library onto a track.
    func place(_ file: String, title: String?, seconds: Double?, track: StudioTrack, at: Double) -> String? {
        var id: String?
        let name = title ?? (file as NSString).lastPathComponent
        change("Added \(name) at \(StudioEdit.clock(at))") { m in
            id = StudioEdit.addSound(&m, track, file: file, seconds: seconds ?? view?.media?[file]?.seconds,
                                     at: at, duration: duration)
            return true
        }
        if let id { selected = id }
        return id
    }

    /// Asks the PC what an ElevenLabs sound would cost; the sheet shows it and waits for a yes.
    func priceGeneration(kind: String, prompt: String, seconds: Double) async {
        let b = StudioGenerateBody(kind: kind, prompt: prompt, seconds: seconds, confirm: false)
        if demo {
            estimate = Pending(body: b, reply: StudioGenerateReply(estimate: (seconds * (kind == "sfx" ? 20 : 30)).rounded(.up),
                                                                    rate: 20, how: "measured", seconds: seconds, left: 21_400))
            return
        }
        guard let p = pairing else { return }
        do {
            estimate = Pending(body: b, reply: try await api.studioGenerate(p, ref, b))
        } catch {
            actionError = APIError.from(error).message
        }
    }

    /// The yes: the PC makes it (a job in the view); it lands in the library when it's done.
    func confirmGeneration() async {
        guard var b = estimate?.body else { return }
        estimate = nil
        b.confirm = true
        if demo {
            addJob(StudioJob(id: "snd9", kind: b.kind, status: "running", progress: 0.3,
                                                         phase: "Generating", prompt: b.prompt))
            return
        }
        guard let p = pairing else { return }
        do {
            let r = try await api.studioGenerate(p, ref, b)
            if let j = r.job { addJob(j) }
        } catch {
            actionError = APIError.from(error).message
        }
    }

    /// A recording from the phone (already uploaded to the PC) into the library and onto Effects at `at`.
    func addRecording(upload path: String, title: String, seconds: Double?, at: Double) async -> String? {
        guard let p = pairing, !demo else { return nil }
        do {
            let r = try await api.studioAddSound(p, ref, StudioAddBody(file: path, title: title))
            if let s = r.sound { addLog(s) }
            if let m = r.media { for (k, x) in m { view?.media?[k] = x } }
            return place(r.file, title: title, seconds: seconds ?? r.sound?.seconds, track: .sfx, at: at)
        } catch {
            actionError = APIError.from(error).message
            return nil
        }
    }

    func uploadRecording(_ data: Data, name: String) async -> UploadReply? {
        guard let p = pairing, !demo else { return nil }
        do {
            return try await api.upload(p, data, name: name, type: "audio/mp4", chat: "studio")
        } catch {
            actionError = APIError.from(error).message
            return nil
        }
    }

    // (a `view?.x = view?.x + …` reads `view` inside its own change, which Swift stops)
    private func addLog(_ s: StudioSound) {
        guard var v = view else { return }
        v.log = (v.log ?? []).filter { $0.file != s.file } + [s]
        view = v
    }

    private func addJob(_ j: StudioJob) {
        guard var v = view else { return }
        v.jobs = (v.jobs ?? []).filter { $0.id != j.id } + [j]
        view = v
    }

    // MARK: mixdown

    var mixdownJob: StudioJob? { view?.jobs?.last { $0.kind == "mixdown" } }

    func makeMixdown() async {
        if demo {
            addJob(StudioJob(id: "snd8", kind: "mixdown", status: "running", progress: 0.4,
                                                         phase: "Measuring"))
            return
        }
        guard let p = pairing else { return }
        while saving || !queue.isEmpty { await flush(); if saving { try? await Task.sleep(nanoseconds: 50_000_000) } }
        do {
            let j = try await api.studioMixdown(p, ref).job
            addJob(j)
        } catch {
            actionError = APIError.from(error).message
        }
    }

    // MARK: media

    /// where a file of the video folder loads from: the bridge's signed link (or the demo's bundled copy)
    func url(_ link: String?) -> URL? {
        guard let link, !link.isEmpty else { return nil }
        if demo {
            let dir = (link as NSString).deletingLastPathComponent
            return Demo.file((link as NSString).lastPathComponent, in: dir.isEmpty ? "fixtures/studio" : "fixtures/studio/" + dir)
        }
        if link.hasPrefix("http") { return URL(string: link) }
        guard let p = pairing else { return nil }
        return URL(string: link, relativeTo: Routes.shared.current(for: p.baseURL))?.absoluteURL
    }

    func media(_ file: String?) -> StudioMedia? { file.flatMap { view?.media?[$0] } }
}

/// The phone's copies of the video's media (a 640 px video, a JPEG, an AAC sound, an outline), downloaded once a
/// file and kept by the PC's key for it, so a changed file is fetched again and an unchanged one never is.
@Observable
@MainActor
final class StudioMediaCache {
    /// the local copy of each file, by its path in the video folder
    private(set) var local: [String: URL] = [:]
    private(set) var peaks: [String: [Float]] = [:]
    private var running: Set<String> = []
    private let folder: URL

    init(folder: URL? = nil) {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        self.folder = folder ?? caches.appendingPathComponent("studio-media", isDirectory: true)
        try? FileManager.default.createDirectory(at: self.folder, withIntermediateDirectories: true)
    }

    func ready(_ file: String) -> Bool { local[file] != nil }

    /// Fetches what's missing of `files` (the demo's are local already).
    func fetch(_ files: [String], store: StudioEditStore) {
        for f in files where local[f] == nil && !running.contains(f) {
            guard let m = store.media(f), let src = store.url(m.url) else { continue }
            if src.isFileURL {
                local[f] = src
                if let pk = store.url(m.peaks) { loadPeaks(f, from: pk) }
                continue
            }
            let ext = m.kind == "video" ? "mp4" : m.kind == "audio" ? "m4a" : "jpg"
            let key = m.key ?? String(f.hashValue, radix: 16)
            let dest = folder.appendingPathComponent("\(key).\(ext)")
            if FileManager.default.fileExists(atPath: dest.path) {
                local[f] = dest
                if let pk = store.url(m.peaks) { loadPeaks(f, from: pk) }
                continue
            }
            running.insert(f)
            let peaksURL = store.url(m.peaks)
            Task {
                defer { running.remove(f) }
                do {
                    let (tmp, resp) = try await URLSession.shared.download(from: src)
                    guard (resp as? HTTPURLResponse)?.statusCode ?? 200 == 200 else { return }
                    try? FileManager.default.removeItem(at: dest)
                    try FileManager.default.moveItem(at: tmp, to: dest)
                    local[f] = dest
                    if let peaksURL { loadPeaks(f, from: peaksURL) }
                } catch {}
            }
        }
    }

    private struct Peaks: Decodable {
        var rate: Double?
        var peaks: [Float]
    }

    /// a sound's outline: 25 values a second, 0-1
    private func loadPeaks(_ f: String, from u: URL) {
        guard peaks[f] == nil else { return }
        Task {
            let data: Data?
            if u.isFileURL { data = try? Data(contentsOf: u) } else { data = try? await URLSession.shared.data(from: u).0 }
            if let data, let p = try? JSONDecoder().decode(Peaks.self, from: data) {
                peaks[f] = p.peaks.map { min(1, max(0, $0 / 100)) }
            }
        }
    }
}
