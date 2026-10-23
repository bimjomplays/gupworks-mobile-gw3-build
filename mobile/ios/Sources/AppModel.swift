import Foundation
import Observation

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
        let p = try await api.pair(link)
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
