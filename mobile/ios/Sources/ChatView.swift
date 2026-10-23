import SwiftUI

/// A step card's own screen, pushed from the chat.
struct CardRoute: Hashable {
    let id: String
}

/// D2: one chat, read-only in this slice. Turns come from the PC and stay live; the composer is shown but off.
struct ChatView: View {
    @State private var store: ChatStore
    @State private var folds: [String: Bool] = [:]
    @State private var showDetails = false
    @State private var position = ScrollPosition(edge: .bottom)
    @State private var atBottom = true
    @Environment(\.scenePhase) private var phase

    init(id: String, pairing: Pairing?, demo: Bool) {
        _store = State(initialValue: ChatStore(id: id, pairing: pairing, demo: demo))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if store.more || store.loadingOlder {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                }
                ForEach(store.turns) { t in
                    TurnView(turn: t, base: store.baseURL, open: folds[t.id] ?? t.open) {
                        withAnimation(.easeInOut(duration: 0.2)) { folds[t.id] = !(folds[t.id] ?? t.open) }
                    }
                }
                footer
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 12)
        }
        .defaultScrollAnchor(.bottom)
        .scrollPosition($position)
        .onScrollGeometryChange(for: Bool.self) { g in
            g.contentOffset.y + g.contentInsets.top < 300
        } action: { _, nearTop in
            if nearTop { Task { await store.loadOlder() } }
        }
        .onScrollGeometryChange(for: Bool.self) { g in
            g.contentOffset.y + g.containerSize.height - g.contentInsets.bottom >= g.contentSize.height - 120
        } action: { _, bottom in
            atBottom = bottom
        }
        .onChange(of: store.turns.isEmpty) { _, empty in
            // the first page: start at the newest turn (again once pictures have taken their room)
            guard !empty else { return }
            position.scrollTo(edge: .bottom)
            Task {
                try? await Task.sleep(nanoseconds: 300_000_000)
                position.scrollTo(edge: .bottom)
            }
        }
        .onChange(of: store.liveTick) {
            // follow a running turn, unless you scrolled up to read
            if atBottom { withAnimation(.easeOut(duration: 0.25)) { position.scrollTo(edge: .bottom) } }
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Theme.background)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            BottomBar(usage: store.header?.usage ?? [], asking: asking)
        }
        .navigationBarTitleDisplayMode(.inline)
        // a solid bar under the title, as in D2: turns scroll under it instead of showing through
        .toolbarBackground(Theme.background, for: .navigationBar)
        .toolbarBackgroundVisibility(.visible, for: .navigationBar)
        .toolbar { toolbar }
        .task(id: phase == .active) {
            if phase == .active { await store.run() }
        }
        .navigationDestination(for: CardRoute.self) { r in
            CardDetailView(store: store, cardId: r.id)
        }
        .sheet(isPresented: $showDetails) {
            if let h = store.header { ChatDetailsSheet(header: h) }
        }
    }

    /// a thread's question waits in this chat: the composer reads "Answer or ask…"
    private var asking: Bool {
        store.turns.last?.outside?.contains { $0.type == "ask" && $0.answered != true } ?? false
    }

    @ViewBuilder
    private var footer: some View {
        if store.gone {
            Notice(icon: "trash", text: "This chat isn't on the PC anymore.")
        } else if let e = store.error {
            Notice(icon: "exclamationmark.triangle", text: e == .unreachable ? "Reconnecting\u{2026} " + e.message : e.message)
        } else if store.header != nil && store.turns.isEmpty {
            Notice(icon: "bubble.left", text: "No messages yet.")
        } else if store.header == nil {
            ProgressView().frame(maxWidth: .infinity).padding(.vertical, 40)
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            Button { showDetails = true } label: { TitleView(header: store.header) }
                .buttonStyle(.plain)
                .accessibilityIdentifier("chatTitle")
        }
        .sharedBackgroundVisibility(.hidden)
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                // slices 3, 4 and 8
                Button("Claude's browser", systemImage: "globe") {}.disabled(true)
                Button("Claude's screen", systemImage: "display") {}.disabled(true)
                Button("Your messages", systemImage: "text.bubble") {}.disabled(true)
                Button("Rename", systemImage: "pencil") {}.disabled(true)
                Button("Chat details", systemImage: "info.circle") { showDetails = true }
            } label: {
                Image(systemName: "ellipsis").foregroundStyle(Theme.rowTitle)
            }
            .accessibilityLabel("More")
        }
    }
}

