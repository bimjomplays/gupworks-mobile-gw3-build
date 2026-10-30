import SwiftUI

extension EnvironmentValues {
    /// Pushes a chat on the list's stack (a thread opened from a project's Overview or a thread card).
    @Entry var openChat: ((String) -> Void)? = nil
    /// a181: a chat with its route's extras (the Studio's Edit context chip)
    @Entry var openChatRoute: ((ChatRoute) -> Void)? = nil
    /// The project's threads, live from the PC, by id: the main chat's thread cards read their state here (05).
    @Entry var projectThreads: [String: ThreadItem] = [:]
}

// a141: the Overview's three tabs (OverviewLayer.swift draws the page and its glass top). Overview (1b, 1c) is the
// desktop's right bar group by group; Library (1d) has the Ideas note on top (1e, no tab of its own); Scheduled (1f).

// MARK: - Overview (1b, 1c)

struct OverviewTabView: View {
    let host: OverviewHost
    let store: ProjectStore
    @Environment(\.openChat) private var openChat
    @State private var asking: ThreadAsk?
    /// the threads (and "main") whose done subagents are unfolded
    @State private var unfolded: Set<String> = []

    var body: some View {
        List {
            if let v = store.view {
                content(v)
            } else if let e = store.error {
                OverviewNotice(icon: "exclamationmark.triangle", text: e.message)
            } else {
                ProgressView().frame(maxWidth: .infinity).padding(.vertical, 30).listRowBackground(Color.clear)
            }
        }
        .modifier(OverviewList())
        .refreshable { await store.refresh() }
        .modifier(ThreadDialogs(store: store, asking: $asking))
    }

    @ViewBuilder
    private func content(_ v: ProjectView) -> some View {
        Section { glance(v) }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 0, leading: 6, bottom: 0, trailing: 6))
        if v.paused {
            Section { pausedRow }
        }
        if let m = v.main {
            Section {
                mainRow(m)
            } header: { OverviewHeader(text: "Main chat") }
        }
        let needs = v.groups.first { $0.state == "needs-you" }?.threads ?? []
        if v.mainNeeds != nil || !needs.isEmpty {
            Section {
                if let m = v.mainNeeds { mainNeedsRow(m) }
                ForEach(needs) { t in threadRow(t) }
            } header: { OverviewHeader(text: "Needs you", count: OverviewSections.needsCount(v)) }
        }
        ForEach(OverviewSections.open(v).filter { $0.state != "needs-you" }) { g in
            Section {
                ForEach(g.threads) { t in threadRow(t) }
            } header: { OverviewHeader(text: g.label, count: g.count) }
        }
        Section { links(v) }
        usage(v)
    }

    /// "● 1 needs you  ◌ 3 working  ⊙ 1 being checked", the desktop's summary line
    private func glance(_ v: ProjectView) -> some View {
        HStack(spacing: 16) {
            ForEach(v.quiet, id: \.self) { q in
                HStack(spacing: 7) {
                    ThreadMark(glyph: q.glyph, size: 16)
                    Text(q.text).foregroundStyle(q.glyph == "needs" ? Theme.violetText : Color(hex: 0xC8C8CC))
                }
            }
            if v.quiet.isEmpty {
                Text(v.paused ? "Project paused" : "Nothing running")
            }
        }
        .font(.system(size: 16))
        .foregroundStyle(Color(hex: 0xC8C8CC))
        .lineLimit(1)
        .minimumScaleFactor(0.75)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("overviewGlance")
    }

    private var pausedRow: some View {
        HStack(spacing: 12) {
            LucideIcon(name: "circle-pause", size: 21).foregroundStyle(Theme.amber)
            VStack(alignment: .leading, spacing: 2) {
                Text("Project paused").font(.system(size: 17)).foregroundStyle(Theme.rowTitle)
                Text("No thread starts or wakes until you resume it.")
                    .font(.system(size: 14)).foregroundStyle(OverviewStyle.grey)
            }
            Spacer(minLength: 8)
            Button("Resume") { Task { await store.setPaused(false) } }
                .buttonStyle(.borderless)
                .font(.system(size: 16, weight: .semibold))
                .tint(Theme.blue)
                .accessibilityIdentifier("projectResume")
        }
        .padding(.vertical, 6)
        .listRowBackground(OverviewStyle.card)
        .accessibilityIdentifier("pausedBanner")
    }

    /// the main chat: model, effort, usage, what it's doing; its subagents under it. A tap goes back to it.
    private func mainRow(_ m: ProjectView.MainRow) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Button { host.close() } label: {
                HStack(alignment: .firstTextBaseline, spacing: 14) {
                    LucideIcon(name: "message-square", size: 21)
                        .foregroundStyle(ProjectLook.plainIcon)
                        .frame(width: 24)
                        .alignmentGuide(.firstTextBaseline) { d in d[VerticalAlignment.center] + 6 }
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(m.title).font(.system(size: 17)).foregroundStyle(Theme.rowTitle).lineLimit(1)
                                .layoutPriority(1)
                            Spacer(minLength: 4)
                            Text([m.modelLabel, m.usage].filter { !$0.isEmpty }.joined(separator: " \u{00B7} "))
                                .font(.system(size: 14)).foregroundStyle(OverviewStyle.grey).lineLimit(1)
                        }
                        if !m.line.isEmpty {
                            Text(m.line)
                                .font(.system(size: 15))
                                .foregroundStyle(m.state == "needs" ? Theme.violetText : OverviewStyle.grey)
                                .lineLimit(2)
                        }
                    }
                }
                .padding(.vertical, 6)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityHint("Back to the main chat")
            .accessibilityIdentifier("mainChat")
            SubagentTree(owner: "main", subagents: m.subagents, unfolded: $unfolded)
        }
        .listRowBackground(OverviewStyle.card)
    }

    /// The main chat's own question: a tap goes back to it.
    private func mainNeedsRow(_ m: ProjectView.MainNeeds) -> some View {
        Button { host.close() } label: {
            HStack(alignment: .firstTextBaseline, spacing: 14) {
                ThreadMark(glyph: "needs", size: 22).frame(width: 24)
                    .alignmentGuide(.firstTextBaseline) { d in d[VerticalAlignment.center] + 6 }
                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Main chat").font(.system(size: 17)).foregroundStyle(Theme.rowTitle)
                        Spacer(minLength: 6)
                        Text(m.ago.map { $0.isEmpty || $0 == "0m" ? "now" : $0 } ?? "now")
                            .font(.system(size: 14)).foregroundStyle(OverviewStyle.grey)
                    }
                    Text(m.text).font(.system(size: 15)).foregroundStyle(Theme.violetText).lineLimit(2)
                }
            }
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(OverviewStyle.card)
        .accessibilityIdentifier("needsMain")
    }

    private func threadRow(_ t: ThreadItem) -> some View {
        ThreadCell(thread: t, store: store, unfolded: $unfolded, ask: { asking = $0 })
    }

    /// Done and Archived folded like the desktop (a tap lists them), and the next scheduled run
    @ViewBuilder
    private func links(_ v: ProjectView) -> some View {
        let done = v.counts.done ?? (v.groups.first { $0.state == "done" }?.count ?? 0)
        let archived = v.counts.archived ?? (v.groups.first { $0.state == "archived" }?.count ?? 0)
        linkRow("doneThreads", "circle-check", "Done", "\(done)") { host.path.append(OverviewPage.threads("done")) }
        if archived > 0 {
            linkRow("archivedThreads", "archive", "Archived", "\(archived)") {
                host.path.append(OverviewPage.threads("archived"))
            }
        }
        if let n = v.nextSchedule {
            linkRow("nextScheduled", "calendar-clock", "Next scheduled", n.when) {
                withAnimation(.snappy(duration: 0.25)) { host.tab = .scheduled }
            }
        }
    }

    private func linkRow(_ id: String, _ icon: String, _ title: String, _ value: String,
                         _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                LucideIcon(name: icon, size: 21).foregroundStyle(ProjectLook.plainIcon).frame(width: 24)
                Text(title).font(.system(size: 17)).foregroundStyle(Theme.rowTitle)
                Spacer(minLength: 6)
                Text(value).font(.system(size: 16)).foregroundStyle(OverviewStyle.grey)
                RowChevron()
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(OverviewStyle.card)
        .accessibilityIdentifier(id)
    }

    /// main chat and threads by model, the heavy threads in red (a tap opens one), the plan's limits
    @ViewBuilder
    private func usage(_ v: ProjectView) -> some View {
        let u = OverviewSections.usage(v)
        let plan = OverviewSections.planLine(v.plan)
        if !v.usage.isEmpty || plan != nil {
            Section {
                ForEach(u.totals, id: \.self) { r in usageRow(r, red: false) }
                ForEach(u.heavy, id: \.self) { r in
                    Button { if let c = r.chatId { openChat?(c) } } label: { usageRow(r, red: true) }
                        .buttonStyle(.plain)
                        .disabled(r.chatId == nil)
                }
                if let plan {
                    HStack {
                        Text("Plan").font(.system(size: 17)).foregroundStyle(Theme.rowTitle)
                        Spacer(minLength: 8)
                        Text(plan).font(.system(size: 16)).foregroundStyle(Color(hex: 0xC8C8CC))
                    }
                    .padding(.vertical, 4)
                    .listRowBackground(OverviewStyle.card)
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("usagePlan")
                }
            } header: { OverviewHeader(text: "Usage") }
        }
    }

    private func usageRow(_ r: ProjectView.UsageRow, red: Bool) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline) {
                Text(r.title).font(.system(size: 17)).foregroundStyle(red ? ChatStyle.failed : Theme.rowTitle).lineLimit(1)
                Spacer(minLength: 8)
                Text(r.value).font(.system(size: 16)).foregroundStyle(red ? ChatStyle.failed : Color(hex: 0xC8C8CC))
            }
            if !r.detail.isEmpty {
                Text(r.detail).font(.system(size: 15)).foregroundStyle(OverviewStyle.grey).lineLimit(2)
            }
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .listRowBackground(OverviewStyle.card)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("usage-\(r.title)")
    }
}

