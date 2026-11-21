import SwiftUI
import UIKit
import UIKit.UIGestureRecognizerSubclass

/// a229: puts ChatScroll's rules (GupKit) on a chat's scroll view. SwiftUI's ScrollView is a UIScrollView underneath;
/// the keeper finds it and works on it directly, because only UIKit says exactly when a finger is down and lets the
/// offset move in the same layout pass the content changed in:
/// - a touch watcher (a gesture recognizer that never wins) tells when a finger is on the chat;
/// - the content's size (KVO) keeps a following chat at the bottom before the frame is drawn;
/// - each row of the chat reports its top in the content (`.scrollRow`), so content changing size above the line
///   being read moves the offset by as much.
/// The chat (ChatView, TransferPage) uses `.keepsScroll(keeper)` on its ScrollView and `.scrollContent(keeper)` on
/// the stack inside it. Nothing else may scroll it on its own.
@MainActor
final class ChatScrollKeeper: NSObject, UIGestureRecognizerDelegate {
    static let space = "chatScrollContent"
    /// a236 diagnostics for one CI run (the streaming test turns it on): the gesture's steps and the rest's decision
    nonisolated(unsafe) static var trace = false

    private func note(_ what: String) {
        guard Self.trace, let sv = view else { return }
        print(String(format: "a236 %@: offset %.1f lowest %.1f gap %.1f size %.1f tracking %d decel %d following %d left %d released %d",
                     what, sv.contentOffset.y, lowest, gap, sv.contentSize.height, sv.isTracking ? 1 : 0,
                     sv.isDecelerating ? 1 : 0, logic.following ? 1 : 0, logic.leftAtBottom ? 1 : 0, logic.released ? 1 : 0))
    }

    private(set) var logic = ChatScroll()
    private weak var view: UIScrollView?
    private var watches: [NSKeyValueObservation] = []
    private weak var watcher: TouchWatch?

    var following: Bool { logic.following }

    func attach(_ sv: UIScrollView) {
        guard view !== sv else { return }
        if let old = view, let w = watcher { old.removeGestureRecognizer(w) }
        watches = []
        view = sv
        let touch = TouchWatch(target: nil, action: nil)
        touch.keeper = self
        touch.delegate = self
        touch.cancelsTouchesInView = false
        touch.delaysTouchesBegan = false
        touch.delaysTouchesEnded = false
        sv.addGestureRecognizer(touch)
        watcher = touch
        watches.append(sv.observe(\.contentSize, options: [.new]) { [weak self] _, _ in
            MainActor.assumeIsolated { self?.resized() }
        })
        watches.append(sv.observe(\.contentOffset, options: [.new]) { [weak self] _, _ in
            MainActor.assumeIsolated { self?.scrolled() }
        })
        scrolled()
        resized()
    }

    // MARK: what the chat tells it

    /// your own message went: to the bottom, following
    func follow() { perform(logic.follow()) }

    /// the app is about to move what you look at (a fold opens, a jump to a message): stop following
    func hold() { logic.hold() }

    /// a230: brings a row near the top of the screen (Open chat with the card in view) and holds there; a row at the
    /// end stays following at the bottom. False until the row has told where it is.
    @discardableResult
    func show(_ id: String) -> Bool {
        guard let sv = view else { return false }
        if fits { return logic.rows[id] != nil }
        guard let want = logic.reveal(id) else { return false }
        let y = CGFloat(want) - sv.adjustedContentInset.top
        if y >= lowest - CGFloat(ChatScroll.slack) {
            perform(logic.follow())
        } else {
            sv.contentOffset.y = max(y, highest)
        }
        return true
    }

    /// the content, the screen or the insets changed size (the keyboard, a rotation, new text)
    func resized() {
        guard let sv = view else { return }
        if logic.touching || logic.released { note("resized") }
        // content that shrank leaves UIKit's offset past its end (it doesn't clamp): back to the end, unless a finger
        // or a bounce has it
        if !sv.isTracking, !sv.isDecelerating, sv.contentOffset.y > lowest + 0.5 {
            sv.contentOffset.y = lowest
        }
        perform(logic.resized(gap: gap))
    }

    /// SwiftUI says the scroll came to rest
    func settled() {
        guard let sv = view, !sv.isTracking, !sv.isDecelerating else { return }
        let was = logic.released
        let m = logic.rest(top: top, gap: gap)
        if was { note("rest -> \(m)") }
        perform(m)
    }

    func row(_ id: String, top rowTop: CGFloat) {
        perform(logic.row(id, top: Double(rowTop), readingTop: top))
    }

    func rowGone(_ id: String) {
        logic.rowGone(id, readingTop: top)
    }

    // MARK: touches

    fileprivate func touchDown() {
        logic.touchDown(top: top, gap: gap)
        note("down")
    }

    fileprivate func touchUp() {
        logic.touchUp()
        note("up")
        // a fling or a bounce starts as the finger lifts; SwiftUI's idle phase says when it ends
        DispatchQueue.main.async { [weak self] in self?.settled() }
    }

