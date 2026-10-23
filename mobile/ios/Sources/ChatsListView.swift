import SwiftUI

/// D1: one list, no tab bar. Settings up top; search and New chat in the bottom toolbar where the thumb is.
/// Rows open their chat (a project its main chat). A chat row swipes right to Pin, left to Archive · Delete, and
/// long-presses for Rename and the rest. New project comes with a later slice.
struct ChatsListView: View {
    @Environment(AppModel.self) private var model
    @State private var query = ""
    @State private var showSettings = false
    @State private var path = NavigationPath()  // chats, then step cards inside them
    @State private var renaming: ChatRow?
    @State private var newTitle = ""
    @State private var deleting: ChatRow?

    var body: some View {
        NavigationStack(path: $path) {
            List {
                if let error = model.error {
                    ErrorBanner(error: error)
                }
                if let home = model.home {
                    content(home)
                } else if model.error == nil {
                    loadingRow
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle("Chats")
            .navigationBarTitleDisplayMode(.large)
            .refreshable { await model.refresh() }
            .searchable(text: $query, prompt: "Search")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showSettings = true } label: {
                        Image(systemName: "gearshape").foregroundStyle(Theme.rowTitle)
                    }
                        .accessibilityLabel("Settings")
                        .accessibilityIdentifier("settings")
                }
                DefaultToolbarItem(kind: .search, placement: .bottomBar)
                ToolbarSpacer(.fixed, placement: .bottomBar)
                ToolbarItem(placement: .bottomBar) {
                    Button { path.append(NewChatRoute()) } label: {
                        Image(systemName: "square.and.pencil").foregroundStyle(Theme.rowTitle)
                    }
                        .accessibilityLabel("New chat")
                        .accessibilityIdentifier("newChat")
                }
            }
            .sheet(isPresented: $showSettings) { SettingsView() }
            .task {
                // the demo's `-open <chat id>` (screenshot tests): straight into a chat the list doesn't show
                let args = ProcessInfo.processInfo.arguments
                if model.demo, path.isEmpty, let i = args.firstIndex(of: "-open"), i + 1 < args.count {
                    path.append(ChatRoute(id: args[i + 1]))
                }
            }
            .navigationDestination(for: ChatRoute.self) { r in
                ChatView(id: r.id, pairing: model.pairing, demo: model.demo)
            }
            .navigationDestination(for: NewChatRoute.self) { _ in
                ChatView(id: nil, pairing: model.pairing, demo: model.demo)
            }
            .alert("Rename chat", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } }),
                   presenting: renaming) { c in
                TextField("Title", text: $newTitle)
                    .accessibilityIdentifier("renameField")
                Button("Cancel", role: .cancel) {}
                Button("Rename") {
                    let title = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !title.isEmpty && title != c.title { Task { await model.edit(c.id, ChatEdit(title: title)) } }
                }
            }
            .confirmationDialog(deleting.map { "Delete \u{201C}\($0.title)\u{201D}?" } ?? "Delete this chat?",
                                isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                                titleVisibility: .visible, presenting: deleting) { c in
                Button("Delete", role: .destructive) { Task { await model.delete(c.id) } }
                Button("Cancel", role: .cancel) {}
            } message: { _ in
                Text(ChatActions.deleteNote)
            }
        }
        .alert("That didn't work", isPresented: Binding(get: { model.actionError != nil },
                                                       set: { if !$0 { model.actionError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.actionError ?? "")
        }
    }

    private func startRename(_ c: ChatRow) {
        newTitle = c.title
        renaming = c
    }

    private func pin(_ c: ChatRow) {
        Task { await model.edit(c.id, ChatEdit(pinned: !c.pinned)) }
    }

    private func archive(_ c: ChatRow) {
        Task { await model.edit(c.id, ChatEdit(archived: true)) }
    }

    @ViewBuilder
    private func content(_ home: Home) -> some View {
        let q = query.trimmingCharacters(in: .whitespaces)
        let projects = home.projects.filter { matches($0.name, q) }
        let chats = (home.setups + home.chats).filter { matches($0.title, q) }
        let now = Date(timeIntervalSince1970: home.now / 1000)

        if q.isEmpty || !projects.isEmpty {
            Section {
                ForEach(projects) { p in
                    ProjectRowView(project: p)
                        .onTapGesture { if let id = p.mainChatId { path.append(ChatRoute(id: id)) } }
                        .accessibilityAddTraits(p.mainChatId == nil ? [] : .isButton)
                }
                if projects.isEmpty {
                    emptyRow(home.projectsError.map { "Projects can't be read right now (\($0))." } ?? "No projects yet.")
                }
            } header: {
                SectionHeader(title: "Projects") {
                    Button {} label: { Image(systemName: "folder.badge.plus") }
                        .disabled(true)  // a later slice
                        .accessibilityLabel("New project")
                }
            }
        }
        if q.isEmpty || !chats.isEmpty {
            Section {
                ForEach(chats) { c in
                    ChatRowView(chat: c, now: now)
                        .onTapGesture { path.append(ChatRoute(id: c.id)) }
                        .accessibilityAddTraits(.isButton)
                        .swipeActions(edge: .leading, allowsFullSwipe: true) {
                            Button { pin(c) } label: {
                                Label(c.pinned ? "Unpin" : "Pin", systemImage: c.pinned ? "pin.slash" : "pin")
                            }
                            .tint(ChatActions.pinTint)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            // Delete asks first, so no role here (that would take the row out at once)
                            Button { deleting = c } label: { Label("Delete", systemImage: "trash") }
                                .tint(ChatActions.deleteTint)
                            Button { archive(c) } label: { Label("Archive", systemImage: "archivebox") }
                                .tint(ChatActions.archiveTint)
                        }
                        .contextMenu {
                            Section {
                                Button("Rename", systemImage: "pencil") { startRename(c) }
                                Button(c.pinned ? "Unpin" : "Pin to top", systemImage: c.pinned ? "pin.slash" : "pin") {
                                    pin(c)
                                }
                                Button("Archive", systemImage: "archivebox") { archive(c) }
                            }
                            Section {
                                Button("Delete\u{2026}", systemImage: "trash", role: .destructive) { deleting = c }
                            }
                        }
                }
                if chats.isEmpty {
                    emptyRow("Every chat is in a project.")
                }
            } header: {
                SectionHeader(title: "Chats") { EmptyView() }
            }
        }
        if !q.isEmpty && projects.isEmpty && chats.isEmpty {
            emptyRow("Nothing called \u{201C}\(q)\u{201D}.")
        }
    }

    private func matches(_ text: String, _ q: String) -> Bool {
        q.isEmpty || text.localizedStandardContains(q)
    }

    private var loadingRow: some View {
        HStack {
            Spacer()
            ProgressView()
            Spacer()
        }
        .padding(.vertical, 40)
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    private func emptyRow(_ text: String) -> some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(Theme.secondary)
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
    }
}