/// "Gallery lightbox fix" over "Opus 5.5 · medium · Bypass ⌄" (Bypass in red); a main chat says "Main chat · Haiku 5.5".
private struct TitleView: View {
    let header: ChatHeader?

    var body: some View {
        VStack(spacing: 1) {
            Text(header?.title ?? " ")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Theme.title)
                .lineLimit(1)
            if let h = header {
                HStack(spacing: 4) {
                    subtitle(h)
                        .font(.system(size: 13))
                        .foregroundStyle(ChatStyle.dim)
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(ChatStyle.dim)
                }
            }
        }
        .frame(maxWidth: 260)
        .accessibilityElement(children: .combine)
    }

    private func subtitle(_ h: ChatHeader) -> Text {
        if h.role == "main" {
            return Text("Main chat · \(h.model)")
        }
        let parts = [h.model, h.effort].filter { !$0.isEmpty }.joined(separator: " · ")
        if h.bypass {
            return Text("\(parts) · \(Text("Bypass").foregroundStyle(Color(hex: 0xE07C7C)))")
        }
        return Text(parts)
    }
}

private struct Notice: View {
    let icon: String
    let text: String

    var body: some View {
        Label(text, systemImage: icon)
            .font(.subheadline)
            .foregroundStyle(ChatStyle.dim)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 20)
    }
}

// MARK: - a turn

struct TurnView: View {
    let turn: Turn
    let base: URL?
    let open: Bool
    let toggle: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PromptView(turn: turn, base: base)
            if let h = turn.handle {
                HandleRow(handle: h, open: open, turnId: turn.id, toggle: toggle)
                    .padding(.top, 10)
            }
            if lastAnswer == nil { outsideViews }
            ForEach(Array(shown.enumerated()), id: \.offset) { _, item in
                BlockView(block: item.block, base: base)
                if item.index == lastAnswer { outsideViews }
            }
        }
        .padding(.top, 14)
    }

    /// a folded turn shows only its answer; a turn without steps has nothing to fold
    private var shown: [(index: Int, block: Block)] {
        turn.blocks.enumerated()
            .filter { _, b in turn.handle == nil || open || b.answer == true }
            .map { (index: $0.offset, block: $0.element) }
    }

    /// the reply's last text: what stays outside the fold goes right under it
    private var lastAnswer: Int? {
        turn.blocks.lastIndex { $0.type == "text" && $0.answer == true }
    }

    @ViewBuilder
    private var outsideViews: some View {
        ForEach(turn.outside ?? []) { o in
            OutsideView(item: o)
        }
    }
}

/// What opened the turn: your blue bubble, a slash command, a fresh start, or a GupWorks notice.
private struct PromptView: View {
    let turn: Turn
    let base: URL?

    var body: some View {
        switch turn.kind {
        case "command":
            HStack {
                Spacer(minLength: 60)
                Text(turn.prompt.text ?? "")
                    .font(.system(size: 15, design: .monospaced))
                    .foregroundStyle(ChatStyle.dim)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(ChatStyle.chevronBG, in: Capsule())
            }
            .padding(.top, 4)
        case "handoff":
            FoldedDivider(label: "Fresh start · handoff", text: turn.prompt.text ?? "")
        case "notice":
            NoticeCard(prompt: turn.prompt)
        case "task":
            Label(taskLine, systemImage: "checklist")
                .font(.system(size: 15))
                .foregroundStyle(ChatStyle.dim)
                .padding(.vertical, 4)
        default:
            Bubble(prompt: turn.prompt, base: base)
        }
    }

    private var taskLine: String {
        let s = turn.prompt.text ?? "A background task finished"
        guard let st = turn.prompt.status, !st.isEmpty else { return s }
        return "\(s) · \(st)"
    }
}

struct Bubble: View {
    let prompt: Prompt
    let base: URL?
    var queued = false
    @State private var open: MDItem?

