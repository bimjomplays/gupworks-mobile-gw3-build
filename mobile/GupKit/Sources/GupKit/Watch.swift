import Foundation

// The Apple Watch app (a234, docs/watch-mockups/round2 Option 7 "Crown list with voice"): its plain rules, tested on
// Linux. What a card shows and in what order, the deck's order, the 5 s Undo every send waits out, what goes between
// the watch and the iPhone (WatchConnectivity: the iPhone keeps the watch's list, the watch hands its answers to the
// iPhone, which sends them to gw3-phone through the same routes as the notification buttons), and the dynamic
// notification's real answers. The watch target compiles this file and Needs.swift only (mobile/ios/project.yml), so
// nothing here may use the rest of GupKit; Push.swift maps a WatchSend onto the iPhone's PushAction.

// MARK: the card

enum WatchCardKind: String, Codable, Equatable {
    /// a question with answers (a project's ask, what's next, a chat's question or plan)
    case ask
    /// a chat wants to run something: Allow once / Deny, tap only
    case permission
    /// the PC's memory warning: Sleep idle chats / Dismiss
    case memory
    /// several questions at once, tabs, or nothing to read: Open on iPhone
    case phone
}

/// One needs-you item as the watch draws it (round 2's order: where it's from and how long it waited, the question,
/// the whole summary, the recommended answer with its detail, the other answers).
struct WatchCard: Equatable, Identifiable {
    struct Answer: Equatable, Hashable {
        /// its index in the item's options: what /v1/needs/answer takes
        var option: Int
        var label: String
        var detail: String
        var recommended: Bool
    }

    var key: String
    var kind: WatchCardKind
    var tone: NeedTone
    /// "Home server", a chat's title, or "The PC" for memory
    var source: String
    /// a plain chat (the speech bubble) rather than a project
    var chat: Bool
    var projectId: String?
    /// when it started waiting, the PC's milliseconds
    var since: Double
    /// the thread that asks: "a14", "Memory limits"
    var threadId: String?
    var threadTitle: String?
    /// the whole question (never cut)
    var question: String
    /// the whole summary; a permission's why
    var summary: String
    /// every answer with its detail, the recommended one first (empty for a permission, see allow / deny)
    var answers: [Answer]
    var allow: Answer?
    var deny: Answer?
    /// a permission's command as it will run
    var command: String?
    /// the mic: words of his own (an ask's "Something else", a permission's "No, and tell Claude what to do")
    var voice: Bool
    var pictures: [NeedItem.Picture]
    /// the memory card's Sleep idle chats
    var sleep: Answer?
    /// the waiting list's line: "a21: Ship the new gallery grid?", "Memory nearly full"
    var listTitle: String
    /// the same without the thread: "Ship the new gallery grid?" (the complication's second line, a235)
    var title: String

    var id: String { key }

