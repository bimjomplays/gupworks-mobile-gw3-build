import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// What gw3-phone sends (tools/gw3_phone.py; the demo copies are in mobile/fixtures/).

struct Hello: Codable, Equatable {
    var app: String
    var version: String
    var api: Int
    var pc: String
    var features: [String]
    var direct: String?  // the PC's tailnet address (gw3-phone 0.8.1), tried when the name fails (Routes)
}

/// POST /v1/voice: the words, and how the PC got them ("gpu", "cpu"; none when the clip was silent)
struct VoiceReply: Codable, Equatable {
    var text: String
    var engine: String?
    var seconds: Double?
    var ms: Int?
}

struct PairReply: Codable {
    var token: String
    var pc: String
    var version: String
    var direct: String?
}

struct Home: Codable, Equatable {
    var now: Double
    var projects: [ProjectRow]
    var setups: [ChatRow]
    var chats: [ChatRow]
    var archivedCount: Int
    var projectsError: String?
    var layout: [LayoutEntry]?      // slice 6: the desktop sidebar's order and folders
    var pinned: [PinRef]?           // the menu's Pinned: chats and projects in the order set on the phone (gw3-phone 0.8)
    var usage: [Meter]?             // the account's 5-hour and weekly limits, for a new chat's rings
    var archivedProjects: [ProjectRow]?  // the Projects filter's Archived (gw3-phone 0.9)
}

/// One row of Pinned: a chat or a project.
struct PinRef: Codable, Equatable, Hashable {
    var kind: String       // chat | project
    var id: String
}

struct PinnedBody: Codable, Equatable {
    var pinned: [PinRef]
}

/// GET /v1/search: chats whose words match, with the line that matched.
struct SearchReply: Codable, Equatable {
    var chats: [SearchHit]
}

struct SearchHit: Codable, Equatable, Identifiable {
    var id: String
    var title: String
    var snippet: String?
}

struct ProjectRow: Codable, Equatable, Identifiable {
    var id: String
    var name: String
    var state: String      // needs | permission | working | paused | idle
    var detail: String
    var needs: Int
    var permission: Int
    var working: Int
    var paused: Bool
    var mainChatId: String?
    // gw3-phone 0.9: the project's icon and colour (ProjectLook), its last activity and when it was made (ms)
    var icon: String?
    var color: String?
    var lastActive: Double?
    var created: Double?
}

struct ChatRow: Codable, Equatable, Identifiable {
    var id: String
    var title: String
    var state: String      // working | needs | permission | done | idle
    var model: String
    var provider: String
    var lastActive: Double // ms since 1970 on the PC's clock
    var pinned: Bool
    var running: Bool
    var pinnedAt: Double?
}

/// A message for a chat: its words and the uploads it names (UploadReply.path).
struct OutgoingBody: Codable, Equatable {
    var clientId: String
    var text: String
    var files: [String]
}

/// One of the phone's messages the chat hasn't shown as a turn yet.
struct QueueItem: Codable, Equatable, Identifiable {
    var clientId: String
    var text: String
    var ts: Double
    var state: String      // queued (waits for the turn to end) | sent (its turn is on its way) | failed
    var error: String?
    var images: [String]?
    var files: [String]?

    var id: String { clientId }
}

struct SendReply: Codable, Equatable {
    var ok: Bool
    var new: Bool
    var started: Bool
    var queue: [QueueItem]
}

/// POST /v1/chats: the first message, and the model and effort picked before it (a temporary chat is forgotten
/// for good once it's deleted).
struct NewChatBody: Codable, Equatable {
    var clientId: String
    var text: String
    var files: [String]
    var model: String?
    var effort: String?
    var temporary: Bool?
}

struct NewChatReply: Codable, Equatable {
    var id: String
    var started: Bool
    var temporary: Bool?
}

struct UploadReply: Codable, Equatable {
    var path: String
    var name: String
    var size: Int
    var image: Bool
}

struct OKReply: Codable {
    var ok: Bool
}

/// PATCH /v1/chats/<id>: only what's set is sent (nil fields stay out of the JSON).
struct ChatEdit: Codable, Equatable {
    var title: String?
    var pinned: Bool?
    var archived: Bool?
}

// MARK: slice 4: answering, picking, commands

/// POST …/answer: one of the dialog's choices, ticks for a multiple choice question, words for "Something else…",
/// or skip / chat. `sig` names the dialog, so an answer never lands on a newer question.
struct DialogAnswer: Codable, Equatable {
    var sig: String
    var choice: Int?
    var ticks: [Int]?
    var text: String?
    var action: String?         // skip | chat
    var lines: Int?             // rewind's Restore: how many lines the message has (the PC clears its box)
}

/// what's on Claude's screen after an answer: a question's next tab, or nothing (nil)
struct AnswerReply: Codable, Equatable {
    var ok: Bool
    var dialog: Dialog?
}

struct ModeReply: Codable, Equatable {
    var ok: Bool
    var mode: String
    var bypass: Bool
}

struct PickBody: Codable, Equatable {
    var model: String
    var effort: String?
}

