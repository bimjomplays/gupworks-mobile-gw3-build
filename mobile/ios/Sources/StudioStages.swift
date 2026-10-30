import SwiftUI

// Voice, Visuals and the final cut on the phone (a180, mockups 10-13): takes line by line with approve and redo,
// shot drafts and the GPU's render queue, and the final cut to watch with notes at a moment and its checks.

// MARK: - 10-11 Voice

/// 10: the ElevenLabs credits, each line's takes (play, approve, redo) and generating what has no take yet.
struct StudioVoiceStage: View {
    let store: StudioVideoStore
    @State private var active: String?
    @State private var playingTake: [String: Int] = [:]
    @State private var redoing: RedoLine?
    private let audio = AudioPlayback.shared

    var body: some View {
        ScrollView {
            if let v = store.voice {
                VStack(alignment: .leading, spacing: 12) {
                    credits(v)
                    jobs(v)
                    ForEach(chapters(v), id: \.chapter) { ch in
                        let lines = v.lines.filter { ($0.chapter ?? 0) == ch.chapter }
                        HStack {
                            Text(ch.title).font(.system(size: 17, weight: .semibold)).foregroundStyle(Theme.title)
                            Spacer()
                            Text("\(lines.filter { $0.approved != nil }.count) of \(lines.count) approved")
                                .font(.system(size: 14)).foregroundStyle(StudioLook.label)
                        }
                        .padding(.horizontal, 4)
                        .padding(.top, 6)
                        VStack(spacing: 0) {
                            ForEach(Array(lines.enumerated()), id: \.element.id) { i, l in
                                if i > 0 { Rectangle().fill(StudioLook.border).frame(height: 1) }
                                row(l, v)
                            }
                        }
                        .studioCard()
                        let missing = lines.filter { $0.takes.isEmpty }
                        if !missing.isEmpty && !(v.readonly ?? false) {
                            generateRest(ch, missing)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 30)
            } else {
                ProgressView().frame(maxWidth: .infinity).padding(.vertical, 40)
            }
        }
        .refreshable { await store.load("voice") }
        .sheet(item: $redoing) { r in StudioRedoSheet(store: store, redo: r) }
        .onDisappear { audio.pause() }
        .onAppear {
            if Demo.isOn, active == nil, let l = store.voice?.lines.first(where: { $0.approved == nil && !$0.takes.isEmpty }) {
                active = l.id
                if Demo.args.contains("-redo"), let t = l.takes.last {
                    redoing = RedoLine(line: l.id, text: l.text, take: t.n, direction: t.direction ?? "")
                }
            }
        }
    }

    private func chapters(_ v: StudioVoice) -> [StudioChapter] {
        v.chapters.isEmpty ? [StudioChapter(chapter: 0, title: "Script", first: nil)] : v.chapters
    }

    private func credits(_ v: StudioVoice) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                if let left = v.credits?.left {
                    Text("\(left.formatted()) credits left").font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Theme.title)
                } else {
                    Text("Credits").font(.system(size: 17, weight: .semibold)).foregroundStyle(Theme.title)
                }
                Spacer()
                Text([v.config?.name, v.config?.model].compactMap { $0 }.joined(separator: " \u{00B7} "))
                    .font(.system(size: 14)).foregroundStyle(StudioLook.label)
            }
            if let c = v.credits, let used = c.used, let limit = c.limit, limit > 0 {
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color(hex: 0x2A2A2E))
                        Capsule().fill(Theme.violet).frame(width: g.size.width * min(1, Double(limit - used) / Double(limit)))
                    }
                }
                .frame(height: 5)
            }
            if let e = v.creditsError, !e.isEmpty {
                Text(e).font(.system(size: 13)).foregroundStyle(Theme.amber)
            }
            if let s = v.trackSeconds, s > 0 {
                Text("\(v.approved ?? 0) approved \u{00B7} \(VideoMath.clock(s)) of voice")
                    .font(.system(size: 13)).foregroundStyle(StudioLook.label)
            }
        }
        .padding(14)
        .studioCard()
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("credits")
    }

    @ViewBuilder
    private func jobs(_ v: StudioVoice) -> some View {
        ForEach(v.jobs.filter { $0.status == "running" || $0.status == "queued" }) { j in
            HStack(spacing: 10) {
                Spinner()
                Text("Making takes \u{00B7} \(j.done?.count ?? 0) of \(j.lines.count)\(j.current.map { " \u{00B7} line \($0)" } ?? "")")
                    .font(.system(size: 15)).foregroundStyle(Theme.blue)
                Spacer()
            }
            .padding(12)
            .studioCard(radius: 14)
        }
    }

    private func take(_ l: StudioVoice.Line) -> StudioVoice.Take? {
        let n = playingTake[l.id] ?? l.approved ?? l.takes.last?.n
        return l.takes.first { $0.n == n } ?? l.takes.last
    }

    private func row(_ l: StudioVoice.Line, _ v: StudioVoice) -> some View {
        let isActive = active == l.id
        let t = take(l)
        return VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .top, spacing: 10) {
                Text(l.id).font(.system(size: 12)).monospacedDigit().foregroundStyle(Color(hex: 0x6A6A70))
                    .frame(width: 26, alignment: .leading).padding(.top, 3)
                Text(l.text).font(.system(size: 17, design: .serif)).foregroundStyle(Theme.title)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
            .onTapGesture { withAnimation(.snappy(duration: 0.2)) { active = isActive ? nil : l.id } }
            HStack(spacing: 6) {
                if l.takes.isEmpty {
                    Text("no take yet").font(.system(size: 14)).foregroundStyle(StudioLook.label)
                    Spacer()
                    if !(v.readonly ?? false) {
                        StudioButton(title: "Generate \u{00B7} ~\(l.chars ?? l.text.count) cr",
                                     busy: store.busy.contains("redo-\(l.id)"), id: "generate-\(l.id)", height: 32) {
                            Task { _ = await store.redo(line: l.id, from: nil, direction: "") }
                        }
                    }
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(l.takes) { tk in takeChip(l, tk, on: tk.n == t?.n) }
                        }
                    }
                    if let a = l.approved {
                        Text(l.takes.count > 1 ? "Approved #\(a)" : "Approved")
                            .font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.green)
                            .padding(.horizontal, 9).padding(.vertical, 4)
                            .background(Theme.green.opacity(0.15), in: Capsule())
                    }
                }
            }
            .padding(.leading, 36)
            if isActive, let t, !l.takes.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    progress(t)
                    if let d = t.direction, !d.isEmpty {
                        Text("Direction: \(d)").font(.system(size: 14)).foregroundStyle(StudioLook.label)
                    }
                    if t.stale == true {
                        Text("The line changed since this take.").font(.system(size: 14)).foregroundStyle(Theme.amber)
                    }
                    if !(v.readonly ?? false) {
                        HStack(spacing: 8) {
                            if l.approved != t.n {
                                StudioButton(title: "Approve #\(t.n)", icon: "check", primary: true,
                                             busy: store.busy.contains("take-\(l.id)"), id: "approve-\(l.id)", height: 34) {
                                    Task { await store.approve(line: l.id, take: t.n) }
                                }
                            }
                            StudioButton(title: "Redo", icon: "rotate-ccw", busy: store.busy.contains("redo-\(l.id)"),
                                         id: "redo-\(l.id)", height: 34) {
                                redoing = RedoLine(line: l.id, text: l.text, take: t.n, direction: t.direction ?? "")
                            }
                        }
                    }
                }
                .padding(.leading, 36)
            }
        }
        .padding(12)
        .background(isActive ? Color.white.opacity(0.03) : .clear)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("voice-\(l.id)")
    }

    private func takeChip(_ l: StudioVoice.Line, _ tk: StudioVoice.Take, on: Bool) -> some View {
        let url = MediaLink.url(tk.fileUrl, base: store.baseURL)
        let playing = audio.isPlaying(url)
        return Button {
            playingTake[l.id] = tk.n
            withAnimation(.snappy(duration: 0.2)) { active = l.id }
            if let url { audio.toggle(url) }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: playing ? "pause.fill" : "play.fill").font(.system(size: 10))
                Text("#\(tk.n)\(tk.seconds.map { String(format: " %.1fs", $0) } ?? "")")
                    .font(.system(size: 13, weight: .medium)).monospacedDigit()
            }
            .foregroundStyle(on ? Color.black : Theme.rowTitle)
            .padding(.horizontal, 9)
            .frame(height: 28)
            .background(on ? Color(hex: 0xF0F0F0) : Color(hex: 0x26262A), in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(url == nil)
        .accessibilityLabel("Take \(tk.n)\(playing ? ", playing" : "")")
        .accessibilityIdentifier("take-\(l.id)-\(tk.n)")
    }

    /// The take's words as bars, lit up to where it plays.
    private func progress(_ t: StudioVoice.Take) -> some View {
        let url = MediaLink.url(t.fileUrl, base: store.baseURL)
        let seconds = t.seconds ?? max(audio.duration, 1)
        let at = audio.place(of: url)
        let bars = 48
        return HStack(spacing: 2) {
            ForEach(0..<bars, id: \.self) { i in
                let h = 6 + 16 * abs(sin(Double(i) * 1.7 + Double(t.n)))
                Capsule()
                    .fill(Double(i) / Double(bars) < at / seconds ? Theme.blue : Color(hex: 0x3A3A3E))
                    .frame(width: 3, height: h)
            }
        }
        .frame(height: 24)
        .accessibilityHidden(true)
    }

    private func generateRest(_ ch: StudioChapter, _ missing: [StudioVoice.Line]) -> some View {
        let cr = missing.reduce(0) { $0 + ($1.chars ?? $1.text.count) }
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Generate the rest of \(ch.title)").font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.title)
                Text("\(Format.plural(missing.count, "line")) \u{00B7} ~\(cr.formatted()) credits")
                    .font(.system(size: 14)).foregroundStyle(StudioLook.label)
            }
            Spacer()
            StudioButton(title: "Generate", primary: true, busy: store.busy.contains("generate"), id: "generateRest") {
                Task { await store.generate(chapter: ch.chapter) }
            }
        }
        .padding(14)
        .studioCard()
    }
}

