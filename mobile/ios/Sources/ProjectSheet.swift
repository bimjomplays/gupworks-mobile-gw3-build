import SwiftUI

extension EnvironmentValues {
    /// Pushes a chat on the list's stack (a thread opened from a project's sheet).
    @Entry var openChat: ((String) -> Void)? = nil
}

enum ProjectTab: String, CaseIterable {
    case threads, library, scheduled

    var title: String {
        switch self {
        case .threads: return "Threads"
        case .library: return "Library"
        case .scheduled: return "Scheduled"
        }
    }
}

/// Pushed inside the sheet.
struct NewThreadRoute: Hashable {}
struct ProjectInfoRoute: Hashable {}

/// D9: the project's sheet over its main chat (medium or large): Threads · Library · Scheduled. A thread opens its
/// chat on the list's stack (the sheet closes first); notes and New thread push inside the sheet.
struct ProjectSheet: View {
    let store: ProjectStore
    @Binding var tab: ProjectTab
    @Binding var path: NavigationPath
    @Binding var detent: PresentationDetent
    /// closes the sheet, then opens this chat
    let open: (String) -> Void

    var body: some View {
        NavigationStack(path: $path) {
            VStack(spacing: 0) {
                TabsBar(tab: $tab, threads: store.view?.counts.threads)
                switch tab {
                case .threads: ThreadsTab(store: store, open: open) { path.append(NewThreadRoute()) }
                case .library: LibraryTab(store: store)
                case .scheduled: ScheduledTab(store: store)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: LibraryRow.self) { row in
                if row.kind == "folder" {
                    LibraryFolderView(store: store, row: row)
                } else {
                    NoteView(store: store, row: row)
                }
            }
            .navigationDestination(for: NewThreadRoute.self) { _ in
                NewThreadView(store: store) { path = NavigationPath() }
            }
            .navigationDestination(for: ProjectInfoRoute.self) { _ in
                ProjectInfoView(store: store)
            }
        }
        .presentationDetents([.medium, .large], selection: $detent)
        .presentationDragIndicator(.visible)
        .presentationBackgroundInteraction(.enabled(upThrough: .medium))
        .onChange(of: path.count) { _, n in
            if n > 0 { withAnimation { detent = .large } }
        }
        .alert("That didn't work", isPresented: Binding(get: { store.actionError != nil },
                                                       set: { if !$0 { store.actionError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(store.actionError ?? "")
        }
    }
}

/// Threads 3 · Library · Scheduled, each 44 pt tall, the open one underlined.
private struct TabsBar: View {
    @Binding var tab: ProjectTab
    let threads: Int?

    var body: some View {
        HStack(spacing: 4) {
            ForEach(ProjectTab.allCases, id: \.self) { t in
                Button { tab = t } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        Text(t.title).font(.system(size: 16, weight: .medium))
                        if t == .threads, let n = threads, n > 0 {
                            Text("\(n)").font(.system(size: 13)).foregroundStyle(ChatStyle.dim)
                        }
                    }
                    .foregroundStyle(tab == t ? Theme.title : ChatStyle.dim)
                    .padding(.horizontal, 10)
                    .frame(minHeight: 44)
                    .overlay(alignment: .bottom) {
                        if tab == t { Rectangle().fill(ChatStyle.body).frame(height: 2) }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("tab-\(t.rawValue)")
                .accessibilityAddTraits(tab == t ? .isSelected : [])
            }
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.top, 14)
        .overlay(alignment: .bottom) { Rectangle().fill(ChatStyle.line).frame(height: 0.5) }
    }
}

// MARK: - Threads

private struct ThreadsTab: View {
    let store: ProjectStore
    let open: (String) -> Void
    let newThread: () -> Void
    @State private var unfolded: [String: Bool] = [:]
    @State private var stopping: ThreadItem?

    var body: some View {
        VStack(spacing: 0) {
            if let v = store.view { topLine(v) }
            list
        }
    }

    private var list: some View {
        List {
            if let v = store.view {
                ForEach(v.groups) { g in
                    let isOpen = unfolded[g.state] ?? !g.folded
                    Section {
                        if isOpen {
                            ForEach(g.threads) { t in row(t) }
                        }
                    } header: {
                        GroupHeader(label: g.label, count: g.count, folds: g.folded, open: isOpen) {
                            withAnimation { unfolded[g.state] = !isOpen }
                        }
                    }
                }
                if !v.usage.isEmpty {
                    Section {
                        ForEach(v.usage, id: \.self) { u in UsageRowView(row: u) }
                    } header: {
                        GroupHeader(label: "Usage", count: nil, folds: false, open: true) {}
                    }
                }
            } else if let e = store.error {
                SheetNotice(icon: "exclamationmark.triangle", text: e.message)
            } else {
                ProgressView().frame(maxWidth: .infinity).padding(.vertical, 30).listRowBackground(Color.clear)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .environment(\.defaultMinListRowHeight, 44)
        .refreshable { await store.refresh() }
        .confirmationDialog(stopping.map { "Stop \u{201C}\($0.title)\u{201D}?" } ?? "Stop this thread?",
                            isPresented: Binding(get: { stopping != nil }, set: { if !$0 { stopping = nil } }),
                            titleVisibility: .visible, presenting: stopping) { t in
            Button("Stop", role: .destructive) { Task { await store.move("stop", thread: t.id) } }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("Its Claude stops working on it. The thread stays in the project, so it can be picked up again.")
        }
    }

    /// "◌ 2 working" and + New thread
    private func topLine(_ v: ProjectView) -> some View {
        HStack(spacing: 12) {
            HStack(spacing: 14) {
                ForEach(v.quiet, id: \.self) { q in
                    HStack(spacing: 7) {
                        Glyph(name: q.glyph, size: 13)
                        Text(q.text)
                    }
                }
                if v.quiet.isEmpty {
                    Text(v.paused ? "Project paused" : "Nothing running")
                }
            }
            .font(.system(size: 15))
            .foregroundStyle(ChatStyle.dim)
            .lineLimit(1)
            Spacer(minLength: 4)
            Button(action: newThread) {
                HStack(spacing: 7) {
                    Image(systemName: "plus")
                    Text("New thread")
                }
                .font(.system(size: 15))
                .foregroundStyle(Color(hex: 0xCFCFCF))
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .fixedSize()
            .accessibilityIdentifier("newThread")
        }
        .padding(.leading, 20)
        .padding(.trailing, 14)
        .padding(.top, 4)
    }

    private func row(_ t: ThreadItem) -> some View {
        ThreadRowView(thread: t, busy: store.busy.contains(t.id))
            .contentShape(Rectangle())
            .onTapGesture { if let c = t.chatId { open(c) } }
            .accessibilityAddTraits(t.chatId == nil ? [] : .isButton)
            .accessibilityIdentifier("thread-\(t.id)")
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                // D9: Done at the edge, Pause beside it, Archive further left
                if t.moves.contains("done") {
                    Button { act("done", t) } label: { Label("Done", systemImage: "checkmark") }
                        .tint(Color(hex: 0x3D6A45))
                }
                if t.moves.contains("pause") {
                    Button { act("pause", t) } label: { Label("Pause", systemImage: "pause") }
                        .tint(Color(hex: 0x4A4A4E))
                } else if t.moves.contains("resume") {
                    Button { act("resume", t) } label: { Label("Resume", systemImage: "play") }
                        .tint(Color(hex: 0x2F5FB3))
                }
                if t.moves.contains("archive") {
                    Button { act("archive", t) } label: { Label("Archive", systemImage: "archivebox") }
                        .tint(ChatActions.archiveTint)
                } else if t.moves.contains("unarchive") {
                    Button { act("unarchive", t) } label: { Label("Unarchive", systemImage: "tray.and.arrow.up") }
                        .tint(ChatActions.archiveTint)
                }
            }
            .contextMenu {
                if let c = t.chatId {
                    Button("Open chat", systemImage: "bubble.left") { open(c) }
                }
                Section {
                    if t.moves.contains("pause") { Button("Pause", systemImage: "pause") { act("pause", t) } }
                    if t.moves.contains("resume") { Button("Resume", systemImage: "play") { act("resume", t) } }
                    if t.moves.contains("done") { Button("Mark done", systemImage: "checkmark") { act("done", t) } }
                    if t.moves.contains("archive") { Button("Archive", systemImage: "archivebox") { act("archive", t) } }
                    if t.moves.contains("unarchive") {
                        Button("Unarchive", systemImage: "tray.and.arrow.up") { act("unarchive", t) }
                    }
                }
                if t.moves.contains("stop") {
                    Section {
                        Button("Stop\u{2026}", systemImage: "stop", role: .destructive) { stopping = t }
                    }
                }
            }
    }

    private func act(_ move: String, _ t: ThreadItem) {
        Task { await store.move(move, thread: t.id) }
    }
}

/// "Needs you   1"; a folded group (Done, Archived) has a chevron and opens on tap.
private struct GroupHeader: View {
    let label: String
    let count: Int?
    let folds: Bool
    let open: Bool
    let toggle: () -> Void

    var body: some View {
        if folds {
            Button(action: toggle) { line }
                .buttonStyle(.plain)
                .accessibilityIdentifier("group-\(label)")
        } else {
            line
        }
    }

    private var line: some View {
        HStack(spacing: 4) {
            if folds {
                Image(systemName: open ? "chevron.down" : "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
            }
            Text(label)
            Spacer()
            if let count { Text("\(count)").monospacedDigit() }
        }
        .font(.system(size: 13))
        .foregroundStyle(Theme.section)
        .frame(minHeight: folds ? 44 : 28)
        .contentShape(Rectangle())
        .textCase(nil)
    }
}

/// One thread: its glyph, title and id, model · usage, and what it's doing.
struct ThreadRowView: View {
    let thread: ThreadItem
    var busy = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            Group {
                if busy { ProgressView().controlSize(.small) } else { Glyph(name: thread.glyph, size: 15) }
            }
            .frame(width: 20)
            .alignmentGuide(.firstTextBaseline) { d in d[VerticalAlignment.center] + 5 }
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(thread.title)
                            .font(.system(size: 17, weight: .medium))
                            .foregroundStyle(thread.muted ? ChatStyle.dim : Theme.rowTitle)
                            .lineLimit(1)
                        Text(thread.id).font(.system(size: 13)).foregroundStyle(ChatStyle.dim)
                    }
                    .layoutPriority(1)
                    Spacer(minLength: 4)
                    rightText.font(.system(size: 13)).lineLimit(1)
                }
                if !detail.isEmpty {
                    Text(detail)
                        .font(.system(size: 15))
                        .foregroundStyle(ChatStyle.dim)
                        .lineLimit(2)
                }
            }
        }
        .padding(.vertical, 6)
        .listRowInsets(EdgeInsets(top: 4, leading: 20, bottom: 4, trailing: 20))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .accessibilityElement(children: .combine)
    }

    private var detail: String {
        let holds = thread.holds.isEmpty ? "" : "holds " + thread.holds.joined(separator: ", ")
        return [thread.detail, holds].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    /// "Sonnet · 167K"; a thread that used much more than the usual one has its number in amber
    private var rightText: Text {
        let model = Text(thread.right).foregroundStyle(ChatStyle.dim)
        guard !thread.usage.isEmpty else { return model }
        let used = Text(thread.usage).foregroundStyle(thread.expensive ? Theme.amber : ChatStyle.dim)
        return thread.right.isEmpty ? used : Text("\(model)\(Text(" · ").foregroundStyle(ChatStyle.dim))\(used)")
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

private struct UsageRowView: View {
    let row: ProjectView.UsageRow

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(row.title).font(.system(size: 16)).foregroundStyle(Theme.rowTitle).lineLimit(1)
                Text(row.detail).font(.system(size: 13))
                    .foregroundStyle(row.expensive ? Theme.amber : ChatStyle.dim)
                    .lineLimit(2)
            }
            Spacer()
            Text(row.value).font(.system(size: 15)).foregroundStyle(row.expensive ? Theme.amber : ChatStyle.dim)
        }
        .padding(.vertical, 4)
        .listRowInsets(EdgeInsets(top: 4, leading: 20, bottom: 4, trailing: 20))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .accessibilityElement(children: .combine)
    }
}

private struct SheetNotice: View {
    let icon: String
    let text: String

    var body: some View {
        Label(text, systemImage: icon)
            .font(.subheadline)
            .foregroundStyle(ChatStyle.dim)
            .padding(.vertical, 20)
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
    }
}

// MARK: - New thread

/// The panel's + New thread: your own thread in the project, started with this message.
private struct NewThreadView: View {
    let store: ProjectStore
    let done: () -> Void
    @State private var text = ""
    @State private var starting = false
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("A thread of your own in \(store.view?.name ?? "the project"). It starts with this message, in "
                 + "its own folder, like + New thread on the PC.")
                .font(.system(size: 15))
                .foregroundStyle(ChatStyle.dim)
            TextEditor(text: $text)
                .font(.system(size: 17))
                .scrollContentBackground(.hidden)
                .padding(10)
                .background(ChatStyle.cardBG, in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(ChatStyle.cardBorder))
                .overlay(alignment: .topLeading) {
                    if text.isEmpty {
                        Text("What should it do?")
                            .font(.system(size: 17))
                            .foregroundStyle(ChatStyle.faint)
                            .padding(.horizontal, 15)
                            .padding(.vertical, 18)
                            .allowsHitTesting(false)
                    }
                }
                .focused($focused)
                .accessibilityIdentifier("newThreadText")
        }
        .padding(20)
        .navigationTitle("New thread")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    starting = true
                    Task {
                        if await store.newThread(text) { done() }
                        starting = false
                    }
                } label: {
                    if starting { ProgressView() } else { Text("Start") }
                }
                .buttonStyle(.glassProminent)
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || starting)
                .accessibilityIdentifier("startThread")
            }
        }
        .onAppear { focused = true }
    }
}

