import SwiftUI

// A Studio video on the phone (a180, mockups 03-06): its overview and the stage screens, one page with a stage row
// on top. Script and Listen are in StudioScript.swift; Voice, Visuals and Final cut in StudioStages.swift; Edit is
// a181's StudioEditView, pushed through StudioEditEntry.swift.

/// 03 and the stages: the video's overview, or one stage when `stage` is set.
struct StudioVideoPage: View {
    let projectId: String
    let videoId: String
    @Environment(AppModel.self) private var model
    @Environment(\.openChat) private var openChat
    @Environment(\.dismiss) private var dismiss
    @Environment(\.pushRoute) private var pushRoute
    @State private var store: StudioVideoStore?
    @State private var stage: String?

    init(projectId: String, videoId: String, stage: String? = nil) {
        self.projectId = projectId
        self.videoId = videoId
        _stage = State(initialValue: stage)
    }

    var body: some View {
        let o = store?.overview
        VStack(spacing: 0) {
            StudioTopBar(back: {
                if stage != nil { withAnimation(.snappy(duration: 0.2)) { stage = nil } } else { dismiss() }
            }, chat: store?.chatId.map { id in { openChat?(id) } }, chatDot: o?.needs != nil) {
                if let stage {
                    StudioPill(title: StudioLook.stageName(stage), subtitle: store?.title)
                } else {
                    StudioPill(title: store?.title ?? "Video", subtitle: "Overview")
                }
            }
            if stage != nil, let o { stageRow(o) }
            if let store, o != nil {
                page(store)
            } else if let e = store?.error {
                StudioNote(text: e.message)
                Spacer()
            } else {
                ProgressView().frame(maxWidth: .infinity).padding(.vertical, 40)
                Spacer()
            }
        }
        .background(Theme.background)
        .toolbar(.hidden, for: .navigationBar)
        .overlay(alignment: .bottom) {
            if let n = store?.notice {
                Text(n)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Theme.title)
                    .padding(.horizontal, 18)
                    .frame(height: 42)
                    .glassEffect(.regular, in: .capsule)
                    .padding(.bottom, 90)
                    .transition(.opacity)
                    .task(id: n) {
                        try? await Task.sleep(nanoseconds: 2_500_000_000)
                        withAnimation { store?.notice = nil }
                    }
                    .accessibilityIdentifier("studioNotice")
            }
        }
        .alert("That didn't work", isPresented: Binding(get: { store?.actionError != nil },
                                                       set: { if !$0 { store?.actionError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(store?.actionError ?? "")
        }
        .task {
            if store == nil {
                store = StudioVideoStore(projectId: projectId, videoId: videoId, pairing: model.pairing, demo: model.demo)
                await store?.refresh()
            }
        }
        .task(id: stage ?? "") {
            guard let store else { return }
            if let stage, store.demo { await store.refresh(); await store.load(stage); return }
            await store.follow(stage)
        }
    }

    @ViewBuilder
    private func page(_ store: StudioVideoStore) -> some View {
        switch stage {
        case nil: StudioOverviewView(store: store) { s in pick(s) }
        case "brief": StudioBriefStage(store: store) { withAnimation { stage = "research" } }
        case "research": StudioResearchStage(store: store)
        case "script": StudioScriptStage(store: store)
        case "voice": StudioVoiceStage(store: store)
        case "visuals": StudioVisualsStage(store: store)
        case "edit": ScrollView { StudioEditStage(store: store) }
        case "finish": StudioFinishStage(store: store)
        default:
            ScrollView {
                StudioNote(text: (store.overview?.stages.first { $0.key == stage }?.summary ?? "")
                           + "\n\nThis stage is on the PC for now.")
            }
        }
    }

    /// Opens a stage; Edit is a181's own page, pushed on the stack when it's there.
    private func pick(_ s: String) {
        if s == "edit", let r = studioEditRoute(projectId: projectId, videoId: videoId, title: store?.title ?? "Video") {
            pushRoute?(r)
            return
        }
        withAnimation(.snappy(duration: 0.2)) { stage = s }
    }

    /// The stages as pills: done ones with a tick, the open one white.
    private func stageRow(_ o: StudioOverview) -> some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(o.stages) { s in
                        let on = s.key == stage
                        Button { pick(s.key) } label: {
                            HStack(spacing: 5) {
                                if s.state == "done" { Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)) }
                                if s.busy && !on { Spinner().scaleEffect(0.7).frame(width: 12, height: 12) }
                                Text(s.name).font(.system(size: 15, weight: on ? .semibold : .regular))
                            }
                            .foregroundStyle(on ? Color.black : s.state == "todo" ? Theme.secondary : Theme.rowTitle)
                            .padding(.horizontal, 14)
                            .frame(height: 34)
                            .background(on ? Color(hex: 0xF0F0F0) : Color(hex: 0x1C1C1E), in: Capsule())
                            .overlay(Capsule().stroke(on ? .clear : StudioLook.chipBorder, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                        .id(s.key)
                        .accessibilityAddTraits(on ? .isSelected : [])
                        .accessibilityIdentifier("stage-\(s.key)")
                    }
                }
                .padding(.horizontal, 16)
            }
            .padding(.bottom, 10)
            .onAppear { proxy.scrollTo(stage, anchor: .center) }
            .onChange(of: stage) { _, s in withAnimation { proxy.scrollTo(s, anchor: .center) } }
        }
    }
}

