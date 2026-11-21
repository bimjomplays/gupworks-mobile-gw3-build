import SwiftUI

/// Answering by voice (round 2 screen 5): after the watch's own input (dictation, Scribble or the keyboard), who gets
/// it, the words as heard (tap to fix them), "Not sent yet", Say again, Send. Nothing goes before Send, and then it
/// still waits out the 5 s Undo.
struct VoiceCheck: View {
    @Environment(WatchStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let draft: VoiceDraft
    @State private var words = ""

    var body: some View {
        let card = store.card(draft.key) ?? store.item(draft.key).map(WatchCard.init)
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                if let card {
                    HStack(spacing: 5) {
                        Image(systemName: "mic").font(.system(size: 12))
                        (Text("To ") + Text(card.source).fontWeight(.semibold).foregroundColor(Look.threadID)
                            + Text(card.threadId.map { " · \($0)" } ?? ""))
                            .lineLimit(1)
                    }
                    .font(.system(size: 13))
                    .foregroundStyle(Look.source)
                    .accessibilityIdentifier("watchVoiceTo")
                }
                if words.isEmpty {
                    TextFieldLink(prompt: Text("Your answer")) {
                        PillLabel(title: "Say it", icon: "mic.fill", fill: Look.blue)
                    } onSubmit: { words = $0 }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("watchVoiceSay")
                } else {
                    TextField("Your answer", text: $words, axis: .vertical)
                        .textFieldStyle(.plain)
                        .font(.system(size: 16, weight: .medium))
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
        .navigationTitle("Your answer")
        .overlay(alignment: .bottom) {
            if let card, !words.isEmpty {
                HStack(spacing: 6) {
                    TextFieldLink(prompt: Text("Your answer")) {
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
                        if let s = WatchSend.words(words, on: card, at: store.now) {
                            store.voice = nil
                            store.send(s)
                            dismiss()
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
