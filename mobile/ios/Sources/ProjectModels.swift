import Foundation

// Slice 6: what gw3-phone's project routes send (tools/gw3_phone.py, "Slice 6"); the demo's copy is
// mobile/fixtures/projects/<id>.json.

/// GET /v1/projects/<id> (and each `project` event): the desktop panel's threads, groups, usage and info.
struct ProjectView: Codable, Equatable {
    var id: String
    var name: String
    var paused: Bool
    var archived: Bool
    var mainChatId: String?
    var now: Double
    var counts: Counts
    var quiet: [Quiet]
    var groups: [ThreadGroup]
    var usage: [UsageRow]
    var info: [InfoRow]
    // a121: the project's look and goal, and what its main chat asks you (the NEEDS YOU card, 05)
    var icon: String?
    var color: String?
    var goal: String?
    var mainNeeds: MainNeeds?

    struct Counts: Codable, Equatable {
        var threads: Int        // not done or archived
        var needs: Int
        var working: Int
        var checking: Int
        var schedules: Int
        var done: Int?
        var archived: Int?
        var library: Int?
        var ideas: Int?
    }

    /// The main chat's own question (notify_user): the card under its newest turn, with its answers.
    struct MainNeeds: Codable, Equatable {
        var text: String
        var question: String?
        var options: [String]?
        var work: String?
        var ts: Double?
        var ago: String?
        var chatId: String?
    }

    /// "1 needs you", "2 working" over the list (glyph: needs | spin | review)
    struct Quiet: Codable, Equatable, Hashable {
        var glyph: String
        var text: String
    }

    struct UsageRow: Codable, Equatable, Hashable {
        var title: String
        var value: String
        var detail: String
        var chatId: String?
        var expensive: Bool
    }

    struct InfoRow: Codable, Equatable, Hashable {
        var label: String
        var value: String
    }

    var allThreads: [ThreadItem] { groups.flatMap(\.threads) }
}

/// Needs you, Working, Being checked, Up next, Idle, Done, Archived (Done and Archived start folded).
struct ThreadGroup: Codable, Equatable, Identifiable {
    var state: String
    var label: String
    var count: Int
    var folded: Bool
    var threads: [ThreadItem]

    var id: String { state }
}

/// One thread row, as the panel draws it.
struct ThreadItem: Codable, Equatable, Identifiable {
    var id: String              // a6
    var title: String
    var chatId: String?
    var state: String
    var status: String
    var glyph: String           // needs | spin | idle | pause | review | ring | check | cross
    var part: String
    var detail: String
    var holds: [String]
    var right: String           // the model, or a done thread's commit
    var usage: String           // "167K"
    var expensive: Bool
    var muted: Bool
    var doneOk: Bool
    var moves: [String]         // pause | resume | stop | done | archive | unarchive
    // a121: the Overview's and the chat cards' words: "needs you", "landed"; the line under the title; "Sonnet high"
    var word: String?
    var line: String?
    var modelLabel: String?
    var ago: String?
}

/// GET …/library (or ?folder=): Pinned, Notes, From threads; a folder's notes.
struct LibraryList: Codable, Equatable {
    var folder: String?
    var title: String
    var count: Int
    var groups: [LibraryGroup]
}

struct LibraryGroup: Codable, Equatable, Identifiable {
    var id: String
    var label: String
    var count: Int?
    var items: [LibraryRow]
}

struct LibraryRow: Codable, Equatable, Identifiable, Hashable {
    var path: String
    var kind: String            // note | folder | image | file
    var title: String
    var sub: String
    var mtime: Double
    var exists: Bool
    var workId: String?
    var editable: Bool
    var thumb: String?          // a picture's small copy (a121)
    var url: String?
    var group: String?

    var id: String { path }
}

/// GET …/library/file: a note's text and how it reads, a picture's link, or a file the phone only names.
struct LibraryFile: Codable, Equatable {
    var path: String
    var kind: String
    var title: String
    var name: String
    var editable: Bool
    var text: String?
    var version: String?
    var url: String?
    var mtime: Double
    var blocks: [MD]?
}

/// PUT …/library/file: the text to save over `version` (what the phone opened); `force` saves over a change.
struct NoteSave: Codable, Equatable {
    var path: String
    var text: String
    var version: String?
    var force: Bool?
}

