import SwiftUI

// The Script stage on the phone (a180, mockups 07-09): the script to read with its facts and style hits, a line
// selected goes to the video chat (Change this, Punchier, Why?, Comment), the chat's rewrites wait inline with
// Accept and Undo, and Listen reads it aloud with the PC's Kokoro voice, a word at a time.

/// 07-08: the script, chapter by chapter.
struct StudioScriptStage: View {
    let store: StudioVideoStore
    @State private var selected: String?
    @State private var listen = Demo.isOn && Demo.args.contains("-listen")
    @State private var factCheck = false
    @State private var asking: String?
    @State private var askText = ""

    var body: some View {
        if let s = store.script {
            if listen {
                StudioListenView(store: store, script: s, start: selected) { listen = false }
            } else {
                reading(s)
            }
        } else {
            ProgressView().frame(maxWidth: .infinity).padding(.vertical, 40)
            Spacer()
        }
    }

    private func reading(_ s: StudioScript) -> some View {
        ScrollViewReader { proxy in
            VStack(spacing: 0) {
                chips(s, proxy)
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        if factCheck { checksLine(s) }
                        ForEach(chapters(s), id: \.chapter) { ch in
                            Text(header(ch, s))
                                .font(.system(size: 12, weight: .semibold)).kerning(0.6)
                                .foregroundStyle(StudioLook.label)
                                .padding(.horizontal, 6)
                                .padding(.top, 14)
                                .padding(.bottom, 4)
                                .id("chapter-\(ch.chapter)")
                            ForEach(s.lines.filter { ($0.chapter ?? 0) == ch.chapter }) { line in
                                lineView(line, s)
                                if let c = lastOf(line.id, in: s) { changeCard(c) }
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, selected == nil ? 30 : 150)
                }
                .refreshable { await store.load("script") }
            }
            .overlay(alignment: .bottom) { if let id = selected, let line = s.lines.first(where: { $0.id == id }) { bar(line) } }
        }
        .alert(asking == "comment" ? "Comment on line \(selected ?? "")" : "Change line \(selected ?? "")",
               isPresented: Binding(get: { asking != nil }, set: { if !$0 { asking = nil } })) {
            TextField(asking == "comment" ? "Your comment" : "What to change", text: $askText)
            Button("Cancel", role: .cancel) { askText = "" }
            Button("Send") {
                let what = asking ?? "change"
                let text = askText
                askText = ""
                ask(what, extra: text)
            }
        }
    }

    // chips: chapter, Listen, Fact-check, versions