/// The Overview's lists: insetGrouped cards on the near-black page, under the glass top.
struct OverviewList: ViewModifier {
    func body(content: Content) -> some View {
        content
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(OverviewStyle.background)
            .environment(\.defaultMinListRowHeight, 50)
            .listSectionSpacing(14)
            .contentMargins(.top, 4, for: .scrollContent)
    }
}

/// "Working  3": grey over a card, the count on the right
struct OverviewHeader: View {
    let text: String
    var count: Int?

    var body: some View {
        HStack {
            Text(text)
            Spacer(minLength: 8)
            if let count { Text("\(count)") }
        }
        .font(.system(size: 15))
        .foregroundStyle(Color(hex: 0x98989F))
        .textCase(nil)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - A thread

/// What a thread's long-press asks about first.
enum ThreadAsk: Identifiable {
    case stop(ThreadItem), rename(ThreadItem), delete(ThreadItem)

    var thread: ThreadItem {
        switch self {
        case .stop(let t), .rename(let t), .delete(let t): return t
        }
    }

    var id: String {
        switch self {
        case .stop(let t): return "stop-\(t.id)"
        case .rename(let t): return "rename-\(t.id)"
        case .delete(let t): return "delete-\(t.id)"
        }
    }
}

/// One thread: its row with its subagents under it; a tap opens its chat inside the Overview, a swipe pauses,
/// marks done or archives, a long press shows its task and every move (Open, Pause, Stop, Rename, Mark done,
/// Archive, Delete).
struct ThreadCell: View {
    let thread: ThreadItem
    let store: ProjectStore
    @Binding var unfolded: Set<String>
    let ask: (ThreadAsk) -> Void
    @Environment(\.openChat) private var openChat

    var body: some View {
        let t = thread
        VStack(alignment: .leading, spacing: 0) {
            OverviewThreadRow(thread: t, busy: store.busy.contains(t.id))
                .contentShape(Rectangle())
                .onTapGesture { if let c = t.chatId { openChat?(c) } }
                .accessibilityAddTraits(t.chatId == nil ? [] : .isButton)
                .accessibilityIdentifier("thread-\(t.id)")
            SubagentTree(owner: t.id, subagents: t.subagents ?? [], unfolded: $unfolded)
        }
        .listRowBackground(OverviewStyle.card)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if t.moves.contains("archive") {
                Button { act("archive") } label: { Label("Archive", systemImage: "archivebox") }
                    .tint(ChatActions.archiveTint)
            } else if t.moves.contains("unarchive") {
                Button { act("unarchive") } label: { Label("Unarchive", systemImage: "tray.and.arrow.up") }
                    .tint(ChatActions.archiveTint)
            }
            if t.moves.contains("done") {
                Button { act("done") } label: { Label("Mark done", systemImage: "checkmark") }
                    .tint(Color(hex: 0x3D6A45))
            }
            if t.moves.contains("pause") {
                Button { act("pause") } label: { Label("Pause", systemImage: "pause") }
                    .tint(Color(hex: 0x4A4A4E))
            } else if t.moves.contains("resume") {
                Button { act("resume") } label: { Label("Resume", systemImage: "play") }
                    .tint(Color(hex: 0x2F5FB3))
            }
        }
        .contextMenu {
            ForEach(ThreadMenu.actions(t), id: \.self) { m in
                Button(ThreadMenu.title(m), systemImage: ThreadMenu.symbol(m),
                       role: ThreadMenu.destructive(m) ? .destructive : nil) { pick(m) }
            }
        } preview: {
            ThreadPreview(thread: t)
        }
    }

    private func pick(_ m: String) {
        switch m {
        case "open": if let c = thread.chatId { openChat?(c) }
        case "stop": ask(.stop(thread))
        case "rename": ask(.rename(thread))
        case "delete": ask(.delete(thread))
        default: act(m)
        }
    }

    private func act(_ move: String) {
        let s = store, id = thread.id
        Task { await s.move(move, thread: id) }
    }
}

/// Stop and Delete ask first; Rename asks for the name.
struct ThreadDialogs: ViewModifier {
    let store: ProjectStore
    @Binding var asking: ThreadAsk?
    @State private var name = ""

