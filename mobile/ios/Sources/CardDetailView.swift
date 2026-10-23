import SwiftUI

/// A step card full screen: every call in it with what it did and what it left (command, output, diff, plan).
/// While the card runs it reads the card again every second and a half.
struct CardDetailView: View {
    let store: ChatStore
    let cardId: String
    @State private var card: CardDetail?
    @State private var error: String?

    init(store: ChatStore, cardId: String) {
        self.store = store
        self.cardId = cardId
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let c = card {
                    summary(c)
                    ForEach(c.rows) { CallRowView(row: $0) }
                } else if let error {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(.subheadline)
                        .foregroundStyle(ChatStyle.dim)
                } else {
                    ProgressView().frame(maxWidth: .infinity).padding(.vertical, 40)
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
        }
        .background(Theme.background)
        .navigationTitle(card?.title ?? "Steps")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: store.rev(ofCard: cardId)) { await load() }
    }

    private func load() async {
        while !Task.isCancelled {
            do {
                card = try await store.card(cardId)
                error = nil
            } catch let e as APIError {
                if card == nil { error = e.message }
            } catch {
                return
            }
            guard card?.state == "running" else { return }
            try? await Task.sleep(nanoseconds: 1_500_000_000)
        }
    }

    private func summary(_ c: CardDetail) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(c.title)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Theme.title)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 6) {
                stateWord(c.state)
                if !c.stats.isEmpty { Text("· \(c.stats)").foregroundStyle(ChatStyle.dim) }
                if let a = c.add, a > 0 { Text("+\(a)").foregroundStyle(ChatStyle.add) }
                if let d = c.del, d > 0 { Text("\u{2212}\(d)").foregroundStyle(ChatStyle.del) }
            }
            .font(.system(size: 15))
            if let intent = c.intent, !intent.isEmpty {
                Text(intent)
                    .font(.system(size: 15))
                    .foregroundStyle(ChatStyle.dim)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.bottom, 4)
    }

    @ViewBuilder
    private func stateWord(_ state: String) -> some View {
        switch state {
        case "running": Text("Running").foregroundStyle(Theme.blue)
        case "failed": Text("Failed").foregroundStyle(ChatStyle.failed)
        case "stopped": Text("Stopped").foregroundStyle(ChatStyle.dim)
        default: Text("Done").foregroundStyle(ChatStyle.done)
        }
    }
}

