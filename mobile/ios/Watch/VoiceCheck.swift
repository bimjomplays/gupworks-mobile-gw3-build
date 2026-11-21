import SwiftUI

/// Answering by voice (round 2 screen 5): after the watch's own input (dictation, Scribble or the keyboard), who gets
/// it, the words as heard (tap to fix them), "Not sent yet", Say again, Send. Nothing goes before Send, and then it
/// still waits out the 5 s Undo.
struct VoiceCheck: View {
    @Environment(WatchStore.self) private var store
    let draft: VoiceDraft
    @State private var words = ""

    private var prompt: String { draft.projectId == nil ? "Your answer" : "Your words" }

    var body: some View {
        let card = store.card(draft.key) ?? store.item(draft.key).map(WatchCard.init)
        // a235: words for a project's main chat (the Running screen's mic) have no card: who gets them is the project
        let project = draft.projectId.flatMap { store.glance.project($0) }
        let ready = project != nil || card != nil
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                if ready {
                    HStack(spacing: 5) {
                        Image(systemName: "mic").font(.system(size: 12))
                        (Text("To ") + Text(project?.name ?? card?.source ?? "").fontWeight(.semibold).foregroundColor(Look.threadID)
                            + Text(project != nil ? " · main chat" : card?.threadId.map { " · \($0)" } ?? ""))
                            .lineLimit(1)
                    }
                    .font(.system(size: 13))
                    .foregroundStyle(Look.source)
                    .accessibilityIdentifier("watchVoiceTo")
                }
                if words.isEmpty {
                    TextFieldLink(prompt: Text(prompt)) {
                        PillLabel(title: "Say it", icon: "mic.fill", fill: Look.blue)
                    } onSubmit: { words = $0 }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("watchVoiceSay")
                } else {
                    // the words in full, wrapped (watchOS draws a TextField on one cut line); the field under them
                    // takes the tap and opens the system's input with the words in it to fix
                    Text("\u{201C}\(words)\u{201D}")
                        .font(.system(size: 16, weight: .medium))
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.trailing, 14)
                        .allowsHitTesting(false)
                        .background {
                            TextField(prompt, text: $words)
                                .textFieldStyle(.plain)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .opacity(0.02)  // unseen (its own grey pill showed through) but still takes the tap
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .overlay(alignment: .bottomTrailing) {
                            Image(systemName: "pencil")
                                .font(.system(size: 13))
                                .foregroundStyle(Look.light)
                                .padding(7)
                        }
                        .background(RoundedRectangle(cornerRadius: 14).fill(Look.row))
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Look.edge, lineWidth: 1))
                        .accessibilityIdentifier("watchVoiceWords")
                    (Text("Not sent yet. ").fontWeight(.semibold).foregroundColor(Look.amber)
                        + Text("Tap the words to fix them."))
                        .font(.system(size: 13))
                        .foregroundStyle(Look.summary)
                        .accessibilityIdentifier("watchNotSentYet")
                }
                Color.clear.frame(height: 56)
            }
            .padding(.horizontal, 2)
        }
        .navigationTitle(draft.projectId == nil ? "Your answer" : "Your words")
        .overlay(alignment: .bottom) {
            if ready, !words.isEmpty {
                HStack(spacing: 6) {
                    TextFieldLink(prompt: Text(prompt)) {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                            .background(Circle().fill(Look.mic))
                            .contentShape(Circle())
                    } onSubmit: { words = $0 }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Say it again")
                    .accessibilityIdentifier("watchVoiceAgain")
                    Button {
                        if let project {
                            store.say = nil  // closes this screen; the Sent banner and its Undo show on Running
                            store.sendWords(words, to: project)
                        } else if let card, let s = WatchSend.words(words, on: card, at: store.now) {
                            store.voice = nil  // closes this screen; the Sent banner and its Undo show on the deck
                            store.send(s)
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: Look.hand).font(.system(size: 14))
                            Text("Send")
                        }
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(Capsule().fill(Look.blue))
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .doubleTap(true)
                    .accessibilityIdentifier("watchVoiceSend")
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 10)
                .background(Color.black.padding(.top, -8))
            }
        }
        .ignoresSafeArea(edges: .bottom)
        .onAppear { if words.isEmpty { words = draft.words } }
    }
}
