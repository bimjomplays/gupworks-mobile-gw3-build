import PhotosUI
import SwiftUI

extension EnvironmentValues {
    /// Pushes a chat on the list's stack (a thread opened from a project's Overview or a thread card).
    @Entry var openChat: ((String) -> Void)? = nil
    /// The project's threads, live from the PC, by id: the main chat's thread cards read their state here (05).
    @Entry var projectThreads: [String: ThreadItem] = [:]
}

/// What the Overview pushes inside its own sheet (06-10).
enum OverviewPage: Hashable {
    case newThread, done, library, ideas, scheduled
    case schedule(String)
}

/// 06: the project's Overview over its main chat: what needs you, what's working, what's done, then its places
/// (Library, Ideas, Scheduled), each pushed inside the sheet. A thread opens its chat on the list's stack once the
/// sheet has closed.
struct ProjectOverview: View {
    let store: ProjectStore
    @Binding var path: NavigationPath
    /// closes the sheet, then opens this chat
    let open: (String) -> Void
    /// closes the sheet (the main chat's question is under it)
    let close: () -> Void
    /// closes the sheet, then puts these words in the main chat's box
    let put: (String) -> Void

    var body: some View {
        NavigationStack(path: $path) {
            OverviewHome(store: store, open: open, close: close)
                .navigationTitle("Overview")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button(action: close) { Image(systemName: "xmark") }
                            .accessibilityLabel("Close")
                            .accessibilityIdentifier("overviewClose")
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { path.append(OverviewPage.newThread) } label: { Image(systemName: "plus") }
                            .accessibilityLabel("New thread")
                            .accessibilityIdentifier("newThread")
                    }
                }
                .navigationDestination(for: OverviewPage.self) { page in
                    switch page {
                    case .newThread: NewThreadView(store: store) { path = NavigationPath() }
                    case .done: DoneThreadsPage(store: store, open: open)
                    case .library: LibraryPage(store: store, path: $path)
                    case .ideas: IdeasPage(store: store, path: $path, put: put)
                    case .scheduled: ScheduledPage(store: store, path: $path, open: open, put: put)
                    case .schedule(let id): ScheduleDetailPage(store: store, id: id, open: open)
                    }
                }
                .navigationDestination(for: LibraryRow.self) { row in
                    if row.kind == "folder" {
                        LibraryFolderView(store: store, row: row, path: $path)
                    } else {
                        NoteView(store: store, row: row)
                    }
                }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.hidden)
        .presentationBackground(SheetStyle.background)
        .alert("That didn't work", isPresented: Binding(get: { store.actionError != nil },
                                                       set: { if !$0 { store.actionError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(store.actionError ?? "")
        }
    }
}

// MARK: - 06 the Overview itself

private struct OverviewHome: View {
    let store: ProjectStore
    let open: (String) -> Void
    let close: () -> Void
    @State private var stopping: ThreadItem?

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
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(SheetStyle.background)
        .environment(\.defaultMinListRowHeight, 50)
        .refreshable { await store.refresh() }
        .modifier(StopConfirm(store: store, stopping: $stopping))
    }

    @ViewBuilder
    private func content(_ v: ProjectView) -> some View {
        Section { glance(v) }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 0, leading: 8, bottom: 0, trailing: 8))
        let needs = v.groups.first { $0.state == "needs-you" }?.threads ?? []
        if v.mainNeeds != nil || !needs.isEmpty {
            Section {
                if let m = v.mainNeeds { mainRow(m) }
                ForEach(needs) { t in threadRow(t) }
            } header: { OverviewHeader(text: "Needs you") }
        }
        ForEach(v.groups.filter { !["needs-you", "done", "archived"].contains($0.state) }) { g in
            Section {
                ForEach(g.threads) { t in threadRow(t) }
            } header: { OverviewHeader(text: g.label) }
        }
        let done = v.groups.first { $0.state == "done" }?.threads ?? []
        let doneCount = v.counts.done ?? done.count
        let archived = v.counts.archived ?? (v.groups.first { $0.state == "archived" }?.count ?? 0)
        if doneCount + archived > 0 {
            Section {
                ForEach(done.prefix(2)) { t in threadRow(t) }
                if doneCount > 2 || archived > 0 {
                    NavigationLink(value: OverviewPage.done) {
                        HStack(spacing: 14) {
                            LucideIcon(name: "archive", size: 21).foregroundStyle(ProjectLook.plainIcon).frame(width: 24)
                            Text(restOfDone(doneCount - min(doneCount, 2), archived))
                                .font(.system(size: 17)).foregroundStyle(Theme.rowTitle)
                        }
                    }
                    .listRowBackground(SheetStyle.field)
                    .accessibilityIdentifier("doneMore")
                }
            } header: { OverviewHeader(text: "Done") }
        }
        Section {
            place("library", "Library", "library-big", v.counts.library)
            place("ideas", "Ideas", "lightbulb", v.counts.ideas)
            place("scheduled", "Scheduled", "calendar-clock", v.counts.schedules)
        }
        .listSectionSpacing(18)
    }

    /// "● 1 needs you  ◌ 1 working  ✓ 30 done", the desktop's Threads tab counts
    private func glance(_ v: ProjectView) -> some View {
        HStack(spacing: 16) {
            ForEach(v.quiet, id: \.self) { q in
                HStack(spacing: 7) {
                    ThreadMark(glyph: q.glyph, size: 16)
                    Text(q.text)
                }
            }
            if let d = v.counts.done, d > 0 {
                HStack(spacing: 7) {
                    ThreadMark(glyph: "check", size: 16)
                    Text("\(d) done")
                }
            }
            if v.quiet.isEmpty && (v.counts.done ?? 0) == 0 {
                Text(v.paused ? "Project paused" : "Nothing running yet")
            }
        }
        .font(.system(size: 16))
        .foregroundStyle(Color(hex: 0xC8C8CC))
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("overviewGlance")
    }

    private func restOfDone(_ more: Int, _ archived: Int) -> String {
        var parts: [String] = []
        if more > 0 { parts.append("\(more) more") }
        if archived > 0 { parts.append("\(archived) archived") }
        return parts.isEmpty ? "All done threads" : parts.joined(separator: ", ")
    }

    /// The main chat's own question: a tap closes the sheet onto it.
    private func mainRow(_ m: ProjectView.MainNeeds) -> some View {
        Button(action: close) {
            HStack(alignment: .firstTextBaseline, spacing: 14) {
                ThreadMark(glyph: "needs", size: 22).alignmentGuide(.firstTextBaseline) { d in d[VerticalAlignment.center] + 6 }
                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Main chat").font(.system(size: 17)).foregroundStyle(Theme.rowTitle)
                        Spacer(minLength: 6)
                        Text(m.ago.map { $0.isEmpty || $0 == "0m" ? "now" : $0 } ?? "now")
                            .font(.system(size: 14)).foregroundStyle(Color(hex: 0x8E8E93))
                    }
                    Text(m.text).font(.system(size: 15)).foregroundStyle(Theme.violet).lineLimit(2)
                }
            }
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(SheetStyle.field)
        .accessibilityIdentifier("needsMain")
    }

    private func threadRow(_ t: ThreadItem) -> some View {
        OverviewThreadRow(thread: t, busy: store.busy.contains(t.id))
            .contentShape(Rectangle())
            .onTapGesture { if let c = t.chatId { open(c) } }
            .accessibilityAddTraits(t.chatId == nil ? [] : .isButton)
            .accessibilityIdentifier("thread-\(t.id)")
            .listRowBackground(SheetStyle.field)
            .modifier(ThreadMoves(store: store, thread: t, open: open, stopping: $stopping))
    }

    private func place(_ id: String, _ title: String, _ icon: String, _ count: Int?) -> some View {
        let page: OverviewPage = id == "library" ? .library : id == "ideas" ? .ideas : .scheduled
        return NavigationLink(value: page) {
            HStack(spacing: 14) {
                LucideIcon(name: icon, size: 21).foregroundStyle(ProjectLook.plainIcon).frame(width: 24)
                Text(title).font(.system(size: 17)).foregroundStyle(Theme.rowTitle)
                Spacer(minLength: 6)
                if let count { Text("\(count)").font(.system(size: 16)).foregroundStyle(Color(hex: 0x8E8E93)) }
            }
        }
        .listRowBackground(SheetStyle.field)
        .accessibilityIdentifier("overview-\(id)")
    }
}