    private func shown(_ kind: String) -> Binding<Bool> {
        Binding(get: { asking?.id.hasPrefix(kind + "-") ?? false }, set: { if !$0 { asking = nil } })
    }

    func body(content: Content) -> some View {
        let t = asking?.thread
        content
            .confirmationDialog("Stop \u{201C}\(t?.title ?? "this thread")\u{201D}?", isPresented: shown("stop"),
                                titleVisibility: .visible, presenting: t) { t in
                Button("Stop", role: .destructive) { Task { await store.move("stop", thread: t.id) } }
                Button("Cancel", role: .cancel) {}
            } message: { _ in
                Text("Its Claude stops working on it. The thread stays in the project, so it can be picked up again.")
            }
            .confirmationDialog("Delete \u{201C}\(t?.title ?? "this thread")\u{201D}?", isPresented: shown("delete"),
                                titleVisibility: .visible, presenting: t) { t in
                Button("Delete", role: .destructive) { Task { await store.move("delete", thread: t.id) } }
                Button("Cancel", role: .cancel) {}
            } message: { t in
                Text(ThreadMenu.deleteText(t))
            }
            .alert("Rename thread", isPresented: shown("rename"), presenting: t) { t in
                TextField("Name", text: $name)
                    .accessibilityIdentifier("renameText")
                Button("Rename") {
                    let title = name.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !title.isEmpty, title != t.title else { return }
                    Task { await store.move("rename", thread: t.id, title: title) }
                }
                Button("Cancel", role: .cancel) {}
            }
            .onChange(of: asking?.id) { _, _ in
                if case .rename(let t) = asking { name = t.title }
            }
    }
}

/// One thread's line: its mark, title, id and usage (red when heavy); its model and what it's doing under it, the
/// app it holds on the right.
struct OverviewThreadRow: View {
    let thread: ThreadItem
    var busy = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            Group {
                if busy { ProgressView().controlSize(.small) } else { ThreadMark(glyph: thread.glyph, size: 22) }
            }
            .frame(width: 24)
            .alignmentGuide(.firstTextBaseline) { d in d[VerticalAlignment.center] + 6 }
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    HStack(alignment: .firstTextBaseline, spacing: 7) {
                        Text(thread.title)
                            .font(.system(size: 17))
                            .foregroundStyle(thread.muted ? ChatStyle.dim : Theme.rowTitle)
                            .lineLimit(1)
                        Text(thread.id).font(.system(size: 14)).foregroundStyle(Color(hex: 0x7C7C80))
                    }
                    .layoutPriority(1)
                    Spacer(minLength: 4)
                    if !thread.usage.isEmpty {
                        Text(thread.usage)
                            .font(.system(size: 14))
                            .foregroundStyle(thread.expensive ? ChatStyle.failed : OverviewStyle.grey)
                            .accessibilityLabel(thread.expensive ? "\(thread.usage), heavy" : thread.usage)
                    }
                }
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    second
                        .font(.system(size: 15))
                        .lineLimit(1)
                    if !thread.holds.isEmpty {
                        Spacer(minLength: 4)
                        HStack(spacing: 4) {
                            Image(systemName: "lock").font(.system(size: 12, weight: .medium))
                            Text(thread.holds.joined(separator: ", "))
                        }
                        .font(.system(size: 15))
                        .foregroundStyle(Color(hex: 0xC8C8CC))
                        .fixedSize()
                        .accessibilityLabel("Holds \(thread.holds.joined(separator: ", "))")
                    }
                }
            }
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }

    /// "Sonnet high · writing script.js 2m ago"; a question in violet
    private var second: Text {
        let model = thread.modelLabel ?? ""
        let doing = thread.detail.isEmpty ? (thread.line ?? "") : thread.detail
        let tone = thread.glyph == "needs" ? Theme.violetText : OverviewStyle.grey
        if model.isEmpty { return Text(doing).foregroundStyle(tone) }
        if doing.isEmpty { return Text(model).foregroundStyle(OverviewStyle.grey) }
        return Text("\(Text(model + " \u{00B7} ").foregroundStyle(OverviewStyle.grey))\(Text(doing).foregroundStyle(tone))")
    }
}

/// A chat's subagents under its row: the running ones, then "N done subagents" that unfolds the rest.
struct SubagentTree: View {
    let owner: String
    let subagents: [Subagent]
    @Binding var unfolded: Set<String>