// MARK: - Project info

private struct ProjectInfoView: View {
    let store: ProjectStore

    var body: some View {
        List {
            ForEach(store.view?.info ?? [], id: \.self) { r in
                VStack(alignment: .leading, spacing: 3) {
                    Text(r.label).font(.system(size: 13)).foregroundStyle(Theme.section)
                    Text(r.value).font(.system(size: 16)).foregroundStyle(Theme.rowTitle).textSelection(.enabled)
                }
                .padding(.vertical, 4)
                .listRowBackground(Color.clear)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .navigationTitle(store.view?.name ?? "Project")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Scheduled

private struct ScheduledTab: View {
    let store: ProjectStore

    var body: some View {
        List {
            if let s = store.schedules {
                ForEach(s.groups) { g in
                    Section {
                        ForEach(g.items) { r in ScheduleRowView(row: r) }
                    } header: {
                        GroupHeader(label: g.label, count: g.count, folds: false, open: true) {}
                    }
                }
                if s.groups.isEmpty {
                    SheetNotice(icon: "clock", text: "Nothing scheduled. The main chat sets up runs when you ask it.")
                }
                Text(s.footer)
                    .font(.system(size: 13))
                    .foregroundStyle(ChatStyle.faint)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .padding(.top, 8)
            } else {
                ProgressView().frame(maxWidth: .infinity).padding(.vertical, 30).listRowBackground(Color.clear)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .refreshable { await store.loadSchedules() }
        .task { await store.loadSchedules() }
    }
}

private struct ScheduleRowView: View {
    let row: ScheduleRow

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            Image(systemName: row.running ? "play.circle" : row.paused ? "pause.circle" : "clock")
                .font(.system(size: 15))
                .foregroundStyle(row.running ? Theme.blue : ChatStyle.dim)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline) {
                    Text(row.title).font(.system(size: 17, weight: .medium))
                        .foregroundStyle(row.paused ? ChatStyle.dim : Theme.rowTitle)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Text(row.right).font(.system(size: 13)).foregroundStyle(ChatStyle.dim)
                }
                Text(row.when).font(.system(size: 15)).foregroundStyle(ChatStyle.dim).lineLimit(1)
                if !row.last.isEmpty {
                    Text(row.last).font(.system(size: 13))
                        .foregroundStyle(row.lastStatus == "failed" ? ChatStyle.failed : ChatStyle.faint)
                        .lineLimit(2)
                }
            }
        }
        .padding(.vertical, 6)
        .listRowInsets(EdgeInsets(top: 4, leading: 20, bottom: 4, trailing: 20))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .accessibilityElement(children: .combine)
    }
}