struct PickReply: Codable, Equatable {
    var ok: Bool
    var model: String
    var effort: String
}

struct ModelInfo: Codable, Equatable, Identifiable {
    var id: String
    var label: String
    var provider: String
    var note: String?
    var efforts: [String]
}

struct ModelsReply: Codable, Equatable {
    var models: [ModelInfo]
    var `default`: PickBody?        // what a new chat starts on (gw3-phone 0.8)
}

struct CommandInfo: Codable, Equatable, Identifiable {
    var name: String
    var group: String
    var args: String?
    var summary: String?
    var description: String?

    var id: String { name }
    /// `<what>` in its args: the command needs words after it, so it goes into the box instead of running
    var needsArgs: Bool { (args ?? "").hasPrefix("<") }
}

struct CommandsReply: Codable, Equatable {
    var pinned: [String]
    var recent: [String]
    var groups: [String]?
    var commands: [CommandInfo]
}

struct PinsBody: Codable, Equatable {
    var pinned: [String]
}

struct PinsReply: Codable, Equatable {
    var pinned: [String]
    var recent: [String]
}

struct RewindReply: Codable, Equatable {
    var ok: Bool
    var dialog: Dialog
    var text: String
}

enum APIError: Error, Equatable {
    case notPaired           // 401: the PC doesn't know this phone (anymore)
    case unreachable(NoAnswer)  // no answer: Tailscale off, PC asleep, the name not found (NoAnswer says which)
    case server(String)      // the PC answered with an error
    /// an answer the PC turned down: the chat's hold is older (`old`), or the question changed (the new `dialog`)
    case refused(String, old: Bool, dialog: Dialog?)
    /// a note save the PC turned down: the note changed on the PC since the phone opened it (its text now)
    case conflict(String, theirs: String, version: String)

    var message: String {
        switch self {
        case .notPaired: return "Your PC doesn't know this phone anymore. Pair again."
        case .unreachable(let why): return why.message
        case .server(let text): return text
        case .refused(let text, _, _): return text
        case .conflict(let text, _, _): return text
        }
    }

    var isUnreachable: Bool {
        if case .unreachable = self { return true }
        return false
    }

    /// the app stopped the request itself: nothing to tell the user
    var isCancelled: Bool { self == .unreachable(.cancelled) }

    /// any error as one of these: the PC's own answers stay, a failed connection says which step failed
    static func from(_ error: Error) -> APIError {
        if let e = error as? APIError { return e }
        return .unreachable(NoAnswer(error))
    }
}

/// Which step of reaching the PC failed, from the iPhone's network error. The PC's address is a Tailscale name
/// that only Tailscale's DNS knows; ordinary DNS either doesn't know it or (with Funnel on) points it at
/// Tailscale's public relays, where the phone's port just times out.
enum NoAnswer: Equatable {
    case unknown(Int?)  // any other failure; a URLError's code, shown so a report says which
    case noName      // the name lookup failed
    case timeout     // nothing answered in time
    case refused     // something answered and turned the connection down
    case dropped     // the connection broke off partway
    case offline     // this iPhone has no network
    case secure      // the secure connection (its certificate) failed
    case cancelled   // the app stopped the request itself (it went to the back, a refresh started over)

    init(_ error: Error) {
        if error is CancellationError { self = .cancelled; return }
        guard let e = error as? URLError else { self = .unknown(nil); return }
        switch e.code {
        case .cannotFindHost, .dnsLookupFailed: self = .noName
        case .timedOut: self = .timeout
        case .cannotConnectToHost: self = .refused
        case .networkConnectionLost: self = .dropped
        case .notConnectedToInternet, .dataNotAllowed, .internationalRoamingOff: self = .offline
        case .secureConnectionFailed, .serverCertificateUntrusted, .serverCertificateHasBadDate,
             .serverCertificateNotYetValid, .serverCertificateHasUnknownRoot:
            self = .secure
        case .cancelled: self = .cancelled
        default: self = .unknown(e.code.rawValue)
        }
    }

    var message: String {
        switch self {
        case .unknown(let code):
            return "Can't reach your PC" + (code.map { " (error \($0))" } ?? "")
                + ". Is Tailscale on? In the Tailscale app, also check that Use Tailscale DNS is on."
        case .noName:
            return "Can't find your PC's name. In the Tailscale app, turn on Use Tailscale DNS, and turn off any other "
                + "VPN or DNS app (NextDNS, Cloudflare WARP, AdGuard)."
        case .timeout:
            return "Your PC didn't answer. In the Tailscale app, check it's connected and Use Tailscale DNS is on; if "
                + "both are, turn Tailscale off and on. The PC must be awake."
        case .refused:
            return "Your PC turned the connection down. Is GupWorks' phone service set up on the PC?"
        case .dropped:
            return "The connection to your PC broke off. Try again; if it keeps happening, turn Tailscale off and on."
        case .offline:
            return "This iPhone is offline."
        case .secure:
            return "The secure connection to your PC failed. Check the iPhone's date and time, then try again."
        case .cancelled:
            return "Stopped before your PC answered. Try again."
        }
    }
}