    var body: some View {
        let s = OverviewSections.split(subagents)
        let open = unfolded.contains(owner)
        if !subagents.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(s.running) { a in SubagentRow(subagent: a) }
                if !s.done.isEmpty {
                    Button {
                        withAnimation(.snappy(duration: 0.25)) {
                            if open { unfolded.remove(owner) } else { unfolded.insert(owner) }
                        }
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: open ? "chevron.down" : "chevron.right")
                                .font(.system(size: 13, weight: .semibold))
                                .frame(width: 18)
                            Text(OverviewSections.doneLabel(s.done.count)).font(.system(size: 15))
                            Spacer(minLength: 0)
                        }
                        .foregroundStyle(OverviewStyle.grey)
                        .frame(minHeight: 34)
                        .contentShape(Rectangle())
                        .modifier(TreeLine())
                    }
                    .buttonStyle(.borderless)
                    .accessibilityIdentifier("doneSubagents-\(owner)")
                    if open { ForEach(s.done) { a in SubagentRow(subagent: a) } }
                }
            }
            .padding(.bottom, 4)
        }
    }
}

/// a subagent: its job, model and tokens
struct SubagentRow: View {
    let subagent: Subagent

    var body: some View {
        HStack(spacing: 10) {
            LucideIcon(name: "bot", size: 17)
                .foregroundStyle(subagent.running ? Theme.blue : OverviewStyle.faint)
                .frame(width: 18)
            Text(subagent.title)
                .font(.system(size: 15.5))
                .foregroundStyle(subagent.running ? Theme.rowTitle : Color(hex: 0xA8A8AD))
                .lineLimit(1)
            Spacer(minLength: 6)
            Text(subagent.right).font(.system(size: 14)).foregroundStyle(OverviewStyle.grey).lineLimit(1).fixedSize()
        }
        .frame(minHeight: 34)
        .modifier(TreeLine())
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("subagent-\(subagent.id)")
    }
}

/// the elbow from the chat's mark down to a subagent (1b)
private struct TreeLine: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.leading, 38)
            .overlay(alignment: .topLeading) {
                Path { p in
                    p.move(to: CGPoint(x: 12, y: 0))
                    p.addLine(to: CGPoint(x: 12, y: 13))
                    p.addQuadCurve(to: CGPoint(x: 20, y: 17), control: CGPoint(x: 12, y: 17))
                    p.addLine(to: CGPoint(x: 30, y: 17))
                }
                .stroke(OverviewStyle.line, lineWidth: 1.2)
                .frame(width: 32, height: 34)
            }
    }
}

/// A long press's card: the thread's task, what done means, where it is.
private struct ThreadPreview: View {
    let thread: ThreadItem

    var body: some View {
        let f = thread.facts
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                ThreadMark(glyph: thread.glyph, size: 18)
                Text(thread.title).font(.system(size: 18, weight: .semibold)).foregroundStyle(Theme.title)
                Text(thread.id).font(.system(size: 14)).foregroundStyle(OverviewStyle.grey)
            }
            let model = [f?.model ?? "", f?.effort ?? ""].filter { !$0.isEmpty }.joined(separator: " ")
            line([thread.word ?? thread.status, model.isEmpty ? (thread.modelLabel ?? "") : model, thread.usage]
                .filter { !$0.isEmpty }.joined(separator: " \u{00B7} "))
            if let f {
                if !f.outcome.isEmpty { block("Outcome", f.outcome) }
                if !f.criteria.isEmpty {
                    block("Done when", f.criteria.map { "\u{2022} " + $0 }.joined(separator: "\n"))
                }
                if !f.checkpoint.isEmpty { block("Checkpoint", f.checkpoint) }
                if !f.nextAction.isEmpty { block("Next", f.nextAction) }
                if !f.waitsFor.isEmpty { block("Waits for", f.waitsFor.joined(separator: ", ")) }
                if !f.issue.isEmpty { block("Issue", f.issue, red: true) }
                let where_ = [f.branch, f.commit.isEmpty ? "" : String(f.commit.prefix(7)),
                              f.reworks > 0 ? (f.reworks == 1 ? "1 rework" : "\(f.reworks) reworks") : ""]
                    .filter { !$0.isEmpty }
                if !where_.isEmpty { block("Branch", where_.joined(separator: " \u{00B7} ")) }
                if !f.evidence.isEmpty {
                    block("Evidence", f.evidence.prefix(4).map { e in
                        "\u{2022} " + [e.kind, e.summary].filter { !$0.isEmpty }.joined(separator: ": ")
                    }.joined(separator: "\n"))
                }
            } else if !thread.detail.isEmpty {
                line(thread.detail)
            }
        }
        .padding(18)
        .frame(width: 340, alignment: .leading)
        .background(OverviewStyle.card)
    }

    private func line(_ s: String) -> some View {
        Text(s).font(.system(size: 15)).foregroundStyle(OverviewStyle.grey).lineLimit(2)
    }

    private func block(_ label: String, _ text: String, red: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(.system(size: 13, weight: .semibold)).foregroundStyle(OverviewStyle.grey)
            Text(text).font(.system(size: 15)).foregroundStyle(red ? ChatStyle.failed : Theme.rowTitle).lineLimit(6)
        }
    }
}

struct OverviewNotice: View {
    let icon: String
    let text: String

    var body: some View {
        Label(text, systemImage: icon)
            .font(.subheadline)
            .foregroundStyle(ChatStyle.dim)
            .padding(.vertical, 20)
            .listRowBackground(Color.clear)
    }
}

/// Every Done or every Archived thread, pushed from the Overview's rows.
struct ThreadListPage: View {
    let store: ProjectStore
    let state: String
    @State private var asking: ThreadAsk?
    @State private var unfolded: Set<String> = []

    private var group: ThreadGroup? { store.view?.groups.first { $0.state == state } }

    var body: some View {
        List {
            if let g = group, !g.threads.isEmpty {
                Section {
                    ForEach(g.threads) { t in
                        ThreadCell(thread: t, store: store, unfolded: $unfolded, ask: { asking = $0 })
                    }
                } header: { OverviewHeader(text: g.label, count: g.count) }
            } else {
                OverviewNotice(icon: "tray", text: state == "done" ? "Nothing done yet." : "Nothing archived.")
            }
        }
        .modifier(OverviewList())
        .navigationTitle(state == "done" ? "Done" : "Archived")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await store.refresh() }
        .modifier(ThreadDialogs(store: store, asking: $asking))
    }
}

// MARK: - New thread