/// "Working", "Done": grey over a card
private struct OverviewHeader: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 15))
            .foregroundStyle(Color(hex: 0x98989F))
            .textCase(nil)
            .padding(.leading, 0)
    }
}

/// One thread in the Overview: its mark, title and id, how long ago; what it's doing and its model under it.
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
                    if let ago = thread.ago, !ago.isEmpty {
                        Text(ago).font(.system(size: 14)).foregroundStyle(Color(hex: 0x8E8E93))
                    }
                }
                if !line.isEmpty {
                    Text(line)
                        .font(.system(size: 15))
                        .foregroundStyle(thread.glyph == "needs" ? Theme.violet : Color(hex: 0x8E8E93))
                        .lineLimit(2)
                }
            }
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }

    /// the PC's line ("Restaurant shot · Opus xhigh"); an older PC's detail and model
    private var line: String {
        if let l = thread.line, !l.isEmpty { return l }
        return [thread.detail, thread.right].filter { !$0.isEmpty }.joined(separator: " \u{00B7} ")
    }
}

/// D9's moves on a thread: swipe for Pause or Resume, Mark done and Archive; a long press adds Open and Stop.
private struct ThreadMoves: ViewModifier {
    let store: ProjectStore
    let thread: ThreadItem
    let open: (String) -> Void
    @Binding var stopping: ThreadItem?

