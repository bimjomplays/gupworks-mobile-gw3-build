import SwiftUI

/// D1: one list, no tab bar. Settings up top; search and New chat in the bottom toolbar where the thumb is.
/// Slice 1 is read-only: rows don't open yet, New chat and New project are shown but off.
struct ChatsListView: View {
    @Environment(AppModel.self) private var model
    @State private var query = ""
    @State private var showSettings = false

    var body: some View {
        NavigationStack {
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
                    Button { showSettings = true } label: { Image(systemName: "gearshape") }
                        .accessibilityLabel("Settings")
                        .accessibilityIdentifier("settings")
                }
                DefaultToolbarItem(kind: .search, placement: .bottomBar)
                ToolbarSpacer(.fixed, placement: .bottomBar)
                ToolbarItem(placement: .bottomBar) {
                    Button {} label: { Image(systemName: "square.and.pencil") }
                        .disabled(true)  // slice 3
                        .accessibilityLabel("New chat")
                }
            }
            .sheet(isPresented: $showSettings) { SettingsView() }
        }
    }

    @ViewBuilder
    private func content(_ home: Home) -> some View {
        let q = query.trimmingCharacters(in: .whitespaces)
        let projects = home.projects.filter { matches($0.name, q) }
        let chats = (home.setups + home.chats).filter { matches($0.title, q) }
        let now = Date(timeIntervalSince1970: home.now / 1000)

        if q.isEmpty || !projects.isEmpty {
            Section {
                ForEach(projects) { ProjectRowView(project: $0) }
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
                ForEach(chats) { ChatRowView(chat: $0, now: now) }
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
