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
        let s = Screen(["-menu"], test: self)
        defer { s.close(); flush() }
        let found = await s.waitFor("place-projects", 20)
        note("place-projects after \(Date().timeIntervalSince(t0))s: \(found != nil)")
        let nodes = s.nodes()
        note("nodes: \(nodes.count)")
        for n in nodes.prefix(80) { note("  [\(n.id)] \(n.label.prefix(60)) = \(n.value.prefix(30)) \(n.frame)") }
        await s.shot("probe-menu")
        let t1 = Date()
        await s.tap("pin-Gallery lightbox fix")
        let chat = await s.waitForText("All five pages pass", 10)
        note("chat after tap \(Date().timeIntervalSince(t1))s: \(chat != nil)")
        let menuGone = await s.gone("place-projects")
        note("menu gone: \(menuGone)")
        await s.shot("probe-chat")
        note("total \(Date().timeIntervalSince(t0))s")
    }

    func testProbeFullScreenShot() async throws {
        let s = Screen(["-open", "00000009-1111-4222-8333-000000000009"], test: self)
        defer { s.close(); flush() }
        _ = await s.waitForText("All five pages pass", 20)
        let t = Date()
        let png = XCUIScreen.main.screenshot().pngRepresentation
        note("XCUIScreen: \(png.count) bytes in \(Date().timeIntervalSince(t))s")
        let a = XCTAttachment(data: png, uniformTypeIdentifier: "public.png")
        a.name = "probe-xcuiscreen"
        a.lifetime = .keepAlways
        add(a)
        if let dir = ProcessInfo.processInfo.environment["SHOTS_DIR"], !dir.isEmpty {
            try? png.write(to: URL(fileURLWithPath: dir).appendingPathComponent("probe-xcuiscreen.png"))
        }
    }

    func testProbeTypingAndSend() async throws {
        let t0 = Date()
        let s = Screen([], test: self)
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
        let s = Screen(["-place", "projects", "-push", "00000066-1111-4222-8333-000000000066", "-sheet"], test: self)
        defer { s.close(); flush() }
        let glance = await s.waitFor("overviewGlance", 20)
        note("overview sheet: \(glance != nil) after \(Date().timeIntervalSince(t0))s")
        note("needsMain \(s.el("needsMain") != nil) thread-a6 \(s.el("thread-a6") != nil)")
        await s.shot("probe-overview")
        await s.tap("thread-a4")
        let task = await s.waitFor("taskCard", 10)
        note("taskCard after tap: \(task != nil)")
        await s.shot("probe-thread")
        note("total \(Date().timeIntervalSince(t0))s")
    }
}