    func body(content: Content) -> some View {
        let t = thread
        content
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
                if let c = t.chatId {
                    Button("Open thread", systemImage: "bubble.left") { open(c) }
                }
                Section {
                    if t.moves.contains("pause") { Button("Pause", systemImage: "pause") { act("pause") } }
                    if t.moves.contains("resume") { Button("Resume", systemImage: "play") { act("resume") } }
                    if t.moves.contains("done") { Button("Mark done", systemImage: "checkmark") { act("done") } }
                    if t.moves.contains("archive") { Button("Archive", systemImage: "archivebox") { act("archive") } }
                    if t.moves.contains("unarchive") {
                        Button("Unarchive", systemImage: "tray.and.arrow.up") { act("unarchive") }
                    }
                }
                if t.moves.contains("stop") {
                    Section {
                        Button("Stop\u{2026}", systemImage: "stop", role: .destructive) { stopping = t }
                    }
                }
            }
    }

    private func act(_ move: String) {
        let s = store, id = thread.id
        Task { await s.move(move, thread: id) }
    }
}

/// Stop asks first: the thread's Claude stops, the thread stays.
private struct StopConfirm: ViewModifier {
    let store: ProjectStore
    @Binding var stopping: ThreadItem?

    func body(content: Content) -> some View {
        content
            .confirmationDialog(stopping.map { "Stop \u{201C}\($0.title)\u{201D}?" } ?? "Stop this thread?",
                                isPresented: Binding(get: { stopping != nil }, set: { if !$0 { stopping = nil } }),
                                titleVisibility: .visible, presenting: stopping) { t in
                Button("Stop", role: .destructive) { Task { await store.move("stop", thread: t.id) } }
                Button("Cancel", role: .cancel) {}
            } message: { _ in
                Text("Its Claude stops working on it. The thread stays in the project, so it can be picked up again.")
            }
    }
}

private struct OverviewNotice: View {
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

/// "28 more, 4 archived": every done thread, then the archived ones.
private struct DoneThreadsPage: View {
    let store: ProjectStore
    let open: (String) -> Void
    @State private var stopping: ThreadItem?

