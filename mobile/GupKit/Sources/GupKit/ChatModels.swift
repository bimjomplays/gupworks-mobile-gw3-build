import Foundation

// One chat as gw3-phone sends it (tools/gw3_turns.py turn_json / card_detail, tools/gw3_phone.py Chat.header).
// Every field the PC may leave out is optional, so an older or newer PC still decodes.

struct ChatHeader: Codable, Equatable {
    var id: String
    var title: String
    var role: String            // chat | main | worker
    var model: String
    var modelId: String?
    var provider: String?
    var effort: String
    var bypass: Bool
    var usage: [Meter]
    var branch: String?
    var folder: String?
    var running: Bool
    var state: String
    var project: ProjectRef?
    var pinned: Bool?
    // slice 4
    var mode: String?           // bypass | auto | manual | acceptEdits | plan (Claude's mode line)
    var door: Bool?             // the chat's gw3-hold takes keys from the phone (false: an older hold)
    var pending: Bool?          // a model or effort picked that applies from the next turn
    var cache: Cache?

    struct ProjectRef: Codable, Equatable {
        var id: String?
        var name: String
        var icon: String?
        var color: String?
        var mainChatId: String?
    }

    /// a thread's own chat (07): its task and live line (gw3-phone a121)
    var work: WorkInfo?
    /// a Studio video's own chat (a180): the video, the stage open on the PC and what is selected there
    var video: VideoInfo?

    struct VideoInfo: Codable, Equatable {
        var projectId: String
        var videoId: String
        var title: String
        var channel: String
        var openStage: String
        var stageName: String
        var selection: String?
    }

    struct WorkInfo: Codable, Equatable {
        var id: String
        var title: String
        var state: String
        var status: String
        var glyph: String
        var part: String
        var detail: String
        var word: String?
        var line: String?
        var modelLabel: String?
        var ago: String?
        var usage: String?
        var outcome: String
        var criteria: [String]
        var projectId: String?
        var from: String?       // you | main
        var moves: [String]?
    }

    /// the prompt cache: written at `at` (ms), kept `ttlMin` minutes
    struct Cache: Codable, Equatable {
        var at: Double?
        var ttlMin: Double?
    }
}

struct Meter: Codable, Equatable {
    var label: String           // ctx | 5h | wk
    var percent: Double?
    var tokens: Double?
    var switchAt: Double?
    var auto: Bool?
    var resets: String?
    var plan: String?           // "openai": a GPT chat, its limits are the ChatGPT plan's
}

struct ChatStatus: Codable, Equatable {
    var state: String
    var ts: Double
    var live: Bool
    var running: Bool
    var waiting: String?        // you | permission
    var dialog: Dialog?         // what Claude asks on its screen now (slice 4)
}

/// A dialog on Claude's screen (tools/gw3_dialogs.py parse): a permission, a question, its review page, a plan, or
/// /rewind's confirm page. `answerable` false: the chat's hold is older, so the phone says "Answer this on the PC".
struct Dialog: Codable, Equatable {
    var kind: String            // permission | ask | review | plan | rewind
    var title: String?
    var question: String?
    var body: [String]?
    var notes: [String]?
    var choices: [Choice]?
    var chat: Int?              // the choice number of "Chat about this"
    var multi: Bool?
    var tabs: [Tab]?
    var sig: String?
    var answerable: Bool?
    var plan: [MD]?

    struct Choice: Codable, Equatable, Identifiable {
        var n: Int
        var label: String
        var button: String?
        var detail: String?
        var input: Bool?        // "Type something." / "Tell Claude what to change": answered with words
        var box: Bool?
        var checked: Bool?
        var focused: Bool?

        var id: Int { n }
        var words: String { button ?? label }
    }

    struct Tab: Codable, Equatable {
        var name: String
        var answered: Bool?
    }

    var canAnswer: Bool { answerable == true && !(sig ?? "").isEmpty }
}

struct TurnsPage: Codable, Equatable {
    var turns: [Turn]
    var more: Bool
}

struct Turn: Codable, Equatable, Identifiable {
    var id: String
    var kind: String            // prompt | command | handoff | notice | task
    var start: Double
    var state: String           // working | waiting | done | failed | stopped
    var prompt: Prompt
    var waiting: String?
    var handle: Handle?
    var open: Bool
    var blocks: [Block]
    var outside: [Outside]?
    var rev: String
    var rewind: Bool?           // Claude's /rewind lists this prompt (D7's Rewind to here)
}

struct Prompt: Codable, Equatable {
    var text: String?
    var images: [String]?
    var phone: Bool?
    var bookmarked: Bool?
    var plugin: String?
    var notice: String?
    var items: [NoticeItem]?
    var status: String?
    /// audio files you sent, played in your bubble (a157)
    var audio: [MDItem]?
}

struct NoticeItem: Codable, Equatable {
    var kind: String
    var work: String
    var title: String
    var body: String
}

struct Handle: Codable, Equatable {
    var title: String
    var stats: String
    var ms: Double?
    var since: Double?          // set while the turn runs: the clock counts from here
}

/// A turn's block: text, card, divider, error, stdout, prompt (a queued message) or notice.
struct Block: Codable, Equatable {
    var type: String
    var id: String?
    var answer: Bool?
    var md: [MD]?
    // card
    var state: String?
    var steps: Int?
    var title: String?
    var stats: String?
    var add: Int?
    var del: Int?
    var since: Double?
    var one: OneCall?
    // divider, error, stdout
    var label: String?
    var body: String?
    var text: String?
    // prompt, notice
    var prompt: Prompt?