/// an error answer: its words, and for answers what came with them
private struct ErrorBody: Decodable {
    var error: String?
    var old: Bool?
    var dialog: Dialog?
    var text: String?           // a note save's conflict: the PC's text and its version
    var version: String?
}

/// Talks to gw3-phone: an ephemeral session (no cookies, cache or stored credentials), no redirects.
final class APIClient {
    private let routes: Routes

    init(routes: Routes = .shared) {
        self.routes = routes
    }

    private let session = APIClient.makeSession(timeout: 12)
    /// answers and rewinds: the PC presses keys and waits for Claude to redraw between them
    private let slowSession = APIClient.makeSession(timeout: 60)
    /// "is the PC there?" before a recording goes up: a short wait, so Airplane Mode falls back to the iPhone quickly
    private let quickSession = APIClient.makeSession(timeout: 4)
    /// a recording: up to 10 minutes of speech, which whisper on the CPU (no GPU) takes a while over
    private let voiceSession = APIClient.makeSession(timeout: 300)
    /// a quick action's on/off: Away mode's lights can take a while (the PC gives it 150 s)
    private let actionSession = APIClient.makeSession(timeout: 165)

    private static func makeSession(timeout: TimeInterval) -> URLSession {
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = timeout
        #if canImport(Darwin)
        c.waitsForConnectivity = false
        #endif
        c.httpCookieStorage = nil
        c.urlCache = nil
        return URLSession(configuration: c, delegate: NoRedirects(), delegateQueue: nil)
    }

    /// `device` is the name the PC lists this phone under (`gw3-phone status`)
    func pair(_ link: PairLink, device: String) async throws -> Pairing {
        let body = ["code": link.code, "device": device]
        let reply: PairReply = try await request(link.baseURL, "/v1/pair", token: nil, method: "POST", body: body)
        routes.learn(reply.direct, for: link.baseURL)
        return Pairing(baseURL: link.baseURL, token: reply.token, pairedAt: Date(), pcName: reply.pc)
    }

    func hello(_ p: Pairing) async throws -> Hello {
        let h: Hello = try await request(p.baseURL, "/v1/hello", token: p.token)
        routes.learn(h.direct, for: p.baseURL)
        return h
    }

    /// hello with a short wait (voice asks it while recording)
    func quickHello(_ p: Pairing) async throws -> Hello {
        let h: Hello = try await perform(p.baseURL, "/v1/hello", token: p.token, via: quickSession)
        routes.learn(h.direct, for: p.baseURL)
        return h
    }

    func home(_ p: Pairing) async throws -> Home {
        try await request(p.baseURL, "/v1/home", token: p.token)
    }

    func chat(_ p: Pairing, _ id: String) async throws -> ChatHeader {
        try await request(p.baseURL, "/v1/chats/\(id)", token: p.token)
    }

    /// a page of turns, oldest first; `before` is the oldest turn the phone has
    func turns(_ p: Pairing, _ id: String, before: String? = nil, limit: Int = 30) async throws -> TurnsPage {
        var q = [URLQueryItem(name: "limit", value: String(limit))]
        if let before { q.append(URLQueryItem(name: "before", value: before)) }
        return try await request(p.baseURL, "/v1/chats/\(id)/turns", token: p.token, query: q)
    }

    func card(_ p: Pairing, chat: String, card: String) async throws -> CardDetail {
        try await request(p.baseURL, "/v1/chats/\(chat)/cards/\(card)", token: p.token)
    }

    // MARK: talking to a chat (slice 3)

    /// Queues a message; the chat gets it once it's idle (started first if its process is gone). Sending the same
    /// clientId again is the same message, so a retry after a lost answer never sends twice.
    func send(_ p: Pairing, chat: String, _ m: OutgoingBody) async throws -> SendReply {
        try await request(p.baseURL, "/v1/chats/\(chat)/send", token: p.token, method: "POST", encoding: m)
    }

    /// Ends the running turn (the PC answers 409 when nothing runs).
    func stop(_ p: Pairing, chat: String) async throws {
        let _: OKReply = try await request(p.baseURL, "/v1/chats/\(chat)/stop", token: p.token, method: "POST",
                                           encoding: [String: String]())
    }

    /// A new chat with its first message; the answer names it.
    func newChat(_ p: Pairing, _ m: NewChatBody) async throws -> NewChatReply {
        try await request(p.baseURL, "/v1/chats", token: p.token, method: "POST", encoding: m)
    }

    func editChat(_ p: Pairing, _ id: String, _ edit: ChatEdit) async throws {
        let _: OKReply = try await request(p.baseURL, "/v1/chats/\(id)", token: p.token, method: "PATCH", encoding: edit)
    }

    /// Out of the list, as the desktop's delete: the PC keeps the transcript, so it can be brought back there.
    func deleteChat(_ p: Pairing, _ id: String) async throws {
        let _: OKReply = try await perform(p.baseURL, "/v1/chats/\(id)", token: p.token, method: "DELETE")
    }

