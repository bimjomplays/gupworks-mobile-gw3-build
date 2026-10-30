import SwiftUI
import AVFoundation

/// The panels that come up over the timeline's lower part (19-25): each edits the same timeline through the store,
/// so its changes undo like any other.
struct StudioEditSheet: View {
    let sheet: StudioSheet
    @Bindable var store: StudioEditStore
    let cache: StudioMediaCache
    let player: StudioPlayer
    let thumbs: StudioThumbs
    var openStage: ((String) -> Void)?
    var close: () -> Void
    var open: (StudioSheet) -> Void

    var body: some View {
        Group {
            switch sheet {
            case .voice(let id): StudioVoiceSheet(id: id, store: store, openStage: openStage, close: close)
            case .text(let id): StudioTextSheet(id: id, store: store, close: close)
            case .transition(let id): StudioTransitionSheet(id: id, store: store, player: player, thumbs: thumbs, close: close)
            case .kenburns(let id): StudioKenBurnsSheet(id: id, store: store, close: close)
            case .sound(let id): StudioSoundClipSheet(id: id, store: store, close: close)
            case .replace(let id): StudioReplaceSheet(id: id, store: store, thumbs: thumbs, close: close)
            case .photo: StudioPhotoSheet(store: store, player: player, thumbs: thumbs, close: close)
            case .shots: StudioShotsSheet(store: store, player: player, thumbs: thumbs, close: close)
            case .mix: StudioMixSheet(store: store, cache: cache, player: player, close: close)
            case .sounds: StudioSoundsSheet(store: store, player: player, close: close)
            }
        }
    }
}

// MARK: shared parts

/// A panel: its grabber, a title with a grey note, the tick that closes it, and its rows.
struct StudioPanel<Content: View>: View {
    let title: String
    var note: String?
    let id: String
    var close: () -> Void
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Capsule().fill(Color(hex: 0x48484A)).frame(width: 36, height: 5)
                .frame(maxWidth: .infinity).padding(.top, 8)
            HStack(alignment: .center, spacing: 10) {
                Text(title).font(.system(size: 19, weight: .semibold)).foregroundStyle(Theme.title)
                if let note {
                    Text(note).font(.system(size: 14)).foregroundStyle(Theme.secondary).lineLimit(1)
                }
                Spacer(minLength: 8)
                Button(action: close) {
                    LucideIcon(name: "check", size: 20).foregroundStyle(Color(hex: 0x555555))
                        .frame(width: 40, height: 40)
                        .background(Color(hex: 0xE8E8E8), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Done")
                .accessibilityIdentifier("sheetDone")
            }
            content()
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(hex: 0x1C1C1E), in: UnevenRoundedRectangle(topLeadingRadius: 26, topTrailingRadius: 26))
        .contentShape(Rectangle())
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(id)
    }
}

/// A slider row: its icon and name, the value on the right. It commits when the finger lifts, so a drag is one
/// step in the history.
struct StudioSlider: View {
    let icon: String
    let label: String
    let value: Double
    let range: ClosedRange<Double>
    var tick: Double?
    let text: (Double) -> String
    let commit: (Double) -> Void
    @State private var shown: Double?

    var body: some View {
        HStack(spacing: 10) {
            LucideIcon(name: icon, size: 17).foregroundStyle(Theme.secondary)
            Text(label).font(.system(size: 16)).foregroundStyle(Theme.title).frame(width: 86, alignment: .leading)
            Slider(value: Binding(get: { shown ?? value }, set: { shown = $0 }), in: range, onEditingChanged: { editing in
                if !editing, let v = shown { commit(v); shown = nil }
            })
            .tint(.white)
            .overlay(alignment: .leading) {
                if let tick {
                    GeometryReader { g in
                        Rectangle().fill(Color(hex: 0x666666)).frame(width: 1.5, height: 14)
                            .offset(x: g.size.width * (tick - range.lowerBound) / (range.upperBound - range.lowerBound),
                                    y: g.size.height / 2 - 7)
                    }
                    .allowsHitTesting(false)
                }
            }
            Text(text(shown ?? value)).font(.system(size: 15).monospacedDigit()).foregroundStyle(Theme.title)
                .frame(width: 78, alignment: .trailing)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(label)
        .accessibilityValue(text(shown ?? value))
    }
}

/// A segmented pick: the chosen one on a light pill.
struct StudioSegments: View {
    let items: [(id: String, label: String)]
    let chosen: String
    var disabled: Set<String> = []
    let pick: (String) -> Void

    var body: some View {
        HStack(spacing: 0) {
            ForEach(items.indices, id: \.self) { k in
                let i = items[k]
                Button { pick(i.id) } label: {
                    Text(i.label).font(.system(size: 15, weight: i.id == chosen ? .semibold : .regular))
                        .foregroundStyle(i.id == chosen ? Color.black : disabled.contains(i.id) ? Theme.secondary.opacity(0.5) : Theme.title)
                        .frame(maxWidth: .infinity).frame(height: 36)
                        .background(i.id == chosen ? Color(hex: 0xEDEDED) : .clear, in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(disabled.contains(i.id))
                .accessibilityIdentifier("seg-\(i.id)")
                .accessibilityAddTraits(i.id == chosen ? .isSelected : [])
            }
        }
        .padding(3)
        .background(Color(hex: 0x2C2C2E), in: Capsule())
    }
}

/// A row with an icon in a circle, two lines and something on the right.
struct StudioIconRow<Trailing: View>: View {
    let icon: String
    let title: String
    var sub: String?
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 12) {
            LucideIcon(name: icon, size: 18).foregroundStyle(Theme.title)
                .frame(width: 40, height: 40).background(Color(hex: 0x2C2C2E), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 16)).foregroundStyle(Theme.title).lineLimit(1)
                if let sub { Text(sub).font(.system(size: 13)).foregroundStyle(Theme.secondary).lineLimit(2) }
            }
            Spacer(minLength: 6)
            trailing()
        }
    }
}