/// The line a redo is for.
struct RedoLine: Identifiable {
    let line: String
    let text: String
    let take: Int
    var direction: String
    var id: String { line }
}

/// 11: a new take of one line with a direction in plain words (quick picks add to it); or ask the chat about it.
struct StudioRedoSheet: View {
    let store: StudioVideoStore
    let redo: RedoLine
    @Environment(\.dismiss) private var dismiss
    @State private var direction = ""
    @State private var working = false
    private static let picks = ["Slower", "Faster", "Whisper", "Stress a word", "Pause before\u{2026}", "Steadier",
                                "More emotion"]

    private var sends: String {
        let d = direction.trimmingCharacters(in: .whitespacesAndNewlines)
        return "Take \(redo.take + 1) of line \(redo.line), from take \(redo.take)"
            + (d.isEmpty ? ", read again as it is." : ", read: \(d)")
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .top, spacing: 10) {
                        Text(redo.line).font(.system(size: 12)).foregroundStyle(Color(hex: 0x6A6A70)).padding(.top, 4)
                        Text(redo.text).font(.system(size: 18, design: .serif)).foregroundStyle(Theme.title)
                    }
                    Text("From take #\(redo.take)")
                        .font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.rowTitle)
                        .padding(.horizontal, 9).padding(.vertical, 4)
                        .background(Color(hex: 0x2C2C30), in: Capsule())
                        .padding(.top, 10)
                    SheetLabel(text: "Direction")
                    TextField("", text: $direction, prompt: Text("Slower, stress \u{201C}dark\u{201D}").foregroundStyle(SheetStyle.optional),
                              axis: .vertical)
                        .lineLimit(2...4)
                        .font(.system(size: 17))
                        .foregroundStyle(Theme.rowTitle)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 15)
                        .background(SheetStyle.field, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                        .accessibilityIdentifier("redoDirection")
                    FlowRow(spacing: 8) {
                        ForEach(Self.picks, id: \.self) { p in
                            StudioChip(text: p, on: false, small: true, id: "pick-\(p)") {
                                let word = p.replacingOccurrences(of: "\u{2026}", with: "").lowercased()
                                direction = direction.isEmpty ? word : direction + ", " + word
                            }
                        }
                    }
                    .padding(.top, 12)
                    SheetLabel(text: "What it sends")
                    Text(sends)
                        .font(.system(size: 15))
                        .foregroundStyle(Theme.rowTitle)
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(SheetStyle.field, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    HStack(spacing: 10) {
                        StudioButton(title: "Ask the chat", icon: "message-circle", busy: store.busy.contains("send"),
                                     id: "redoAsk", height: 46) {
                            Task {
                                if await store.send("About the voice take #\(redo.take) of line \(redo.line) (\"\(redo.text)\"): "
                                                    + (direction.isEmpty ? "how should it be read?" : direction)) {
                                    dismiss()
                                }
                            }
                        }
                        .frame(maxWidth: .infinity)
                        StudioButton(title: "Make take \(redo.take + 1)", primary: true, busy: working, id: "makeTake",
                                     height: 46) {
                            working = true
                            Task {
                                let ok = await store.redo(line: redo.line, from: redo.take, direction: direction)
                                working = false
                                if ok { dismiss() }
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .padding(.top, 20)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
            }
            .background(SheetStyle.background)
            .navigationTitle("Redo line \(redo.line)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }.accessibilityLabel("Close")
                }
            }
        }
        .presentationDetents([.large])
        .presentationBackground(SheetStyle.background)
        .onAppear { direction = redo.direction }
    }
}

