import SwiftUI
import XCTest
@testable import GupWorks3

/// Drives the app's real screens inside the unit-test process: no app launch per test, no XCUITest round trips.
/// A Screen builds RootView in demo mode with the given flags (as the UI tests' launch arguments), finds things by
/// their accessibility id or label, taps them through accessibility, types into the focused field and takes
/// screenshots with the same names the UI tests used (SHOTS_DIR, docs/mobile-shots).
@MainActor
final class Screen {
    let window: UIWindow
    let model: AppModel
    private weak var test: XCTestCase?

    init(_ flags: [String] = [], test: XCTestCase) async {
        Accessibility.enable()
        Demo.args = ["-demo"] + flags
        model = AppModel(demo: true)
        self.test = test
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first!
        window = UIWindow(windowScene: scene)
        // the window isn't the App's scene, so SwiftUI's scenePhase would never say "active" (RootView loads on active)
        let root = RootView().environment(model).environment(\.scenePhase, .active)
            .preferredColorScheme(.dark).tint(Theme.blue)
        window.rootViewController = UIHostingController(rootView: root)
        window.makeKeyAndVisible()
        await model.refresh()  // what RootView's task does once the app is in front
    }

    func close() {
        window.endEditing(true)
        window.rootViewController?.dismiss(animated: false)
        window.isHidden = true
        window.rootViewController = nil
        Demo.args = ProcessInfo.processInfo.arguments
    }

    // MARK: finding

    /// every accessibility element and identified container on screen, in tree order
    func nodes() -> [Node] {
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
        for w in window.windowScene?.windows ?? [window] where !w.isHidden { walk(w, 0) }
        return out
    }

    /// by accessibility id
    func el(_ id: String) -> Node? { nodes().first { $0.id == id } }
    /// any element whose label contains `text` (rows combine their texts into one element)
    func find(_ text: String) -> Node? { nodes().first { $0.label.localizedCaseInsensitiveContains(text) } }
    func all(_ id: String) -> [Node] { nodes().filter { $0.id == id } }