private func pill(_ label: String, icon: String? = nil, filled: Bool = false, id: String,
                  _ action: @escaping () -> Void) -> some View {
    Button(action: action) {
        HStack(spacing: 7) {
            if let icon { LucideIcon(name: icon, size: 16) }
            Text(label).font(.system(size: 15, weight: .medium))
        }
        .foregroundStyle(Theme.title)
        .padding(.horizontal, 16).frame(height: 40)
        .background(filled ? Color(hex: 0x2F5FBF) : Color.clear, in: Capsule())
        .overlay(Capsule().stroke(filled ? Color.clear : Color(hex: 0x3A3A3C), lineWidth: 1))
    }
    .buttonStyle(.plain)
    .accessibilityIdentifier(id)
}

private func seconds(_ v: Double) -> String { String(format: "%.1f s", v) }

/// a picture of the video folder as a thumbnail (a video's first strip frame)
@MainActor
private func picture(_ file: String?, _ store: StudioEditStore, _ thumbs: StudioThumbs) -> UIImage? {
    guard let m = store.media(file) else { return nil }
    if let n = m.frames, n > 1 { return thumbs.frame(m.thumb, n, 0, store) }
    return thumbs.image(m.thumb ?? (m.kind == "image" ? m.url : nil), store)
}

@MainActor
private func thumbView(_ img: UIImage?) -> some View {
    ZStack {
        Color(hex: 0x2C2C2E)
        if let img { Image(uiImage: img).resizable().scaledToFill() }
    }
    .clipped()
}

// MARK: 19 · a voice line

struct StudioVoiceSheet: View {
    let id: String
    @Bindable var store: StudioEditStore
    var openStage: ((String) -> Void)?
    var close: () -> Void

    var body: some View {
        let line = store.voice.first { "voice:\($0.id)" == id }
        let lid = line?.id ?? String(id.dropFirst(6))
        let lm = store.mix.lines?[lid] ?? StudioLineMix()
        StudioPanel(title: "Voice line \(lid)", note: line.map { seconds($0.end - $0.start) }, id: "sheetVoice", close: close) {
            StudioSlider(icon: "volume-2", label: "Volume", value: StudioWords.db(lm.gain ?? 1), range: -24...6, tick: 0,
                         text: { String(format: "%.1f dB", $0) }) { v in
                set(lid, "Voice line \(lid) volume") { $0.gain = StudioEdit.r3(StudioWords.gain(v)) }
            }
            StudioSlider(icon: "trending-up", label: "Fade in", value: lm.fadeIn ?? 0, range: 0...2, text: seconds) { v in
                set(lid, "Voice line \(lid) fade in") { $0.fadeIn = StudioEdit.r3(v) }
            }
            StudioSlider(icon: "trending-down", label: "Fade out", value: lm.fadeOut ?? 0, range: 0...2, text: seconds) { v in
                set(lid, "Voice line \(lid) fade out") { $0.fadeOut = StudioEdit.r3(v) }
            }
            if let openStage {
                HStack(spacing: 10) {
                    pill("Retake in Voice", icon: "rotate-ccw", id: "voiceRetake") { openStage("voice") }
                    pill("Read in Script", icon: "file-text", id: "voiceScript") { openStage("script") }
                }
            }
        }
    }

    private func set(_ lid: String, _ label: String, _ f: (inout StudioLineMix) -> Void) {
        var mix = store.mix
        var lines = mix.lines ?? [:]
        var l = lines[lid] ?? StudioLineMix()
        f(&l)
        lines[lid] = l
        mix.lines = lines
        store.setMix(mix, label: label)
    }
}

// MARK: 21 · text

struct StudioTextSheet: View {
    let id: String
    @Bindable var store: StudioEditStore
    var close: () -> Void
    @State private var words: String?
    @FocusState private var typing: Bool

    var body: some View {
        let c = StudioEdit.clip(id, in: store.model)
        StudioPanel(title: "Text", note: c.map { seconds($0.dur) }, id: "sheetText", close: { commit(); close() }) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Two lines").font(.system(size: 13)).foregroundStyle(Theme.secondary)
                TextField("Words", text: Binding(get: { words ?? c?.text ?? "" }, set: { words = $0 }), axis: .vertical)
                    .font(.system(size: 17)).foregroundStyle(Theme.title)
                    .lineLimit(1...3)
                    .focused($typing)
                    .onSubmit { commit() }
                    .accessibilityIdentifier("textWords")
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(hex: 0x2C2C2E), in: RoundedRectangle(cornerRadius: 14))
            Text("STYLE").font(.system(size: 13)).foregroundStyle(Theme.secondary)
            StudioSegments(items: [("lower", "Lower third"), ("title", "Title"), ("caption", "Caption")],
                           chosen: c?.style ?? "lower") { s in
                commit()
                store.change("Text style: \(["lower": "lower third", "title": "title", "caption": "caption"][s] ?? s)") { m in
                    StudioEdit.set(&m, id) { $0.style = s }
                }
            }
        }
        .onChange(of: typing) { _, on in if !on { commit() } }
        .onDisappear { commit() }
    }

    private func commit() {
        guard let w = words else { return }
        words = nil
        store.change("Changed the words of “\(StudioEdit.cut(w, 24))”") { m in
            StudioEdit.set(&m, id) { $0.text = w }
        }
    }
}

// MARK: 22 · a transition

struct StudioTransitionSheet: View {
    let id: String
    @Bindable var store: StudioEditStore
    let player: StudioPlayer
    let thumbs: StudioThumbs
    var close: () -> Void
    @State private var sound = true
    @State private var preview: Task<Void, Never>?

