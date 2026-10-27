import Foundation
import Observation

// a151: the PC part of Quick actions, as gw3-phone's /v1/quick/pc, media, volume and open answer (tools/gw3_pc.py, the
// desktop's page reads the same module). A part that broke on the PC comes back as {"error": ...} alone, so every
// field here is optional and shown as it is, never guessed.

/// One item of the health line ("CPU 61°C"); `level` is ok, warn or bad.
struct QuickHealthItem: Codable, Equatable, Identifiable {
    var id: String
    var label: String
    var value: String
    var level: String?
}

struct QuickHealthRow: Codable, Equatable {
    var label: String
    var value: String
    var level: String?
    var unit: String?
}

struct QuickHealthSection: Codable, Equatable {
    var title: String
    var rows: [QuickHealthRow]
}

struct QuickHealth: Codable, Equatable {
    var line: [QuickHealthItem]?
    var errors: [String]?
    var sections: [QuickHealthSection]?
    var error: String?

    /// what shows in red under the line: the parts that couldn't be read
    var problems: [String] { (errors ?? []) + (error.map { [$0] } ?? []) }
}

struct QuickPlayer: Codable, Equatable {
    var id: String
    var app: String?
    var status: String?
    var title: String?
    var artist: String?
    var canNext: Bool?
    var canPrevious: Bool?
    var canControl: Bool?

    var playing: Bool { status == "Playing" }
    /// "Northern Lights — Aurora Hall"
    var nowPlaying: String {
        let t = (title?.isEmpty == false ? title! : "Untitled")
        guard let a = artist, !a.isEmpty else { return t }
        return "\(t) — \(a)"
    }
}

struct QuickVolume: Codable, Equatable {
    var level: Double
    var muted: Bool
    var device: String?

    var percent: Int { Int((level * 100).rounded()) }
    /// "Desk Speakers · 42%", or "· Muted"
    var detail: String {
        let d = (device?.isEmpty == false ? device! : "Default output")
        return "\(d) · " + (muted ? "Muted" : "\(percent)%")
    }
}

struct QuickMedia: Codable, Equatable {
    var player: QuickPlayer?
    var players: Int?
    var volume: QuickVolume?
    var errors: [String: String]?
    var error: String?

    var playerError: String? { QuickPcText.nonEmpty(errors?["player"]) ?? QuickPcText.nonEmpty(error) }
    var volumeError: String? { QuickPcText.nonEmpty(errors?["volume"]) ?? QuickPcText.nonEmpty(error) }
}

/// Whether the owner is in a Discord voice call: read from PipeWire (Discord's voice streams), so no channel name.
struct QuickDiscord: Codable, Equatable {
    var running: Bool?
    var inCall: Bool?
    var mic: Bool?
    var detail: String?
    var how: String?
    var error: String?
}

struct QuickBrowser: Codable, Equatable, Identifiable, Hashable {
    var id: String
    var label: String
}

struct QuickBrowsers: Codable, Equatable {
    var browsers: [QuickBrowser]?
    var last: String?
    var error: String?

    var list: [QuickBrowser] { browsers ?? [] }
    func label(_ id: String) -> String { list.first { $0.id == id }?.label ?? id }
}

struct QuickPcState: Codable, Equatable {
    var health: QuickHealth?
    var media: QuickMedia?
    var discord: QuickDiscord?
    var browsers: QuickBrowsers?
}

struct QuickMediaReply: Codable, Equatable {
    var error: String?
    var media: QuickMedia
}

struct QuickOpenReply: Codable, Equatable {
    var error: String?
    var browsers: QuickBrowsers
}

struct QuickMediaBody: Encodable {
    var action: String
    var player: String?
}

struct QuickVolumeBody: Encodable {
    var level: Double?
    var muted: Bool?
}

enum QuickPcText {
    static func nonEmpty(_ s: String?) -> String? { s?.isEmpty == false ? s : nil }

    /// The same check as the PC's (gw3_pc.clean_url), so the phone can say it before sending: one http(s) link with a
    /// host, no spaces. nil when fine, else why not.
    static func linkProblem(_ text: String) -> String? {
        let url = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if url.isEmpty { return "Paste a link first." }
        if url.count > 4096 || url.unicodeScalars.contains(where: { $0.value < 33 || $0.value == 127 }) {
            return "That isn't a single link (spaces or control characters)."
        }
        guard let u = URLComponents(string: url), let scheme = u.scheme?.lowercased(),
              ["http", "https"].contains(scheme), u.host?.isEmpty == false else {
            return "Only http:// and https:// links open on the PC."
        }
        return nil
    }

