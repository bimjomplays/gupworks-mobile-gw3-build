import Foundation

// YouTube Studio on the phone (a180): the answers of gw3-phone's /v1/studio routes (tools/gw3_phone_videos.py) and
// the client calls for them. A stage's answer is the PC Studio service's own (gw3_studio*.py), with a signed link
// (`<key>Url`, `<key>Poster` for a video) next to every file it names. The Edit stage (a181) calls the same `call`.

/// A video chat waiting on you: on the channel card, at the top of the video and as a notification.
struct StudioNeed: Codable, Equatable, Identifiable, Hashable {
    var projectId: String
    var videoId: String
    var title: String
    var channel: String
    var chatId: String?
    var ts: Double
    var permission: Bool
    var question: String
    var options: [Option]
    var answerable: Bool
    var kind: String?
    var sig: String?

    var id: String { "\(projectId)/\(videoId)" }

    struct Option: Codable, Equatable, Hashable {
        var n: Int
        var label: String
    }
}

/// A thread working for a video now (a research thread, a render).
struct StudioJob: Codable, Equatable, Hashable, Identifiable {
    var id: String
    var title: String
    var status: String
}

/// A video as a card: its stage, its chat's state, its cover.
struct StudioCard: Codable, Equatable, Identifiable {
    var id: String
    var title: String
    var kind: String                // long | short
    var stage: String
    var stageIndex: Int
    var stageName: String
    var stages: Int
    var chatId: String?
    var chatState: String           // needs | permission | working | idle | ...
    var updated: Double
    var jobs: [StudioJob]
    var readonly: Bool
    var working: String?
    var needs: StudioNeed?
    var cover: String?
    var duration: String?           // "22:10", the final cut's length

    var isShort: Bool { kind == "short" }
}

struct StudioStageName: Codable, Equatable {
    var key: String
    var name: String
}

/// GET /v1/studio: every channel, and what waits on you.
struct StudioHome: Codable, Equatable {
    var channels: [StudioChannelRow]
    var stages: [StudioStageName]
    var needs: [StudioNeed]
}

struct StudioChannelRow: Codable, Equatable, Identifiable {
    var projectId: String
    var name: String
    var icon: String?
    var color: String?
    var mainChatId: String?
    var about: String
    var longVideos: Int
    var shorts: Int
    var needs: [StudioNeed]
    var working: Int
    var covers: [String]
    var latest: [String]
    var updated: Double

    var id: String { projectId }
}

/// GET /v1/studio/<pid>: the channel row plus its videos, Shorts and style guide.
struct StudioChannel: Codable, Equatable {
    var row: StudioChannelRow
    var videos: [StudioCard]
    var shortsList: [StudioCard]
    var styleGuide: StyleGuide

    struct StyleGuide: Codable, Equatable {
        var path: String
        var text: String
        var blocks: [MD]?
    }

    private enum Keys: String, CodingKey { case videos, shortsList, styleGuide }

    init(row: StudioChannelRow, videos: [StudioCard], shortsList: [StudioCard], styleGuide: StyleGuide) {
        self.row = row
        self.videos = videos
        self.shortsList = shortsList
        self.styleGuide = styleGuide
    }

    init(from decoder: Decoder) throws {
        row = try StudioChannelRow(from: decoder)
        let c = try decoder.container(keyedBy: Keys.self)
        videos = try c.decode([StudioCard].self, forKey: .videos)
        shortsList = try c.decode([StudioCard].self, forKey: .shortsList)
        styleGuide = try c.decode(StyleGuide.self, forKey: .styleGuide)
    }

    func encode(to encoder: Encoder) throws {
        try row.encode(to: encoder)
        var c = encoder.container(keyedBy: Keys.self)
        try c.encode(videos, forKey: .videos)
        try c.encode(shortsList, forKey: .shortsList)
        try c.encode(styleGuide, forKey: .styleGuide)
    }
}

/// GET /v1/studio/<pid>/<vid>: the video's overview.
struct StudioOverview: Codable, Equatable {
    var card: StudioCard
    var channel: Channel
    var stages: [Stage]
    var openStage: String
    var needs: StudioNeed?
    var jobs: [StudioJob]
    var voiceSeconds: Double?

    struct Channel: Codable, Equatable {
        var projectId: String
        var name: String
        var icon: String?
        var color: String?
    }

