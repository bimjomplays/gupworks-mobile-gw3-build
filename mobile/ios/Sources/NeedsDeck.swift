import SwiftUI
import UIKit

// The needs-you bar on the phone (a230): Option 4 "Card deck" of docs/needs-phone-mockups/round1 (04-*.png and their
// HTML): a small chip under every chat's title opens full-screen cards to swipe through and answer, with a list of
// everything waiting and parked. The rules are GupKit's (Needs.swift); the colours and sizes are the mockup's.

enum NeedsLook {
    static let violet = Color(hex: 0xA78BFA)
    static let amber = Color(hex: 0xE0B060)
    static let red = Color(hex: 0xFF7B7B)
    static let card = Color(hex: 0x121118)
    static let cardEdge = Color(hex: 0x3A3456)
    static let box = Color(hex: 0x1A1A1D)
    static let boxEdge = Color(hex: 0x2F2F34)
    static let recBox = Color(hex: 0x16213A)
    static let recEdge = Color(hex: 0x3D66B8)
    static let recText = Color(hex: 0x8FB8FF)
    static let source = Color(hex: 0x9A9AA0)
    static let dimmer = Color(hex: 0x6F6F75)
    static let summary = Color(hex: 0xA3A3A8)
    static let detail = Color(hex: 0x8E8E93)
    static let list = Color(hex: 0x121214)
    static let listEdge = Color(hex: 0x232327)

    static func color(_ tone: NeedTone) -> Color {
        switch tone {
        case .violet: return violet
        case .amber: return amber
        case .red: return red
        case .grey: return Color(hex: 0x8E8E93)
        }
    }

    /// the "!" mark's own text colour on each fill
    static func ink(_ tone: NeedTone) -> Color {
        switch tone {
        case .violet: return Color(hex: 0x151021)
        case .amber: return Color(hex: 0x21180A)
        case .red: return Color(hex: 0x2A0F0F)
        case .grey: return Color(hex: 0x151515)
        }
    }
}

/// The round "!" (a memory chip for the memory warning) in the item's colour.
struct NeedsMark: View {
    let tone: NeedTone
    var size: CGFloat = 26

    var body: some View {
        Circle()
            .fill(NeedsLook.color(tone))
            .frame(width: size, height: size)
            .overlay {
                if tone == .red {
                    LucideIcon(name: "memory-stick", size: size * 0.6).foregroundStyle(NeedsLook.ink(tone))
                } else {
                    Text("!").font(.system(size: size * 0.58, weight: .bold)).foregroundStyle(NeedsLook.ink(tone))
                }
            }
            .accessibilityHidden(true)
    }
}

/// 04-card-deck-at-rest: "5 need you ›" centred under the chat's title, the only thing on the chat. Only parked items:
/// "1 parked" in grey, which opens the list. Nothing at all: nothing.
struct NeedsChip: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let deck = model.needsDeck
        if let chip = deck.chip {
            Button {
                model.openNeeds = deck.waiting.isEmpty ? NeedsDeckView.listMode : ""
            } label: {
                HStack(spacing: 8) {
                    if chip.tone == .grey {
                        LucideIcon(name: "circle-pause", size: 18).foregroundStyle(Color(hex: 0x8E8E93))
                            .frame(width: 26, height: 26)
                    } else {
                        NeedsMark(tone: chip.tone, size: 26)
                    }
                    Text(chip.text)
                        .font(.system(size: 15.5, weight: .medium))
                        .foregroundStyle(chip.tone == .grey ? Color(hex: 0xB4B4B8) : Color(hex: 0xE6E0FF))
                    LucideIcon(name: "chevron-right", size: 16)
                        .foregroundStyle(chip.tone == .grey ? Color(hex: 0x7A7A80) : Color(hex: 0x9A8FD0))
                }
                .padding(.leading, 8)
                .padding(.trailing, 14)
                .frame(height: 40)
                .glassEffect(.regular.interactive(), in: .capsule)
                .overlay(Capsule().stroke(chip.tone == .grey ? Color.white.opacity(0.11)
                                          : NeedsLook.color(chip.tone).opacity(0.45), lineWidth: 1))
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(chip.text)
            .accessibilityIdentifier("needsChip")
            .transition(.opacity)
        }
    }
}

