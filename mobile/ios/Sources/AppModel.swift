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
            self.error = .unreachable
        }
    }
}