    /// One photo or file, sent before the message that names it (`chat` is "new" for a chat not made yet).
    func upload(_ p: Pairing, _ data: Data, name: String, type: String, chat: String) async throws -> UploadReply {
        let q = [URLQueryItem(name: "name", value: name), URLQueryItem(name: "chat", value: chat)]
        return try await perform(p.baseURL, "/v1/uploads", token: p.token, method: "POST", query: q, raw: data,
                                 contentType: type)
    }

    // MARK: voice (slice 5)

    /// A recording (AAC in .m4a) turned into text by the PC's whisper; the PC deletes the audio once it answers.
    func voice(_ p: Pairing, _ audio: Data) async throws -> VoiceReply {
        try await perform(p.baseURL, "/v1/voice", token: p.token, method: "POST", raw: audio, contentType: "audio/mp4",
                          via: voiceSession)
    }

    // MARK: answering, picking, commands (slice 4)

    func answer(_ p: Pairing, chat: String, _ a: DialogAnswer) async throws -> AnswerReply {
        try await request(p.baseURL, "/v1/chats/\(chat)/answer", token: p.token, method: "POST", encoding: a, slow: true)
    }

    /// Bypass on or off (Shift+Tab on the PC until Claude's mode line says so)
    func setBypass(_ p: Pairing, chat: String, _ on: Bool) async throws -> ModeReply {
        try await request(p.baseURL, "/v1/chats/\(chat)/mode", token: p.token, method: "POST", encoding: ["bypass": on],
                          slow: true)
    }

    /// the model and effort for the chat's next turn (as the desktop's picker)
    func pick(_ p: Pairing, chat: String, _ b: PickBody) async throws -> PickReply {
        try await request(p.baseURL, "/v1/chats/\(chat)/pick", token: p.token, method: "POST", encoding: b)
    }

    func models(_ p: Pairing) async throws -> ModelsReply {
        try await request(p.baseURL, "/v1/models", token: p.token)
    }

    func commands(_ p: Pairing, chat: String) async throws -> CommandsReply {
        try await request(p.baseURL, "/v1/chats/\(chat)/commands", token: p.token)
    }

    /// the commands for a chat not made yet
    func commands(_ p: Pairing) async throws -> CommandsReply {
        try await request(p.baseURL, "/v1/commands", token: p.token)
    }

    /// Pinned in a new order (chats joining or leaving it are pinned or unpinned); the answer is the new home.
    func setPinned(_ p: Pairing, _ pinned: [PinRef]) async throws -> Home {
        try await request(p.baseURL, "/v1/home/pinned", token: p.token, method: "PUT", encoding: PinnedBody(pinned: pinned))
    }

    /// chats whose words match (titles are matched on the phone)
    func search(_ p: Pairing, _ q: String) async throws -> SearchReply {
        try await request(p.baseURL, "/v1/search", token: p.token, query: [URLQueryItem(name: "q", value: q)])
    }

    /// the pinned commands, the same list the desktop's palette pins
    func setPins(_ p: Pairing, _ pinned: [String]) async throws -> PinsReply {
        try await request(p.baseURL, "/v1/pins", token: p.token, method: "PUT", encoding: PinsBody(pinned: pinned))
    }

    /// Opens /rewind at a prompt; the answer is its confirm page, answered like any dialog.
    func rewind(_ p: Pairing, chat: String, turn: String) async throws -> RewindReply {
        try await request(p.baseURL, "/v1/chats/\(chat)/rewind", token: p.token, method: "POST", encoding: ["turn": turn],
                          slow: true)
    }

    // MARK: projects (slice 6)

    func project(_ p: Pairing, _ id: String) async throws -> ProjectView {
        try await request(p.baseURL, "/v1/projects/\(id)", token: p.token)
    }

    /// the Library, or one of its folders
    func library(_ p: Pairing, project: String, folder: String? = nil) async throws -> LibraryList {
        let q = folder.map { [URLQueryItem(name: "folder", value: $0)] } ?? []
        return try await request(p.baseURL, "/v1/projects/\(project)/library", token: p.token, query: q)
    }

    func libraryFile(_ p: Pairing, project: String, path: String) async throws -> LibraryFile {
        try await request(p.baseURL, "/v1/projects/\(project)/library/file", token: p.token,
                          query: [URLQueryItem(name: "path", value: path)])
    }

    /// Saves a note over the version the phone opened; a change on the PC meanwhile comes back as `.conflict`.
    func saveNote(_ p: Pairing, project: String, _ save: NoteSave) async throws -> NoteSaved {
        try await request(p.baseURL, "/v1/projects/\(project)/library/file", token: p.token, method: "PUT",
                          encoding: save)
    }

    func schedules(_ p: Pairing, project: String) async throws -> ScheduleList {
        try await request(p.baseURL, "/v1/projects/\(project)/schedules", token: p.token)
    }

    /// pause | resume | stop | done | archive | unarchive | rename {title} | delete, as the desktop panel's thread menu
    func moveThread(_ p: Pairing, project: String, thread: String, _ move: String,
                    title: String? = nil) async throws -> ProjectView {
        try await request(p.baseURL, "/v1/projects/\(project)/threads/\(thread)/\(move)", token: p.token,
                          method: "POST", encoding: title.map { ["title": $0] } ?? [String: String]())
    }