// MARK: - 03 Overview

/// 03: the cover and lengths, what needs you (answered right here), and the stages with what each holds.
struct StudioOverviewView: View {
    let store: StudioVideoStore
    let open: (String) -> Void

    var body: some View {
        ScrollView {
            if let o = store.overview {
                VStack(alignment: .leading, spacing: 16) {
                    header(o)
                    if let n = o.needs { StudioNeedsCard(need: n, cover: o.card.cover, store: store) }
                    stages(o)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 30)
            }
        }
        .refreshable { await store.refresh() }
    }

    private func header(_ o: StudioOverview) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Group {
                if let c = o.card.cover {
                    RemoteImage(url: MediaLink.url(c, base: store.baseURL), fill: true)
                } else {
                    Color(hex: 0x111113).overlay(LucideIcon(name: "film", size: 22).foregroundStyle(Color(hex: 0x55555A)))
                }
            }
            .frame(width: 120, height: 68)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(o.card.title).font(.system(size: 20, weight: .bold)).foregroundStyle(Theme.title).lineLimit(2)
                Text(kindLine(o)).font(.system(size: 14)).foregroundStyle(Theme.rowTitle)
                Text("changed \(Format.ago(o.card.updated, now: Date()).replacingOccurrences(of: "Yesterday", with: "yesterday"))")
                    .font(.system(size: 14)).foregroundStyle(StudioLook.label)
            }
            Spacer(minLength: 0)
        }
        .padding(.top, 4)
        .accessibilityElement(children: .combine)
    }

    private func kindLine(_ o: StudioOverview) -> String {
        var s = o.card.isShort ? "Short" : "Long video"
        if let v = o.voiceSeconds, v > 0 { s += " \u{00B7} voice \(VideoMath.clock(v))" }
        else if let d = o.card.duration { s += " \u{00B7} \(d)" }
        if o.card.readonly { s += " \u{00B7} read only" }
        return s
    }

    private func stages(_ o: StudioOverview) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(o.stages.enumerated()), id: \.element.key) { i, s in
                if i > 0 { Rectangle().fill(StudioLook.border).frame(height: 1).padding(.leading, 52) }
                Button { open(s.key) } label: {
                    HStack(spacing: 14) {
                        mark(s).frame(width: 24)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(s.name).font(.system(size: 17, weight: .semibold)).foregroundStyle(Theme.title)
                            Text(s.summary).font(.system(size: 14))
                                .foregroundStyle(s.state == "current" ? Theme.blue : StudioLook.label).lineLimit(2)
                        }
                        Spacer(minLength: 6)
                        Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color(hex: 0x55555A))
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(s.state == "current" ? Theme.blue.opacity(0.10) : .clear)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("open-\(s.key)")
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .studioCard()
    }

    @ViewBuilder
    private func mark(_ s: StudioOverview.Stage) -> some View {
        if s.state == "done" {
            Image(systemName: "checkmark.circle.fill").font(.system(size: 20)).foregroundStyle(Theme.green)
        } else if s.busy || s.state == "current" {
            Spinner()
        } else {
            Circle().stroke(Color(hex: 0x48484C), lineWidth: 1.5).frame(width: 18, height: 18)
        }
    }
}