    init(_ item: NeedItem) {
        key = item.key
        source = item.kind == "memory" ? "The PC" : item.name
        listTitle = item.kind == "memory" ? "Memory nearly full" : item.listTitle
        title = item.kind == "memory" ? "Memory nearly full"
            : item.kind == "open" && item.sig != nil ? "Several answers: open the chat" : item.title
        chat = item.source == "chat"
        projectId = item.projectId
        since = item.since
        tone = NeedsDeck.tone(of: item)
        let work = (item.work ?? "").trimmingCharacters(in: .whitespaces)
        threadId = work.isEmpty ? nil : work
        let wt = (item.workTitle ?? "").trimmingCharacters(in: .whitespaces)
        threadTitle = threadId == nil || wt.isEmpty ? nil : wt
        pictures = Array((item.pictures ?? []).prefix(2))
        let q = (item.question ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let sum = (item.summary ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let all = item.options.enumerated().map { i, o in
            Answer(option: i, label: o.label, detail: o.detail ?? "", recommended: i == item.recommended)
        }
        answers = []
        allow = nil
        deny = nil
        command = nil
        sleep = nil
        voice = false
        let labels = item.options.map(\.label)
        switch item.kind {
        case "memory":
            kind = .memory
            question = item.title
            summary = sum
            sleep = all.first { $0.label == "Sleep idle chats" } ?? all.first
        case "permission" where labels.contains("Allow once") && labels.contains("Deny"):
            kind = .permission
            question = item.title
            let body = (item.body ?? []).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            command = body.first ?? item.title
            let why = body.dropFirst().joined(separator: " ")
            summary = why.isEmpty ? sum : why
            allow = all.first { $0.label == "Allow once" }
            deny = all.first { $0.label == "Deny" }
            voice = item.other
        case "open", "permission":
            kind = .phone
            question = item.title
            summary = sum.isEmpty ? (item.sig != nil ? "Several questions at once: answer them on your iPhone."
                                                     : "It waits on you in the chat.") : sum
        default:
            if item.options.isEmpty {
                kind = .phone
                question = q.isEmpty ? item.title : q
                summary = sum.isEmpty ? "It waits on you in the chat." : sum
            } else {
                kind = .ask
                question = q.isEmpty ? item.title : q
                summary = sum
                answers = all.filter(\.recommended) + all.filter { !$0.recommended }
                voice = item.other
            }
        }
    }

    /// The bar's right button: the recommended answer, or a permission's Allow once.
    var primary: Answer? { kind == .permission ? allow : answers.first { $0.recommended } }

    /// A double tap sends `primary`: only a question's recommended answer, never a command.
    var doubleTap: Bool { kind == .ask && primary != nil }

    /// The fixed bar (mic left, `primary` right) on every card with answers.
    var bar: Bool { (kind == .ask || kind == .permission) && (primary != nil || voice) }

    /// "a14 · Memory limits"
    var thread: String? { threadId.map { id in threadTitle.map { "\(id) · \($0)" } ?? id } }

    /// who gets a voice answer: "Home server · a14"
    var to: String { threadId.map { "\(source) · \($0)" } ?? source }

    /// "Home server · 12m"
    func head(now: Double) -> String { "\(source) · \(WatchCard.wait(now - since))" }

    /// how long it waited: "now" under a minute, else as the phone and desktop say it ("12m", "1h 5m")
    static func wait(_ ms: Double) -> String { ms < 60_000 ? "now" : NeedsDeck.wait(ms) }
}

// MARK: the deck

struct WatchParked: Equatable, Hashable {
    var projectId: String
    var name: String
    var items: Int
}

/// The cards in their order: the memory warning first while it lasts, then oldest first (the phone's and desktop's
/// order), without what is snoozed, dismissed, parked or answered on this watch a moment ago.
struct WatchDeck: Equatable {
    private(set) var cards: [WatchCard]
    private(set) var parked: [WatchParked]

    init(_ state: NeedsState?, now: Double, off: Set<String> = []) {
        let deck = NeedsDeck(state, now: now, dropped: off)
        let waiting = deck.waiting.map(WatchCard.init)
        cards = waiting.filter { $0.kind == .memory } + waiting.filter { $0.kind != .memory }
        parked = deck.parked.map { WatchParked(projectId: $0.project.projectId, name: $0.project.name, items: $0.items) }
    }

    func index(of key: String?) -> Int? {
        guard let key else { return nil }
        return cards.firstIndex { $0.key == key }
    }

    /// The card to show after the list changed: the same one, else the one now in its place (the next), else the first.
    func current(after key: String?, was index: Int?) -> Int? {
        if cards.isEmpty { return nil }
        if let i = self.index(of: key) { return i }
        if let i = index { return min(max(i, 0), cards.count - 1) }
        return 0
    }

    /// the top left: "1 of 5", or "Memory" on the memory card
    func title(_ index: Int) -> String {
        guard cards.indices.contains(index) else { return "Needs you" }
        if cards[index].kind == .memory { return "Memory" }
        let asks = cards.filter { $0.kind != .memory }
        let n = (asks.firstIndex { $0.key == cards[index].key } ?? 0) + 1
        return "\(n) of \(asks.count)"
    }
}

// MARK: sending, with Undo

/// One thing the watch asks of the PC. Answers, snoozes and dismissals wait out the Undo first; Bring back and Open on
/// iPhone go at once.
struct WatchSend: Codable, Equatable, Identifiable {
    enum What: String, Codable { case answer, snooze, dismiss, park, open, say }

    var id: String
    var what: What
    var key: String
    var option: Int?
    var text: String?
    var projectId: String?
    var parked: Bool?
    /// the card's source, for "Sent to Home server"
    var to: String
    /// what was picked, for the second line: "Add disk swap", his words
    var label: String
    /// when it was pressed (seconds, the watch's clock)
    var at: Double

    init(id: String = UUID().uuidString, what: What, key: String, option: Int? = nil, text: String? = nil,
         projectId: String? = nil, parked: Bool? = nil, to: String, label: String, at: Double) {
        self.id = id; self.what = what; self.key = key; self.option = option; self.text = text
        self.projectId = projectId; self.parked = parked; self.to = to; self.label = label; self.at = at
    }

    static func answer(_ a: WatchCard.Answer, on card: WatchCard, at: Double) -> WatchSend {
        WatchSend(what: .answer, key: card.key, option: a.option, to: card.source, label: a.label, at: at)
    }

    /// his own words (voice, Scribble or the keyboard), as he left them on the check screen
    static func words(_ text: String, on card: WatchCard, at: Double) -> WatchSend? {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return nil }
        return WatchSend(what: .answer, key: card.key, text: String(t.prefix(4000)), to: card.source, label: "“\(t)”",
                         at: at)
    }

    /// Words for a project's main chat (a235, the Running screen's mic), as he left them on the check screen. Only
    /// a project that has a main chat takes them; the iPhone finds that chat itself from `projectId`.
    static func say(_ text: String, to p: WatchProject, at: Double) -> WatchSend? {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, p.main else { return nil }
        return WatchSend(what: .say, key: "say:\(p.id)", text: String(t.prefix(4000)), projectId: p.id, to: p.name,
                         label: "\u{201C}\(t)\u{201D}", at: at)
    }

    /// waits out the Undo (everything that answers, speaks or takes a card off)
    var undoable: Bool { what == .answer || what == .snooze || what == .dismiss || what == .say }

    /// the banner's first line
    var headline: String {
        switch what {
        case .answer, .say: return "Sent to \(to)"
        case .snooze: return "Snoozed for an hour"
        case .dismiss: return "Dismissed"
        case .park: return "Brought back"
        case .open: return "On your iPhone"
        }
    }

    /// the banner's second line
    var detail: String {
        switch what {
        case .answer, .say: return label
        case .snooze, .dismiss, .park: return to
        case .open: return "Open GupWorks there to answer"
        }
    }
}

/// The watch's sends: the one whose Undo shows (5 s), those past it waiting for the iPhone, and those handed over a
/// moment ago (their cards stay off until the PC's list drops them, or come back when it still lists them after
/// `grace`: the answer didn't take).
struct WatchOutbox: Codable, Equatable {
    static let undoSeconds = 5.0
    static let grace = 120.0

