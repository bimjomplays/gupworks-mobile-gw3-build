import SwiftUI

/// A step card's own screen, pushed from the chat.
struct CardRoute: Hashable {
    let id: String
}

/// D2/D3/D6, 5a/5e: one chat, live from the PC, with the box; `id` nil is a new chat, made by its first message.
/// The main screen's chat has a `shell` (the menu button, the temporary switch); a project's thread pushed over it
/// has none and goes back instead.
struct ChatView: View {
    let shell: ChatShell?
    @State private var store: ChatStore
    @State private var usageOpen = false
    @State private var folds: [String: Bool] = [:]
    @State private var showDetails = false
    @State private var position = ScrollPosition(edge: .bottom)
    @State private var atBottom = true
    @State private var renaming = false
    @State private var newTitle = ""
    @State private var confirmDelete = false
    @State private var selecting: SelectedText?
    // a121: a project's main chat (05) has its Overview (06-10) and settings (11); a thread's chat (07) its task
    @State private var project: ProjectStore?
    @State private var opensSheet: Bool
    /// a141: on top of its stack (a main chat's Overview slides in over it only then)
    @State private var shown = false
    @State private var showSettings = false
    @State private var showTask = false
    @State private var confirmStop = false
    @Environment(\.openChat) private var openChat
    @Environment(\.scenePhase) private var phase
    @Environment(\.dismiss) private var dismiss
    @Environment(AppModel.self) private var model
    @Environment(OverviewHost.self) private var overview: OverviewHost?

    /// `projectSheet`: a project's main chat opens with its Overview up (06); only the demo's `-sheet` shots set it (a149)
    init(id: String?, pairing: Pairing?, demo: Bool, projectSheet: Bool = false, shell: ChatShell? = nil) {
        self.shell = shell
        _store = State(initialValue: ChatStore(id: id ?? "", pairing: pairing, demo: demo))
        _opensSheet = State(initialValue: projectSheet)
    }

    var body: some View {
        projectParts(sheets(alerts(chat)))
    }

    /// the project's id when this is its main chat
    private var mainOf: String? {
        guard let h = store.header, h.role == "main" else { return nil }
        return h.project?.id
    }

    /// a thread's own chat (07): its task, state and moves
    private var work: ChatHeader.WorkInfo? {
        guard let h = store.header, h.role == "worker" else { return nil }
        return h.work
    }

    /// the project this chat leads or works in
    private var projectOf: String? {
        if let m = mainOf { return m }
        guard let w = work else { return nil }
        return w.projectId ?? store.header?.project?.id
    }

    /// the thread as the project's view has it now (live state), when this is a thread's chat
    private var liveThread: ThreadItem? {
        guard let w = work else { return nil }
        return project?.view?.allThreads.first { $0.id == w.id }
    }