    var body: some View {
        let v = store.model.video
        let i = v.firstIndex { $0.id == id } ?? 0
        let c = i < v.count ? v[i] : nil
        let prev = i > 0 && i - 1 < v.count ? v[i - 1] : nil
        let kind = c?.transition ?? "cut"
        let fade = c?.fade ?? 0.6
        StudioPanel(title: "Into shot \(i + 1)", note: "from shot \(i)", id: "sheetTransition", close: close) {
            HStack(spacing: 10) {
                card("cut", "Cut", kind, prev, c)
                card("crossfade", "Crossfade", kind, prev, c)
                card("dip", "Dip to black", kind, prev, c)
            }
            StudioSlider(icon: "clock", label: "Length", value: fade, range: 0.1...2, text: seconds) { f in
                apply(kind == "cut" ? "crossfade" : kind, fade: f)
            }
            .disabled(kind == "cut")
            .opacity(kind == "cut" ? 0.4 : 1)
            StudioIconRow(icon: "audio-lines", title: "The sound crossfades too", sub: soundNote(c?.start)) {
                Toggle("", isOn: $sound).labelsHidden().tint(Theme.blue)
                    .accessibilityIdentifier("transitionSound")
            }
            if let ch = c.flatMap({ StudioEdit.chapter(at: $0.start, store.chapters) }) {
                pill("Use for every cut in \(ch.title)", id: "transitionEverywhere") {
                    let ids = StudioEdit.shots(in: ch, store.model)
                    store.change("\(kind == "cut" ? "Cuts" : kind == "dip" ? "Dips to black" : "Crossfades") for every cut in \(ch.title)",
                                 toast: true) { m in
                        StudioEdit.setTransition(&m, ids, kind: kind, fade: fade, sound: sound)
                        return true
                    }
                }
            }
        }
        .onDisappear { preview?.cancel() }
    }

    private func card(_ k: String, _ label: String, _ kind: String, _ a: StudioClip?, _ b: StudioClip?) -> some View {
        let on = k == kind
        let left = a.flatMap { picture(StudioEdit.source($0, store.shots).src, store, thumbs) }
        let right = b.flatMap { picture(StudioEdit.source($0, store.shots).src, store, thumbs) }
        return Button { apply(k, fade: b?.fade ?? 0.6) } label: {
            VStack(spacing: 8) {
                GeometryReader { g in
                    ZStack {
                        HStack(spacing: 0) {
                            thumbView(left).frame(width: g.size.width / 2)
                            thumbView(right).frame(width: g.size.width / 2)
                        }
                        if k == "crossfade" {
                            thumbView(right).opacity(0.5).mask(
                                LinearGradient(colors: [.clear, .black, .clear], startPoint: .leading, endPoint: .trailing))
                        }
                        if k == "dip" {
                            LinearGradient(colors: [.clear, .black, .clear], startPoint: .leading, endPoint: .trailing)
                        }
                    }
                }
                .frame(height: 50)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                Text(label).font(.system(size: 14, weight: on ? .semibold : .regular)).foregroundStyle(Theme.title)
                    .lineLimit(1)
            }
            .padding(8)
            .background(Color(hex: 0x2C2C2E), in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(on ? Color.white : .clear, lineWidth: 2))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("transition-\(k)")
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private func apply(_ k: String, fade: Double) {
        let n = (store.model.video.firstIndex { $0.id == id } ?? 0) + 1
        let what = k == "cut" ? "cut" : k == "dip" ? String(format: "dip %.1f s", fade) : String(format: "crossfade %.1f s", fade)
        store.change("Shot \(n) in: \(what)") { m in
            StudioEdit.setTransition(&m, [id], kind: k, fade: fade, sound: sound)
            return true
        }
        play()
    }

    /// plays the change: from a second before the cut to a second after
    private func play() {
        guard let c = StudioEdit.clip(id, in: store.model) else { return }
        preview?.cancel()
        player.seek(max(0, c.start - 1))
        preview = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 350_000_000)
            if Task.isCancelled { return }
            if !player.playing { player.toggle(duration: store.duration) }
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            if !Task.isCancelled, player.playing { player.pause() }
        }
    }

    /// "room tone into the street rain": the beds that meet at the cut
    private func soundNote(_ cut: Double?) -> String {
        guard let cut else { return "" }
        let log = store.view?.log
        let all = store.model.sfx + store.model.music
        let out = all.first { abs($0.end - cut) < 0.1 }.map { StudioWords.sound($0, log) }
        let into = all.first { abs($0.start - cut) < 0.1 }.map { StudioWords.sound($0, log) }
        switch (out, into) {
        case let (a?, b?): return "\(a) into \(b)"
        case let (a?, nil): return "\(a) fades out over it"
        case let (nil, b?): return "\(b) fades in over it"
        default: return "the effects and music at the cut"
        }
    }
}

// MARK: 23 · add a photo

struct StudioPhotoSheet: View {
    @Bindable var store: StudioEditStore
    let player: StudioPlayer
    let thumbs: StudioThumbs
    var close: () -> Void
    @State private var filter = "cleared"
    @State private var picked: String?