/// NEEDS YOU: the video chat's question with its options as buttons (the first one blue).
struct StudioNeedsCard: View {
    let need: StudioNeed
    let cover: String?
    let store: StudioVideoStore
    @Environment(\.openChat) private var openChat

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Circle().fill(Theme.violet).frame(width: 7, height: 7)
                Text("NEEDS YOU").font(.system(size: 12, weight: .semibold)).kerning(0.6)
            }
            .foregroundStyle(Theme.violetText)
            HStack(alignment: .top, spacing: 12) {
                if let cover {
                    RemoteImage(url: MediaLink.url(cover, base: store.baseURL), fill: true)
                        .frame(width: 64, height: 40)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                Text(need.question).font(.system(size: 16)).foregroundStyle(Theme.title)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if need.answerable, !need.options.isEmpty {
                HStack(spacing: 8) {
                    ForEach(Array(need.options.prefix(3).enumerated()), id: \.element.n) { i, opt in
                        StudioButton(title: opt.label, primary: i == 0, busy: store.busy.contains("answer") && i == 0,
                                     id: "need-\(opt.n)") {
                            Task { _ = await store.answer(need, choice: opt.n) }
                        }
                    }
                }
            } else if let chat = need.chatId {
                StudioButton(title: "Open the chat", primary: true, id: "needOpenChat") { openChat?(chat) }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(StudioLook.needsBG, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(StudioLook.needsBorder, lineWidth: 1))
        .accessibilityIdentifier("needsYou")
    }
}

// MARK: - 04 Brief

/// 04: the brief's fields (edited in place), format and length, the research questions and how far each is.
struct StudioBriefStage: View {
    let store: StudioVideoStore
    let researched: () -> Void
    @State private var topic = ""
    @State private var angle = ""
    @State private var audience = ""
    @State private var length = ""
    @State private var loadedFrom: StudioBrief.Fields?
    @FocusState private var focus: String?

    var body: some View {
        ScrollView {
            if let b = store.brief {
                VStack(alignment: .leading, spacing: 10) {
                    field("TOPIC", "topic", $topic)
                    field("ANGLE", "angle", $angle)
                    field("AUDIENCE", "audience", $audience)
                    HStack(spacing: 8) {
                        chip(b.brief.format == "short" ? "Short" : "Long video", on: true)
                        chip(b.brief.length.isEmpty ? "Length not set" : b.brief.length, on: !b.brief.length.isEmpty)
                    }
                    .padding(.top, 2)
                    questions(b)
                    HStack(spacing: 10) {
                        StudioButton(title: "Interview me", icon: "mic", busy: store.busy.contains("send"), id: "interview",
                                     height: 46) {
                            Task {
                                await store.send("Interview me about this video's brief: ask me one question at a time "
                                                 + "and fill in the brief from my answers.")
                            }
                        }
                        .frame(maxWidth: .infinity)
                        StudioButton(title: "Run research", icon: "search", primary: true,
                                     busy: store.busy.contains("research/start"), id: "runResearch", height: 46) {
                            Task { await store.startResearch() }
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .disabled(store.readonly)
                    .padding(.top, 8)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 30)
            } else {
                ProgressView().frame(maxWidth: .infinity).padding(.vertical, 40)
            }
        }
        .onAppear(perform: fill)
        .onChange(of: store.brief?.brief) { _, _ in fill() }
        .onChange(of: focus) { old, _ in if let old { save(old) } }
    }

    private func fill() {
        guard let f = store.brief?.brief, f != loadedFrom else { return }
        loadedFrom = f
        if focus != "topic" { topic = f.topic }
        if focus != "angle" { angle = f.angle }
        if focus != "audience" { audience = f.audience }
        length = f.length
    }

    private func save(_ key: String) {
        guard let f = store.brief?.brief else { return }
        let now = key == "topic" ? topic : key == "angle" ? angle : audience
        let was = key == "topic" ? f.topic : key == "angle" ? f.angle : f.audience
        guard now != was else { return }
        Task { await store.saveBrief([key: now]) }
    }

    private func field(_ label: String, _ key: String, _ text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.system(size: 12, weight: .semibold)).kerning(0.6).foregroundStyle(StudioLook.label)
            TextField("", text: text, prompt: Text("Not set yet").foregroundStyle(SheetStyle.optional), axis: .vertical)
                .font(.system(size: 17))
                .foregroundStyle(Theme.title)
                .focused($focus, equals: key)
                .disabled(store.readonly)
                .accessibilityIdentifier("brief-\(key)")
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .studioCard(radius: 14)
    }

    private func chip(_ text: String, on: Bool) -> some View {
        Text(text)
            .font(.system(size: 15))
            .foregroundStyle(on ? Theme.rowTitle : Theme.secondary)
            .padding(.horizontal, 14)
            .frame(height: 34)
            .background(Color(hex: 0x1C1C1E), in: Capsule())
            .overlay(Capsule().stroke(StudioLook.chipBorder, lineWidth: 1))
    }

    private func questions(_ b: StudioBrief) -> some View {
        let answered = b.questions.filter { $0.state == "answered" }.count
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("RESEARCH QUESTIONS").font(.system(size: 12, weight: .semibold)).kerning(0.6)
                Spacer()
                Text("\(answered) of \(b.questions.count) answered").font(.system(size: 13))
            }
            .foregroundStyle(StudioLook.label)
            .padding(.horizontal, 4)
            .padding(.top, 14)
            VStack(spacing: 0) {
                ForEach(Array(b.questions.enumerated()), id: \.element.id) { i, q in
                    if i > 0 { Rectangle().fill(StudioLook.border).frame(height: 1).padding(.leading, 44) }
                    HStack(alignment: .top, spacing: 12) {
                        Group {
                            if q.state == "answered" {
                                Image(systemName: "checkmark.circle.fill").font(.system(size: 18)).foregroundStyle(Theme.green)
                            } else if q.state == "researching" {
                                Spinner()
                            } else {
                                Circle().stroke(Color(hex: 0x48484C), lineWidth: 1.5).frame(width: 16, height: 16)
                            }
                        }
                        .frame(width: 20).padding(.top, 2)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(q.text).font(.system(size: 16)).foregroundStyle(Theme.title)
                            if let s = q.summary, !s.isEmpty {
                                Text(s).font(.system(size: 14)).foregroundStyle(StudioLook.label)
                            } else if q.state == "researching" {
                                Text("Researching\(q.thread.map { " \u{00B7} \($0)" } ?? "")")
                                    .font(.system(size: 14)).foregroundStyle(Theme.blue)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(14)
                    .accessibilityElement(children: .combine)
                }
            }
            .studioCard()
        }
    }
}

// MARK: - 05-06 Research

/// 05 and 06: the research board. Facts with their confidence, sources and conflicts (Pin, Reject, Dig deeper);
/// sources, people, the timeline; media with its rights.
struct StudioResearchStage: View {
    let store: StudioVideoStore
    @State private var board = "facts"
    @State private var open: String?
    @State private var rights = "all"
    @State private var viewing: MediaOpen?

    var body: some View {
        VStack(spacing: 0) {
            if let r = store.research {
                boards(r)
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        switch board {
                        case "sources": sources(r)
                        case "people": people(r)
                        case "timeline": timeline(r)
                        case "media": media(r)
                        default: facts(r)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 30)
                }
                .refreshable { await store.load("research") }
            } else {
                ProgressView().frame(maxWidth: .infinity).padding(.vertical, 40)
                Spacer()
            }
        }
        .fullScreenCover(item: $viewing) { MediaViewer(open: $0, base: store.baseURL) }
        .onAppear { if Demo.isOn && Demo.args.contains("-media") { board = "media" } }
    }

    private func boards(_ r: StudioResearch) -> some View {
        let all: [(String, String, Int)] = [("facts", "Facts", r.items.facts.count), ("sources", "Sources", r.items.sources.count),
                                            ("people", "People", r.items.people.count + r.items.places.count),
                                            ("timeline", "Timeline", r.items.events.count), ("media", "Media", r.items.media.count)]
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(all, id: \.0) { key, name, n in
                    StudioChip(text: "\(name) \(n)", on: board == key, id: "board-\(key)") {
                        withAnimation(.snappy(duration: 0.2)) { board = key }
                    }
                }
            }
            .padding(.horizontal, 16)
        }
        .padding(.bottom, 10)
    }

    private func sourceTitle(_ r: StudioResearch, _ id: String) -> String {
        r.items.sources.first { $0.id == id }?.title ?? id
    }

    // facts

    @ViewBuilder
    private func facts(_ r: StudioResearch) -> some View {
        if r.items.facts.isEmpty { StudioNote(text: "No facts yet. Run research from the Brief.") }
        ForEach(r.items.facts) { f in
            let isOpen = open == f.id
            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 6) {
                    Circle().fill(confidenceColor(f.confidence)).frame(width: 8, height: 8)
                    Text(f.confidence.prefix(1).uppercased() + f.confidence.dropFirst())
                        .font(.system(size: 13, weight: .medium)).foregroundStyle(confidenceColor(f.confidence))
                    if f.mark == "pinned" {
                        Text("\u{00B7} Pinned\(f.question.map { " \u{00B7} \($0.uppercased())" } ?? "")")
                            .font(.system(size: 13)).foregroundStyle(StudioLook.label)
                    } else if f.mark == "rejected" {
                        Text("\u{00B7} Rejected").font(.system(size: 13)).foregroundStyle(Theme.red)
                    } else if let q = f.question {
                        Text("\u{00B7} \(q.uppercased())").font(.system(size: 13)).foregroundStyle(StudioLook.label)
                    }
                    Spacer()
                    Text(f.id).font(.system(size: 12)).foregroundStyle(Color(hex: 0x6A6A70))
                }
                Text(f.text).font(.system(size: 17)).foregroundStyle(f.mark == "rejected" ? Theme.secondary : Theme.title)
                    .strikethrough(f.mark == "rejected")
                    .fixedSize(horizontal: false, vertical: true)
                FlowRow(spacing: 6) {
                    ForEach(f.sources, id: \.self) { s in StudioTag(text: sourceTitle(r, s)) }
                    if let c = f.conflicts, !c.isEmpty {
                        StudioTag(text: "Conflict", color: Theme.red, background: Theme.red.opacity(0.14))
                    }
                }
                if isOpen {
                    ForEach(f.conflicts ?? [], id: \.self) { c in
                        HStack(spacing: 10) {
                            Rectangle().fill(Theme.red).frame(width: 3)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(c.text).font(.system(size: 15)).foregroundStyle(Theme.rowTitle)
                                if let s = c.sources, !s.isEmpty {
                                    Text(s.map { sourceTitle(r, $0) }.joined(separator: ", "))
                                        .font(.system(size: 13)).foregroundStyle(StudioLook.label)
                                }
                            }
                        }
                        .fixedSize(horizontal: false, vertical: true)
                    }
                    if let n = f.note, !n.isEmpty {
                        Text(n).font(.system(size: 14)).foregroundStyle(StudioLook.label)
                    }
                    HStack(spacing: 8) {
                        StudioButton(title: f.mark == "pinned" ? "Unpin" : "Pin", icon: "pin",
                                     busy: store.busy.contains("mark-\(f.id)"), id: "pin-\(f.id)") {
                            Task { await store.mark(kind: "facts", id: f.id, mark: f.mark == "pinned" ? nil : "pinned") }
                        }
                        StudioButton(title: f.mark == "rejected" ? "Keep" : "Reject", icon: "x", id: "reject-\(f.id)") {
                            Task { await store.mark(kind: "facts", id: f.id, mark: f.mark == "rejected" ? nil : "rejected") }
                        }
                        StudioButton(title: "Dig deeper", primary: true, busy: store.busy.contains("send"),
                                     id: "dig-\(f.id)") {
                            Task { await store.digDeeper("fact \(f.id) (\"\(f.text)\")") }
                        }
                    }
                    .disabled(store.readonly)
                    .padding(.top, 2)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .studioCard()
            .contentShape(Rectangle())
            .onTapGesture { withAnimation(.snappy(duration: 0.2)) { open = isOpen ? nil : f.id } }
            .accessibilityIdentifier("fact-\(f.id)")
        }
    }

    private func confidenceColor(_ c: String) -> Color {
        c == "high" ? Theme.green : c == "medium" ? Theme.amber : Theme.red
    }

    // sources, people, timeline

    @ViewBuilder
    private func sources(_ r: StudioResearch) -> some View {
        if r.items.sources.isEmpty { StudioNote(text: "No sources yet.") }
        ForEach(r.items.sources) { s in
            row(title: s.title, sub: [s.kind, s.author, s.date, s.credibility.map { "\($0) credibility" }]
                .compactMap { $0 }.joined(separator: " \u{00B7} "), mark: s.mark, note: s.note)
                .contextMenu { markMenu("sources", s.id, s.mark) }
        }
    }

    @ViewBuilder
    private func people(_ r: StudioResearch) -> some View {
        if r.items.people.isEmpty && r.items.places.isEmpty { StudioNote(text: "No people or places yet.") }
        ForEach(r.items.people) { p in
            row(title: p.name, sub: [p.role, [p.born, p.died].compactMap { $0 }.joined(separator: "\u{2013}")]
                .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " \u{00B7} "), mark: p.mark, note: p.note)
        }
        ForEach(r.items.places) { p in
            row(title: p.name, sub: p.where ?? "Place", mark: p.mark, note: p.note)
        }
    }

    @ViewBuilder
    private func timeline(_ r: StudioResearch) -> some View {
        if r.items.events.isEmpty { StudioNote(text: "No timeline yet.") }
        ForEach(r.items.events) { e in
            row(title: e.text, sub: [e.date, e.place].compactMap { $0 }.joined(separator: " \u{00B7} "), mark: e.mark,
                note: e.note)
        }
    }

    private func row(title: String, sub: String, mark: String?, note: String?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top) {
                Text(title).font(.system(size: 16, weight: .medium)).foregroundStyle(Theme.title)
                Spacer()
                if mark == "pinned" { LucideIcon(name: "pin", size: 14).foregroundStyle(Theme.blue) }
            }
            if !sub.isEmpty { Text(sub).font(.system(size: 14)).foregroundStyle(StudioLook.label) }
            if let note, !note.isEmpty { Text(note).font(.system(size: 14)).foregroundStyle(Theme.secondary) }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .studioCard(radius: 14)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func markMenu(_ kind: String, _ id: String, _ mark: String?) -> some View {
        Button(mark == "pinned" ? "Unpin" : "Pin") {
            Task { await store.mark(kind: kind, id: id, mark: mark == "pinned" ? nil : "pinned") }
        }
        Button(mark == "rejected" ? "Keep" : "Reject", role: .destructive) {
            Task { await store.mark(kind: kind, id: id, mark: mark == "rejected" ? nil : "rejected") }
        }
    }

    // media

    @ViewBuilder
    private func media(_ r: StudioResearch) -> some View {
        let filters: [(String, String)] = [("all", "All"), ("cleared", "Cleared"), ("needs-permission", "Needs permission"),
                                           ("reference-only", "Reference")]
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(filters, id: \.0) { key, name in
                    StudioChip(text: name, on: rights == key, small: true, id: "rights-\(key)") { rights = key }
                }
            }
        }
        .scrollClipDisabled()
        let shown = r.items.media.filter { m in
            rights == "all" || (rights == "cleared" ? m.cleared : m.rights == rights)
        }
        if shown.isEmpty { StudioNote(text: "No media here.") }
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
            ForEach(shown) { m in mediaTile(m, r) }
        }
    }

    private func mediaTile(_ m: StudioResearch.Media, _ r: StudioResearch) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Group {
                if let u = m.fileUrl, let url = MediaLink.url(u, base: store.baseURL) {
                    RemoteImage(url: url, fill: true)
                } else {
                    Color(hex: 0x111113).overlay(
                        VStack(spacing: 4) {
                            LucideIcon(name: "image-off", size: 20)
                            Text("No local copy").font(.system(size: 12))
                        }
                        .foregroundStyle(Color(hex: 0x6A6A70)))
                }
            }
            .frame(height: 104)
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .contentShape(Rectangle())
            .onTapGesture {
                if let u = m.fileUrl {
                    viewing = .studio(u, video: m.kind == "video", name: m.title)
                }
            }
            Text(m.title).font(.system(size: 15, weight: .medium)).foregroundStyle(Theme.title).lineLimit(2)
            if let c = m.credit { Text(c).font(.system(size: 13)).foregroundStyle(StudioLook.label).lineLimit(1) }
            rightsBadge(m, r)
        }
        .padding(8)
        .studioCard(radius: 14)
        .opacity(m.mark == "rejected" ? 0.5 : 1)
        .contextMenu { markMenu("media", m.id, m.mark) }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("media-\(m.id)")
    }

    private func rightsBadge(_ m: StudioResearch.Media, _ r: StudioResearch) -> some View {
        let c: Color = m.rights == "public-domain" ? Theme.green : m.rights == "cc-credit" ? Theme.blue
            : m.rights == "needs-permission" ? Theme.amber : Theme.secondary
        return Text(r.rights?[m.rights] ?? m.rights)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(c)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(c.opacity(0.15), in: Capsule())
    }
}