    var body: some View {
        VStack(alignment: .trailing, spacing: 6) {
            if let images = prompt.images, !images.isEmpty {
                HStack(spacing: 6) {
                    Spacer(minLength: 60)
                    ForEach(images, id: \.self) { link in
                        Button { open = MDItem(kind: "image", url: link, name: "Your picture") } label: {
                            RemoteImage(url: MediaLink.url(link, base: base), fill: true)
                                .frame(width: 96, height: 96)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Your picture")
                    }
                }
            }
            if let text = prompt.text, !text.isEmpty {
                HStack {
                    Spacer(minLength: 60)
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        if prompt.phone == true {
                            Image(systemName: "iphone").font(.system(size: 13)).foregroundStyle(.white.opacity(0.75))
                        }
                        Text(text)
                            .font(.system(size: 17))
                            .lineSpacing(2)
                            .foregroundStyle(.white)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(queued ? Color(hex: 0x24365A) : ChatStyle.bubble, in: RoundedRectangle(cornerRadius: 14))
                }
            }
            if queued {
                Text("queued · sends when Claude is done")
                    .font(.system(size: 13))
                    .foregroundStyle(ChatStyle.dim)
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .padding(.top, 4)
        .fullScreenCover(item: $open) { MediaViewer(item: $0, base: base) }
    }
}

/// "Worked for 48s  7 steps" with a chevron; while the turn runs "Working 1:02 · 3 steps" with the clock ticking.
private struct HandleRow: View {
    let handle: Handle
    let open: Bool
    let turnId: String
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: 12) {
                Image(systemName: open ? "chevron.down" : "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color(hex: 0xA0A0A0))
                    .frame(width: 28, height: 28)
                    .background(ChatStyle.chevronBG, in: RoundedRectangle(cornerRadius: 8))
                label
                    .font(.system(size: 15))
                    .lineLimit(1)
                    .layoutPriority(1)
                Rectangle().fill(ChatStyle.line).frame(height: 1)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("handle")
        .accessibilityValue(open ? "open" : "folded")
    }

    @ViewBuilder
    private var label: some View {
        if let since = handle.since {
            TimelineView(.periodic(from: .now, by: 1)) { ctx in
                let clock = Format.clock(ctx.date.timeIntervalSince1970 * 1000 - since)
                let stats = handle.stats.isEmpty ? "" : " · \(handle.stats)"
                Text("\(Text(handle.title).foregroundStyle(ChatStyle.body)) \(Text(clock).foregroundStyle(ChatStyle.clock).monospacedDigit())\(Text(stats).foregroundStyle(ChatStyle.dim))")
            }
        } else {
            Text("\(Text(handle.title).foregroundStyle(ChatStyle.body))  \(Text(handle.stats).foregroundStyle(ChatStyle.dim))")
        }
    }
}

// MARK: - blocks

private struct BlockView: View {
    let block: Block
    let base: URL?

    var body: some View {
        switch block.type {
        case "text":
            MarkdownView(blocks: block.md ?? [], base: base)
                .padding(.top, 12)
        case "card":
            NavigationLink(value: CardRoute(id: block.id ?? "")) {
                StepCard(block: block)
            }
            .buttonStyle(.plain)
            .padding(.top, 8)
        case "divider":
            FoldedDivider(label: block.label ?? "", text: block.body ?? "")
        case "error":
            Label(block.text ?? "", systemImage: "exclamationmark.triangle")
                .font(.system(size: 15))
                .foregroundStyle(ChatStyle.failed)
                .padding(.top, 12)
                .fixedSize(horizontal: false, vertical: true)
        case "stdout":
            Text(block.text ?? "")
                .font(.system(size: 13, design: .monospaced))
                .foregroundStyle(ChatStyle.dim)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(ChatStyle.cardBG, in: RoundedRectangle(cornerRadius: 10))
                .padding(.top, 10)
        case "prompt":
            if let p = block.prompt { Bubble(prompt: p, base: base, queued: true).padding(.top, 8) }
        case "notice":
            if let p = block.prompt { NoticeCard(prompt: p) }
        default:
            EmptyView()
        }
    }
}

/// A step card: dot, title, "3 steps · 1.2s" (or "2 steps · +6 −2"), chevron. Taps open its own screen.
struct StepCard: View {
    let block: Block

    var body: some View {
        HStack(spacing: 10) {
            indicator.frame(width: 16)
            Text(block.title ?? "")
                .font(.system(size: 16))
                .foregroundStyle(Theme.rowTitle)
                .lineLimit(2)  // long stats ("3 steps · 1 failed · 2.4s") leave less room: wrap, don't cut
                .truncationMode(.tail)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 6)
            meta
                .font(.system(size: 13))
                .lineLimit(1)
                .layoutPriority(1)
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(ChatStyle.dim)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .frame(minHeight: 48)
        .background(ChatStyle.cardBG, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(ChatStyle.cardBorder, lineWidth: 1))
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }

    @ViewBuilder
    private var indicator: some View {
        switch block.state {
        case "running": Spinner().scaleEffect(0.8)
        case "failed": Circle().fill(ChatStyle.failed).frame(width: 7, height: 7)
        case "stopped": Circle().fill(Color(hex: 0x555555)).frame(width: 7, height: 7)
        default: Circle().fill(ChatStyle.done).frame(width: 7, height: 7)
        }
    }

    @ViewBuilder
    private var meta: some View {
        let stats = Self.stats(block)
        if block.state == "running", let since = block.since {
            TimelineView(.periodic(from: .now, by: 1)) { ctx in
                let clock = Format.clock(ctx.date.timeIntervalSince1970 * 1000 - since)
                Text(stats.isEmpty ? clock : "\(clock) · \(stats)").foregroundStyle(ChatStyle.dim).monospacedDigit()
            }
        } else {
            let failed = block.state == "failed"
            HStack(spacing: 4) {
                if !stats.isEmpty {
                    Text(stats).foregroundStyle(failed ? ChatStyle.failed : ChatStyle.dim)
                }
                if let a = block.add, a > 0 {
                    Text((stats.isEmpty ? "" : "· ") + "+\(a)").foregroundStyle(ChatStyle.add)
                }
                if let d = block.del, d > 0 {
                    Text("\u{2212}\(d)").foregroundStyle(ChatStyle.del)
                }
            }
        }
    }

    /// The card's stats; with a diff the time gives way to +added −removed, as in the mockup.
    static func stats(_ b: Block) -> String {
        var parts = (b.stats ?? "").components(separatedBy: " · ").filter { !$0.isEmpty }
        if (b.add ?? 0) + (b.del ?? 0) > 0, let last = parts.last, last.first?.isNumber == true, last.hasSuffix("s") {
            parts.removeLast()
        }
        return parts.joined(separator: " · ")
    }
}

/// "› Earlier messages summarised": the text it stands for unfolds under it.
private struct FoldedDivider: View {
    let label: String
    let text: String
    @State private var open = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { open.toggle() }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: open ? "chevron.down" : "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                    Text(label).font(.system(size: 15)).lineLimit(1).layoutPriority(1)
                    Rectangle().fill(ChatStyle.line).frame(height: 1)
                }
                .foregroundStyle(ChatStyle.dim)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("divider")
            if open && !text.isEmpty {
                Text(text)
                    .font(.system(size: 15))
                    .foregroundStyle(ChatStyle.dim)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, 22)
            }
        }
        .padding(.top, 10)
    }
}