    private var threadsById: [String: ThreadItem] {
        Dictionary((project?.view?.allThreads ?? []).map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
    }

    /// split from body so the compiler can type-check it
    private func projectParts(_ v: some View) -> some View {
        v
            .onChange(of: projectOf, initial: true) { _, pid in
                guard let pid else { return }
                if project?.id != pid { project = ProjectStore(id: pid, pairing: model.pairing, demo: model.demo) }
                register()
                if opensSheet && mainOf != nil {
                    opensSheet = false
                    // after the push has settled
                    Task {
                        try? await Task.sleep(nanoseconds: 450_000_000)
                        overview?.present()
                    }
                }
            }
            .onAppear {
                shown = true
                register()
            }
            .onDisappear {
                shown = false
                overview?.detach(store.id)
            }
            .task(id: "\(phase == .active) \(project?.id ?? "")") {
                if phase == .active, let project { await project.follow() }
            }
            .sheet(isPresented: $showSettings) {
                if let pid = projectOf {
                    ProjectSettingsSheet(projectId: pid) {
                        // archived or deleted: its chat goes too, once the sheet has gone
                        Task {
                            try? await Task.sleep(nanoseconds: 450_000_000)
                            leave()
                        }
                    }
                }
            }
            .sheet(isPresented: $showTask) {
                if let work { TaskSheet(work: work) }
            }
            .confirmationDialog("Stop \u{201C}\(work?.title ?? "this thread")\u{201D}?", isPresented: $confirmStop,
                                titleVisibility: .visible) {
                Button("Stop", role: .destructive) { threadMove("stop") }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Its Claude stops working on it. The thread stays in the project, so it can be picked up again.")
            }
            .alert("That didn't work", isPresented: Binding(get: { !overviewUp && project?.actionError != nil },
                                                           set: { if !$0 { project?.actionError = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(project?.actionError ?? "")
            }
            .environment(\.projectThreads, threadsById)
    }

    /// a141: a project's main chat on top of its stack lends the Overview its project (MainView draws it)
    private func register() {
        guard shown, mainOf != nil, let project, let overview, !store.id.isEmpty else { return }
        let chat = store
        overview.attach(project, chat: store.id, put: { text in chat.put(text) })
    }

    /// this chat's Overview is in (its errors show there)
    private var overviewUp: Bool {
        guard let overview, overview.chatId == store.id else { return false }
        return overview.progress > 0
    }

    /// 05's Overview button: slides the Overview in (1a)
    private func toggleOverview() {
        register()
        overview?.toggle()
    }

    /// 07's ⋯: Pause or Resume, Mark done, Archive, Stop, as the Overview's swipes do
    private func threadMove(_ move: String) {
        guard let w = work, let project else { return }
        Task { await project.move(move, thread: w.id) }
    }

    private var chat: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if store.more || store.loadingOlder {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                }
                if let w = work, !store.more, store.header != nil {
                    TaskCard(work: w) { showTask = true }
                        .padding(.top, 12)
                        .padding(.bottom, 4)
                }
                ForEach(store.turns) { t in
                    TurnView(turn: t, base: store.baseURL, open: folds[t.id] ?? t.open, briefed: t.id == briefed) {
                        withAnimation(.easeInOut(duration: 0.2)) { folds[t.id] = !(folds[t.id] ?? t.open) }
                    }
                }
                ForEach(store.waiting) { q in
                    // "queued" only while Claude works: an idle chat sends it within a moment
                    QueuedBubble(item: q, base: store.baseURL, waits: store.working).padding(.top, 14)
                }
                ForEach(store.sending) { m in
                    OutgoingBubble(message: m) {
                        Task { await store.retry(m.clientId) }
                    } discard: {
                        store.discard(m.clientId)
                    }
                }
                if let d = store.dialog {
                    DialogCard(dialog: d, busy: store.answering, base: store.baseURL) { a in
                        Task { await store.answer(a) }
                    }
                    .id(d.sig ?? d.kind)
                    .padding(.top, 14)
                }
                if let w = work, (liveThread?.glyph ?? w.glyph) == "spin" {
                    LiveLine(text: liveThread?.detail ?? w.detail)
                        .padding(.top, 14)
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
        .onChange(of: store.outbox.count + store.waiting.count) { old, new in
            // your own message: always to the bottom
            if new > old { withAnimation(.easeOut(duration: 0.25)) { position.scrollTo(edge: .bottom) } }
        }
        .onChange(of: store.dialog?.sig) { _, sig in
            // Claude asks: its card is the newest thing, at the bottom
            if sig != nil { withAnimation(.easeOut(duration: 0.25)) { position.scrollTo(edge: .bottom) } }
        }
        .onChange(of: store.liveTick) {
            // follow a running turn, unless you scrolled up to read
            if atBottom { withAnimation(.easeOut(duration: 0.25)) { position.scrollTo(edge: .bottom) } }
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Theme.background)
        .overlay {
            if store.isNew && store.temporary && store.outbox.isEmpty && store.waiting.isEmpty {
                TemporaryNote()
            }
        }
        .overlay(alignment: .bottom) {
            if usageOpen && !store.isNew {
                // 5g: the card over a dimmed chat; the box below stays as it is
                ZStack(alignment: .bottom) {
                    Color.black.opacity(0.4)
                        .ignoresSafeArea(edges: .top)
                        .contentShape(Rectangle())
                        .onTapGesture { usageOpen = false }
                        .accessibilityLabel("Close usage")
                        .accessibilityAddTraits(.isButton)
                        .accessibilityIdentifier("closeUsage")
                    UsageCard(usage: usage, now: Date())
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12)
                        .padding(.bottom, 14)
                        .onTapGesture { usageOpen = false }
                }
                .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.18), value: usageOpen)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Composer(store: store, usage: usage, asking: asking, usageOpen: $usageOpen, prompt: composerPrompt)
        }
        .onChange(of: shell?.temporary ?? false, initial: true) { _, on in
            if store.isNew { store.temporary = on }
        }
        .task {
            // 5a: a new chat on the main screen takes the keyboard at once
            if let shell {
                store.onMade = shell.made
                if store.isNew {
                    try? await Task.sleep(nanoseconds: 350_000_000)
                    if !shell.menuIsOpen() { store.focus() }
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        // no bar band (a127): the turns scroll under the floating glass buttons and title pill, softly blurred and
        // faded at the top edge, as in Claude's app
        .toolbarBackgroundVisibility(.hidden, for: .navigationBar)
        // the system's top edge effect fades the turns to solid black across the status bar (a130); it's off, and the
        // dim below lets them show through at the top instead, as in ChatGPT
        .scrollEdgeEffectHidden(true, for: .top)
        .overlay(alignment: .top) { TopDim() }
        .toolbar { toolbar }
        .task(id: "\(phase == .active) \(store.id)") {
            if phase == .active { await store.run() }
        }
        .navigationDestination(for: CardRoute.self) { r in
            CardDetailView(store: store, cardId: r.id)
        }
        .environment(\.messageActions, actions)
        .environment(\.chatPhotos, photoSource)
    }

    /// split from body so the compiler can type-check it
    private func sheets(_ v: some View) -> some View {
        v
            .sheet(isPresented: $showDetails) {
                ChatDetailsSheet(store: store)
            }
            .sheet(item: $selecting) { (s: SelectedText) in SelectTextSheet(text: s.text) }
            .confirmationDialog(store.rewindDialog?.title ?? "Rewind", isPresented: rewindShown,
                                titleVisibility: .visible) {
                ForEach(rewindChoices) { (c: Dialog.Choice) in
                    Button(c.words) { Task { await store.finishRewind(c) } }
                }
                Button("Never mind", role: .cancel) { Task { await store.finishRewind(nil) } }
            } message: {
                Text(rewindNote)
            }
    }

    private var rewindShown: Binding<Bool> {
        let s = store
        return Binding(
            get: { s.rewindDialog != nil },
            set: { (shown: Bool) in if !shown && s.rewindDialog != nil { Task { await s.finishRewind(nil) } } }
        )
    }

    private func alerts(_ v: some View) -> some View {
        v
        .alert("Rename chat", isPresented: $renaming) {
            TextField("Title", text: $newTitle)
                .accessibilityIdentifier("renameField")
            Button("Cancel", role: .cancel) {}
            Button("Rename") { rename() }
        }
        .confirmationDialog("Delete this chat?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                let id = store.id
                Task { if await model.delete(id) { leave() } }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(ChatActions.deleteNote)
        }
        .alert("That didn't work", isPresented: Binding(get: { store.actionError != nil },
                                                       set: { if !$0 { store.actionError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(store.actionError ?? "")
        }
    }

    private var pinned: Bool { store.header?.pinned ?? false }

    /// a thread's first turn: the task card stands for its prompt (the brief), so TurnView leaves the prompt out
    private var briefed: String? {
        guard work != nil, !store.more, let first = store.turns.first, first.kind == "prompt" else { return nil }
        return first.id
    }

    /// the chat's pictures for the photo viewer: open one, swipe through them all (older pages load at the first)
    private var photoSource: PhotoSource {
        let s = store, hidden = briefed
        return PhotoSource(photos: { ChatPhotos.collect(turns: s.turns, briefed: hidden) },
                           more: { s.more },
                           loadOlder: { await s.loadOlder() })
    }

    /// D7's long-press actions and the thread card's answers, for the turns below
    private var actions: MessageActions {
        let s = store
        // these come up as their own sheet or dialog, so the project sheet steps aside first
        let rewind: ((Turn) -> Void)? = s.working || s.rewinding ? nil : { t in
            Task { await s.startRewind(t) }
        }
        return MessageActions(
            rewind: rewind,
            btw: { text in s.put("/btw about \u{201C}\(MessageActions.quote(text))\u{201D}: ") },
            select: { text in selecting = SelectedText(text: text) },
            reply: { text in Task { await s.send(text: text, attachments: []) } }
        )
    }

    /// the confirm page's choices but Never mind (the cancel button)
    private var rewindChoices: [Dialog.Choice] {
        (store.rewindDialog?.choices ?? []).filter { $0.n > 0 && !$0.label.lowercased().hasPrefix("never mind") }
    }

    private var rewindNote: String {
        let q = store.rewindDialog?.question ?? ""
        let t = MessageActions.quote(store.rewindText)
        let notes = (store.rewindDialog?.notes ?? []).joined(separator: " ")
        return [q, t.isEmpty ? "" : "\u{201C}\(t)\u{201D}", notes].filter { !$0.isEmpty }.joined(separator: "\n\n")
    }

    private func rename() {
        let title = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, title != store.header?.title else { return }
        let edit = ChatEdit(title: title)
        store.showEdit(edit)
        let id = store.id
        Task { await model.edit(id, edit) }
    }

    private func pin() {
        let edit = ChatEdit(pinned: !pinned)
        store.showEdit(edit)
        let id = store.id
        Task { await model.edit(id, edit) }
    }

    private func archive() {
        let id = store.id
        Task { if await model.edit(id, ChatEdit(archived: true)) { leave() } }
    }

    /// the chat went away: the main screen gets a new chat, a thread goes back
    private func leave() {
        if let shell { shell.leave() } else { dismiss() }
    }

    /// the rings' meters: the chat's (a new chat: the account's 5-hour and week, from home)
    private var usage: [Meter] {
        Format.chatMeters(store.header, home: model.home?.usage ?? [])
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
            Notice(icon: "exclamationmark.triangle", text: e.isUnreachable ? "Reconnecting\u{2026} " + e.message : e.message)
        } else if store.isNew {
            EmptyView()
        } else if store.header != nil && store.turns.isEmpty {
            if store.waiting.isEmpty && store.outbox.isEmpty {
                Notice(icon: "bubble.left", text: "No messages yet.")
            }
        } else if store.header == nil {
            ProgressView().frame(maxWidth: .infinity).padding(.vertical, 40)
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        if let shell {
            ToolbarItem(placement: .topBarLeading) {
                Button(action: shell.openMenu) {
                    Icons.menu()
                        .foregroundStyle(Theme.rowTitle)
                        .overlay(alignment: .topTrailing) {
                            if shell.menuDot {
                                Circle().fill(Theme.violet).frame(width: 9, height: 9).offset(x: 3, y: -1)
                            }
                        }
                }
                .accessibilityLabel("Menu")
                .accessibilityValue(shell.menuDot ? "Something needs you" : "")
                .accessibilityIdentifier("menu")
            }
        }
        if store.isNew {
            if let shell {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: shell.toggleTemporary) {
                        Icons.temporary(on: shell.temporary).foregroundStyle(Theme.rowTitle)
                    }
                    .accessibilityLabel("Temporary chat")
                    .accessibilityValue(shell.temporary ? "On" : "Off")
                    .accessibilityIdentifier("temporaryChat")
                }
            }
        } else if mainOf != nil || work != nil {
            ToolbarItem(placement: .principal) {
                projectPill
            }
            .sharedBackgroundVisibility(.hidden)
            ToolbarItem(placement: .topBarTrailing) {
                if mainOf != nil { overviewButton } else { threadMenu }
            }
        } else {
            ToolbarItem(placement: .principal) {
                // 5e: just the title; the gauge holds the model. A tap opens the chat's details (D5).
                Button { showDetails = true } label: {
                    // its own width (centred by the bar), cut at 230 pt when long
                    ViewThatFits(in: .horizontal) {
                        titleText.fixedSize()
                        titleText.frame(width: 200)
                    }
                    .frame(maxWidth: 200)
                    .glassPill()
                }
                .buttonStyle(.plain)
                .disabled(store.header == nil)
                .accessibilityLabel(titleLabel)
                .accessibilityIdentifier("chatTitle")
            }
            .sharedBackgroundVisibility(.hidden)
            if let shell {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: shell.newChat) {
                        Image(systemName: "square.and.pencil").foregroundStyle(Theme.rowTitle)
                    }
                    .accessibilityLabel("New chat")
                    .accessibilityIdentifier("compose")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                moreMenu
            }
        }
    }

    /// 05: the project's icon and name, a tap for its settings (11); 07: the thread's state and title, a tap for
    /// its task.
    private var projectPill: some View {
        Button {
            if mainOf != nil { showSettings = true } else { showTask = true }
        } label: {
            HStack(spacing: 10) {
                if let w = work {
                    ThreadMark(glyph: liveThread?.glyph ?? w.glyph, size: 20)
                    Text(w.title)
                } else {
                    let p = store.header?.project
                    ProjectTile(icon: project?.view?.icon ?? p?.icon, color: project?.view?.color ?? p?.color,
                                size: 30, iconSize: 17, radius: 15)
                    Text(project?.view?.name ?? p?.name ?? store.header?.title ?? "")
                }
            }
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(Theme.title)
            .lineLimit(1)
            .frame(maxWidth: 210)
            .glassPill(leading: work == nil ? 7 : 16)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(pillLabel)
        .accessibilityIdentifier(mainOf != nil ? "projectPill" : "threadPill")
    }

    private var pillLabel: String {
        if let w = work { return "\(w.title), \(liveThread?.word ?? w.word ?? w.status)" }
        return "\(project?.view?.name ?? store.header?.project?.name ?? "Project") settings"
    }

    /// 05's Overview button: violet dot while something in the project needs you
    private var overviewButton: some View {
        let needs = (project?.view?.counts.needs ?? 0) > 0 || project?.view?.mainNeeds != nil
        return Button(action: toggleOverview) {
            LucideIcon(name: "list-checks", size: 21)
                .foregroundStyle(Theme.rowTitle)
                .overlay(alignment: .topTrailing) {
                    if needs { Circle().fill(Theme.violet).frame(width: 8, height: 8).offset(x: 3, y: -3) }
                }
        }
        .accessibilityLabel("Overview")
        .accessibilityValue(needs ? "Something needs you" : "")
        .accessibilityIdentifier("overviewButton")
    }

    /// 07's ⋯: the thread's moves
    private var threadMenu: some View {
        let moves = liveThread?.moves ?? work?.moves ?? []
        return Menu {
            Button("Task", systemImage: "target") { showTask = true }
            Section {
                if moves.contains("pause") { Button("Pause", systemImage: "pause") { threadMove("pause") } }
                if moves.contains("resume") { Button("Resume", systemImage: "play") { threadMove("resume") } }
                if moves.contains("done") { Button("Mark done", systemImage: "checkmark") { threadMove("done") } }
                if moves.contains("archive") { Button("Archive", systemImage: "archivebox") { threadMove("archive") } }
                if moves.contains("unarchive") {
                    Button("Unarchive", systemImage: "tray.and.arrow.up") { threadMove("unarchive") }
                }
            }
            if moves.contains("stop") {
                Section {
                    Button("Stop\u{2026}", systemImage: "stop", role: .destructive) { confirmStop = true }
                }
            }
        } label: {
            Image(systemName: "ellipsis").foregroundStyle(Theme.rowTitle)
        }
        .disabled(store.header == nil)
        .accessibilityLabel("More")
        .accessibilityIdentifier("more")
    }

    private var composerPrompt: String? {
        if mainOf != nil { return "Message the main chat" }
        if work != nil { return "Message this thread" }
        return nil
    }

    private var titleText: some View {
        Text(store.header?.title ?? " ")
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(Theme.title)
            .lineLimit(1)
    }

    private var moreMenu: some View {
        Menu {
            Section {
                // slice 8
                Button("Claude's browser", systemImage: "globe") {}.disabled(true)
                Button("Claude's screen", systemImage: "display") {}.disabled(true)
                Button("Your messages", systemImage: "list.bullet") {}.disabled(true)
            }
            if store.editable && !store.temporary {
                Section {
                    Button("Rename", systemImage: "pencil") {
                        newTitle = store.header?.title ?? ""
                        renaming = true
                    }
                    Button(pinned ? "Unpin" : "Pin to top", systemImage: pinned ? "pin.slash" : "pin", action: pin)
                    Button("Archive", systemImage: "archivebox", action: archive)
                }
                Section {
                    Button("Delete\u{2026}", systemImage: "trash", role: .destructive) { confirmDelete = true }
                }
            }
        } label: {
            Image(systemName: "ellipsis").foregroundStyle(Theme.rowTitle)
        }
        .disabled(store.header == nil)
        .accessibilityLabel("More")
        .accessibilityIdentifier("more")
    }

    /// the title for VoiceOver, with what the old second line said: "Main chat · Haiku 5.5", "Opus 5.5 · medium · Bypass"
    private var titleLabel: String {
        guard let h = store.header else { return "Chat" }
        if h.role == "main" { return "\(h.title), Main chat · \(h.model)" }
        let parts = [h.model, h.effort].filter { !$0.isEmpty } + (h.bypass ? ["Bypass"] : [])
        return "\(h.title), \(parts.joined(separator: " · "))"
    }
}

/// 5b: what a temporary chat means, in the middle of the empty chat.
private struct TemporaryNote: View {
    var body: some View {
        VStack(spacing: 0) {
            Text("Temporary chat")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color(hex: 0xECECEC))
            Text("Not saved in your chats. Deleted for good when you leave.")
                .font(.system(size: 15.5))
                .foregroundStyle(Color(hex: 0xB4B4B8))
                .multilineTextAlignment(.center)
                .padding(.top, 4)
            Label("No memory or recall", systemImage: "circle.slash")
                .font(.system(size: 14.5))
                .foregroundStyle(Color(hex: 0x98989F))
                .padding(.top, 16)
        }
        // a set width: the empty chat's scroll view offers the overlay too little room to wrap in
        .frame(width: 310)
        .fixedSize(horizontal: false, vertical: true)
        .allowsHitTesting(false)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("temporaryNote")
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
    /// a thread's first turn: its prompt is the brief, which the task card above stands for (07)
    var briefed = false
    let toggle: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !briefed {
                PromptView(turn: turn, base: base)
                    .environment(\.photoScope, ChatPhotos.promptScope(turn.id))
            }
            if let h = turn.handle {
                HandleRow(handle: h, open: open, turnId: turn.id, toggle: toggle)
                    .padding(.top, 10)
            }
            if lastAnswer == nil { outsideViews }
            ForEach(Array(shown.enumerated()), id: \.offset) { _, item in
                BlockView(block: item.block, base: base)
                    .environment(\.photoScope, ChatPhotos.blockScope(turn.id, item.index))
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
                .messageMenu(text: turn.prompt.text ?? "", turn: turn.rewind == true ? turn : nil)
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
    @Environment(\.chatPhotos) private var photos
    @Environment(\.photoScope) private var scope
    @State private var open: MediaOpen?

    var body: some View {
        VStack(alignment: .trailing, spacing: 6) {
            if let images = prompt.images, !images.isEmpty {
                PhotoGrid {
                    ForEach(Array(images.enumerated()), id: \.offset) { k, link in
                        Button { openPicture(link, at: k) } label: {
                            PhotoTile { RemoteImage(url: MediaLink.url(link, base: base), fill: true) }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Your picture")
                        .accessibilityIdentifier("yourPicture")
                    }
                }
                .padding(.leading, 60)
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
            if let audio = prompt.audio, !audio.isEmpty {
                AudioList(items: audio, base: base, mine: true)
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
        .fullScreenCover(item: $open) { MediaViewer(open: $0, base: base, source: photos) }
    }

    private func openPicture(_ link: String, at k: Int) {
        let item = MDItem(kind: "image", url: link, name: "Your picture")
        open = MediaOpen.picture(item, id: scope.map { ChatPhotos.id(scope: $0, item: k) }, source: photos)
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
                .messageMenu(text: MessageActions.plain(block.md ?? []), turn: nil)
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

// MARK: - a thread's chat (07)

/// 07: what the thread was asked, at the top of its chat; a tap shows all of it with how it's checked.
private struct TaskCard: View {
    let work: ChatHeader.WorkInfo
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 9) {
                    LucideIcon(name: "target", size: 17).foregroundStyle(Color(hex: 0x98989F))
                    Text(work.from == "you" ? "Your task" : "Task from the main chat")
                        .font(.system(size: 15))
                        .foregroundStyle(Color(hex: 0x98989F))
                    Spacer(minLength: 6)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color(hex: 0x6C6C70))
                }
                Text(work.title)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(Theme.title)
                    .padding(.top, 10)
                if !work.outcome.isEmpty {
                    Text(work.outcome)
                        .font(.system(size: 15.5))
                        .foregroundStyle(Color(hex: 0x98989F))
                        .lineSpacing(4)
                        .lineLimit(5)
                        .multilineTextAlignment(.leading)
                        .padding(.top, 6)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(Color(hex: 0x111113), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Color(hex: 0x2C2C2E), lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("taskCard")
    }
}

/// The task in full: its outcome and the checks it's held to.
private struct TaskSheet: View {
    let work: ChatHeader.WorkInfo
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(work.title).font(.system(size: 19, weight: .semibold)).foregroundStyle(Theme.title)
                        Text("\(work.id) \u{00B7} \(work.from == "you" ? "your own thread" : "from the main chat")")
                            .font(.system(size: 15)).foregroundStyle(SheetStyle.label)
                    }
                    .padding(.vertical, 4)
                }
                if !work.outcome.isEmpty {
                    Section {
                        Text(work.outcome).font(.system(size: 17)).foregroundStyle(Theme.rowTitle).textSelection(.enabled)
                    } header: { Text("Outcome").textCase(nil) }
                }
                if !work.criteria.isEmpty {
                    Section {
                        ForEach(Array(work.criteria.enumerated()), id: \.offset) { _, c in
                            HStack(alignment: .firstTextBaseline, spacing: 10) {
                                Image(systemName: "checkmark.circle").foregroundStyle(SheetStyle.label)
                                Text(c).font(.system(size: 16)).foregroundStyle(Theme.rowTitle)
                            }
                        }
                    } header: { Text("How it's checked").textCase(nil) }
                }
            }
            .listRowBackground(SheetStyle.field)
            .scrollContentBackground(.hidden)
            .background(SheetStyle.background)
            .navigationTitle("Task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel("Close")
                        .accessibilityIdentifier("taskClose")
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(SheetStyle.background)
    }
}

/// 07: what the thread is doing now, under its newest turn.
private struct LiveLine: View {
    /// the thread's activity as the server words it ("writing script.js 2m ago")
    let text: String

    var body: some View {
        HStack(spacing: 12) {
            Spinner()
            Text(shown)
                .font(.system(size: 16))
                .foregroundStyle(Theme.rowTitle)
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("liveLine")
    }

    private var shown: String {
        guard let first = text.first else { return "Working" }
        return first.uppercased() + text.dropFirst()
    }
}

// MARK: - outside the fold

private struct OutsideView: View {
    let item: Outside
    @Environment(\.projectThreads) private var live
    @Environment(\.openChat) private var openChat

    var body: some View {
        switch item.type {
        case "ask":
            AskCard(item: item).padding(.top, 12)
        case "threads":
            if live.isEmpty {
                OutsideBox(title: item.title ?? "", meta: "", foldable: false) {
                    ForEach(item.threads ?? [], id: \.id) { t in
                        row(icon: "arrow.triangle.branch", title: "\(t.id) \(t.title)", line: t.model, state: "")
                    }
                }
            } else {
                // 05: one live card per thread it started; a tap opens the thread (07)
                VStack(spacing: 10) {
                    ForEach(item.threads ?? [], id: \.id) { t in
                        ThreadCard(info: t, live: live[t.id]) { id in openChat?(id) }
                    }
                }
                .padding(.top, 12)
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

/// 05: a thread the main chat started, live: ✓ landed, the spinner while working, violet when it needs you.
private struct ThreadCard: View {
    let info: Outside.ThreadInfo
    let live: ThreadItem?
    let open: (String) -> Void

    var body: some View {
        let glyph = live?.glyph ?? "ring"
        let word = live?.word ?? live?.status ?? ""
        Button { if let c = live?.chatId { open(c) } } label: {
            HStack(spacing: 14) {
                ThreadMark(glyph: glyph, size: 24)
                Text(live?.title ?? info.title)
                    .font(.system(size: 17))
                    .foregroundStyle(Theme.rowTitle)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text(word.isEmpty ? info.id : "\(info.id) \u{00B7} \(word)")
                    .font(.system(size: 15))
                    .foregroundStyle(glyph == "spin" ? Theme.blue : glyph == "needs" ? Theme.violet : Color(hex: 0x8E8E93))
                    .lineLimit(1)
                    .layoutPriority(1)
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 56)
            .background(Color(hex: 0x111113), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Color(hex: 0x2C2C2E), lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(live?.chatId == nil)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("threadCard-\(info.id)")
    }
}

/// 05's NEEDS YOU card: the main chat's own question (or a thread's, passed on); a choice answers in this chat,
/// a thread's as `a6: Land it as is`.
private struct AskCard: View {
    let item: Outside
    @Environment(\.messageActions) private var actions
    @State private var sent: String?

    var body: some View {
        let answered = item.answered == true || sent != nil
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                HStack(spacing: 8) {
                    if !answered { Circle().fill(Theme.violet).frame(width: 8, height: 8) }
                    Text(answered ? "ANSWERED" : "NEEDS YOU")
                        .font(.system(size: 13, weight: .semibold))
                        .tracking(0.6)
                        .foregroundStyle(Theme.violetText)
                }
                Spacer()
                Text((item.work ?? "").isEmpty ? "" : [item.work ?? "", Format.shortModel(item.model ?? "")].filter { !$0.isEmpty }.joined(separator: " · "))
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
                        Button {
                            let words = [item.work ?? "", o].filter { !$0.isEmpty }.joined(separator: ": ")
                            sent = o
                            actions.reply(words)
                        } label: {
                            Text(o)
                                .font(.system(size: 16))
                                .foregroundStyle(i == 0 ? .white : ChatStyle.body)
                                .padding(.horizontal, 18)
                                .frame(height: 44)
                                .background(i == 0 ? ChatStyle.bubble : .clear, in: Capsule())
                                .overlay(Capsule().stroke(i == 0 ? ChatStyle.bubble : Color(hex: 0x3A3A40), lineWidth: 1))
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("askOption-\(i)")
                    }
                }
            }
            if let s = sent {
                Text("You answered \u{201C}\(s)\u{201D}")
                    .font(.system(size: 14))
                    .foregroundStyle(ChatStyle.dim)
                    .padding(.top, 8)
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 14)
        .padding(.bottom, 16)
        .background(Color(hex: 0x14121E), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Color(hex: 0x37325A), lineWidth: 1))
        .accessibilityElement(children: .contain)
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

extension View {
    /// the chat title's floating Liquid Glass capsule (a127): 44 pt tall like the round buttons beside it
    func glassPill(leading: CGFloat = 18) -> some View {
        self
            .padding(.leading, leading)
            .padding(.trailing, 18)
            .frame(height: 44)
            .glassEffect(.regular.interactive(), in: .capsule)
            .contentShape(Capsule())
    }
}

/// a130: a soft dark veil over the top of the chat, from the very top of the screen down through the glass buttons:
/// the turns scrolling under the status bar and the Dynamic Island show through dimmed, never as a solid black band,
/// and the status bar's own text stays readable on top of them
struct TopDim: View {
    var body: some View {
        GeometryReader { geo in
            let top = geo.safeAreaInsets.top
            LinearGradient(stops: [
                .init(color: Theme.background.opacity(0.82), location: 0),
                .init(color: Theme.background.opacity(0.66), location: 0.45),
                .init(color: Theme.background.opacity(0.3), location: 0.8),
                .init(color: Theme.background.opacity(0), location: 1),
            ], startPoint: .top, endPoint: .bottom)
                .frame(height: top + 6)
                .offset(y: -top)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
