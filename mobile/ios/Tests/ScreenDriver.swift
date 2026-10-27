import Hammer
import SwiftUI
import XCTest
@testable import GupWorks3

/// Drives the app's real screens inside the unit-test process, with the same calls the UI tests used (app.buttons[id],
/// waitForExistence, tap, typeText, press...), so a UI test's body moves over almost as it is. No app launch per test
/// and no XCUITest round trips: a screen opens in about a second and a tap takes milliseconds.
///
/// - The screen is RootView in demo mode with the test's flags (what the UI tests passed as launch arguments).
/// - Things are found through the accessibility tree (turned on in-process, as XCUITest does), by id or label.
/// - Taps, presses and drags are real touches: Lyft's Hammer puts finger events into the app's own event queue, the
///   way the system delivers them, so UIKit's and SwiftUI's gestures see them as from a finger.
/// - Typing goes into the field that has the keyboard; the keyboard itself shows (remote, in the screenshots).
/// - Screenshots are the whole simulator screen (status bar and keyboard included), as XCUIScreen took them.
///
/// Waiting lets the app run (its main queue, timers and animations), so tests must be synchronous (not async), and a
/// `sleep` must be `spin` (Darwin's sleep would freeze the app).
@MainActor
final class App {
    let window: UIWindow
    let model: AppModel
    /// Hammer's event generator for this screen (touches go through the app's event queue, to any of its windows)
    private(set) var fingers: EventGenerator?
    private weak var test: XCTestCase?
    static var current: App?

    /// a screen in demo mode with `flags` (e.g. ["-menu"]); waits until its home data is in
    init(_ flags: [String] = [], test: XCTestCase) {
        App.current?.close()
        Accessibility.enable()
        Demo.args = ["-demo"] + flags
        // each screen starts as a fresh install would (the projects filter and such are kept in the defaults);
        // Hammer's own note that the accessibility engine is warm stays
        let defaults = UserDefaults.standard
        for key in (defaults.persistentDomain(forName: Bundle.main.bundleIdentifier ?? "") ?? [:]).keys
        where key != "accessibility_activated" {
            defaults.removeObject(forKey: key)
        }
        model = AppModel(demo: true)
        self.test = test
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first!
        // the test host's own window (the app as it launched) goes out of sight, touches and the tree
        for w in scene.windows where w.windowLevel == .normal { w.isHidden = true }
        window = UIWindow(windowScene: scene)
        // the window isn't the App's scene, so SwiftUI's scenePhase would never say "active" (RootView loads on active)
        let root = RootView().environment(model).environment(\.scenePhase, .active)
            .preferredColorScheme(.dark).tint(Theme.blue)
        window.rootViewController = UIHostingController(rootView: root)
        window.makeKeyAndVisible()
        App.current = self
        let loaded = Flag()
        Task { @MainActor [model] in
            await model.refresh()  // what RootView's task does once the app is in front
            loaded.on = true
        }
        poll(20) { loaded.on }
        idle()
        do {
            fingers = try EventGenerator(window: window)
            fingers?.showTouches = false
        } catch {
            XCTFail("touches can't reach the screen: \(error)")
        }
    }

    func close() {
        try? fingers?.finish()
        fingers = nil
        window.endEditing(true)
        window.rootViewController?.dismiss(animated: false)
        window.isHidden = true
        window.rootViewController = nil
        Demo.args = ProcessInfo.processInfo.arguments
        if App.current === self { App.current = nil }
        spin(0.05)
    }

    // MARK: queries, as XCUIApplication has them

