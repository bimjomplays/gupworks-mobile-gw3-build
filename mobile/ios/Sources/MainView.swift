import SwiftUI
import UIKit

/// What the main screen shows: a new chat (5a, fresh each time) or one of the chats.
enum Current: Hashable {
    case new(UUID)
    case chat(String, sheet: Bool)

    static var fresh: Current { .new(UUID()) }
}

/// A place from the menu's top rows, pushed over the chat.
enum Place: String, Hashable, CaseIterable {
    case projects, scheduled, quick, bot

    var title: String {
        switch self {
        case .projects: return "Projects"
        case .scheduled: return "Scheduled"
        case .quick: return "Quick actions"
        case .bot: return "Gup Bot"
        }
    }
}

/// What the main chat needs from the shell around it: the menu, a new chat, the temporary switch.
struct ChatShell {
    var openMenu: () -> Void
    var newChat: () -> Void
    /// the chat went away (deleted or archived): a new chat takes its place
    var leave: () -> Void
    var temporary: Bool
    var toggleTemporary: () -> Void
    /// the new chat was made on the PC by its first message
    var made: (String) -> Void
    /// something waits on you: the menu button's violet dot
    var menuDot: Bool
    /// read when the keyboard would come up: not over an open menu
    var menuIsOpen: () -> Bool = { false }
}

/// 5a-5d: ChatGPT's layout. The app opens on a new chat with the keyboard up; the menu slides out from the left
/// (its button, or a swipe right anywhere in the chat) and the chat slides over to the right, dimmed.
struct MainView: View {
    @Environment(AppModel.self) private var model
    @State private var current: Current
    @State private var path = NavigationPath()
    @State private var menuOpen: Bool
    /// how far a swipe has moved the chat so far (0 when nothing moves)
    @State private var drag: CGFloat = 0
    @State private var temporary: Bool
    /// the temporary chat once its first message made it: deleted when you leave
    @State private var temporaryId: String?
    /// the chat the new chat became, for the menu's highlight
    @State private var madeId: String?
    @State private var showSettings = false
    @State private var opened = 0

    init() {
        let args = ProcessInfo.processInfo.arguments
        // the demo's flags for the screenshot tests
        var start = Current.fresh
        if Demo.isOn, let i = args.firstIndex(of: "-open"), i + 1 < args.count {
            start = .chat(args[i + 1], sheet: args.contains("-sheet"))
        }
        _current = State(initialValue: start)
        _menuOpen = State(initialValue: Demo.isOn && args.contains("-menu"))
        _temporary = State(initialValue: Demo.isOn && args.contains("-temporary"))
    }

