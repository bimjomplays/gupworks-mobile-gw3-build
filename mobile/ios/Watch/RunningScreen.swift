import SwiftUI

/// What's running (a235, docs/watch-mockups/round1 shared-5-running-extra): each project's threads at a glance (a dot,
/// the name, "2 working" / "1 checking" / "idle") and a mic to tell its main chat something. The mic is the same check
/// as an answer's: what was heard comes back to read ("Not sent yet"), Send, then the green Sent with Undo for 5 s
/// before anything leaves the watch. Nothing else: no chats to read, no projects to open, no settings.
struct RunningScreen: View {
    @Environment(WatchStore.self) private var store

    var body: some View {
        @Bindable var store = store
        let glance = store.glance
        ScrollView {
            VStack(spacing: 6) {
                if let s = store.outbox.holding, s.what == .say {
                    SentBanner(send: s)
                } else if let failed = store.sayFailed, let text = store.problem {
                    Button {
                        store.problem = nil
                        store.sayFailed = nil
                        store.say = failed
                    } label: {
                        HStack(alignment: .top, spacing: 7) {
                            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Look.red)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Not sent: \(text)").foregroundStyle(Look.memoryInk)
                                Text("Tap to try again").foregroundStyle(Look.light)
                            }
                            .font(.system(size: 14))
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(9)
                        .background(RoundedRectangle(cornerRadius: 14).fill(Look.memoryBG))
                    }
                    .buttonStyle(.plain)
                }
                if glance.isEmpty {
                    Text(store.list == nil ? "Open GupWorks on your iPhone" : "No projects yet")
                        .font(.system(size: 14))
                        .foregroundStyle(Look.summary)
                        .multilineTextAlignment(.center)
                        .padding(.top, 20)
                }
                ForEach(glance.rows) { row in
                    RunningRow(row: row)
                }
            }
            .padding(.horizontal, 2)
        }
        .navigationTitle("Running")
        .sheet(item: $store.say) { draft in NavigationStack { VoiceCheck(draft: draft) } }
    }
}

/// One project: its state dot, name and words, and the mic when it has a main chat.
struct RunningRow: View {
    @Environment(WatchStore.self) private var store
    let row: WatchGlance.Row

    var body: some View {
        HStack(spacing: 8) {
            Circle().fill(dot).frame(width: 11, height: 11)
            VStack(alignment: .leading, spacing: 0) {
                Text(row.project.name)
                    .font(.system(size: 16, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(row.text)
                    .font(.system(size: 15))
                    .foregroundStyle(Look.source)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            Spacer(minLength: 0)
            if row.project.main {
                TextFieldLink(prompt: Text("Your words")) {
                    Image(systemName: "mic")
                        .font(.system(size: 20, weight: .regular))
                        .foregroundStyle(Look.light)
                        .frame(width: 34, height: 44)
                        .contentShape(Rectangle())
                } onSubmit: { words in
                    store.say = VoiceDraft(key: "say:\(row.project.id)", words: words, projectId: row.project.id)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Tell \(row.project.name)'s main chat")
                .accessibilityIdentifier("watchRunningMic")
            }
        }
        .padding(.leading, 12)
        .padding(.trailing, 6)
        .frame(minHeight: 56)
        .background(RoundedRectangle(cornerRadius: 20).fill(Look.row))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("watchRunningRow")
    }

    /// green working, blue being checked, grey idle (as drawn)
    private var dot: Color {
        switch row.state {
        case .working: return Color(hex: 0x7FD17F)
        case .checking: return Color(hex: 0x6EA8FF)
        case .idle: return Color(hex: 0x5A5A5E)
        }
    }
}

/// "Running" as a row at the foot of the waiting list, and on the empty screen: the way into the one extra screen.
struct RunningLink: View {
    var body: some View {
        NavigationLink {
            RunningScreen()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "bolt.horizontal.circle").font(.system(size: 16))
                    .foregroundStyle(Look.light)
                Text("Running").font(.system(size: 16, weight: .medium))
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.system(size: 12)).foregroundStyle(Look.dim)
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 44)
            .background(Capsule().fill(Look.row))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("watchRunningLink")
    }
}
