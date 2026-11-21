import XCTest
import UIKit
@testable import GupWorks3

/// a229: the chat goes only where the finger takes it. Scrolled up, or with a finger on the screen, nothing moves it
/// (a reply streaming in, the keyboard, a fold opening above, older turns loading at the top); at the bottom, left
/// alone, it follows new text. The demo's `-stream` reply grows a line every 0.4 s (160 of them); with `-stepped` it
/// grows only when the test lets lines in (`lines(k)`), so a test that needs a line at an exact moment (under a finger
/// at the bottom) steps it instead of racing the timer (a236). `-long` is the same reply done, `-older` loads older
/// pages at the top (ChatStore's demo).
@MainActor
final class ChatScrollTests: XCTestCase {
    private nonisolated(unsafe) var started = Date()

    override nonisolated func setUp() {
        started = Date()
        continueAfterFailure = false
    }

    override nonisolated func tearDown() {
        MainActor.assumeIsolated {
            if let run = testRun, run.failureCount > 0, let app = App.current {
                let name = name.components(separatedBy: " ").last?.trimmingCharacters(in: CharacterSet(charactersIn: "]")) ?? "test"
                app.shot("fail-\(name)")
                print("SCREEN at the failure of \(name):\n\(app.debugDescription)")
            }
            App.current?.close()
            Timing.report(name, Date().timeIntervalSince(started))
        }
    }

    private let gallery = "00000009-1111-4222-8333-000000000009"

    private func open(_ flags: [String]) -> App {
        let app = App(["-open", gallery] + flags, test: self)
        XCTAssertTrue(app.descendants(matching: .any)["chatTitle"].waitForExistence(timeout: 20))
        XCTAssertTrue(poll(15) { self.rect(app, "Step 3 of the plan") != nil }, "the plan shows")
        return app
    }

    /// where `text` is drawn on screen: its line inside a text view, or the element whose label has it
    private func rect(_ app: App, _ text: String) -> CGRect? {
        for n in Tree.nodes() {
            if let tv = n.obj as? UITextView, let r = tv.text.range(of: text) {
                let ns = NSRange(r, in: tv.text)
                guard let a = tv.position(from: tv.beginningOfDocument, offset: ns.location),
                      let b = tv.position(from: a, offset: ns.length),
                      let range = tv.textRange(from: a, to: b) else { continue }
                return tv.convert(tv.firstRect(for: range), to: nil)
            }
            if n.label.contains(text) { return n.frame }
        }
        return nil
    }

    /// the chat's own scroll view (the tallest; text views don't count)
    private func chatScroll() -> UIScrollView? {
        Tree.views(UIScrollView.self).filter { !($0 is UITextView) }.max { $0.contentSize.height < $1.contentSize.height }
    }

    /// a line of the plan in the middle of the screen, to watch
    private func visibleStep(_ app: App) -> (String, CGRect)? {
        let h = app.frame.height
        for n in 1...160 {
            let s = "Step \(n) of the plan"
            if let r = rect(app, s), r.minY > 170, r.maxY < h - 280 { return (s, r) }
        }
        return nil
    }

    /// the newest line of the plan drawn so far
    private func newestStep(_ app: App) -> (Int, CGRect)? {
        for n in stride(from: 160, through: 1, by: -1) {
            if let r = rect(app, "Step \(n) of the plan") { return (n, r) }
        }
        return nil
    }

    private func box(_ app: App) -> Element {
        app.textFields["composer"].exists ? app.textFields["composer"] : app.textViews["composer"]
    }

    /// the newest line sits on screen just above the box
    private func atBottom(_ app: App, _ what: String) {
        let ok = poll(3) {
            guard let (_, r) = self.newestStep(app) else { return false }
            return r.maxY <= self.box(app).frame.minY + 4 && r.minY > 120
        }
        XCTAssertTrue(ok, "\(what): the newest line shows above the box; \(String(describing: newestStep(app))), box \(box(app).frame)")
    }