    struct Stage: Codable, Equatable, Identifiable {
        var key: String
        var name: String
        var state: String           // done | current | todo
        var summary: String
        var busy: Bool
        var id: String { key }
    }
}

struct StudioNewVideo: Codable, Equatable {
    var title: String
    var kind: String
}

struct StudioNewChannel: Codable, Equatable {
    var name: String
    var about: String
}

struct StudioNewChannelReply: Codable, Equatable {
    var projectId: String?
    var name: String?
}

// MARK: the stages' answers

/// A word's time in a voice take or a Kokoro reading.
struct StudioWord: Codable, Equatable, Hashable {
    var w: String
    var start: Double
    var end: Double
}

struct StudioChapter: Codable, Equatable, Hashable {
    var chapter: Int
    var title: String
    var first: String?
}

struct StudioBriefQuestion: Codable, Equatable, Identifiable {
    var id: String
    var text: String
    var state: String?              // answered | researching | open
    var thread: String?
    var summary: String?
}

/// studio/brief: the brief's fields and its research questions with how far each is.
struct StudioBrief: Codable, Equatable {
    var brief: Fields
    var title: String?
    var questions: [StudioBriefQuestion]
    var filled: Int?
    var of: Int?

    struct Fields: Codable, Equatable {
        var topic: String
        var angle: String
        var audience: String
        var format: String
        var length: String
        var extra: String?
    }
}

/// studio/research: the board's items, questions and research threads.
struct StudioResearch: Codable, Equatable {
    var title: String?
    var items: Items
    var questions: [StudioBriefQuestion]
    var threads: [Thread]
    var rights: [String: String]?

    struct Items: Codable, Equatable {
        var sources: [Source]
        var facts: [Fact]
        var people: [Person]
        var places: [Place]
        var events: [Event]
        var media: [Media]
    }

    struct Conflict: Codable, Equatable, Hashable {
        var text: String
        var sources: [String]?
    }

    struct Fact: Codable, Equatable, Identifiable {
        var id: String
        var text: String
        var sources: [String]
        var confidence: String       // high | medium | low
        var conflicts: [Conflict]?
        var question: String?
        var note: String?
        var mark: String?            // pinned | rejected
    }

    struct Source: Codable, Equatable, Identifiable {
        var id: String
        var title: String
        var url: String?
        var kind: String?
        var author: String?
        var date: String?
        var credibility: String?
        var note: String?
        var mark: String?
    }

    struct Person: Codable, Equatable, Identifiable {
        var id: String
        var name: String
        var role: String?
        var born: String?
        var died: String?
        var note: String?
        var mark: String?
    }

    struct Place: Codable, Equatable, Identifiable {
        var id: String
        var name: String
        var `where`: String?
        var note: String?
        var mark: String?
    }

    struct Event: Codable, Equatable, Identifiable {
        var id: String
        var date: String?
        var text: String
        var place: String?
        var note: String?
        var mark: String?
    }

    struct Media: Codable, Equatable, Identifiable {
        var id: String
        var title: String
        var file: String?
        var fileUrl: String?
        var url: String?
        var kind: String?
        var rights: String           // public-domain | cc-credit | needs-permission | reference-only
        var licence: String?
        var credit: String?
        var date: String?
        var note: String?
        var mark: String?

        /// cleared for use in the video (public domain, or CC with its credit line)
        var cleared: Bool { rights == "public-domain" || rights == "cc-credit" }
    }

    struct Thread: Codable, Equatable, Identifiable {
        var id: String
        var title: String
        var status: String
        var checkpoint: String?
        var summary: String?
        var chatId: String?
    }
}

/// studio/script: the lines, the chat's waiting rewrites, versions and the checks.
struct StudioScript: Codable, Equatable {
    var lines: [Line]
    var chapters: [StudioChapter]
    var checks: Checks?
    var pending: [Change]
    var versions: [Version]
    var keys: [String: String]?
    var voice: String?
    var words: Int?
    var seconds: Double?
    var title: String?
    var readonly: Bool?

    struct Line: Codable, Equatable, Identifiable {
        var id: String
        var chapter: Int?
        var text: String
        var facts: [String]?
    }

    struct Checks: Codable, Equatable {
        var hits: [Hit]
        var unsourced: [String]
        var rules: Int?
    }

    struct Hit: Codable, Equatable, Hashable {
        var line: String
        var start: Int
        var end: Int
        var rule: String
        var suggestion: String?
        var severity: String?
    }

