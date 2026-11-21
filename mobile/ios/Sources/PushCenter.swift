import SwiftUI
import UserNotifications

/// Apple push (a233): registers this phone with gw3-phone, runs a notification's buttons in the background (also
/// with the phone locked, through the answer-only token) and takes delivered notifications back once their item is
/// answered or dismissed anywhere. The rules are GupKit's (Push.swift); this is the UIKit and UserNotifications side.
@Observable
@MainActor
final class PushCenter {
    static let shared = PushCenter()

    /// why this build can't get push (no aps-environment, simulator), for Settings
    var problem: String?
    /// the PC's last word on push (GET or POST /v1/push…), for Settings
    var status: PushStatus?

    @ObservationIgnored private let api = APIClient()
    @ObservationIgnored private var registered: String?  // the pairing and token this launch registered

    /// At every launch, a background one for a button included: the categories first, so the buttons exist.
    func start() {
        UNUserNotificationCenter.current().setNotificationCategories(Self.categories)
        if PairingStore.load() != nil { ask() }
    }

    /// Paired and in front: allow notifications (iOS asks once) and get this phone's push token.
    func ask() {
        guard !Demo.isOn, NSClassFromString("XCTestCase") == nil else { return }
        Task {
            let center = UNUserNotificationCenter.current()
            let ok = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
            if ok { UIApplication.shared.registerForRemoteNotifications() }
        }
    }

    static var categories: Set<UNNotificationCategory> {
        Set(PushCategory.all.map { c in
            let actions: [UNNotificationAction] = c.buttons.map { b in
                // no .foreground: the button runs in the background; no .authenticationRequired: it works from the
                // watch and a locked phone (iOS still hides the buttons on a locked phone while previews are hidden)
                let options: UNNotificationActionOptions = b.destructive ? [.destructive] : []
                if b.text {
                    return UNTextInputNotificationAction(identifier: b.id, title: b.title, options: options,
                                                         textInputButtonTitle: PushCategory.sendTitle,
                                                         textInputPlaceholder: PushCategory.placeholder)
                }
                return UNNotificationAction(identifier: b.id, title: b.title, options: options)
            }
            return UNNotificationCategory(identifier: c.id, actions: actions, intentIdentifiers: [], options: [])
        })
    }

    /// iOS gave the push token: gw3-phone gets it with the pairing's token (readable only while unlocked: a
    /// background launch registers on the next one), and an answer-only token comes back the first time.
    func got(token data: Data) {
        problem = nil
        guard let p = PairingStore.load() else { return }
        let hex = PushToken.hex(data)
        let mark = "\(p.baseURL.absoluteString) \(p.pairedAt.timeIntervalSince1970) \(hex)"
        guard registered != mark else { return }
        let pass = AnswerPassStore.load()
        let body = PushRegistration(token: hex, environment: PushEnvironment.of(profile: Self.profile),
                                    device: UIDevice.current.name,
                                    team: PushToken.team(Bundle.main.object(forInfoDictionaryKey: "GW3Team") as? String),
                                    answer: pass == nil || pass?.baseURL != p.baseURL)
        Task {
            do {
                let r = try await api.registerPush(p, body)
                if let t = r.answerToken { AnswerPassStore.save(AnswerPass(baseURL: p.baseURL, token: t)) }
                status = r.push
                registered = mark
            } catch {
                // a PC from before a233 has no push route: nothing to do until it's updated
            }
        }
    }

    func failed(_ error: Error) {
        problem = "This build can't get notifications: \(error.localizedDescription)"
    }

    private static var profile: Data? {
        Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision").flatMap { try? Data(contentsOf: $0) }
    }

    /// A notification's button, in the background: one request to the PC. When it doesn't go through, a
    /// notification says so (a tap on it opens the card, as the original's would).
    func perform(_ action: PushAction) async {
        guard let c = PushAnswerer.credentials(pass: AnswerPassStore.load(), pairing: PairingStore.load()) else {
            await tell(action, "Open GupWorks to answer: this phone can't reach its key right now.")
            return
        }
        do {
            try await api.perform(action, base: c.base, token: c.token)
        } catch {
            await tell(action, "Your answer didn't reach the PC: \(APIError.from(error).message)")
        }
    }

    private func tell(_ action: PushAction, _ text: String) async {
        let n = UNMutableNotificationContent()
        n.title = "Not sent"
        n.body = text
        n.sound = .default
        n.userInfo = ["needs": action.key]
        try? await UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: "gw3-failed-\(action.key)", content: n, trigger: nil))
    }

    /// The silent push's gone/live keys, or a fresh list from the PC (`live` only): delivered notifications of
    /// items no longer waiting go (the watch's mirrored ones with them).
    func takeBack(gone: Set<String> = [], live: Set<String>?) async {
        let center = UNUserNotificationCenter.current()
        let delivered = await center.deliveredNotifications()
        let ids = PushPayload.toRemove(delivered.map { ($0.request.identifier, PushPayload.key($0.request.content.userInfo)) },
                                       gone: gone, live: live)
        if !ids.isEmpty { center.removeDeliveredNotifications(withIdentifiers: ids) }
    }

    /// Settings: the PC's word on push now
    func refresh(_ p: Pairing) async {
        if let s = try? await api.pushStatus(p) { status = s }
    }
}
