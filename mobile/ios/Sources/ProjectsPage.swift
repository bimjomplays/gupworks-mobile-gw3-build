import SwiftUI

/// What the Projects page lists (02's filter).
enum ProjectFilter: String, CaseIterable {
    case pinned, all, archived
}

/// 01-02: every project newest first, its icon, and what it's doing under its name; the filter (Pinned, All,
/// Archived, folders), search, and New project. A tap opens the project's main chat (05); long-press for Pin,
/// Settings, Archive.
struct ProjectsPage: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openChat) private var openChat
    /// the slide-out menu, as on every page
    let openMenu: () -> Void
    @AppStorage("projectsFilter") private var filterRaw = ProjectFilter.all.rawValue
    @AppStorage("projectsShowFolders") private var showFolders = false
    @State private var filterOpen: Bool
    @State private var openFolders: [String: Bool] = [:]
    @State private var searching = false
    @State private var query = ""
    @State private var hits: [ProjectHit] = []
    @State private var newProject: Bool
    @State private var settingsFor: String?
    @FocusState private var searchFocused: Bool

    init(openMenu: @escaping () -> Void) {
        self.openMenu = openMenu
        let args = Demo.args
        _filterOpen = State(initialValue: Demo.isOn && args.contains("-filter"))
        _newProject = State(initialValue: Demo.isOn && args.contains("-newProject"))
    }

    private var filter: ProjectFilter { ProjectFilter(rawValue: filterRaw) ?? .all }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            ZStack(alignment: .top) {
                list
                    .opacity(filterOpen ? 0.55 : 1)
                    .allowsHitTesting(!filterOpen)
            }
        }
        .overlay(alignment: .topTrailing) {
            if filterOpen {
                Color.black.opacity(0.001)
                    .ignoresSafeArea()
                    .onTapGesture { withAnimation(.snappy(duration: 0.2)) { filterOpen = false } }
                    .accessibilityLabel("Close the filter")
                    .accessibilityIdentifier("closeFilter")
                filterMenu
                    .padding(.trailing, 12)
                    .padding(.top, -2)
                    .transition(.scale(scale: 0.85, anchor: .topTrailing).combined(with: .opacity))
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { bottomBar }
        .background(Theme.background)
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $newProject) {
            NewProjectSheet { reply in
                // after the sheet has gone: one sheet at a time
                Task {
                    try? await Task.sleep(nanoseconds: 450_000_000)
                    if let id = reply.mainChatId { openChat?(id) } else { settingsFor = reply.projectId }
                }
            }
        }
        .sheet(item: Binding(get: { settingsFor.map(SheetID.init) }, set: { settingsFor = $0?.id })) { s in
            ProjectSettingsSheet(projectId: s.id)
        }
        .task(id: query) {
            let q = query.trimmingCharacters(in: .whitespaces)
            guard searching, q.count >= 2 else { hits = []; return }
            try? await Task.sleep(nanoseconds: 300_000_000)
            if Task.isCancelled { return }
            hits = await model.searchProjects(q)
        }
    }

    // MARK: top and bottom

    private var topBar: some View {
        HStack {
            RoundButton(label: "Menu", id: "menu", action: openMenu) {
                Icons.menu().foregroundStyle(Theme.rowTitle)
            }
            .overlay(alignment: .topTrailing) {
                if model.needsYou {
                    Circle().fill(Theme.violet).frame(width: 9, height: 9)
                        .overlay(Circle().stroke(Color(hex: 0x161616), lineWidth: 2))
                        .offset(x: -8, y: 9)
                }
            }
            Spacer(minLength: 8)
            Text(searching ? "Search" : filterTitle)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Theme.title)
                .lineLimit(1)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            RoundButton(label: "Filter", id: "projectFilter",
                        action: { withAnimation(.snappy(duration: 0.2)) { filterOpen.toggle() } }) {
                LucideIcon(name: "sliders-vertical", size: 21).foregroundStyle(Theme.rowTitle)
            }
            .accessibilityValue(filterTitle)
            .opacity(filterOpen ? 0 : 1)
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
        .padding(.bottom, 10)
    }

    private var filterTitle: String {
        switch filter {
        case .pinned: return "Pinned"
        case .all: return "Projects"
        case .archived: return "Archived"
        }
    }

    @ViewBuilder
    private var bottomBar: some View {
        HStack(spacing: 12) {
            if searching {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass").font(.system(size: 17)).foregroundStyle(SheetStyle.optional)
                    TextField("Search projects", text: $query)
                        .font(.system(size: 17))
                        .foregroundStyle(Theme.rowTitle)
                        .focused($searchFocused)
                        .submitLabel(.search)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("projectSearch")
                }
                .padding(.horizontal, 16)
                .frame(height: 48)
                .background(Color(hex: 0x161616), in: Capsule())
                .overlay(Capsule().stroke(Color(hex: 0x262626), lineWidth: 1))
                RoundButton(label: "Close search", id: "closeSearch", size: 48) {
                    withAnimation(.snappy(duration: 0.25)) {
                        searching = false
                        query = ""
                        hits = []
                    }
                } label: {
                    Image(systemName: "xmark").font(.system(size: 17, weight: .semibold)).foregroundStyle(Theme.rowTitle)
                }
            } else {
                RoundButton(label: "Search", id: "searchProjects", size: 46) {
                    withAnimation(.snappy(duration: 0.25)) { searching = true }
                    searchFocused = true
                } label: {
                    LucideIcon(name: "search", size: 22).foregroundStyle(Theme.rowTitle)
                }
                Spacer()
                Button { newProject = true } label: {
                    HStack(spacing: 9) {
                        LucideIcon(name: "plus", size: 22)
                        Text("New project").font(.system(size: 17, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.leading, 18)
                    .padding(.trailing, 22)
                    .frame(height: 50)
                    .background(Color(hex: 0x2F6FE0), in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("newProject")
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 6)
    }

    // MARK: the filter (02)

    private var filterMenu: some View {
        VStack(spacing: 0) {
            filterRow(.pinned, icon: "pin", text: "Pinned", count: pinnedRows.count)
            filterRow(.all, icon: "folder", text: "All projects", count: model.home?.projects.count ?? 0)
            menuLine
            filterRow(.archived, icon: "archive", text: "Archived", count: model.home?.archivedProjects?.count ?? 0)
            menuLine
            Button {
                showFolders.toggle()
                if showFolders { filterRaw = ProjectFilter.all.rawValue }
                withAnimation(.snappy(duration: 0.2)) { filterOpen = false }
            } label: {
                menuItem(on: showFolders, icon: "folder-open", text: "Show folders", count: nil)
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(showFolders ? .isSelected : [])
            .accessibilityIdentifier("filter-folders")
        }
        .padding(.vertical, 8)
        .frame(width: 234)
        .background(Color(hex: 0x1F1F21), in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).stroke(Color(hex: 0x303033), lineWidth: 1))
        .shadow(color: .black.opacity(0.7), radius: 22, y: 18)
    }

    private var menuLine: some View {
        Rectangle().fill(Color(hex: 0x38383A)).frame(height: 1).padding(.leading, 42).padding(.trailing, 18)
            .padding(.vertical, 6)
    }

    private func filterRow(_ f: ProjectFilter, icon: String, text: String, count: Int) -> some View {
        Button {
            filterRaw = f.rawValue
            withAnimation(.snappy(duration: 0.2)) { filterOpen = false }
        } label: {
            menuItem(on: filter == f, icon: icon, text: text, count: count)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(filter == f ? .isSelected : [])
        .accessibilityIdentifier("filter-\(f.rawValue)")
    }

    private func menuItem(on: Bool, icon: String, text: String, count: Int?) -> some View {
        HStack(spacing: 12) {
            Group {
                if on { Image(systemName: "checkmark").font(.system(size: 15, weight: .semibold)) }
            }
            .frame(width: 18)
            LucideIcon(name: icon, size: 21)
            Text(text).font(.system(size: 17))
            Spacer(minLength: 8)
            if let count { Text("\(count)").font(.system(size: 15)).foregroundStyle(Color(hex: 0x8E8E93)) }
        }
        .foregroundStyle(Color(hex: 0xECECEC))
        .padding(.leading, 12)
        .padding(.trailing, 18)
        .frame(height: 46)
        .contentShape(Rectangle())
    }

    // MARK: the list (01)

    private var pinnedRows: [ProjectRow] {
        model.pinnedItems.compactMap { if case .project(let p) = $0 { return p } else { return nil } }
    }

    private var shown: [ProjectRow] {
        guard let h = model.home else { return [] }
        let rows: [ProjectRow]
        switch filter {
        case .pinned: rows = pinnedRows
        case .all: rows = ProjectRow.newestFirst(h.projects)
        case .archived: rows = ProjectRow.newestFirst(h.archivedProjects ?? [])
        }
        guard searching else { return rows }
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return rows }
        return ProjectRow.newestFirst((h.projects + (h.archivedProjects ?? [])).filter { $0.name.lowercased().contains(q) })
    }

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if let home = model.home {
                    if let e = home.projectsError, home.projects.isEmpty {
                        note("Projects can't be read right now (\(e)).")
                    }
                    if showFolders && filter == .all && !searching {
                        ForEach(ProjectLayout.rows(ProjectRow.newestFirst(home.projects), layout: home.layout,
                                                   open: openFolders)) { row in
                            switch row {
                            case .folder(let f, let count): folderHeader(f, count: count)
                            case .project(let p, _): projectRow(p)
                            }
                        }
                    } else {
                        ForEach(shown) { projectRow($0) }
                    }
                    if shown.isEmpty && home.projectsError == nil && !(searching && !hits.isEmpty) {
                        note(emptyText)
                    }
                    if searching && !hits.isEmpty {
                        Text("In their chats")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(Color(hex: 0x8E8E93))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 20)
                            .padding(.top, 14)
                            .padding(.bottom, 10)
                        // their own ids: a project can be both a name match above and a hit here
                        ForEach(hits, id: \.chatId) { hitRow($0) }
                    }
                } else if let e = model.error {
                    note(e.message)
                } else {
                    ProgressView().frame(maxWidth: .infinity).padding(.vertical, 40)
                }
            }
            .padding(.bottom, 20)
        }
        .scrollDismissesKeyboard(.immediately)
        .refreshable { await model.refresh() }
        .accessibilityIdentifier("projectList")
    }

    private var emptyText: String {
        if searching { return "No project has that name." }
        switch filter {
        case .pinned: return "No pinned projects. Long-press one to pin it to the menu."
        case .archived: return "No archived projects."
        case .all: return "No projects yet. New project starts one."
        }
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 15))
            .foregroundStyle(Theme.secondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 30)
            .padding(.vertical, 40)
    }

    private func folderHeader(_ f: LayoutEntry.Folder, count: Int) -> some View {
        let open = openFolders[f.id] ?? !f.collapsed
        return Button {
            withAnimation(.snappy(duration: 0.25)) { openFolders[f.id] = !open }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .rotationEffect(.degrees(open ? 90 : 0))
                Text(f.name).lineLimit(1)
                Spacer(minLength: 8)
                Text("\(count)")
            }
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(Color(hex: 0x8E8E93))
            .padding(.horizontal, 20)
            .padding(.top, 10)
            .padding(.bottom, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(open ? "open" : "closed")
        .accessibilityIdentifier("folder-\(f.name)")
    }

    private func projectRow(_ p: ProjectRow) -> some View {
        let archived = model.home?.archivedProjects?.contains { $0.id == p.id } ?? false
        return Button { open(p) } label: {
            ProjectListRow(project: p, archived: archived)
        }
        .buttonStyle(RowPress())
        .contextMenu {
            if archived {
                Button("Unarchive", systemImage: "archivebox") {
                    Task { await model.setArchived(project: p.id, false) }
                }
                Button("Settings", systemImage: "gearshape") { settingsFor = p.id }
            } else {
                let pinned = model.isPinned(project: p.id)
                Button(pinned ? "Unpin" : "Pin", systemImage: pinned ? "pin.slash" : "pin") {
                    Task { await model.togglePin(project: p.id) }
                }
                Button("Settings", systemImage: "gearshape") { settingsFor = p.id }
                Button("Archive", systemImage: "archivebox") {
                    Task { await model.setArchived(project: p.id, true) }
                }
            }
        }
        .accessibilityIdentifier("project-\(p.id)")
    }

    private func hitRow(_ h: ProjectHit) -> some View {
        let row = model.projectRow(h.id)
        return Button { openChat?(h.chatId) } label: {
            HStack(alignment: .top, spacing: 14) {
                ProjectTile(icon: row?.icon, color: row?.color).padding(.top, 1)
                VStack(alignment: .leading, spacing: 3) {
                    Text(h.name).font(.system(size: 17)).foregroundStyle(Color(hex: 0xECECEC)).lineLimit(1)
                    Text(h.title).font(.system(size: 15)).foregroundStyle(Color(hex: 0x8E8E93)).lineLimit(1)
                    Text(h.snippet).font(.system(size: 14)).foregroundStyle(Theme.secondary).lineLimit(2)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPress())
        .accessibilityIdentifier("hit-\(h.id)")
    }

    /// a project opens on its main chat; one without (not started yet, or archived long ago) on its Settings
    private func open(_ p: ProjectRow) {
        searchFocused = false
        if let id = p.mainChatId { openChat?(id) } else { settingsFor = p.id }
    }
}

/// a String as a sheet's item
struct SheetID: Identifiable {
    let id: String
}

/// One row of 01: the icon on its colour, the name, and "Needs you · 4 min ago"; threads working on the right.
struct ProjectListRow: View {
    let project: ProjectRow
    var archived = false

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            ProjectTile(icon: project.icon, color: project.color).padding(.top, 1)
            VStack(alignment: .leading, spacing: 3) {
                Text(project.name)
                    .font(.system(size: 17))
                    .foregroundStyle(Color(hex: 0xECECEC))
                    .lineLimit(1)
                subline.font(.system(size: 15)).lineLimit(1)
            }
            Spacer(minLength: 8)
            if project.working > 0 && !archived {
                HStack(spacing: 6) {
                    Spinner()
                    Text("\(project.working)").font(.system(size: 15)).foregroundStyle(Color(hex: 0x8E8E93))
                        .monospacedDigit()
                }
                .padding(.top, 13)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(Format.plural(project.working, "thread")) working")
            }
        }
        .padding(.horizontal, 20)
        .frame(height: 64, alignment: .top)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private var subline: Text {
        let when = Format.ago(project.lastActive ?? project.created ?? 0, now: Date())
        let (word, color) = state
        let grey = Color(hex: 0x8E8E93)
        if when.isEmpty { return Text(word).foregroundStyle(color) }
        return Text("\(Text(word).foregroundStyle(color))\(Text(" \u{00B7} \(when)").foregroundStyle(grey))")
    }

    private var state: (String, Color) {
        if archived { return ("Archived", Color(hex: 0x8E8E93)) }
        switch project.state {
        case "needs": return ("Needs you", Theme.violetText)
        case "permission": return ("Waiting for permission", Theme.amber)
        case "working": return ("Working", Theme.blue)
        case "paused": return ("Paused", Color(hex: 0x8E8E93))
        default: return ("All done", Color(hex: 0x8E8E93))
        }
    }
}

/// The overhaul's round top button: 44 pt, dark, a thin border (5a).
struct RoundButton<Label: View>: View {
    let label: String
    let id: String
    var size: CGFloat = 44
    let action: () -> Void
    @ViewBuilder var content: () -> Label

    init(label: String, id: String, size: CGFloat = 44, action: @escaping () -> Void,
         @ViewBuilder label content: @escaping () -> Label) {
        self.label = label
        self.id = id
        self.size = size
        self.action = action
        self.content = content
    }

    var body: some View {
        Button(action: action) {
            content()
                .frame(width: size, height: size)
                .background(Color(hex: 0x161616), in: Circle())
                .overlay(Circle().stroke(Color(hex: 0x262626), lineWidth: 1))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityIdentifier(id)
    }
}

/// a row that greys a little while pressed
struct RowPress: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.background(configuration.isPressed ? Color.white.opacity(0.06) : .clear)
    }
}