    private(set) var holding: WatchSend?
    private(set) var ready: [WatchSend] = []
    private(set) var sent: [String: Double] = [:]

    init() {}

    /// A new send: undoable ones hold for 5 s (an earlier one still holding goes now); the rest are ready at once.
    mutating func add(_ s: WatchSend) {
        guard s.undoable else { ready.append(s); return }
        if let h = holding { ready.append(h) }
        holding = s
    }

    /// Undo: the held send is gone, nothing reached the iPhone.
    @discardableResult
    mutating func undo() -> WatchSend? {
        defer { holding = nil }
        return holding
    }

    /// Past its 5 s the held send is ready to go.
    mutating func tick(now: Double) {
        if let h = holding, now - h.at >= Self.undoSeconds {
            ready.append(h)
            holding = nil
        }
    }

    /// whole seconds of Undo left: 5, 4, … 1
    func left(now: Double) -> Int {
        guard let h = holding else { return 0 }
        return max(1, Int((Self.undoSeconds - (now - h.at)).rounded(.up)))
    }

    /// The iPhone has it (or the system queued it for the iPhone): out of the outbox.
    mutating func handed(_ id: String, now: Double) {
        guard let i = ready.firstIndex(where: { $0.id == id }) else { return }
        let s = ready.remove(at: i)
        // the memory warning stays while memory is full, whatever was pressed (as on the phone)
        if s.undoable, !s.key.hasPrefix("memory:") { sent[s.key] = now }
    }

