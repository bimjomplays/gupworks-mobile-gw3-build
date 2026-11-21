import SwiftUI
import UserNotifications
import WatchKit

/// The watch app's own notification (round 2 screen 1): the wrist tap shows the card's top (where it's from, the
/// thread, the whole question and summary) and every answer with its detail, and the buttons under it are the ask's
/// real answers (the iPhone's notification can only say "Send recommended"). The first button is the recommended
/// answer, which a double tap presses on a notification (watchOS 10.1+); on a command it is Deny. Each button opens
/// the app, where the answer shows Sent with its 5 s Undo before it goes (WatchStore.respond).
final class NoticeController: WKUserNotificationHostingController<NoticeBody> {
    // WKUserNotificationHostingController has no setNeedsBodyUpdate (CI run 44865801797): the body watches this
    private let shown = NoticeShown()

    override var body: NoticeBody { NoticeBody(shown: shown) }

    override func didReceive(_ notification: UNNotification) {
        let content = notification.request.content
        let info = content.userInfo
        let pushed = WatchNotice.item(info)
        let item = pushed ?? WatchStore.shared.item(info["needs"] as? String)
        if let pushed { WatchStore.shared.adopt(pushed) }
        let card = item.map(WatchCard.init)
        shown.card = card
        shown.title = content.title
        shown.text = content.body
        notificationActions = card.map { c in
            WatchNotice.buttons(c).map { b in
                UNNotificationAction(identifier: b.id, title: b.title,
                                     options: b.destructive ? [.foreground, .destructive] : [.foreground])
            }
        } ?? notificationActions
    }
}

/// What the notification shows, filled in by didReceive after the body is first asked for.
final class NoticeShown: ObservableObject {
    @Published var card: WatchCard?
    @Published var title = ""
    @Published var text = ""
}

struct NoticeBody: View {
    @ObservedObject var shown: NoticeShown

    var body: some View {
        NoticeView(card: shown.card, title: shown.title, text: shown.text, now: WatchStore.shared.pcNow)
    }
}

/// The notification's body: the card's top and its answers, as the app draws them (not buttons: the system's are
/// under it).
struct NoticeView: View {
    let card: WatchCard?
    var title = ""
    var text = ""
    let now: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let card {
                SourceLine(card: card, now: now)
                ThreadLine(card: card).padding(.top, 2)
                if card.kind == .permission, let cmd = card.command {
                    Text(cmd)
                        .font(.system(size: 14, weight: .medium, design: .monospaced))
                        .foregroundStyle(Look.command)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 10).fill(Look.commandBG))
                        .padding(.top, 6)
                } else {
                    Text(card.question)
                        .font(.system(size: 16, weight: .semibold))
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 4)
                }
                if !card.summary.isEmpty {
                    Text(card.summary)
                        .font(.system(size: 14))
                        .foregroundStyle(Look.summary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 4)
                }
                if card.kind == .ask {
                    VStack(spacing: 5) {
                        ForEach(card.answers, id: \.option) { a in AnswerRow(answer: a, doubleTap: card.doubleTap) }
                    }
                    .padding(.top, 7)
                }
            } else {
                // an older PC sends no card: the notification's own words
                Text(title).font(.system(size: 16, weight: .semibold))
                Text(text).font(.system(size: 14)).foregroundStyle(Look.summary).padding(.top, 4)
            }
        }
        .accessibilityIdentifier("watchNotice")
    }
}