/// A filter or board chip: white when on.
struct StudioChip: View {
    let text: String
    let on: Bool
    var small = false
    var icon: String? = nil
    var id: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let icon { LucideIcon(name: icon, size: 15) }
                Text(text).font(.system(size: small ? 14 : 15, weight: on ? .semibold : .regular))
            }
            .foregroundStyle(on ? Color.black : Theme.rowTitle)
            .padding(.horizontal, small ? 12 : 14)
            .frame(height: small ? 30 : 34)
            .background(on ? Color(hex: 0xF0F0F0) : Color(hex: 0x1C1C1E), in: Capsule())
            .overlay(Capsule().stroke(on ? .clear : StudioLook.chipBorder, lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
        .accessibilityIdentifier(id ?? text)
    }
}

/// Small views laid out left to right, wrapping onto new lines.
struct FlowRow: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 320
        var x: CGFloat = 0, y: CGFloat = 0, line: CGFloat = 0, widest: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > 0 && x + s.width > width { y += line + spacing; x = 0; line = 0 }
            x += s.width + spacing
            widest = max(widest, x - spacing)
            line = max(line, s.height)
        }
        return CGSize(width: min(widest, width), height: y + line)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, line: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > bounds.minX && x + s.width > bounds.maxX { y += line + spacing; x = bounds.minX; line = 0 }
            v.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(s))
            x += s.width + spacing
            line = max(line, s.height)
        }
    }
}

extension MediaOpen {
    /// a Studio picture or video full screen, on its own
    @MainActor
    static func studio(_ link: String, video: Bool, name: String, poster: String? = nil) -> MediaOpen {
        let item = MDItem(kind: video ? "video" : "image", url: link, name: name, poster: poster)
        return video ? MediaOpen(item: item) : .picture(item, id: nil, source: nil)
    }
}