    /// waits (letting the app run) until `ok` holds; false after `timeout` seconds
    @discardableResult
    func wait(_ timeout: Double = 5, until ok: () -> Bool) async -> Bool {
        let end = Date().addingTimeInterval(timeout)
        while Date() < end {
            if ok() { return true }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return ok()
    }

    func waitFor(_ id: String, _ timeout: Double = 5) async -> Node? {
        await wait(timeout) { el(id) != nil } ? el(id) : nil
    }

    func waitForText(_ text: String, _ timeout: Double = 5) async -> Node? {
        await wait(timeout) { find(text) != nil } ? find(text) : nil
    }

    func gone(_ id: String, _ timeout: Double = 5) async -> Bool { await wait(timeout) { el(id) == nil } }

    /// lets animations and the demo's PC finish
    func settle(_ seconds: Double = 0.6) async { try? await Task.sleep(for: .seconds(seconds)) }

    // MARK: acting

    /// a tap through accessibility (the element's default action)
    func tap(_ id: String, file: StaticString = #filePath, line: UInt = #line) async {
        guard let n = await waitFor(id) else { return XCTFail("no \(id) to tap", file: file, line: line) }
        n.tap()
        await settle(0.3)
    }

    /// types into the field that has the keyboard (or `id`'s field first)
    func type(_ text: String, into id: String? = nil, file: StaticString = #filePath, line: UInt = #line) async {
        if let id {
            guard let n = await waitFor(id) else { return XCTFail("no field \(id)", file: file, line: line) }
            n.focus()
            await settle(0.3)
        }
        guard let field = Self.firstResponder(in: window) as? UIKeyInput else {
            return XCTFail("no field has the keyboard", file: file, line: line)
        }
        for ch in text { field.insertText(String(ch)) }
        await settle(0.3)
    }

    static func firstResponder(in view: UIView) -> UIView? {
        if view.isFirstResponder { return view }
        for s in view.subviews { if let r = firstResponder(in: s) { return r } }
        return nil
    }

    // MARK: pictures

    /// the whole screen as the UI tests took it, attached and written to SHOTS_DIR
    func shot(_ name: String) async {
        await settle()
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

    /// XCUIScreen (status bar and keyboard included) when it works in this bundle, else the app's own windows
    static var fullScreen = false
    static func screenPNG(_ window: UIWindow) -> Data {
        if let full = uikitScreen() { return full }
        return drawn(window)
    }

    /// the whole screen as the simulator shows it (status bar and keyboard included): UIKit's own screen capture
    static func uikitScreen() -> Data? {
        typealias Capture = @convention(c) () -> Unmanaged<UIImage>?
        guard let lib = dlopen(nil, RTLD_NOW), let f = dlsym(lib, "_UICreateScreenUIImage") else { return nil }
        return unsafeBitCast(f, to: Capture.self)()?.takeRetainedValue().pngData()
    }

    /// UIScreen's snapshot view drawn into a picture
    static func screenSnapshot() -> Data? {
        guard let screen = UIApplication.shared.connectedScenes.compactMap({ ($0 as? UIWindowScene)?.screen }).first,
              let v = Optional(screen.snapshotView(afterScreenUpdates: true)) else { return nil }
        v.frame = screen.bounds
        return UIGraphicsImageRenderer(bounds: screen.bounds).pngData { _ in
            v.drawHierarchy(in: screen.bounds, afterScreenUpdates: true)
        }
    }

    /// the app's windows drawn into one picture (no status bar or keyboard)
    static func drawn(_ window: UIWindow) -> Data {
        let bounds = window.bounds
        let r = UIGraphicsImageRenderer(bounds: bounds)
        return r.pngData { _ in
            for w in window.windowScene?.windows ?? [window] where !w.isHidden {
                w.drawHierarchy(in: w.frame, afterScreenUpdates: true)
            }
        }
    }
}

/// One thing on screen as accessibility sees it.
@MainActor
struct Node {
    let obj: NSObject
    init(_ obj: NSObject) { self.obj = obj }

    /// SwiftUI's elements answer accessibilityIdentifier without declaring UIAccessibilityIdentification
    var id: String {
        let sel = NSSelectorFromString("accessibilityIdentifier")
        guard obj.responds(to: sel) else { return "" }
        return (obj.perform(sel)?.takeUnretainedValue() as? String) ?? ""
    }
    var kind: String { String(describing: type(of: obj)) }
    var label: String { obj.accessibilityLabel ?? "" }
    var value: String { obj.accessibilityValue ?? "" }
    var frame: CGRect { obj.accessibilityFrame }
    var isSelected: Bool { obj.accessibilityTraits.contains(.selected) }
    var isButton: Bool { obj.accessibilityTraits.contains(.button) }

    /// a tap: the accessibility action when the element has one, else a finger (XCTest's event synthesizer)
    @discardableResult
    func tap() -> String {
        if obj.accessibilityActivate() { return "activate" }
        if let c = obj as? UIControl { c.sendActions(for: .touchUpInside); return "control" }
        let f = frame
        return Finger.tap(CGPoint(x: f.midX, y: f.midY))
    }

    /// a text field: the keyboard to it
    func focus() {
        if let r = obj as? UIResponder, r.becomeFirstResponder() { return }
        _ = obj.accessibilityActivate()
    }
}

/// Turns on the accessibility tree inside the app (as XCUITest and KIF do), so SwiftUI builds its elements.
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

/// Touches through XCTest's own event synthesizer (what XCUIElement.tap() uses), from inside the app.
@MainActor
enum Finger {
    private typealias InitPath = @convention(c) (AnyObject, Selector, CGPoint, Double) -> AnyObject
    private typealias AtOffset = @convention(c) (AnyObject, Selector, Double) -> Void
    private typealias MoveTo = @convention(c) (AnyObject, Selector, CGPoint, Double) -> Void
    private typealias InitRecord = @convention(c) (AnyObject, Selector, NSString, Int) -> AnyObject
    private typealias AddPath = @convention(c) (AnyObject, Selector, AnyObject) -> Void
    private typealias SynthWithError = @convention(c) (AnyObject, Selector, UnsafeMutablePointer<NSError?>?) -> Bool

    private static func imp<T>(_ cls: AnyClass, _ name: String, _: T.Type) -> T? {
        guard let m = class_getInstanceMethod(cls, NSSelectorFromString(name)) else { return nil }
        return unsafeBitCast(method_getImplementation(m), to: T.self)
    }

    /// a path of points (screen coordinates); one point is a tap
    static func path(_ points: [CGPoint], seconds: Double = 0.05) -> String {
        guard let pathCls = NSClassFromString("XCPointerEventPath"),
              let recCls = NSClassFromString("XCSynthesizedEventRecord"),
              let initPath = imp(pathCls, "initForTouchAtPoint:offset:", InitPath.self),
              let lift = imp(pathCls, "liftUpAtOffset:", AtOffset.self),
              let move = imp(pathCls, "moveToPoint:atOffset:", MoveTo.self),
              let initRec = imp(recCls, "initWithName:interfaceOrientation:", InitRecord.self),
              let add = imp(recCls, "addPointerEventPath:", AddPath.self)
        else { return "no XCTest synthesizer classes" }
        let p = initPath((pathCls as! NSObject.Type).alloc(), NSSelectorFromString("initForTouchAtPoint:offset:"), points[0], 0)
        let step = points.count > 1 ? seconds / Double(points.count - 1) : 0
        for (i, pt) in points.enumerated().dropFirst() {
            move(p, NSSelectorFromString("moveToPoint:atOffset:"), pt, step * Double(i))
        }
        lift(p, NSSelectorFromString("liftUpAtOffset:"), points.count > 1 ? seconds : 0.05)
        let rec = initRec((recCls as! NSObject.Type).alloc(), NSSelectorFromString("initWithName:interfaceOrientation:"),
                          "a125 finger" as NSString, UIInterfaceOrientation.portrait.rawValue)
        add(rec, NSSelectorFromString("addPointerEventPath:"), p)
        if let synth = imp(recCls, "synthesizeWithError:", SynthWithError.self) {
            var err: NSError?
            let ok = synth(rec, NSSelectorFromString("synthesizeWithError:"), &err)
            return ok ? "synthesized" : "synthesize failed: \(err?.localizedDescription ?? "?")"
        }
        // newer XCTest: XCUIDevice's event synthesizer, answers through a block
        typealias Synth = @convention(c) (AnyObject, Selector, AnyObject, @escaping @convention(block) (NSError?) -> Void) -> Void
        let dev = XCUIDevice.shared as NSObject
        guard dev.responds(to: NSSelectorFromString("eventSynthesizer")),
              let es = dev.value(forKey: "eventSynthesizer") as? NSObject,
              let m = class_getInstanceMethod(type(of: es), NSSelectorFromString("synthesizeEvent:completion:"))
        else { return "no synthesizer" }
        var done = false, failure: String?
        unsafeBitCast(method_getImplementation(m), to: Synth.self)(es, NSSelectorFromString("synthesizeEvent:completion:"), rec) { e in
            failure = e?.localizedDescription
            done = true
        }
        let end = Date().addingTimeInterval(10)
        while !done && Date() < end { RunLoop.current.run(until: Date().addingTimeInterval(0.02)) }
        return !done ? "synthesizer timed out" : failure.map { "synthesizer: " + $0 } ?? "synthesized (device)"
    }

    static func tap(_ at: CGPoint) -> String { path([at]) }

    static func swipe(from a: CGPoint, to b: CGPoint, steps: Int = 12, seconds: Double = 0.3) -> String {
        path((0...steps).map { i in
            let t = CGFloat(i) / CGFloat(steps)
            return CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
        }, seconds: seconds)
    }
}