/// The Overview's +: your own thread in the project, started with this message (the desktop's + New thread).
struct NewThreadView: View {
    let store: ProjectStore
    let done: () -> Void
    @State private var text = ""
    @State private var starting = false
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("A thread of your own in \(store.view?.name ?? "the project"). Your first message is its task; "
                 + "the main chat sees it.")
                .font(.system(size: 15))
                .foregroundStyle(SheetStyle.label)
            TextEditor(text: $text)
                .font(.system(size: 17))
                .scrollContentBackground(.hidden)
                .padding(10)
                .frame(minHeight: 160)
                .background(OverviewStyle.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(alignment: .topLeading) {
                    if text.isEmpty {
                        Text("What should it do?")
                            .font(.system(size: 17))
                            .foregroundStyle(SheetStyle.optional)
                            .padding(.horizontal, 15)
                            .padding(.vertical, 18)
                            .allowsHitTesting(false)
                    }
                }
                .focused($focused)
                .accessibilityIdentifier("newThreadText")
            Spacer()
        }
        .padding(16)
        .background(OverviewStyle.background)
        .navigationTitle("New thread")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                SheetDoneButton(on: !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !starting,
                                busy: starting, id: "startThread", label: "Start") {
                    starting = true
                    Task {
                        if await store.newThread(text) { done() }
                        starting = false
                    }
                }
            }
        }
        .onAppear { focused = true }
    }
}

// MARK: - Library (1d, ideas from 1e on top)

/// The Library tab: the project's Ideas first (add one, see them by section, start, move, edit or delete one),
/// then its notes and what its threads made. The glass + copies photos or files into the notes folder.
struct LibraryTab: View {
    let host: OverviewHost
    let store: ProjectStore
    /// photos or files are being copied to the PC
    let adding: Bool
    @State private var query = ""
    @State private var searching = false
    @State private var kind = "all"
    /// both the ideas and the Library are in: until then a spinner, so the ideas don't arrive above rows already
    /// shown (the list would keep its place on those and open scrolled past the ideas)
    @State private var ready: Bool

    init(host: OverviewHost, store: ProjectStore, adding: Bool) {
        self.host = host
        self.store = store
        self.adding = adding
        _ready = State(initialValue: store.ideas != nil && store.library != nil)
    }

    private static let kinds = [("all", "All"), ("notes", "Notes"), ("images", "Images"), ("files", "Files")]

    var body: some View {
        List {
            if ready { content } else {
                ProgressView().frame(maxWidth: .infinity).padding(.vertical, 30).listRowBackground(Color.clear)
            }
        }
        .modifier(OverviewList())
        .scrollDismissesKeyboard(.interactively)
        .refreshable {
            await store.loadIdeas()
            await store.loadLibrary()
        }
        .task {
            await store.loadIdeas()
            await store.loadLibrary()
            ready = true
        }
    }

    @ViewBuilder private var content: some View {
        IdeasSections(host: host, store: store)
        Section {
            VStack(spacing: 12) {
                HStack(spacing: 8) {
                    ForEach(Self.kinds, id: \.0) { k in chip(k.0, k.1) }
                    Spacer(minLength: 0)
                    Button {
                        withAnimation(.snappy(duration: 0.2)) {
                            searching.toggle()
                            if !searching { query = "" }
                        }
                    } label: {
                        Image(systemName: searching ? "xmark" : "magnifyingglass")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(Color(hex: 0xC8C8CC))
                            .frame(width: 38, height: 38)
                            .background(OverviewStyle.card, in: Circle())
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel(searching ? "Close search" : "Search the Library")
                    .accessibilityIdentifier("librarySearchButton")
                }
                if searching {
                    SheetSearchField(text: $query, prompt: "Search notes and files\u{2026}")
                        .accessibilityIdentifier("librarySearch")
                }
            }
        }
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 0, trailing: 0))
        if adding {
            Section {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Copying to the PC\u{2026}").foregroundStyle(SheetStyle.label)
                }
            }
            .listRowBackground(OverviewStyle.card)
        }
        if let lib = store.library {
            let groups = filtered(lib.groups)
            LibraryCards(groups: groups, store: store, path: Binding(get: { host.path }, set: { host.path = $0 }))
            if groups.isEmpty {
                OverviewNotice(icon: "magnifyingglass",
                               text: lib.groups.allSatisfy { $0.items.isEmpty } ? "No notes yet." : "Nothing matches.")
            }
        } else {
            ProgressView().frame(maxWidth: .infinity).padding(.vertical, 30).listRowBackground(Color.clear)
        }
    }

    private func chip(_ id: String, _ title: String) -> some View {
        let on = kind == id
        return Button { kind = id } label: {
            Text(title)
                .font(.system(size: 16))
                .foregroundStyle(on ? Color.black : Color(hex: 0xC8C8CC))
                .padding(.horizontal, 16)
                .frame(height: 38)
                .background(on ? Color(hex: 0xECECEC) : OverviewStyle.card, in: Capsule())
        }
        .buttonStyle(.borderless)
        .accessibilityAddTraits(on ? .isSelected : [])
        .accessibilityIdentifier("libraryKind-\(id)")
    }

    /// the kind and the search; the pinned Ideas row goes (its ideas are on top)
    private func filtered(_ groups: [LibraryGroup]) -> [LibraryGroup] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        return groups.compactMap { g in
            var g = g
            g.items = g.items.filter { r in
                if LibraryCards.isIdeas(r) { return false }
                let kindOK: Bool
                switch kind {
                case "notes": kindOK = r.kind == "note" || r.kind == "folder"
                case "images": kindOK = r.kind == "image"
                case "files": kindOK = r.kind != "note" && r.kind != "folder" && r.kind != "image"
                default: kindOK = true
                }
                return kindOK && (q.isEmpty || r.title.lowercased().contains(q) || r.sub.lowercased().contains(q))
            }
            return g.items.isEmpty ? nil : g
        }
    }
}

/// The Ideas note at the top of the Library: an add field, then its sections (three ideas each until unfolded).
/// Tap an idea to edit it in place; swipe or long-press to start it (the main chat plans a thread), move or delete it.
private struct IdeasSections: View {
    let host: OverviewHost
    let store: ProjectStore
    @State private var newIdea = ""
    @State private var editing: IdeaRef?
    @State private var draft = ""
    @State private var adding = false
    @State private var unfolded: Set<String> = []
    @FocusState private var focus: Field?