// MARK: - 12 Visuals

/// 12: the render running on the GPU and what waits after it, then every shot with its draft or render
/// (approve or redraft the drafts).
struct StudioVisualsStage: View {
    let store: StudioVideoStore
    @State private var viewing: MediaOpen?
    @State private var redrafting: String?
    @State private var direction = ""

    var body: some View {
        ScrollView {
            if let v = store.visuals {
                VStack(alignment: .leading, spacing: 12) {
                    renders(v)
                    drafts(v)
                    HStack(spacing: 8) {
                        let chapter = v.chapters?.first?.title
                        Text([chapter, Format.plural(v.shots.count, "shot")].compactMap { $0 }.joined(separator: " \u{00B7} "))
                            .font(.system(size: 15)).foregroundStyle(Theme.rowTitle)
                            .padding(.horizontal, 14).frame(height: 34)
                            .background(Color(hex: 0x1C1C1E), in: Capsule())
                            .overlay(Capsule().stroke(StudioLook.chipBorder, lineWidth: 1))
                        Spacer()
                        let ready = v.shots.filter { $0.status == "approved" }.count
                        if ready > 0 && !(v.readonly ?? false) {
                            StudioButton(title: "Render \(ready) approved", primary: true, busy: store.busy.contains("render"),
                                         id: "renderApproved") {
                                Task { await store.renderApproved() }
                            }
                        }
                    }
                    VStack(spacing: 0) {
                        ForEach(Array(v.shots.enumerated()), id: \.element.id) { i, s in
                            if i > 0 { Rectangle().fill(StudioLook.border).frame(height: 1) }
                            shot(s, v)
                        }
                    }
                    .studioCard()
                    if v.shots.isEmpty { StudioNote(text: "No shots yet; the video chat plans them from the script.") }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 30)
            } else {
                ProgressView().frame(maxWidth: .infinity).padding(.vertical, 40)
            }
        }
        .refreshable { await store.load("visuals") }
        .fullScreenCover(item: $viewing) { MediaViewer(open: $0, base: store.baseURL) }
        .alert("Redraft \(redrafting ?? "")", isPresented: Binding(get: { redrafting != nil },
                                                                   set: { if !$0 { redrafting = nil } })) {
            TextField("What to change", text: $direction)
            Button("Cancel", role: .cancel) { direction = "" }
            Button("Redraft") {
                let shot = redrafting ?? "", d = direction
                direction = ""
                Task { await store.redraft(shot: shot, direction: d) }
            }
        }
    }

