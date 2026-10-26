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

    init(_ flags: [String] = [], test: XCTestCase) {
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

    func tap() {
        if obj.accessibilityActivate() { return }
        if let c = obj as? UIControl { c.sendActions(for: .touchUpInside) }
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
