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
    // slice 6: a project's main chat has the D9 sheet (threads, Library, Scheduled)
    @State private var project: ProjectStore?
    @State private var showProject = false
    @State private var projectDetent: PresentationDetent = .medium
    @State private var projectTab: ProjectTab = .threads
    @State private var projectPath = NavigationPath()
    @State private var pendingChat: String?
    @State private var opensSheet: Bool
    @State private var confirmArchiveProject = false
    @Environment(\.openChat) private var openChat
    @Environment(\.scenePhase) private var phase
    @Environment(\.dismiss) private var dismiss
    @Environment(AppModel.self) private var model

    /// `projectSheet`: a project's main chat opened from the list shows its threads sheet at once (D9)
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

    /// split from body so the compiler can type-check it
    private func projectParts(_ v: some View) -> some View {
        v
            .onChange(of: mainOf, initial: true) { _, pid in
                guard let pid else { return }
                if project?.id != pid { project = ProjectStore(id: pid, pairing: model.pairing, demo: model.demo) }
                if opensSheet {
                    opensSheet = false
                    projectDetent = .medium
                    showProject = true
                }
            }
            .task(id: "\(phase == .active) \(project?.id ?? "")") {
                if phase == .active, let project { await project.follow() }
            }
            .sheet(isPresented: $showProject, onDismiss: {
                if let id = pendingChat {
                    pendingChat = nil
                    openChat?(id)
                }
            }) {
                if let project {
                    ProjectSheet(store: project, tab: $projectTab, path: $projectPath, detent: $projectDetent) { id in
                        pendingChat = id
                        showProject = false
                    }
                }
            }
            .confirmationDialog("Archive \u{201C}\(project?.view?.name ?? "this project")\u{201D}?",
                                isPresented: $confirmArchiveProject, titleVisibility: .visible) {
                Button("Archive", role: .destructive) {
                    guard let project else { return }
                    Task { if await project.setArchived(true) { leave() } }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("It leaves your projects on the PC and the phone; its threads stop. It can be brought back from "
                     + "the PC's archive.")
            }
            .alert("That didn't work", isPresented: Binding(get: { !showProject && project?.actionError != nil },
                                                           set: { if !$0 { project?.actionError = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(project?.actionError ?? "")
            }
    }

    /// The sheet closes first when something else is shown (one sheet at a time).
    private func overSheet(_ show: @escaping () -> Void) {
        guard showProject else { return show() }
        showProject = false
        Task {
            try? await Task.sleep(nanoseconds: 450_000_000)
            show()
        }
    }

    /// The Threads button: the sheet at full height (D9), or closed when it's already there.
    private func toggleThreads() {
        if showProject && projectDetent == .large {
            showProject = false
        } else {
            projectTab = .threads
            projectPath = NavigationPath()
            projectDetent = .large
            showProject = true
        }
    }

    private func showProjectInfo() {
        projectPath = NavigationPath([ProjectInfoRoute()])
        projectDetent = .large
        showProject = true
    }

    private var chat: some View {
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
                ForEach(store.queue) { q in
                    QueuedBubble(item: q, base: store.baseURL).padding(.top, 14)
                }
                ForEach(store.outbox) { m in
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
                footer
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 12)
            // the column is the screen's width, whatever is in it: something too wide can't widen the chat and push
            // the box and its send button off screen
            .containerRelativeFrame(.horizontal)
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
        .onChange(of: store.outbox.count + store.queue.count) { old, new in
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
            if store.isNew && store.temporary && store.outbox.isEmpty && store.queue.isEmpty {
                TemporaryNote()
            }
        }
        .overlay(alignment: .bottom) {
            if usageOpen {
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
            Composer(store: store, usage: usage, asking: asking, usageOpen: $usageOpen)
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
        // a solid bar under the title, as in D2: turns scroll under it instead of showing through
        .toolbarBackground(Theme.background, for: .navigationBar)
        .toolbarBackgroundVisibility(.visible, for: .navigationBar)
        .toolbar { toolbar }
        .task(id: "\(phase == .active) \(store.id)") {
            if phase == .active { await store.run() }
        }
        .navigationDestination(for: CardRoute.self) { r in
            CardDetailView(store: store, cardId: r.id)
        }
        .environment(\.messageActions, actions)
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

    /// D7's long-press actions and the thread card's answers, for the turns below
    private var actions: MessageActions {
        let s = store
        // these come up as their own sheet or dialog, so the project sheet steps aside first
        let rewind: ((Turn) -> Void)? = s.working || s.rewinding ? nil : { t in
            overSheet { Task { await s.startRewind(t) } }
        }
        return MessageActions(
            rewind: rewind,
            btw: { text in s.put("/btw about \u{201C}\(MessageActions.quote(text))\u{201D}: ") },
            select: { text in overSheet { selecting = SelectedText(text: text) } },
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
        var u = store.header?.usage ?? []
        for m in model.home?.usage ?? [] where !u.contains(where: { $0.label == m.label }) { u.append(m) }
        return u
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
            if store.queue.isEmpty && store.outbox.isEmpty {
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
        } else {
            ToolbarItem(placement: .principal) {
                // 5e: just the title; the gauge holds the model. A tap opens the chat's details (D5).
                Button { overSheet { showDetails = true } } label: {
                    // its own width (centred by the bar), cut at 230 pt when long
                    ViewThatFits(in: .horizontal) {
                        titleText.fixedSize()
                        titleText.frame(width: 230)
                    }
                    .frame(maxWidth: 230)
                }
                .buttonStyle(.plain)
                .disabled(store.header == nil)
                .accessibilityLabel(titleLabel)
                .accessibilityIdentifier("chatTitle")
            }
            .sharedBackgroundVisibility(.hidden)
            if let project {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: toggleThreads) {
                        Image(systemName: "sidebar.left")
                            .foregroundStyle(Theme.rowTitle)
                            .overlay(alignment: .topTrailing) {
                                if let n = project.view?.counts.threads, n > 0 {
                                    Text("\(n)")
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 5)
                                        .frame(minWidth: 17, minHeight: 17)
                                        .background(Color(hex: 0x2F5FB3), in: Capsule())
                                        .offset(x: 10, y: -9)
                                }
                            }
                    }
                    .accessibilityLabel("Threads")
                    .accessibilityValue(project.view.map { Format.plural($0.counts.threads, "thread") } ?? "")
                    .accessibilityIdentifier("threadsButton")
                }
            }
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

    private var titleText: some View {
        Text(store.header?.title ?? " ")
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(Theme.title)
            .lineLimit(1)
    }

    private var moreMenu: some View {
        Menu {
            if let v = project?.view, let pid = project?.id {
                Section(v.name) {
                    Button("Project info", systemImage: "info.circle", action: showProjectInfo)
                    let pinnedProject = model.isPinned(project: pid)
                    Button(pinnedProject ? "Unpin" : "Pin", systemImage: pinnedProject ? "pin.slash" : "pin") {
                        Task { await model.togglePin(project: pid) }
                    }
                    Button(v.paused ? "Resume project" : "Pause project",
                           systemImage: v.paused ? "play" : "pause") {
                        Task { await project?.setPaused(!v.paused) }
                    }
                    Button("Archive project\u{2026}", systemImage: "archivebox") {
                        overSheet { confirmArchiveProject = true }
                    }
                }
            }
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
    @State private var open: MDItem?

    var body: some View {
        VStack(alignment: .trailing, spacing: 6) {
            if let images = prompt.images, !images.isEmpty {
                PhotoGrid {
                    ForEach(Array(images.enumerated()), id: \.offset) { _, link in
                        Button { open = MDItem(kind: "image", url: link, name: "Your picture") } label: {
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

/// D11's "THREAD NEEDS YOU" card: a choice answers in this chat as `a6: Land it as is`, which the main chat passes on.
private struct AskCard: View {
    let item: Outside
    @Environment(\.messageActions) private var actions
    @State private var sent: String?

    var body: some View {
        let answered = item.answered == true || sent != nil
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
                        Button {
                            let words = [item.work ?? "", o].filter { !$0.isEmpty }.joined(separator: ": ")
                            sent = o
                            actions.reply(words)
                        } label: {
                            Text(o)
                                .font(.system(size: 16))
                                .foregroundStyle(i == 0 ? .white : ChatStyle.body)
                                .padding(.horizontal, 16)
                                .frame(height: 44)
                                .background(i == 0 ? ChatStyle.bubble : .clear, in: RoundedRectangle(cornerRadius: 12))
                                .overlay(RoundedRectangle(cornerRadius: 12).stroke(i == 0 ? ChatStyle.bubble : Color(hex: 0x34343A), lineWidth: 1))
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
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 14)
        .background(Color(hex: 0x17151D), in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(answered ? Color(hex: 0x3A3358) : Theme.blue.opacity(0.75), lineWidth: answered ? 1 : 2)
        )
        .shadow(color: answered ? .clear : Theme.blue.opacity(0.25), radius: 12)
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