    /// Your own thread (the panel's + New thread), started with its first message.
    func newThread(_ p: Pairing, project: String, text: String) async throws -> NewThreadReply {
        try await request(p.baseURL, "/v1/projects/\(project)/threads", token: p.token, method: "POST",
                          encoding: ["text": text])
    }

    func pauseProject(_ p: Pairing, _ id: String, _ on: Bool) async throws -> ProjectView {
        try await request(p.baseURL, "/v1/projects/\(id)/pause", token: p.token, method: "POST",
                          encoding: ["paused": on])
    }

    func archiveProject(_ p: Pairing, _ id: String, _ on: Bool) async throws -> ProjectView {
        try await request(p.baseURL, "/v1/projects/\(id)/archive", token: p.token, method: "POST",
                          encoding: ["archived": on])
    }

    // MARK: quick actions (a142)

    func quick(_ p: Pairing) async throws -> QuickList {
        try await request(p.baseURL, "/v1/quick", token: p.token)
    }

    /// Away mode or Dillon's game bot on or off; the answer is every switch read again afterwards
    func setQuick(_ p: Pairing, _ id: String, on: Bool) async throws -> QuickList {
        try await perform(p.baseURL, "/v1/quick/\(id)", token: p.token, method: "POST",
                          json: try JSONEncoder().encode(["on": on]), via: actionSession)
    }

    /// Restart PC's dialog opens: a one-time confirm token for its Restart button
    func restartConfirm(_ p: Pairing) async throws -> QuickConfirm {
        try await request(p.baseURL, "/v1/quick/restart-pc/confirm", token: p.token, method: "POST",
                          encoding: [String: String]())
    }

    /// Restart PC, with the token the dialog got; only after the dialog's Restart was pressed
    func restartPC(_ p: Pairing, confirm: String) async throws -> QuickRestarted {
        try await request(p.baseURL, "/v1/quick/restart-pc", token: p.token, method: "POST",
                          encoding: ["confirm": confirm], slow: true)
    }

    // MARK: quick actions round 2 (a151): health, media and volume, open on the PC, Discord

    func quickPc(_ p: Pairing) async throws -> QuickPcState {
        try await request(p.baseURL, "/v1/quick/pc", token: p.token)
    }

    /// play-pause, next or previous; the answer is the media read again
    func quickMedia(_ p: Pairing, action: String, player: String?) async throws -> QuickMediaReply {
        try await request(p.baseURL, "/v1/quick/media", token: p.token, method: "POST",
                          encoding: QuickMediaBody(action: action, player: player))
    }

    /// the default output's volume (0...1) or mute; the answer is the media read again
    func quickVolume(_ p: Pairing, level: Double?, muted: Bool?) async throws -> QuickMediaReply {
        try await request(p.baseURL, "/v1/quick/volume", token: p.token, method: "POST",
                          encoding: QuickVolumeBody(level: level, muted: muted))
    }

    /// opens an http(s) link in one of the PC's browsers (an id from QuickBrowsers); the PC remembers the pick
    func quickOpen(_ p: Pairing, url: String, browser: String) async throws -> QuickOpenReply {
        try await request(p.baseURL, "/v1/quick/open", token: p.token, method: "POST",
                          encoding: ["url": url, "browser": browser])
    }

    // MARK: a121's project pages

    func createProject(_ p: Pairing, _ b: NewProjectBody) async throws -> NewProjectReply {
        try await request(p.baseURL, "/v1/projects", token: p.token, method: "POST", encoding: b, slow: true)
    }

    func projectFolders(_ p: Pairing) async throws -> FoldersReply {
        try await request(p.baseURL, "/v1/projects/folders", token: p.token)
    }

    func projectSettings(_ p: Pairing, _ id: String) async throws -> ProjectSettings {
        try await request(p.baseURL, "/v1/projects/\(id)/settings", token: p.token)
    }

    func updateProject(_ p: Pairing, _ id: String, _ patch: ProjectPatch) async throws -> ProjectSettings {
        try await request(p.baseURL, "/v1/projects/\(id)", token: p.token, method: "PATCH", encoding: patch)
    }

    /// The project's record goes; its folder and notes stay on the PC.
    func deleteProject(_ p: Pairing, _ id: String) async throws {
        let _: OKReply = try await request(p.baseURL, "/v1/projects/\(id)", token: p.token, method: "DELETE",
                                           encoding: ["confirm": "delete"])
    }

    func ideas(_ p: Pairing, project: String) async throws -> IdeasList {
        try await request(p.baseURL, "/v1/projects/\(project)/ideas", token: p.token)
    }

    func addIdea(_ p: Pairing, project: String, text: String, section: String) async throws -> IdeasList {
        try await request(p.baseURL, "/v1/projects/\(project)/ideas", token: p.token, method: "POST",
                          encoding: ["text": text, "section": section])
    }

    func changeIdea(_ p: Pairing, project: String, _ c: IdeaChange) async throws -> IdeasList {
        try await request(p.baseURL, "/v1/projects/\(project)/ideas/change", token: p.token, method: "POST", encoding: c)
    }