/// One call: "Bash  npm test   1.2s", then its command, output, diff or plan.
struct CallRowView: View {
    let row: CallRow

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                icon
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(row.label).font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.rowTitle)
                        if !row.chip.isEmpty {
                            Text(row.chip)
                                .font(.system(size: 11))
                                .foregroundStyle(ChatStyle.dim)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(ChatStyle.chevronBG, in: Capsule())
                        }
                    }
                    if !row.detail.isEmpty {
                        Text(row.detail)
                            .font(.system(size: 14, design: row.tool == "Bash" ? .monospaced : .default))
                            .foregroundStyle(ChatStyle.dim)
                            .lineLimit(4)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 6)
                time
                    .font(.system(size: 13))
                    .monospacedDigit()
            }
            .padding(12)
            if let cmd = row.command {
                mono([cmd], color: Color(hex: 0xD8D8E0))
            }
            if let out = row.out {
                output(out)
            }
            if let diff = row.diff {
                DiffView(diff: diff)
            }
            if let plan = row.plan, !plan.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(plan.enumerated()), id: \.offset) { _, p in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Image(systemName: p.state == "done" ? "checkmark.circle.fill" : p.state == "doing" ? "circle.dotted" : "circle")
                                .foregroundStyle(p.state == "done" ? ChatStyle.done : p.state == "doing" ? Theme.blue : ChatStyle.dim)
                            Text(p.content)
                                .foregroundStyle(p.state == "done" ? ChatStyle.dim : ChatStyle.body)
                                .strikethrough(p.state == "done", color: ChatStyle.dim)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .font(.system(size: 15))
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ChatStyle.cardBG, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(ChatStyle.cardBorder, lineWidth: 1))
    }

    @ViewBuilder
    private var icon: some View {
        switch row.state {
        case "running": Spinner().scaleEffect(0.8)
        case "error": Image(systemName: "xmark.circle.fill").foregroundStyle(ChatStyle.failed)
        case "stopped": Image(systemName: "stop.circle").foregroundStyle(ChatStyle.dim)
        default: Image(systemName: "checkmark.circle.fill").foregroundStyle(ChatStyle.done)
        }
    }

    @ViewBuilder
    private var time: some View {
        if let since = row.since {
            TimelineView(.periodic(from: .now, by: 1)) { ctx in
                Text(Format.duration(ctx.date.timeIntervalSince1970 * 1000 - since) + "\u{2026}").foregroundStyle(ChatStyle.dim)
            }
        } else if let ms = row.ms {
            Text(Format.duration(ms)).foregroundStyle(ChatStyle.dim)
        }
    }

    private func output(_ out: CallRow.Output) -> some View {
        let more = out.total - out.head.count - out.tail.count
        return VStack(alignment: .leading, spacing: 0) {
            mono(out.head, color: out.failed ? ChatStyle.failed : ChatStyle.body)
            if more > 0 {
                Text("\u{2026} \(Format.plural(more, "more line"))")
                    .font(.system(size: 12))
                    .foregroundStyle(ChatStyle.faint)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
            }
            if !out.tail.isEmpty {
                mono(out.tail, color: out.failed ? ChatStyle.failed : ChatStyle.body)
            }
        }
    }

    private func mono(_ lines: [String], color: Color) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            Text(lines.joined(separator: "\n"))
                .font(.system(size: 13, design: .monospaced))
                .foregroundStyle(color)
                .textSelection(.enabled)
                .fixedSize(horizontal: true, vertical: true)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
        }
        .background(Color(hex: 0x141416))
    }
}

/// A file's change: removed lines red, added green, with line numbers; gaps and "N more lines" between.
private struct DiffView: View {
    let diff: CallRow.Diff

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(diff.path)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(ChatStyle.dim)
                .lineLimit(1)
                .truncationMode(.head)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
            ScrollView(.horizontal, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(diff.lines.enumerated()), id: \.offset) { _, l in
                        line(l)
                    }
                }
                .padding(.bottom, 8)
            }
        }
        .background(Color(hex: 0x141416))
    }

    @ViewBuilder
    private func line(_ l: CallRow.DiffLine) -> some View {
        switch l.k {
        case "gap":
            Text("\u{22EF}").font(.system(size: 12)).foregroundStyle(ChatStyle.faint).padding(.horizontal, 12)
        case "more":
            Text("\u{2026} \(Format.plural(l.n, "more line"))")
                .font(.system(size: 12))
                .foregroundStyle(ChatStyle.faint)
                .padding(.horizontal, 12)
                .padding(.vertical, 2)
        default:
            HStack(spacing: 8) {
                Text(l.n > 0 ? "\(l.n)" : "")
                    .frame(width: 30, alignment: .trailing)
                    .foregroundStyle(ChatStyle.faint)
                Text(l.k == " " ? " " : l.k == "-" ? "\u{2212}" : "+")
                    .foregroundStyle(l.k == "+" ? ChatStyle.add : l.k == "-" ? ChatStyle.del : ChatStyle.faint)
                Text(l.text.isEmpty ? " " : l.text)
                    .foregroundStyle(l.k == "+" ? Color(hex: 0xBFE3BF) : l.k == "-" ? Color(hex: 0xF0B8B4) : ChatStyle.body)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .font(.system(size: 12, design: .monospaced))
            .padding(.horizontal, 12)
            .padding(.vertical, 1)
            .background(l.k == "+" ? Color(hex: 0x1C2A1E) : l.k == "-" ? Color(hex: 0x2E1C1C) : .clear)
        }
    }
}
