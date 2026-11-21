import Foundation


// The needs-you bar on the phone (a230, docs/needs-phone-mockups/round1 Option 4 "Card deck"): the desktop bar's
// items as gw3-phone sends them in /v1/home (`needs`, tools/gw3_needs.py) and the deck's rules: which wait and in
// what order, the chip, what each card offers. The snoozes and dismissals come from the PC's one shared file, so the
// desktop's bar and the phone always agree; `dropped` only bridges the moment between a tap and the PC's next list.

/// /v1/home `needs`: every item (any order) with the snoozes and dismissals, and the parked projects.
struct NeedsState: Codable, Equatable {
    var items: [NeedItem]
    var parked: [ParkedProject]
    var snoozed: [String: Double]
    var dismissed: [String: Double]

    static let empty = NeedsState(items: [], parked: [], snoozed: [:], dismissed: [:])
}

struct ParkedProject: Codable, Equatable, Hashable {
    var projectId: String
    var name: String
}

/// One thing that waits on you. `key` is the desktop's (`ask:<project>:<q3>`, `chat:<chat>:<sig>`,
/// `memory:<id>`): a notification that names it opens the deck at its card.
struct NeedItem: Codable, Equatable, Identifiable, Hashable {
    var key: String
    var kind: String            // ask | next | question | permission | plan | open | memory
    var source: String          // project | chat | memory
    var projectId: String?
    var askId: String?
    var chatId: String?
    var name: String
    var title: String
    var question: String?
    var summary: String?
    var body: [String]?         // a permission's command, a plan's lines (a plain chat's dialog)
    var options: [Option]
    var recommended: Int
    var other: Bool             // "Something else…" typed in place
    var otherChoice: Int?
    var since: Double
    var sig: String?
    var work: String?           // a thread's question: "a21"
    var workTitle: String?
    var pictures: [Picture]?

    struct Option: Codable, Equatable, Hashable {
        var label: String
        var detail: String?
        var n: Int?
    }

    struct Picture: Codable, Equatable, Hashable {
        var url: String
        var caption: String?
    }

    var id: String { key }
}

enum NeedTone: String, Equatable {
    case violet, amber, red, grey
}

/// The deck's rules (the desktop's src/NeedsQueue): pure, tested in NeedsDeckTests.
struct NeedsDeck: Equatable {
    /// waiting oldest first (as on the PC): not snoozed, not dismissed, not of a parked project
    private(set) var waiting: [NeedItem]
    /// the parked projects with how many items each holds meanwhile
    private(set) var parked: [(project: ParkedProject, items: Int)]

    static func == (a: NeedsDeck, b: NeedsDeck) -> Bool {
        a.waiting == b.waiting && a.parked.map(\.project) == b.parked.map(\.project) && a.parked.map(\.items) == b.parked.map(\.items)
    }

    /// `now` in the PC's milliseconds; `dropped`: keys the phone answered, snoozed or dismissed a moment ago
    init(_ state: NeedsState?, now: Double, dropped: Set<String> = []) {
        let s = state ?? .empty
        let parkedIds = Set(s.parked.map(\.projectId))
        var counts: [String: Int] = [:]
        var out: [NeedItem] = []
        for i in s.items {
            if dropped.contains(i.key) { continue }
            if let d = s.dismissed[i.key], d >= i.since { continue }
            if i.source == "project", let p = i.projectId, parkedIds.contains(p) {
                counts[p, default: 0] += 1
                continue
            }
            if let until = s.snoozed[i.key], until > now { continue }
            out.append(i)
        }
        waiting = out.sorted { $0.since != $1.since ? $0.since < $1.since : $0.key < $1.key }
        parked = s.parked.map { ($0, counts[$0.projectId] ?? 0) }
    }

    /// nothing waits and nothing is parked: no chip
    var shown: Bool { !waiting.isEmpty || !parked.isEmpty }