    func projectUsage(_ p: Pairing, project: String) async throws -> ProjectUsage {
        try await request(p.baseURL, "/v1/projects/\(project)/usage", token: p.token)
    }

    /// uploads (UploadReply.path) copied into the project's notes folder
    func libraryAdd(_ p: Pairing, project: String, files: [String]) async throws -> LibraryAddReply {
        try await request(p.baseURL, "/v1/projects/\(project)/library/add", token: p.token, method: "POST",
                          encoding: ["files": files])
    }

    /// run | pause | resume one schedule
    func scheduleMove(_ p: Pairing, project: String, schedule: String, _ move: String) async throws -> ScheduleList {
        try await request(p.baseURL, "/v1/projects/\(project)/schedules/\(schedule)/\(move)", token: p.token,
                          method: "POST", encoding: [String: String]())
    }

    func searchProjects(_ p: Pairing, _ q: String) async throws -> ProjectSearchReply {
        try await request(p.baseURL, "/v1/search", token: p.token,
                          query: [URLQueryItem(name: "q", value: q), URLQueryItem(name: "in", value: "projects")])
    }

    /// A server-sent events stream (`/v1/home/events`, `/v1/chats/<id>/events`). Ends when the PC closes it; throws
    /// APIError like the other calls.
    func events(_ p: Pairing, _ path: String, query: [URLQueryItem] = []) -> AsyncThrowingStream<SSEEvent, Error> {
        // one way per stream: a failed one goes last, so the caller's next try takes the other
        let base = p.baseURL, routes = self.routes, token = p.token
        let session = streamSession
        return AsyncThrowingStream { continuation in
            let task = Task {
                await routes.discover(for: base)
                let way = routes.current(for: base)
                let req = Self.makeRequest(way, path, token: token, query: query, accept: "text/event-stream")
                do {
                    #if canImport(Darwin)
                    let bytes: URLSession.AsyncBytes, response: URLResponse
                    do {
                        (bytes, response) = try await session.bytes(for: req)
                    } catch {
                        if !Task.isCancelled { routes.failed(way, for: base) }
                        throw error
                    }
                    routes.worked(way, for: base)
                    let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                    if status == 401 { throw APIError.notPaired }
                    guard status == 200 else { throw APIError.server("The PC answered \(status).") }
                    var parser = SSEParser()
                    for try await byte in bytes {
                        if let e = parser.feed(byte) { continuation.yield(e) }
                    }
                    continuation.finish()
                    #else
                    throw APIError.server("Event streams need Apple's URLSession.")  // Linux tests don't stream
                    #endif
                } catch let e as APIError {
                    continuation.finish(throwing: e)
                } catch {
                    continuation.finish(throwing: Task.isCancelled ? CancellationError() as Error : APIError.from(error))
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Streams stay open for minutes; the PC sends a keepalive every 15 s, so a quiet 45 s means the line is dead.
    private let streamSession: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = 45
        c.timeoutIntervalForResource = 60 * 60 * 24
        #if canImport(Darwin)
        c.waitsForConnectivity = false
        #endif
        c.httpCookieStorage = nil
        c.urlCache = nil
        c.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: c, delegate: NoRedirects(), delegateQueue: nil)
    }()

    private static func makeRequest(_ base: URL, _ path: String, token: String?, query: [URLQueryItem] = [],
                                    accept: String = "application/json") -> URLRequest {
        var c = URLComponents(url: base, resolvingAgainstBaseURL: false)!
        c.path = path
        c.queryItems = query.isEmpty ? nil : query
        var req = URLRequest(url: c.url!)
        req.setValue(accept, forHTTPHeaderField: "Accept")
        if let token { req.setValue("Bearer " + token, forHTTPHeaderField: "Authorization") }
        return req
    }

    private func request<T: Decodable>(_ base: URL, _ path: String, token: String?, method: String = "GET",
                                       query: [URLQueryItem] = [], body: [String: String]? = nil) async throws -> T {
        try await perform(base, path, token: token, method: method, query: query,
                          json: body.map { try JSONEncoder().encode($0) })
    }

    private func request<T: Decodable, B: Encodable>(_ base: URL, _ path: String, token: String?, method: String,
                                                     encoding body: B, slow: Bool = false) async throws -> T {
        try await perform(base, path, token: token, method: method, json: try JSONEncoder().encode(body), slow: slow)
    }

    private func perform<T: Decodable>(_ base: URL, _ path: String, token: String?, method: String = "GET",
                                       query: [URLQueryItem] = [], json: Data? = nil, raw: Data? = nil,
                                       contentType: String? = nil, slow: Bool = false,
                                       via: URLSession? = nil) async throws -> T {
        let (data, status) = try await fetch(base, path, token: token, method: method, query: query, json: json, raw: raw,
                                             contentType: contentType, slow: slow, via: via)
        if status == 401 {
            if token == nil, let e = try? JSONDecoder().decode([String: String].self, from: data), let text = e["error"] {
                throw APIError.server(text)  // a wrong or expired pairing code
            }
            throw APIError.notPaired
        }
        guard status == 200 else { throw Self.failure(status, data) }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw APIError.server("The PC sent something this app can't read. Update GupWorks on the PC or the app.")
        }
    }

    /// One request by whichever way to the PC answers: the answer's body and status, whatever the status.
    private func fetch(_ base: URL, _ path: String, token: String?, method: String = "GET",
                       query: [URLQueryItem] = [], json: Data? = nil, raw: Data? = nil,
                       contentType: String? = nil, slow: Bool = false,
                       via: URLSession? = nil) async throws -> (Data, Int) {
        await routes.discover(for: base)
        let ways = routes.order(for: base)
        var answer: (Data, URLResponse)?
        for (i, way) in ways.enumerated() {
            var req = Self.makeRequest(way, path, token: token, query: query)
            req.httpMethod = method
            if let json {
                req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                req.httpBody = json
            } else if let raw {
                req.setValue(contentType ?? "application/octet-stream", forHTTPHeaderField: "Content-Type")
                req.httpBody = raw
            }
            do {
                answer = try await (via ?? (slow ? slowSession : session)).data(for: req)
                routes.worked(way, for: base)
                break
            } catch {
                let e = APIError.from(error)
                if Task.isCancelled || e.isCancelled { throw e }
                routes.failed(way, for: base)
                if i + 1 < ways.count, Self.mayTryOtherWay(e, method: method) { continue }
                throw e
            }
        }
        guard let answer else { throw APIError.unreachable(.unknown(nil)) }
        let (data, response) = answer
        return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
    }

    // MARK: file transfer (a144)

    /// a piece of a file going up over Tailscale's relay can take a while
    private let uploadSession = APIClient.makeSession(timeout: 90)

    /// the newest messages of the phone-to-PC chat, or those before `before`
    func transferPage(_ p: Pairing, before: String? = nil) async throws -> TransferMessages {
        var q: [URLQueryItem] = []
        if let before { q.append(URLQueryItem(name: "before", value: before)) }
        return try await request(p.baseURL, "/v1/transfer", token: p.token, query: q)
    }

    func transferLibrary(_ p: Pairing) async throws -> TransferLibraryList {
        try await request(p.baseURL, "/v1/transfer/library", token: p.token)
    }

    func startUpload(_ p: Pairing, name: String, size: Int64, type: String) async throws -> UploadState {
        try await request(p.baseURL, "/v1/transfer/uploads", token: p.token, method: "POST",
                          encoding: UploadStart(name: name, size: size, type: type))
    }

    /// how much of an upload the PC has; TransferError.gone when it has none (cleared after a week)
    func uploadState(_ p: Pairing, _ id: String) async throws -> UploadState {
        let (data, status) = try await fetch(p.baseURL, "/v1/transfer/uploads/\(id)", token: p.token)
        return try Self.uploadAnswer(status, data)
    }

    /// One piece of a file at `offset`; TransferError.behind when the PC's copy stands elsewhere (a piece lost or
    /// sent twice: go on from there).
    func putPiece(_ p: Pairing, _ id: String, offset: Int64, _ data: Data) async throws -> UploadState {
        let (body, status) = try await fetch(p.baseURL, "/v1/transfer/uploads/\(id)", token: p.token, method: "PUT",
                                             query: [URLQueryItem(name: "offset", value: String(offset))], raw: data,
                                             via: uploadSession)
        return try Self.uploadAnswer(status, body)
    }

    func sendTransfer(_ p: Pairing, _ m: TransferSend) async throws -> TransferMessage {
        let (data, status) = try await fetch(p.baseURL, "/v1/transfer/messages", token: p.token, method: "POST",
                                             json: try JSONEncoder().encode(m))
        if status == 200, let msg = try? JSONDecoder().decode(TransferMessage.self, from: data) { return msg }
        if status == 404 { throw TransferError.gone }
        if status == 409, let r = try? JSONDecoder().decode(UploadState.Behind.self, from: data) {
            throw TransferError.behind(r.received)
        }
        if status == 401 { throw APIError.notPaired }
        throw Self.failure(status, data)
    }

    /// an upload route's answer: its state, or why not
    static func uploadAnswer(_ status: Int, _ data: Data) throws -> UploadState {
        switch status {
        case 200:
            guard let st = try? JSONDecoder().decode(UploadState.self, from: data) else {
                throw APIError.server("The PC sent something this app can't read. Update GupWorks on the PC or the app.")
            }
            return st
        case 401: throw APIError.notPaired
        case 404: throw TransferError.gone
        case 409:
            if let r = try? JSONDecoder().decode(UploadState.Behind.self, from: data) { throw TransferError.behind(r.received) }
            throw failure(status, data)
        default: throw failure(status, data)
        }
    }
}

extension APIClient {
    /// After a failed way, whether the other may be tried. A read always. A change only when the request surely never
    /// reached the PC (no name, turned down, no secure connection), so a message isn't sent twice after a timeout.
    static func mayTryOtherWay(_ e: APIError, method: String) -> Bool {
        guard case .unreachable(let why) = e else { return false }
        if method == "GET" || method == "HEAD" { return why != .offline }
        return why == .noName || why == .refused || why == .secure
    }