    private static let shown = 3

    enum Field: Hashable { case add, edit }

    struct IdeaRef: Hashable {
        let section: String
        let raw: String
    }

    var body: some View {
        Section {
            addRow
        } header: {
            HStack {
                Text("Ideas")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Theme.title)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("ideasTitle")
                if let n = store.ideas?.count, n > 0 {
                    Text("\(n)").font(.system(size: 16)).foregroundStyle(OverviewStyle.grey)
                }
                Spacer(minLength: 8)
                Menu {
                    Button("Open as note", systemImage: "doc.text") { openAsNote() }
                    Button("Refresh", systemImage: "arrow.clockwise") { Task { await store.loadIdeas() } }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Color(hex: 0xC8C8CC))
                        .frame(width: 36, height: 30)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Ideas note")
                .accessibilityIdentifier("ideasMore")
            }
            .textCase(nil)
        }
        if let l = store.ideas {
            ForEach(l.sections.filter { !$0.items.isEmpty }) { s in
                Section {
                    let open = unfolded.contains(s.name) || s.items.count <= Self.shown + 1
                    ForEach(open ? s.items : Array(s.items.prefix(Self.shown)), id: \.raw) { item in
                        idea(item, in: s, all: l.sections)
                    }
                    if !open {
                        Button {
                            withAnimation(.snappy(duration: 0.25)) { _ = unfolded.insert(s.name) }
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "chevron.down").font(.system(size: 13, weight: .semibold))
                                Text("\(s.items.count - Self.shown) more").font(.system(size: 16))
                            }
                            .foregroundStyle(OverviewStyle.grey)
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(OverviewStyle.card)
                        .accessibilityIdentifier("ideasMore-\(s.name)")
                    }
                } header: { OverviewHeader(text: s.name, count: s.items.count) }
            }
        } else {
            ProgressView().frame(maxWidth: .infinity).padding(.vertical, 10).listRowBackground(Color.clear)
        }
    }

    private var addRow: some View {
        HStack(spacing: 12) {
            LucideIcon(name: "lightbulb", size: 21).foregroundStyle(OverviewStyle.grey)
            TextField("Add an idea\u{2026}", text: $newIdea, axis: .vertical)
                .lineLimit(1...4)
                .font(.system(size: 17))
                .foregroundStyle(Theme.rowTitle)
                .focused($focus, equals: .add)
                .submitLabel(.done)
                .accessibilityIdentifier("ideaText")
            Button(action: add) {
                Group {
                    if adding { ProgressView().tint(.white) } else { Image(systemName: "arrow.up") }
                }
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(canAdd ? Color.black : OverviewStyle.grey)
                .frame(width: 36, height: 36)
                .background(canAdd ? Color(hex: 0xECECEC) : Color(hex: 0x3A3A3C), in: Circle())
            }
            .buttonStyle(.borderless)
            .disabled(!canAdd)
            .accessibilityLabel("Add idea")
            .accessibilityIdentifier("ideaAdd")
        }
        .padding(.vertical, 2)
        .listRowBackground(OverviewStyle.card)
        .onChange(of: focus) { old, new in
            if old == .edit && new != .edit { saveEdit() }
        }
    }

    @ViewBuilder
    private func idea(_ item: IdeaItem, in s: IdeasSection, all: [IdeasSection]) -> some View {
        let ref = IdeaRef(section: s.name, raw: item.raw)
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            if item.ai {
                Text("AI")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.violetText)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Theme.violet.opacity(0.22), in: RoundedRectangle(cornerRadius: 6))
            }
            if editing == ref {
                TextField("Idea", text: $draft, axis: .vertical)
                    .font(.system(size: 17))
                    .foregroundStyle(Theme.rowTitle)
                    .focused($focus, equals: .edit)
                    .submitLabel(.done)
                    .onSubmit { focus = nil }
                    .accessibilityIdentifier("ideaEditor")
            } else {
                ideaText(item)
                    .font(.system(size: 17))
                    .lineSpacing(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture { startEdit(ref, item) }
                    .accessibilityIdentifier("idea-\(item.text)")
            }
        }
        .padding(.vertical, 6)
        .listRowBackground(OverviewStyle.card)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                change(IdeaChange(op: "delete", section: s.name, old: item.raw))
            } label: { Label("Delete", systemImage: "trash") }
            Button { start(item) } label: { Label("Start it", systemImage: "play") }.tint(Color(hex: 0x2F5FB3))
        }
        .contextMenu {
            Button("Start it", systemImage: "play") { start(item) }
            Menu("Move to", systemImage: "arrow.right") {
                ForEach(all.filter { $0.name != s.name }) { to in
                    Button(to.name) { change(IdeaChange(op: "move", section: s.name, old: item.raw, to: to.name)) }
                }
            }
            Button("Edit", systemImage: "pencil") { startEdit(ref, item) }
            Button("Delete", systemImage: "trash", role: .destructive) {
                change(IdeaChange(op: "delete", section: s.name, old: item.raw))
            }
        }
    }

    /// the idea, its date in grey after it
    private func ideaText(_ item: IdeaItem) -> Text {
        let date = item.date.map { " " + $0 } ?? ""
        return Text("\(Text(item.text).foregroundStyle(Theme.rowTitle))\(Text(date).font(.system(size: 14)).foregroundStyle(OverviewStyle.faint))")
    }

    private var canAdd: Bool { !newIdea.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !adding }

    private func add() {
        let text = newIdea
        adding = true
        Task {
            if await store.addIdea(text) {
                newIdea = ""
                focus = nil
            }
            adding = false
        }
    }

    /// the main chat plans a thread for it
    private func start(_ item: IdeaItem) {
        host.putInChat("Start a thread for this idea from the Ideas note: \(item.text)")
    }

    private func startEdit(_ ref: IdeaRef, _ item: IdeaItem) {
        if editing != nil { saveEdit() }
        draft = item.text
        editing = ref
        focus = .edit
    }

    private func saveEdit() {
        guard let ref = editing else { return }
        editing = nil
        let old = store.ideas?.sections.first { $0.name == ref.section }?.items.first { $0.raw == ref.raw }
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let old, text != old.text else { return }
        change(IdeaChange(op: text.isEmpty ? "delete" : "edit", section: ref.section, old: ref.raw,
                          text: text.isEmpty ? nil : text))
    }

    private func change(_ c: IdeaChange) {
        Task { await store.changeIdea(c) }
    }

    private func openAsNote() {
        guard let l = store.ideas else { return }
        host.path.append(LibraryRow(path: l.path, kind: "note", title: "Ideas", sub: "", mtime: l.mtime, exists: true,
                                    workId: nil, editable: true, thumb: nil, url: nil, group: nil))
    }
}