    /// the chip under the chat's title: "5 need you" in the most pressing colour, or "1 parked" in grey
    var chip: (text: String, tone: NeedTone)? {
        if let first = waiting.first {
            let tone: NeedTone = waiting.contains { $0.kind == "memory" } ? .red : Self.tone(of: first)
            return ("\(waiting.count) need\(waiting.count == 1 ? "s" : "") you", tone)
        }
        return parked.isEmpty ? nil : ("\(parked.count) parked", .grey)
    }

    /// violet for questions, amber when a chat waits (a permission, or a chat to open), red for memory
    static func tone(of item: NeedItem) -> NeedTone {
        switch item.kind {
        case "memory": return .red
        case "permission", "open": return .amber
        default: return .violet
        }
    }

    func index(of key: String?) -> Int? {
        guard let key else { return nil }
        return waiting.firstIndex { $0.key == key }
    }

    /// The card to show after the waiting list changed: the same one, else the one now in its place (the next),
    /// else the oldest (NeedsQueue::rebuild).
    func current(after key: String?, was index: Int?) -> Int? {
        if waiting.isEmpty { return nil }
        if let i = self.index(of: key) { return i }
        if let i = index { return min(i, waiting.count - 1) }
        return 0
    }

    /// "1 of 5"
    func position(_ index: Int) -> String { "\(index + 1) of \(waiting.count)" }

    /// How long it has waited: "40s", "12m", "1h 5m", "3d 2h" (needsWait in src/NeedsQueue.cpp)
    static func wait(_ ms: Double) -> String {
        let ms = max(0, ms)
        let m = Int(ms / 60_000)
        if m < 1 { return "\(Int(ms / 1000))s" }
        if m < 60 { return "\(m)m" }
        if m < 24 * 60 { return m % 60 != 0 ? "\(m / 60)h \(m % 60)m" : "\(m / 60)h" }
        let h = m / 60
        return h % 24 != 0 ? "\(h / 24)d \(h % 24)h" : "\(h / 24)d"
    }
}

/// What one card offers (docs/needs-phone-mockups README "Every feature" 3, 9, 10).
struct NeedCard: Equatable {
    struct Answer: Equatable {
        var label: String
        var detail: String
        var recommended: Bool
    }

    var answers: [Answer]
    /// "Something else…" typed in place, its field starting with `prefix` ("a21: " for a thread's question)
    var somethingElse: Bool
    var prefix: String
    /// a chat that waits with several answers, tabs or no dialog to read: answered in the chat
    var openOnly: Bool
    var memory: Bool
    /// the dialog's own lines (a permission's command) and the question's pictures
    var body: [String]
    var pictures: [NeedItem.Picture]
    /// the line under the source: "12m"
    var headline: String
    var text: String
    var summary: String

    init(_ item: NeedItem) {
        let rec = item.recommended
        answers = item.options.enumerated().map { i, o in
            Answer(label: o.label, detail: o.detail ?? "", recommended: i == rec)
        }
        openOnly = item.kind == "open" || (item.options.isEmpty && item.kind != "memory")
        somethingElse = item.other && !openOnly
        prefix = (item.work ?? "").isEmpty ? "" : "\(item.work!): "
        memory = item.kind == "memory"
        body = item.body ?? []
        pictures = item.pictures ?? []
        headline = item.title
        let q = (item.question ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        switch item.kind {
        case "permission":
            text = item.title
            summary = q
        case "memory":
            text = item.title
            summary = item.summary ?? ""
        case "open":
            text = item.title
            summary = item.sig == nil ? "It waits on you in the chat." : "Several answers or tabs: answer it in the chat."
        default:
            text = q.isEmpty ? item.title : (item.work.map { "\($0): " } ?? "") + q
            summary = item.summary ?? ""
        }
    }
}

extension NeedItem {
    /// the list's line and the card's head: "a21: Ship the new gallery grid?" for a thread's question
    var listTitle: String {
        if kind == "open", sig != nil { return "Several answers: open the chat" }
        return (work ?? "").isEmpty ? title : "\(work!): \(title)"
    }
    /// the chat Open chat opens (the project's main chat, or the plain chat); none for the memory warning
    var openChat: String? { kind == "memory" ? nil : chatId }
}

// MARK: the routes

/// POST /v1/needs/<answer | snooze | dismiss | park>
struct NeedsAction: Codable, Equatable {
    var key: String?
    var option: Int?
    var text: String?
    var projectId: String?
    var parked: Bool?
}

struct NeedsReply: Codable, Equatable {
    var ok: Bool
    var needs: NeedsState?
    var chatId: String?
}

/// POST /v1/memory/sleep: one chat ({chatId}) as the Memory page's Sleep, or every idle one ({all: true})
struct SleepBody: Codable, Equatable {
    var chatId: String?
    var all: Bool?
}

/// /chat/sleep's answer ({chat, slept, reasons}) or /chat/sleep-idle's ({slept: [{chat}], awake, unreadable}), with
/// the memory numbers again
struct SleepReply: Codable, Equatable {
    var chat: String?
    var sleptOne: Bool?
    var reasons: [String]?
    var sleptChats: [String]?
    var awakeCount: Int?
    var memory: MemoryView?