    @ViewBuilder
    private func renders(_ v: StudioVisuals) -> some View {
        let mine = v.renders.filter { $0.videoId == nil || $0.videoId == store.videoId }
        if let r = mine.first(where: { $0.status == "running" }) {
            let queued = v.renders.filter { $0.status == "queued" }.count
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    Spinner()
                    Text("Rendering \(r.shot.map { "shot \($0.replacingOccurrences(of: "sh", with: ""))" } ?? "a shot")")
                        .font(.system(size: 17, weight: .semibold)).foregroundStyle(Theme.title)
                    Spacer()
                    if let eta = r.eta {
                        Text("\(max(1, Int(eta / 60))) min left").font(.system(size: 14)).foregroundStyle(Theme.blue)
                    }
                }
                if let f = r.frames, f > 0 {
                    ProgressView(value: Double(r.done ?? 0) / Double(f)).tint(Theme.blue)
                }
                Text([r.frames.map { "frame \(r.done ?? 0) of \($0)" }, queued > 0 ? "\(queued) more queued" : nil,
                      "the GPU is shared by every video"].compactMap { $0 }.joined(separator: " \u{00B7} "))
                    .font(.system(size: 13)).foregroundStyle(StudioLook.label)
            }
            .padding(14)
            .studioCard()
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("renderCard")
        } else if let q = mine.first(where: { $0.status == "queued" }) {
            HStack(spacing: 10) {
                LucideIcon(name: "clock", size: 18).foregroundStyle(Theme.blue)
                Text("Shot \(q.shot ?? "") is queued\(q.startsIn.map { "; starts in about \(max(1, Int($0 / 60))) min" } ?? "")")
                    .font(.system(size: 15)).foregroundStyle(Theme.rowTitle)
                Spacer()
            }
            .padding(14)
            .studioCard()
        }
        ForEach(mine.filter { $0.status == "failed" }) { r in
            Text("Shot \(r.shot ?? "") didn't render: \(r.error ?? "it failed")")
                .font(.system(size: 14)).foregroundStyle(Theme.red)
                .padding(12).frame(maxWidth: .infinity, alignment: .leading).studioCard(radius: 14)
        }
    }

    @ViewBuilder
    private func drafts(_ v: StudioVisuals) -> some View {
        ForEach(v.drafts.filter { $0.status == "running" || $0.status == "queued" }) { d in
            HStack(spacing: 10) {
                Spinner()
                Text("Drafting \(Format.plural(d.shots.count, "shot"))\(d.current.map { " \u{00B7} \($0)" } ?? "")")
                    .font(.system(size: 15)).foregroundStyle(Theme.blue)
                Spacer()
            }
            .padding(12)
            .studioCard(radius: 14)
        }
    }

    private func shot(_ s: StudioVisuals.Shot, _ v: StudioVisuals) -> some View {
        let picture = s.status == "rendered" ? (s.renderPoster ?? s.draftUrl) : s.draftUrl
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                Group {
                    if let p = picture {
                        RemoteImage(url: MediaLink.url(p, base: store.baseURL), fill: true)
                    } else {
                        Color(hex: 0x111113).overlay(LucideIcon(name: "image", size: 18).foregroundStyle(Color(hex: 0x55555A)))
                    }
                }
                .frame(width: 96, height: 54)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay {
                    if s.status == "rendered", s.renderUrl != nil {
                        Image(systemName: "play.fill").font(.system(size: 14)).foregroundStyle(.white)
                            .frame(width: 28, height: 28).background(.black.opacity(0.55), in: Circle())
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture { view(s) }
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text("\(s.id)\(s.start.map { " \u{00B7} \(VideoMath.clock($0))" } ?? "")")
                            .font(.system(size: 14, weight: .semibold)).monospacedDigit().foregroundStyle(Theme.title)
                        badge(s)
                    }
                    if let d = s.description {
                        Text(d).font(.system(size: 14)).foregroundStyle(Theme.rowTitle).lineLimit(3)
                    }
                }
                Spacer(minLength: 0)
            }
            if s.status == "draft" && !(v.readonly ?? false) {
                HStack(spacing: 8) {
                    StudioButton(title: "Approve", icon: "check", primary: true, busy: store.busy.contains("shot-\(s.id)"),
                                 id: "approveShot-\(s.id)", height: 32) {
                        Task { await store.approve(shot: s.id) }
                    }
                    StudioButton(title: "Redo", icon: "rotate-ccw", id: "redoShot-\(s.id)", height: 32) { redrafting = s.id }
                }
                .padding(.leading, 108)
            }
        }
        .padding(12)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("shot-\(s.id)")
    }

    private func view(_ s: StudioVisuals.Shot) {
        if s.status == "rendered", let r = s.renderUrl {
            viewing = .studio(r, video: true, name: s.id, poster: s.renderPoster)
        } else if let d = s.draftUrl {
            viewing = .studio(d, video: false, name: s.id)
        }
    }

    private func badge(_ s: StudioVisuals.Shot) -> some View {
        let rendering = store.visuals?.renders.first { $0.shot == s.id && $0.status == "running" }
        let queued = store.visuals?.renders.contains { $0.shot == s.id && $0.status == "queued" } ?? false
        let (text, color): (String, Color) = {
            if let r = rendering, let f = r.frames, f > 0 { return ("Rendering \(Int(100 * Double(r.done ?? 0) / Double(f)))%", Theme.blue) }
            switch s.status {
            case "rendered": return ("Rendered", Theme.green)
            case "approved": return (queued ? "Approved \u{00B7} queued" : "Approved", Theme.blue)
            case "rendering": return ("Rendering", Theme.blue)
            default: return ("Draft \(s.drafts?.count ?? 1)", Theme.amber)
            }
        }()
        return Text(text).font(.system(size: 12, weight: .medium)).foregroundStyle(color)
            .padding(.horizontal, 7).padding(.vertical, 2)
            .background(color.opacity(0.15), in: Capsule())
    }
}