    func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        true
    }

    // MARK: the scroll view

    /// the content's y at the top of the readable area
    private var top: Double {
        guard let sv = view else { return 0 }
        return Double(sv.contentOffset.y + sv.adjustedContentInset.top)
    }

    private var lowest: CGFloat {
        guard let sv = view else { return 0 }
        let i = sv.adjustedContentInset
        return max(-i.top, sv.contentSize.height + i.bottom - sv.bounds.height)
    }

    private var highest: CGFloat {
        -(view?.adjustedContentInset.top ?? 0)
    }

    /// the whole content fits on screen: SwiftUI sets it at the bottom (`.alignment`), nothing to keep
    private var fits: Bool {
        guard let sv = view else { return true }
        let i = sv.adjustedContentInset
        return sv.contentSize.height + i.top + i.bottom <= sv.bounds.height + 0.5
    }

    /// how far the content's end is below the bottom of the screen
    private var gap: Double {
        guard let sv = view, !fits else { return 0 }
        return Double(lowest - sv.contentOffset.y)
    }

    private func scrolled() {
        logic.scrolled(top: top)
        let left = logic.leftAtBottom
        logic.moved(top: top, gap: gap)
        if logic.leftAtBottom != left { note("moved, left at bottom \(logic.leftAtBottom)") }
    }

    private func perform(_ move: ChatScroll.Move) {
        guard let sv = view, !fits else { return }
        switch move {
        case .none:
            return
        case .bottom(let animated):
            let y = lowest
            if animated {
                sv.setContentOffset(CGPoint(x: sv.contentOffset.x, y: y), animated: true)
            } else if abs(sv.contentOffset.y - y) > 0.5 {
                sv.contentOffset.y = y
            }
        case .by(let d):
            let y = min(max(sv.contentOffset.y + CGFloat(d), highest), max(highest, lowest))
            if abs(sv.contentOffset.y - y) > 0.5 { sv.contentOffset.y = y }
        }
    }
}

/// Tells the keeper when the first finger comes down on the chat and when the last one leaves. It never recognizes
/// and never holds a touch back, so scrolling, taps, presses and text selection work as before.
private final class TouchWatch: UIGestureRecognizer {
    weak var keeper: ChatScrollKeeper?
    private var down = 0

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        let first = down == 0
        down += touches.count
        if first { keeper?.touchDown() }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) { lift(touches.count) }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) { lift(touches.count) }

    private func lift(_ n: Int) {
        down = max(0, down - n)
        if down == 0 {
            keeper?.touchUp()
            state = .failed
        }
    }

    override func reset() {
        if down > 0 {
            down = 0
            keeper?.touchUp()
        }
    }

    override func canPrevent(_ other: UIGestureRecognizer) -> Bool { false }
    override func canBePrevented(by other: UIGestureRecognizer) -> Bool { false }
}

/// Finds the UIScrollView a SwiftUI ScrollView is drawn with (this sits inside its content).
private struct ScrollViewFinder: UIViewRepresentable {
    let found: (UIScrollView) -> Void

    func makeUIView(context: Context) -> FinderView {
        let v = FinderView()
        v.found = found
        v.isUserInteractionEnabled = false
        return v
    }

    func updateUIView(_ v: FinderView, context: Context) {
        v.found = found
    }

    final class FinderView: UIView {
        var found: ((UIScrollView) -> Void)?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            guard window != nil else { return }
            var v = superview
            while let s = v, !(s is UIScrollView) { v = s.superview }
            if let sv = v as? UIScrollView { found?(sv) }
        }
    }
}

extension EnvironmentValues {
    @Entry var chatScroll: ChatScrollKeeper? = nil
}

private struct ScrollRow: ViewModifier {
    let id: String
    @Environment(\.chatScroll) private var keeper

    func body(content: Content) -> some View {
        if let keeper {
            content
                .onGeometryChange(for: CGFloat.self) { $0.frame(in: .named(ChatScrollKeeper.space)).minY } action: { y in
                    keeper.row(id, top: y)
                }
                .onDisappear { keeper.rowGone(id) }
        } else {
            content
        }
    }
}

extension View {
    /// a229: a part of a chat (a turn's prompt, fold, block; a message) that stays where it is when content above it
    /// changes size
    func scrollRow(_ id: String) -> some View {
        modifier(ScrollRow(id: id))
    }

    /// a229: on a chat's ScrollView: it opens at the bottom, short chats sit at the bottom, and the keeper does the
    /// rest (no other scroll anchor or position on it)
    func keepsScroll(_ keeper: ChatScrollKeeper) -> some View {
        self
            .defaultScrollAnchor(.bottom, for: .initialOffset)
            .defaultScrollAnchor(.bottom, for: .alignment)
            .onScrollPhaseChange { _, phase in
                if phase == .idle { keeper.settled() }
            }
            .onScrollGeometryChange(for: [CGFloat].self) { g in
                [g.containerSize.height, g.contentInsets.top, g.contentInsets.bottom, g.contentSize.height]
            } action: { _, _ in
                keeper.resized()
            }
            .environment(\.chatScroll, keeper)
    }

    /// a229: on the stack inside a chat's ScrollView: the rows' coordinates and the way to the scroll view
    func scrollContent(_ keeper: ChatScrollKeeper) -> some View {
        self
            .coordinateSpace(.named(ChatScrollKeeper.space))
            .background(ScrollViewFinder { keeper.attach($0) })
    }
}