    var body: some View {
        List {
            ForEach((store.view?.groups ?? []).filter { $0.state == "done" || $0.state == "archived" }) { g in
                Section {
                    ForEach(g.threads) { t in
                        OverviewThreadRow(thread: t, busy: store.busy.contains(t.id))
                            .contentShape(Rectangle())
                            .onTapGesture { if let c = t.chatId { open(c) } }
                            .accessibilityIdentifier("thread-\(t.id)")
                            .listRowBackground(SheetStyle.field)
                            .modifier(ThreadMoves(store: store, thread: t, open: open, stopping: $stopping))
                    }
                } header: { OverviewHeader(text: "\(g.label) \u{00B7} \(g.count)") }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(SheetStyle.background)
        .navigationTitle("Done")
        .navigationBarTitleDisplayMode(.inline)
        .modifier(StopConfirm(store: store, stopping: $stopping))
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
                .background(SheetStyle.field, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
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
        .background(SheetStyle.background)
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

// MARK: - 08 Library

/// 08: the project's notes and what its threads made, Ideas and the project note first; + copies photos or
/// files into the notes folder.
struct LibraryPage: View {
    let store: ProjectStore
    @Binding var path: NavigationPath
    @State private var query = ""
    @State private var kind = "all"
    @State private var pickingPhotos = false
    @State private var pickingFiles = false
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var adding = false

    private static let kinds = [("all", "All"), ("notes", "Notes"), ("images", "Images"), ("videos", "Videos")]

    var body: some View {
        List {
            Section {
                VStack(spacing: 14) {
                    SheetSearchField(text: $query, prompt: "Search notes and files\u{2026}")
                        .accessibilityIdentifier("librarySearch")
                    HStack(spacing: 8) {
                        ForEach(Self.kinds, id: \.0) { k in chip(k.0, k.1) }
                        Spacer(minLength: 0)
                    }
                }
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
            if adding {
                Section {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Copying to the PC\u{2026}").foregroundStyle(SheetStyle.label)
                    }
                }
                .listRowBackground(SheetStyle.field)
            }
            if let lib = store.library {
                LibraryCards(groups: filtered(lib.groups), store: store, path: $path)
                if filtered(lib.groups).isEmpty {
                    OverviewNotice(icon: "magnifyingglass",
                                   text: lib.groups.allSatisfy { $0.items.isEmpty } ? "No notes yet." : "Nothing matches.")
                }
            } else {
                ProgressView().frame(maxWidth: .infinity).padding(.vertical, 30).listRowBackground(Color.clear)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(SheetStyle.background)
        .environment(\.defaultMinListRowHeight, 50)
        .navigationTitle("Library")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Photos", systemImage: "photo.on.rectangle") { pickingPhotos = true }
                    Button("Files", systemImage: "folder") { pickingFiles = true }
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add to the Library")
                .accessibilityIdentifier("libraryAdd")
                .disabled(adding)
            }
        }
        .photosPicker(isPresented: $pickingPhotos, selection: $photoItems, maxSelectionCount: 10, matching: .images)
        .onChange(of: photoItems) { _, items in addPhotos(items) }
        .fileImporter(isPresented: $pickingFiles, allowedContentTypes: [.item], allowsMultipleSelection: true) { r in
            guard case .success(let urls) = r else { return }
            var files: [Attachment] = []
            for url in urls.prefix(10) {
                switch Attachment.file(url) {
                case .success(let a): files.append(a)
                case .failure(let p): store.actionError = p.message
                }
            }
            add(files)
        }
        .refreshable { await store.loadLibrary() }
        .task { await store.loadLibrary() }
    }

    private func chip(_ id: String, _ title: String) -> some View {
        let on = kind == id
        return Button { kind = id } label: {
            Text(title)
                .font(.system(size: 16))
                .foregroundStyle(on ? Color.black : Color(hex: 0xC8C8CC))
                .padding(.horizontal, 16)
                .frame(height: 38)
                .background(on ? Color(hex: 0xECECEC) : SheetStyle.field, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
        .accessibilityIdentifier("libraryKind-\(id)")
    }

    private func filtered(_ groups: [LibraryGroup]) -> [LibraryGroup] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        return groups.compactMap { g in
            var g = g
            g.items = g.items.filter { r in
                let kindOK: Bool
                switch kind {
                case "notes": kindOK = r.kind == "note" || r.kind == "folder"
                case "images": kindOK = r.kind == "image"
                case "videos": kindOK = r.kind == "video"
                default: kindOK = true
                }
                return kindOK && (q.isEmpty || r.title.lowercased().contains(q) || r.sub.lowercased().contains(q))
            }
            return g.items.isEmpty ? nil : g
        }
    }

    private func addPhotos(_ items: [PhotosPickerItem]) {
        guard !items.isEmpty else { return }
        photoItems = []
        Task {
            var files: [Attachment] = []
            for (i, item) in items.enumerated() {
                if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data),
                   let a = Attachment.photo(image, name: items.count == 1 ? "photo.jpg" : "photo-\(i + 1).jpg") {
                    files.append(a)
                }
            }
            add(files)
        }
    }

    private func add(_ files: [Attachment]) {
        guard !files.isEmpty else { return }
        adding = true
        Task {
            _ = await store.addToLibrary(files)
            adding = false
        }
    }
}

/// The Library's groups as cards: a tap opens a note or folder inside the sheet, Ideas as its own page (09), a
/// video in the player.
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
                    .listRowBackground(SheetStyle.field)
                    .listRowInsets(EdgeInsets(top: 0, leading: 14, bottom: 0, trailing: 16))
                    .accessibilityIdentifier("lib-\(r.title)")
                }
            } header: {
                if !g.label.isEmpty { OverviewHeader(text: g.label) }
            }
        }
        .fullScreenCover(item: $playing) { MediaViewer(item: $0, base: store.baseURL) }
    }