    /// The iPhone said it didn't reach the PC: the card comes back.
    mutating func failed(_ key: String) {
        sent.removeValue(forKey: key)
    }

    /// The PC's list after a send: keys it no longer lists are done; keys it still lists `grace` after they went come
    /// back.
    mutating func listed(_ keys: Set<String>, now: Double) {
        sent = sent.filter { k, at in keys.contains(k) && now - at < Self.grace }
    }

    /// cards kept off the deck: Undo showing, waiting for the iPhone, sent a moment ago
    var off: Set<String> {
        var out = Set(sent.keys)
        for s in ready + (holding.map { [$0] } ?? []) where s.undoable && !(s.what == .answer && s.key.hasPrefix("memory:")) {
            out.insert(s.key)
        }
        return out
    }
}

// MARK: between the iPhone and the watch

/// What goes over WatchConnectivity. Every payload is one JSON value under one key, so both sides decode the same
/// Codable types (and the tests read them on Linux).
enum WatchRelay {
    /// the iPhone's list in updateApplicationContext: the latest one wins, also when the watch was away
    static let listKey = "list"
    /// a send from the watch, by sendMessage (reply: ok / error) or transferUserInfo (queued while out of reach)
    static let sendKey = "send"
    /// the watch asks for a fresh list (sendMessage; the reply is the list)
    static let refreshKey = "refresh"
    /// transferFile's metadata: which picture link the file is
    static let pictureKey = "picture"
    static let okKey = "ok"
    static let errorKey = "error"

    /// The PC's needs as the iPhone last saw them. `pcNow` is the PC's clock (ms) at `at` (the iPhone's, seconds
    /// since 1970), so the watch's wait times follow the PC's clock as the phone's do.
    struct List: Codable, Equatable {
        var needs: NeedsState
        var pcNow: Double
        var at: Double
        /// a235: each project's threads for the Running screen (nil from an iPhone that doesn't send them yet)
        var projects: [WatchProject]? = nil

        /// the PC's milliseconds at `now` (the watch's seconds since 1970)
        func pc(at now: Double) -> Double { pcNow + (now - at) * 1000 }

        /// after a silent push: the items answered or dismissed elsewhere leave (gone, or not live when it says)
        func without(gone: Set<String>, live: Set<String>?) -> List {
            var out = self
            out.needs.items.removeAll { item in gone.contains(item.key) || (live.map { !$0.contains(item.key) } ?? false) }
            return out
        }
    }

    static func encode<T: Encodable>(_ key: String, _ value: T) -> [String: Any] {
        guard let data = try? JSONEncoder().encode(value) else { return [:] }
        return [key: data]
    }