    /// The first http(s) link in some pasted or shared text ("Look at this https://… !"), else the text itself.
    static func firstLink(in text: String) -> String {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        for word in t.split(whereSeparator: { $0.isWhitespace }) {
            let w = String(word).trimmingCharacters(in: CharacterSet(charactersIn: "<>()[]\"'.,!?"))
            if linkProblem(w) == nil { return w }
        }
        return t
    }

    /// An older gw3-phone has no such route: say what to do instead of "No route GET …"
    static func readable(_ message: String) -> String {
        message.hasPrefix("No route") ? "The PC's GupWorks is older than this app: update it on the PC for these rows." : message
    }
}

/// The PC part of the Quick actions page: health, media and volume, Open on the PC and the Discord call. Read with
/// the page (on open, when the app comes back, pull to refresh) and again after each action; an action's error stays
/// on its row until the next try. The demo answers from mobile/fixtures/quick-pc.json (`-quickError`: errors on
/// every row).
@Observable
@MainActor
final class QuickPcStore {
    private(set) var state: QuickPcState?
    /// the whole read failed (no answer from the PC)
    private(set) var error: String?
    private(set) var busy: Set<String> = []
    /// errors of the phone's own tries, by row: media, volume, open
    private(set) var tried: [String: String] = [:]
    /// "Opened in Chrome · Work" after a link opened
    private(set) var openNote: String?
    /// the browser picked on this phone; nil until the owner picks one (the PC's last pick shows meanwhile)
    var picked: String?

    let pairing: Pairing?
    let demo: Bool
    private let api = APIClient()

    init(pairing: Pairing?, demo: Bool) {
        self.pairing = pairing
        self.demo = demo
    }

    var health: QuickHealth? { state?.health }
    var media: QuickMedia? { state?.media }
    var discord: QuickDiscord? { state?.discord }
    var browsers: QuickBrowsers? { state?.browsers }

    /// the browser that Open uses: this visit's pick, else the PC's remembered one, else the first
    var browser: String? {
        let list = browsers?.list ?? []
        if let p = picked, list.contains(where: { $0.id == p }) { return p }
        if let l = browsers?.last, list.contains(where: { $0.id == l }) { return l }
        return list.first?.id
    }

    func errorText(_ row: String) -> String? {
        if let t = tried[row], !t.isEmpty { return t }
        switch row {
        case "media": return media?.playerError ?? error
        case "volume": return media?.volumeError ?? error
        case "open": return QuickPcText.nonEmpty(browsers?.error) ?? error
        case "discord": return QuickPcText.nonEmpty(discord?.error) ?? error
        default: return error
        }
    }

    /// the page opens again: old tries' errors and the last "Opened in" go
    func forgetTries() {
        tried = [:]
        openNote = nil
        picked = nil
    }

    func refresh() async {
        if demo { return loadDemo() }
        guard let p = pairing else { return }
        do {
            let s = try await api.quickPc(p)
            // a volume change on its way keeps its own answer
            if busy.contains("volume") || busy.contains("media") { state = QuickPcState(health: s.health, media: state?.media,
                                                                                          discord: s.discord, browsers: s.browsers) }
            else { state = s }
            error = nil
        } catch {
            let e = APIError.from(error)
            if Task.isCancelled || e.isCancelled { return }
            self.error = QuickPcText.readable(e.message)
        }
    }

    /// play-pause, next or previous, sent to the player shown
    func mediaAction(_ action: String) async {
        let player = media?.player?.id
        await act("media", demo: { $0.demoMedia(action) }) { api, p in
            let r = try await api.quickMedia(p, action: action, player: player)
            return (r.media, r.error)
        }
    }

    /// 0...1
    func setVolume(_ level: Double) async {
        let l = min(max(level, 0), 1)
        await act("volume", demo: { $0.demoVolume(level: l, muted: nil) }) { api, p in
            let r = try await api.quickVolume(p, level: (l * 100).rounded() / 100, muted: nil)
            return (r.media, r.error)
        }
    }

