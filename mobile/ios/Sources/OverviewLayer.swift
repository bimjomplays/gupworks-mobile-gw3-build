import PhotosUI
import SwiftUI
import UIKit

// a141: the project's Overview, option 1 "Sections" (the overview-v2 mockups 1a to 1f). A page that
// slides in from the right over the project's main chat (a swipe left anywhere in the chat, or its Overview button),
// the chat moving a third of the way left and dimming under it; a swipe right or ‹ goes back. Its top: a round
// glass ‹, the project's name, a round glass +, and a glass pill with Overview, Library and Scheduled.

/// What the main screen needs to draw the Overview: the project's main chat on screen registers its store here
/// (ChatView), MainView draws the page over the chat and moves it with the finger.
@MainActor @Observable
final class OverviewHost {
    /// the project whose main chat is on top of the stack (nil: no Overview to open)
    private(set) var store: ProjectStore?
    private(set) var chatId: String?
    private var put: ((String) -> Void)?
    private(set) var open = false
    /// its page is drawn: from the start of a slide in until a slide out has ended (closed, it isn't in the tree)
    private(set) var shown = false
    /// how far in it is while a finger moves it (nil: nothing moves)
    var drag: Double?
    /// what is pushed inside the Overview (a folder, a note, a thread's chat, a schedule)
    var path = NavigationPath()
    var tab: OverviewTab = .overview
    /// the demo's `-slide 0.55`: the page held part of the way in, for 1a's picture
    private let demoSlide: Double?

    init() {
        let args = Demo.args
        if Demo.isOn, let i = args.firstIndex(of: "-slide"), i + 1 < args.count, let s = Double(args[i + 1]) {
            demoSlide = s
        } else {
            demoSlide = nil
        }
        if Demo.isOn, let i = args.firstIndex(of: "-tab"), i + 1 < args.count, let t = OverviewTab(rawValue: args[i + 1]) {
            tab = t
        }
    }

    /// 0 closed, 1 open
    var progress: Double { store == nil ? 0 : drag ?? (open ? 1 : 0) }

    /// the main chat came on top of the stack
    func attach(_ store: ProjectStore, chat: String, put: @escaping (String) -> Void) {
        if self.store !== store {
            path = NavigationPath()
            open = false
            drag = nil
            shown = false
        }
        self.store = store
        chatId = chat
        self.put = put
    }

    /// the main chat left the top of the stack (a thread pushed over it, back to Projects, another chat)
    func detach(_ chat: String) {
        guard chatId == chat else { return }
        store = nil
        chatId = nil
        put = nil
        open = false
        drag = nil
        shown = false
        path = NavigationPath()
    }

    func present() {
        guard store != nil else { return }
        shown = true
        if let s = demoSlide {
            drag = s
            return
        }
        Self.dropKeyboard()
        path = NavigationPath()
        withAnimation(.snappy(duration: 0.35)) { open = true }
    }

    /// back to the chat; `then` runs once the page is out of the way
    func close(then: (() -> Void)? = nil) {
        withAnimation(.snappy(duration: 0.3)) {
            open = false
            drag = nil
        } completion: { [weak self] in self?.hideIfClosed() }
        if let then {
            Task {
                try? await Task.sleep(nanoseconds: 330_000_000)
                then()
            }
        }
    }

    func toggle() { open ? close() : present() }

    /// closes, then puts these words in the main chat's box (+ on Scheduled, an idea's Start it)
    func putInChat(_ text: String) {
        let p = put
        close { p?(text) }
    }

    /// a swipe moves the page
    func moved(_ p: Double) {
        if drag == nil && !open {
            Self.dropKeyboard()
            path = NavigationPath()
        }
        shown = true
        drag = p
    }

    /// the finger let go: the page finishes the move or goes back
    func settle(open o: Bool) {
        withAnimation(.snappy(duration: 0.3)) {
            open = o
            drag = nil
        } completion: { [weak self] in self?.hideIfClosed() }
    }

    private func hideIfClosed() {
        if !open && drag == nil { shown = false }
    }

    static func dropKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}

/// The page itself: its own stack, so a folder, a note, a schedule or a thread's chat opens inside it and Back
/// returns to the Overview.
struct OverviewLayer: View {
    @Bindable var host: OverviewHost
    let store: ProjectStore
    @Environment(AppModel.self) private var model