    static func isIdeas(_ r: LibraryRow) -> Bool { r.group == "pinned" && r.title == "Ideas" }

    private func chevron(_ r: LibraryRow) -> Bool { r.kind == "folder" || r.group == "pinned" }

    private func tap(_ r: LibraryRow) {
        if Self.isIdeas(r) {
            path.append(OverviewPage.ideas)
        } else if r.kind == "video" {
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
                    .foregroundStyle(Color(hex: 0x8E8E93))
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
                .foregroundStyle(row.kind == "folder" ? ProjectLook.plainIcon : ProjectLook.plainIcon)
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

// MARK: - 09 Ideas

/// 09: the project's Ideas note by its sections. Tap an idea to edit it in place; a long press starts it, moves it
/// or deletes it; the bar at the bottom adds one word for word (no model turn).
struct IdeasPage: View {
    let store: ProjectStore
    @Binding var path: NavigationPath
    let put: (String) -> Void
    @State private var newIdea = ""
    @State private var editing: IdeaRef?
    @State private var draft = ""
    @State private var adding = false
    @FocusState private var focus: Field?

    enum Field: Hashable { case add, edit }

    struct IdeaRef: Hashable {
        let section: String
        let raw: String
    }

    var body: some View {
        ScrollView {
            if let l = store.ideas {
                VStack(alignment: .leading, spacing: 0) {
                    Text(l.title)
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(Theme.title)
                        .padding(.bottom, 8)
                        .accessibilityIdentifier("ideasTitle")
                    ForEach(l.sections) { s in section(s, all: l.sections) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 22)
                .padding(.top, 12)
                .padding(.bottom, 30)
            } else {
                ProgressView().padding(.top, 60)
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Theme.background)
        .navigationTitle("Ideas")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Open as note", systemImage: "doc.text") { openAsNote() }
                    Button("Refresh", systemImage: "arrow.clockwise") { Task { await store.loadIdeas() } }
                } label: {
                    Image(systemName: "ellipsis")
                }
                .accessibilityLabel("More")
                .accessibilityIdentifier("ideasMore")
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { addBar }
        .refreshable { await store.loadIdeas() }
        .task { await store.loadIdeas() }
        .onChange(of: focus) { old, new in
            if old == .edit && new != .edit { saveEdit() }
        }
    }

    private func section(_ s: IdeasSection, all: [IdeasSection]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(s.name).font(.system(size: 20, weight: .semibold)).foregroundStyle(Theme.title)
            if s.items.isEmpty {
                Text(s.empty).font(.system(size: 17)).foregroundStyle(Color(hex: 0x7C7C80))
            }
            ForEach(s.items, id: \.raw) { item in
                idea(item, in: s, all: all)
            }
        }
        .padding(.top, 22)
    }

    @ViewBuilder
    private func idea(_ item: IdeaItem, in s: IdeasSection, all: [IdeasSection]) -> some View {
        let ref = IdeaRef(section: s.name, raw: item.raw)
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            if item.ai {
                Text("AI")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.violetText)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Theme.violet.opacity(0.22), in: RoundedRectangle(cornerRadius: 6))
            } else {
                Text("\u{2022}").font(.system(size: 17)).foregroundStyle(Color(hex: 0x8E8E93))
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
                    .lineSpacing(4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture { startEdit(ref, item) }
                    .contextMenu {
                        Button("Start it", systemImage: "play") {
                            put("Start a thread for this idea from the Ideas note: \(item.text)")
                        }
                        Menu("Move to", systemImage: "arrow.right") {
                            ForEach(all.filter { $0.name != s.name }) { to in
                                Button(to.name) {
                                    change(IdeaChange(op: "move", section: s.name, old: item.raw, to: to.name))
                                }
                            }
                        }
                        Button("Edit", systemImage: "pencil") { startEdit(ref, item) }
                        Button("Delete", systemImage: "trash", role: .destructive) {
                            change(IdeaChange(op: "delete", section: s.name, old: item.raw))
                        }
                    }
                    .accessibilityIdentifier("idea-\(item.text)")
            }
        }
    }

    /// the idea, its date in grey after it
    private func ideaText(_ item: IdeaItem) -> Text {
        let date = item.date.map { " (" + $0 + ")" } ?? ""
        return Text("\(Text(item.text).foregroundStyle(Theme.rowTitle))\(Text(date).foregroundStyle(Color(hex: 0x7C7C80)))")
    }

    private var addBar: some View {
        HStack(spacing: 12) {
            LucideIcon(name: "lightbulb", size: 21).foregroundStyle(Color(hex: 0x8E8E93))
            TextField("Add an idea\u{2026}", text: $newIdea, axis: .vertical)
                .lineLimit(1...4)
                .font(.system(size: 17))
                .foregroundStyle(Theme.rowTitle)
                .focused($focus, equals: .add)
                .accessibilityIdentifier("ideaText")
            Button(action: add) {
                Group {
                    if adding { ProgressView().tint(.white) } else { Image(systemName: "arrow.up") }
                }
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(canAdd ? Color.black : Color(hex: 0x8E8E93))
                .frame(width: 40, height: 40)
                .background(canAdd ? Color(hex: 0xECECEC) : Color(hex: 0x3A3A3C), in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(!canAdd)
            .accessibilityLabel("Add idea")
            .accessibilityIdentifier("ideaAdd")
        }
        .padding(.leading, 18)
        .padding(.trailing, 6)
        .padding(.vertical, 6)
        .background(Color(hex: 0x1C1C1E), in: Capsule())
        .overlay(Capsule().stroke(Color(hex: 0x2C2C2E), lineWidth: 1))
        .padding(.horizontal, 14)
        .padding(.bottom, 8)
    }

    private var canAdd: Bool { !newIdea.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !adding }

    private func add() {
        let text = newIdea
        adding = true
        Task {
            if await store.addIdea(text) { newIdea = "" }
            adding = false
        }
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
        path.append(LibraryRow(path: l.path, kind: "note", title: "Ideas", sub: "", mtime: l.mtime, exists: true,
                               workId: nil, editable: true, thumb: nil, url: nil, group: nil))
    }
}

// MARK: - 10 Scheduled

/// 10: the project's schedules (each run is a thread): Scheduled, Running now, Paused and the past runs.
/// + puts "New schedule: " in the main chat's box, as the desktop's New schedule does.
struct ScheduledPage: View {
    let store: ProjectStore
    @Binding var path: NavigationPath
    let open: (String) -> Void
    let put: (String) -> Void

    var body: some View {
        List {
            if let s = store.schedules {
                ForEach(s.groups) { g in
                    Section {
                        ForEach(g.items) { r in row(r) }
                    } header: { OverviewHeader(text: g.label) }
                }
                if let past = s.past, !past.isEmpty {
                    Section {
                        ForEach(Array(past.enumerated()), id: \.offset) { _, run in RunRow(run: run, open: open) }
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
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(SheetStyle.background)
        .environment(\.defaultMinListRowHeight, 50)
        .navigationTitle("Scheduled")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { put("New schedule: ") } label: { Image(systemName: "plus") }
                    .accessibilityLabel("New schedule")
                    .accessibilityIdentifier("newSchedule")
            }
        }
        .refreshable { await store.loadSchedules() }
        .task { await store.loadSchedules() }
    }

    private func row(_ r: ScheduleRow) -> some View {
        Button {
            if r.running, let c = r.chatId { open(c) } else { path.append(OverviewPage.schedule(r.id)) }
        } label: {
            ScheduleCardRow(row: r)
        }
        .buttonStyle(.plain)
        .listRowBackground(SheetStyle.field)
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

private struct ScheduleCardRow: View {
    let row: ScheduleRow

    var body: some View {
        HStack(spacing: 14) {
            Group {
                if row.running {
                    ThreadMark(glyph: "spin", size: 22)
                } else {
                    LucideIcon(name: row.paused ? "circle-pause" : "clock", size: 22).foregroundStyle(ProjectLook.plainIcon)
                }
            }
            .frame(width: 24)
            VStack(alignment: .leading, spacing: 3) {
                Text(row.title).font(.system(size: 17)).foregroundStyle(Theme.rowTitle).lineLimit(1)
                Text(row.when)
                    .font(.system(size: 15))
                    .foregroundStyle(row.skipped == true ? Theme.amber : Color(hex: 0x8E8E93))
                    .lineLimit(2)
            }
            Spacer(minLength: 6)
            if !row.right.isEmpty {
                Text(row.right).font(.system(size: 16)).foregroundStyle(Color(hex: 0x8E8E93))
            }
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// One run of a schedule: the thread it made, or why it didn't run; a tap opens the thread.
private struct RunRow: View {
    let run: ScheduleRun
    let open: (String) -> Void

    var body: some View {
        Button { if let c = run.chatId { open(c) } } label: {
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
                        .foregroundStyle(run.status == "failed" ? ChatStyle.failed : Color(hex: 0x8E8E93))
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(run.chatId == nil)
        .listRowBackground(SheetStyle.field)
    }
}

/// A schedule's own page: when it runs, its prompt and model, and its runs.
private struct ScheduleDetailPage: View {
    let store: ProjectStore
    let id: String
    let open: (String) -> Void

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
                            .listRowBackground(SheetStyle.field)
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
                .listRowBackground(SheetStyle.field)
                .foregroundStyle(Theme.rowTitle)
                if let runs = r.runs, !runs.isEmpty {
                    Section {
                        ForEach(Array(runs.enumerated()), id: \.offset) { _, run in RunRow(run: run, open: open) }
                    } header: { OverviewHeader(text: "Runs") }
                }
            } else {
                OverviewNotice(icon: "clock", text: "This schedule is gone.")
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(SheetStyle.background)
        .navigationTitle(row?.title ?? "Schedule")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func line(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).foregroundStyle(Theme.rowTitle)
            Spacer(minLength: 12)
            Text(value.isEmpty ? "\u{2014}" : value).foregroundStyle(Color(hex: 0x8E8E93)).multilineTextAlignment(.trailing)
        }
        .font(.system(size: 17))
        .listRowBackground(SheetStyle.field)
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