    var body: some View {
        let cleared = (store.view?.photos ?? []).filter { $0.cleared && !$0.rejected }
        let pd = cleared.filter { $0.rights == "public-domain" }
        let cc = cleared.filter { $0.rights != "public-domain" }
        let shown = filter == "pd" ? pd : filter == "cc" ? cc : cleared
        StudioPanel(title: "Add a photo", note: "from Research", id: "sheetPhoto", close: close) {
            HStack(spacing: 8) {
                chip("cleared", "Cleared \(cleared.count)")
                chip("pd", "Public domain \(pd.count)")
                chip("cc", "CC with credit \(cc.count)")
            }
            if cleared.isEmpty {
                Text("Nothing is cleared yet: Research clears pictures for the video.")
                    .font(.system(size: 15)).foregroundStyle(Theme.secondary)
            }
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                    ForEach(shown) { p in photo(p) }
                }
            }
            .frame(maxHeight: 290)
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("In at \(StudioEdit.clock(player.time)) for 4 s").font(.system(size: 16)).foregroundStyle(Theme.title)
                    Text("with a slow zoom in · its credit goes to Finish").font(.system(size: 13))
                        .foregroundStyle(Theme.secondary)
                }
                Spacer()
                pill("Add", icon: "plus", filled: true, id: "photoAdd") { add(cleared) }
                    .disabled(picked == nil)
                    .opacity(picked == nil ? 0.5 : 1)
            }
        }
    }

    private func chip(_ id: String, _ label: String) -> some View {
        Button { filter = id } label: {
            Text(label).font(.system(size: 14, weight: filter == id ? .semibold : .regular))
                .foregroundStyle(filter == id ? Color.black : Theme.title)
                .padding(.horizontal, 12).frame(height: 34)
                .background(filter == id ? Color(hex: 0xEDEDED) : .clear, in: Capsule())
                .overlay(Capsule().stroke(filter == id ? Color.clear : Color(hex: 0x3A3A3C), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("photoFilter-\(id)")
    }

    private func photo(_ p: StudioPhoto) -> some View {
        let on = picked == p.id
        let pd = p.rights == "public-domain"
        return Button { picked = on ? nil : p.id } label: {
            VStack(alignment: .leading, spacing: 4) {
                thumbView(picture(p.file, store, thumbs))
                    .frame(height: 70)
                    .overlay(alignment: .topTrailing) {
                        if on {
                            LucideIcon(name: "check", size: 13).foregroundStyle(.white)
                                .frame(width: 22, height: 22).background(Theme.blue, in: Circle()).padding(5)
                        }
                    }
                Text(p.title).font(.system(size: 13)).foregroundStyle(Theme.title).lineLimit(1).padding(.horizontal, 6)
                Text(pd ? "Public domain" : "CC with credit").font(.system(size: 12))
                    .foregroundStyle(pd ? Theme.green : Theme.blue)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background((pd ? Theme.green : Theme.blue).opacity(0.14), in: RoundedRectangle(cornerRadius: 5))
                    .padding(.horizontal, 4).padding(.bottom, 6)
            }
            .background(Color(hex: 0x2C2C2E), in: RoundedRectangle(cornerRadius: 12))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(on ? Color.white : .clear, lineWidth: 2))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("photo-\(p.id)")
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private func add(_ cleared: [StudioPhoto]) {
        guard let p = cleared.first(where: { $0.id == picked }) else { return }
        let at = player.time
        var id = ""
        store.change("Added \(p.title) at \(StudioEdit.clock(at))", toast: true) { m in
            id = StudioEdit.addPhoto(&m, p, at: at)
            return true
        }
        close()
        if !id.isEmpty { store.selected = id }
    }
}

// MARK: 24 · Ken Burns

struct StudioKenBurnsSheet: View {
    let id: String
    @Bindable var store: StudioEditStore
    var close: () -> Void

    private static let moves: [(id: String?, label: String, icon: String)] = [
        (nil, "Off", "circle-slash"), ("in", "Zoom in", "zoom-in"), ("out", "Zoom out", "zoom-out"),
        ("left", "Pan left", "arrow-left"), ("right", "Pan right", "arrow-right"),
    ]

    var body: some View {
        let c = StudioEdit.clip(id, in: store.model)
        let p = store.view?.photos.first { $0.file == c?.media }
        let n = StudioWords.names(store.model, store.view?.log)[id] ?? id
        StudioPanel(title: "Ken Burns", note: p.map { "\(n) · \($0.title)" } ?? n, id: "sheetKenBurns", close: close) {
            HStack(spacing: 8) {
                ForEach(Self.moves.indices, id: \.self) { k in
                    let mv = Self.moves[k]
                    let on = c?.kenburns == mv.id
                    Button { setMove(mv.id, mv.label) } label: {
                        VStack(spacing: 6) {
                            LucideIcon(name: mv.icon, size: 22)
                            Text(mv.label).font(.system(size: 13)).lineLimit(1).minimumScaleFactor(0.8)
                        }
                        .foregroundStyle(Theme.title)
                        .frame(maxWidth: .infinity).frame(height: 66)
                        .background(Color(hex: 0x2C2C2E), in: RoundedRectangle(cornerRadius: 14))
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(on ? Color.white : .clear, lineWidth: 2))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("kb-\(mv.id ?? "off")")
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
            StudioSlider(icon: "clock", label: "Length", value: c?.dur ?? 4, range: 1...12, text: seconds) { v in
                guard let c else { return }
                store.change("Length of \(n): \(String(format: "%.1f", v)) s") { m in
                    StudioEdit.trim(&m, original: c, edge: .right, by: v - c.dur, shots: store.shots, snaps: [], within: 0)
                    return true
                }
            }
            let z = c?.kbZoom ?? 1.15
            StudioSlider(icon: "scan", label: "Zoom", value: z, range: 1.02...2,
                         text: { v in c?.kenburns == "out" ? String(format: "%.1f → 1.0×", v)
                             : c?.kenburns == "in" ? String(format: "1.0 → %.1f×", v) : String(format: "%.1f×", v) }) { v in
                store.change("Ken Burns zoom on \(n)") { m in StudioEdit.set(&m, id) { $0.kbZoom = StudioEdit.r3(v) } }
            }
            .disabled(c?.kenburns == nil)
            .opacity(c?.kenburns == nil ? 0.4 : 1)
            if let p {
                StudioIconRow(icon: "image", title: p.credit,
                              sub: p.rights == "public-domain" ? "Public domain" : "CC with credit · kept for Finish") { EmptyView() }
            }
        }
    }

    private func setMove(_ k: String?, _ label: String) {
        let n = StudioWords.names(store.model, store.view?.log)[id] ?? id
        store.change("Ken Burns on \(n): \(label.lowercased())") { m in StudioEdit.set(&m, id) { $0.kenburns = k } }
    }
}

// MARK: a music or effects clip

struct StudioSoundClipSheet: View {
    let id: String
    @Bindable var store: StudioEditStore
    var close: () -> Void

    var body: some View {
        let c = StudioEdit.clip(id, in: store.model)
        let t = StudioEdit.track(of: id, in: store.model) ?? .sfx
        let n = c.map { StudioWords.sound($0, store.view?.log) } ?? id
        StudioPanel(title: n, note: c.map { seconds($0.dur) }, id: "sheetSound", close: close) {
            StudioSlider(icon: "volume-2", label: "Volume", value: StudioWords.db(c?.gain ?? 1), range: -40...6, tick: 0,
                         text: { String(format: "%.1f dB", $0) }) { v in
                store.change("Volume of \(n)") { m in StudioEdit.set(&m, id) { $0.gain = StudioEdit.r3(StudioWords.gain(v)) } }
            }
            StudioSlider(icon: "trending-up", label: "Fade in", value: c?.fadeIn ?? 0, range: 0...min(5, max(0.1, c?.dur ?? 5)),
                         text: seconds) { v in
                store.change("Fade in of \(n)") { m in StudioEdit.set(&m, id) { $0.fadeIn = StudioEdit.r3(v) } }
            }
            StudioSlider(icon: "trending-down", label: "Fade out", value: c?.fadeOut ?? 0, range: 0...min(5, max(0.1, c?.dur ?? 5)),
                         text: seconds) { v in
                store.change("Fade out of \(n)") { m in StudioEdit.set(&m, id) { $0.fadeOut = StudioEdit.r3(v) } }
            }
            if let c {
                StudioIconRow(icon: "mic", title: "Dips under the voice", sub: "ducks when the narrator speaks") {
                    Toggle("", isOn: Binding(get: { StudioPreview.ducks(t, c) }, set: { on in
                        store.change(on ? "\(n) ducks under the voice" : "\(n) stays up under the voice") { m in
                            StudioEdit.set(&m, id) { $0.duck = on }
                        }
                    }))
                    .labelsHidden().tint(Theme.blue)
                    .accessibilityIdentifier("soundDuck")
                }
            }
        }
    }
}

// MARK: replace a shot

struct StudioReplaceSheet: View {
    let id: String
    @Bindable var store: StudioEditStore
    let thumbs: StudioThumbs
    var close: () -> Void

    var body: some View {
        let n = StudioWords.names(store.model, store.view?.log)[id] ?? id
        let shots = (store.view?.shots ?? []).filter { $0.src != nil }
        let photos = (store.view?.photos ?? []).filter { $0.cleared && !$0.rejected }
        StudioPanel(title: "Replace \(n)", note: "another shot or a cleared photo", id: "sheetReplace", close: close) {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    Text("SHOTS").font(.system(size: 13)).foregroundStyle(Theme.secondary)
                    grid(shots.map { ($0.id, "Shot \($0.id.dropFirst())", $0.src) }) { sid in
                        replace("shot \(sid.dropFirst())") { $0.shot = sid; $0.media = nil; $0.trim = nil; $0.label = nil }
                    }
                    Text("CLEARED PHOTOS").font(.system(size: 13)).foregroundStyle(Theme.secondary)
                    grid(photos.map { ($0.id, $0.title, $0.file) }) { pid in
                        guard let p = photos.first(where: { $0.id == pid }) else { return }
                        replace(p.title) { c in
                            c.media = p.file; c.shot = nil; c.trim = nil; c.label = p.title
                            if c.kenburns == nil { c.kenburns = "in" }
                        }
                    }
                }
            }
            .frame(maxHeight: 320)
        }
    }

    private func grid(_ items: [(String, String, String?)], pick: @escaping (String) -> Void) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
            ForEach(items.indices, id: \.self) { k in
                let it = items[k]
                Button { pick(it.0) } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        thumbView(picture(it.2, store, thumbs)).frame(height: 62)
                        Text(it.1).font(.system(size: 13)).foregroundStyle(Theme.title).lineLimit(1)
                            .padding(.horizontal, 6).padding(.bottom, 6)
                    }
                    .background(Color(hex: 0x2C2C2E))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("replace-\(it.0)")
            }
        }
    }

    private func replace(_ what: String, _ f: @escaping (inout StudioClip) -> Void) {
        let n = StudioWords.names(store.model, store.view?.log)[id] ?? id
        store.change("Replaced \(n) with \(what)", toast: true) { m in StudioEdit.set(&m, id, f) }
        close()
    }
}