    var body: some View {
        GeometryReader { geo in
            let width = max(geo.size.width - 91, 240)
            let x = min(max((menuOpen ? width : 0) + drag, 0), width)
            ZStack(alignment: .topLeading) {
                MenuView(current: shownId, open: menuOpen, pick: pick, newChat: { newChat() },
                         place: { p in go(p) }, settings: { showSettings = true })
                    .frame(width: width)
                    .offset(x: (x - width) * 0.25)
                    .opacity(menuOpen || drag > 0 ? 1 : 0)
                    .accessibilityHidden(!menuOpen)
                    .ignoresSafeArea(.keyboard)
                stack
                    .frame(width: geo.size.width)
                    .clipShape(RoundedRectangle(cornerRadius: x > 0 ? 44 : 0, style: .continuous))
                    .overlay {
                        if x > 0 {
                            RoundedRectangle(cornerRadius: 44, style: .continuous)
                                .stroke(Color(hex: 0x2A2A2A), lineWidth: 1)
                                .ignoresSafeArea()
                            Color.black.opacity(0.42 * x / width)
                                .clipShape(RoundedRectangle(cornerRadius: 44, style: .continuous))
                                .ignoresSafeArea()
                                .contentShape(Rectangle())
                                .onTapGesture { close() }
                                .gesture(closeDrag(width))
                                .accessibilityLabel("Close the menu")
                                .accessibilityAddTraits(.isButton)
                                .accessibilityIdentifier("closeMenu")
                        }
                    }
                    .offset(x: x)
                    .gesture(MenuSwipe(enabled: path.isEmpty && !menuOpen,
                                       changed: { dx in drag = max(0, dx) },
                                       ended: { dx, v in
                                           let opens = dx > width * 0.35 || v > 500
                                           withAnimation(.snappy(duration: 0.3)) {
                                               drag = 0
                                               if opens { openMenu() }
                                           }
                                       }))
            }
            .background(Color.black)
        }
        .sensoryFeedback(.impact(weight: .light), trigger: opened)
        .sheet(isPresented: $showSettings) { SettingsView() }
        .alert("That didn't work", isPresented: Binding(get: { model.actionError != nil },
                                                       set: { if !$0 { model.actionError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.actionError ?? "")
        }
    }

    private var stack: some View {
        NavigationStack(path: $path) {
            root
                .id(current)
                .navigationDestination(for: ChatRoute.self) { r in
                    ChatView(id: r.id, pairing: model.pairing, demo: model.demo, projectSheet: r.sheet)
                }
                .navigationDestination(for: Place.self) { p in
                    if p == .projects {
                        ProjectsPage { id in pick(.chat(id, sheet: true)) }
                    } else {
                        ComingSoonPage(place: p)
                    }
                }
        }
        .environment(\.openChat, { (id: String) in path.append(ChatRoute(id: id)) })
    }

    @ViewBuilder
    private var root: some View {
        let shell = ChatShell(openMenu: { withAnimation(.snappy(duration: 0.3)) { openMenu() } },
                              newChat: { newChat() },
                              leave: { leaveGone() },
                              temporary: temporary,
                              toggleTemporary: { temporary.toggle() },
                              made: { id in
                                  madeId = id
                                  if temporary { temporaryId = id }
                              },
                              menuDot: model.needsYou,
                              menuIsOpen: { menuOpen })
        switch current {
        case .new:
            ChatView(id: nil, pairing: model.pairing, demo: model.demo, shell: shell)
        case .chat(let id, let sheet):
            ChatView(id: id, pairing: model.pairing, demo: model.demo, projectSheet: sheet, shell: shell)
        }
    }

    /// the chat on screen, for the menu's highlight
    private var shownId: String? {
        switch current {
        case .new: return madeId
        case .chat(let id, _): return id
        }
    }

    private func openMenu() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        // leaving a temporary chat deletes it (5b): a fresh new chat waits behind the menu
        if dropTemporary() { current = .fresh }
        menuOpen = true
        opened += 1
    }

    private func close() {
        withAnimation(.snappy(duration: 0.3)) {
            menuOpen = false
            drag = 0
        }
    }

    private func closeDrag(_ width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { g in drag = min(0, g.translation.width) }
            .onEnded { g in
                let closes = g.translation.width < -width * 0.3 || g.predictedEndTranslation.width < -width * 0.5
                withAnimation(.snappy(duration: 0.3)) {
                    drag = 0
                    if closes { menuOpen = false }
                }
            }
    }

    /// a chat (or a project's main chat) from the menu
    private func pick(_ c: Current) {
        _ = dropTemporary()
        temporary = false
        if c != current {
            current = c
            madeId = nil
        }
        path = NavigationPath()
        close()
    }

    private func newChat() {
        _ = dropTemporary()
        temporary = false
        madeId = nil
        current = .fresh
        path = NavigationPath()
        close()
    }

    private func go(_ p: Place) {
        path = NavigationPath([p])
        close()
    }

    /// the chat on screen was deleted or archived
    private func leaveGone() {
        temporaryId = nil
        temporary = false
        madeId = nil
        current = .fresh
        path = NavigationPath()
    }

    /// Deletes the temporary chat if one was made; true when it did.
    private func dropTemporary() -> Bool {
        guard let id = temporaryId else { return false }
        temporaryId = nil
        temporary = false
        madeId = nil
        Task { await model.delete(id) }
        return true
    }
}

/// A swipe right anywhere in the chat opens the menu (5a). A UIKit pan, so it works beside the chat's own scrolling:
/// it starts only on a mostly sideways move to the right.
struct MenuSwipe: UIGestureRecognizerRepresentable {
    var enabled: Bool
    var changed: (CGFloat) -> Void
    var ended: (CGFloat, CGFloat) -> Void

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator { Coordinator() }