    private struct ChatRef: Codable { var chat: String }
    enum CodingKeys: String, CodingKey { case chat, slept, reasons, awake, unreadable, memory }

    init(chat: String? = nil, sleptOne: Bool? = nil, reasons: [String]? = nil, sleptChats: [String]? = nil,
         awakeCount: Int? = nil, memory: MemoryView? = nil) {
        self.chat = chat; self.sleptOne = sleptOne; self.reasons = reasons; self.sleptChats = sleptChats
        self.awakeCount = awakeCount; self.memory = memory
    }

    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        chat = try c.decodeIfPresent(String.self, forKey: .chat)
        reasons = try c.decodeIfPresent([String].self, forKey: .reasons)
        memory = try c.decodeIfPresent(MemoryView.self, forKey: .memory)
        if let one = try? c.decode(Bool.self, forKey: .slept) {
            sleptOne = one
        } else if let many = try? c.decode([ChatRef].self, forKey: .slept) {
            sleptChats = many.map(\.chat)
            let awake = (try? c.decode([ChatRef].self, forKey: .awake))?.count ?? 0
            let unreadable = (try? c.decode([ChatRef].self, forKey: .unreadable))?.count ?? 0
            awakeCount = awake + unreadable
        }
    }

    func encode(to e: Encoder) throws {
        var c = e.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(chat, forKey: .chat)
        try c.encodeIfPresent(sleptOne, forKey: .slept)
        try c.encodeIfPresent(reasons, forKey: .reasons)
        try c.encodeIfPresent(memory, forKey: .memory)
    }

    /// what the Memory sheet says after it (MemoryPage::sleep / sleepAll's words)
    var words: String {
        if let one = sleptOne {
            return one ? "Asleep" : "Stays awake: " + (reasons?.first ?? "not safe to stop now")
        }
        let n = sleptChats?.count ?? 0
        let awake = awakeCount ?? 0
        return (n == 1 ? "1 chat put to sleep" : "\(n) chats put to sleep")
            + (awake > 0 ? "; \(awake) stay awake (busy, used in the last 5 min, or shown)" : "")
    }
}

/// GET /v1/memory: the desktop Memory page's numbers (<run>/memory.json)
struct MemoryView: Codable, Equatable {
    var ts: Double?
    var level: Int?
    var levelName: String?
    var availPct: Double?
    var swapPct: Double?
    var ram: Ram?
    var swap: Swap?
    var gupworks: Share?
    var asleep: Int?
    var chats: [ChatUse]?
    var others: [Other]?
    var warning: Warning?
    var stale: Bool?
    var thresholds: [String: Double]?

    struct Ram: Codable, Equatable { var total: Double; var used: Double; var available: Double? }
    struct Swap: Codable, Equatable {
        var total: Double
        var used: Double
        var zram: Zram?
        var disk: Disk?
    }
    struct Zram: Codable, Equatable { var size: Double; var used: Double; var ram: Double? }
    struct Disk: Codable, Equatable { var size: Double; var used: Double }
    struct Share: Codable, Equatable { var total: Double; var chats: Double; var count: Int }
    struct ChatUse: Codable, Equatable, Identifiable {
        var chat: String
        var name: String
        var kind: String?
        var kindLabel: String?
        var project: String?
        var used: Double
        var swap: Double?
        var files: Double?
        var max: Double?
        var nearLimit: Bool?
        var id: String { chat }
    }
    struct Other: Codable, Equatable, Hashable { var label: String; var used: Double }
    struct Warning: Codable, Equatable { var id: String?; var ts: Double?; var text: String? }
}