/// A glass round button with its label under it (the deck's bottom bar) or alone (its top corners).
private struct DeckButton: View {
    let icon: String
    var label: String?
    /// what VoiceOver says when there's no label under it
    var name: String = ""
    var id: String
    let action: () -> Void

    var body: some View {
        VStack(spacing: 5) {
            Button(action: action) {
                LucideIcon(name: icon, size: 21)
                    .foregroundStyle(Theme.rowTitle)
                    .frame(width: 48, height: 48)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.interactive(), in: .circle)
            .accessibilityLabel(label ?? name)
            .accessibilityIdentifier(id)
            if let label {
                Text(label).font(.system(size: 13)).foregroundStyle(Color(hex: 0xA8A8AD)).accessibilityHidden(true)
            }
        }
    }
}

/// 04-card-deck-question-open and 04-card-deck-all-waiting: the deck over everything. `start`: the card to open at (an
/// item's key; "" the first) or `listMode` for the list.
struct NeedsDeckView: View {
    static let listMode = "#list"

    let start: String
    /// Open chat (or a tap on the card's name): the deck closes and the chat shows with the card in view
    let openChat: (NeedItem) -> Void
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var current: String?
    @State private var lastIndex: Int?
    @State private var listing = false
    @State private var memory = false
    @State private var typing: String?
    @State private var started = false

    var body: some View {
        let deck = model.needsDeck
        ZStack {
            Color.black.ignoresSafeArea()
            if listing || deck.waiting.isEmpty {
                NeedsListView(deck: deck, current: current, now: model.pcNow, close: { dismiss() }) { key in
                    current = key
                    withAnimation(.easeOut(duration: 0.2)) { listing = false }
                }
                .transition(.opacity)
            } else {
                cards(deck)
                    .transition(.opacity)
            }
        }
        .onAppear {
            guard !started else { return }
            started = true
            if start == Self.listMode {
                listing = true
            } else {
                current = deck.index(of: start).map { deck.waiting[$0].key } ?? deck.waiting.first?.key
            }
            lastIndex = deck.index(of: current)
        }
        .onChange(of: deck.waiting.map(\.key)) { _, keys in
            // answered, snoozed or dismissed (here or on the PC): the next one in its place
            let i = deck.current(after: current, was: lastIndex)
            current = i.map { keys[$0] }
            lastIndex = i
            if keys.isEmpty && deck.parked.isEmpty { dismiss() }
        }
        .onChange(of: current) { _, key in
            if let i = deck.index(of: key) { lastIndex = i }
        }
        .sheet(isPresented: $memory) { MemorySheet() }
        .preferredColorScheme(.dark)
    }

