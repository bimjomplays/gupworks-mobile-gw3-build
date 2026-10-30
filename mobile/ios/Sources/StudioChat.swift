import SwiftUI

// A Studio video chat on the phone (a180, mockup 14): the script's waiting rewrites as cards (Accept, Undo, Open in
// Script), the video's long jobs, and the selection the next message carries, above the composer.

/// The video's waiting script changes and running jobs, under the chat's turns.
struct StudioChatExtras: View {
    let video: ChatHeader.VideoInfo
    let store: StudioVideoStore
    @Environment(\.openStudio) private var openStudio

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(store.script?.pending.filter { $0.status == "pending" } ?? []) { c in change(c) }
            ForEach(store.overview?.jobs ?? []) { j in
                HStack(spacing: 10) {
                    Spinner()
                    VStack(alignment: .leading, spacing: 1) {
                        Text(j.title).font(.system(size: 15, weight: .medium)).foregroundStyle(Theme.title)
                        Text("\(j.id) \u{00B7} \(j.status == "running" ? "working" : j.status)")
                            .font(.system(size: 13)).foregroundStyle(StudioLook.label)
                    }
                    Spacer()
                }
                .padding(12)
                .studioCard(radius: 14)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("job-\(j.id)")
            }
        }
    }

    private func change(_ c: StudioScript.Change) -> some View {
        let ids = c.lines.map(\.id)
        return VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text("Line\(ids.count > 1 ? "s" : "") \(ids.joined(separator: ", ")) \u{00B7} proposed")
                    .font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.title)
                Spacer()
                Text("Script").font(.system(size: 13)).foregroundStyle(StudioLook.label)
            }
            ForEach(c.lines, id: \.id) { e in
                Text(e.new).font(.system(size: 17, design: .serif)).foregroundStyle(Theme.title)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let n = c.note, !n.isEmpty {
                Text(n).font(.system(size: 14)).foregroundStyle(StudioLook.label).fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 8) {
                StudioButton(title: "Accept", icon: "check", primary: true, busy: store.busy.contains("change-\(c.id)"),
                             id: "chatAccept-\(c.id)", height: 34) {
                    Task { await store.resolve(change: c.id, accept: true) }
                }
                StudioButton(title: "Undo", icon: "undo-2", id: "chatUndo-\(c.id)", height: 34) {
                    Task { await store.resolve(change: c.id, accept: false) }
                }
                StudioButton(title: "Open in Script", id: "openScript-\(c.id)", height: 34) {
                    openStudio?(.video(video.projectId, video.videoId, stage: "script"))
                }
            }
            .disabled(store.readonly)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .studioCard(radius: 16)
        .accessibilityIdentifier("chatChange-\(c.id)")
    }
}

/// "Script · line c6 selected": what the video page has selected, which the next message carries.
struct StudioSelectionChip: View {
    let text: String

    private var shown: String {
        let head = text.split(separator: ":", maxSplits: 1).first.map(String.init) ?? text
        let words = head.split(separator: " ", maxSplits: 1).map(String.init)
        guard words.count == 2 else { return head }
        return "\(StudioLook.stageName(words[0])) \u{00B7} \(words[1]) selected"
    }

    var body: some View {
        HStack(spacing: 7) {
            LucideIcon(name: "text-select", size: 15)
            Text(shown).font(.system(size: 14)).lineLimit(1)
        }
        .foregroundStyle(Theme.blue)
        .padding(.horizontal, 12)
        .frame(height: 30)
        .background(Theme.blue.opacity(0.14), in: Capsule())
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.bottom, 6)
        .accessibilityIdentifier("selectionChip")
    }
}