/// The Library's groups as cards: a tap opens a note or folder inside the Overview, a video in the player.
struct LibraryCards: View {
    let groups: [LibraryGroup]
    let store: ProjectStore
    @Binding var path: NavigationPath
    @State private var playing: MDItem?

    var body: some View {
        ForEach(groups) { g in
            Section {
                ForEach(g.items) { r in
                    Button { tap(r) } label: {
                        LibraryCardRow(row: r, base: store.baseURL, chevron: chevron(r))
                    }
                    .buttonStyle(.plain)
                    .disabled(!r.exists)
                    .listRowBackground(OverviewStyle.card)
                    .listRowInsets(EdgeInsets(top: 0, leading: 14, bottom: 0, trailing: 16))
                    .accessibilityIdentifier("lib-\(r.title)")
                }
            } header: {
                if !g.label.isEmpty { OverviewHeader(text: g.label, count: g.id == "pinned" ? nil : (g.count ?? g.items.count)) }
            }
        }
        .fullScreenCover(item: $playing) { MediaViewer(item: $0, base: store.baseURL) }
    }

    static func isIdeas(_ r: LibraryRow) -> Bool { r.group == "pinned" && r.title == "Ideas" }

    private func chevron(_ r: LibraryRow) -> Bool { r.kind == "folder" || r.group == "pinned" }

    private func tap(_ r: LibraryRow) {
        if r.kind == "video" {
            playing = MDItem(kind: "video", url: r.url ?? r.path, name: r.title, poster: r.thumb)
        } else {
            path.append(r)
        }
    }
}

private struct LibraryCardRow: View {
    let row: LibraryRow
    let base: URL?
    let chevron: Bool

    var body: some View {
        HStack(spacing: 13) {
            mark
            VStack(alignment: .leading, spacing: 3) {
                Text(row.title)
                    .font(.system(size: 17))
                    .foregroundStyle(row.exists ? Theme.rowTitle : ChatStyle.faint)
                    .lineLimit(1)
                Text(row.exists ? row.sub : "Gone from the PC")
                    .font(.system(size: 15))
                    .foregroundStyle(OverviewStyle.grey)
                    .lineLimit(1)
            }
            Spacer(minLength: 6)
            if chevron { RowChevron() }
        }
        .padding(.vertical, 9)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var mark: some View {
        if let t = row.thumb, (row.kind == "image" || row.kind == "video") {
            RemoteImage(url: MediaLink.url(t, base: base), fill: true)
                .frame(width: 44, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                .overlay(alignment: .bottomTrailing) {
                    if row.kind == "video" {
                        Image(systemName: "play.fill").font(.system(size: 9)).foregroundStyle(.white)
                            .padding(3).background(.black.opacity(0.55), in: Circle()).padding(3)
                    }
                }
        } else {
            LucideIcon(name: icon, size: 22)
                .foregroundStyle(ProjectLook.plainIcon)
                .frame(width: 44, height: 44)
        }
    }

    private var icon: String {
        if LibraryCards.isIdeas(row) { return "lightbulb" }
        if row.group == "pinned" && row.kind == "note" { return "notebook-pen" }
        switch row.kind {
        case "folder": return "folder"
        case "image": return "image"
        case "video": return "film"
        case "note": return "file-text"
        default: return "file"
        }
    }
}

// MARK: - Scheduled (1f)

/// The project's schedules (each run is a thread): Scheduled, Running now, Paused and the past runs. The glass +
/// puts "New schedule: " in the main chat's box, as the desktop's New schedule does.
struct ScheduledTab: View {
    let host: OverviewHost
    let store: ProjectStore
    @Environment(\.openChat) private var openChat

    var body: some View {
        List {
            if let s = store.schedules {
                ForEach(s.groups) { g in
                    Section {
                        ForEach(g.items) { r in row(r) }
                    } header: { OverviewHeader(text: g.label, count: g.count) }
                }
                if let past = s.past, !past.isEmpty {
                    Section {
                        ForEach(Array(past.enumerated()), id: \.offset) { _, run in RunRow(run: run) }
                    } header: { OverviewHeader(text: "Past runs") }
                }
                if s.groups.isEmpty {
                    OverviewNotice(icon: "clock", text: s.empty ?? "Nothing scheduled yet.")
                }
                Section {
                    Text(s.footer)
                        .font(.system(size: 15))
                        .foregroundStyle(SheetStyle.label)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 0, leading: 8, bottom: 0, trailing: 8))
                }
            } else {
                ProgressView().frame(maxWidth: .infinity).padding(.vertical, 30).listRowBackground(Color.clear)
            }
        }
        .modifier(OverviewList())
        .refreshable { await store.loadSchedules() }
        .task { await store.loadSchedules() }
    }

    private func row(_ r: ScheduleRow) -> some View {
        Button {
            if r.running, let c = r.chatId { openChat?(c) } else { host.path.append(OverviewPage.schedule(r.id)) }
        } label: {
            ScheduleCardRow(row: r)
        }
        .buttonStyle(.plain)
        .listRowBackground(OverviewStyle.card)
        .accessibilityIdentifier("schedule-\(r.id)")
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if r.paused {
                Button { move(r, "resume") } label: { Label("Resume", systemImage: "play") }.tint(Color(hex: 0x2F5FB3))
            } else if !r.running {
                Button { move(r, "pause") } label: { Label("Pause", systemImage: "pause") }.tint(Color(hex: 0x4A4A4E))
            }
            if !r.running {
                Button { move(r, "run") } label: { Label("Run now", systemImage: "play.fill") }.tint(Color(hex: 0x3D6A45))
            }
        }
    }

    private func move(_ r: ScheduleRow, _ m: String) {
        Task { await store.scheduleMove(r.id, m) }
    }
}