// MARK: - 13 Final cut

/// 13: the final cut playing here (HLS from the PC), with its chapters and your notes on the scrubber; a note at the
/// moment it is at, Looks good, the notes sent to the chat and the checks that ran after the render.
struct StudioFinishStage: View {
    let store: StudioVideoStore
    @State private var playback: VideoPlayback?
    @State private var noting: Double?
    @State private var noteText = ""
    @State private var full: MediaOpen?

    var body: some View {
        ScrollView {
            if let f = store.finish {
                VStack(alignment: .leading, spacing: 14) {
                    if let final = f.final, let link = final.fileUrl {
                        video(f, link: link, poster: final.filePoster)
                        info(f, final)
                        notes(f)
                    } else {
                        StudioNote(text: f.reason?.isEmpty == false ? f.reason! : "No final cut yet. It's rendered after the Edit.")
                    }
                    checks(f)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 30)
            } else {
                ProgressView().frame(maxWidth: .infinity).padding(.vertical, 40)
            }
        }
        .refreshable { await store.load("finish") }
        .onDisappear { playback?.stop(); playback = nil }
        .fullScreenCover(item: $full) { MediaViewer(open: $0, base: store.baseURL) }
        .alert("Note at \(VideoMath.clock(noting ?? 0))", isPresented: Binding(get: { noting != nil },
                                                                               set: { if !$0 { noting = nil } })) {
            TextField("What to change here", text: $noteText)
            Button("Cancel", role: .cancel) { noteText = "" }
            Button("Send") {
                let at = noting ?? 0, text = noteText
                noteText = ""
                Task { _ = await store.addNote(at: at, text: text) }
            }
        }
    }