    /// What an error answer (not 200, not 401) means.
    static func failure(_ status: Int, _ data: Data) -> APIError {
        let e = try? JSONDecoder().decode(ErrorBody.self, from: data)
        let text = e?.error ?? "The PC answered \(status)."
        if status == 409, let theirs = e?.text, let version = e?.version {
            return .conflict(text, theirs: theirs, version: version)
        }
        if e?.old == true || e?.dialog != nil {
            return .refused(text, old: e?.old == true, dialog: e?.dialog)
        }
        return .server(text)
    }
}

/// One server-sent event: `event: <name>` and its `data:` lines.
struct SSEEvent: Equatable {
    var name: String
    var data: String
}

/// Reads an event stream byte by byte (AsyncBytes.lines drops the empty lines that end each event).
struct SSEParser {
    private var line: [UInt8] = []
    private var name = ""
    private var data: [String] = []

    mutating func feed(_ byte: UInt8) -> SSEEvent? {
        if byte == 13 { return nil }               // \r\n endings
        guard byte == 10 else { line.append(byte); return nil }
        let text = String(decoding: line, as: UTF8.self)
        line.removeAll(keepingCapacity: true)
        if text.isEmpty {
            defer { name = ""; data = [] }
            return data.isEmpty ? nil : SSEEvent(name: name.isEmpty ? "message" : name, data: data.joined(separator: "\n"))
        }
        if text.hasPrefix(":") { return nil }       // keepalive
        let field = text.prefix { $0 != ":" }
        var value = text.dropFirst(field.count).dropFirst()
        if value.hasPrefix(" ") { value = value.dropFirst() }
        switch field {
        case "event": name = String(value)
        case "data": data.append(String(value))
        default: break
        }
        return nil
    }