/// 1f's schedule: its mark, title and next run; when it runs; how the last run went
private struct ScheduleCardRow: View {
    let row: ScheduleRow

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            Group {
                if row.running {
                    ThreadMark(glyph: "spin", size: 22)
                } else {
                    LucideIcon(name: row.paused ? "circle-pause" : "clock", size: 22).foregroundStyle(ProjectLook.plainIcon)
                }
            }
            .frame(width: 24)
            .alignmentGuide(.firstTextBaseline) { d in d[VerticalAlignment.center] + 6 }
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(row.title).font(.system(size: 17)).foregroundStyle(Theme.rowTitle).lineLimit(1)
                        .layoutPriority(1)
                    Spacer(minLength: 4)
                    if !row.right.isEmpty {
                        Text(row.right).font(.system(size: 14)).foregroundStyle(OverviewStyle.grey).lineLimit(1)
                    }
                }
                Text(row.whenText ?? row.when)
                    .font(.system(size: 15))
                    .foregroundStyle(OverviewStyle.grey)
                    .lineLimit(2)
                if !row.last.isEmpty && row.last != (row.whenText ?? row.when) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Image(systemName: lastIcon).font(.system(size: 13)).foregroundStyle(lastTint)
                        Text(row.last).font(.system(size: 15)).foregroundStyle(lastTint == ChatStyle.done ? OverviewStyle.grey : lastTint)
                            .lineLimit(2)
                    }
                }
            }
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private var lastIcon: String {
        if row.paused { return "pause.circle" }
        switch row.lastStatus {
        case "ok": return "checkmark.circle"
        case "failed": return "xmark.circle"
        case "skipped": return "slash.circle"
        case "running": return "circle.dotted"
        default: return "circle"
        }
    }

    private var lastTint: Color {
        if row.paused { return OverviewStyle.grey }
        switch row.lastStatus {
        case "ok": return ChatStyle.done
        case "failed": return ChatStyle.failed
        case "skipped": return Theme.amber
        default: return OverviewStyle.grey
        }
    }
}

/// One run of a schedule: the thread it made, or why it didn't run; a tap opens the thread.
private struct RunRow: View {
    let run: ScheduleRun
    @Environment(\.openChat) private var openChat

    var body: some View {
        Button { if let c = run.chatId { openChat?(c) } } label: {
            HStack(spacing: 14) {
                Group {
                    if run.glyph == "pause" {
                        LucideIcon(name: "circle-pause", size: 22).foregroundStyle(ProjectLook.plainIcon)
                    } else {
                        ThreadMark(glyph: run.glyph, size: 22)
                    }
                }
                .frame(width: 24)
                VStack(alignment: .leading, spacing: 3) {
                    Text(run.title).font(.system(size: 17)).foregroundStyle(Theme.rowTitle).lineLimit(1)
                    Text(run.line).font(.system(size: 15))
                        .foregroundStyle(run.status == "failed" ? ChatStyle.failed : OverviewStyle.grey)
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(run.chatId == nil)
        .listRowBackground(OverviewStyle.card)
    }
}

/// A schedule's own page: when it runs, its prompt and model, and its runs.
struct ScheduleDetailPage: View {
    let store: ProjectStore
    let id: String

    private var row: ScheduleRow? { store.schedules?.groups.flatMap(\.items).first { $0.id == id } }

    var body: some View {
        List {
            if let r = row {
                Section {
                    line("When", r.whenText ?? r.when)
                    if let n = r.next, !n.isEmpty { line("Next run", n) }
                    if !r.last.isEmpty { line("Last run", r.last) }
                    line("Model", [r.model ?? "", r.effort ?? ""].filter { !$0.isEmpty }.joined(separator: " \u{00B7} "))
                }
                if let p = r.prompt, !p.isEmpty {
                    Section {
                        Text(p).font(.system(size: 17)).foregroundStyle(Theme.rowTitle).textSelection(.enabled)
                            .listRowBackground(OverviewStyle.card)
                    } header: { OverviewHeader(text: "Prompt") }
                }
                Section {
                    if !r.running {
                        Button("Run now", systemImage: "play.fill") { move("run") }
                            .accessibilityIdentifier("scheduleRun")
                    }
                    Button(r.paused ? "Resume" : "Pause", systemImage: r.paused ? "play" : "pause") {
                        move(r.paused ? "resume" : "pause")
                    }
                    .accessibilityIdentifier("schedulePause")
                }
                .listRowBackground(OverviewStyle.card)
                .foregroundStyle(Theme.rowTitle)
                if let runs = r.runs, !runs.isEmpty {
                    Section {
                        ForEach(Array(runs.enumerated()), id: \.offset) { _, run in RunRow(run: run) }
                    } header: { OverviewHeader(text: "Runs") }
                }
            } else {
                OverviewNotice(icon: "clock", text: "This schedule is gone.")
            }
        }
        .modifier(OverviewList())
        .navigationTitle(row?.title ?? "Schedule")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func line(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).foregroundStyle(Theme.rowTitle)
            Spacer(minLength: 12)
            Text(value.isEmpty ? "\u{2014}" : value).foregroundStyle(OverviewStyle.grey).multilineTextAlignment(.trailing)
        }
        .font(.system(size: 17))
        .listRowBackground(OverviewStyle.card)
    }

    private func move(_ m: String) {
        Task { await store.scheduleMove(id, m) }
    }
}

/// The panel's thread glyphs.
struct Glyph: View {
    let name: String
    var size: CGFloat = 15

    var body: some View {
        switch name {
        case "needs": Circle().fill(Theme.violet).frame(width: 8, height: 8).accessibilityLabel("Needs you")
        case "spin": Spinner()
        case "pause": icon("pause.circle", ChatStyle.dim).accessibilityLabel("Paused")
        case "review": icon("smallcircle.filled.circle", Theme.blue).accessibilityLabel("Being checked")
        case "ring": icon("circle.dashed", ChatStyle.dim).accessibilityLabel("Up next")
        case "check": icon("checkmark", ChatStyle.done).accessibilityLabel("Done")
        case "cross": icon("xmark", ChatStyle.failed).accessibilityLabel("Stopped")
        default: Circle().fill(Theme.idleDot).frame(width: 8, height: 8).accessibilityLabel("Idle")
        }
    }

    private func icon(_ system: String, _ color: Color) -> some View {
        Image(systemName: system).font(.system(size: size, weight: .semibold)).foregroundStyle(color)
    }
}