/// The Memory sheet's words (src/MemoryPage.cpp), testable on Linux.
enum MemoryText {
    /// "3.8 GB", "58 GB"
    static func gb(_ bytes: Double) -> String {
        let v = bytes / Double(1 << 30)
        return v < 10 ? String(format: "%.1f GB", v) : "\(Int(v.rounded())) GB"
    }

    static func state(_ m: MemoryView) -> String {
        switch m.level ?? 0 {
        case 2...: return "Memory is nearly full"
        case 1: return "Memory is getting tight: GupWorks puts idle chats to sleep"
        default: return "Memory is fine"
        }
    }

    /// the warning without its first words (the state line says them)
    static func warning(_ m: MemoryView) -> String? {
        guard var t = m.warning?.text, !t.isEmpty else { return nil }
        let lead = "Memory is nearly full: "
        if t.hasPrefix(lead) { t = String(t.dropFirst(lead.count)); t = t.prefix(1).uppercased() + t.dropFirst() }
        return t
    }

    static func ram(_ m: MemoryView) -> (value: String, hint: String, pct: Double) {
        let r = m.ram ?? .init(total: 0, used: 0, available: 0)
        return ("\(gb(r.used)) of \(gb(r.total)) in use", "\(gb(r.available ?? 0)) available", 100 - (m.availPct ?? 0))
    }

    static func swap(_ m: MemoryView) -> (value: String, hint: String, pct: Double) {
        let s = m.swap ?? .init(total: 0, used: 0)
        var hint = s.zram.map { "Compressed swap in RAM (zram): it holds \(gb($0.used)) in \(gb($0.ram ?? 0)) of RAM" } ?? ""
        if let d = s.disk {
            hint += (hint.isEmpty ? "" : "  ·  ") + "on disk \(gb(d.used)) of \(gb(d.size))"
        }
        return ("\(gb(s.used)) of \(gb(s.total)) in use", hint, m.swapPct ?? 0)
    }

    /// 0 fine, 1 tight, 2 full: the bar's colour
    static func level(ram m: MemoryView) -> Int {
        let pct = 100 - (m.availPct ?? 100)
        let th = m.thresholds ?? [:]
        return pct > 100 - (th["fullAvail"] ?? 10) ? 2 : pct > 100 - (th["tightAvail"] ?? 20) ? 1 : 0
    }

    static func level(swap m: MemoryView) -> Int {
        let pct = m.swapPct ?? 0
        let th = m.thresholds ?? [:]
        return pct > (th["fullSwap"] ?? 75) ? 2 : pct > (th["tightSwap"] ?? 50) ? 1 : 0
    }

    static func share(_ m: MemoryView) -> (total: String, parts: String) {
        let g = m.gupworks ?? .init(total: 0, chats: 0, count: 0)
        var parts = "\(g.count) running chat\(g.count == 1 ? "" : "s") \(gb(g.chats)), the window and services \(gb(g.total - g.chats))"
        if let a = m.asleep, a > 0 { parts += "  ·  \(a) asleep (no memory)" }
        return ("\(gb(g.total)) in all", parts)
    }

    /// a chat row's second line
    static func hint(_ c: MemoryView.ChatUse) -> String {
        if c.nearLimit == true { return "Near its \(gb(c.max ?? 0)) limit: past it, its biggest process is stopped" }
        var k = c.kindLabel ?? ""
        k = k.prefix(1).uppercased() + k.dropFirst()
        if let f = c.files, f >= Double(1 << 30) { return k + "  ·  \(gb(f)) of it is files in /tmp, freed only by deleting them" }
        if let s = c.swap, s > Double(256 << 20) { return k + "  ·  \(gb(s)) of it in swap" }
        return k
    }
}