struct NoteSaved: Codable, Equatable {
    var ok: Bool
    var path: String
    var version: String
    var mtime: Double
    var blocks: [MD]?
}

/// GET …/schedules: Scheduled and Paused.
struct ScheduleList: Codable, Equatable {
    var groups: [ScheduleGroup]
    var count: Int
    var footer: String
    var past: [ScheduleRun]?    // a121: the newest runs of every schedule
    var empty: String?
}

/// One run of a schedule: the thread it made (or why it didn't run).
struct ScheduleRun: Codable, Equatable, Hashable {
    var title: String
    var line: String
    var status: String          // ok | failed | skipped | running
    var at: Double
    var workId: String?
    var chatId: String?
    var glyph: String
}

struct ScheduleGroup: Codable, Equatable, Identifiable {
    var label: String
    var count: Int
    var items: [ScheduleRow]

    var id: String { label }
}

struct ScheduleRow: Codable, Equatable, Identifiable {
    var id: String
    var title: String
    var when: String
    var paused: Bool
    var running: Bool
    var lastStatus: String?
    var chatId: String?
    var right: String
    var last: String
    var nextRun: Double?
    // a121
    var whenText: String?
    var skipped: Bool?
    var next: String?
    var prompt: String?
    var model: String?
    var effort: String?
    var runs: [ScheduleRun]?
}

/// POST …/threads: the new thread and the view with it.
struct NewThreadReply: Codable, Equatable {
    var workId: String?
    var chatId: String?
    var project: ProjectView
}

/// mobile/fixtures/projects/<id>.json: one project's answers for the demo.
struct ProjectFixture: Codable {
    var now: Double
    var view: ProjectView
    var library: LibraryList
    var folders: [String: LibraryList]
    var files: [String: LibraryFile]
    var schedules: ScheduleList
    var settings: ProjectSettings?
    var ideas: IdeasList?
    var usage: ProjectUsage?
}

// MARK: a121's project pages (docs/projects-mobile-mockups): new project, settings, ideas, usage

/// POST /v1/projects: a new project; the PC makes its folder, git and notes, copies the files into its Library
/// and starts its main chat.
struct NewProjectBody: Codable, Equatable {
    var name: String
    var goal: String
    var icon: String?
    var color: String?
    var folder: String          // "new" or a folder from FoldersReply
    var files: [String]
    var clientId: String
}

struct NewProjectReply: Codable, Equatable {
    var projectId: String
    var mainChatId: String?
    var running: Bool
    var name: String
}

/// GET /v1/projects/folders: the folders in the projects folder a project can start in, newest first.
struct FoldersReply: Codable, Equatable {
    var root: String            // the projects folder, short (home as a tilde)
    var folders: [ProjectFolder]
}

struct ProjectFolder: Codable, Equatable, Identifiable, Hashable {
    var name: String
    var path: String
    var short: String
    var git: Bool
    var project: String?        // the project already in it
    var mtime: Double

    var id: String { path }
}

/// GET …/settings (11), and what a PATCH answers.
struct ProjectSettings: Codable, Equatable {
    var id: String
    var name: String
    var icon: String?
    var color: String?
    var goal: String
    var instructions: String
    var folder: String
    var notes: String
    var parts: [String]
    var mainModel: String
    var mainEffort: String
    var mainLabel: String
    var threadModels: [String: String]
    var threadLabel: String
    var usage: String
    var paused: Bool
    var archived: Bool
    var models: [ModelInfo]
}

/// PATCH /v1/projects/<id>: only what changed is sent.
struct ProjectPatch: Codable, Equatable {
    var name: String?
    var goal: String?
    var instructions: String?
    var icon: String?
    var color: String?          // "" is no colour
    var mainModel: String?
    var mainEffort: String?
    var threadModel: String?
    var threadEffort: String?
}

/// GET …/ideas (09): the Ideas note by its sections.
struct IdeasList: Codable, Equatable {
    var title: String
    var path: String
    var mtime: Double
    var sections: [IdeasSection]
    var count: Int
}

struct IdeasSection: Codable, Equatable, Identifiable {
    var name: String
    var items: [IdeaItem]
    var empty: String

    var id: String { name }
}

struct IdeaItem: Codable, Equatable, Hashable {
    var raw: String             // the line as written, what an edit or delete names
    var text: String
    var date: String?
    var ai: Bool
}

