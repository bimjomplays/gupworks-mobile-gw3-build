import SwiftUI

/// The app: one card per screen (swipe for the next, the crown scrolls the card), "1 of 5" at the top opens the
/// waiting list, the bar fixed at the bottom of every card with answers (mic left, the recommended answer right, a
/// double tap sends it), and after a send the green Sent with its 5 s Undo above the next card (round 2 screens 2-9).
struct DeckScreen: View {
    @Environment(WatchStore.self) private var store

    var body: some View {
        @Bindable var store = store
        NavigationStack {
            Group {
                let deck = store.deck
                if deck.cards.isEmpty {
                    EmptyDeck(paired: store.list != nil || store.demo)
                } else {
                    cards(deck)
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        store.showList = true
                    } label: {
                        Text(title).font(.system(size: 15, weight: .semibold)).foregroundStyle(Look.light)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("watchPosition")
                }
            }
            .sheet(isPresented: $store.showList) { NavigationStack { WaitingList() } }
            .sheet(item: $store.voice) { draft in NavigationStack { VoiceCheck(draft: draft) } }
            .fullScreenCover(item: $store.picture) { open in PictureViewer(open: open) }
        }
    }

    private var title: String {
        let deck = store.deck
        guard let c = store.current, let i = deck.index(of: c.key) else { return "Needs you" }
        return deck.title(i)
    }

    private func cards(_ deck: WatchDeck) -> some View {
        let current = store.current
        return VStack(spacing: 0) {
            if let s = store.outbox.holding {
                SentBanner(send: s)
                    .padding(.horizontal, 2)
                    .padding(.bottom, 6)
            } else if let p = store.problem {
                ProblemBanner(text: p)
                    .padding(.horizontal, 2)
                    .padding(.bottom, 6)
            } else if let n = store.notice {
                SentBanner(send: n, undo: false)
                    .padding(.horizontal, 2)
                    .padding(.bottom, 6)
            }
            TabView(selection: Binding(get: { current?.key ?? "" }, set: { store.select($0) })) {
                ForEach(deck.cards) { c in
                    CardView(card: c, scroll: c.key == current?.key ? store.screen : "")
                        .tag(c.key)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
        }
        .overlay(alignment: .bottom) {
            if let c = current, c.bar {
                AnswerBar(card: c)
            }
        }
        .ignoresSafeArea(edges: .bottom)
    }
}

/// The bar fixed at the bottom of a card: the mic (his own words, read back before Send) and the recommended answer
/// (double tap; a permission's Allow once is tap only).
struct AnswerBar: View {
    @Environment(WatchStore.self) private var store
    let card: WatchCard

    var body: some View {
        HStack(spacing: 6) {
            if card.voice {
                MicButton(card: card)
            }
            if let a = card.primary {
                Button {
                    store.answer(a, on: card)
                } label: {
                    HStack(spacing: 5) {
                        if card.doubleTap {
                            Image(systemName: Look.hand).font(.system(size: 14))
                        }
                        Text(a.label).lineLimit(1).minimumScaleFactor(0.75)
                    }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(Capsule().fill(card.kind == .permission ? Look.allowBG : Look.blue))
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                // a double tap waits until the Undo is gone, and never allows a command
                .doubleTap(card.doubleTap && store.outbox.holding == nil && store.voice == nil && !store.showList)
                .accessibilityIdentifier(card.kind == .permission ? "watchAllow" : "watchRecommended")
            }
        }
        .padding(.horizontal, 10)
        .padding(.top, 6)
        .padding(.bottom, 10)
        .background(alignment: .top) {
            LinearGradient(colors: [.black.opacity(0), .black], startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.25))
                .padding(.top, -14)
        }
    }
}

/// The mic: the watch's own input (dictation, Scribble, keyboard), then the check screen; nothing goes before Send.
struct MicButton: View {
    @Environment(WatchStore.self) private var store
    let card: WatchCard
    var icon = "mic.fill"

    var body: some View {
        TextFieldLink(prompt: Text(card.kind == .permission ? "What to do instead" : "Your answer")) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(Circle().fill(Look.mic))
                .contentShape(Circle())
        } onSubmit: { words in
            store.voice = VoiceDraft(key: card.key, words: words)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(card.kind == .permission ? "Say what to do instead" : "Say it")
        .accessibilityIdentifier("watchMic")
    }
}

/// "✓ Sent to Home server / Add disk swap / ↶ Undo · 5 s" (round 2 screen 9)
struct SentBanner: View {
    @Environment(WatchStore.self) private var store
    let send: WatchSend
    var undo = true

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 7) {
                Image(systemName: "checkmark").font(.system(size: 15, weight: .bold))
                VStack(alignment: .leading, spacing: 0) {
                    Text(send.headline).foregroundStyle(Look.sentInk)
                    Text(send.detail).foregroundStyle(Look.sentDetail).fontWeight(.regular).lineLimit(2)
                }
                .font(.system(size: 14, weight: .medium))
            }
            .foregroundStyle(Look.sentInk)
            if undo {
                Button {
                    store.undo()
                } label: {
                    TimelineView(.periodic(from: .now, by: 0.25)) { ctx in
                        PillLabel(title: "Undo · \(store.undoLeft(at: ctx.date)) s", icon: "arrow.uturn.backward",
                                  fill: Look.undoBG, ink: Look.undoInk)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("watchUndo")
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 14).fill(Look.sentBG))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Look.sentEdge, lineWidth: 1))
        .accessibilityIdentifier("watchSent")
    }
}

/// The iPhone said the answer didn't reach the PC: the card is back, this says why.
struct ProblemBanner: View {
    @Environment(WatchStore.self) private var store
    let text: String

    var body: some View {
        Button {
            store.problem = nil
        } label: {
            HStack(alignment: .top, spacing: 7) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Look.red)
                Text("Not sent: \(text)").font(.system(size: 14)).foregroundStyle(Look.memoryInk)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(9)
            .background(RoundedRectangle(cornerRadius: 14).fill(Look.memoryBG))
        }
        .buttonStyle(.plain)
    }
}

/// Nothing waits (or the iPhone hasn't sent a list yet).
struct EmptyDeck: View {
    let paired: Bool

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: paired ? "checkmark.circle" : "iphone")
                .font(.system(size: 30))
                .foregroundStyle(Look.light)
            Text(paired ? "Nothing needs you" : "Open GupWorks on your iPhone")
                .font(.system(size: 16, weight: .semibold))
                .multilineTextAlignment(.center)
            Text(paired ? "Questions from your PC show up here." : "Your iPhone brings the cards to this watch.")
                .font(.system(size: 13))
                .foregroundStyle(Look.summary)
                .multilineTextAlignment(.center)
            if paired { RunningLink().padding(.top, 6) }
        }
        .padding(.horizontal, 8)
    }
}