    private func cards(_ deck: NeedsDeck) -> some View {
        let index = deck.index(of: current) ?? 0
        return VStack(spacing: 0) {
            // X · "1 of 5" and its dots · the list
            ZStack {
                VStack(spacing: 6) {
                    Text(deck.position(index))
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color(hex: 0xECECEC))
                        .accessibilityIdentifier("needsPosition")
                    HStack(spacing: 6) {
                        ForEach(0..<min(deck.waiting.count, 12), id: \.self) { k in
                            Circle().fill(k == index ? Color(hex: 0xECECEC) : Color(hex: 0x48484C)).frame(width: 7, height: 7)
                        }
                    }
                    .accessibilityHidden(true)
                }
                HStack {
                    DeckButton(icon: "x", name: "Close", id: "needsClose") { dismiss() }
                    Spacer()
                    DeckButton(icon: "layout-grid", name: "All of them", id: "needsAll") {
                        withAnimation(.easeOut(duration: 0.2)) { listing = true }
                    }
                }
                .padding(.horizontal, 14)
            }
            .padding(.top, 6)
            .frame(height: 60)

            // the cards, the next one peeking at the right edge
            ScrollView(.horizontal) {
                LazyHStack(spacing: 8) {
                    ForEach(deck.waiting) { item in
                        NeedCardView(item: item, now: model.pcNow, base: model.pairing?.baseURL, typing: $typing,
                                     answer: { answer(item, option: $0, text: $1) },
                                     openChat: { open(item) })
                            .containerRelativeFrame(.horizontal)  // the scroll view less its margins: the next card peeks 18 pt
                            .id(item.key)
                    }
                }
                .scrollTargetLayout()
            }
            .contentMargins(.leading, 14, for: .scrollContent)
            .contentMargins(.trailing, 26, for: .scrollContent)
            .scrollTargetBehavior(.viewAligned(limitBehavior: .alwaysByOne))
            .scrollPosition(id: $current)
            .scrollIndicators(.hidden)
            .scrollDisabled(typing != nil)
            .padding(.top, 10)
            .accessibilityIdentifier("needsCards")

            // Snooze · Open chat · Dismiss, in the thumb's reach
            if typing == nil, let item = deck.waiting.first(where: { $0.key == current }) ?? deck.waiting.first {
                HStack {
                    DeckButton(icon: "clock", label: "Snooze", id: "needsSnooze") {
                        Task { await model.snooze(need: item) }
                    }
                    .frame(maxWidth: .infinity)
                    if item.kind == "memory" {
                        DeckButton(icon: "memory-stick", label: "Show memory", id: "needsShowMemory") { memory = true }
                            .frame(maxWidth: .infinity)
                    } else {
                        DeckButton(icon: "message-circle", label: "Open chat", id: "needsOpenChat") { open(item) }
                            .frame(maxWidth: .infinity)
                    }
                    DeckButton(icon: "x", label: "Dismiss", id: "needsDismiss") {
                        Task { await model.dismiss(need: item) }
                    }
                    .frame(maxWidth: .infinity)
                }
                .padding(.horizontal, 24)
                .padding(.top, 12)
                .padding(.bottom, 4)
            }
        }
    }

    private func answer(_ item: NeedItem, option: Int?, text: String?) {
        if item.kind == "memory" {
            if option == 1 { memory = true; return }
            Task {
                await model.answer(need: item, option: option)
                memory = true  // as the desktop: Sleep idle chats, then the Memory page says what it did
            }
            return
        }
        typing = nil
        Task { await model.answer(need: item, option: option, text: text) }
    }

    private func open(_ item: NeedItem) {
        if item.kind == "memory" {
            memory = true
            return
        }
        dismiss()
        openChat(item)
    }
}

/// One card: whose it is and how long it waited, the question, its summary, the pictures, the big answer boxes and
/// "Something else…" typed in place.
struct NeedCardView: View {
    let item: NeedItem
    let now: Double
    let base: URL?
    @Binding var typing: String?
    let answer: (Int?, String?) -> Void
    let openChat: () -> Void
    @State private var words = ""
    @FocusState private var focused: Bool