    func descendants(matching kind: Kind) -> Query { Query(kind: kind, scope: nil) }
    var buttons: Query { descendants(matching: .button) }
    var textFields: Query { descendants(matching: .textField) }
    var textViews: Query { descendants(matching: .textView) }
    var searchFields: Query { descendants(matching: .searchField) }
    var switches: Query { descendants(matching: .toggle) }
    var segmentedControls: Query { descendants(matching: .segmentedControl) }
    var alerts: Query { descendants(matching: .alert) }
    var navigationBars: Query { descendants(matching: .navigationBar) }
    /// topmost first (a sheet's list before the page under it)
    var collectionViews: Query { descendants(matching: .collectionView) }
    var keyboards: Query { descendants(matching: .keyboard) }
    var windows: Query { descendants(matching: .window) }

    var frame: CGRect { window.bounds }
    func coordinate(withNormalizedOffset v: CGVector) -> Coordinate { Coordinate(frame, v) }
    func swipeUp() { Element.swipe(in: frame, up: true) }
    func swipeDown() { Element.swipe(in: frame, up: false) }

    /// the accessibility tree, for failure messages
    var debugDescription: String {
        Tree.nodes().map { "[\($0.id)] \($0.kind) '\($0.label.prefix(60))' = '\($0.value.prefix(30))' \($0.frame)" }
            .joined(separator: "\n")
    }

    // MARK: pictures

    /// the whole screen as the UI tests took it, attached and written to SHOTS_DIR
    func shot(_ name: String) {
        idle()
        let t0 = Date()
        defer { Timing.shots += Date().timeIntervalSince(t0) }
        let png = Self.screenPNG(window)
        let a = XCTAttachment(data: png, uniformTypeIdentifier: "public.png")
        a.name = name
        a.lifetime = .keepAlways
        test?.add(a)
        if let dir = ProcessInfo.processInfo.environment["SHOTS_DIR"], !dir.isEmpty {
            try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            try? png.write(to: URL(fileURLWithPath: dir).appendingPathComponent(name + ".png"))
        }
    }

    /// UIKit's own capture of the whole screen (status bar and keyboard included), else the app's windows drawn
    static func screenPNG(_ window: UIWindow) -> Data {
        typealias Capture = @convention(c) () -> Unmanaged<UIImage>?
        if let lib = dlopen(nil, RTLD_NOW), let f = dlsym(lib, "_UICreateScreenUIImage"),
           let png = unsafeBitCast(f, to: Capture.self)()?.takeRetainedValue().pngData() {
            return png
        }
        return UIGraphicsImageRenderer(bounds: window.bounds).pngData { _ in
            for w in window.windowScene?.windows ?? [window] where !w.isHidden {
                w.drawHierarchy(in: w.frame, afterScreenUpdates: true)
            }
        }
    }
}

final class Flag { var on = false }

// MARK: waiting

/// lets the app run for `seconds`
@MainActor
func spin(_ seconds: Double) {
    let end = Date().addingTimeInterval(seconds)
    repeat {
        Tree.run(max(0.001, min(0.02, end.timeIntervalSinceNow)))
    } while Date() < end
}

/// lets the app run until `ok` holds; false if it still doesn't after `timeout` seconds
@MainActor @discardableResult
func poll(_ timeout: Double, until ok: () -> Bool) -> Bool {
    let end = Date().addingTimeInterval(timeout)
    while Date() < end {
        if ok() { return true }
        Tree.run(0.02)
    }
    return ok()
}

/// lets the app finish what a tap started: at least a moment, then until no (finite) animation runs, at most 1.5 s
@MainActor
func idle(_ least: Double = 0.15) {
    let t0 = Date()
    defer { Timing.idle += Date().timeIntervalSince(t0) }
    spin(least)
    // SwiftUI moves things without Core Animation, so "still" is also: the same elements in the same places as a
    // moment ago
    var last = ""
    poll(1.5) {
        if Tree.animating() { return false }
        let now = Tree.nodes().map { "\($0.id)|\($0.label)|\($0.frame)" }.joined(separator: "\n")
        defer { last = now }
        spin(0.05)
        return now == last
    }
}