/// A chat pushed on the list's stack.
struct ChatRoute: Hashable {
    let id: String
}

/// What the list's swipes and long-press and a chat's ⋯ menu share.
enum ChatActions {
    static let pinTint = Color(hex: 0x2F5FB3)      // the D1 swipe's blue
    static let archiveTint = Color(hex: 0x5A5A63)
    static let deleteTint = Color(hex: 0xD9534F)
    static let deleteNote = "It leaves your chats on the PC too and its Claude stops. The PC keeps the transcript, "
        + "so the chat can be brought back there."
}

private struct SectionHeader<Trailing: View>: View {
    let title: String
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(Theme.section)
            Spacer()
            trailing()
                .font(.title3)
                .foregroundStyle(Theme.rowTitle)
                .frame(minWidth: 44, minHeight: 44, alignment: .trailing)
        }
        .textCase(nil)
    }
}

struct ProjectRowView: View {
    let project: ProjectRow

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: "folder")
                .font(.title3)
                .foregroundStyle(Theme.icon)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text(project.name)
                    .font(.body)
                    .foregroundStyle(Theme.rowTitle)
                    .lineLimit(1)
                StateLine(word: stateWord, color: stateColor, rest: project.detail)
            }
            Spacer(minLength: 8)
            badge
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .accessibilityElement(children: .combine)
    }

    private var stateWord: String? {
        switch project.state {
        case "needs": return "Needs you"
        case "permission": return "Waiting for permission"
        case "working": return "Working"
        case "paused": return "Paused"
        default: return nil
        }
    }

    private var stateColor: Color {
        switch project.state {
        case "needs": return Theme.violetText
        case "permission": return Theme.amber
        default: return Theme.secondary
        }
    }

    @ViewBuilder
    private var badge: some View {
        if project.state == "permission" {
            CountBadge(count: max(project.permission, 1)) { Dot(color: Theme.amber) }
        } else if project.working > 0 {
            CountBadge(count: project.working) { Spinner() }
        } else if project.needs > 0 {
            CountBadge(count: project.needs) { Dot(color: Theme.violet) }
        } else if project.paused {
            Image(systemName: "pause.circle").foregroundStyle(Theme.secondary)
        }
    }
}

