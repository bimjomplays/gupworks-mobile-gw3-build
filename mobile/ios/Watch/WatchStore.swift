import Foundation
import Observation
import SwiftUI
import UIKit
import WatchConnectivity
import WatchKit
import WidgetKit

/// What the voice check screen holds: the card and the words as heard (empty: say them first).
struct VoiceDraft: Identifiable, Equatable {
    var key: String
    var words: String
    /// a235: words for this project's main chat (the Running screen's mic) rather than an answer on a card
    var projectId: String? = nil
    var id: String { key }
}

/// A picture open on the whole screen: the card and which of its pictures.
struct PictureOpen: Identifiable, Equatable {
    var key: String
    var index: Int
    var id: String { "\(key)#\(index)" }
}

/// The watch app's state (a234): the list the iPhone keeps current, the sends with their Undo, and the link to the
/// iPhone (WatchConnectivity; the iPhone side is ios/Sources/WatchLink.swift). The rules are GupKit's Watch.swift.
@Observable
@MainActor
final class WatchStore: NSObject, WCSessionDelegate {
    static let shared = WatchStore()

    private(set) var list: WatchRelay.List?
    private(set) var outbox = WatchOutbox()
    /// sends queued with transferUserInfo while the iPhone was out of reach: sent again by message once it is back
    /// (the iPhone runs each send once)
    private(set) var queued: [WatchSend] = []
    /// the card on screen
    var currentKey: String?
    var showList = false
    var voice: VoiceDraft?
    /// a235: the Running screen's mic: the check screen for words to a project's main chat
    var say: VoiceDraft?
    /// words that didn't reach the main chat: one tap brings the check screen back with them
    var sayFailed: VoiceDraft?
    var picture: PictureOpen?
    /// why the last send didn't reach the PC
    var problem: String?
    /// the screenshots' demo (-demo): fixtures/watch, no iPhone
    let demo: Bool
    let args = ProcessInfo.processInfo.arguments
    /// the demo's words as heard
    private(set) var demoWords = ""

    @ObservationIgnored private var lastIndex: Int?
    @ObservationIgnored private var ticking = false
    @ObservationIgnored private var started = false

    override init() {
        demo = ProcessInfo.processInfo.arguments.contains("-demo")
        super.init()
    }

    // MARK: start

    func start() {
        guard !started else { return }
        started = true
        if demo {
            loadDemo()
            return
        }
        load()
        if WCSession.isSupported() {
            WCSession.default.delegate = self
            WCSession.default.activate()
        }
    }

    /// Waits (at most 8 s) until WatchConnectivity has delivered what it was holding for this app, so a background
    /// wake for the iPhone's list is not ended before the list, and with it the complication's data, is in.
    func settle() async {
        start()
        guard !demo, WCSession.isSupported() else { return }
        var waited = 0
        while waited < 32, WCSession.default.activationState != .activated || WCSession.default.hasContentPending {
            try? await Task.sleep(for: .milliseconds(250))
            waited += 1
        }
    }

    private func loadDemo() {
        guard let url = Bundle.main.url(forResource: "needs", withExtension: "json", subdirectory: "watch"),
              let data = try? Data(contentsOf: url),
              let d = try? JSONDecoder().decode(WatchDemo.self, from: data) else { return }
        list = d.list(now: Date().timeIntervalSince1970, memory: args.contains("-memory"))
        demoWords = d.words
        let cards = deck.cards
        func key(_ prefix: String) -> String? { cards.first { $0.key.hasPrefix(prefix) }?.key }
        currentKey = cards.first { $0.kind != .memory }?.key
        switch screen {
        case "picture-card", "picture-full": currentKey = key("ask:lumen")
        case "permission": currentKey = key("chat:00000009")
        case "phone": currentKey = key("chat:00000003")
        case "memory", "list": currentKey = key("memory:") ?? currentKey
        default: break
        }
        if screen == "list" { currentKey = key("ask:home"); showList = true }
        if screen == "voice", let k = currentKey { voice = VoiceDraft(key: k, words: d.words) }
        if screen == "running-voice", let p = glance.rows.first?.project {
            say = VoiceDraft(key: "say:\(p.id)", words: d.words, projectId: p.id)
        }
        if screen == "running-sent", let p = glance.rows.first?.project, let w = WatchSend.say(d.words, to: p, at: now) {
            send(w)  // the demo doesn't count down: the Undo stays up for the screenshot
        }
        if screen == "picture-full", let k = currentKey { picture = PictureOpen(key: k, index: 1) }
        if screen == "answered", let c = card(currentKey), let a = c.primary {
            send(.answer(a, on: c, at: now))  // the demo doesn't count down: the Undo stays up for the screenshot
        }
    }