/// before a touch, as XCUITest waits for the app to be idle: no transition or animation running and the target
/// (when given) holding still for a frame or two; at most 3 s
@MainActor
func settle(_ frame: (() -> CGRect?)? = nil) {
    let t0 = Date()
    defer { Timing.settle += Date().timeIntervalSince(t0) }
    var last = frame?()
    // a touch right after another lands while SwiftUI still animates the last one's change (a button fading back
    // in takes no touch yet); XCUITest leaves about this much between actions too
    let quiet = 0.3 - Date().timeIntervalSince(Finger.lastTouch)
    if quiet > 0 { spin(quiet) }
    poll(3) {
        if (UIApplication.shared as UIApplicationDeprecated).isIgnoringInteractionEvents || Tree.animating() { return false }
        if App.current?.fingers?.isWindowReady == false { return false }
        spin(0.04)
        let now = frame?()
        defer { last = now }
        return now == last
    }
}

/// isIgnoringInteractionEvents without its deprecation warning (UIKit still sets it during transitions)
@MainActor
private protocol UIApplicationDeprecated {
    var isIgnoringInteractionEvents: Bool { get }
}
extension UIApplication: UIApplicationDeprecated {}

/// XCUIKeyboardKey.delete
enum Key {
    static let delete = "\u{8}"
}

/// XCUIGestureVelocity's pixels per second (3 pixels a point here)
struct Velocity {
    let rawValue: CGFloat
    init(rawValue: CGFloat) { self.rawValue = rawValue }
    static let slow = Velocity(rawValue: 300)
    static let `default` = Velocity(rawValue: 600)
    static let fast = Velocity(rawValue: 750)
    var pointsPerSecond: CGFloat { rawValue / 3 }
}

// MARK: queries and elements

enum Kind {
    case any, button, textField, textView, searchField, toggle, segmentedControl, alert, navigationBar,
         collectionView, keyboard, window, staticText
}

/// A lazy list of things on screen (resolved each time it's read, as XCUIElementQuery is).
@MainActor
struct Query {
    let resolve: () -> [Node]

    init(_ resolve: @escaping () -> [Node]) { self.resolve = resolve }

    init(kind: Kind, scope: (() -> CGRect?)?) {
        self.init {
            var all = Tree.nodes(kind)
            if let scope {
                guard let r = scope() else { return [] }
                let box = r.insetBy(dx: -1, dy: -1)
                all = all.filter { box.contains(CGPoint(x: $0.frame.midX, y: $0.frame.midY)) && $0.frame != r }
            }
            return all
        }
    }

    /// by accessibility id or label, as XCUIElementQuery's subscript; any kind of thing when none of this kind has it
    subscript(_ key: String) -> Element {
        let typed = resolve
        return Element {
            if let n = typed().first(where: { $0.id == key || $0.label == key }) { return n }
            return Tree.nodes().first { $0.id == key || $0.label == key }
        }
    }

    func matching(identifier: String) -> Query {
        let r = resolve
        return Query { r().filter { $0.id == identifier } }
    }

    /// an NSPredicate on label, identifier, value, placeholderValue (as the UI tests wrote them)
    func matching(_ predicate: NSPredicate) -> Query {
        let r = resolve
        return Query { r().filter { predicate.evaluate(with: $0.snapshot) } }
    }

    var firstMatch: Element {
        let r = resolve
        return Element { r().first }
    }

    func element(boundBy i: Int) -> Element {
        let r = resolve
        return Element { let all = r(); return i < all.count ? all[i] : nil }
    }

    var count: Int { resolve().count }

    /// the buttons inside what this query finds (e.g. app.alerts.buttons["Keep mine"])
    var buttons: Query { inside(.button) }
    var textFields: Query { inside(.textField) }

    private func inside(_ kind: Kind) -> Query {
        let r = resolve
        return Query {
            let boxes = r().map(\.frame)
            return Tree.nodes(kind).filter { n in
                boxes.contains { $0.insetBy(dx: -1, dy: -1).contains(CGPoint(x: n.frame.midX, y: n.frame.midY)) && $0 != n.frame }
            }
        }
    }
}

