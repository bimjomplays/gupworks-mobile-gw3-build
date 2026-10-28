import Foundation

// a141: the project Overview, option 1 "Sections" (the overview-v2 mockups 1a to 1f): a page that
// slides in from the right over the main chat, with three tabs on a glass pill. The plain logic is here so it is
// tested on Linux; ProjectOverview.swift draws it.

/// The glass pill's tabs. Ideas live at the top of the Library tab.
enum OverviewTab: String, CaseIterable, Identifiable {
    case overview, library, scheduled

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: return "Overview"
        case .library: return "Library"
        case .scheduled: return "Scheduled"
        }
    }
}

/// The slide (1a): the Overview follows the finger in from the right edge; the chat moves a third of the width left
/// and dims under it. `progress` is how far in the Overview is: 0 closed, 1 open.
struct OverviewDrag {
    let width: Double

    static let flick = 500.0
    static let past = 0.35
    /// how dark the chat gets under the open Overview
    static let dim = 0.45

    /// how far in the Overview is while a swipe `dx` points along (right is positive) is under way
    func progress(open: Bool, dx: Double) -> Double {
        guard width > 0 else { return open ? 1 : 0 }
        return min(max((open ? 1 : 0) - dx / width, 0), 1)
    }

    /// whether the Overview is open once a swipe of `dx` lets go at `velocity` (points, right is positive)
    func endsOpen(open: Bool, dx: Double, velocity: Double) -> Bool {
        if abs(velocity) >= Self.flick { return velocity < 0 }
        let moved = open ? dx : -dx
        return moved > width * Self.past ? !open : open
    }

    /// the Overview's left edge
    func overviewX(_ progress: Double) -> Double { width * (1 - progress) }

    /// the chat's left edge: a third of the width to the left when open
    func chatX(_ progress: Double) -> Double { -width / 3 * progress }
}

/// The long-press menu of a thread, in the desktop's order (ProjectPanel::showThreadMenu).
enum ThreadMenu {
    static let order = ["open", "resume", "pause", "stop", "rename", "done", "archive", "unarchive", "delete"]

    static func actions(_ t: ThreadItem) -> [String] {
        let have = Set(t.moves + (t.chatId != nil ? ["open"] : []))
        return order.filter { have.contains($0) }
    }

    static func title(_ move: String) -> String {
        switch move {
        case "open": return "Open"
        case "resume": return "Resume"
        case "pause": return "Pause"
        case "stop": return "Stop…"
        case "rename": return "Rename…"
        case "done": return "Mark done"
        case "archive": return "Archive"
        case "unarchive": return "Unarchive"
        case "delete": return "Delete…"
        default: return move.capitalized
        }
    }

    static func symbol(_ move: String) -> String {
        switch move {
        case "open": return "arrow.up.right"
        case "resume": return "play"
        case "pause": return "pause"
        case "stop": return "stop.circle"
        case "rename": return "pencil"
        case "done": return "checkmark"
        case "archive": return "archivebox"
        case "unarchive": return "tray.and.arrow.up"
        case "delete": return "trash"
        default: return "circle"
        }
    }

    /// Stop and Delete ask first; Delete is drawn red
    static func asks(_ move: String) -> Bool { move == "stop" || move == "delete" }
    static func destructive(_ move: String) -> Bool { move == "delete" }

    /// The Delete confirmation, as the desktop's deleteThread says it.
    static func deleteText(_ t: ThreadItem) -> String {
        var text = "“\(t.title)” stops and leaves the project."
        if let b = t.facts?.branch, !b.isEmpty {
            text += " Its folder is deleted, and its branch \(b) too, unless it has commits the main branch doesn't."
        }
        return text + " Its Claude transcript is kept. This can't be undone."
    }
}

/// What the Overview tab draws, from the project view.
enum OverviewSections {
    /// The groups drawn as cards: every group but Done and Archived, which are rows that open their lists.
    static func open(_ v: ProjectView) -> [ThreadGroup] {
        v.groups.filter { $0.state != "done" && $0.state != "archived" }
    }

    /// Running subagents, then the done ones (folded under "N done subagents").
    static func split(_ subs: [Subagent]?) -> (running: [Subagent], done: [Subagent]) {
        let all = subs ?? []
        return (all.filter(\.running), all.filter { !$0.running })
    }

    static func doneLabel(_ n: Int) -> String { n == 1 ? "1 done subagent" : "\(n) done subagents" }

    /// "5-hour 18% · weekly 41%" ("ChatGPT weekly 3%" when the main chat runs on GPT), or nil before anything
    /// measured them
    static func planLine(_ plan: ProjectUsage.Plan?) -> String? {
        guard let plan else { return nil }
        let bits = [plan.fiveHour.map { "5-hour \(Int($0.rounded()))%" }, plan.week.map { "weekly \(Int($0.rounded()))%" }]
            .compactMap { $0 }
        if bits.isEmpty { return nil }
        return (plan.provider == "openai" ? "ChatGPT " : "") + bits.joined(separator: " · ")
    }

    /// The usage card's rows: main chat and all threads (by model), then the heavy threads in red.
    static func usage(_ v: ProjectView) -> (totals: [ProjectView.UsageRow], heavy: [ProjectView.UsageRow]) {
        (v.usage.filter { !$0.expensive }, v.usage.filter(\.expensive))
    }

    /// Whether the main chat's own question goes on top of Needs you.
    static func needsCount(_ v: ProjectView) -> Int {
        (v.groups.first { $0.state == "needs-you" }?.count ?? 0) + (v.mainNeeds == nil ? 0 : 1)
    }
}
