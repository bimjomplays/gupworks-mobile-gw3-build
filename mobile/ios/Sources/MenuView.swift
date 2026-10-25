import SwiftUI

/// 5c: ChatGPT's menu with GupWorks inside. The title and search; Projects, Scheduled, Quick actions, Gup Bot; then
/// Pinned (chats and projects, long-press to sort them, 5d) and Recents (every other chat, newest first). New chat
/// floats at the bottom with Settings beside it.
struct MenuView: View {
    @Environment(AppModel.self) private var model
    /// the chat on screen (its row is lit)
    let current: String?
    let open: Bool
    let pick: (Current) -> Void
    let newChat: () -> Void
    let place: (Place) -> Void
    let settings: () -> Void

    @State private var searching = false
    @State private var query = ""
    @State private var hits: [SearchHit] = []
    @FocusState private var searchFocused: Bool
    // 5d: sorting the pins
    @State private var sorting = false
    @State private var order: [PinItem] = []
    @State private var dragged: String?
    @State private var dragY: CGFloat = 0
    @State private var dragFrom = 0
    /// the long-press that started sorting still holds the row
    @GestureState private var holding = false
    @State private var slotTick = 0
    @State private var liftTick = 0
    @State private var renaming: ChatRow?
    @State private var newTitle = ""
    @State private var deleting: ChatRow?

    static let rowStep: CGFloat = 46
    static let ink = Color(hex: 0xECECEC)
    static let grey = Color(hex: 0x8E8E93)
    static let dim = Color(hex: 0x5C5C60)