/// One thing on screen, found again each time it's read (as XCUIElement is).
@MainActor
struct Element {
    let resolve: () -> Node?
    init(_ resolve: @escaping () -> Node?) { self.resolve = resolve }

    var exists: Bool { resolve() != nil }
    var firstMatch: Element { self }

    func waitForExistence(timeout: Double) -> Bool { poll(timeout) { resolve() != nil } }

    func waitForNonExistence(timeout: Double) -> Bool { poll(timeout) { resolve() == nil } }

    var label: String { resolve()?.label ?? "" }
    var identifier: String { resolve()?.id ?? "" }
    /// a field's text, a switch's "0" or "1", an accessibility value
    var value: Any? { resolve()?.valueOrText }
    var placeholderValue: String? { resolve()?.placeholder }
    var frame: CGRect { resolve()?.frame ?? .zero }
    var isSelected: Bool { resolve()?.isSelected ?? false }
    var hasKeyboardFocus: Bool { resolve()?.hasKeyboardFocus ?? false }

    /// on screen, above the keyboard, and the screen's touch there lands on it
    var isHittable: Bool { resolve()?.isHittable ?? false }

    private func node(_ what: String, file: StaticString, line: UInt) -> Node? {
        // as XCUITest: an action waits a little for its element
        if resolve() != nil || poll(3, until: { resolve() != nil }) {
            settle { resolve()?.frame }
            if let n = resolve() { return n }
        }
        XCTFail("nothing to \(what)\n\(App.current?.debugDescription ?? "")", file: file, line: line)
        return nil
    }

    func tap(file: StaticString = #filePath, line: UInt = #line) {
        guard let n = node("tap", file: file, line: line) else { return }
        n.tap()
        idle()
    }

    func press(forDuration seconds: Double, file: StaticString = #filePath, line: UInt = #line) {
        guard let n = node("press", file: file, line: line) else { return }
        Finger.press(n.hitPoint, seconds: seconds)
        idle()
    }

    func press(forDuration seconds: Double, thenDragTo other: Element, withVelocity v: Velocity = .default,
               thenHoldForDuration hold: Double = 0, file: StaticString = #filePath, line: UInt = #line) {
        guard let n = node("press", file: file, line: line), let to = other.resolve() else {
            return XCTFail("nothing to drag to", file: file, line: line)
        }
        Finger.press(n.hitPoint, seconds: seconds, thenDragTo: to.hitPoint, speed: v.pointsPerSecond, hold: hold)
        idle()
    }

    func coordinate(withNormalizedOffset v: CGVector) -> Coordinate {
        let f = frame
        return Coordinate(f, v)
    }

    /// types into this field (focusing it first when the keyboard is elsewhere); "\u{8}" deletes
    func typeText(_ text: String, file: StaticString = #filePath, line: UInt = #line) {
        guard let n = node("type into", file: file, line: line) else { return }
        if !n.hasKeyboardFocus || !(Tree.firstResponder() is UIKeyInput) {
            n.tap()
            poll(3) { Tree.firstResponder() is UIKeyInput }
        }
        guard let field = Tree.firstResponder() as? UIKeyInput else {
            return XCTFail("no field has the keyboard for \(n.id)", file: file, line: line)
        }
        for ch in text {
            if String(ch) == Key.delete { field.deleteBackward() } else { field.insertText(String(ch)) }
            spin(0.005)
        }
        idle()
    }

    func swipeUp() { Element.swipe(in: frame, up: true) }
    func swipeDown() { Element.swipe(in: frame, up: false) }

