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
/// (its button, or a swipe right anywhere in the chat) and the chat slides over to the right, dimmed. A swipe left
/// anywhere (the menu or the chat's strip) closes it the same way.
struct MainView: View {
    @Environment(AppModel.self) private var model
    @State private var current: Current
    @State private var path = NavigationPath()
    @State private var menuOpen: Bool
    /// how far a swipe has moved the chat so far (0 when nothing moves)
    @State private var drag: CGFloat = 0
    /// a pin is lifted for sorting: a sideways move drags the pin, not the menu
    @State private var pinLifted = false
    /// when the menu's swipe moved and let go: the row it started on doesn't count as tapped
    @State private var swipeClock = SwipeClock()
    @State private var temporary: Bool
    /// the temporary chat once its first message made it: deleted when you leave
    @State private var temporaryId: String?
    /// the chat the new chat became, for the menu's highlight
    @State private var madeId: String?
    @State private var showSettings = false
    @State private var opened = 0
    /// the stack starts at Projects (its page and a project's chat open from it take the menu's swipe too)
    @State private var onProjects = false

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
        if Demo.isOn, let i = args.firstIndex(of: "-place"), i + 1 < args.count, let p = Place(rawValue: args[i + 1]) {
            var path = NavigationPath([p])
            if let j = args.firstIndex(of: "-push"), j + 1 < args.count { path.append(ChatRoute(id: args[j + 1])) }
            _path = State(initialValue: path)
            _onProjects = State(initialValue: p == .projects)
        }
    }

    var body: some View {
        GeometryReader { geo in
            let swipe = MenuDrag(width: max(geo.size.width - 91, 240))
            let width = swipe.width
            let x = swipe.x(open: menuOpen, dx: drag)
            ZStack(alignment: .topLeading) {
                MenuView(current: shownId, open: menuOpen,
                         pick: { c in if !swipeClock.recent { pick(c) } },
                         newChat: { if !swipeClock.recent { newChat() } },
                         place: { p in if !swipeClock.recent { go(p) } },
                         settings: { if !swipeClock.recent { showSettings = true } },
                         lifting: { pinLifted = $0 })
                    .frame(width: width)
                    .offset(x: (x - width) * 0.25)
                    .opacity(menuOpen || x > 0 ? 1 : 0)
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
                                .accessibilityLabel("Close the menu")
                                .accessibilityAddTraits(.isButton)
                                .accessibilityIdentifier("closeMenu")
                        }
                    }
                    .offset(x: x)
            }
            .background(Color.black)
            // one pan over the whole screen opens and closes, so a swipe starting anywhere (the menu's rows, its
            // empty space, the chat's strip) follows the finger the same way
            .gesture(MenuSwipe(closing: menuOpen,
                               enabled: menuOpen ? !pinLifted : path.count <= (onProjects ? 1 : 0),
                               changed: { dx in
                                   swipeClock.moving = true
                                   drag = dx
                               },
                               ended: { dx, v in
                                   swipeClock.letGo()
                                   let open = swipe.endsOpen(open: menuOpen, dx: dx, velocity: v)
                                   withAnimation(.snappy(duration: 0.3)) {
                                       drag = 0
                                       if open && !menuOpen { openMenu() }
                                       if !open { menuOpen = false }
                                   }
                               }))
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
                        ProjectsPage(openMenu: { withAnimation(.snappy(duration: 0.3)) { openMenu() } })
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
                              menuIsOpen: { menuOpen || !path.isEmpty })
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

    /// a chat (or a project's main chat) from the menu
    private func pick(_ c: Current) {
        _ = dropTemporary()
        temporary = false
        if c != current {
            current = c
            madeId = nil
        }
        path = NavigationPath()
        onProjects = false
        close()
    }

    private func newChat() {
        _ = dropTemporary()
        temporary = false
        madeId = nil
        current = .fresh
        path = NavigationPath()
        onProjects = false
        close()
    }

    private func go(_ p: Place) {
        path = NavigationPath([p])
        onProjects = p == .projects
        close()
    }

    /// the chat on screen was deleted or archived
    private func leaveGone() {
        temporaryId = nil
        temporary = false
        madeId = nil
        current = .fresh
        path = NavigationPath()
        onProjects = false
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

/// A row's button fires when the finger lifts over it, even after a swipe across it (seen on the old menu: a flick
/// to close from Gup Bot's row opened Gup Bot). The menu's actions check this first and skip what a swipe ended.
final class SwipeClock {
    var moving = false
    private var endedAt = Date.distantPast

    func letGo() {
        moving = false
        endedAt = Date()
    }

    /// a swipe is under way or let go a moment ago
    var recent: Bool { moving || Date().timeIntervalSince(endedAt) < 0.4 }
}

/// Where the chat sits while a swipe moves it, and where it ends up when the finger lets go. Opening and closing
/// feel the same: the chat follows the finger 1:1, and letting go past 35% of the way, or a flick (500 pt/s) that
/// way, finishes the move; a flick back cancels it.
struct MenuDrag {
    /// how far the chat moves over when the menu is open
    let width: CGFloat

    static let flick: CGFloat = 500
    static let past: CGFloat = 0.35

    /// the chat's left edge for the menu's state and how far the finger has moved since the swipe began
    func x(open: Bool, dx: CGFloat) -> CGFloat {
        min(max((open ? width : 0) + dx, 0), width)
    }

    /// whether the menu is open once a swipe of `dx` lets go at `velocity` (both in points, right is positive)
    func endsOpen(open: Bool, dx: CGFloat, velocity: CGFloat) -> Bool {
        if abs(velocity) >= Self.flick { return velocity > 0 }
        let moved = open ? -dx : dx
        return moved > width * Self.past ? !open : open
    }
}

/// The menu's swipe (5a): a UIKit pan over the whole screen, so it works beside the scroll views and the pin's long
/// press. Closed, it starts on a mostly sideways move to the right; open, on one to the left. It measures in the
/// window's points, so the chat moving under the finger doesn't shrink the swipe. Once a close starts, the scroll
/// views under the finger stop, so the menu list doesn't drift up or down while it slides away.
struct MenuSwipe: UIGestureRecognizerRepresentable {
    /// the menu is open: a swipe left closes it
    var closing: Bool
    var enabled: Bool
    var changed: (CGFloat) -> Void
    var ended: (CGFloat, CGFloat) -> Void

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator { Coordinator() }

    func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
        let g = UIPanGestureRecognizer()
        g.delegate = context.coordinator
        g.cancelsTouchesInView = false
        g.maximumNumberOfTouches = 1
        return g
    }

    func updateUIGestureRecognizer(_ g: UIPanGestureRecognizer, context: Context) {
        // read when a swipe would start (the menu doesn't open or close while one is under way)
        context.coordinator.closing = closing
        g.isEnabled = enabled
    }

    func handleUIGestureRecognizerAction(_ g: UIPanGestureRecognizer, context: Context) {
        let dx = g.translation(in: nil).x
        switch g.state {
        case .began:
            if context.coordinator.closing { context.coordinator.stopScrolling() }
            changed(dx)
        case .changed:
            if context.coordinator.closing { context.coordinator.stopScrolling() }
            changed(dx)
        case .ended: ended(dx, g.velocity(in: nil).x)
        case .cancelled, .failed: ended(0, 0)
        default: break
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var closing = false
        /// the scroll views' pans this touch also reaches
        private var scrolls: [WeakPan] = []

        func gestureRecognizerShouldBegin(_ g: UIGestureRecognizer) -> Bool {
            guard let pan = g as? UIPanGestureRecognizer else { return false }
            let v = pan.velocity(in: nil)
            let sideways = abs(v.x) > 1.5 * abs(v.y)
            return sideways && (closing ? v.x < 0 : v.x > 0)
        }

        func gestureRecognizer(_ g: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            if let pan = other as? UIPanGestureRecognizer, let scroll = other.view as? UIScrollView,
               scroll.panGestureRecognizer === pan {
                scrolls.removeAll { $0.pan == nil || $0.pan === pan }
                scrolls.append(WeakPan(pan: pan))
            }
            return true
        }

        /// cancels the scroll views' pans (turning one off and on again ends its touch; it stays where it is)
        func stopScrolling() {
            for w in scrolls {
                guard let pan = w.pan, pan.state == .began || pan.state == .changed else { continue }
                pan.isEnabled = false
                pan.isEnabled = true
            }
        }
    }

    struct WeakPan {
        weak var pan: UIPanGestureRecognizer?
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