// MARK: the shots

struct StudioShotsSheet: View {
    @Bindable var store: StudioEditStore
    let player: StudioPlayer
    let thumbs: StudioThumbs
    var close: () -> Void

    var body: some View {
        let v = store.model.video
        StudioPanel(title: "Shots", note: "\(v.count) on the timeline", id: "sheetShots", close: close) {
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(Array(v.enumerated()), id: \.element.id) { i, c in
                        Button {
                            player.seek(c.start)
                            store.selected = c.id
                            close()
                        } label: {
                            HStack(spacing: 12) {
                                thumbView(picture(StudioEdit.source(c, store.shots).src, store, thumbs))
                                    .frame(width: 72, height: 42).clipShape(RoundedRectangle(cornerRadius: 7))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("\(c.media != nil ? "Photo" : "Shot") \(i + 1)").font(.system(size: 15, weight: .medium))
                                        .foregroundStyle(Theme.title)
                                    Text(c.label ?? c.shot.flatMap { store.shots[$0]?.description } ?? "")
                                        .font(.system(size: 13)).foregroundStyle(Theme.secondary).lineLimit(1)
                                }
                                Spacer()
                                Text("\(StudioEdit.clock(c.start)) · \(seconds(c.dur))").font(.system(size: 13).monospacedDigit())
                                    .foregroundStyle(Theme.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("shotRow-\(c.id)")
                    }
                }
            }
            .frame(maxHeight: 320)
        }
    }
}

// MARK: 25 · mix and loudness

struct StudioMixSheet: View {
    @Bindable var store: StudioEditStore
    let cache: StudioMediaCache
    let player: StudioPlayer
    var close: () -> Void