    /// a quick swipe through the middle of `r` (as XCUIElement's swipeUp: the list flings on)
    static func swipe(in r: CGRect, up: Bool) {
        let a = CGPoint(x: r.midX, y: r.minY + r.height * (up ? 0.75 : 0.25))
        let b = CGPoint(x: r.midX, y: r.minY + r.height * (up ? 0.25 : 0.75))
        settle()
        Finger.press(a, seconds: 0, thenDragTo: b, speed: 1500, hold: 0)
        idle()
    }

    // scoped queries (inside this element's frame)
    func descendants(matching kind: Kind) -> Query { Query(kind: kind, scope: { resolve()?.frame }) }
    var buttons: Query { descendants(matching: .button) }
    var switches: Query { descendants(matching: .toggle) }
    var textFields: Query { descendants(matching: .textField) }
}

/// A point on screen (a fraction of an element's frame), as XCUICoordinate.
@MainActor
struct Coordinate {
    let point: CGPoint
    init(_ r: CGRect, _ v: CGVector) { point = CGPoint(x: r.minX + r.width * v.dx, y: r.minY + r.height * v.dy) }

    func tap() {
        settle()
        Finger.tap(point)
        idle()
    }

    func press(forDuration seconds: Double, thenDragTo other: Coordinate, withVelocity v: Velocity = .default,
               thenHoldForDuration hold: Double = 0) {
        settle()
        Finger.press(point, seconds: seconds, thenDragTo: other.point, speed: v.pointsPerSecond, hold: hold)
        idle()
    }
}

// MARK: the accessibility tree

/// One thing on screen as accessibility sees it.
@MainActor
struct Node {
    let obj: NSObject
    /// an alert's title
    var name: String?
    init(_ obj: NSObject, name: String? = nil) { self.obj = obj; self.name = name }

    /// SwiftUI's elements answer accessibilityIdentifier without declaring UIAccessibilityIdentification
    var id: String {
        let sel = NSSelectorFromString("accessibilityIdentifier")
        guard obj.responds(to: sel) else { return "" }
        return (obj.perform(sel)?.takeUnretainedValue() as? String) ?? ""
    }
    var kind: String { String(describing: type(of: obj)) }
    var label: String { name ?? obj.accessibilityLabel ?? "" }
    var value: String { obj.accessibilityValue ?? "" }
    var frame: CGRect {
        if let v = obj as? UIView, v.window != nil { return v.convert(v.bounds, to: nil) }
        return obj.accessibilityFrame
    }
    var traits: UIAccessibilityTraits { obj.accessibilityTraits }
    var isSelected: Bool { traits.contains(.selected) }

    var valueOrText: String? {
        if let f = obj as? UITextField { return f.text?.isEmpty == false ? f.text : f.placeholder }
        if let t = obj as? UITextView { return t.text }
        return obj.accessibilityValue
    }

    var placeholder: String? {
        if let f = obj as? UITextField { return f.placeholder }
        let sel = NSSelectorFromString("accessibilityPlaceholderValue")
        if obj.responds(to: sel), let s = obj.perform(sel)?.takeUnretainedValue() as? String { return s }
        // SwiftUI's vertical TextField: a text view with its prompt in a label
        if let v = obj as? UIView {
            var found: String?
            func walk(_ v: UIView) {
                for s in v.subviews where found == nil {
                    if let l = s as? UILabel, let t = l.text, !t.isEmpty { found = t } else { walk(s) }
                }
            }
            walk(v)
            return found
        }
        return nil
    }

    var hasKeyboardFocus: Bool {
        guard let r = Tree.firstResponder() else { return false }
        if let v = obj as? UIView { return r === v || r.isDescendant(of: v) }
        let f = r.convert(r.bounds, to: nil), mine = frame
        return mine.insetBy(dx: -2, dy: -2).contains(CGPoint(x: f.midX, y: f.midY))
            || f.insetBy(dx: -2, dy: -2).contains(CGPoint(x: mine.midX, y: mine.midY))
    }