    var body: some View {
        let card = NeedCard(item)
        let tone = NeedsDeck.tone(of: item)
        ScrollViewReader { reader in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Button(action: openChat) {
                        HStack(spacing: 10) {
                            NeedsMark(tone: tone, size: 30)
                            HStack(spacing: 5) {
                                if item.source != "memory" {
                                    LucideIcon(name: item.source == "chat" ? "message-circle" : "folder", size: 15)
                                        .foregroundStyle(NeedsLook.detail)
                                }
                                Text(item.name).foregroundStyle(NeedsLook.source).lineLimit(1)
                                Text("\u{00B7} \(NeedsDeck.wait(now - item.since))").foregroundStyle(NeedsLook.dimmer)
                                    .fixedSize()
                            }
                            .font(.system(size: 14))
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(item.name), waited \(NeedsDeck.wait(now - item.since))")
                    .accessibilityHint(item.kind == "memory" ? "Shows memory" : "Opens the chat with this question")
                    .accessibilityIdentifier("needsSource")

                    Text(card.text)
                        .font(.system(size: 21, weight: .medium))
                        .lineSpacing(4)
                        .foregroundStyle(Color(hex: 0xF0F0F0))
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 14)
                        .accessibilityIdentifier("needsQuestion")
                    if !card.summary.isEmpty {
                        Text(card.summary)
                            .font(.system(size: 15.5))
                            .lineSpacing(4)
                            .foregroundStyle(NeedsLook.summary)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 8)
                    }
                    if !card.body.isEmpty {
                        Text(card.body.joined(separator: "\n"))
                            .font(.system(size: 14, design: .monospaced))
                            .foregroundStyle(Color(hex: 0xD4D4D8))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                            .background(NeedsLook.box, in: RoundedRectangle(cornerRadius: 12))
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(NeedsLook.boxEdge, lineWidth: 1))
                            .padding(.top, 14)
                    }
                    ForEach(Array(card.pictures.enumerated()), id: \.offset) { k, pic in
                        picture(pic).padding(.top, k == 0 ? 14 : 8)
                    }
                    VStack(spacing: 8) {
                        ForEach(Array(card.answers.enumerated()), id: \.offset) { k, a in
                            Button { answer(k, nil) } label: { box(a) }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("needsAnswer-\(k)")
                        }
                        if card.somethingElse { other(card, reader: reader) }
                    }
                    .padding(.top, 14)
                    Color.clear.frame(height: 1).id("end")
                }
                .padding(18)
            }
            .scrollIndicators(.hidden)
            .background(NeedsLook.card, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).stroke(NeedsLook.cardEdge, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("needsCard")
    }

    private func box(_ a: NeedCard.Answer) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(a.label).font(.system(size: 16, weight: .medium)).foregroundStyle(Color(hex: 0xECECEC))
                Spacer(minLength: 0)
                if a.recommended {
                    Text("Recommended").font(.system(size: 12.5, weight: .medium)).foregroundStyle(NeedsLook.recText)
                }
            }
            if !a.detail.isEmpty {
                Text(a.detail)
                    .font(.system(size: 14))
                    .foregroundStyle(NeedsLook.detail)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(a.recommended ? NeedsLook.recBox : NeedsLook.box, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(a.recommended ? NeedsLook.recEdge : NeedsLook.boxEdge, lineWidth: 1))
        .contentShape(RoundedRectangle(cornerRadius: 14))
    }

    /// "Something else…": a dashed box that becomes a field in place; the card scrolls it above the keyboard
    @ViewBuilder
    private func other(_ card: NeedCard, reader: ScrollViewProxy) -> some View {
        let open = typing == item.key
        VStack(alignment: .leading, spacing: 8) {
            if open {
                TextField("Type your own answer", text: $words, axis: .vertical)
                    .font(.system(size: 16))
                    .foregroundStyle(Color(hex: 0xECECEC))
                    .lineLimit(1...6)
                    .focused($focused)
                    .accessibilityIdentifier("needsOther")
                HStack(spacing: 10) {
                    Spacer()
                    Button("Cancel") {
                        typing = nil
                        focused = false
                    }
                    .font(.system(size: 15))
                    .foregroundStyle(Color(hex: 0xC8C8CC))
                    .accessibilityIdentifier("needsOtherCancel")
                    Button {
                        let t = words.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !t.isEmpty, t != card.prefix.trimmingCharacters(in: .whitespaces) else { return }
                        focused = false
                        answer(nil, t)
                    } label: {
                        Text("Send")
                            .font(.system(size: 15.5, weight: .medium))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 16)
                            .frame(height: 36)
                            .background(Color(hex: 0x2F5FB3), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("needsOtherSend")
                }
            } else {
                Text(words.isEmpty || words == card.prefix ? "Something else\u{2026}" : words)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Color(hex: 0xC8C8CC))
                    .lineLimit(2)
                Text("Type your own answer").font(.system(size: 14)).foregroundStyle(NeedsLook.detail)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .overlay(RoundedRectangle(cornerRadius: 14)
            .stroke(open ? NeedsLook.recEdge : Color(hex: 0x3D3D42), style: StrokeStyle(lineWidth: 1, dash: open ? [] : [4, 3])))
        .contentShape(RoundedRectangle(cornerRadius: 14))
        .onTapGesture {
            guard !open else { return }
            if words.isEmpty { words = card.prefix }
            typing = item.key
            focused = true
        }
        .onChange(of: focused) { _, on in
            if on {
                // above the keyboard: the field's end in view once the keyboard is up
                Task {
                    try? await Task.sleep(nanoseconds: 350_000_000)
                    withAnimation(.easeOut(duration: 0.2)) { reader.scrollTo("end", anchor: .bottom) }
                }
            }
        }
        .accessibilityElement(children: open ? .contain : .combine)
        .accessibilityAddTraits(open ? [] : .isButton)
        .accessibilityIdentifier(open ? "needsOtherBox" : "needsSomethingElse")
    }

    private func picture(_ pic: NeedItem.Picture) -> some View {
        RemoteImage(url: MediaLink.url(pic.url, base: base), fill: true)
            .frame(maxWidth: .infinity)
            .frame(height: 190)
            .clipped()
            .overlay(alignment: .bottom) {
                if let c = pic.caption, !c.isEmpty {
                    caption(c)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 6)
                        .background(Color(hex: 0x0E0E10).opacity(0.88))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(NeedsLook.boxEdge, lineWidth: 1))
            .accessibilityElement()
            .accessibilityLabel(pic.caption ?? "Picture")
            .accessibilityIdentifier("needsPicture")
    }

    /// "Before · One per row": the first word bold, as the mockup's captions
    private func caption(_ c: String) -> Text {
        let parts = c.components(separatedBy: " \u{00B7} ")
        guard parts.count > 1 else { return Text(c).font(.system(size: 13)).foregroundStyle(Color(hex: 0xD4D4D8)) }
        let first = Text(parts[0]).font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
        let rest = parts.dropFirst().joined(separator: " \u{00B7} ")
        return Text("\(first) \(rest)").font(.system(size: 13)).foregroundStyle(Color(hex: 0xD4D4D8))
    }
}

/// 04-card-deck-all-waiting: "Needs you": Waiting · N oldest first with wait times, the current card marked blue (a tap
/// jumps to it), then Parked · N with Bring back.
struct NeedsListView: View {
    let deck: NeedsDeck
    let current: String?
    let now: Double
    let close: () -> Void
    let jump: (String) -> Void
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                DeckButton(icon: "x", name: "Close", id: "needsListClose", action: close)
                    .padding(.top, 6)
                Text("Needs you")
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundStyle(Color(hex: 0xF0F0F0))
                    .padding(.leading, 6)
                    .padding(.top, 14)
                    .accessibilityAddTraits(.isHeader)
                if !deck.waiting.isEmpty {
                    header("Waiting \u{00B7} \(deck.waiting.count)", right: "oldest first")
                        .padding(.top, 18)
                    group {
                        ForEach(Array(deck.waiting.enumerated()), id: \.element.key) { k, item in
                            if k > 0 { Rectangle().fill(NeedsLook.listEdge).frame(height: 1).padding(.leading, 53) }
                            row(item)
                        }
                    }
                }
                if !deck.parked.isEmpty {
                    header("Parked \u{00B7} \(deck.parked.count)", right: nil)
                        .padding(.top, 22)
                    group {
                        ForEach(Array(deck.parked.enumerated()), id: \.element.project.projectId) { k, p in
                            if k > 0 { Rectangle().fill(NeedsLook.listEdge).frame(height: 1).padding(.leading, 53) }
                            parkedRow(p.project, items: p.items)
                        }
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 30)
        }
        .scrollIndicators(.hidden)
        .accessibilityIdentifier("needsList")
    }

    private func header(_ text: String, right: String?) -> some View {
        HStack {
            Text(text)
            Spacer()
            if let right { Text(right) }
        }
        .font(.system(size: 14, weight: .medium))
        .foregroundStyle(Color(hex: 0x8E8E93))
        .padding(.horizontal, 6)
        .padding(.bottom, 8)
    }

    private func group(@ViewBuilder _ content: () -> some View) -> some View {
        VStack(spacing: 0) { content() }
            .background(NeedsLook.list, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(NeedsLook.listEdge, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func source(_ name: String, chat: Bool, memory: Bool) -> some View {
        HStack(spacing: 5) {
            if !memory {
                LucideIcon(name: chat ? "message-circle" : "folder", size: 15).foregroundStyle(NeedsLook.detail)
            }
            Text(name).lineLimit(1)
        }
        .font(.system(size: 14))
        .foregroundStyle(NeedsLook.source)
    }

    private func row(_ item: NeedItem) -> some View {
        let on = item.key == current
        return Button { jump(item.key) } label: {
            HStack(spacing: 11) {
                NeedsMark(tone: NeedsDeck.tone(of: item), size: 28)
                VStack(alignment: .leading, spacing: 1) {
                    source(item.name, chat: item.source == "chat", memory: item.source == "memory")
                    Text(item.listTitle)
                        .font(.system(size: 16.5, weight: .medium))
                        .foregroundStyle(Color(hex: 0xECECEC))
                        .lineLimit(1)
                }
                Spacer(minLength: 6)
                Text(NeedsDeck.wait(now - item.since))
                    .font(.system(size: 13.5))
                    .foregroundStyle(Color(hex: 0x7A7A80))
            }
            .padding(.horizontal, 14)
            .frame(height: 64)
            .background(on ? Color(hex: 0x16161C) : .clear)
            .overlay(alignment: .leading) {
                if on { Rectangle().fill(Theme.blue).frame(width: 3) }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(item.name), \(item.listTitle), \(NeedsDeck.wait(now - item.since))")
        .accessibilityValue(on ? "Current card" : "")
        .accessibilityIdentifier("needsRow-\(item.key)")
    }

    private func parkedRow(_ p: ParkedProject, items: Int) -> some View {
        HStack(spacing: 11) {
            LucideIcon(name: "circle-pause", size: 22)
                .foregroundStyle(NeedsLook.dimmer)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 1) {
                source(p.name, chat: false, memory: false)
                Text(items == 0 ? "Nothing waiting, off the list"
                     : items == 1 ? "1 question, off the list" : "\(items) questions, off the list")
                    .font(.system(size: 16.5, weight: .medium))
                    .foregroundStyle(Color(hex: 0x9A9AA0))
                    .lineLimit(1)
            }
            Spacer(minLength: 6)
            Button {
                Task { await model.park(project: p.projectId, false) }
            } label: {
                Text("Bring back")
                    .font(.system(size: 14.5, weight: .medium))
                    .foregroundStyle(Color(hex: 0xE6E6E6))
                    .padding(.horizontal, 13)
                    .frame(height: 34)
                    .background(Color.white.opacity(0.03), in: Capsule())
                    .overlay(Capsule().stroke(Color(hex: 0x38383D), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("needsBringBack-\(p.projectId)")
        }
        .padding(.horizontal, 14)
        .frame(height: 64)
        .accessibilityElement(children: .contain)
    }
}

/// "Show memory" (README feature 9): the desktop's Memory page as a sheet: how full the PC is, RAM and swap, GupWorks'
/// share, each running chat with Sleep, and Sleep all idle.
struct MemorySheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var data: MemoryView?
    @State private var failed: String?
    @State private var busy: Set<String> = []
    @State private var result: [String: String] = [:]
    @State private var allBusy = false
    @State private var allResult: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("What is using the PC's memory, and what GupWorks can free.")
                        .font(.system(size: 15))
                        .foregroundStyle(Theme.secondary)
                    if let m = data {
                        content(m)
                    } else if let failed {
                        Text(failed).font(.system(size: 15)).foregroundStyle(Theme.secondary).padding(.top, 24)
                    } else {
                        ProgressView().frame(maxWidth: .infinity).padding(.top, 40)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 30)
            }
            .navigationTitle("Memory")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.accessibilityIdentifier("memoryDone")
                }
            }
            .background(Color(hex: 0x0E0E10))
        }
        .preferredColorScheme(.dark)
        .task { await load() }
        .accessibilityIdentifier("memorySheet")
    }

    private func load() async {
        do {
            data = try await model.memory()
        } catch {
            failed = "No numbers yet: the projects service writes them every 15 seconds (gw3-projects)."
        }
    }

    @ViewBuilder
    private func content(_ m: MemoryView) -> some View {
        let level = m.level ?? 0
        VStack(alignment: .leading, spacing: 4) {
            Text(MemoryText.state(m))
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(level >= 2 ? NeedsLook.red : level == 1 ? NeedsLook.amber : Theme.green)
            if let w = MemoryText.warning(m) {
                Text(w).font(.system(size: 14.5)).foregroundStyle(Color(hex: 0xC8C8CC))
            }
            if m.stale == true {
                Text("These numbers are old: is the projects service (gw3-projects) running?")
                    .font(.system(size: 14)).foregroundStyle(NeedsLook.amber)
            }
        }
        .padding(.top, 18)
        section("Now")
        let ram = MemoryText.ram(m)
        meter("RAM", ram.value, ram.hint, ram.pct, MemoryText.level(ram: m))
        let swap = MemoryText.swap(m)
        meter("Swap", swap.value, swap.hint, swap.pct, MemoryText.level(swap: m)).padding(.top, 10)
        section("GupWorks")
        let share = MemoryText.share(m)
        box {
            VStack(alignment: .leading, spacing: 3) {
                Text(share.total).font(.system(size: 16, weight: .medium)).foregroundStyle(Theme.rowTitle)
                Text(share.parts).font(.system(size: 13.5)).foregroundStyle(Theme.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
        }
        HStack {
            Text("Chats and threads").font(.system(size: 14, weight: .medium)).foregroundStyle(Theme.section)
            Spacer()
            small(allBusy ? "Sleeping\u{2026}" : "Sleep all idle", id: "memorySleepAll") { Task { await sleepAll() } }
                .disabled(allBusy)
        }
        .padding(.top, 22)
        .padding(.bottom, 8)
        if let allResult {
            Text(allResult).font(.system(size: 13.5)).foregroundStyle(Theme.secondary).padding(.bottom, 8)
        }
        box {
            let chats = m.chats ?? []
            if chats.isEmpty {
                Text("No chat is running.").font(.system(size: 15)).foregroundStyle(Theme.secondary).padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            ForEach(Array(chats.enumerated()), id: \.element.id) { k, c in
                if k > 0 { Rectangle().fill(NeedsLook.listEdge).frame(height: 1).padding(.leading, 14) }
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(c.name).font(.system(size: 15.5, weight: .medium)).foregroundStyle(Theme.rowTitle).lineLimit(1)
                        Text(result[c.chat] ?? MemoryText.hint(c))
                            .font(.system(size: 13))
                            .foregroundStyle(c.nearLimit == true ? NeedsLook.amber : Theme.secondary)
                            .lineLimit(2)
                    }
                    Spacer(minLength: 6)
                    Text(MemoryText.gb(c.used)).font(.system(size: 14)).foregroundStyle(Color(hex: 0xC8C8CC))
                    small(busy.contains(c.chat) ? "\u{2026}" : "Sleep", id: "memorySleep-\(c.chat)") {
                        Task { await sleep(c.chat) }
                    }
                    .disabled(busy.contains(c.chat) || result[c.chat] == "Asleep")
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }
        }
        if let others = m.others, !others.isEmpty {
            section("Other apps")
            box {
                ForEach(Array(others.enumerated()), id: \.offset) { k, o in
                    if k > 0 { Rectangle().fill(NeedsLook.listEdge).frame(height: 1).padding(.leading, 14) }
                    HStack {
                        Text(o.label).font(.system(size: 15)).foregroundStyle(Theme.rowTitle)
                        Spacer()
                        Text(MemoryText.gb(o.used)).font(.system(size: 14)).foregroundStyle(Color(hex: 0xC8C8CC))
                    }
                    .padding(.horizontal, 14)
                    .frame(height: 44)
                }
            }
        }
    }

    private func section(_ title: String) -> some View {
        Text(title).font(.system(size: 14, weight: .medium)).foregroundStyle(Theme.section)
            .padding(.top, 22).padding(.bottom, 8)
    }

    private func box(@ViewBuilder _ content: () -> some View) -> some View {
        VStack(spacing: 0) { content() }
            .background(NeedsLook.list, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(NeedsLook.listEdge, lineWidth: 1))
    }

    private func meter(_ name: String, _ value: String, _ hint: String, _ pct: Double, _ level: Int) -> some View {
        box {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(name).font(.system(size: 15, weight: .medium)).foregroundStyle(Theme.rowTitle)
                    Spacer()
                    Text(value).font(.system(size: 14)).foregroundStyle(Color(hex: 0xC8C8CC))
                }
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color(hex: 0x26262A))
                        Capsule().fill(level >= 2 ? NeedsLook.red : level == 1 ? NeedsLook.amber : Theme.blue)
                            .frame(width: g.size.width * min(max(pct, 0), 100) / 100)
                    }
                }
                .frame(height: 8)
                if !hint.isEmpty {
                    Text(hint).font(.system(size: 13)).foregroundStyle(Theme.secondary)
                }
            }
            .padding(14)
        }
        .accessibilityElement(children: .combine)
    }

    private func small(_ title: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color(hex: 0xE6E6E6))
                .padding(.horizontal, 12)
                .frame(height: 32)
                .overlay(Capsule().stroke(Color(hex: 0x38383D), lineWidth: 1))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
    }

    private func sleep(_ chat: String) async {
        busy.insert(chat)
        defer { busy.remove(chat) }
        do {
            let r = try await model.sleep(SleepBody(chatId: chat))
            result[chat] = r.words
            if let m = r.memory { data = m }
        } catch {
            result[chat] = "The projects service isn't running"
        }
    }

    private func sleepAll() async {
        allBusy = true
        defer { allBusy = false }
        do {
            let r = try await model.sleep(SleepBody(all: true))
            allResult = r.words
            for c in r.sleptChats ?? [] { result[c] = "Asleep" }
            if let m = r.memory { data = m }
        } catch {
            allResult = "The projects service isn't running"
        }
    }
}
