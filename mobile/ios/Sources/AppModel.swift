import Foundation
import Observation
import UIKit

/// The app's state: the pairing (Keychain), the last home list and what went wrong last.
@Observable
@MainActor
final class AppModel {
    private(set) var pairing: Pairing?
    private(set) var home: Home?
    private(set) var hello: Hello?
    private(set) var error: APIError?
    private(set) var loading = false
    private(set) var lastRefresh: Date?
    /// a rename, pin, archive or delete the PC refused or never got, for an alert
    var actionError: String?
    /// a gupworks3://pair link the system opened the app with (iPhone camera scan), for the pairing screen
    var incomingLink: String?

    let demo: Bool
    private let api = APIClient()

    init() {
        let args = ProcessInfo.processInfo.arguments
        demo = Demo.isOn
        if demo {
            pairing = args.contains("-unpaired") ? nil : Demo.pairing
        } else {
            pairing = PairingStore.load()
        }
    }

    var isPaired: Bool { pairing != nil }

    func pair(with link: PairLink) async throws {
        let p = try await api.pair(link, device: UIDevice.current.name)
        guard PairingStore.save(p) else { throw APIError.server("The phone couldn't keep the key (Keychain).") }
        pairing = p
        error = nil
        home = nil  // RootView's task loads the list for the new pairing
    }

    func unpair() {
        if !demo { PairingStore.clear() }
        pairing = nil
        home = nil
        hello = nil
        error = nil
    }

    /// Keeps the list live from the PC's home stream until the task is cancelled (the app leaves the front).
    func followHome() async {
        guard !demo, let p = pairing else { return }
        var wait: UInt64 = 2
        while !Task.isCancelled {
            do {
                for try await e in api.events(p, "/v1/home/events") where e.name == "home" {
                    if let h = try? JSONDecoder().decode(Home.self, from: Data(e.data.utf8)) {
                        home = h
                        error = nil
                        lastRefresh = Date()
                    }
                    wait = 2
                }
            } catch let e as APIError {
                if Task.isCancelled { return }
                if e == .notPaired { error = e; return }
            } catch {
                if Task.isCancelled { return }
            }
            try? await Task.sleep(nanoseconds: wait * 1_000_000_000)
            wait = min(wait * 2, 30)
        }
    }

    func refresh() async {
        guard let p = pairing else { return }
        if demo {
            home = Demo.home
            hello = Demo.load("hello")
            lastRefresh = Date()
            return
        }
        loading = true
        defer { loading = false }
        do {
            home = try await api.home(p)
            error = nil
            lastRefresh = Date()
            if hello == nil { hello = try? await api.hello(p) }
        } catch let e as APIError {
            error = e
        } catch {
            self.error = APIError.from(error)
        }
    }

    // MARK: chat edits (slice 3): shown in the list at once, then sent; the PC's next list has them too

    /// Rename, pin or archive one of the Chats. False when it didn't go through (the list is read again).
    @discardableResult
    func edit(_ id: String, _ e: ChatEdit) async -> Bool {
        showLocally(id, e, deleted: false)
        if demo { return true }
        guard let p = pairing else { return false }
        do {
            try await api.editChat(p, id, e)
            return true
        } catch {
            actionError = APIError.from(error).message
            await refresh()
            return false
        }
    }

    /// Deletes a chat as the desktop does: out of the list and its process ended; the PC keeps its transcript, so
    /// it can be brought back there (`gw3-phone restore`).
    @discardableResult
    func delete(_ id: String) async -> Bool {
        showLocally(id, ChatEdit(), deleted: true)
        if demo { return true }
        guard let p = pairing else { return false }
        do {
            try await api.deleteChat(p, id)
            return true
        } catch {
            actionError = APIError.from(error).message
            await refresh()
            return false
        }
    }

    private func showLocally(_ id: String, _ e: ChatEdit, deleted: Bool) {
        guard var h = home else { return }
        var archived = 0
        func change(_ rows: [ChatRow]) -> [ChatRow] {
            var out: [ChatRow] = []
            for var c in rows {
                guard c.id == id else { out.append(c); continue }
                if deleted || e.archived == true {
                    if e.archived == true { archived += 1 }
                    continue
                }
                if let t = e.title { c.title = t }
                if let p = e.pinned { c.pinned = p }
                out.append(c)
            }
            // pinned first, as the PC lists them (the rest keep their order)
            return out.filter(\.pinned) + out.filter { !$0.pinned }
        }
        h.setups = change(h.setups)
        h.chats = change(h.chats)
        h.archivedCount += archived
        home = h
    }
}