    /// where a finger touches it: its middle, kept on screen
    var hitPoint: CGPoint {
        let f = frame, screen = UIScreen.main.bounds
        let visible = f.intersection(screen)
        let r = visible.isNull || visible.isEmpty ? f : visible
        return CGPoint(x: r.midX, y: r.midY)
    }

    var isHittable: Bool {
        let p = hitPoint, screen = UIScreen.main.bounds
        guard screen.contains(p) else { return false }
        if let k = Tree.keyboardFrame(), k.contains(p) { return false }
        guard let hit = Finger.target(p)?.hitTest(p, with: nil) else { return false }
        guard let mine = (obj as? UIView) ?? Tree.container(of: obj) else { return true }
        return hit === mine || hit.isDescendant(of: mine) || mine.isDescendant(of: hit)
    }

    /// a finger on its middle (what XCUITest did); a text field gets the keyboard as a tap would give it
    func tap() {
        Finger.tap(hitPoint)
        if let r = obj as? UIResponder, !(r.isFirstResponder), obj is UITextField || obj is UITextView {
            _ = r.becomeFirstResponder()
        }
    }

    /// for NSPredicate: the names the UI tests' predicates use
    var snapshot: Snapshot { Snapshot(self) }
}

/// What an NSPredicate reads (by key, as from an XCUIElement snapshot); each value is read only when asked.
@MainActor
final class Snapshot: NSObject {
    let node: Node
    init(_ node: Node) { self.node = node }
    @objc var label: String { node.label }
    @objc var identifier: String { node.id }
    @objc var value: String? { node.valueOrText }
    @objc var placeholderValue: String? { node.placeholder }
    @objc var hasKeyboardFocus: Bool { node.hasKeyboardFocus }
}

