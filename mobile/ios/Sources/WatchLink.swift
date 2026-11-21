import SwiftUI
import UIKit
import UserNotifications
import WatchConnectivity

/// The iPhone side of the watch app (a234, docs/watch-mockups/round2 Option 7). Tailscale has no watch app, so the
/// watch reaches the PC through this phone: it keeps the watch's list current (updateApplicationContext: the latest
/// wins, also when the watch was away), sends the asks' pictures shrunk to watch size (transferFile), and runs the
/// watch's answers through the same code as a notification's buttons (PushCenter.perform, the answer-only token, so
/// it works while the phone is locked). The rules and the wire format are GupKit's (Watch.swift).
@MainActor
final class WatchLink: NSObject, WCSessionDelegate {
    static let shared = WatchLink()

    /// the list the watch has (or will have once it wakes)
    private var last: WatchRelay.List?
    /// pictures offered this launch (the watch asks again for any it lacks)
    private var offered = Set<String>()
    private let api = APIClient()
    private static let doneKey = "gw3.watch.done"

    private var session: WCSession? {
        guard WCSession.isSupported(), !Demo.isOn, NSClassFromString("XCTestCase") == nil else { return nil }
        return WCSession.default
    }

    /// At every launch (a background one for a push or a watch message included).
    func start() {
        guard let s = session else { return }
        s.delegate = self
        s.activate()
    }

    private var watchReady: WCSession? {
        guard let s = session, s.activationState == .activated, s.isPaired, s.isWatchAppInstalled else { return nil }
        return s
    }

    /// A fresh list from the PC (the app in front follows it live): the watch gets it.
    func update(_ needs: NeedsState, pcNow: Double, projects: [WatchProject]?) {
        send(WatchRelay.List(needs: needs, pcNow: pcNow, at: Date().timeIntervalSince1970, projects: projects))
    }

    /// gw3-phone's silent push: an item was answered or dismissed elsewhere, so it leaves the watch too.
    func takeBack(gone: Set<String>, live: Set<String>?) {
        guard let base = last ?? sentList else { return }
        send(base.without(gone: gone, live: live))
    }

    private var sentList: WatchRelay.List? {
        guard let s = session else { return nil }
        return WatchRelay.decode(WatchRelay.listKey, s.applicationContext)
    }

    private func send(_ list: WatchRelay.List) {
        last = list
        guard let s = watchReady else { return }
        try? s.updateApplicationContext(WatchRelay.encode(WatchRelay.listKey, list))
        Task { await sendPictures(WatchRelay.pictures(list.needs).filter { !offered.contains($0) }) }
    }

    /// The PC's list now when this phone can read its pairing (unlocked), else the last one the watch got.
    private func freshList() async -> WatchRelay.List? {
        if let p = PairingStore.load(), let h = try? await api.home(p), let n = h.needs {
            let l = WatchRelay.List(needs: n, pcNow: h.now, at: Date().timeIntervalSince1970, projects: WatchProject.list(h))
            send(l)
            return l
        }
        return last ?? sentList
    }

    // MARK: pictures

    /// Fetches each picture (signed /v1/media links: no token needed), shrinks it to watch size and hands it over.
    private func sendPictures(_ links: [String]) async {
        guard let s = watchReady, let base = PairingStore.load()?.baseURL else { return }
        for link in links {
            guard let url = MediaLink.url(link, base: base),
                  let got = try? await URLSession.shared.data(from: url),
                  let image = UIImage(data: got.0) else { continue }
            let px = (image.size.width * image.scale, image.size.height * image.scale)
            let fit = WatchRelay.fit(width: px.0, height: px.1)
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            let small = UIGraphicsImageRenderer(size: CGSize(width: fit.width, height: fit.height), format: format).image { _ in
                image.draw(in: CGRect(x: 0, y: 0, width: fit.width, height: fit.height))
            }
            guard let jpeg = small.jpegData(compressionQuality: 0.82) else { continue }
            let file = FileManager.default.temporaryDirectory.appendingPathComponent(WatchRelay.pictureName(link))
            guard (try? jpeg.write(to: file)) != nil else { continue }
            s.transferFile(file, metadata: [WatchRelay.pictureKey: link])
            offered.insert(link)
        }
    }

    // MARK: what the watch sends