    var body: some View {
        let mix = store.mix
        let md = store.view?.mixdown
        let canMixdown = md.map { cache.ready($0.file) } ?? false
        StudioPanel(title: "Mix", note: "picture and sound together", id: "sheetMix", close: close) {
            StudioSegments(items: [("timeline", "Timeline mix"), ("mixdown", "Mixdown")],
                           chosen: player.useMixdown ? "mixdown" : "timeline",
                           disabled: canMixdown ? [] : ["mixdown"]) { k in player.useMixdown = k == "mixdown" }
            level("mic", "Voice", mix.voice.gain) { m, g in m.voice.gain = g }
            level("music", "Music", mix.music.gain) { m, g in m.music.gain = g }
            level("audio-lines", "Effects", mix.sfx.gain) { m, g in m.sfx.gain = g }
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Duck the music under the voice").font(.system(size: 16)).foregroundStyle(Theme.title)
                    Text("dips \(Int(mix.duck.depth.rounded())) dB under the narrator's words").font(.system(size: 13))
                        .foregroundStyle(Theme.secondary)
                }
                Spacer()
                Toggle("", isOn: Binding(get: { mix.duck.on }, set: { on in
                    var m = store.mix
                    m.duck.on = on
                    store.setMix(m, label: on ? "Ducking on" : "Ducking off")
                }))
                .labelsHidden().tint(Theme.blue)
                .accessibilityIdentifier("mixDuck")
            }
            loudness(md, target: mix.target)
            mixdownButton
        }
    }

    private func level(_ icon: String, _ label: String, _ g: Double, _ f: @escaping (inout StudioMix, Double) -> Void) -> some View {
        StudioSlider(icon: icon, label: label, value: StudioWords.db(g), range: -40...6, tick: 0,
                     text: { String(format: abs($0) < 0.5 ? "0 dB" : "%.0f dB", $0) }) { v in
            var m = store.mix
            f(&m, StudioEdit.r3(StudioWords.gain(v)))
            store.setMix(m, label: "\(label) level")
        }
    }

    private func loudness(_ md: StudioMixdown?, target: Double) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("Loudness").font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.title)
                Text(String(format: "target %.0f LUFS (YouTube)", target)).font(.system(size: 14)).foregroundStyle(Theme.secondary)
            }
            if let md {
                HStack(alignment: .top, spacing: 22) {
                    stat(md.lufs, "%.1f", "LUFS")
                    stat(md.truePeak, "%.1f", "true peak")
                    stat(md.lra, "%.1f", "LU range")
                    stat(md.gain, "%+.1f", "dB gain")
                }
                if store.view?.mixCurrent == false {
                    HStack(spacing: 6) {
                        LucideIcon(name: "circle-alert", size: 15)
                        Text("The timeline changed since this mixdown").font(.system(size: 14))
                    }
                    .foregroundStyle(Theme.amber)
                    .accessibilityIdentifier("mixOutOfDate")
                }
            } else {
                Text("No mixdown yet: make one and it's measured here.").font(.system(size: 14)).foregroundStyle(Theme.secondary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color(hex: 0x3A3A3C), lineWidth: 1))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("mixLoudness")
    }

    private func stat(_ v: Double?, _ f: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(v.map { String(format: f, $0).replacingOccurrences(of: "-", with: "−") } ?? "–")
                .font(.system(size: 22, weight: .semibold).monospacedDigit()).foregroundStyle(Theme.title)
            Text(label).font(.system(size: 12)).foregroundStyle(Theme.secondary)
        }
    }

    @ViewBuilder
    private var mixdownButton: some View {
        if let j = store.mixdownJob, j.status == "running" {
            HStack(spacing: 10) {
                ProgressView().tint(Theme.blue)
                Text("Mixdown to \(Int(store.mix.target)) LUFS · \(j.phase ?? "working")").font(.system(size: 15))
                    .foregroundStyle(Theme.title)
                Spacer()
                if let p = j.progress { Text("\(Int(p * 100))%").font(.system(size: 14).monospacedDigit()).foregroundStyle(Theme.blue) }
            }
            .accessibilityIdentifier("mixdownRunning")
        } else {
            pill("Make mixdown", icon: "audio-lines", filled: true, id: "mixdownMake") { Task { await store.makeMixdown() } }
                .disabled(store.readonly)
        }
    }
}

// MARK: 20 · sounds

struct StudioSoundsSheet: View {
    @Bindable var store: StudioEditStore
    let player: StudioPlayer
    var close: () -> Void
    @State private var tab = "library"
    @State private var query = ""
    @State private var track = StudioTrack.sfx
    @State private var atShot = false
    @State private var listen = AVPlayer()
    @State private var listening: String?
    @State private var kind = "sfx"
    @State private var prompt = ""
    @State private var length = 3.0
    @State private var recorder = StudioRecorder()

    var body: some View {
        StudioPanel(title: "Sounds", id: "sheetSounds", close: { listen.pause(); close() }) {
            StudioSegments(items: [("library", "Library"), ("generate", "Generate"), ("record", "Record"), ("sources", "Sources")],
                           chosen: tab) { tab = $0 }
            switch tab {
            case "generate": generate
            case "record": record
            case "sources": sources
            default: library
            }
            if tab != "sources" { whereItGoes }
        }
        .onDisappear { listen.pause() }
    }

    /// where a sound goes: the playhead, or the start of the shot under it; on Effects or Music
    private var at: Double {
        guard atShot, let c = store.model.video.last(where: { $0.start <= player.time + 1e-6 }) else { return player.time }
        return c.start
    }

    private var whereItGoes: some View {
        Menu {
            Button("On Effects") { track = .sfx }
            Button("On Music") { track = .music }
            Divider()
            Button("At the playhead") { atShot = false }
            Button("At the start of the shot") { atShot = true }
        } label: {
            StudioIconRow(icon: "map-pin", title: atShot ? "Goes in at the shot's start" : "Goes in at the playhead",
                          sub: "\(StudioEdit.clock(at)) on \(track == .music ? "Music" : "Effects") · or on a shot's start") {
                LucideIcon(name: "chevron-down", size: 18).foregroundStyle(Theme.secondary)
            }
        }
        .accessibilityIdentifier("soundsWhere")
    }

    // the library: Freesound's CC0 sounds, and what the video has already