    struct Change: Codable, Equatable, Identifiable {
        var id: String
        var at: Double?
        var by: String?
        var note: String?
        var request: String?
        var lines: [Edit]
        var status: String

        struct Edit: Codable, Equatable, Hashable {
            var id: String
            var old: String
            var new: String
            var facts: [String]?
        }
    }

    struct Version: Codable, Equatable {
        var n: Int
        var at: Double?
        var by: String?
        var label: String?
        var lines: Int?
    }
}

/// studio/voice: the ElevenLabs takes line by line, the jobs making them, credits left.
struct StudioVoice: Codable, Equatable {
    var lines: [Line]
    var chapters: [StudioChapter]
    var config: Config?
    var approved: Int?
    var trackSeconds: Double?
    var readonly: Bool?
    var jobs: [Job]
    var credits: Credits?
    var creditsError: String?
    var rate: Double?

    struct Line: Codable, Equatable, Identifiable {
        var id: String
        var chapter: Int?
        var text: String
        var chars: Int?
        var takes: [Take]
        var approved: Int?
    }

    struct Take: Codable, Equatable, Identifiable {
        var n: Int
        var file: String?
        var fileUrl: String?
        var text: String?
        var direction: String?
        var applied: [String]?
        var seconds: Double?
        var words: [StudioWord]?
        var stale: Bool?
        var id: Int { n }
    }

    struct Config: Codable, Equatable {
        var name: String?
        var model: String?
    }

    struct Credits: Codable, Equatable {
        var used: Int?
        var limit: Int?
        var left: Int?
    }

    struct Job: Codable, Equatable, Identifiable {
        var id: String
        var lines: [String]
        var done: [Done]?
        var failed: [Failed]?
        var current: String?
        var status: String
        var estimate: Int?

        struct Done: Codable, Equatable { var line: String; var take: Int }
        struct Failed: Codable, Equatable { var line: String; var error: String }
    }
}

/// studio/visuals: shots with their drafts and renders, the draft jobs and the GPU's render queue.
struct StudioVisuals: Codable, Equatable {
    var shots: [Shot]
    var chapters: [StudioChapter]?
    var drafts: [DraftJob]
    var renders: [Render]
    var readonly: Bool?

    struct Shot: Codable, Equatable, Identifiable {
        var id: String
        var chapter: Int?
        var lines: [String]?
        var start: Double?
        var end: Double?
        var style: String?
        var description: String?
        var status: String           // draft | approved | rendering | rendered
        var draft: String?
        var draftUrl: String?
        var render: String?
        var renderUrl: String?
        var renderPoster: String?
        var drafts: [Draft]?

        struct Draft: Codable, Equatable { var n: Int; var file: String?; var direction: String? }
    }

    struct DraftJob: Codable, Equatable, Identifiable {
        var id: String
        var shots: [String]
        var current: String?
        var status: String
    }

    struct Render: Codable, Equatable, Identifiable {
        var id: String
        var videoId: String?
        var video: String?
        var shot: String?
        var status: String           // queued | running | done | failed | cancelled
        var frames: Int?
        var done: Int?
        var eta: Double?
        var startsIn: Double?
        var error: String?
    }
}

/// studio/finish: the final cut, its checks and chapters, the phone's notes on it.
struct StudioFinish: Codable, Equatable {
    var title: String?
    var kind: String?
    var readonly: Bool?
    var reason: String?
    var duration: Double?
    var final: Final?
    var checks: Checks?
    var jobs: [String: Job]?
    var chapters: [Chapter]
    var notes: StudioNotes?

    struct Final: Codable, Equatable {
        var file: String?
        var fileUrl: String?
        var filePoster: String?
        var timeline: Double?
        var at: Double?
    }

    struct Checks: Codable, Equatable {
        var at: Double?
        var items: [Item]
        struct Item: Codable, Equatable, Identifiable {
            var id: String
            var name: String
            var ok: Bool
            var detail: String?
        }
    }

    struct Job: Codable, Equatable {
        var id: String?
        var status: String?
        var step: String?
        var progress: Double?
        var error: String?
    }

    struct Chapter: Codable, Equatable, Hashable {
        var chapter: Int?
        var title: String
        var start: Double
        var stamp: String?
    }
}

/// The notes on a final cut (and when you said it looks good).
struct StudioNotes: Codable, Equatable {
    var notes: [Note]
    var ok: Double?
    var sent: Bool?