    func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
        let g = UIPanGestureRecognizer()
        g.delegate = context.coordinator
        g.cancelsTouchesInView = false
        return g
    }

    func updateUIGestureRecognizer(_ g: UIPanGestureRecognizer, context: Context) {
        g.isEnabled = enabled
    }

    func handleUIGestureRecognizerAction(_ g: UIPanGestureRecognizer, context: Context) {
        let dx = g.translation(in: g.view).x
        switch g.state {
        case .began, .changed: changed(dx)
        case .ended: ended(dx, g.velocity(in: g.view).x)
        case .cancelled, .failed: ended(0, 0)
        default: break
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        func gestureRecognizerShouldBegin(_ g: UIGestureRecognizer) -> Bool {
            guard let pan = g as? UIPanGestureRecognizer else { return false }
            let v = pan.velocity(in: pan.view)
            return v.x > 0 && abs(v.x) > 1.5 * abs(v.y)
        }

        func gestureRecognizer(_ g: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            true
        }
    }
}

/// The menu's Projects: every project in the desktop sidebar's order and folders; a tap opens its main chat with
/// its threads (D9). Long-press to pin one to the menu.
struct ProjectsPage: View {
    @Environment(AppModel.self) private var model
    let open: (String) -> Void
    @State private var openFolders: [String: Bool] = [:]

    var body: some View {
        List {
            if let home = model.home {
                ForEach(ProjectLayout.rows(home.projects, layout: home.layout, open: openFolders)) { row in
                    switch row {
                    case .folder(let f, let count):
                        FolderRowView(folder: f, count: count, open: openFolders[f.id] ?? !f.collapsed)
                            .onTapGesture {
                                withAnimation { openFolders[f.id] = !(openFolders[f.id] ?? !f.collapsed) }
                            }
                            .accessibilityAddTraits(.isButton)
                            .accessibilityIdentifier("folder-\(f.name)")
                    case .project(let p, let inFolder):
                        ProjectRowView(project: p)
                            .padding(.leading, inFolder ? 22 : 0)
                            .onTapGesture { if let id = p.mainChatId { open(id) } }
                            .accessibilityAddTraits(p.mainChatId == nil ? [] : .isButton)
                            .contextMenu {
                                let pinned = model.isPinned(project: p.id)
                                Button(pinned ? "Unpin" : "Pin", systemImage: pinned ? "pin.slash" : "pin") {
                                    Task { await model.togglePin(project: p.id) }
                                }
                            }
                    }
                }
                if home.projects.isEmpty {
                    Text(home.projectsError.map { "Projects can't be read right now (\($0))." } ?? "No projects yet.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.secondary)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
            } else {
                ProgressView().frame(maxWidth: .infinity).padding(.vertical, 40)
                    .listRowBackground(Color.clear)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .refreshable { await model.refresh() }
        .navigationTitle("Projects")
        .navigationBarTitleDisplayMode(.large)
    }
}

/// Scheduled, Quick actions and Gup Bot: places for what comes next.
struct ComingSoonPage: View {
    let place: Place

    var body: some View {
        VStack(spacing: 12) {
            MenuIcon(place: place).foregroundStyle(Theme.secondary).scaleEffect(1.6).padding(.bottom, 6)
            Text(place.title).font(.system(size: 20, weight: .semibold)).foregroundStyle(Theme.title)
            Text("Coming soon").font(.system(size: 16)).foregroundStyle(Theme.secondary)
                .accessibilityIdentifier("comingSoon")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background)
        .navigationTitle(place.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// a place's icon, as in the menu
struct MenuIcon: View {
    let place: Place

    var body: some View {
        switch place {
        case .projects: Image(systemName: "folder").font(.system(size: 19))
        case .scheduled: Image(systemName: "clock").font(.system(size: 19))
        case .quick: Image(systemName: "bolt").font(.system(size: 19))
        case .bot: Icons.bot(size: 23)
        }
    }
}
