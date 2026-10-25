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

    // MARK: the menu (5c, 5d)

    /// Pinned in its order: chats and projects (an older PC without the order: its pinned chats).
    var pinnedItems: [PinItem] { home.map(Self.pinnedItems) ?? [] }

    static func pinnedItems(_ h: Home) -> [PinItem] {
        let chats = h.setups + h.chats
        guard let order = h.pinned else { return chats.filter(\.pinned).map { .chat($0) } }
        return order.compactMap { r in
            if r.kind == "project" { return h.projects.first { $0.id == r.id }.map { .project($0) } }
            return chats.first { $0.id == r.id }.map { .chat($0) }
        }
    }

    /// every other chat, newest first
    var recents: [ChatRow] { home.map(Self.recents) ?? [] }

    static func recents(_ h: Home) -> [ChatRow] {
        let pinned = Set(pinnedItems(h).compactMap { if case .chat(let c) = $0 { return c.id } else { return nil } })
        return (h.setups + h.chats).filter { !pinned.contains($0.id) && !$0.pinned }
            .sorted { $0.lastActive > $1.lastActive }
    }

    /// a project or chat waits on you: the menu button's violet dot
    var needsYou: Bool {
        guard let h = home else { return false }
        let waiting: Set<String> = ["needs", "permission"]
        return h.projects.contains { waiting.contains($0.state) } || (h.setups + h.chats).contains { waiting.contains($0.state) }
    }

    func isPinned(project id: String) -> Bool {
        home?.pinned?.contains(PinRef(kind: "project", id: id)) ?? false
    }

    /// Pins a project (first in Pinned) or unpins it; projects are pinned only on the phone.
    func togglePin(project id: String) async {
        let ref = PinRef(kind: "project", id: id)
        var order = pinnedItems.map(\.ref)
        if order.contains(ref) { order.removeAll { $0 == ref } } else { order.insert(ref, at: 0) }
        await setPinned(order)
    }

    /// Pinned in a new order (5d's Done, or a pin or unpin): shown at once, then sent; the PC answers with the home.
    func setPinned(_ order: [PinRef]) async {
        guard var h = home else { return }
        let chats = Set(order.filter { $0.kind == "chat" }.map(\.id))
        h.pinned = order
        h.setups = h.setups.map { var c = $0; c.pinned = chats.contains(c.id); return c }
        h.chats = h.chats.map { var c = $0; c.pinned = chats.contains(c.id); return c }
        home = h
        if demo { return }
        guard let p = pairing else { return }
        do {
            home = try await api.setPinned(p, order)
        } catch {
            actionError = APIError.from(error).message
            await refresh()
        }
    }

    /// Chats whose words match (5c's search): the PC's search; the demo's comes from its fixture.
    func search(_ q: String) async -> [SearchHit] {
        let q = q.trimmingCharacters(in: .whitespaces)
        guard q.count >= 2 else { return [] }
        if demo {
            let r: SearchReply? = Demo.load("search")
            return r?.chats ?? []
        }
        guard let p = pairing else { return [] }
        return (try? await api.search(p, q))?.chats ?? []
    }

    private func showLocally(_ id: String, _ e: ChatEdit, deleted: Bool) {
        guard var h = home else { return }
        let ref = PinRef(kind: "chat", id: id)
        if deleted || e.archived == true || e.pinned == false {
            h.pinned?.removeAll { $0 == ref }
        } else if e.pinned == true, h.pinned?.contains(ref) == false {
            h.pinned?.insert(ref, at: 0)  // a fresh pin goes first, as the PC lists it
        }
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

/// One row of the menu's Pinned.
enum PinItem: Identifiable, Equatable {
    case chat(ChatRow)
    case project(ProjectRow)

    var ref: PinRef {
        switch self {
        case .chat(let c): return PinRef(kind: "chat", id: c.id)
        case .project(let p): return PinRef(kind: "project", id: p.id)
        }
    }

    var id: String { "\(ref.kind)-\(ref.id)" }

    var title: String {
        switch self {
        case .chat(let c): return c.title
        case .project(let p): return p.name
        }
    }
}
