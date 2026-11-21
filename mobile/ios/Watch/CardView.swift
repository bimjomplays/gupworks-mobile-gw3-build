import SwiftUI

/// One needs-you card, everything to decide on the wrist (round 2's order): where it's from and how long it waited,
/// the thread, the whole question, pictures under it, the whole summary, the recommended answer first with its detail,
/// the other answers, then Snooze · Dismiss. The crown scrolls; the bar stays at the bottom (DeckScreen).
struct CardView: View {
    @Environment(WatchStore.self) private var store
    let card: WatchCard
    /// the demo's screenshots: "card-answers" scrolls to the recommended answer, "card-end" to the end
    var scroll = ""

    var body: some View {
        ScrollViewReader { reader in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    switch card.kind {
                    case .ask: ask
                    case .permission: permission
                    case .memory: memory
                    case .phone: phone
                    }
                    Color.clear.frame(height: card.bar ? 62 : 8).id("end")
                }
                .padding(.horizontal, 2)
            }
            .task(id: scroll) {
                guard scroll == "card-answers" || scroll == "card-end" else { return }
                try? await Task.sleep(for: .milliseconds(600))
                if scroll == "card-answers" {
                    reader.scrollTo("answers", anchor: UnitPoint(x: 0.5, y: 0.22))
                } else {
                    reader.scrollTo("end", anchor: .bottom)
                }
            }
        }
        .accessibilityIdentifier("watchCard")
    }

    private var now: Double { store.pcNow }

    // MARK: a question

    private var ask: some View {
        VStack(alignment: .leading, spacing: 0) {
            SourceLine(card: card, now: now)
            ThreadLine(card: card).padding(.top, 2)
            Text(card.question)
                .font(.system(size: 16, weight: .semibold))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 4)
                .accessibilityIdentifier("watchQuestion")
            if !card.pictures.isEmpty {
                Thumbnails(card: card).padding(.top, 6)
            }
            if !card.summary.isEmpty {
                Text(card.summary)
                    .font(.system(size: 14))
                    .foregroundStyle(Look.summary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 4)
                    .accessibilityIdentifier("watchSummary")
            }
            VStack(spacing: 5) {
                ForEach(card.answers, id: \.option) { a in
                    AnswerRow(answer: a, doubleTap: card.doubleTap) { store.answer(a, on: card) }
                }
            }
            .padding(.top, 7)
            .id("answers")
            snoozeDismiss
        }
    }

    private var snoozeDismiss: some View {
        HStack(spacing: 6) {
            Button { store.snooze(card) } label: { PillLabel(title: "Snooze", icon: "moon.zzz") }
                .buttonStyle(.plain)
                .accessibilityIdentifier("watchSnooze")
            Button { store.dismiss(card) } label: { PillLabel(title: "Dismiss") }
                .buttonStyle(.plain)
                .accessibilityIdentifier("watchDismiss")
        }
        .padding(.top, 8)
    }

    // MARK: a permission (round 2 screen 8): tap only

    private var permission: some View {
        VStack(alignment: .leading, spacing: 0) {
            SourceLine(card: card, now: now)
            Text(card.command ?? card.question)
                .font(.system(size: 14, weight: .medium, design: .monospaced))
                .foregroundStyle(Look.command)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 10).fill(Look.commandBG))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Look.commandEdge, lineWidth: 1))
                .padding(.top, 6)
                .accessibilityIdentifier("watchCommand")
            if !card.summary.isEmpty {
                Text(card.summary)
                    .font(.system(size: 13))
                    .foregroundStyle(Look.summary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 5)
            }
            if let d = card.deny {
                Button { store.answer(d, on: card) } label: { PillLabel(title: d.label) }
                    .buttonStyle(.plain)
                    .padding(.top, 8)
                    .accessibilityIdentifier("watchDeny")
            }
        }
    }

    // MARK: the memory warning (round 1 shared screen 3)

    private var memory: some View {
        VStack(alignment: .leading, spacing: 0) {
            SourceLine(card: card, now: now)
            Text(card.question)
                .font(.system(size: 18, weight: .semibold))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 4)
            if !card.summary.isEmpty {
                Text(card.summary)
                    .font(.system(size: 14))
                    .foregroundStyle(Look.summary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 4)
            }
            if let s = card.sleep {
                Button { store.answer(s, on: card) } label: {
                    PillLabel(title: s.label, fill: Look.memoryBG, ink: Look.memoryInk)
                }
                .buttonStyle(.plain)
                .padding(.top, 8)
                .accessibilityIdentifier("watchSleep")
            }
            Button { store.dismiss(card) } label: { PillLabel(title: "Dismiss") }
                .buttonStyle(.plain)
                .padding(.top, 5)
                .accessibilityIdentifier("watchDismiss")
        }
    }

    // MARK: several questions at once: answered on the iPhone

    private var phone: some View {
        VStack(alignment: .leading, spacing: 0) {
            SourceLine(card: card, now: now)
            ThreadLine(card: card).padding(.top, 2)
            Text(card.question)
                .font(.system(size: 16, weight: .semibold))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 4)
            Text(card.summary)
                .font(.system(size: 14))
                .foregroundStyle(Look.summary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 4)
            Button { store.openOnPhone(card) } label: {
                PillLabel(title: "Open on iPhone", icon: "iphone", fill: Look.blue)
            }
            .buttonStyle(.plain)
            .padding(.top, 8)
            .accessibilityIdentifier("watchOpenOnPhone")
            snoozeDismiss
        }
    }
}

