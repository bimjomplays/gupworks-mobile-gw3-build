import SwiftUI

/// The needs-you card at the end of a chat: what Claude asks on the PC's screen, answered with 44 pt buttons that
/// do what the desktop's buttons do. A permission is amber (Allow once / Always… / Deny), Claude's question and a
/// plan are violet (its choices and Something else…; Approve / Keep planning…). A chat on an older GupWorks can't
/// take keys from the phone: then the card says *Answer this on the PC*.
struct DialogCard: View {
    let dialog: Dialog
    let busy: Bool
    let base: URL?
    let answer: (DialogAnswer) -> Void

    /// the choice being answered with words (Something else…, Keep planning…)
    @State private var typing: Int?
    @State private var words = ""
    @State private var ticks: Set<Int>
    @State private var planOpen = false
    @FocusState private var focused: Bool

    init(dialog: Dialog, busy: Bool, base: URL?, answer: @escaping (DialogAnswer) -> Void) {
        self.dialog = dialog
        self.busy = busy
        self.base = base
        self.answer = answer
        _ticks = State(initialValue: Set((dialog.choices ?? []).filter { $0.checked == true && $0.input != true }.map(\.n)))
    }

    private var amber: Bool { dialog.kind == "permission" }
    private var choices: [Dialog.Choice] { (dialog.choices ?? []).filter { $0.n != 0 } }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            heading
            if let tabs = dialog.tabs, tabs.count > 1 { tabRow(tabs).padding(.top, 10) }
            if let q = dialog.question, !q.isEmpty {
                Text(Inline.text(q, color: Color(hex: 0xE2E2E2)))
                    .font(.system(size: 17))
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 10)
            }
            content
            if let notes = dialog.notes, !notes.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(notes.enumerated()), id: \.offset) { _, n in
                        Text(n).font(.system(size: 14)).foregroundStyle(ChatStyle.dim)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.top, 8)
            }
            if dialog.canAnswer {
                answers.padding(.top, 14)
            } else {
                onThePC.padding(.top, 14)
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(amber ? Color(hex: 0x1E1A12) : Color(hex: 0x17151D), in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(amber ? Color(hex: 0x6B5524) : Theme.blue.opacity(0.75), lineWidth: amber ? 1 : 2)
        )
        .shadow(color: amber ? .clear : Theme.blue.opacity(0.25), radius: 12)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("dialog-\(dialog.kind)")
    }

    // MARK: parts

    private var kindWord: String {
        switch dialog.kind {
        case "permission": return "WAITING FOR PERMISSION"
        case "plan": return "PLAN READY"
        case "review": return "CHECK YOUR ANSWERS"
        default: return "CLAUDE ASKS"
        }
    }

    private var heading: some View {
        HStack(spacing: 7) {
            if amber {
                Circle().fill(Theme.amber).frame(width: 7, height: 7)
            }
            Text(kindWord)
                .font(.system(size: 12, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(amber ? Theme.amber : Theme.violetText)
            Spacer(minLength: 8)
            if busy {
                ProgressView().controlSize(.small)
            } else if let t = dialog.title, !t.isEmpty, dialog.kind != "plan" || t != "Ready to code?" {
                Text(t).font(.system(size: 13)).foregroundStyle(ChatStyle.dim).lineLimit(1)
            }
        }
    }

    private func tabRow(_ tabs: [Dialog.Tab]) -> some View {
        FlowLayout(spacing: 6) {
            ForEach(Array(tabs.enumerated()), id: \.offset) { _, t in
                Label(t.name, systemImage: t.answered == true ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 13))
                    .foregroundStyle(t.answered == true ? Theme.green : ChatStyle.dim)
                    .padding(.horizontal, 10)
                    .frame(height: 28)
                    .background(Color.white.opacity(0.05), in: Capsule())
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if dialog.kind == "plan", let plan = dialog.plan, !plan.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                MarkdownView(blocks: plan, base: base)
                    .frame(maxHeight: planOpen ? nil : 240, alignment: .top)
                    .clipped()
                Button(planOpen ? "Show less" : "Show the whole plan") {
                    withAnimation(.easeInOut(duration: 0.2)) { planOpen.toggle() }
                }
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Theme.blue)
                .frame(minHeight: 44)
                .accessibilityIdentifier("planMore")
            }
            .padding(.top, 4)
        } else if let body = dialog.body, !body.isEmpty {
            if amber {
                Text(body.joined(separator: "\n"))
                    .font(.system(size: 14, design: .monospaced))
                    .foregroundStyle(ChatStyle.codeText)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(ChatStyle.codeBG, in: RoundedRectangle(cornerRadius: 8))
                    .padding(.top, 10)
            } else {
                Text(body.joined(separator: "\n"))
                    .font(.system(size: 15))
                    .foregroundStyle(ChatStyle.body)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 8)
            }
        }
    }

    private var onThePC: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("Answer this on the PC", systemImage: "desktopcomputer")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Theme.rowTitle)
            Text("This chat started before GupWorks could take answers from the phone. Once it's restarted on the PC, "
                 + "you can answer here.")
                .font(.system(size: 14))
                .foregroundStyle(ChatStyle.dim)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("onPC")
    }

    // MARK: answering

    @ViewBuilder
    private var answers: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let n = typing {
                wordsEntry(n)
            } else if dialog.multi == true {
                multiChoices
            } else if dialog.kind == "ask" && choices.contains(where: { ($0.detail ?? "").isEmpty == false }) {
                VStack(spacing: 8) {
                    ForEach(choices) { c in row(c) }
                }
            } else {
                FlowLayout(spacing: 8) {
                    ForEach(Array(choices.enumerated()), id: \.element.n) { i, c in
                        chip(c, primary: i == 0)
                    }
                }
            }
            if typing == nil && dialog.kind == "ask" { extras }
        }
        .disabled(busy)
    }

    /// what a choice's button says: words to type end in "…"
    private func buttonWords(_ c: Dialog.Choice) -> String {
        guard c.input == true else { return c.words }
        switch dialog.kind {
        case "plan": return "Keep planning\u{2026}"
        default: return "Something else\u{2026}"
        }
    }

    private func pick(_ c: Dialog.Choice) {
        guard let sig = dialog.sig else { return }
        if c.input == true {
            words = ""
            withAnimation(.easeInOut(duration: 0.15)) { typing = c.n }
            focused = true
            return
        }
        answer(DialogAnswer(sig: sig, choice: c.n))
    }

    private func chip(_ c: Dialog.Choice, primary: Bool) -> some View {
        Button { pick(c) } label: {
            Text(buttonWords(c))
                .font(.system(size: 16))
                .foregroundStyle(primary ? .white : ChatStyle.body)
                .padding(.horizontal, 16)
                .frame(minHeight: 44)
                .background(primary ? ChatStyle.bubble : .clear, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(primary ? ChatStyle.bubble : Color(hex: 0x3A3A40), lineWidth: 1))
                .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("choice-\(c.n)")
    }

    /// a choice with a line under it (Claude's questions often explain each one)
    private func row(_ c: Dialog.Choice) -> some View {
        Button { pick(c) } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(buttonWords(c)).font(.system(size: 16, weight: .medium)).foregroundStyle(Theme.rowTitle)
                if let d = c.detail, !d.isEmpty, c.input != true {
                    Text(d).font(.system(size: 14)).foregroundStyle(ChatStyle.dim)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(hex: 0x3A3A40), lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("choice-\(c.n)")
    }

    /// several answers: tick them, then Submit (an "other" box asks for its words)
    private var multiChoices: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(choices.filter { $0.input != true }) { c in
                let on = ticks.contains(c.n)
                Button {
                    if on { ticks.remove(c.n) } else { ticks.insert(c.n) }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: on ? "checkmark.square.fill" : "square")
                            .font(.system(size: 18))
                            .foregroundStyle(on ? Theme.blue : ChatStyle.dim)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(c.label).font(.system(size: 16)).foregroundStyle(Theme.rowTitle)
                            if let d = c.detail, !d.isEmpty {
                                Text(d).font(.system(size: 14)).foregroundStyle(ChatStyle.dim)
                                    .multilineTextAlignment(.leading)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("tick-\(c.n)")
                .accessibilityValue(on ? "ticked" : "not ticked")
            }
            if choices.contains(where: { $0.input == true }) {
                TextField("Something else (optional)", text: $words, axis: .vertical)
                    .font(.system(size: 16))
                    .lineLimit(1...4)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(Composer.fill, in: RoundedRectangle(cornerRadius: 12))
                    .accessibilityIdentifier("dialogText")
            }
            Button {
                guard let sig = dialog.sig else { return }
                let w = words.trimmingCharacters(in: .whitespacesAndNewlines)
                answer(DialogAnswer(sig: sig, ticks: ticks.sorted(), text: w.isEmpty ? nil : w))
            } label: {
                Text("Submit")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 20)
                    .frame(minHeight: 44)
                    .background(ChatStyle.bubble, in: RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
            .disabled(ticks.isEmpty && words.trimmingCharacters(in: .whitespaces).isEmpty)
            .accessibilityIdentifier("dialogSubmit")
        }
    }

    private func wordsEntry(_ n: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField(dialog.kind == "plan" ? "What should Claude change?" : "Your answer", text: $words, axis: .vertical)
                .font(.system(size: 17))
                .foregroundStyle(Theme.title)
                .lineLimit(1...8)
                .focused($focused)
                .padding(.horizontal, 12)
                .padding(.vertical, 11)
                .background(Composer.fill, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Composer.border, lineWidth: 1))
                .accessibilityIdentifier("dialogText")
            HStack(spacing: 8) {
                Button("Back") {
                    withAnimation(.easeInOut(duration: 0.15)) { typing = nil }
                }
                .font(.system(size: 16))
                .foregroundStyle(ChatStyle.body)
                .padding(.horizontal, 16)
                .frame(minHeight: 44)
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(hex: 0x3A3A40), lineWidth: 1))
                Button {
                    guard let sig = dialog.sig else { return }
                    let w = words.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !w.isEmpty else { return }
                    answer(DialogAnswer(sig: sig, choice: n, text: w))
                } label: {
                    Text("Send")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 20)
                        .frame(minHeight: 44)
                        .background(ChatStyle.bubble, in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .disabled(words.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityIdentifier("dialogSend")
            }
        }
    }

    /// Claude's question also offers "Chat about this" and Esc (skip)
    private var extras: some View {
        HStack(spacing: 18) {
            if dialog.chat != nil {
                Button("Chat about this") {
                    if let sig = dialog.sig { answer(DialogAnswer(sig: sig, action: "chat")) }
                }
                .accessibilityIdentifier("dialogChat")
            }
            Button("Skip") {
                if let sig = dialog.sig { answer(DialogAnswer(sig: sig, action: "skip")) }
            }
            .accessibilityIdentifier("dialogSkip")
        }
        .font(.system(size: 15))
        .foregroundStyle(ChatStyle.dim)
        .frame(minHeight: 44)
    }
}
