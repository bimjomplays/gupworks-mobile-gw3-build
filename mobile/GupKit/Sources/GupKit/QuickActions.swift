import Foundation
import Observation

/// One of Quick actions' switches, as gw3-phone's GET /v1/quick reads it from the PC (tools/gw3_quick.py): Away mode
/// and Dillon's game bot are toggles (`on`, nil when their status didn't answer), Restart PC a button (`allowed`, and
/// `reason` when logind or the PC says no).
struct QuickSwitch: Codable, Equatable, Identifiable {
    var id: String
    var label: String
    var kind: String?
    var on: Bool?
    var allowed: Bool?
    var detail: String?
    var warning: String?
    var reason: String?
    var error: String?

    var isToggle: Bool { kind != "button" }
}

struct QuickList: Codable, Equatable {
    var switches: [QuickSwitch]
    var error: String?
}

struct QuickConfirm: Codable, Equatable {
    var confirm: String
    var question: String?
    var seconds: Int?
}

struct QuickRestarted: Codable, Equatable {
    var ok: Bool
    var restarting: Bool?
}

/// The Quick actions page's data. Every state shown is the PC's answer, read again after each switch and whenever the
/// page or the app comes back to the front; a failed switch keeps its error under it until the next try or the next
/// visit. The demo answers from mobile/fixtures/quick.json (`-quickError` shows the errors and the warning).
@Observable
@MainActor
final class QuickStore {
    private(set) var switches: [QuickSwitch] = []
    /// the page couldn't be read at all (no answer from the PC)
    private(set) var error: APIError?
    private(set) var loaded = false
    /// switches with a change on its way (their row shows a spinner)
    private(set) var busy: Set<String> = []
    /// errors of the phone's own tries (a switch that failed, a restart refused), by switch
    private(set) var tried: [String: String] = [:]
    /// Restart PC went through: the PC is going down
    private(set) var restarting = false

    let pairing: Pairing?
    let demo: Bool
    private let api = APIClient()

    init(pairing: Pairing?, demo: Bool) {
        self.pairing = pairing
        self.demo = demo
    }

    func state(_ id: String) -> QuickSwitch? { switches.first { $0.id == id } }

    /// what shows in red under the switch: the phone's own try, else what the PC's status said
    func errorText(_ id: String) -> String? {
        if let t = tried[id], !t.isEmpty { return t }
        if let e = state(id)?.error, !e.isEmpty { return e }
        return nil
    }

    /// the page opens again: old tries' errors go
    func forgetTries() { tried = [:] }

    func refresh() async {
        if demo { return loadDemo() }
        guard let p = pairing else { return }
        do {
            switches = try await api.quick(p).switches
            error = nil
            loaded = true
        } catch {
            let e = APIError.from(error)
            if Task.isCancelled || e.isCancelled { return }
            self.error = e
        }
    }

    /// Away mode or Dillon's game bot: the PC switches it and reads every switch again
    func set(_ id: String, on: Bool) async {
        guard !busy.contains(id) else { return }
        busy.insert(id)
        tried[id] = nil
        defer { busy.remove(id) }
        if demo {
            try? await Task.sleep(nanoseconds: 300_000_000)
            if Demo.args.contains("-quickError") {
                tried[id] = "\(state(id)?.label ?? id) didn't switch: exit 1 (demo)"
                return
            }
            if let i = switches.firstIndex(where: { $0.id == id }) { switches[i].on = on }
            return
        }
        guard let p = pairing else { return }
        do {
            let r = try await api.setQuick(p, id, on: on)
            switches = r.switches
            if let e = r.error, !e.isEmpty { tried[id] = e }
        } catch {
            tried[id] = APIError.from(error).message
            await refresh()  // whatever it is now, not what was asked for
        }
    }

    /// Restart PC was pressed: a fresh check on the PC and the dialog's one-time token, or nil (its error shows)
    func askRestart() async -> QuickConfirm? {
        tried["restart-pc"] = nil
        if demo { return QuickConfirm(confirm: "demo", question: "Restart the PC now?", seconds: 60) }
        guard let p = pairing else { return nil }
        do {
            return try await api.restartConfirm(p)
        } catch {
            tried["restart-pc"] = APIError.from(error).message
            await refresh()
            return nil
        }
    }

    /// the dialog's Restart: only with the token its opening got
    func restart(_ confirm: QuickConfirm) async {
        guard !busy.contains("restart-pc") else { return }
        busy.insert("restart-pc")
        defer { busy.remove("restart-pc") }
        if demo {
            restarting = true
            return
        }
        guard let p = pairing else { return }
        do {
            restarting = try await api.restartPC(p, confirm: confirm.confirm).ok
        } catch {
            tried["restart-pc"] = APIError.from(error).message
        }
    }

    private func loadDemo() {
        guard !loaded, var list: QuickList = Demo.load("quick") else { return }
        if Demo.args.contains("-quickError") {
            for i in list.switches.indices {
                switch list.switches[i].id {
                case "away": list.switches[i].warning = "gupworks-away.service isn't running"
                case "game-bot":
                    list.switches[i].on = nil
                    list.switches[i].error = "tmux: no server running"
                default:
                    list.switches[i].allowed = false
                    list.switches[i].reason = "logind CanReboot: challenge (it would ask for a password)"
                }
            }
        }
        switches = list.switches
        loaded = true
    }
}