    private func chips(_ s: StudioScript, _ proxy: ScrollViewProxy) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Menu {
                    ForEach(s.chapters, id: \.chapter) { c in
                        Button(c.title) { withAnimation { proxy.scrollTo("chapter-\(c.chapter)", anchor: .top) } }
                    }
                } label: {
                    HStack(spacing: 5) {
                        Text(s.chapters.first?.title ?? "Chapters").font(.system(size: 15))
                        Image(systemName: "chevron.down").font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundStyle(Theme.rowTitle)
                    .padding(.horizontal, 14)
                    .frame(height: 34)
                    .background(Color(hex: 0x1C1C1E), in: Capsule())
                    .overlay(Capsule().stroke(StudioLook.chipBorder, lineWidth: 1))
                }
                .accessibilityIdentifier("chapterMenu")
                StudioChip(text: "Listen", on: false, icon: "headphones", id: "listen") { listen = true }
                StudioChip(text: "Fact-check", on: factCheck, icon: "shield-check", id: "factCheck") { factCheck.toggle() }
                if let v = s.versions.first {
                    Menu {
                        ForEach(s.versions, id: \.n) { v in
                            Text("v\(v.n) \u{00B7} \(v.label ?? "") \u{00B7} \(v.by == "you" ? "you" : "the chat")")
                        }
                    } label: {
                        Text("v\(v.n) \u{00B7} \(Format.plural(s.versions.count, "version"))")
                            .font(.system(size: 15)).foregroundStyle(Theme.rowTitle)
                            .padding(.horizontal, 14).frame(height: 34)
                            .background(Color(hex: 0x1C1C1E), in: Capsule())
                            .overlay(Capsule().stroke(StudioLook.chipBorder, lineWidth: 1))
                    }
                    .accessibilityIdentifier("versions")
                }
            }
            .padding(.horizontal, 16)
        }
        .padding(.bottom, 4)
    }

    private func checksLine(_ s: StudioScript) -> some View {
        let hits = s.checks?.hits.count ?? 0, unsourced = s.checks?.unsourced.count ?? 0
        return Text(hits == 0 && unsourced == 0 ? "Every line has its facts, and no style rule is hit."
                    : "\(Format.plural(hits, "style hit")) \u{00B7} \(Format.plural(unsourced, "line")) without a fact")
            .font(.system(size: 14))
            .foregroundStyle(hits + unsourced == 0 ? Theme.green : Theme.amber)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .studioCard(radius: 12)
            .padding(.top, 6)
    }

    private func chapters(_ s: StudioScript) -> [StudioChapter] {
        s.chapters.isEmpty ? [StudioChapter(chapter: 0, title: "Script", first: s.lines.first?.id)] : s.chapters
    }

    private func header(_ ch: StudioChapter, _ s: StudioScript) -> String {
        let ids = s.lines.filter { ($0.chapter ?? 0) == ch.chapter }.map(\.id)
        guard let a = ids.first, let b = ids.last else { return ch.title.uppercased() }
        return "\(ch.title.uppercased()) \u{00B7} LINES \(a.uppercased())\u{2013}\(b.uppercased())"
    }

    /// the waiting change that ends at this line (its card goes under it)
    private func lastOf(_ id: String, in s: StudioScript) -> StudioScript.Change? {
        s.pending.first { $0.status == "pending" && $0.lines.last?.id == id }
    }

    private func edit(_ id: String, in s: StudioScript) -> StudioScript.Change.Edit? {
        s.pending.filter { $0.status == "pending" }.flatMap(\.lines).first { $0.id == id }
    }

    // a line

    private func lineView(_ line: StudioScript.Line, _ s: StudioScript) -> some View {
        let on = selected == line.id
        let unsourced = factCheck && (s.checks?.unsourced.contains(line.id) ?? false)
        return HStack(alignment: .top, spacing: 8) {
            Text(line.id)
                .font(.system(size: 11)).monospacedDigit()
                .foregroundStyle(on ? Theme.blue : Color(hex: 0x5A5A5E))
                .frame(width: 26, alignment: .trailing)
                .padding(.top, 5)
            Group {
                if let e = edit(line.id, in: s) {
                    (Text(e.old).foregroundStyle(Theme.red.opacity(0.85)).strikethrough(color: Theme.red)
                        + Text(" ") + Text(e.new).foregroundStyle(Color(hex: 0x9BD89B)))
                } else {
                    styled(line, s) + facts(line)
                }
            }
            .font(.system(size: 19, design: .serif))
            .lineSpacing(4)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 6)
        .padding(.trailing, 8)
        .background(on ? Theme.blue.opacity(0.16) : .clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(alignment: .leading) {
            if unsourced { Rectangle().fill(Theme.red).frame(width: 2).padding(.vertical, 6) }
        }
        .contentShape(Rectangle())
        .onTapGesture { select(on ? nil : line.id) }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(on ? [.isSelected, .isButton] : .isButton)
        .accessibilityIdentifier("line-\(line.id)")
    }

    /// the line's words with its style hits underlined in amber
    private func styled(_ line: StudioScript.Line, _ s: StudioScript) -> Text {
        var a = AttributedString(line.text)
        a.foregroundColor = Theme.title
        for h in s.checks?.hits ?? [] where h.line == line.id {
            let chars = Array(line.text)
            guard h.start >= 0, h.end <= chars.count, h.start < h.end else { continue }
            let lo = a.index(a.startIndex, offsetByCharacters: h.start)
            let hi = a.index(a.startIndex, offsetByCharacters: h.end)
            a[lo..<hi].underlineStyle = Text.LineStyle(pattern: .dot, color: Theme.amber)
        }
        return Text(a)
    }

    private func facts(_ line: StudioScript.Line) -> Text {
        guard let f = line.facts, !f.isEmpty else { return Text("") }
        return Text("  " + f.joined(separator: " "))
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(Theme.blue.opacity(0.8))
            .baselineOffset(3)
    }

    private func select(_ id: String?) {
        withAnimation(.snappy(duration: 0.15)) { selected = id }
        Task {
            if let id {
                // the desktop's label: "script line c3: \"Down in the harbour…\""
                let text = store.script?.lines.first { $0.id == id }?.text ?? ""
                await store.select(stage: "script", kind: "line", id: id, label: "script line \(id): \"\(text)\"")
            }
            else { await store.clearSelection() }
        }
    }

    // the bar for the selected line

    private func bar(_ line: StudioScript.Line) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 4) {
                Text("Line \(line.id) selected").foregroundStyle(Theme.title).fontWeight(.medium)
                Text("\u{00B7} goes to the video chat").foregroundStyle(StudioLook.label)
                Spacer()
                Button { select(nil) } label: {
                    Image(systemName: "xmark").font(.system(size: 13, weight: .semibold)).foregroundStyle(StudioLook.label)
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear the selection")
            }
            .font(.system(size: 14))
            HStack(spacing: 6) {
                StudioButton(title: "Change this", id: "askChange", height: 34) { asking = "change" }
                StudioButton(title: "Punchier", busy: store.busy.contains("send"), id: "askPunchier", height: 34) {
                    ask("punchier")
                }
                StudioButton(title: "Why?", id: "askWhy", height: 34) { ask("why") }
                StudioButton(title: "Comment", id: "askComment", height: 34) { asking = "comment" }
            }
            .disabled(store.readonly || store.busy.contains("send"))
        }
        .padding(14)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .padding(.horizontal, 10)
        .padding(.bottom, 6)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("selectionBar")
    }

    private func ask(_ what: String, extra: String = "") {
        guard let id = selected, let line = store.script?.lines.first(where: { $0.id == id }) else { return }
        let text = StudioVideoStore.scriptAsk(what, ids: [id], text: line.text, extra: extra)
        Task { await store.send(text) }
    }

    // a rewrite from the chat

    private func changeCard(_ c: StudioScript.Change) -> some View {
        let ids = c.lines.map(\.id)
        let what = c.request == "punchier" ? "Punchier" : c.request == "change" ? "Change" : "Rewrite"
        return VStack(alignment: .leading, spacing: 8) {
            Text("FROM THE VIDEO CHAT").font(.system(size: 11, weight: .semibold)).kerning(0.6)
                .foregroundStyle(Theme.violetText)
            Text("\(what) \u{00B7} line\(ids.count > 1 ? "s" : "") \(ids.joined(separator: ", "))")
                .font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.title)
            if let n = c.note, !n.isEmpty {
                Text(n).font(.system(size: 14)).foregroundStyle(Theme.rowTitle).fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 8) {
                StudioButton(title: "Accept", icon: "check", primary: true, busy: store.busy.contains("change-\(c.id)"),
                             id: "accept-\(c.id)", height: 34) {
                    Task { await store.resolve(change: c.id, accept: true) }
                }
                StudioButton(title: "Undo", icon: "undo-2", id: "undo-\(c.id)", height: 34) {
                    Task { await store.resolve(change: c.id, accept: false) }
                }
                StudioButton(title: "Ask again", id: "again-\(c.id)", height: 34) {
                    let old = c.lines.map(\.old).joined(separator: " ")
                    Task {
                        await store.resolve(change: c.id, accept: false)
                        await store.send(StudioVideoStore.scriptAsk(c.request == "punchier" ? "punchier" : "change",
                                                                    ids: ids, text: old,
                                                                    extra: "Try again, differently from: \"\(c.lines.map(\.new).joined(separator: " "))\""))
                    }
                }
            }
            .disabled(store.readonly)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(StudioLook.needsBG, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(StudioLook.needsBorder, lineWidth: 1))
        .padding(.leading, 34)
        .padding(.vertical, 6)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("change-\(c.id)")
    }
}