    var body: some View {
        ZStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 0) {
                header
                if searching {
                    searchResults
                } else {
                    list
                }
            }
            if !searching { bottomBar }
        }
        .background(Color.black)
        .onChange(of: open) { _, o in
            if !o {
                finishSorting()
                endSearch()
            }
        }
        .onChange(of: holding) { _, h in
            // the finger left (or the touch was cancelled): the pin settles in its slot
            if !h { drop() }
        }
        .sensoryFeedback(.selection, trigger: slotTick)
        .sensoryFeedback(.impact(weight: .medium), trigger: liftTick)
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
            Button("Delete", role: .destructive) {
                Task {
                    if await model.delete(c.id), c.id == current { newChat() }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text(ChatActions.deleteNote)
        }
    }

    // MARK: the title and search

    @ViewBuilder
    private var header: some View {
        if searching {
            HStack(spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(Self.grey)
                    TextField("", text: $query, prompt: Text("Search").foregroundStyle(Self.grey))
                        .foregroundStyle(Self.ink)
                        .focused($searchFocused)
                        .submitLabel(.search)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("searchField")
                }
                .padding(.horizontal, 12)
                .frame(height: 40)
                .background(Color(hex: 0x1C1C1E), in: Capsule())
                Button("Cancel") { endSearch() }
                    .foregroundStyle(Self.ink)
                    .accessibilityIdentifier("cancelSearch")
            }
            .padding(.leading, 16)
            .padding(.trailing, 14)
            .frame(height: 56)
            .padding(.top, 2)
        } else {
            HStack {
                Text("GupWorks")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(Color(hex: 0xF2F2F2))
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Button {
                    finishSorting()
                    searching = true
                    searchFocused = true
                } label: {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(Self.ink)
                        .frame(width: 44, height: 44)
                        .background(Color(hex: 0x161616), in: Circle())
                        .overlay(Circle().stroke(Color(hex: 0x262626), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Search")
                .accessibilityIdentifier("search")
            }
            .padding(.leading, 22)
            .padding(.trailing, 16)
            .frame(height: 56)
            .padding(.top, 2)
        }
    }

    // MARK: places, Pinned and Recents

    private var list: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                if let e = model.error {
                    ErrorBanner(error: e).padding(.horizontal, 22).padding(.vertical, 8)
                }
                ForEach(Place.allCases, id: \.self) { p in
                    Button { place(p) } label: {
                        MenuRow(title: p.title) { MenuIcon(place: p) }
                    }
                    .buttonStyle(MenuRowStyle())
                    .disabled(sorting)
                    .accessibilityIdentifier("place-\(p.rawValue)")
                }
                if model.home == nil && model.error == nil {
                    ProgressView().frame(maxWidth: .infinity).padding(.vertical, 30)
                }
                if !pins.isEmpty {
                    sectionHeader("Pinned") {
                        if sorting {
                            Button("Done") { finishSorting() }
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(Theme.blue)
                                .accessibilityIdentifier("doneSorting")
                        }
                    }
                    pinnedRows
                }
                if !model.recents.isEmpty {
                    sectionHeader("Recents") { EmptyView() }
                    ForEach(model.recents) { c in recentRow(c) }
                }
            }
            .padding(.top, 4)
            .padding(.bottom, 120)
        }
        .scrollIndicators(.hidden)
        .scrollDisabled(dragged != nil)
        .refreshable { await model.refresh() }
        .coordinateSpace(.named("menu"))
    }

    private func sectionHeader(_ title: String, @ViewBuilder trailing: () -> some View) -> some View {
        HStack {
            Text(title).font(.system(size: 15, weight: .medium)).foregroundStyle(Self.grey)
            Spacer()
            trailing()
        }
        .padding(.leading, 22)
        .padding(.trailing, 24)
        .frame(height: 30)
        .padding(.top, 16)
    }

    /// the pins as shown: while sorting, in the order being made
    private var pins: [PinItem] { sorting ? order : model.pinnedItems }

    private var pinnedRows: some View {
        ForEach(Array(pins.enumerated()), id: \.element.id) { i, item in
            let lifted = dragged == item.id
            PinRowView(item: item, sorting: sorting, lifted: lifted, lit: !sorting && isCurrent(item),
                       now: now)
                .offset(y: lifted ? dragY - CGFloat(i - dragFrom) * Self.rowStep : 0)
                .zIndex(lifted ? 1 : 0)
                .contentShape(Rectangle())
                .onTapGesture { if !sorting { open(item) } }
                .gesture(liftGesture(item))
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isButton)
                .accessibilityIdentifier("pin-\(item.title)")
                .accessibilityAction(named: "Reorder pins") { startSorting(lifting: nil) }
        }
    }

    private func recentRow(_ c: ChatRow) -> some View {
        Button { pick(.chat(c.id, sheet: false)) } label: {
            MenuRow(title: c.title, dim: sorting, lit: !sorting && c.id == current) {
                Image(systemName: "bubble.left").font(.system(size: 19))
            } mark: {
                StateMark(state: c.state)
            }
        }
        .buttonStyle(MenuRowStyle())
        .disabled(sorting)
        .accessibilityIdentifier("chat-\(c.title)")
        .contextMenu {
            Section {
                Button("Rename", systemImage: "pencil") {
                    newTitle = c.title
                    renaming = c
                }
                Button("Pin", systemImage: "pin") { Task { await model.edit(c.id, ChatEdit(pinned: true)) } }
                Button("Archive", systemImage: "archivebox") {
                    Task { if await model.edit(c.id, ChatEdit(archived: true)), c.id == current { newChat() } }
                }
            }
            Section {
                Button("Delete\u{2026}", systemImage: "trash", role: .destructive) { deleting = c }
            }
        }
    }

    private var now: Date { Date(timeIntervalSince1970: (model.home?.now ?? 0) / 1000) }

    private func isCurrent(_ item: PinItem) -> Bool {
        switch item {
        case .chat(let c): return c.id == current
        case .project(let p): return p.mainChatId != nil && p.mainChatId == current
        }
    }

    private func open(_ item: PinItem) {
        switch item {
        case .chat(let c): pick(.chat(c.id, sheet: false))
        case .project(let p): if let id = p.mainChatId { pick(.chat(id, sheet: true)) }
        }
    }

    // MARK: 5d: sorting

    /// long-press a pin: every pin gets its handle and the pressed one follows your finger; while sorting, each
    /// pin is picked up the same way. One fixed gesture: changing a row's gestures mid-touch cancels the touch.
    private func liftGesture(_ item: PinItem) -> some Gesture {
        LongPressGesture(minimumDuration: 0.4)
            .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .named("menu")))
            .updating($holding) { v, holding, _ in
                if case .second(true, _) = v { holding = true }
            }
            .onChanged { v in
                guard case .second(true, let d) = v else { return }
                if !sorting { startSorting(lifting: item) } else if dragged == nil { lift(item) }
                if let d { follow(item, d.translation.height) }
            }
    }

    private func startSorting(lifting item: PinItem?) {
        order = model.pinnedItems
        withAnimation(.easeOut(duration: 0.2)) { sorting = true }
        if let item { lift(item) } else { liftTick += 1 }
    }

    private func lift(_ item: PinItem) {
        dragFrom = order.firstIndex(of: item) ?? 0
        dragY = 0
        withAnimation(.easeOut(duration: 0.15)) { dragged = item.id }
        liftTick += 1
    }

    /// the finger is `dy` from where the lift began: the row takes the slot under it, the others slide aside
    private func follow(_ item: PinItem, _ dy: CGFloat) {
        guard dragged == item.id, let at = order.firstIndex(of: item) else { return }
        dragY = dy
        let want = min(max(Int((CGFloat(dragFrom) * Self.rowStep + dy) / Self.rowStep + 0.5), 0), order.count - 1)
        if want != at {
            withAnimation(.snappy(duration: 0.2)) {
                order.move(fromOffsets: IndexSet(integer: at), toOffset: want > at ? want + 1 : want)
            }
            slotTick += 1
        }
    }

    private func drop() {
        withAnimation(.snappy(duration: 0.2)) {
            dragged = nil
            dragY = 0
        }
    }

    /// Done (or the menu closing): the new order goes to the PC
    private func finishSorting() {
        guard sorting else { return }
        drop()
        withAnimation(.easeOut(duration: 0.2)) { sorting = false }
        let refs = order.map(\.ref)
        if refs != model.pinnedItems.map(\.ref) { Task { await model.setPinned(refs) } }
    }

    // MARK: search: titles first, then what was said

    private var searchResults: some View {
        let q = query.trimmingCharacters(in: .whitespaces)
        let titled = titleMatches(q)
        return ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                if !titled.isEmpty {
                    ForEach(titled) { item in
                        Button { open(item) } label: {
                            MenuRow(title: item.title) { itemIcon(item) }
                        }
                        .buttonStyle(MenuRowStyle())
                        .accessibilityIdentifier("found-\(item.title)")
                    }
                }
                let said = hits.filter { h in !titled.contains { $0.ref == PinRef(kind: "chat", id: h.id) } }
                if !said.isEmpty {
                    sectionHeader("In what was said") { EmptyView() }
                    ForEach(said, id: \.id) { h in
                        Button { pick(.chat(h.id, sheet: false)) } label: {
                            HStack(alignment: .top, spacing: 14) {
                                Image(systemName: "text.magnifyingglass").font(.system(size: 18))
                                    .frame(width: 24, height: 22)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(h.title).font(.system(size: 17)).foregroundStyle(Self.ink).lineLimit(1)
                                    if let s = h.snippet, !s.isEmpty {
                                        Text(s).font(.system(size: 14)).foregroundStyle(Self.grey).lineLimit(2)
                                    }
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(MenuRowStyle())
                        .accessibilityIdentifier("said-\(h.title)")
                    }
                }
                if q.count >= 2 && titled.isEmpty && said.isEmpty {
                    Text("Nothing found for \u{201C}\(q)\u{201D}.")
                        .font(.system(size: 15))
                        .foregroundStyle(Self.grey)
                        .padding(.horizontal, 22)
                        .padding(.top, 16)
                }
            }
            .padding(.top, 6)
            .padding(.bottom, 30)
        }
        .scrollDismissesKeyboard(.interactively)
        .task(id: q) {
            guard q.count >= 2 else { hits = []; return }
            try? await Task.sleep(nanoseconds: 250_000_000)
            if Task.isCancelled { return }
            hits = await model.search(q)
        }
    }

    /// every chat and project whose title has the words: pins first, then the rest newest first
    private func titleMatches(_ q: String) -> [PinItem] {
        guard !q.isEmpty, let h = model.home else { return [] }
        var items = model.pinnedItems
        items += model.recents.map { .chat($0) }
        items += h.projects.filter { p in !items.contains { $0.ref == PinRef(kind: "project", id: p.id) } }
            .map { .project($0) }
        return items.filter { $0.title.localizedStandardContains(q) }
    }

    @ViewBuilder
    private func itemIcon(_ item: PinItem) -> some View {
        switch item {
        case .chat: Image(systemName: "bubble.left").font(.system(size: 19))
        case .project: Image(systemName: "folder").font(.system(size: 19))
        }
    }

    private func endSearch() {
        searching = false
        searchFocused = false
        query = ""
        hits = []
    }

    // MARK: New chat and Settings

    private var bottomBar: some View {
        HStack {
            Button(action: newChat) {
                HStack(spacing: 10) {
                    Image(systemName: "square.and.pencil").font(.system(size: 19, weight: .medium))
                    Text("New chat").font(.system(size: 17, weight: .semibold))
                }
                .foregroundStyle(.white)
                .padding(.leading, 20)
                .padding(.trailing, 24)
                .frame(height: 52)
                .background(Color(hex: 0x2F6FE0), in: Capsule())
                .shadow(color: .black.opacity(0.5), radius: 12, y: 6)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("newChat")
            Spacer()
            Button(action: settings) {
                Image(systemName: "gearshape")
                    .font(.system(size: 20))
                    .foregroundStyle(Self.ink)
                    .frame(width: 46, height: 46)
                    .background(Color(hex: 0x161616), in: Circle())
                    .overlay(Circle().stroke(Color(hex: 0x2A2A2A), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Settings")
            .accessibilityIdentifier("settings")
        }
        .padding(.leading, 22)
        .padding(.trailing, 20)
        .padding(.bottom, 8)
    }
}

/// One of the menu's rows: a 22-point icon, the title, and a state mark on the right.
struct MenuRow<Icon: View, Mark: View>: View {
    let title: String
    var dim = false
    var lit = false
    @ViewBuilder var icon: () -> Icon
    @ViewBuilder var mark: () -> Mark

    var body: some View {
        HStack(spacing: 14) {
            icon().frame(width: 24, height: 24)
            Text(title).font(.system(size: 17)).lineLimit(1)
            Spacer(minLength: 8)
            mark()
        }
        .foregroundStyle(dim ? MenuView.dim : MenuView.ink)
        .padding(.horizontal, 12)
        .frame(height: 44)
        .background(lit ? Color(hex: 0x1C1C1E) : .clear, in: RoundedRectangle(cornerRadius: 12))
        .contentShape(Rectangle())
        .padding(.horizontal, 10)
    }
}

extension MenuRow where Mark == EmptyView {
    init(title: String, dim: Bool = false, lit: Bool = false, @ViewBuilder icon: @escaping () -> Icon) {
        self.init(title: title, dim: dim, lit: lit, icon: icon, mark: { EmptyView() })
    }
}

/// a pressed row darkens, as ChatGPT's
struct MenuRowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(configuration.isPressed ? 0.55 : 1)
    }
}

/// violet: needs you; amber: waiting for permission; the spinner: working
struct StateMark: View {
    let state: String
    var working = false

    var body: some View {
        if state == "working" || working {
            Spinner().scaleEffect(0.95)
        } else if state == "needs" {
            Circle().fill(Theme.violet).frame(width: 8, height: 8).accessibilityLabel("Needs you")
        } else if state == "permission" {
            Circle().fill(Color(hex: 0xE0B060)).frame(width: 8, height: 8).accessibilityLabel("Waiting for permission")
        }
    }
}

/// a pinned chat or project; while sorting it has a handle, and the one under your finger is lifted
private struct PinRowView: View {
    let item: PinItem
    let sorting: Bool
    let lifted: Bool
    let lit: Bool
    let now: Date

    var body: some View {
        HStack(spacing: 14) {
            icon.frame(width: 24, height: 24)
            Text(item.title).font(.system(size: 17)).lineLimit(1)
            Spacer(minLength: 8)
            mark
            if sorting {
                Icons.grip().foregroundStyle(Color(hex: 0x8E8E93))
                    .accessibilityLabel("Drag to reorder")
            }
        }
        .foregroundStyle(MenuView.ink)
        .padding(.horizontal, 12)
        .frame(height: 44)
        .background(lifted ? Color(hex: 0x2A2A2C) : (lit ? Color(hex: 0x1C1C1E) : .clear),
                    in: RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(lifted ? 0.6 : 0), radius: 14, y: 8)
        .scaleEffect(lifted ? 1.03 : 1)
        .padding(.horizontal, 10)
    }

    @ViewBuilder
    private var icon: some View {
        switch item {
        case .chat: Image(systemName: "bubble.left").font(.system(size: 19))
        case .project: Image(systemName: "folder").font(.system(size: 19))
        }
    }

    @ViewBuilder
    private var mark: some View {
        switch item {
        case .chat(let c): StateMark(state: c.state)
        case .project(let p): StateMark(state: p.state == "working" ? "" : p.state, working: p.working > 0)
        }
    }
}