    static func decode<T: Decodable>(_ key: String, _ dict: [String: Any]) -> T? {
        guard let data = dict[key] as? Data else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    /// the reply to a send: ok, or why it didn't reach the PC
    static func reply(error: String?) -> [String: Any] {
        error.map { [okKey: false, errorKey: $0] } ?? [okKey: true]
    }

    static func error(in reply: [String: Any]) -> String? {
        if reply[okKey] as? Bool == true { return nil }
        return reply[errorKey] as? String ?? "The iPhone couldn't send it."
    }

    /// A picture's file name on the watch, the same for the same link (FNV-1a: stable across launches, unlike
    /// Swift's hashValue).
    static func pictureName(_ url: String) -> String {
        var h: UInt64 = 0xcbf2_9ce4_8422_2325
        for b in url.utf8 {
            h ^= UInt64(b)
            h = h &* 0x0000_0100_0000_01b3
        }
        return String(format: "%016llx.jpg", h)
    }

    /// The links the watch should have as files: every picture of every listed item.
    static func pictures(_ needs: NeedsState) -> [String] {
        var seen = Set<String>()
        return needs.items.flatMap { ($0.pictures ?? []).prefix(2).map(\.url) }.filter { seen.insert($0).inserted }
    }

    /// The size a picture is shrunk to before it goes to the watch: its longer side at most `max` pixels (a 46 mm
    /// screen is 416 x 496 px; 2x leaves room for the crown's zoom).
    static func fit(width: Double, height: Double, max: Double = 832) -> (width: Double, height: Double) {
        let longest = Swift.max(width, height)
        guard longest > max, longest > 0 else { return (width, height) }
        let k = max / longest
        return ((width * k).rounded(), (height * k).rounded())
    }
}

// MARK: what is running (a235, docs/watch-mockups/round1 shared-5-running-extra)

/// One project as the Running screen draws it: its threads working or being checked, and whether it has a main chat
/// to tell something (YouTube Studio has none). The iPhone fills it from the PC's project rows (WatchHome.swift).
struct WatchProject: Codable, Equatable, Hashable, Identifiable {
    var id: String
    var name: String
    var working: Int
    var checking: Int
    var main: Bool
}

enum WatchRunState: Equatable {
    case working, checking, idle
}

/// The Running screen's rows, in the Projects list's order as drawn (idle ones stay where they are), each with the
/// coloured dot and the words under its name: "2 working", "1 checking", "idle".
struct WatchGlance: Equatable {
    struct Row: Equatable, Identifiable {
        var project: WatchProject
        var state: WatchRunState
        var text: String
        var id: String { project.id }
    }

    private(set) var rows: [Row]

    init(_ projects: [WatchProject]?) {
        rows = (projects ?? []).map { p in
            Row(project: p, state: p.working > 0 ? .working : p.checking > 0 ? .checking : .idle,
                text: WatchGlance.words(working: p.working, checking: p.checking))
        }
    }

    /// "2 working", "1 checking", "2 working · 1 checking", "idle"
    static func words(working: Int, checking: Int) -> String {
        let parts = [working > 0 ? "\(working) working" : nil, checking > 0 ? "\(checking) checking" : nil]
        let text = parts.compactMap { $0 }.joined(separator: " \u{B7} ")
        return text.isEmpty ? "idle" : text
    }

    /// nothing listed yet (the iPhone hasn't sent projects)
    var isEmpty: Bool { rows.isEmpty }

    func project(_ id: String?) -> WatchProject? { rows.first { $0.project.id == id }?.project }
}

// MARK: the complication (a235, docs/watch-mockups/round1 shared-1-complication)

/// What the watch face shows: how many wait, the colour of the oldest, and the oldest one's project and question for
/// the families with room (rectangular). The count and order are the deck's, so the face and the app agree.
struct WatchComplication: Equatable {
    var count: Int
    var tone: NeedTone
    /// the oldest item's project (or chat), its question and when it started waiting (the PC's ms)
    var source: String?
    var title: String?
    var since: Double?
    /// the PC's milliseconds the entry was made for
    var pcNow: Double
    /// false until the iPhone has sent the watch a list: the face says to open GupWorks instead of "nothing"
    var known: Bool

    /// `now`: seconds since 1970 (the watch's clock); `off`: what the watch took off a moment ago (its outbox)
    init(_ list: WatchRelay.List?, now: Double, off: Set<String> = []) {
        pcNow = list?.pc(at: now) ?? now * 1000
        known = list != nil
        let cards = WatchDeck(list?.needs, now: pcNow, off: off).cards
        count = cards.count
        // the memory warning heads the deck; the face names the oldest question, and colours itself red while memory waits
        let oldest = cards.first { $0.kind != .memory } ?? cards.first
        source = oldest?.source
        title = oldest?.title
        since = oldest?.since
        tone = cards.contains { $0.kind == .memory } ? .red : oldest?.tone ?? .grey
    }