    private var library: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                LucideIcon(name: "search", size: 18).foregroundStyle(Theme.secondary)
                TextField("Search Freesound", text: $query)
                    .font(.system(size: 17)).foregroundStyle(Theme.title)
                    .submitLabel(.search)
                    .onSubmit { Task { await store.search(query) } }
                    .accessibilityIdentifier("soundsSearch")
                if store.searching { ProgressView().tint(Theme.secondary) }
            }
            .padding(.horizontal, 14).frame(height: 46)
            .background(Color(hex: 0x2C2C2E), in: RoundedRectangle(cornerRadius: 14))
            .onAppear { if query.isEmpty, let q = store.found?.query { query = q } }
            .onChange(of: store.found?.query) { _, q in if query.isEmpty, let q { query = q } }
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    if let f = store.found {
                        Text("FREESOUND · CC0 ONLY").font(.system(size: 13)).foregroundStyle(Theme.secondary)
                        if f.results.isEmpty {
                            Text("Nothing found for “\(f.query)”.").font(.system(size: 14)).foregroundStyle(Theme.secondary)
                        }
                        ForEach(f.results) { r in found(r) }
                    } else if let log = store.view?.log, !log.isEmpty {
                        Text("IN THIS VIDEO").font(.system(size: 13)).foregroundStyle(Theme.secondary)
                        ForEach(log.filter { $0.missing != true }) { s in owned(s) }
                    }
                    Button { tab = "generate"; if prompt.isEmpty { prompt = query.isEmpty ? store.found?.query ?? "" : query } } label: {
                        StudioIconRow(icon: "wand-sparkles", title: "Nothing fits? Generate it",
                                      sub: "ElevenLabs sound effect · about \(Int(rate("sfx") * 2)) credits") {
                            LucideIcon(name: "chevron-right", size: 18).foregroundStyle(Theme.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("soundsToGenerate")
                }
            }
            .frame(maxHeight: 250)
        }
    }

    private func found(_ r: StudioFound) -> some View {
        let have = store.fileOf(r) != nil
        let sub = [r.author, r.seconds.map { StudioEdit.clock($0, tenths: false) }].compactMap { $0 }.joined(separator: " · ")
        return HStack(spacing: 12) {
            playButton(r.id, store.url(r.preview))
            VStack(alignment: .leading, spacing: 2) {
                Text(r.title).font(.system(size: 16)).foregroundStyle(Theme.title).lineLimit(1)
                HStack(spacing: 6) {
                    Text(sub).font(.system(size: 13)).foregroundStyle(Theme.secondary).lineLimit(1)
                    Text("CC0").font(.system(size: 12)).foregroundStyle(Theme.green)
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(Theme.green.opacity(0.14), in: RoundedRectangle(cornerRadius: 4))
                }
            }
            Spacer(minLength: 6)
            if store.getting.contains(r.id) {
                ProgressView().tint(Theme.secondary).frame(width: 80)
            } else {
                addButton(have) {
                    let at = self.at, t = track
                    Task {
                        if await store.add(r, track: t, at: at) != nil {
                            store.show("Added \(r.title) at \(StudioEdit.clock(at))", undo: true)
                        }
                    }
                }
                .accessibilityIdentifier("soundAdd-\(r.id)")
            }
        }
    }

    private func owned(_ s: StudioSound) -> some View {
        let used = !(s.clips ?? []).isEmpty
        return HStack(spacing: 12) {
            playButton(s.file, store.media(s.file).flatMap { store.url($0.url) })
            VStack(alignment: .leading, spacing: 2) {
                Text(s.title ?? (s.file as NSString).lastPathComponent).font(.system(size: 16)).foregroundStyle(Theme.title)
                    .lineLimit(1)
                Text([s.licence, s.seconds.map { StudioEdit.clock($0, tenths: false) }].compactMap { $0 }.joined(separator: " · "))
                    .font(.system(size: 13)).foregroundStyle(Theme.secondary).lineLimit(1)
            }
            Spacer(minLength: 6)
            addButton(used) {
                let at = self.at
                if store.place(s.file, title: s.title, seconds: s.seconds, track: track, at: at) != nil {
                    store.show("Added \(s.title ?? "the sound") at \(StudioEdit.clock(at))", undo: true)
                }
            }
            .accessibilityIdentifier("soundPlace-\((s.file as NSString).lastPathComponent)")
        }
    }

    /// "Added" once it's in the video, but a second copy can still go in
    private func addButton(_ added: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                LucideIcon(name: added ? "check" : "plus", size: 15)
                Text(added ? "Added" : "Add").font(.system(size: 15, weight: .medium))
            }
            .foregroundStyle(Theme.title)
            .padding(.horizontal, 14).frame(height: 36)
            .background(added ? Color.clear : Color(hex: 0x2F5FBF), in: Capsule())
            .overlay(Capsule().stroke(added ? Color(hex: 0x3A3A3C) : .clear, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(store.readonly)
    }

    private func playButton(_ id: String, _ url: URL?) -> some View {
        let on = listening == id
        return Button {
            if on {
                listen.pause()
                listening = nil
            } else if let url {
                player.pause()
                try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
                listen.replaceCurrentItem(with: AVPlayerItem(url: url))
                listen.play()
                listening = id
            }
        } label: {
            LucideIcon(name: on ? "pause" : "play", size: 16).foregroundStyle(on ? Color.black : Theme.title)
                .frame(width: 40, height: 40)
                .background(on ? Color(hex: 0xEDEDED) : Color(hex: 0x2C2C2E), in: Circle())
        }
        .buttonStyle(.plain)
        .disabled(url == nil)
        .accessibilityLabel(on ? "Stop the preview" : "Preview")
    }

    // generate: ElevenLabs, with its price first and a yes

    private func rate(_ k: String) -> Double {
        (k == "music" ? store.view?.rates?.music : store.view?.rates?.sfx) ?? (k == "music" ? 30 : 20)
    }

    private var generate: some View {
        VStack(alignment: .leading, spacing: 12) {
            StudioSegments(items: [("sfx", "Sound effect"), ("music", "Music score")], chosen: kind) { k in
                kind = k
                length = k == "music" ? 30 : 3
                store.estimate = nil
            }
            TextField("What it sounds like", text: $prompt, axis: .vertical)
                .font(.system(size: 16)).foregroundStyle(Theme.title).lineLimit(1...3)
                .padding(12)
                .background(Color(hex: 0x2C2C2E), in: RoundedRectangle(cornerRadius: 14))
                .accessibilityIdentifier("generatePrompt")
            StudioSlider(icon: "clock", label: "Length", value: length, range: kind == "music" ? 10...120 : 0.5...22,
                         text: seconds) { length = ($0 * 10).rounded() / 10; store.estimate = nil }
            if let e = store.estimate {
                VStack(alignment: .leading, spacing: 10) {
                    Text("About \(Int(e.reply.estimate)) credits").font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Theme.title)
                    Text([e.reply.left.map { "\(Int($0)) left on the plan" }, e.reply.how.map { "price \($0)" }]
                        .compactMap { $0 }.joined(separator: " · "))
                        .font(.system(size: 13)).foregroundStyle(Theme.secondary)
                    HStack(spacing: 10) {
                        pill("Generate for \(Int(e.reply.estimate)) credits", icon: "wand-sparkles", filled: true,
                             id: "generateConfirm") { Task { await store.confirmGeneration() } }
                        pill("Cancel", id: "generateCancel") { store.estimate = nil }
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.amber.opacity(0.6), lineWidth: 1))
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("generateEstimate")
            } else {
                pill("What would it cost?", icon: "wand-sparkles", id: "generatePrice") {
                    let p = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !p.isEmpty else { return }
                    Task { await store.priceGeneration(kind: kind, prompt: p, seconds: length) }
                }
                .disabled(prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || store.readonly)
            }
            ForEach((store.view?.jobs ?? []).filter { $0.kind != "mixdown" && $0.status == "running" }) { j in
                HStack(spacing: 10) {
                    ProgressView().tint(Theme.blue)
                    Text(j.prompt ?? j.kind).font(.system(size: 15)).foregroundStyle(Theme.title).lineLimit(1)
                    Spacer()
                    Text(j.phase ?? "working").font(.system(size: 13)).foregroundStyle(Theme.blue)
                }
            }
        }
    }

    // record: the phone's microphone, sent to the PC's library

    private var record: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                Button {
                    Task {
                        if recorder.recording {
                            recorder.stop()
                        } else {
                            player.pause()
                            await recorder.start()
                        }
                    }
                } label: {
                    Circle().fill(Theme.red).frame(width: recorder.recording ? 22 : 30, height: recorder.recording ? 22 : 30)
                        .clipShape(RoundedRectangle(cornerRadius: recorder.recording ? 5 : 15))
                        .frame(width: 56, height: 56)
                        .overlay(Circle().stroke(Color.white, lineWidth: 3))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(recorder.recording ? "Stop" : "Record")
                .accessibilityIdentifier("soundsRecord")
                VStack(alignment: .leading, spacing: 2) {
                    Text(recorder.recording ? "Recording · \(seconds(recorder.elapsed))"
                         : recorder.file != nil ? "Recorded \(seconds(recorder.elapsed))" : "Record a sound")
                        .font(.system(size: 16)).foregroundStyle(Theme.title)
                    Text(recorder.note ?? "it goes into the video's library, logged as recorded")
                        .font(.system(size: 13)).foregroundStyle(Theme.secondary)
                }
            }
            if recorder.file != nil, !recorder.recording {
                pill(recorder.sending ? "Sending…" : "Add at \(StudioEdit.clock(at))", icon: "plus", filled: true,
                     id: "recordAdd") { send() }
                    .disabled(recorder.sending || store.demo || store.readonly)
            }
        }
    }

    private func send() {
        guard let url = recorder.file, let data = try? Data(contentsOf: url) else { return }
        let at = self.at, len = recorder.elapsed
        recorder.sending = true
        Task {
            defer { recorder.sending = false }
            let name = "recording-\(Int(Date().timeIntervalSince1970)).m4a"
            guard let up = await store.uploadRecording(data, name: name) else { return }
            if await store.addRecording(upload: up.path, title: "Recording", seconds: len, at: at) != nil {
                store.show("Added the recording at \(StudioEdit.clock(at))", undo: true)
                recorder.clear()
            }
        }
    }

    // sources: every sound in the video with where it came from (the licence log)

    private var sources: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(store.view?.log ?? []) { s in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(s.title ?? (s.file as NSString).lastPathComponent).font(.system(size: 15)).foregroundStyle(Theme.title)
                        Text([s.author, s.licence, s.credits.map { "\(Int($0)) credits" }, (s.clips ?? []).isEmpty ? "not used" : nil]
                            .compactMap { $0 }.joined(separator: " · "))
                            .font(.system(size: 13)).foregroundStyle(Theme.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                if let c = store.view?.credits?.left {
                    Text("ElevenLabs: \(Int(c)) credits left").font(.system(size: 13)).foregroundStyle(Theme.secondary)
                }
            }
        }
        .frame(maxHeight: 300)
        .accessibilityIdentifier("soundsSources")
    }
}