    var body: some View {
        NavigationStack(path: $host.path) {
            OverviewRoot(host: host, store: store)
                .toolbar(.hidden, for: .navigationBar)
                .navigationDestination(for: OverviewPage.self) { page in
                    switch page {
                    case .newThread: NewThreadView(store: store) { host.path = NavigationPath() }
                    case .threads(let state): ThreadListPage(store: store, state: state)
                    case .schedule(let id): ScheduleDetailPage(store: store, id: id)
                    }
                }
                .navigationDestination(for: LibraryRow.self) { row in
                    if row.kind == "folder" {
                        LibraryFolderView(store: store, row: row, path: $host.path)
                    } else {
                        NoteView(store: store, row: row)
                    }
                }
                .navigationDestination(for: ChatRoute.self) { r in
                    ChatView(id: r.id, pairing: model.pairing, demo: model.demo)
                }
        }
        .environment(\.openChat, { (id: String) in
            if id == host.chatId { host.close() } else { host.path.append(ChatRoute(id: id)) }
        })
        .alert("That didn't work", isPresented: Binding(get: { store.actionError != nil },
                                                       set: { if !$0 { store.actionError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(store.actionError ?? "")
        }
        .alert("Deleted", isPresented: Binding(get: { store.notice != nil }, set: { if !$0 { store.notice = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(store.notice ?? "")
        }
    }
}

/// What the Overview pushes inside its own stack.
enum OverviewPage: Hashable {
    case newThread
    /// every Done or Archived thread
    case threads(String)
    case schedule(String)
}

/// The colours of option 1: near-black page, dark grey cards (the Projects page's).
enum OverviewStyle {
    static let background = Color(hex: 0x111111)
    static let card = Color(hex: 0x1F1F21)
    static let grey = Color(hex: 0x8E8E93)
    static let faint = Color(hex: 0x6C6C70)
    static let line = Color(hex: 0x3A3A3C)
}

/// The root: the glass top over the tab's list, which passes under it.
private struct OverviewRoot: View {
    let host: OverviewHost
    let store: ProjectStore
    @Namespace private var pill
    @State private var pickingPhotos = false
    @State private var pickingFiles = false
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var adding = false

    var body: some View {
        Group {
            switch host.tab {
            case .overview: OverviewTabView(host: host, store: store)
            case .library: LibraryTab(host: host, store: store, adding: adding)
            case .scheduled: ScheduledTab(host: host, store: store)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .safeAreaBar(edge: .top, spacing: 0) { top }
        .background(OverviewStyle.background.ignoresSafeArea())
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
    }

    /// round ‹, the name, round +; the pill under them
    private var top: some View {
        VStack(spacing: 14) {
            ZStack {
                Text(store.view?.name ?? "")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Theme.title)
                    .lineLimit(1)
                    .padding(.horizontal, 64)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("overviewName")
                HStack {
                    Button { host.close() } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 19, weight: .semibold))
                            .foregroundStyle(Theme.rowTitle)
                            .frame(width: 48, height: 48)
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .glassEffect(.regular.interactive(), in: .circle)
                    .accessibilityLabel("Back to the chat")
                    .accessibilityIdentifier("overviewClose")
                    Spacer()
                    plus
                }
            }
            .padding(.horizontal, 16)
            tabs
        }
        .padding(.top, 4)
        .padding(.bottom, 8)
    }

    /// + : a new thread on Overview, photos or files on Library, a new schedule on Scheduled
    @ViewBuilder
    private var plus: some View {
        let icon = Image(systemName: "plus")
            .font(.system(size: 20, weight: .medium))
            .foregroundStyle(Theme.rowTitle)
            .frame(width: 48, height: 48)
            .contentShape(Circle())
        switch host.tab {
        case .overview:
            Button { host.path.append(OverviewPage.newThread) } label: { icon }
                .buttonStyle(.plain)
                .glassEffect(.regular.interactive(), in: .circle)
                .accessibilityLabel("New thread")
                .accessibilityIdentifier("newThread")
        case .library:
            Menu {
                Button("Photos", systemImage: "photo.on.rectangle") { pickingPhotos = true }
                Button("Files", systemImage: "folder") { pickingFiles = true }
            } label: { icon }
                .buttonStyle(.plain)
                .glassEffect(.regular.interactive(), in: .circle)
                .disabled(adding)
                .accessibilityLabel("Add to the Library")
                .accessibilityIdentifier("libraryAdd")
        case .scheduled:
            Button { host.putInChat("New schedule: ") } label: { icon }
                .buttonStyle(.plain)
                .glassEffect(.regular.interactive(), in: .circle)
                .accessibilityLabel("New schedule")
                .accessibilityIdentifier("newSchedule")
        }
    }

    /// the glass pill: exactly Overview, Library, Scheduled
    private var tabs: some View {
        HStack(spacing: 0) {
            ForEach(OverviewTab.allCases) { t in
                let on = host.tab == t
                Button {
                    withAnimation(.snappy(duration: 0.25)) { host.tab = t }
                } label: {
                    Text(t.title)
                        .font(.system(size: 16, weight: on ? .semibold : .regular))
                        .foregroundStyle(on ? Theme.title : Color(hex: 0xC8C8CC))
                        .padding(.horizontal, 18)
                        .frame(height: 40)
                        .background {
                            if on {
                                Capsule().fill(Color.white.opacity(0.14)).matchedGeometryEffect(id: "tab", in: pill)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
                .accessibilityIdentifier("overviewTab-\(t.rawValue)")
            }
        }
        .padding(4)
        .glassEffect(.regular, in: .capsule)
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

/// The Overview's swipe (1a): a UIKit pan over the whole screen like the menu's. Closed, it starts on a mostly
/// sideways move to the left (not when a wide table under the finger can still scroll that way); open, on one to the
/// right. Once it starts the scroll views under the finger stop, and the touch no longer taps what it started on.
struct OverviewSwipe: UIGestureRecognizerRepresentable {
    /// the Overview is open: a swipe right closes it
    var closing: Bool
    var enabled: Bool
    var changed: (CGFloat) -> Void
    var ended: (CGFloat, CGFloat) -> Void

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator { Coordinator() }

    func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
        let g = UIPanGestureRecognizer()
        g.delegate = context.coordinator
        g.cancelsTouchesInView = true
        g.maximumNumberOfTouches = 1
        g.name = "overviewSwipe"
        return g
    }

    func updateUIGestureRecognizer(_ g: UIPanGestureRecognizer, context: Context) {
        context.coordinator.closing = closing
        let moving = g.state == .began || g.state == .changed
        g.isEnabled = enabled
        if moving && !enabled { Task { @MainActor in ended(0, 0) } }
    }

    func handleUIGestureRecognizerAction(_ g: UIPanGestureRecognizer, context: Context) {
        let dx = g.translation(in: nil).x
        switch g.state {
        case .began, .changed:
            context.coordinator.stopScrolling()
            changed(dx)
        case .ended: ended(dx, g.velocity(in: nil).x)
        case .cancelled, .failed: ended(0, 0)
        default: break
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var closing = false
        private weak var touched: UIView?
        private var scrolls: [MenuSwipe.WeakPan] = []

        func gestureRecognizer(_ g: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            touched = touch.view
            return true
        }

        func gestureRecognizerShouldBegin(_ g: UIGestureRecognizer) -> Bool {
            guard let pan = g as? UIPanGestureRecognizer, !MenuSwipe.pinHeld else { return false }
            let v = pan.velocity(in: nil)
            guard abs(v.x) > 1.5 * abs(v.y) else { return false }
            if closing {
                return v.x > 0 && !MenuSwipe.Coordinator.scrollsBack(from: touched)
            }
            return v.x < 0 && !Self.scrollsOn(from: touched)
        }

        /// whether a sideways scroll view under the touch can still scroll on (a swipe left moves it)
        static func scrollsOn(from start: UIView?) -> Bool {
            var v = start
            while let view = v {
                if let s = view as? UIScrollView, s.contentSize.width > s.bounds.width + 1,
                   s.contentOffset.x < s.contentSize.width - s.bounds.width + s.adjustedContentInset.right - 0.5 {
                    return true
                }
                v = view.superview
            }
            return false
        }

        func gestureRecognizer(_ g: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            if other.name == MenuSwipe.pinLift { return false }
            if let pan = other as? UIPanGestureRecognizer, let scroll = other.view as? UIScrollView,
               scroll.panGestureRecognizer === pan {
                scrolls.removeAll { $0.pan == nil || $0.pan === pan }
                scrolls.append(MenuSwipe.WeakPan(pan: pan))
            }
            return true
        }

        /// the page moves sideways only: the lists under the finger stay where they are
        func stopScrolling() {
            for w in scrolls {
                guard let pan = w.pan, pan.state == .began || pan.state == .changed else { continue }
                pan.isEnabled = false
                pan.isEnabled = true
            }
        }
    }
}