/// POST …/ideas/change: edit | delete | move one idea (`old` is its raw line).
struct IdeaChange: Codable, Equatable {
    var op: String
    var section: String
    var old: String
    var text: String?
    var to: String?
}

/// GET …/usage (12).
struct ProjectUsage: Codable, Equatable {
    var total: Double
    var totalText: String
    var since: String
    var main: Double
    var mainText: String
    var threads: Double
    var threadsText: String
    var threadCount: Int
    var models: [Model]
    var biggest: [Big]
    var cacheReads: Int
    var plan: Plan?
    var footer: String

    struct Model: Codable, Equatable, Hashable {
        var name: String
        var tokens: Double
        var value: String
        var percent: Int
    }

    struct Big: Codable, Equatable, Hashable {
        var id: String
        var title: String
        var chatId: String?
        var line: String
        var value: String
        var state: String
        var glyph: String
    }

    struct Plan: Codable, Equatable {
        var fiveHour: Double?
        var week: Double?
    }
}

/// POST …/library/add: the files copied in, and the Library with them.
struct LibraryAddReply: Codable, Equatable {
    var added: [String]
    var library: LibraryList
}

/// GET /v1/search?in=projects: projects whose chats say the words (the Projects page's search).
struct ProjectSearchReply: Codable, Equatable {
    var projects: [ProjectHit]
}

struct ProjectHit: Codable, Equatable, Identifiable {
    var id: String
    var name: String
    var chatId: String
    var title: String
    var snippet: String
}

// MARK: the home list's folders (projects-ui.json's sidebarFolders, as the desktop sidebar has them)

/// One entry of Home.layout: a project on its own, or a folder of projects.
struct LayoutEntry: Codable, Equatable {
    var project: String?
    var folder: Folder?
    var projects: [String]?

    struct Folder: Codable, Equatable {
        var id: String
        var name: String
        var collapsed: Bool
    }
}

/// The Projects section's rows: projects in the desktop's order, folders with theirs (projects the layout
/// doesn't name come last, as on the desktop).
enum ProjectLayout {
    enum Row: Equatable, Identifiable {
        case project(ProjectRow, inFolder: Bool)
        case folder(LayoutEntry.Folder, count: Int)

        var id: String {
            switch self {
            case .project(let p, _): return "p-" + p.id
            case .folder(let f, _): return "f-" + f.id
            }
        }
    }

    /// `open` says which folders are open (by id); a folder not in it uses its own `collapsed`.
    static func rows(_ projects: [ProjectRow], layout: [LayoutEntry]?, open: [String: Bool]) -> [Row] {
        guard let layout, !layout.isEmpty else { return projects.map { .project($0, inFolder: false) } }
        let byId = Dictionary(projects.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var used = Set<String>()
        var out: [Row] = []
        for e in layout {
            if let f = e.folder {
                let inside = (e.projects ?? []).compactMap { byId[$0] }.filter { !used.contains($0.id) }
                guard !inside.isEmpty else { continue }
                used.formUnion(inside.map(\.id))
                out.append(.folder(f, count: inside.count))
                if open[f.id] ?? !f.collapsed {
                    out += inside.map { .project($0, inFolder: true) }
                }
            } else if let id = e.project, let p = byId[id], !used.contains(id) {
                used.insert(id)
                out.append(.project(p, inFolder: false))
            }
        }
        out += projects.filter { !used.contains($0.id) }.map { .project($0, inFolder: false) }
        return out
    }
}

// MARK: the demo's thread moves (nothing leaves the phone)

enum DemoProject {
    static let order = ["needs-you", "working", "checking", "up-next", "idle", "done", "archived"]
    static let labels = ["needs-you": "Needs you", "working": "Working", "checking": "Being checked",
                         "up-next": "Up next", "idle": "Idle", "done": "Done", "archived": "Archived"]