@MainActor
enum Tree {
    /// the visible windows, back to front
    static var windows: [UIWindow] {
        UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows)
            .filter { !$0.isHidden }.enumerated()
            .sorted { ($0.element.windowLevel.rawValue, $0.offset) < ($1.element.windowLevel.rawValue, $1.offset) }
            .map(\.element)
    }

    /// every accessibility element and identified container on screen, in tree order (and alerts, bars and lists
    /// as XCUITest names them)
    /// lets the app run for up to `seconds`; what was read from the tree before is stale after it
    static func run(_ seconds: Double) {
        cache = nil
        _ = CFRunLoopRunInMode(CFRunLoopMode.defaultMode, seconds, false)
        cache = nil
    }

    /// the tree as last read, while the app hasn't run since (a test's queries in a row read it once)
    static var cache: [Node]?

    static func nodes(_ kind: Kind = .any) -> [Node] {
        switch kind {
        case .alert: return alerts()
        case .navigationBar: return views(UINavigationBar.self).map { Node($0) }
        case .collectionView: return views(UICollectionView.self).reversed().map { Node($0) }
        case .window: return [App.current?.window].compactMap { $0 }.map { Node($0) }
        case .keyboard: return keyboardFrame() == nil ? [] : keyboardHosts().map { Node($0) }
        default: break
        }
        if let all = cache { return kind == .any ? all : all.filter { matches($0, kind) } }
        let t0 = Date()
        defer { Timing.walks += 1; Timing.walk += Date().timeIntervalSince(t0) }
        var out: [Node] = [], seen = Set<ObjectIdentifier>()
        func walk(_ o: NSObject, _ depth: Int) {
            guard depth < 80, seen.insert(ObjectIdentifier(o)).inserted else { return }
            if let v = o as? UIView, v.isHidden || v.alpha < 0.01 { return }
            let n = Node(o)
            if o.isAccessibilityElement || !n.id.isEmpty { out.append(n) }
            if o.isAccessibilityElement && !(o is UIView) { return }
            if let els = o.accessibilityElements as? [NSObject] {
                for e in els { walk(e, depth + 1) }
            } else {
                let c = o.accessibilityElementCount()
                if c != NSNotFound && c > 0 {
                    for i in 0..<c { if let e = o.accessibilityElement(at: i) as? NSObject { walk(e, depth + 1) } }
                }
            }
            if let v = o as? UIView { for s in v.subviews { walk(s, depth + 1) } }
        }
        for w in windows { walk(w, 0) }
        cache = out
        return kind == .any ? out : out.filter { matches($0, kind) }
    }

    static func matches(_ n: Node, _ kind: Kind) -> Bool {
        let o = n.obj, t = n.traits
        switch kind {
        case .button: return t.contains(.button) || o is UIButton
        case .searchField: return o is UISearchTextField
        case .textField: return (o is UITextField && !(o is UISearchTextField)) || (t.rawValue & (1 << 18) != 0 && !(o is UITextView))
        case .textView: return o is UITextView
        case .toggle: return o is UISwitch || t.contains(.toggleButton) || ["0", "1"].contains(n.value) && t.contains(.button)
        case .segmentedControl: return o is UISegmentedControl
        case .staticText: return t.contains(.staticText)
        default: return true
        }
    }

    /// views of a class, in tree order
    static func views<T: UIView>(_ cls: T.Type) -> [T] {
        var out: [T] = []
        func walk(_ v: UIView) {
            guard !v.isHidden, v.alpha >= 0.01 else { return }
            if let t = v as? T { out.append(t) }
            for s in v.subviews { walk(s) }
        }
        for w in windows { walk(w) }
        return out
    }

    /// presented alerts (their view, named by their title)
    static func alerts() -> [Node] {
        var out: [Node] = []
        for w in windows {
            var vc = w.rootViewController
            while let c = vc {
                if let a = c as? UIAlertController, a.preferredStyle == .alert, a.viewIfLoaded?.window != nil {
                    out.append(Node(a.view, name: a.title ?? ""))
                }
                vc = c.presentedViewController
            }
        }
        return out
    }

    /// the view that has the keyboard: UIKit's own answer (an action sent to nobody goes to the first responder),
    /// else the first view that says it is first responder and takes text, else any that says it is
    static func firstResponder() -> UIView? {
        Responder.current = nil
        UIApplication.shared.sendAction(#selector(UIResponder.gw3CaptureFirstResponder), to: nil, from: nil, for: nil)
        if let v = Responder.current as? UIView { return v }
        var all: [UIView] = []
        func find(_ v: UIView) {
            if v.isFirstResponder { all.append(v) }
            for s in v.subviews { find(s) }
        }
        for w in windows.reversed() { find(w) }
        return all.first { $0 is UIKeyInput } ?? all.first
    }

    private static func keyboardHosts() -> [UIView] {
        views(UIView.self).filter { String(describing: type(of: $0)) == "UIInputSetHostView" && $0.bounds.height > 100 }
    }

    /// the keyboard's frame on screen, when it's up
    static func keyboardFrame() -> CGRect? {
        let screen = UIScreen.main.bounds
        return keyboardHosts().map { $0.convert($0.bounds, to: nil) }.first { $0.intersects(screen) && $0.minY < screen.maxY - 20 }
    }

    /// the view an accessibility element belongs to
    static func container(of o: NSObject) -> UIView? {
        // accessibilityContainer is an informal protocol on NSObject that Swift doesn't see; ask by key
        func up(_ x: NSObject) -> Any? {
            x.responds(to: NSSelectorFromString("accessibilityContainer")) ? x.value(forKey: "accessibilityContainer") : nil
        }
        var c: Any? = up(o)
        for _ in 0..<20 {
            if let v = c as? UIView { return v }
            guard let n = c as? NSObject else { return nil }
            c = up(n)
        }
        return nil
    }

    /// something on screen is still moving (not counting endless ones: spinners, pulsing dots)
    static func animating() -> Bool {
        func busy(_ l: CALayer) -> Bool {
            for k in l.animationKeys() ?? [] {
                if let a = l.animation(forKey: k), a.repeatCount < 1000, a.duration < 30, a.repeatDuration < 30 { return true }
            }
            return (l.sublayers ?? []).contains { !$0.isHidden && busy($0) }
        }
        return windows.contains { busy($0.layer) }
    }
}