/// The phone's microphone for the Record tab: an AAC file in the temp folder.
@Observable
@MainActor
final class StudioRecorder {
    private(set) var recording = false
    private(set) var elapsed: Double = 0
    private(set) var file: URL?
    private(set) var note: String?
    var sending = false
    private var recorder: AVAudioRecorder?
    private var ticker: Task<Void, Never>?

    func start() async {
        guard !recording else { return }
        guard await AVAudioApplication.requestRecordPermission() else {
            note = "GupWorks can't use the microphone. Allow it in Settings › GupWorks."
            return
        }
        clear()
        do {
            let s = AVAudioSession.sharedInstance()
            try s.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
            try s.setActive(true)
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("studio-\(UUID().uuidString).m4a")
            let r = try AVAudioRecorder(url: url, settings: [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC), AVSampleRateKey: 48_000.0, AVNumberOfChannelsKey: 1,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
            ])
            guard r.record() else { note = "The microphone didn't start."; return }
            recorder = r
            file = url
            recording = true
            ticker = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 100_000_000)
                    guard let self, let r = self.recorder, self.recording else { return }
                    self.elapsed = r.currentTime
                }
            }
        } catch {
            note = "The microphone didn't start: \(error.localizedDescription)"
        }
    }

    func stop() {
        guard let r = recorder else { return }
        elapsed = r.currentTime
        r.stop()
        recorder = nil
        recording = false
        ticker?.cancel()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    func clear() {
        if let f = file { try? FileManager.default.removeItem(at: f) }
        file = nil
        elapsed = 0
        note = nil
    }
}