    var isEmpty: Bool { count == 0 }

    /// Whether the face would look the same (the wait aside, which the timeline keeps ticking itself): the watch app
    /// only asks WidgetKit for a reload when this is false.
    func looksLike(_ other: WatchComplication) -> Bool {
        count == other.count && tone == other.tone && source == other.source && title == other.title
            && known == other.known
    }

    /// "5 NEED YOU", "1 NEEDS YOU"; "Nothing needs you" (quiet, no capitals) with nothing waiting
    var headline: String {
        !known ? "Open GupWorks" : count == 0 ? "Nothing needs you" : count == 1 ? "1 NEEDS YOU" : "\(count) NEED YOU"
    }

    /// "12m", as the cards say it
    var wait: String? { since.map { WatchCard.wait(pcNow - $0) } }

    /// The circle's ring: 6% of it per item, so five is the 30% drawn in the mockup
    var ring: Double { min(Double(count) * 0.06, 1) }

    /// what a tap on the face opens: the app at its first card
    static let url = URL(string: "gupworksw://cards")!
}

/// What the watch app hands its complication (a WidgetKit extension: another process, so the two share an App Group's
/// defaults): the iPhone's last list and what the watch has taken off a moment ago. The extension builds its
/// timeline from this alone, with no WatchConnectivity of its own.
enum WatchFace {
    static let group = "group.app.gupworks3.phone"
    static let key = "face"

    struct Saved: Codable, Equatable {
        var list: WatchRelay.List?
        var off: [String]
    }

    static func load(_ defaults: UserDefaults?) -> Saved {
        guard let data = defaults?.data(forKey: key), let s = try? JSONDecoder().decode(Saved.self, from: data) else {
            return Saved(list: nil, off: [])
        }
        return s
    }

    /// Keeps the face's data (without the pictures' links and the projects it never draws) and says whether the face
    /// now looks different from what it showed before, i.e. whether WidgetKit should reload it.
    @discardableResult
    static func save(list: WatchRelay.List?, off: Set<String>, now: Double, _ defaults: UserDefaults?) -> Bool {
        var slim = list
        slim?.projects = nil
        let before = load(defaults)
        let new = Saved(list: slim, off: off.sorted())
        guard new != before, let data = try? JSONEncoder().encode(new) else { return false }
        defaults?.set(data, forKey: key)
        let a = WatchComplication(before.list, now: now, off: Set(before.off))
        let b = WatchComplication(slim, now: now, off: off)
        return !a.looksLike(b)
    }
}

// MARK: the wrist tap

/// One button of the watch's own notification view: the ask's real answers (WKUserNotificationHostingController's
/// notificationActions). Each opens the watch app, which shows Sent with its Undo before anything goes.
struct WatchButton: Equatable {
    var id: String
    var title: String
    var destructive = false
    var text = false
}

enum WatchNotice {
    /// "gw3.opt.<n>": answer option n (the iPhone understands it too, should the watch hand the tap over)
    static let optionPrefix = "gw3.opt."
    /// say something else: opens the card's voice check
    static let say = "gw3.say"
    static let dismiss = "gw3.dismiss"
    static let open = "gw3.open"

