import SwiftUI
import UserNotifications

/// A Studio video chat's question as a phone notification (a180). The app has no push yet (mobile-app-plan slice 7),
/// so these are local notifications posted when the PC's home list shows a new question while the app runs; a tap
/// opens the video (MainView reads `open`).
@Observable
@MainActor
final class StudioAlerts: NSObject, UNUserNotificationCenterDelegate {
    static let shared = StudioAlerts()

    /// the video a tapped notification asks for
    var open: StudioRoute?

    @ObservationIgnored private var asked = false
    @ObservationIgnored private let seenKey = "gw3.studio.notified"

    private override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }

    /// Posts the questions not notified yet; remembers the rest so a relaunch doesn't post them again.
    func post(_ needs: [StudioNeed]) {
        let keys = needs.map(Self.key)
        let seen = Set(UserDefaults.standard.stringArray(forKey: seenKey) ?? [])
        UserDefaults.standard.set(keys, forKey: seenKey)
        let fresh = needs.filter { !seen.contains(Self.key($0)) }
        guard !fresh.isEmpty, !Demo.isOn else { return }
        Task {
            let center = UNUserNotificationCenter.current()
            if !asked {
                asked = true
                _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
            }
            for n in fresh {
                let c = UNMutableNotificationContent()
                c.title = "\(n.title) needs you"
                c.subtitle = n.channel
                c.body = n.question
                c.sound = .default
                c.threadIdentifier = "studio-\(n.projectId)"
                c.userInfo = ["studioProject": n.projectId, "studioVideo": n.videoId]
                try? await center.add(UNNotificationRequest(identifier: "studio-\(Self.key(n))", content: c, trigger: nil))
            }
        }
    }

    /// one question once: the video and when it was asked
    nonisolated static func key(_ n: StudioNeed) -> String { "\(n.id)@\(Int(n.ts))" }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                            withCompletionHandler done: @escaping (UNNotificationPresentationOptions) -> Void) {
        done([.banner, .list, .sound])
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                            withCompletionHandler done: @escaping () -> Void) {
        let info = response.notification.request.content.userInfo
        if let pid = info["studioProject"] as? String, let vid = info["studioVideo"] as? String {
            Task { @MainActor in StudioAlerts.shared.open = .video(pid, vid, stage: nil) }
        }
        done()
    }
}