    private func length(_ f: StudioFinish) -> Double {
        if let p = playback, p.duration > 0 { return p.duration }
        return f.duration ?? 0
    }

    private func video(_ f: StudioFinish, link: String, poster: String?) -> some View {
        Color.black
            .aspectRatio(16 / 9, contentMode: .fit)
            .frame(maxWidth: .infinity)
            .overlay(alignment: .bottom) { videoContent(f, link: link, poster: poster) }
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("finalCut")
    }

    private func videoContent(_ f: StudioFinish, link: String, poster: String?) -> some View {
        ZStack(alignment: .bottom) {
            if let p = playback {
                StudioPlayerSurface(view: p.surface)
                if p.waiting { ProgressView().tint(.white) }
            } else {
                RemoteImage(url: MediaLink.url(poster, base: store.baseURL), fill: true)
                Button {
                    let p = VideoPlayback(item: MDItem(kind: "video", url: link, name: "Final cut \(store.videoId)",
                                                       poster: poster), base: store.baseURL)
                    playback = p
                    p.start()
                } label: {
                    Image(systemName: "play.fill").font(.system(size: 26)).foregroundStyle(.white)
                        .frame(width: 64, height: 64).background(.black.opacity(0.55), in: Circle())
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityLabel("Play the final cut")
                .accessibilityIdentifier("playFinal")
            }
            scrubber(f, link: link, poster: poster)
        }
    }

    private func scrubber(_ f: StudioFinish, link: String, poster: String?) -> some View {
        let total = length(f)
        let t = playback?.time ?? 0
        return HStack(spacing: 10) {
            Button {
                if let p = playback { p.toggle() } else {
                    let p = VideoPlayback(item: MDItem(kind: "video", url: link, name: "Final cut \(store.videoId)",
                                                       poster: poster), base: store.baseURL)
                    playback = p
                    p.start()
                }
            } label: {
                Image(systemName: playback?.playing == true ? "pause.fill" : "play.fill")
                    .font(.system(size: 15)).foregroundStyle(.white).frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(playback?.playing == true ? "Pause" : "Play")
            Text(VideoMath.clock(t)).font(.system(size: 12)).monospacedDigit().foregroundStyle(.white)
            GeometryReader { g in
                let w = g.size.width
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.25)).frame(height: 4)
                    Capsule().fill(Color.white).frame(width: total > 0 ? w * min(1, t / total) : 0, height: 4)
                    ForEach(f.chapters.dropFirst(), id: \.start) { c in
                        Rectangle().fill(Color.black.opacity(0.8)).frame(width: 2, height: 8)
                            .offset(x: total > 0 ? w * c.start / total - 1 : 0)
                    }
                    ForEach(f.notes?.notes ?? []) { n in
                        Circle().fill(Theme.violet).frame(width: 8, height: 8)
                            .offset(x: total > 0 ? w * min(1, n.at / total) - 4 : 0, y: -9)
                    }
                }
                .frame(height: 24)
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onChanged { v in
                    guard total > 0, let p = playback else { return }
                    p.seek(to: max(0, min(total, total * v.location.x / w)), exact: false)
                }.onEnded { v in
                    guard total > 0, let p = playback else { return }
                    p.seek(to: max(0, min(total, total * v.location.x / w)), exact: true)
                })
            }
            .frame(height: 24)
            Text(VideoMath.clock(total)).font(.system(size: 12)).monospacedDigit().foregroundStyle(.white)
            Button {
                playback?.stop()
                playback = nil
                full = .studio(link, video: true, name: "Final cut", poster: poster)
            } label: {
                Image(systemName: "arrow.up.left.and.arrow.down.right").font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white).frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Full screen")
        }
        .padding(.horizontal, 10)
        .frame(height: 40)
        .glassEffect(.regular, in: .capsule)
        .padding(8)
    }

    private func info(_ f: StudioFinish, _ final: StudioFinish.Final) -> some View {
        let at = playback?.time ?? 0
        return VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Final cut").font(.system(size: 20, weight: .bold)).foregroundStyle(Theme.title)
                Text([f.duration.map { VideoMath.clock($0) }, final.at.map { "rendered \(Format.ago($0, now: Date()))" }]
                    .compactMap { $0 }.joined(separator: " \u{00B7} "))
                    .font(.system(size: 14)).foregroundStyle(StudioLook.label)
            }
            if !(f.readonly ?? false) {
                HStack(spacing: 10) {
                    StudioButton(title: "Note at \(VideoMath.clock(at))", icon: "message-square-plus",
                                 busy: store.busy.contains("note"), id: "noteAt", height: 44) {
                        playback?.player.pause()
                        noting = at
                    }
                    .frame(maxWidth: .infinity)
                    StudioButton(title: f.notes?.ok != nil ? "Sent: looks good" : "Looks good", icon: "thumbs-up",
                                 primary: true, busy: store.busy.contains("ok"), id: "looksGood", height: 44) {
                        Task { await store.looksGood() }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }

    @ViewBuilder
    private func notes(_ f: StudioFinish) -> some View {
        let all = f.notes?.notes ?? []
        if !all.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                Text("Your notes \u{00B7} \(all.count) sent to the chat")
                    .font(.system(size: 14, weight: .semibold)).foregroundStyle(StudioLook.label)
                    .padding(.bottom, 6)
                ForEach(all) { n in
                    HStack(alignment: .top, spacing: 12) {
                        Button { playback?.seek(to: n.at, exact: true) } label: {
                            Text(VideoMath.clock(n.at)).font(.system(size: 15, weight: .semibold)).monospacedDigit()
                                .foregroundStyle(Theme.violetText)
                        }
                        .buttonStyle(.plain)
                        Text(n.text).font(.system(size: 15)).foregroundStyle(Theme.rowTitle)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 7)
                }
            }
            .padding(14)
            .studioCard()
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("finalNotes")
        }
    }

    @ViewBuilder
    private func checks(_ f: StudioFinish) -> some View {
        if let c = f.checks, !c.items.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                Text("Checks \u{00B7} ran after the render")
                    .font(.system(size: 14, weight: .semibold)).foregroundStyle(StudioLook.label)
                    .padding(.bottom, 6)
                ForEach(c.items) { i in
                    HStack(spacing: 10) {
                        Image(systemName: i.ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .font(.system(size: 17)).foregroundStyle(i.ok ? Theme.green : Theme.red)
                        Text(i.name).font(.system(size: 15)).foregroundStyle(Theme.title)
                        Spacer()
                        if let d = i.detail { Text(d).font(.system(size: 14)).foregroundStyle(StudioLook.label).lineLimit(1) }
                    }
                    .padding(.vertical, 7)
                    .accessibilityElement(children: .combine)
                }
            }
            .padding(14)
            .studioCard()
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("finalChecks")
        }
    }
}

/// The player's own layer, drawn inline.
struct StudioPlayerSurface: UIViewRepresentable {
    let view: PlayerLayerView
    func makeUIView(context: Context) -> PlayerLayerView { view }
    func updateUIView(_ v: PlayerLayerView, context: Context) {}
}