    /// The notification's buttons. The first is what a double tap presses on a notification (watchOS 10.1+): the
    /// recommended answer, or Deny on a command (a stray pinch never allows one).
    static func buttons(_ card: WatchCard) -> [WatchButton] {
        func opt(_ a: WatchCard.Answer, destructive: Bool = false) -> WatchButton {
            WatchButton(id: optionPrefix + String(a.option), title: a.label, destructive: destructive)
        }
        switch card.kind {
        case .ask:
            return card.answers.map { opt($0) }
                + (card.voice ? [WatchButton(id: say, title: "Say something else…")] : [])
                + [WatchButton(id: dismiss, title: "Dismiss", destructive: true)]
        case .permission:
            return [card.deny.map { opt($0, destructive: true) }, card.allow.map { opt($0) }].compactMap { $0 }
                + (card.voice ? [WatchButton(id: say, title: "Say what to do instead…")] : [])
        case .memory:
            return (card.sleep.map { [opt($0)] } ?? []) + [WatchButton(id: dismiss, title: "Dismiss", destructive: true)]
        case .phone:
            return [WatchButton(id: open, title: "Open on iPhone")]
        }
    }

    /// What a pressed notification button sends (nil: "say" and "open", which open a screen instead).
    static func send(_ action: String, card: WatchCard, at: Double) -> WatchSend? {
        if action == dismiss {
            return WatchSend(what: .dismiss, key: card.key, to: card.source, label: "Dismiss", at: at)
        }
        guard action.hasPrefix(optionPrefix), let n = Int(action.dropFirst(optionPrefix.count)) else { return nil }
        let pool = card.answers + [card.allow, card.deny, card.sleep].compactMap { $0 }
        guard let a = pool.first(where: { $0.option == n }) else { return nil }
        return .answer(a, on: card, at: at)
    }

    /// The needs-you item a push carries (gw3_push.alert_payload's `gw3.card`), so the notification shows the ask's
    /// real answers even before the iPhone has sent the watch its list.
    static func item(_ info: [AnyHashable: Any]) -> NeedItem? {
        guard let key = info["needs"] as? String, !key.isEmpty, let g = info["gw3"] as? [String: Any],
              let raw = g["card"], JSONSerialization.isValidJSONObject(raw),
              let data = try? JSONSerialization.data(withJSONObject: raw),
              let c = try? JSONDecoder().decode(PushCard.self, from: data) else { return nil }
        return c.item(key: key, kind: g["kind"] as? String ?? "ask", chat: g["chat"] as? String)
    }

    /// gw3.card, short keys to keep the push under Apple's 4 KB
    struct PushCard: Codable {
        var n: String?          // name
        var t: String?          // title
        var q: String?          // question
        var s: String?          // summary
        var w: String?          // work: the thread's id
        var wt: String?         // the thread's title
        var src: String?        // project | chat | memory
        var pid: String?        // projectId
        var since: Double?
        var o: [[String]]?      // options: [label, detail]
        var r: Int?             // recommended
        var x: Bool?            // other: words of his own
        var b: [String]?        // body: a permission's command and why
        var sig: String?

        func item(key: String, kind: String, chat: String?) -> NeedItem {
            NeedItem(key: key, kind: kind, source: src ?? (key.hasPrefix("chat:") ? "chat" : "project"), projectId: pid,
                     askId: nil, chatId: chat, name: n ?? "GupWorks", title: t ?? q ?? "Needs you", question: q,
                     summary: s, body: b,
                     options: (o ?? []).map { NeedItem.Option(label: $0.first ?? "", detail: $0.count > 1 ? $0[1] : nil, n: nil) },
                     recommended: r ?? -1, other: x ?? false, otherChoice: nil, since: since ?? 0, sig: sig, work: w,
                     workTitle: wt, pictures: nil)
        }
    }
}

// MARK: the demo

/// fixtures/watch/needs.json: the watch's demo (round 1 and 2's example content) for the simulator's screenshots.
/// `-memory` adds the memory warning.
struct WatchDemo: Codable {
    var list: WatchRelay.List
    var memory: NeedItem
    /// what the voice check shows as heard
    var words: String

    /// the list as if the iPhone had sent it just now (`now`: seconds since 1970), the warning with it or not
    func list(now: Double, memory withMemory: Bool) -> WatchRelay.List {
        var l = list
        l.at = now
        if withMemory { l.needs.items.append(memory) }
        return l
    }
}