/// A GupWorks message in the chat (a thread's update, a handoff ask): "a6 Accessibility pass  asks" and its words.
private struct NoticeCard: View {
    let prompt: Prompt
    @State private var open = false

    static let word: [String: String] = [
        "asks": "asks", "submitted": "submitted", "waiting": "waiting", "stalled": "stalled", "ended": "stopped",
        "failed": "failed", "started": "started", "told": "from you", "rework": "sent back", "handoff": "handoff",
    ]
    static let colour: [String: UInt32] = [
        "asks": 0xA897E0, "submitted": 0x7FB287, "waiting": 0x86A2CC, "stalled": 0xD1A266, "ended": 0xD1A266,
        "failed": 0xD98A85, "rework": 0xD1A266,
    ]

    var body: some View {
        let items = prompt.items ?? [NoticeItem(kind: "note", work: "", title: prompt.plugin ?? "", body: prompt.text ?? "")]
        let shown = open ? items : Array(items.prefix(4))
        Button {
            withAnimation(.easeInOut(duration: 0.2)) { open.toggle() }
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                if items.count > 1 {
                    Text("\(items.count) updates").font(.system(size: 13, weight: .semibold)).foregroundStyle(ChatStyle.dim)
                }
                ForEach(Array(shown.enumerated()), id: \.offset) { _, it in
                    VStack(alignment: .leading, spacing: 3) {
                        heading(it)
                        Text(it.body)
                            .font(.system(size: 15))
                            .foregroundStyle(Color(hex: 0xC6C6CA))
                            .lineLimit(open ? nil : 4)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                if !open && shown.count < items.count {
                    Text("+\(items.count - shown.count) more").font(.system(size: 13)).foregroundStyle(ChatStyle.dim)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(Color(hex: 0x1C1C20), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(ChatStyle.cardBorder, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .padding(.top, 8)
    }

    private func heading(_ it: NoticeItem) -> some View {
        let name = [it.work, it.title].filter { !$0.isEmpty }.joined(separator: " ")
        let w = Self.word[it.kind] ?? ""
        let c = Self.colour[it.kind].map { Color(hex: $0) } ?? ChatStyle.dim
        return Text("\(Text(name.isEmpty ? "Update" : name).foregroundStyle(Theme.rowTitle).bold())\(Text(w.isEmpty ? "" : "  " + w).foregroundStyle(c))")
            .font(.system(size: 15))
    }
}

// MARK: - outside the fold

private struct OutsideView: View {
    let item: Outside

    var body: some View {
        switch item.type {
        case "ask":
            AskCard(item: item).padding(.top, 12)
        case "threads":
            OutsideBox(title: item.title ?? "", meta: "", foldable: false) {
                ForEach(item.threads ?? [], id: \.id) { t in
                    row(icon: "arrow.triangle.branch", title: "\(t.id) \(t.title)", line: t.model, state: "")
                }
            }
        case "helpers":
            OutsideBox(title: item.title ?? "", meta: item.stats ?? "", foldable: true) {
                ForEach(item.helpers ?? [], id: \.id) { h in
                    row(icon: "person.2", title: h.title, line: h.line, state: h.state)
                }
            }
        case "changes":
            OutsideBox(title: item.title ?? "", meta: "", add: item.add, del: item.del, foldable: true) {
                ForEach(item.files ?? [], id: \.path) { f in
                    HStack(spacing: 8) {
                        Text(f.path)
                            .font(.system(size: 14, design: .monospaced))
                            .foregroundStyle(Theme.rowTitle)
                            .lineLimit(1)
                            .truncationMode(.head)
                        if f.created == true {
                            Text("new").font(.system(size: 12)).foregroundStyle(ChatStyle.dim)
                        }
                        Spacer(minLength: 6)
                        if f.add > 0 { Text("+\(f.add)").foregroundStyle(ChatStyle.add) }
                        if f.del > 0 { Text("\u{2212}\(f.del)").foregroundStyle(ChatStyle.del) }
                    }
                    .font(.system(size: 13))
                    .padding(.horizontal, 14)
                    .frame(minHeight: 40)
                }
            }
        default:
            EmptyView()
        }
    }

    private func row(icon: String, title: String, line: String, state: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon).font(.system(size: 13)).foregroundStyle(ChatStyle.dim).frame(width: 18).padding(.top, 2)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 15)).foregroundStyle(Theme.rowTitle).lineLimit(1)
                if !line.isEmpty {
                    Text(line).font(.system(size: 13)).foregroundStyle(ChatStyle.dim).lineLimit(2)
                }
            }
            Spacer(minLength: 6)
            if !state.isEmpty {
                Text(state).font(.system(size: 13)).foregroundStyle(state == "failed" ? ChatStyle.failed : ChatStyle.dim)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }
}

/// A box under the reply (threads started, helpers, changed files): a 48 pt header, the rows under it.
private struct OutsideBox<Rows: View>: View {
    let title: String
    let meta: String
    var add: Int? = nil
    var del: Int? = nil
    let foldable: Bool
    @ViewBuilder var rows: () -> Rows
    @State private var open = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                if foldable { withAnimation(.easeInOut(duration: 0.2)) { open.toggle() } }
            } label: {
                HStack(spacing: 6) {
                    Text(title).font(.system(size: 16, weight: .medium)).foregroundStyle(Theme.rowTitle)
                    Spacer(minLength: 6)
                    if !meta.isEmpty { Text(meta).foregroundStyle(ChatStyle.dim) }
                    if let a = add, a > 0 { Text("+\(a)").foregroundStyle(ChatStyle.add) }
                    if let d = del, d > 0 { Text("\u{2212}\(d)").foregroundStyle(ChatStyle.del) }
                    if foldable {
                        Image(systemName: open ? "chevron.down" : "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(ChatStyle.dim)
                    }
                }
                .font(.system(size: 13))
                .padding(.horizontal, 14)
                .frame(height: 48)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if open || !foldable {
                Rectangle().fill(Color(hex: 0x232326)).frame(height: 1)
                rows().padding(.vertical, 4)
            }
        }
        .background(ChatStyle.cardBG, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(ChatStyle.cardBorder, lineWidth: 1))
        .padding(.top, 12)
    }
}

/// D11's "THREAD NEEDS YOU" card. Read-only in this slice: the choices show, answering comes with slice 4.
private struct AskCard: View {
    let item: Outside

    var body: some View {
        let answered = item.answered == true
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(answered ? "THREAD ASKED · ANSWERED" : "THREAD NEEDS YOU")
                    .font(.system(size: 12, weight: .semibold))
                    .tracking(0.6)
                    .foregroundStyle(Theme.violetText)
                Spacer()
                Text([item.work ?? "", Format.shortModel(item.model ?? "")].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.system(size: 13))
                    .foregroundStyle(ChatStyle.dim)
            }
            Text(Inline.text(item.question ?? "", color: Color(hex: 0xD8D8D8)))
                .font(.system(size: 17))
                .lineSpacing(5)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 10)
                .padding(.bottom, answered ? 0 : 12)
            if !answered, let options = item.options, !options.isEmpty {
                FlowLayout(spacing: 8) {
                    ForEach(Array(options.enumerated()), id: \.offset) { i, o in
                        Text(o)
                            .font(.system(size: 16))
                            .foregroundStyle(i == 0 ? .white : ChatStyle.body)
                            .padding(.horizontal, 16)
                            .frame(height: 44)
                            .background(i == 0 ? ChatStyle.bubble : .clear, in: RoundedRectangle(cornerRadius: 12))
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(i == 0 ? ChatStyle.bubble : Color(hex: 0x34343A), lineWidth: 1))
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityHint("Answering from the phone comes in a later update.")
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 14)
        .background(Color(hex: 0x17151D), in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(answered ? Color(hex: 0x3A3358) : Theme.blue.opacity(0.75), lineWidth: answered ? 1 : 2)
        )
        .shadow(color: answered ? .clear : Theme.blue.opacity(0.25), radius: 12)
        .accessibilityIdentifier("ask")
    }
}

/// Lays its children out in rows, wrapping like words (the ask card's buttons).
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, row: CGFloat = 0, widest: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > width {
                y += row + spacing
                x = 0
                row = 0
            }
            x += size.width + spacing
            row = max(row, size.height)
            widest = max(widest, x - spacing)
        }
        return CGSize(width: min(widest, width), height: y + row)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, row: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x > bounds.minX && x + size.width > bounds.maxX {
                y += row + spacing
                x = bounds.minX
                row = 0
            }
            s.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            row = max(row, size.height)
        }
    }
}