/// An answer row: its label and what picking it does; the recommended one blue, with the double tap mark. A tap sends
/// it (with the 5 s Undo).
struct AnswerRow: View {
    let answer: WatchCard.Answer
    var doubleTap = true
    var action: (() -> Void)?

    var body: some View {
        if let action {
            Button(action: action) { content }
                .buttonStyle(.plain)
                .accessibilityIdentifier(answer.recommended ? "watchAnswerRecommended" : "watchAnswer")
        } else {
            content
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 2) {
            if answer.recommended {
                HStack(spacing: 4) {
                    Text("Recommended").layoutPriority(1)
                    if doubleTap {
                        Spacer(minLength: 4)
                        Image(systemName: Look.hand)
                        Text("double tap")
                    }
                }
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Look.recTag)
            }
            Text(answer.label)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
            if !answer.detail.isEmpty {
                Text(answer.detail)
                    .font(.system(size: 13))
                    .foregroundStyle(Look.detail)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 11)
        .padding(.top, 7)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14).fill(answer.recommended ? Look.recBG : Look.row))
        .overlay {
            if answer.recommended { RoundedRectangle(cornerRadius: 14).stroke(Look.blue, lineWidth: 1) }
        }
        .contentShape(RoundedRectangle(cornerRadius: 14))
    }
}

/// Before and After right under the question: a tap opens the picture on the whole screen.
struct Thumbnails: View {
    @Environment(WatchStore.self) private var store
    let card: WatchCard

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Array(card.pictures.enumerated()), id: \.offset) { i, pic in
                Button {
                    store.picture = PictureOpen(key: card.key, index: i)
                } label: {
                    thumb(pic, expand: i == card.pictures.count - 1)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(pic.caption ?? "Picture")
                .accessibilityIdentifier("watchPicture")
            }
        }
    }

    private func thumb(_ pic: NeedItem.Picture, expand: Bool) -> some View {
        let _ = store.picturesChanged
        return ZStack(alignment: .topTrailing) {
            // a filled picture reports its own width; laid over a clear box it can't widen the card (CI run 44866334361)
            Color.clear
                .frame(maxWidth: .infinity)
                .frame(height: 68)
                .overlay {
                    if let img = store.image(pic.url) {
                        Image(uiImage: img).resizable().scaledToFill()
                    } else {
                        Rectangle().fill(Look.row).overlay(ProgressView())
                    }
                }
                .clipped()
            if expand {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(.black.opacity(0.7)))
                    .padding(5)
            }
        }
        .overlay(alignment: .bottom) {
            Text(PictureViewer.short(pic.caption))
                .font(.system(size: 13, weight: .semibold))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color(hex: 0x0A0A0C).opacity(0.9))
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