    mutating func feed(_ text: String) -> [SSEEvent] {
        text.utf8.compactMap { feed($0) }
    }
}

private final class NoRedirects: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

/// The demo mode (`-demo` launch argument, used by the screenshot tests): answers from the bundled fixtures, with
/// the times moved so the recorded "now" is now.
enum Demo {
    /// the launch arguments the demo's flags come from (-demo, -open ID, -menu, ...); the in-app screen tests set
    /// their own before they build a screen
    static var args = ProcessInfo.processInfo.arguments
    static var isOn: Bool { args.contains("-demo") }
    /// the menu tells the main view a second late that a pin lifted (MenuView), for MenuSwipeUITests
    static var slowLift: Bool { isOn && args.contains("-slowLift") }
    /// the menu's swipe reaches SwiftUI half a second late (MainView's MenuSwipe), as on a busy phone, for
    /// MenuSwipeUITests: a row's tap then comes before SwiftUI hears of the swipe across it
    static var slowSwipe: Bool { isOn && args.contains("-slowSwipe") }

    /// The folder holding `fixtures/`: the app's bundle, or mobile/ in the repo when GupKit runs as a Swift package
    /// (`swift test` on Linux).
    #if SWIFT_PACKAGE
    static var root: URL? = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    #else
    static var root: URL? = nil
    #endif

    /// a bundled file (`name` with its extension, or `name` + `.ext`) under `folder`, e.g. fixtures/chats
    static func file(_ name: String, ext: String? = nil, in folder: String) -> URL? {
        guard let root else { return Bundle.main.url(forResource: name, withExtension: ext, subdirectory: folder) }
        let u = root.appendingPathComponent(folder).appendingPathComponent(ext.map { name + "." + $0 } ?? name)
        return FileManager.default.fileExists(atPath: u.path) ? u : nil
    }

    static func load<T: Decodable>(_ name: String, in folder: String = "fixtures") -> T? {
        guard let url = file(name, ext: "json", in: folder),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    static var home: Home? {
        guard var h: Home = load("home") else { return nil }
        let shift = Date().timeIntervalSince1970 * 1000 - h.now
        h.now += shift
        h.chats = h.chats.map { var c = $0; c.lastActive += shift; c.pinnedAt = c.pinnedAt.map { $0 + shift }; return c }
        let move = { (r: ProjectRow) -> ProjectRow in
            var r = r
            r.lastActive = r.lastActive.map { $0 + shift }
            r.created = r.created.map { $0 + shift }
            return r
        }
        h.projects = h.projects.map(move)
        h.archivedProjects = h.archivedProjects?.map(move)
        h.usage = h.usage.map { shiftResets($0, by: shift) }
        return h
    }

    /// meters' reset times moved by `ms`
    static func shiftResets(_ meters: [Meter], by ms: Double) -> [Meter] {
        meters.map { m in
            var m = m
            if let r = m.resets, let at = Format.isoDate(r) {
                m.resets = ISO8601DateFormatter().string(from: at.addingTimeInterval(ms / 1000))
            }
            return m
        }
    }

    static var pairing: Pairing {
        Pairing(baseURL: URL(string: "https://desktop.example.ts.net:10005")!, token: "demo",
                pairedAt: Date(timeIntervalSinceNow: -86_400 * 3), pcName: "desktop")
    }
}