    /// -screen NAME: which screen the demo opens on (CI's watch screenshots)
    var screen: String {
        guard let i = args.firstIndex(of: "-screen"), i + 1 < args.count else { return "" }
        return args[i + 1]
    }

    // MARK: the deck

    var now: Double { Date().timeIntervalSince1970 }

    /// the PC's milliseconds now
    var pcNow: Double { list?.pc(at: now) ?? now * 1000 }

    var deck: WatchDeck { WatchDeck(list?.needs, now: pcNow, off: outbox.off) }

    /// a235: the Running screen's rows
    var glance: WatchGlance { WatchGlance(list?.projects) }

    func card(_ key: String?) -> WatchCard? { deck.cards.first { $0.key == key } }

    /// a235: a tap on the watch face's complication: the cards, from the top, with nothing else open over them
    func openCards() {
        showList = false
        voice = nil
        say = nil
        picture = nil
        if let first = deck.cards.first { select(first.key) }
    }

    /// a235: words for a project's main chat, after the check screen's Send; they wait out the 5 s Undo
    func sendWords(_ words: String, to p: WatchProject) {
        guard let s = WatchSend.say(words, to: p, at: now) else { return }
        sayFailed = nil
        send(s)
    }

    /// the card shown: the chosen one while it waits, else the one in its place
    var current: WatchCard? {
        let d = deck
        guard let i = d.current(after: currentKey, was: lastIndex) else { return nil }
        return d.cards[i]
    }

    func select(_ key: String) {
        currentKey = key
        lastIndex = deck.index(of: key)
    }

    func item(_ key: String?) -> NeedItem? { list?.needs.items.first { $0.key == key } }

    /// A notification's item the iPhone hasn't listed yet: on the watch's list until the iPhone's next one.
    func adopt(_ item: NeedItem) {
        guard !demo else { return }
        // made here, not by the iPhone: any list the iPhone sends replaces it
        var l = list ?? WatchRelay.List(needs: .empty, pcNow: 0, at: 0)
        guard !l.needs.items.contains(where: { $0.key == item.key }) else { return }
        l.needs.items.append(item)
        list = l
        save()
    }

    // MARK: sending

    /// An answer, snooze or dismissal: the card leaves at once, Sent shows with Undo for 5 s, then it goes.
    func send(_ s: WatchSend) {
        let d = deck
        let was = d.index(of: s.key) ?? lastIndex
        outbox.add(s)
        problem = nil
        WKInterfaceDevice.current().play(.click)
        let after = deck
        if let i = after.current(after: currentKey == s.key ? nil : currentKey, was: was) {
            currentKey = after.cards[i].key
            lastIndex = i
        }
        save()
        flush()
        if !demo { tick() }
    }

    /// whole seconds of Undo left at `date` (the demo stays at 5 for its screenshot)
    func undoLeft(at date: Date) -> Int {
        demo ? Int(WatchOutbox.undoSeconds) : outbox.left(now: date.timeIntervalSince1970)
    }

    func answer(_ a: WatchCard.Answer, on c: WatchCard) { send(.answer(a, on: c, at: now)) }

    func snooze(_ c: WatchCard) {
        send(WatchSend(what: .snooze, key: c.key, to: c.source, label: "Snooze", at: now))
    }

    func dismiss(_ c: WatchCard) {
        send(WatchSend(what: .dismiss, key: c.key, to: c.source, label: "Dismiss", at: now))
    }

    func openOnPhone(_ c: WatchCard) {
        let s = WatchSend(what: .open, key: c.key, to: c.source, label: "", at: now)
        send(s)
        flash(s)
    }

    func bringBack(_ p: WatchParked) {
        let s = WatchSend(what: .park, key: "park:\(p.projectId)", projectId: p.projectId, parked: false, to: p.name,
                          label: "", at: now)
        send(s)
        flash(s)
    }

    /// a short word after Open on iPhone or Bring back (they have no Undo)
    private(set) var notice: WatchSend?