// MARK: - bottom

/// The composer (off until slice 3) and the usage pill floating above it.
private struct BottomBar: View {
    let usage: [Meter]
    let asking: Bool

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            if !asking, let ctx = usage.first(where: { $0.label == "ctx" })?.percent {
                UsagePill(ctx: ctx, fiveHours: usage.first { $0.label == "5h" }?.percent)
                    .padding(.horizontal, 16)
            }
            HStack(spacing: 8) {
                Image(systemName: "plus")
                    .font(.system(size: 20, weight: .regular))
                    .foregroundStyle(Theme.rowTitle)
                    .frame(width: 52, height: 52)
                    .background(Self.fill, in: Circle())
                    .overlay(Circle().stroke(Self.border, lineWidth: 1))
                    .accessibilityLabel("Attach")
                HStack(spacing: 0) {
                    Text(asking ? "Answer or ask\u{2026}" : "Ask Claude anything\u{2026}")
                        .font(.system(size: 17))
                        .foregroundStyle(Color(hex: 0x8A8A90))
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    // "/" in a small square: commands (slice 3)
                    Text("/")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color(hex: 0xB4B4B8))
                        .frame(width: 19, height: 19)
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color(hex: 0xB4B4B8), lineWidth: 1.5))
                        .frame(width: 44, height: 44)
                    Image(systemName: "mic")
                        .font(.system(size: 18))
                        .foregroundStyle(Theme.rowTitle)
                        .frame(width: 44, height: 44)
                }
                .padding(.leading, 18)
                .padding(.trailing, 4)
                .frame(height: 52)
                .background(Self.fill, in: Capsule())
                .overlay(Capsule().stroke(Self.border, lineWidth: 1))
            }
            .padding(.horizontal, 16)
            .padding(.top, 6)
            .padding(.bottom, 6)
            .background(Theme.background.ignoresSafeArea(edges: .bottom))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Writing from the phone comes in the next update")
        }
    }

    static let fill = Color(hex: 0x1F1F22)
    static let border = Color(hex: 0x2E2E33)
}

