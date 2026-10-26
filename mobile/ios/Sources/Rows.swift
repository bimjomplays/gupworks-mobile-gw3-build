import SwiftUI

/// A chat pushed on the chat's stack (a project's thread).
struct ChatRoute: Hashable {
    let id: String
    /// a project's main chat with its Overview up at once (06)
    var sheet = false
}

/// A project folder from the desktop sidebar: tap to open or close it.
struct FolderRowView: View {
    let folder: LayoutEntry.Folder
    let count: Int
    let open: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.secondary)
                .rotationEffect(.degrees(open ? 90 : 0))
                .frame(width: 28)
            Text(folder.name)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.section)
                .lineLimit(1)
            Spacer(minLength: 8)
            Text("\(count)").font(.subheadline).foregroundStyle(Theme.secondary).monospacedDigit()
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .accessibilityElement(children: .combine)
        .accessibilityValue(open ? "open" : "closed")
    }
}

/// What the list's swipes and long-press and a chat's ⋯ menu share.
enum ChatActions {
    static let pinTint = Color(hex: 0x2F5FB3)      // the D1 swipe's blue
    static let archiveTint = Color(hex: 0x5A5A63)
    static let deleteTint = Color(hex: 0xD9534F)
    static let deleteNote = "It leaves your chats on the PC too and its Claude stops. The PC keeps the transcript, "
        + "so the chat can be brought back there."
}

struct ProjectRowView: View {
    let project: ProjectRow

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: "folder")
                .font(.title3)
                .foregroundStyle(Theme.icon)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text(project.name)
                    .font(.body)
                    .foregroundStyle(Theme.rowTitle)
                    .lineLimit(1)
                StateLine(word: stateWord, color: stateColor, rest: project.detail)
            }
            Spacer(minLength: 8)
            badge
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .accessibilityElement(children: .combine)
    }

    private var stateWord: String? {
        switch project.state {
        case "needs": return "Needs you"
        case "permission": return "Waiting for permission"
        case "working": return "Working"
        case "paused": return "Paused"
        default: return nil
        }
    }

    private var stateColor: Color {
        switch project.state {
        case "needs": return Theme.violetText
        case "permission": return Theme.amber
        default: return Theme.secondary
        }
    }

    @ViewBuilder
    private var badge: some View {
        if project.state == "permission" {
            CountBadge(count: max(project.permission, 1)) { Dot(color: Theme.amber) }
        } else if project.working > 0 {
            CountBadge(count: project.working) { Spinner() }
        } else if project.needs > 0 {
            CountBadge(count: project.needs) { Dot(color: Theme.violet) }
        } else if project.paused {
            Image(systemName: "pause.circle").foregroundStyle(Theme.secondary)
        }
    }
}

struct ChatRowView: View {
    let chat: ChatRow
    let now: Date

    var body: some View {
        HStack(spacing: 16) {
            indicator.frame(width: 28)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(chat.title)
                        .font(.body)
                        .foregroundStyle(Theme.rowTitle)
                        .lineLimit(1)
                    if chat.pinned {
                        Image(systemName: "pin.fill").font(.caption2).foregroundStyle(Theme.secondary)
                    }
                }
                StateLine(word: stateWord, color: stateColor, rest: subtitle)
            }
            Spacer(minLength: 8)
            Text(chat.state == "working" ? "now" : Format.time(chat.lastActive, now: now))
                .font(.subheadline)
                .foregroundStyle(Theme.time)
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .accessibilityElement(children: .combine)
    }

    private var stateWord: String? {
        switch chat.state {
        case "working": return "Working"
        case "needs": return "Needs you"
        case "permission": return "Waiting for permission"
        default: return nil
        }
    }

    private var stateColor: Color {
        switch chat.state {
        case "needs": return Theme.violetText
        case "permission": return Theme.amber
        default: return Theme.secondary
        }
    }

    /// "Opus 5.5 · Claude"; with a state word in front only the model, so the line stays short.
    private var subtitle: String {
        if stateWord != nil { return chat.model }
        return [chat.model, chat.provider].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    @ViewBuilder
    private var indicator: some View {
        switch chat.state {
        case "working": Spinner()
        case "needs": Dot(color: Theme.violet)
        case "permission": Dot(color: Theme.amber)
        default: Dot(color: Theme.idleDot)
        }
    }
}

/// "Needs you · Mockups: pick a look": the state word in its colour, the rest grey.
struct StateLine: View {
    let word: String?
    let color: Color
    let rest: String

    var body: some View {
        let parts: Text = {
            switch (word, rest.isEmpty) {
            case let (w?, true): return Text(w).foregroundStyle(color)
            case let (w?, false): return Text("\(Text(w).foregroundStyle(color)) · \(rest)").foregroundStyle(Theme.secondary)
            case (nil, _): return Text(rest).foregroundStyle(Theme.secondary)
            }
        }()
        parts.font(.subheadline).lineLimit(1)
    }
}

struct CountBadge<Icon: View>: View {
    let count: Int
    @ViewBuilder var icon: () -> Icon

    var body: some View {
        HStack(spacing: 8) {
            icon()
            Text("\(count)").font(.subheadline).foregroundStyle(Theme.secondary).monospacedDigit()
        }
    }
}

struct Dot: View {
    let color: Color
    var body: some View { Circle().fill(color).frame(width: 8, height: 8) }
}

/// A thin ring with a moving arc, like the desktop's working spinner.
struct Spinner: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            ZStack {
                Circle().stroke(Theme.blue.opacity(0.25), lineWidth: 2)
                Circle()
                    .trim(from: 0, to: 0.3)
                    .stroke(Theme.blue, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .rotationEffect(.degrees(t.truncatingRemainder(dividingBy: 1) * 360))
            }
            .frame(width: 16, height: 16)
        }
        .accessibilityLabel("Working")
    }
}

struct ErrorBanner: View {
    @Environment(AppModel.self) private var model
    let error: APIError

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(error.message, systemImage: "exclamationmark.triangle")
                .font(.subheadline)
                .foregroundStyle(Theme.red)
            if error == .notPaired {
                Button("Pair again") { model.unpair() }
                    .buttonStyle(.glass)
            }
        }
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }
}