    private func flash(_ s: WatchSend) {
        notice = s
        Task {
            try? await Task.sleep(for: .seconds(3))
            if notice?.id == s.id { notice = nil }
        }
    }

    /// Undo: nothing went, the card is back on screen.
    func undo() {
        guard let s = outbox.undo() else { return }
        if s.what != .say {
            currentKey = s.key
            lastIndex = deck.index(of: s.key)
        }
        save()
    }

    /// counts the Undo down; once it is over the answer goes to the iPhone
    private func tick() {
        guard !ticking else { return }
        ticking = true
        Task {
            while outbox.holding != nil {
                try? await Task.sleep(for: .milliseconds(250))
                outbox.tick(now: now)
            }
            ticking = false
            save()
            flush()
        }
    }

    /// Hands every send past its Undo to the iPhone: by message when it is in reach (the reply says whether the PC
    /// took it), else queued by transferUserInfo, which the system delivers once the iPhone is back.
    func flush() {
        guard !demo, WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated else { return }
        for s in outbox.ready {
            if session.isReachable {
                deliver(s, session)
            } else {
                session.transferUserInfo(WatchRelay.encode(WatchRelay.sendKey, s))
                queued.append(s)
            }
            outbox.handed(s.id, now: now)
        }
        // what waited for the iPhone goes again by message, so its answer is known
        if session.isReachable {
            for s in queued { deliver(s, session) }
        }
        save()
    }

    private func deliver(_ s: WatchSend, _ session: WCSession) {
        session.sendMessage(WatchRelay.encode(WatchRelay.sendKey, s), replyHandler: { reply in
            let error = WatchRelay.error(in: reply)
            Task { @MainActor in self.delivered(s, error: error) }
        }, errorHandler: { _ in
            // out of reach after all: the queued copy (or the next flush) takes it
            Task { @MainActor in
                if !self.queued.contains(where: { $0.id == s.id }) {
                    session.transferUserInfo(WatchRelay.encode(WatchRelay.sendKey, s))
                    self.queued.append(s)
                    self.save()
                }
            }
        })
    }

    private func delivered(_ s: WatchSend, error: String?) {
        queued.removeAll { $0.id == s.id }
        for t in WCSession.default.outstandingUserInfoTransfers {
            let sent: WatchSend? = WatchRelay.decode(WatchRelay.sendKey, t.userInfo)
            if sent?.id == s.id { t.cancel() }
        }
        if let error {
            outbox.failed(s.key)
            if s.what == .say, let p = s.projectId {
                sayFailed = VoiceDraft(key: s.key, words: s.text ?? "", projectId: p)
            }
            problem = error
            WKInterfaceDevice.current().play(.failure)
        }
        save()
    }

    // MARK: pictures

    private var pictureFolder: URL {
        let u = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("pictures")
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }

    /// the picture's file on the watch (the demo's from the app), nil until the iPhone has sent it
    func pictureFile(_ link: String) -> URL? {
        if link.hasPrefix("demo:") {
            return Bundle.main.url(forResource: String(link.dropFirst(5)), withExtension: nil, subdirectory: "watch")
        }
        let u = pictureFolder.appendingPathComponent(WatchRelay.pictureName(link))
        return FileManager.default.fileExists(atPath: u.path) ? u : nil
    }

    func image(_ link: String) -> UIImage? {
        pictureFile(link).flatMap { UIImage(contentsOfFile: $0.path) }
    }

    /// pictures the list names that the watch doesn't have; old ones go
    private func tidyPictures() {
        guard let l = list else { return }
        let want = WatchRelay.pictures(l.needs)
        let keep = Set(want.map(WatchRelay.pictureName))
        for f in (try? FileManager.default.contentsOfDirectory(atPath: pictureFolder.path)) ?? [] where !keep.contains(f) {
            try? FileManager.default.removeItem(at: pictureFolder.appendingPathComponent(f))
        }
        let missing = want.filter { pictureFile($0) == nil }
        if !missing.isEmpty { refresh(missing: missing) }
    }

    // MARK: the iPhone's list

    private func take(_ l: WatchRelay.List) {
        if let old = list, old.at > l.at { return }
        list = l
        outbox.listed(Set(l.needs.items.map(\.key)), now: now)
        save()
        tidyPictures()
    }