/// "◔ 34% | 5h 5%": the context ring and the five-hour use.
private struct UsagePill: View {
    let ctx: Double
    let fiveHours: Double?

    var body: some View {
        HStack(spacing: 8) {
            ZStack {
                Circle().stroke(Color.white.opacity(0.15), lineWidth: 2.5)
                Circle()
                    .trim(from: 0, to: max(0.02, min(1, ctx / 100)))
                    .stroke(Theme.blue, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: 15, height: 15)
            Text("\(Int(ctx.rounded()))%").foregroundStyle(Theme.rowTitle)
            if let f = fiveHours {
                Rectangle().fill(Color.white.opacity(0.2)).frame(width: 1, height: 14)
                Text("\(Text("5h").foregroundStyle(ChatStyle.dim)) \(Text("\(Int(f.rounded()))%").foregroundStyle(Theme.rowTitle))")
            }
        }
        .font(.system(size: 15))
        .monospacedDigit()
        .padding(.horizontal, 14)
        .frame(height: 36)
        .background(BottomBar.fill, in: Capsule())
        .overlay(Capsule().stroke(BottomBar.border, lineWidth: 1))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Context \(Int(ctx.rounded())) percent used")
    }
}

// MARK: - details

/// Tapping the title: the chat's model, effort, Bypass, usage and folder (changing them comes with slice 4).
struct ChatDetailsSheet: View {
    let header: ChatHeader
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    row("Model", header.model)
                    if !header.effort.isEmpty { row("Effort", header.effort) }
                    row("Bypass", header.bypass ? "On" : "Off", color: header.bypass ? Color(hex: 0xE07C7C) : nil)
                    if let p = header.provider, !p.isEmpty { row("Runs on", p) }
                }
                if !header.usage.isEmpty {
                    Section("Usage") {
                        ForEach(header.usage, id: \.label) { m in
                            row(meterName(m.label), m.percent.map { "\(Int($0.rounded()))%" } ?? "\u{2013}")
                        }
                    }
                }
                Section {
                    if let p = header.project { row("Project", p.name) }
                    if let f = header.folder, !f.isEmpty { row("Folder", f) }
                    if let b = header.branch, !b.isEmpty { row("Branch", b) }
                }
            }
            .navigationTitle(header.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func meterName(_ label: String) -> String {
        switch label {
        case "ctx": return "Context"
        case "5h": return "5 hours"
        case "wk": return "Week"
        default: return label
        }
    }

    private func row(_ name: String, _ value: String, color: Color? = nil) -> some View {
        HStack {
            Text(name)
            Spacer()
            Text(value).foregroundStyle(color ?? ChatStyle.dim).lineLimit(1).truncationMode(.middle)
        }
    }
}
