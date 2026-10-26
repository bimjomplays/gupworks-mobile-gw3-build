import SwiftUI
import XCTest
@testable import GupWorks3

/// a125 prototype: can the unit-test bundle drive and photograph the real screens? Logs what it finds.
@MainActor
final class ScreenProbeTests: XCTestCase {
    private var log: [String] = []
    private func note(_ s: String) { log.append(s); print("PROBE " + s) }

    private func flush() {
        let text = log.joined(separator: "\n")
        let a = XCTAttachment(string: text)
        a.name = "probe-log-\(name)"
        a.lifetime = .keepAlways
        add(a)
        if let dir = ProcessInfo.processInfo.environment["SHOTS_DIR"], !dir.isEmpty {
            try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            let file = name.filter { $0.isLetter || $0.isNumber }
            try? text.write(toFile: dir + "/probe-\(file).txt", atomically: true, encoding: .utf8)
        }
    }

    func testProbeTreeAndTap() async throws {
        let t0 = Date()
        let s = await Screen(["-menu"], test: self)
        defer { s.close(); flush() }
        let found = await s.waitFor("place-projects", 20)
        note("place-projects after \(Date().timeIntervalSince(t0))s: \(found != nil)")
        let nodes = s.nodes()
        note("nodes: \(nodes.count)")
        for n in nodes.prefix(120) { note("  [\(n.id)] \(n.kind) \(n.label.prefix(60)) = \(n.value.prefix(30)) \(n.frame)") }
        await s.shot("probe-menu")
        let t1 = Date()
        note("pins: \(s.nodes().filter { $0.id.hasPrefix("pin-") }.map(\.id))")
        let how = await s.waitFor("pin-Gallery lightbox fix")?.tap() ?? "missing"
        note("pin tap: \(how)")
        let chat = await s.waitForText("All five pages pass", 10)
        note("chat after tap \(Date().timeIntervalSince(t1))s: \(chat != nil)")
        let menuGone = await s.gone("place-projects")
        note("menu gone: \(menuGone)")
        await s.shot("probe-chat")
        // a drag from the left edge: the menu comes back in (MenuSwipeUITests does this with XCUITest)
        let sw = Finger.swipe(from: CGPoint(x: 8, y: 400), to: CGPoint(x: 330, y: 400))
        let back = await s.waitFor("place-projects", 5)
        note("edge swipe: \(sw), menu back: \(back != nil)")
        await s.shot("probe-swipe")
        note("total \(Date().timeIntervalSince(t0))s")
    }

    func testProbeFullScreenShot() async throws {
        let s = await Screen([], test: self)
        defer { s.close(); flush() }
        _ = await s.waitFor("composer", 20)
        await s.settle(1.5)
        for (name, f) in [("uikit", { Screen.uikitScreen() }), ("snapshotview", { Screen.screenSnapshot() }),
                          ("drawn", { Screen.drawn(s.window) })] as [(String, () -> Data?)] {
            let t = Date()
            let png = f()
            note("\(name): \(png?.count ?? -1) bytes in \(Date().timeIntervalSince(t))s, keyboard pixels: \(png.map(Self.lowerBrightness) ?? -1)")
            if let png, let dir = ProcessInfo.processInfo.environment["SHOTS_DIR"], !dir.isEmpty {
                try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
                try? png.write(to: URL(fileURLWithPath: dir).appendingPathComponent("probe-full-\(name).png"))
            }
        }
    }

    /// share of non-black pixels in the bottom third (the keyboard)
    static func lowerBrightness(_ png: Data) -> Double {
        guard let img = UIImage(data: png)?.cgImage else { return -1 }
        let w = img.width, h = img.height
        var px = [UInt8](repeating: 0, count: w * h * 4)
        guard let ctx = CGContext(data: &px, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return -1 }
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
        var lit = 0, all = 0
        for y in (h * 2 / 3)..<h { for x in stride(from: 0, to: w, by: 4) {
            let i = (y * w + x) * 4
            all += 1
            if Int(px[i]) + Int(px[i + 1]) + Int(px[i + 2]) > 60 { lit += 1 }
        } }
        return Double(lit) / Double(max(all, 1))
    }

    func testProbeTypingAndSend() async throws {
        let t0 = Date()
        let s = await Screen([], test: self)
        defer { s.close(); flush() }
        let box = await s.waitFor("composer", 20)
        note("composer: \(box != nil) \(box.map { "\(type(of: $0.obj))" } ?? "")")
        await s.settle(1)
        note("first responder: \(Screen.firstResponder(in: s.window).map { "\(type(of: $0))" } ?? "none")")
        await s.type("Plan a picnic for six", into: Screen.firstResponder(in: s.window) == nil ? "composer" : nil)
        note("box value: \(s.el("composer")?.value ?? "?")")
        await s.shot("probe-typed")
        await s.tap("send")
        let sent = await s.waitForText("This is the demo", 10)
        note("sent: \(sent != nil) title: \(s.el("chatTitle") != nil)")
        await s.shot("probe-sent")
        note("total \(Date().timeIntervalSince(t0))s")
    }

    func testProbeSheetAndProject() async throws {
        let t0 = Date()
        let s = await Screen(["-place", "projects", "-push", "00000066-1111-4222-8333-000000000066", "-sheet"], test: self)
        defer { s.close(); flush() }
        let glance = await s.waitFor("overviewGlance", 20)
        note("overview sheet: \(glance != nil) after \(Date().timeIntervalSince(t0))s")
        note("needsMain \(s.el("needsMain") != nil) thread-a6 \(s.el("thread-a6") != nil)")
        await s.shot("probe-overview")
        let how = await s.waitFor("thread-a4")?.tap() ?? "missing"
        note("thread-a4 tap: \(how)")
        let task = await s.waitFor("taskCard", 10)
        note("taskCard after tap: \(task != nil)")
        await s.shot("probe-thread")
        note("total \(Date().timeIntervalSince(t0))s")
    }
}
