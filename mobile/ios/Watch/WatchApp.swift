import SwiftUI
import UserNotifications
import WatchKit

/// GupWorks on the Apple Watch (a234, docs/watch-mockups/round2 Option 7 "Crown list with voice"): the needs-you
/// cards on the wrist, answered by a tap on a row, a double tap on the recommended answer, or by voice with a read-back
/// before Send; every send has a 5 s Undo. A companion app: its list and answers go through the iPhone app.
@main
struct GupWorksWatchApp: App {
    @WKApplicationDelegateAdaptor(WatchDelegate.self) private var delegate
    @State private var store = WatchStore.shared

    var body: some Scene {
        WindowGroup {
            Group {
                if store.demo && store.screen == "notification" {
                    NoticePreview()
                } else {
                    DeckScreen()
                }
            }
            .environment(store)
            .tint(Look.light)
            .task { store.start() }
        }
        // the categories gw3-phone names (gw3_push.category, GupKit PushCategory): each gets the card's own view
        WKNotificationScene(controller: NoticeController.self, category: "gw3.ask.rec.other")
        WKNotificationScene(controller: NoticeController.self, category: "gw3.ask.rec")
        WKNotificationScene(controller: NoticeController.self, category: "gw3.ask.other")
        WKNotificationScene(controller: NoticeController.self, category: "gw3.ask")
        WKNotificationScene(controller: NoticeController.self, category: "gw3.permission")
        WKNotificationScene(controller: NoticeController.self, category: "gw3.memory")
        WKNotificationScene(controller: NoticeController.self, category: "gw3.open")
    }
}

/// The notification's buttons and taps land here: the app opens at that card (WatchStore.respond).
final class WatchDelegate: NSObject, WKApplicationDelegate, UNUserNotificationCenterDelegate {
    func applicationDidFinishLaunching() {
        UNUserNotificationCenter.current().delegate = self
        Task { @MainActor in WatchStore.shared.start() }
    }

    func applicationDidBecomeActive() {
        Task { @MainActor in WatchStore.shared.refresh() }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                            withCompletionHandler done: @escaping (UNNotificationPresentationOptions) -> Void) {
        let info = notification.request.content.userInfo
        let item = WatchNotice.item(info)
        Task { @MainActor in if let item { WatchStore.shared.adopt(item) } }
        done([.banner, .list, .sound])
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                            withCompletionHandler done: @escaping () -> Void) {
        let info = response.notification.request.content.userInfo
        let action = response.actionIdentifier
        let text = (response as? UNTextInputNotificationResponse)?.userText
        nonisolated(unsafe) let payload = info
        Task { @MainActor in
            WatchStore.shared.respond(action: action, info: payload, text: text)
            done()
        }
    }
}

/// The demo's stand-in for the notification's long look (CI's screenshot when the simulator's push doesn't show it):
/// the same NoticeView with the app's name above and the buttons the notification gets below.
struct NoticePreview: View {
    @Environment(WatchStore.self) private var store

    var body: some View {
        let card = store.deck.cards.first { $0.key.hasPrefix("ask:home") }
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.left.forwardslash.chevron.right")
                        .font(.system(size: 10, weight: .bold))
                        .frame(width: 20, height: 20)
                        .background(Circle().fill(Look.mic))
                    Text("GupWorks").font(.system(size: 14, weight: .semibold))
                    Spacer()
                    Text("now").font(.system(size: 14)).foregroundStyle(Color(hex: 0x8E8E93))
                }
                NoticeView(card: card, now: store.pcNow)
                ForEach(card.map(WatchNotice.buttons) ?? [], id: \.id) { b in
                    Text(b.title)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(b.destructive ? Look.red : .white)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Color(hex: 0x262628)))
                }
            }
            .padding(.horizontal, 2)
        }
    }
}