struct ChatRowView: View {
    let chat: ChatRow
    let now: Date

    var body: some View {
        HStack(spacing: 16) {
            indicator.frame(width: 28)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(chat.title)
                        .font(.body)
                        .foregroundStyle(Theme.rowTitle)
                        .lineLimit(1)
                    if chat.pinned {
                        Image(systemName: "pin.fill").font(.caption2).foregroundStyle(Theme.secondary)
                    }
                }
                StateLine(word: stateWord, color: stateColor, rest: subtitle)
            }
            Spacer(minLength: 8)
            Text(chat.state == "working" ? "now" : Format.time(chat.lastActive, now: now))
                .font(.subheadline)
                .foregroundStyle(Theme.time)
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .accessibilityElement(children: .combine)
    }

    private var stateWord: String? {
        switch chat.state {
        case "working": return "Working"
        case "needs": return "Needs you"
        case "permission": return "Waiting for permission"
        default: return nil
        }
    }

    private var stateColor: Color {
        switch chat.state {
        case "needs": return Theme.violetText
        case "permission": return Theme.amber
        default: return Theme.secondary
        }
    }

    /// "Opus 5.5 · Claude"; with a state word in front only the model, so the line stays short.
    private var subtitle: String {
        if stateWord != nil { return chat.model }
        return [chat.model, chat.provider].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    @ViewBuilder
    private var indicator: some View {
        switch chat.state {
        case "working": Spinner()
        case "needs": Dot(color: Theme.violet)
        case "permission": Dot(color: Theme.amber)
        default: Dot(color: Theme.idleDot)
        }
    }
}

/// "Needs you · Mockups: pick a look": the state word in its colour, the rest grey.
private struct StateLine: View {
    let word: String?
    let color: Color
    let rest: String

    var body: some View {
        let parts: Text = {
            switch (word, rest.isEmpty) {
            case let (w?, true): return Text(w).foregroundStyle(color)
            case let (w?, false): return Text("\(Text(w).foregroundStyle(color)) · \(rest)").foregroundStyle(Theme.secondary)
            case (nil, _): return Text(rest).foregroundStyle(Theme.secondary)
            }
        }()
        parts.font(.subheadline).lineLimit(1)
    }
}

private struct CountBadge<Icon: View>: View {
    let count: Int
    @ViewBuilder var icon: () -> Icon

    var body: some View {
        HStack(spacing: 8) {
            icon()
            Text("\(count)").font(.subheadline).foregroundStyle(Theme.secondary).monospacedDigit()
        }
    }
}

private struct Dot: View {
    let color: Color
    var body: some View { Circle().fill(color).frame(width: 8, height: 8) }
}

/// A thin ring with a moving arc, like the desktop's working spinner.
struct Spinner: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            ZStack {
                Circle().stroke(Theme.blue.opacity(0.25), lineWidth: 2)
                Circle()
                    .trim(from: 0, to: 0.3)
                    .stroke(Theme.blue, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .rotationEffect(.degrees(t.truncatingRemainder(dividingBy: 1) * 360))
            }
            .frame(width: 16, height: 16)
        }
        .accessibilityLabel("Working")
    }
}

private struct ErrorBanner: View {
    @Environment(AppModel.self) private var model
    let error: APIError

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(error.message, systemImage: "exclamationmark.triangle")
                .font(.subheadline)
                .foregroundStyle(Theme.red)
            if error == .notPaired {
                Button("Pair again") { model.unpair() }
                    .buttonStyle(.glass)
            }
        }
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }
}