    /// drags the chat down by `fraction` of the screen (older text comes into view), held at the end: no fling
    private func scrollUp(_ app: App, by fraction: CGFloat = 0.3) {
        let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3))
        let to = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3 + fraction))
        from.press(forDuration: 0.05, thenDragTo: to, withVelocity: Velocity(rawValue: 1500), thenHoldForDuration: 0.2)
    }

    private func scrollDown(_ app: App, by fraction: CGFloat = 0.3) {
        let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3 + fraction))
        let to = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3))
        from.press(forDuration: 0.05, thenDragTo: to, withVelocity: Velocity(rawValue: 1500), thenHoldForDuration: 0.2)
    }

    /// `line` hasn't moved since `before`
    private func stays(_ app: App, _ text: String, _ before: CGRect, _ what: String,
                       file: StaticString = #filePath, line: UInt = #line) {
        guard let now = rect(app, text) else { return XCTFail("\(text) is gone (\(what))", file: file, line: line) }
        XCTAssertEqual(now.minY, before.minY, accuracy: 1.5, "\(what): \(text) moved from \(before.minY) to \(now.minY)",
                       file: file, line: line)
    }

    /// at the bottom and left alone, the chat follows the reply as it streams in
    func testFollowsAtTheBottom() {
        let app = open(["-stream"])
        for k in 0..<3 {
            spin(1.2)
            atBottom(app, "following, check \(k + 1)")
        }
        App.current?.shot("a229-following")
    }

    // MARK: a236: the reply stepped by the test (`-stream -stepped`), not raced

    /// opens the gallery chat with the demo reply waiting for the test, and lets its first `first` lines in
    private func openStepped(_ first: Int) -> App {
        ChatStore.demoStreaming = nil
        let app = App(["-open", gallery, "-stream", "-stepped"], test: self)
        XCTAssertTrue(app.descendants(matching: .any)["chatTitle"].waitForExistence(timeout: 20))
        XCTAssertTrue(poll(10) { ChatStore.demoStreaming != nil }, "the demo reply waits for the test")
        lines(first)
        XCTAssertTrue(poll(15) { self.rect(app, "Step \(first) of the plan") != nil }, "the plan shows")
        spin(0.5)
        return app
    }

    /// the reply's next `k` lines arrive, then a moment for the chat to lay them out
    private func lines(_ k: Int) {
        ChatStore.demoStreaming?.demoStreamNext(k)
        spin(0.4)
    }

    /// the lowest offset (the content's end at the bottom of the screen) and how far the end is below the screen
    private func lowest(_ sv: UIScrollView) -> CGFloat {
        sv.contentSize.height + sv.adjustedContentInset.bottom - sv.bounds.height
    }

    private func gap(_ sv: UIScrollView) -> CGFloat { lowest(sv) - sv.contentOffset.y }

    /// where the back-to-the-bottom drags start: the middle, low on the screen (at the right edge a finger takes the
    /// scroll indicator and scrubs the chat the other way: a236's first CI run)
    private func start(_ app: App) -> CGPoint { CGPoint(x: app.frame.width * 0.5, y: app.frame.height * 0.75) }

    /// the finger that's down moves up by `dy` points (the content goes up, toward its end), slowly, then holds still
    private func fingerUp(by dy: CGFloat, _ app: App, _ p: inout CGPoint) {
        p.y -= dy
        XCTAssertNoThrow(try app.fingers?.fingerMove(to: p, duration: max(0.1, Double(abs(dy)) / 400)))
        spin(0.3)
    }

    /// scrolled up while the reply streams in: the line being read stays where it is. Then back to the bottom with a
    /// finger while it still streams: the finger reaches the end, lines arrive under it, it goes on a little toward
    /// the end (now short of the new end) and lets go: it follows again.
    func testStreamingWhileScrolledUp() {
        let app = openStepped(20)
        atBottom(app, "opened while streaming")
        scrollUp(app)
        spin(0.5)
        guard let (line, before) = visibleStep(app) else { return XCTFail("no line of the plan on screen") }
        lines(6)
        XCTAssertEqual(ChatStore.demoStreaming?.demoStreamLines, 26, "the reply went on streaming")
        stays(app, line, before, "streaming while scrolled up")
        App.current?.shot("a229-streaming-scrolled-up")

        guard let sv = chatScroll(), app.fingers != nil else { return XCTFail("no chat scroll view or no touches") }
        sv.setContentOffset(CGPoint(x: 0, y: lowest(sv) - 120), animated: false)
        spin(0.3)
        var p = start(app)
        XCTAssertNoThrow(try app.fingers?.fingerDown(at: p))
        spin(0.1)
        fingerUp(by: 240, app, &p)
        XCTAssertLessThanOrEqual(gap(sv), ChatScroll.slack, "the finger took it to the end (or past it)")
        lines(4)
        XCTAssertGreaterThan(gap(sv), ChatScroll.reach, "the end moved on under the finger")
        fingerUp(by: 20, app, &p)
        let short = gap(sv)
        XCTAssertNoThrow(try app.fingers?.fingerUp())
        spin(1)
        lines(3)
        atBottom(app, "back at the bottom (let go \(short) pt above the end after reaching it)")
        lines(3)
        atBottom(app, "and following")
    }

    /// dragged down toward the end while lines arrive, and let go a thumb's miss (about 35 pt) above it: follows
    func testLandsJustShortWhileStreaming() {
        let app = openStepped(20)
        scrollUp(app)
        spin(0.5)
        guard let sv = chatScroll(), app.fingers != nil else { return XCTFail("no chat scroll view or no touches") }
        sv.setContentOffset(CGPoint(x: 0, y: lowest(sv) - 250), animated: false)
        spin(0.3)
        var p = start(app)
        XCTAssertNoThrow(try app.fingers?.fingerDown(at: p))
        spin(0.1)
        fingerUp(by: 120, app, &p)
        lines(2)
        fingerUp(by: gap(sv) - 35, app, &p)
        let short = gap(sv)
        XCTAssertTrue(short > ChatScroll.slack && short <= ChatScroll.reach, "let go \(short) pt above the end")
        XCTAssertNoThrow(try app.fingers?.fingerUp())
        spin(1)
        lines(3)
        atBottom(app, "let go \(short) pt above the moving end")
        lines(3)
        atBottom(app, "and following")
    }

    /// a finger resting on the chat (no drag) while the reply streams in: nothing moves under it; let go at the
    /// bottom, it follows again
    func testFingerOnTheScreen() {
        let app = open(["-stream"])
        XCTAssertTrue(poll(10) { self.rect(app, "Step 5 of the plan") != nil })
        spin(0.5)
        // the right margin, beside the text: a press there is the scroll view's only
        let p = CGPoint(x: app.frame.width - 8, y: app.frame.height * 0.45)
        guard let fingers = app.fingers else { return XCTFail("no touches") }
        XCTAssertNoThrow(try fingers.fingerDown(at: p))
        spin(0.3)
        guard let (line, before) = visibleStep(app) else {
            try? fingers.fingerUp()
            return XCTFail("no line of the plan on screen")
        }
        spin(2.0)
        let during = rect(app, line)
        XCTAssertNoThrow(try fingers.fingerUp())
        XCTAssertNotNil(during)
        XCTAssertEqual(during?.minY ?? 0, before.minY, accuracy: 1.5,
                       "finger on the screen: \(line) moved from \(before.minY) to \(during?.minY ?? -1)")
        spin(1.5)
        atBottom(app, "let go at the bottom")
    }

    /// scrolled up, the keyboard coming up doesn't move the chat; at the bottom the newest line stays above the box
    func testKeyboardScrolledUp() {
        let app = open(["-long"])
        scrollUp(app)
        spin(0.5)
        guard let (line, before) = visibleStep(app) else { return XCTFail("no line of the plan on screen") }
        box(app).tap()
        XCTAssertTrue(poll(5) { self.box(app).hasKeyboardFocus })
        idle(1)
        stays(app, line, before, "the keyboard came up while scrolled up")
        App.current?.shot("a229-keyboard-scrolled-up")
    }

    func testKeyboardAtTheBottom() {
        let app = open(["-long"])
        spin(0.5)
        atBottom(app, "opened")
        box(app).tap()
        XCTAssertTrue(poll(5) { self.box(app).hasKeyboardFocus })
        idle(1)
        atBottom(app, "the keyboard came up at the bottom")
    }

    /// opening a fold (Worked for … steps) above the end: the fold's row stays where it was tapped
    func testFoldOpensInPlace() {
        let app = open(["-long"])
        let handle = app.buttons.matching(identifier: "handle").element(boundBy: 0)
        let h = app.frame.height
        for _ in 0..<40 {
            // in view below the top bar (it may be the chat's first row, as high as it goes)
            if handle.exists, handle.frame.minY > 120, handle.frame.maxY < h * 0.6 { break }
            if handle.exists, handle.frame.minY > 0, handle.frame.minY <= 120 { scrollUp(app, by: 0.1) } else { scrollUp(app, by: 0.35) }
        }
        spin(0.5)
        let before = handle.frame
        XCTAssertGreaterThan(before.minY, 120, "the first fold is in view: \(before)")
        handle.tap()
        XCTAssertTrue(poll(3) { (handle.value as? String) == "open" }, "the fold opened")
        spin(1)
        XCTAssertEqual(handle.frame.minY, before.minY, accuracy: 1.5,
                       "the fold's row moved from \(before.minY) to \(handle.frame.minY)")
        App.current?.shot("a229-fold-opened")
    }

    /// an idle long chat scrolled up and down: where the finger leaves it, it stays
    func testIdleChatBothWays() {
        let app = open(["-long"])
        for (k, up) in [true, true, true, false, false].enumerated() {
            if up { scrollUp(app) } else { scrollDown(app) }
            spin(0.3)
            guard let (line, before) = visibleStep(app) else { return XCTFail("no line on screen after drag \(k + 1)") }
            spin(1.2)
            stays(app, line, before, "after drag \(k + 1)")
        }
    }

    /// near the top, older turns load above: what is on screen stays where it was
    func testOlderTurnsLoadAbove() {
        let app = open(["-long", "-older"])
        let first = "The gallery feels slow on my phone"
        let h = app.frame.height
        // (a page may already come while the chat opens: the first frame starts at its top)
        spin(3.5)
        // up until the chat is near its top (the next page is then on its way, 2.5 s later); stop right there
        for _ in 0..<40 {
            if let sv = chatScroll(), sv.contentOffset.y + sv.adjustedContentInset.top < 300 { break }
            scrollUp(app, by: 0.25)
        }
        let earlier = (1...6).map { "Earlier question \($0)" }
        let had = Set(earlier.filter { rect(app, $0) != nil })
        XCTAssertLessThan(had.count, 6, "a page still to come")
        // a row in view to watch: the chat's first message or an older question
        guard let anchor = ([first] + earlier).first(where: { t in rect(app, t).map { $0.minY > 120 && $0.maxY < h - 280 } ?? false }),
              let before = rect(app, anchor)
        else { return XCTFail("nothing to watch in view") }
        XCTAssertTrue(poll(6) { earlier.contains { !had.contains($0) && self.rect(app, $0) != nil } }, "the next page loaded")
        spin(0.5)
        stays(app, anchor, before, "older turns loaded above")
        App.current?.shot("a229-older-loaded")
    }
}