    /// The view after `move` on thread `id`, as the PC's would read (states, glyphs, moves, counts).
    static func apply(_ move: String, to id: String, in v: ProjectView) -> ProjectView {
        var threads = v.allThreads
        guard let i = threads.firstIndex(where: { $0.id == id }) else { return v }
        var t = threads[i]
        switch move {
        case "pause":
            (t.status, t.state, t.glyph, t.moves) = ("paused", "idle", "pause", ["resume", "stop", "done", "archive"])
            t.detail = "paused"
        case "resume":
            (t.status, t.state, t.glyph, t.moves) = ("running", "working", "spin", ["pause", "stop", "archive"])
            t.detail = "Picking up where it stopped"
        case "stop":
            (t.status, t.state, t.glyph, t.moves) = ("stopped", "idle", "idle", ["done", "archive"])
        case "done":
            (t.status, t.state, t.glyph, t.moves, t.doneOk) = ("accepted", "done", "check", ["archive"], true)
        case "archive":
            (t.state, t.moves) = ("archived", ["unarchive"])
        case "unarchive":
            t.state = t.status == "accepted" ? "done" : "idle"
            t.moves = ["archive"]
        default:
            return v
        }
        threads[i] = t
        return regroup(v, threads)
    }

    /// A thread started from the phone: it shows as working at once.
    static func add(_ text: String, to v: ProjectView) -> ProjectView {
        let n = v.allThreads.count + 1
        let title = text.split(separator: "\n").first.map { String($0.prefix(60)) } ?? "New thread"
        let t = ThreadItem(id: "d\(n)", title: title, chatId: nil, state: "working", status: "running", glyph: "spin",
                           part: "", detail: "Starting", holds: [], right: "Sonnet", usage: "", expensive: false,
                           muted: false, doneOk: false, moves: ["pause", "stop", "archive"])
        return regroup(v, [t] + v.allThreads)
    }

    static func regroup(_ v: ProjectView, _ threads: [ThreadItem]) -> ProjectView {
        var out = v
        out.groups = order.compactMap { s in
            let items = threads.filter { $0.state == s }
            guard !items.isEmpty else { return nil }
            let was = v.groups.first { $0.state == s }
            return ThreadGroup(state: s, label: labels[s] ?? s, count: items.count,
                               folded: was?.folded ?? (s == "done" || s == "archived"), threads: items)
        }
        let count = { (s: String) in threads.filter { $0.state == s }.count }
        out.counts.threads = threads.filter { $0.state != "done" && $0.state != "archived" }.count
        out.counts.needs = count("needs-you")
        out.counts.working = count("working")
        out.counts.checking = count("checking")
        out.quiet = []
        if out.counts.needs > 0 {
            out.quiet.append(.init(glyph: "needs", text: out.counts.needs == 1 ? "1 needs you"
                                                     : "\(out.counts.needs) need you"))
        }
        if out.counts.working > 0 { out.quiet.append(.init(glyph: "spin", text: "\(out.counts.working) working")) }
        if out.counts.checking > 0 {
            out.quiet.append(.init(glyph: "review", text: "\(out.counts.checking) being checked"))
        }
        return out
    }

    /// The demo's own rough Markdown for a saved note (the PC renders the real one).
    static func blocks(_ text: String) -> [MD] {
        var out: [MD] = []
        var items: [MDItem] = []
        var table: [[String]] = []
        func flush() {
            if !items.isEmpty { out.append(MD(t: "list", items: items)); items = [] }
            if let head = table.first {
                out.append(MD(t: "table", head: head, rows: Array(table.dropFirst()),
                              align: head.map { _ in "left" }))
                table = []
            }
        }
        func cells(_ line: String) -> [String] {
            line.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "|"))
                .components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
        }
        for para in text.components(separatedBy: "\n\n") {
            for line in para.split(separator: "\n").map(String.init) {
                if line.hasPrefix("|") {
                    if !items.isEmpty { out.append(MD(t: "list", items: items)); items = [] }
                    let c = cells(line)
                    // the |---|---| line under the head
                    if !c.allSatisfy({ $0.allSatisfy { "-:".contains($0) } }) { table.append(c) }
                    continue
                }
                if !table.isEmpty { flush() }
                if line.hasPrefix("#") {
                    flush()
                    let level = line.prefix { $0 == "#" }.count
                    out.append(MD(t: "h", text: line.dropFirst(level).trimmingCharacters(in: .whitespaces), level: level))
                } else if line.hasPrefix("- ") {
                    items.append(MDItem(level: 0, text: String(line.dropFirst(2))))
                } else {
                    flush()
                    out.append(MD(t: "p", text: line))
                }
            }
            flush()
        }
        return out
    }
}