    /// asks the iPhone for the PC's list now (and the pictures the watch lacks)
    func refresh(missing: [String] = []) {
        guard !demo, WCSession.isSupported(), WCSession.default.activationState == .activated,
              WCSession.default.isReachable else { return }
        var msg: [String: Any] = [WatchRelay.refreshKey: true]
        if !missing.isEmpty { msg[WatchRelay.pictureKey] = missing }
        WCSession.default.sendMessage(msg, replyHandler: { reply in
            let l: WatchRelay.List? = WatchRelay.decode(WatchRelay.listKey, reply)
            Task { @MainActor in if let l { self.take(l) } }
        }, errorHandler: nil)
    }

    // MARK: kept between launches

    private struct Saved: Codable {
        var list: WatchRelay.List?
        var outbox: WatchOutbox
        var queued: [WatchSend]
    }

    private var stateFile: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("watch-state.json")
    }

    private func save() {
        guard !demo, let data = try? JSONEncoder().encode(Saved(list: list, outbox: outbox, queued: queued)) else { return }
        try? data.write(to: stateFile, options: .atomic)
        updateFace()
    }

    /// a235: the complication's data goes to the App Group the widget extension reads; the face reloads only when
    /// what it shows changed (the count, its colour, the oldest one), so the system's reload budget is kept.
    private func updateFace() {
        guard WatchFace.save(list: list, off: outbox.off, now: now, UserDefaults(suiteName: WatchFace.group)) else { return }
        WidgetCenter.shared.reloadAllTimelines()
    }

    private func load() {
        guard let data = try? Data(contentsOf: stateFile), let s = try? JSONDecoder().decode(Saved.self, from: data) else { return }
        list = s.list
        outbox = s.outbox
        queued = s.queued
        currentKey = deck.cards.first?.key
        if outbox.holding != nil { tick() }
        updateFace()
    }

    // MARK: WCSessionDelegate

    nonisolated func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {
        let l: WatchRelay.List? = WatchRelay.decode(WatchRelay.listKey, session.receivedApplicationContext)
        Task { @MainActor in
            if let l { self.take(l) }
            self.flush()
            self.refresh()
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext context: [String: Any]) {
        let l: WatchRelay.List? = WatchRelay.decode(WatchRelay.listKey, context)
        Task { @MainActor in if let l { self.take(l) } }
    }

    nonisolated func session(_ session: WCSession, didReceive file: WCSessionFile) {
        guard let link = file.metadata?[WatchRelay.pictureKey] as? String else { return }
        // the file is gone once this returns: move it now
        let folder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("pictures")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let dest = folder.appendingPathComponent(WatchRelay.pictureName(link))
        try? FileManager.default.removeItem(at: dest)
        try? FileManager.default.moveItem(at: file.fileURL, to: dest)
        Task { @MainActor in self.picturesChanged += 1 }
    }

    /// bumps when a picture arrives, so the open card draws it
    var picturesChanged = 0

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        guard session.isReachable else { return }
        Task { @MainActor in
            self.flush()
            self.refresh()
        }
    }

    // MARK: the notification's buttons

    /// A button on the watch's own notification (or the iPhone's category, should the dynamic one not show), or a tap
    /// on it: the app opens at that card and an answer waits out its Undo here.
    func respond(action: String, info: [AnyHashable: Any], text: String?) {
        let key = info["needs"] as? String
        if let pushed = WatchNotice.item(info) { adopt(pushed) }
        guard let key, let c = card(key) ?? item(key).map(WatchCard.init) else { return }
        select(c.key)
        let g = info["gw3"] as? [String: Any] ?? [:]
        func n(_ name: String) -> Int? { (g[name] as? Int) ?? (g[name] as? NSNumber)?.intValue }
        switch action {
        case WatchNotice.say:
            voice = VoiceDraft(key: c.key, words: "")
        case WatchNotice.open:
            openOnPhone(c)
        case "gw3.other":
            // the iPhone's text button: his words still come back to read first
            voice = VoiceDraft(key: c.key, words: text ?? "")
        case "gw3.rec", "gw3.allow", "gw3.deny", "gw3.sleep":
            let name = String(action.dropFirst(4))
            let pool = c.answers + [c.allow, c.deny, c.sleep].compactMap { $0 }
            if let o = n(name) ?? (name == "sleep" ? 0 : nil), let a = pool.first(where: { $0.option == o }) {
                send(.answer(a, on: c, at: now))
            }
        default:
            if let s = WatchNotice.send(action, card: c, at: now) { send(s) }
        }
    }
}