// MARK: - 09 Listen

/// 09: the script read aloud by the PC's Kokoro voice, line after line; the line being read stands out and its word
/// lights up. Speed, previous and next, and Follow (the page keeps the line in view).
struct StudioListenView: View {
    let store: StudioVideoStore
    let script: StudioScript
    let start: String?
    let close: () -> Void
    @State private var index = 0
    @State private var speech: [String: StudioSpeech] = [:]
    @State private var loading = false
    @State private var follow = true
    @State private var url: URL?
    private let audio = AudioPlayback.shared
    private static let speeds: [Float] = [0.75, 1, 1.25, 1.5, 2]

    private var line: StudioScript.Line? { script.lines.indices.contains(index) ? script.lines[index] : nil }
    private var time: Double { audio.place(of: url) }

    var body: some View {
        ScrollViewReader { proxy in
            VStack(spacing: 0) {
                HStack {
                    StudioChip(text: "Listen", on: true, icon: "headphones", id: "listenOn") { stop(); close() }
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 4)
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(Array(script.lines.enumerated()), id: \.element.id) { i, l in
                            Group {
                                if i == index, let sp = speech[l.id], !sp.words.isEmpty {
                                    words(sp)
                                } else {
                                    Text(l.text).foregroundStyle(i == index ? Theme.title : Color(hex: 0x5A5A5E))
                                }
                            }
                            .font(.system(size: 21, design: .serif))
                            .lineSpacing(5)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                            .onTapGesture { Task { await play(i) } }
                            .id(l.id)
                            .accessibilityIdentifier("listen-\(l.id)")
                        }
                    }
                    .padding(.horizontal, 22)
                    .padding(.top, 8)
                    .padding(.bottom, 220)
                }
                .scrollDisabled(false)
            }
            .overlay(alignment: .bottom) { player }
            .onChange(of: index) { _, _ in
                if follow, let id = line?.id { withAnimation { proxy.scrollTo(id, anchor: .center) } }
            }
            .onAppear {
                index = start.flatMap { s in script.lines.firstIndex { $0.id == s } } ?? 0
                if let id = line?.id { proxy.scrollTo(id, anchor: .center) }
            }
        }
        .task { await play(index) }
        .onChange(of: audio.ends) { _, _ in
            guard audio.ended == url, index + 1 < script.lines.count else { return }
            Task { await play(index + 1) }
        }
        .onDisappear { stop() }
    }

    /// the line's words as the voice read them, the one being read in blue
    private func words(_ sp: StudioSpeech) -> Text {
        let t = time
        let now = sp.words.lastIndex { $0.start <= t + 0.02 } ?? -1
        return sp.words.enumerated().reduce(Text("")) { out, pair in
            let (i, w) = pair
            let piece = Text(w.w + " ")
            return out + (i == now ? piece.foregroundStyle(Theme.blue) : piece.foregroundStyle(Theme.title))
        }
    }

    private var player: some View {
        let sp = line.flatMap { speech[$0.id] }
        let seconds = sp?.seconds ?? 0
        let chapter = script.chapters.last { $0.chapter <= (line?.chapter ?? 0) }?.title ?? ""
        return VStack(spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Line \(line?.id ?? "") of \(script.lines.count)\(chapter.isEmpty ? "" : " \u{00B7} \(chapter)")")
                        .font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.title)
                    Text("Kokoro \u{00B7} \(script.voice ?? "default voice")")
                        .font(.system(size: 13)).foregroundStyle(StudioLook.label)
                }
                Spacer()
                if loading { Spinner() }
            }
            ProgressView(value: min(1, (Double(index) + (seconds > 0 ? min(1, time / seconds) : 0))
                                     / Double(max(script.lines.count, 1))))
                .tint(Theme.blue)
            HStack {
                Text(VideoMath.clock(time)).monospacedDigit()
                Spacer()
                Text(VideoMath.clock(seconds)).monospacedDigit()
            }
            .font(.system(size: 12))
            .foregroundStyle(StudioLook.label)
            HStack {
                Button {
                    let all = Self.speeds
                    let i = all.firstIndex(of: audio.speed) ?? 1
                    audio.speed = all[(i + 1) % all.count]
                } label: {
                    Text(speedLabel).font(.system(size: 15, weight: .semibold)).monospacedDigit()
                        .foregroundStyle(Theme.rowTitle).frame(width: 56, height: 40)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Speed \(speedLabel)")
                .accessibilityIdentifier("listenSpeed")
                Spacer()
                control("backward.fill", "Previous line", "listenPrev") { Task { await play(max(0, index - 1)) } }
                Button {
                    if let url, audio.current == url { audio.toggle(url) } else { Task { await play(index) } }
                } label: {
                    Image(systemName: audio.isPlaying(url) ? "pause.fill" : "play.fill")
                        .font(.system(size: 22)).foregroundStyle(.black)
                        .frame(width: 56, height: 56)
                        .background(Color(hex: 0xF0F0F0), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(audio.isPlaying(url) ? "Pause" : "Play")
                .accessibilityIdentifier("listenPlay")
                control("forward.fill", "Next line", "listenNext") {
                    Task { await play(min(script.lines.count - 1, index + 1)) }
                }
                Spacer()
                Button { follow.toggle() } label: {
                    VStack(spacing: 2) {
                        LucideIcon(name: "locate-fixed", size: 18)
                        Text("Follow").font(.system(size: 11))
                    }
                    .foregroundStyle(follow ? Theme.blue : StudioLook.label)
                    .frame(width: 56, height: 40)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(follow ? .isSelected : [])
                .accessibilityIdentifier("listenFollow")
            }
        }
        .padding(16)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .padding(.horizontal, 10)
        .padding(.bottom, 6)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("listenPlayer")
    }

    private var speedLabel: String {
        let s = audio.speed
        return s == s.rounded() ? "\(Int(s))\u{00D7}" : "\(String(format: "%g", s))\u{00D7}"
    }

    private func control(_ icon: String, _ label: String, _ id: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 20)).foregroundStyle(Theme.rowTitle).frame(width: 48, height: 48)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityIdentifier(id)
    }

    /// Reads line `i` (Kokoro on the PC makes it the first time), then the next one is fetched ahead.
    private func play(_ i: Int) async {
        guard script.lines.indices.contains(i) else { return }
        index = i
        let l = script.lines[i]
        var sp = speech[l.id]
        if sp == nil {
            loading = true
            sp = await store.speak(l.text, voice: script.voice)
            loading = false
            guard index == i else { return }        // moved on while it was made
            if let sp { speech[l.id] = sp }
        }
        guard let sp, let u = MediaLink.url(sp.audio, base: store.baseURL) else { return }
        url = u
        audio.seek(u, to: 0)
        if !audio.isPlaying(u) { audio.toggle(u) }
        if i + 1 < script.lines.count, speech[script.lines[i + 1].id] == nil {
            let next = script.lines[i + 1]
            if let n = await store.speak(next.text, voice: script.voice) { speech[next.id] = n }
        }
    }

    private func stop() {
        if audio.isPlaying(url) { audio.pause() }
    }
}