    /// An answer, snooze, dismissal, Bring back or Open on iPhone. `queued`: it came by transferUserInfo (the watch
    /// was out of reach), so nobody waits for the reply: a failure becomes the phone's own "Not sent" notification,
    /// which the watch mirrors while the phone is locked.
    private func handle(_ s: WatchSend, queued: Bool) async -> String? {
        // the watch sends again by message what it queued while away: each send goes once
        var done = UserDefaults.standard.stringArray(forKey: Self.doneKey) ?? []
        if done.contains(s.id) { return nil }
        done = Array((done + [s.id]).suffix(60))
        UserDefaults.standard.set(done, forKey: Self.doneKey)
        if s.what == .open {
            await openOnPhone(s)
            return nil
        }
        if s.what == .say {
            let error = await sayToMainChat(s, queued: queued)
            if error != nil { UserDefaults.standard.set(done.filter { $0 != s.id }, forKey: Self.doneKey) }
            return error
        }
        guard let action = PushAction(s) else { return "The watch sent something this iPhone doesn't know." }
        let error = await PushCenter.shared.perform(action, tell: queued)
        if error != nil {
            // not sent: the watch may try it again
            UserDefaults.standard.set(done.filter { $0 != s.id }, forKey: Self.doneKey)
        }
        if error == nil {
            // the watch's list without it at once; the PC's own list follows when this phone can read it
            if let l = last ?? sentList, s.what != .park, !s.key.hasPrefix("memory:") {
                send(l.without(gone: [s.key], live: nil))
            }
            _ = await freshList()
        }
        return error
    }

    /// a235: words from the Running screen's mic, as his own message to that project's main chat. The iPhone finds the
    /// main chat itself from the PC's project list (the watch names only the project), and sends with the pairing's
    /// own token, so a locked iPhone says so: the words can't go until it is unlocked.
    private func sayToMainChat(_ s: WatchSend, queued: Bool) async -> String? {
        let words = (s.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard let project = s.projectId, !words.isEmpty else { return "The watch sent something this iPhone doesn't know." }
        let why: String
        if let p = PairingStore.load() {
            do {
                let home = try await api.home(p)
                guard let chat = home.listed.first(where: { $0.id == project })?.mainChatId, !chat.isEmpty else {
                    return "That project has no main chat to tell."
                }
                _ = try await api.send(p, chat: chat, OutgoingBody(clientId: s.id, text: words, files: []))
                return nil
            } catch {
                why = "Your words didn't reach the PC: \(APIError.from(error).message)"
            }
        } else {
            why = "Unlock your iPhone, then say it again: it can't send words to a chat while it is locked."
        }
        if queued { await notifyNotSent(s, why) }
        return why
    }

    private func notifyNotSent(_ s: WatchSend, _ text: String) async {
        let n = UNMutableNotificationContent()
        n.title = "Not sent to \(s.to)"
        n.body = text
        n.sound = .default
        try? await UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: "gw3-failed-\(s.key)", content: n, trigger: nil))
    }

    /// "Open on iPhone": a notification on this phone that opens the deck at the card (several questions, tabs).
    private func openOnPhone(_ s: WatchSend) async {
        let n = UNMutableNotificationContent()
        n.title = s.to
        n.body = "Waiting on you: tap to answer it here."
        n.sound = .default
        n.userInfo = ["needs": s.key]
        try? await UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: "gw3-open-\(s.key)", content: n, trigger: nil))
    }

    private func refresh(missing: [String]) async -> [String: Any] {
        let list = await freshList()
        offered.subtract(missing)
        Task { await sendPictures(missing) }
        return list.map { WatchRelay.encode(WatchRelay.listKey, $0) } ?? [:]
    }

    // MARK: WCSessionDelegate

    nonisolated func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {
        Task { @MainActor in
            if let l = self.last { self.send(l) }  // a list made before the session was ready
        }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        session.activate()  // a new watch was paired: start over with it
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any],
                             replyHandler: @escaping ([String: Any]) -> Void) {
        nonisolated(unsafe) let reply = replyHandler
        let send: WatchSend? = WatchRelay.decode(WatchRelay.sendKey, message)
        let refresh = message[WatchRelay.refreshKey] as? Bool == true
        let missing = message[WatchRelay.pictureKey] as? [String] ?? []
        Task { @MainActor in
            if let send {
                reply(WatchRelay.reply(error: await self.handle(send, queued: false)))
            } else if refresh {
                reply(await self.refresh(missing: missing))
            } else {
                reply(WatchRelay.reply(error: "The watch sent something this iPhone doesn't know."))
            }
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        guard let send: WatchSend = WatchRelay.decode(WatchRelay.sendKey, userInfo) else { return }
        Task { @MainActor in _ = await self.handle(send, queued: true) }
    }
}