    func setMuted(_ muted: Bool) async {
        await act("volume", demo: { $0.demoVolume(level: nil, muted: muted) }) { api, p in
            let r = try await api.quickVolume(p, level: nil, muted: muted)
            return (r.media, r.error)
        }
    }

    /// Opens `text`'s link on the PC in the browser picked. true when it opened (the field can clear).
    @discardableResult
    func open(_ text: String) async -> Bool {
        guard !busy.contains("open") else { return false }
        tried["open"] = nil
        openNote = nil
        let url = QuickPcText.firstLink(in: text)
        if let why = QuickPcText.linkProblem(url) {
            tried["open"] = why
            return false
        }
        guard let b = browser else {
            tried["open"] = "No browser found on the PC."
            return false
        }
        busy.insert("open")
        defer { busy.remove("open") }
        if demo {
            try? await Task.sleep(nanoseconds: 300_000_000)
            if Demo.args.contains("-quickError") {
                tried["open"] = "\(b.hasPrefix("chrome") ? "google-chrome-stable" : "firefox"): not responding (demo)"
                return false
            }
            state?.browsers?.last = b
            openNote = "Opened in \(browsers?.label(b) ?? b)"
            return true
        }
        guard let p = pairing else { return false }
        do {
            let r = try await api.quickOpen(p, url: url, browser: b)
            state?.browsers = r.browsers
            if let e = QuickPcText.nonEmpty(r.error) {
                tried["open"] = e
                return false
            }
            openNote = "Opened in \(r.browsers.label(b))"
            return true
        } catch {
            tried["open"] = QuickPcText.readable(APIError.from(error).message)
            return false
        }
    }

    /// one media or volume action: busy while it runs, the media read again after it, its error on its row
    private func act(_ row: String, demo fake: (QuickPcStore) -> QuickMedia,
                     _ send: (APIClient, Pairing) async throws -> (QuickMedia, String?)) async {
        guard !busy.contains(row) else { return }
        guard demo || pairing != nil else { return }
        busy.insert(row)
        tried[row] = nil
        defer { busy.remove(row) }
        if demo {
            try? await Task.sleep(nanoseconds: 250_000_000)
            let m = fake(self)  // it reads the state: not inside the write
            if state == nil { state = QuickPcState() }
            state?.media = m
            return
        }
        guard let p = pairing else { return }
        do {
            let (m, e) = try await send(api, p)
            if state == nil { state = QuickPcState() }
            state?.media = m
            if let e = QuickPcText.nonEmpty(e) { tried[row] = e }
        } catch {
            tried[row] = QuickPcText.readable(APIError.from(error).message)
        }
    }

    // MARK: demo

    private func loadDemo() {
        guard state == nil, var s: QuickPcState = Demo.load("quick-pc") else { return }
        if Demo.args.contains("-quickError") {
            s.health?.errors = ["nvidia-smi: couldn't talk to the driver"]
            let line = s.health?.line?.map { i in
                var i = i
                if i.id == "gpu" { i.value = "?"; i.level = "warn" }
                if i.id == "services" { i.value = "Projects down"; i.level = "bad" }
                return i
            }
            s.health?.line = line
            s.media?.player = nil
            s.media?.volume = nil
            s.media?.errors = ["volume": "Could not connect to PipeWire"]
            s.discord = QuickDiscord(running: nil, inCall: nil, mic: nil, detail: "", how: s.discord?.how,
                                     error: "pw-dump: can't connect to PipeWire")
        }
        state = s
    }

    private func demoMedia(_ action: String) -> QuickMedia {
        var m = media ?? QuickMedia()
        guard var p = m.player else { return m }
        switch action {
        case "play-pause": p.status = p.playing ? "Paused" : "Playing"
        case "next": p.title = "Next track"
        default: p.title = "Previous track"
        }
        m.player = p
        return m
    }

    private func demoVolume(level: Double?, muted: Bool?) -> QuickMedia {
        var m = media ?? QuickMedia()
        var v = m.volume ?? QuickVolume(level: 0.5, muted: false, device: nil)
        if let level { v.level = level }
        if let muted { v.muted = muted }
        m.volume = v
        return m
    }
}