    struct Note: Codable, Equatable, Identifiable {
        var id: String
        var at: Double
        var text: String
        var ts: Double?
    }
}

/// POST .../speak: Kokoro reads a line (Listen), with each word's time.
struct StudioSpeech: Codable, Equatable {
    var audio: String
    var seconds: Double
    var timing: String
    var words: [StudioWord]
}

/// A stage call's body: the route's own fields (the bridge adds projectId and videoId).
enum StudioValue: Encodable, Equatable, Sendable {
    case string(String), int(Int), double(Double), bool(Bool), strings([String]), null
    case object([String: StudioValue])

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .string(let s): try c.encode(s)
        case .int(let n): try c.encode(n)
        case .double(let d): try c.encode(d)
        case .bool(let b): try c.encode(b)
        case .strings(let a): try c.encode(a)
        case .object(let o): try c.encode(o)
        case .null: try c.encodeNil()
        }
    }
}

/// Answers a stage call whose body the phone doesn't read.
struct StudioAny: Decodable, Equatable {
    init(from decoder: Decoder) throws {}
}

extension APIClient {
    /// the routes whose service call can take a while (they start work and answer when it is queued)
    static let studioSlow: Set<String> = ["research/start", "visuals/draft", "visuals/render", "finish/render",
                                          "finish/check", "finish/thumbs", "voice/generate", "voice/credits",
                                          "sound/search", "sound/generate", "sound/mixdown", "edit/apply"]

    func studio(_ p: Pairing) async throws -> StudioHome {
        try await request(p.baseURL, "/v1/studio", token: p.token, slow: true)
    }

    func studioChannel(_ p: Pairing, _ pid: String) async throws -> StudioChannel {
        try await request(p.baseURL, "/v1/studio/\(pid)", token: p.token)
    }

    func studioNewChannel(_ p: Pairing, _ b: StudioNewChannel) async throws -> StudioNewChannelReply {
        try await request(p.baseURL, "/v1/studio/channels", token: p.token, method: "POST", encoding: b, slow: true)
    }

    func studioNewVideo(_ p: Pairing, _ pid: String, _ b: StudioNewVideo) async throws -> StudioCard {
        try await request(p.baseURL, "/v1/studio/\(pid)/videos", token: p.token, method: "POST", encoding: b, slow: true)
    }

    func studioOverview(_ p: Pairing, _ pid: String, _ vid: String) async throws -> StudioOverview {
        try await request(p.baseURL, "/v1/studio/\(pid)/\(vid)", token: p.token, slow: true)
    }

    /// A stage route for a video (brief, script/resolve, voice/generate, edit/save, ...), as the desktop's Studio.
    func studioCall<T: Decodable>(_ p: Pairing, _ pid: String, _ vid: String, _ route: String,
                                  _ body: [String: StudioValue] = [:]) async throws -> T {
        try await request(p.baseURL, "/v1/studio/\(pid)/\(vid)/call/\(route)", token: p.token, method: "POST",
                          encoding: body, slow: Self.studioSlow.contains(route) || !route.contains("/"))
    }

    func studioSpeak(_ p: Pairing, _ pid: String, _ vid: String, text: String, voice: String?) async throws -> StudioSpeech {
        var b = ["text": text]
        if let voice { b["voice"] = voice }
        return try await request(p.baseURL, "/v1/studio/\(pid)/\(vid)/speak", token: p.token, method: "POST", encoding: b,
                                 slow: true)
    }

    func studioNotes(_ p: Pairing, _ pid: String, _ vid: String) async throws -> StudioNotes {
        try await request(p.baseURL, "/v1/studio/\(pid)/\(vid)/notes", token: p.token)
    }

    /// a note at a moment of the final cut ({at, text}) or "looks good" ({ok: true}); the video chat hears it
    func studioAddNote(_ p: Pairing, _ pid: String, _ vid: String, at: Double? = nil, text: String? = nil,
                       ok: Bool = false) async throws -> StudioNotes {
        var b: [String: StudioValue] = [:]
        if ok { b["ok"] = .bool(true) }
        if let at { b["at"] = .double(at) }
        if let text { b["text"] = .string(text) }
        return try await request(p.baseURL, "/v1/studio/\(pid)/\(vid)/notes", token: p.token, method: "POST", encoding: b)
    }
}