    struct OneCall: Codable, Equatable {
        var label: String
        var detail: String
        var chip: String
        var state: String
    }
}

/// A Markdown block the PC cut out of a reply: p, h, list, quote, code, table, hr, media.
struct MD: Codable, Equatable {
    var t: String
    var text: String?
    var level: Int?
    var items: [MDItem]?
    var lang: String?
    var code: String?
    var head: [String]?
    var rows: [[String]]?
    var align: [String]?
    /// a `mockups` block's set (MockupSet.swift)
    var set: MockupSet?
    /// sent for apps from before the set card; this app skips it
    var fallback: Bool?
}

/// A list item (level, text, n, done) or a picture/video/audio file (kind, url, name, poster; audio: duration,
/// peaks, error).
struct MDItem: Codable, Equatable {
    var level: Int?
    var text: String?
    var n: Int?
    var done: Bool?
    var kind: String?
    var url: String?
    var name: String?
    var poster: String?
    /// audio (a157): its length in seconds and 96 loudness values 0-100 across it, or why it can't play
    var duration: Double?
    var peaks: [Int]?
    var error: String?
}

/// What a turn keeps outside its fold: threads it started, helpers, changed files, a thread's question.
struct Outside: Codable, Equatable, Identifiable {
    var type: String            // threads | helpers | changes | ask
    var id: String
    var title: String?
    var stats: String?
    var folded: Bool?
    var add: Int?
    var del: Int?
    var files: [FileChange]?
    var threads: [ThreadInfo]?
    var helpers: [HelperInfo]?
    var answered: Bool?
    var call: String?
    var work: String?
    var question: String?
    var options: [String]?
    var model: String?

    struct FileChange: Codable, Equatable {
        var path: String
        var add: Int
        var del: Int
        var created: Bool?
    }

    struct ThreadInfo: Codable, Equatable {
        var id: String
        var title: String
        var model: String
    }

    struct HelperInfo: Codable, Equatable {
        var id: String
        var title: String
        var line: String
        var state: String
    }
}

/// GET …/cards/<id>: one step card in full.
struct CardDetail: Codable, Equatable {
    var id: String
    var title: String
    var state: String
    var stats: String
    var intent: String?
    var add: Int?
    var del: Int?
    var since: Double?
    var rows: [CallRow]
}

struct CallRow: Codable, Equatable, Identifiable {
    var id: String
    var tool: String
    var state: String           // ok | error | running | stopped
    var label: String
    var detail: String
    var chip: String
    var ms: Double?
    var since: Double?
    var add: Int?
    var del: Int?
    var command: String?
    var out: Output?
    var diff: Diff?
    var plan: [PlanItem]?

    struct Output: Codable, Equatable {
        var head: [String]
        var tail: [String]
        var total: Int
        var failed: Bool
    }

    struct Diff: Codable, Equatable {
        var path: String
        var lines: [DiffLine]
    }

    struct DiffLine: Codable, Equatable {
        var k: String           // + | - | " " | gap | more
        var n: Int
        var text: String
    }

    struct PlanItem: Codable, Equatable {
        var content: String
        var state: String       // done | doing | todo
    }
}

/// A demo chat (mobile/fixtures/chats/<id>.json): what the PC would answer, recorded at `now`.
struct ChatFixture: Codable {
    var now: Double
    var header: ChatHeader
    var status: ChatStatus
    var turns: TurnsPage
    var cards: [String: CardDetail]
}

extension Format {
    /// The desktop's live clock: "0:07", "1:02", "1:02:03".
    static func clock(_ ms: Double) -> String {
        let s = max(0, Int(ms / 1000))
        let ss = String(format: "%02d", s % 60)
        if s < 3600 { return "\(s / 60):\(ss)" }
        return "\(s / 3600):" + String(format: "%02d", (s / 60) % 60) + ":\(ss)"
    }

    /// The desktop's step time: "0.4s", "12s", "1m 5s".
    static func duration(_ ms: Double) -> String {
        let ms = max(0, ms)
        if ms < 10_000 { return String(format: "%.1fs", ms / 1000) }
        let s = Int((ms + 500) / 1000)
        if s < 60 { return "\(s)s" }
        return "\(s / 60)m \(s % 60)s"
    }

    /// "Sonnet 5.5" -> "Sonnet": the thread card's short model name
    static func shortModel(_ label: String) -> String {
        label.split(separator: " ").first.map(String.init) ?? label
    }
}

/// Where a picture or video link points: the PC's signed /v1/media/… link (no bearer needed), or a demo file in the
/// app's bundle (`demo:media/<name>`).
enum MediaLink {
    static func url(_ link: String?, base: URL?) -> URL? {
        guard let link, !link.isEmpty else { return nil }
        if link.hasPrefix("demo:") {
            let rel = String(link.dropFirst(5))           // media/dusk.png
            let name = (rel as NSString).lastPathComponent
            let dir = (rel as NSString).deletingLastPathComponent
            let sub = dir.isEmpty ? "fixtures" : "fixtures/" + dir
            return Demo.file(name, in: sub)
        }
        if link.hasPrefix("file://"), Demo.isOn {
            return URL(string: link)                     // a file the demo "sent" (a144): its copy on this phone
        }
        if link.hasPrefix("/v1/media/"), let base {
            return URL(string: link, relativeTo: base)?.absoluteURL
        }
        return nil
    }
}