/// Turns on the accessibility tree inside the app (as XCUITest does), so SwiftUI builds its elements.
enum Accessibility {
    private static var done = false
    static func enable() {
        guard !done else { return }
        done = true
        let root = ProcessInfo.processInfo.environment["IPHONE_SIMULATOR_ROOT"] ?? ""
        if let lib = dlopen(root + "/usr/lib/libAccessibility.dylib", RTLD_NOW) {
            typealias SetBool = @convention(c) (Bool) -> Void
            for name in ["_AXSSetAutomationEnabled", "_AXSApplicationAccessibilitySetEnabled"] {
                if let f = dlsym(lib, name) { unsafeBitCast(f, to: SetBool.self)(true) }
            }
        }
    }
}

// MARK: touches

/// Real touches inside the app, in screen points, through Hammer. Each call returns once UIKit has handled them.
@MainActor
enum Finger {
    /// when the last touch ended
    static var lastTouch = Date.distantPast

    /// the window that shows `p` (a sheet or menu above the app's window takes the touch)
    static func target(_ p: CGPoint) -> UIWindow? {
        let mine = App.current?.window
        for w in Tree.windows.reversed() where w.isUserInteractionEnabled {
            guard let hit = w.hitTest(w.convert(p, from: nil), with: nil) else { continue }
            // a system window above (the keyboard's) takes it only where it shows something
            if w === mine || w.windowLevel <= (mine?.windowLevel ?? .normal) || hit !== w { return w }
        }
        return mine
    }

    private static func run(_ what: String, _ body: (EventGenerator) throws -> Void) {
        guard let g = App.current?.fingers else { return XCTFail("no screen to touch (\(what))") }
        Tree.cache = nil
        defer { Tree.cache = nil; lastTouch = Date() }
        do { try body(g) } catch { XCTFail("\(what) failed: \(error)") }
    }

    static func tap(_ p: CGPoint) {
        run("tap at \(p)") { try $0.fingerTap(at: p) }
    }

    /// down at `p`, held `seconds`, then (if given) moved to `to` at `speed` points a second, held `hold`, up
    static func press(_ p: CGPoint, seconds: Double, thenDragTo to: CGPoint? = nil, speed: CGFloat = 400, hold: Double = 0) {
        run("press at \(p)") { g in
            try g.fingerDown(at: p)
            if seconds > 0 { spin(seconds) }
            if let to {
                let d = hypot(to.x - p.x, to.y - p.y)
                try g.fingerMove(to: to, duration: max(0.05, Double(d / max(speed, 1))))
                if hold > 0 { spin(hold) }
            }
            try g.fingerUp()
        }
    }

    /// two fingers apart (a photo zooms in)
    static func zoom(at p: CGPoint, distance: CGFloat) {
        run("zoom at \(p)") { try $0.fingerPinch(at: p, fromDistance: 40, toDistance: 40 + distance, duration: 0.5) }
        idle()
    }
}

@MainActor
enum Responder {
    static weak var current: UIResponder?
}

extension UIResponder {
    @objc func gw3CaptureFirstResponder() {
        MainActor.assumeIsolated { Responder.current = self }
    }
}

/// where a screen test's time goes, printed after each test (TIMING lines in unit.log)
@MainActor
enum Timing {
    static var walks = 0, walk = 0.0, idle = 0.0, settle = 0.0, shots = 0.0

    static func report(_ test: String, _ total: Double) {
        print(String(format: "TIMING %@: %.1f s; %d tree reads %.1f s, idle %.1f s, settle %.1f s, pictures %.1f s",
                     test, total, walks, walk, idle, settle, shots))
        walks = 0; walk = 0; idle = 0; settle = 0; shots = 0
    }
}
