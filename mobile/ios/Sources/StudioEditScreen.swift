import SwiftUI
import AVFoundation

/// The Edit stage of a Studio video, pushed on the chat's stack.
struct StudioEditRoute: Hashable {
    let projectId: String
    let videoId: String
    var title: String
}

/// What's open over the timeline's lower part (19-25).
enum StudioSheet: Hashable {
    case sounds, photo, mix, shots
    case voice(String), text(String), transition(String), kenburns(String), replace(String), sound(String)

    /// a sheet of one clip: it closes when nothing is selected
    var clip: String? {
        switch self {
        case .voice(let id), .text(let id), .kenburns(let id), .replace(let id), .sound(let id): id
        default: nil
        }
    }
}

/// Names for clips in the undo history and on the timeline ("shot 6", "Soft room tone · CC0").
enum StudioWords {
    static func sound(_ c: StudioClip, _ log: [StudioSound]?) -> String {
        if let l = c.label { return l }
        let s = log?.first { $0.file == c.file }
        let title = s?.title ?? ((c.file ?? c.id) as NSString).lastPathComponent
        let from: String? = switch s?.source {
        case "freesound": "CC0"
        case "eleven-music": "Eleven Music"
        case "elevenlabs", "elevenlabs-sfx": "ElevenLabs"
        case "recorded": "Recorded"
        default: nil
        }
        return from.map { "\(title) · \($0)" } ?? title
    }

    static func names(_ m: StudioModel, _ log: [StudioSound]?) -> [String: String] {
        var n: [String: String] = [:]
        for (i, c) in m.video.enumerated() { n[c.id] = c.media != nil ? "photo \(i + 1)" : "shot \(i + 1)" }
        for c in m.overlay { n[c.id] = "“\(StudioEdit.cut(c.text ?? "", 24))”" }
        for t in [StudioTrack.music, .sfx] { for c in m[t] { n[c.id] = sound(c, log) } }
        return n
    }

    static func db(_ g: Double) -> Double { g <= 0.0001 ? -60 : 20 * log10(g) }
    static func gain(_ db: Double) -> Double { db <= -59.5 ? 0 : pow(10, db / 20) }
    static func dbText(_ g: Double) -> String {
        let d = db(g)
        return d <= -59.5 ? "off" : String(format: abs(d) < 0.05 ? "0 dB" : "%+.0f dB", d).replacingOccurrences(of: "+-", with: "-")
    }
}

/// 15-28: the player on top, the timeline under a fixed playhead, the toolbars, the sheets.
struct StudioEditScreen: View {
    let route: StudioEditRoute
    /// another stage of the video (Voice for a retake, Script for the words), when the video page is under this
    var openStage: ((String) -> Void)?
    @State private var store: StudioEditStore
    @State private var cache = StudioMediaCache()
    @State private var player = StudioPlayer()
    @State private var thumbs = StudioThumbs()
    @State private var pps: Double
    @State private var draft: StudioDraft?
    @State private var sheet: StudioSheet?
    @State private var full = false
    @State private var shownToast: StudioEditStore.Toast?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openChatRoute) private var openChatRoute

    init(route: StudioEditRoute, pairing: Pairing?, demo: Bool, openStage: ((String) -> Void)? = nil) {
        self.route = route
        self.openStage = openStage
        _store = State(initialValue: StudioEditStore(ref: StudioRef(projectId: route.projectId, videoId: route.videoId),
                                                     pairing: pairing, demo: demo))
        var z = 40.0
        if Demo.isOn, let s = Self.arg("-studioZoom"), let v = Double(s) { z = v }
        _pps = State(initialValue: z)
    }

    private static func arg(_ flag: String) -> String? {
        let a = Demo.args
        guard let i = a.firstIndex(of: flag), i + 1 < a.count else { return nil }
        return a[i + 1]
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            picture
            transport
            if let r = store.view?.reason, store.readonly {
                Text(r).font(.system(size: 13)).foregroundStyle(Theme.amber)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 16).padding(.bottom, 4)
            }
            ZStack(alignment: .bottom) {
                VStack(spacing: 0) {
                    if store.view != nil {
                        StudioEditTimeline(store: store, cache: cache, player: player, thumbs: thumbs, pps: $pps,
                                           draft: $draft, openCut: openCut,
                                           onCut: { id in withAnimation(.snappy(duration: 0.25)) { sheet = .transition(id) } },
                                           onAdd: { withAnimation(.snappy(duration: 0.25)) { sheet = .photo } })
                    } else {
                        loading.frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    Rectangle().fill(Color(hex: 0x1F1F1F)).frame(height: 1)
                    StudioEditToolbar(store: store, player: player, sheet: $sheet, chat: { openChat() })
                }
                toastView
                if let s = sheet {
                    StudioEditSheet(sheet: s, store: store, cache: cache, player: player, thumbs: thumbs,
                                    openStage: openStage, close: { withAnimation(.snappy(duration: 0.25)) { sheet = nil } },
                                    open: { n in withAnimation(.snappy(duration: 0.25)) { sheet = n } })
                        .transition(.move(edge: .bottom))
                        .id(s)
                }
            }
            .clipped()
        }
        .background(Color.black.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .task { await start() }
        .onChange(of: playKey) { player.update(store, cache) }
        .onChange(of: store.view?.media?.count ?? 0) { cache.fetch(store.view?.media.map { Array($0.keys) } ?? [], store: store) }
        .onChange(of: store.selected) { _, id in selected(id) }
        .onChange(of: store.toast) { _, t in showToast(t) }
        .onDisappear { player.pause() }
        .fullScreenCover(isPresented: $full) {
            StudioFullScreen(store: store, player: player, close: { full = false })
        }
        .alert("That didn't work", isPresented: Binding(get: { store.actionError != nil },
                                                       set: { if !$0 { store.actionError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(store.actionError ?? "")
        }
    }

    // MARK: parts

    private var topBar: some View {
        HStack {
            round("chevron-left", "Back", id: "studioBack") { dismiss() }
            Spacer()
            VStack(spacing: 1) {
                Text("Edit").font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.title)
                Text(store.view?.title ?? route.title).font(.system(size: 12)).foregroundStyle(Theme.secondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 22).padding(.vertical, 6)
            .background(Color(hex: 0x1C1C1E), in: Capsule())
            .overlay(Capsule().stroke(Color(hex: 0x2A2A2A), lineWidth: 1))
            .frame(maxWidth: 220)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("studioTitle")
            Spacer()
            round("message-circle", "Video chat", id: "studioChat") { openChat() }
        }
        .padding(.horizontal, 14)
        .frame(height: 54)
    }

    private func round(_ icon: String, _ label: String, id: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            LucideIcon(name: icon, size: 20).foregroundStyle(Theme.title)
                .frame(width: 42, height: 42)
                .background(Color(hex: 0x1C1C1E), in: Circle())
                .overlay(Circle().stroke(Color(hex: 0x2A2A2A), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityIdentifier(id)
    }

    /// what the picture shows: the frame at a dragged handle, or the playhead's
    private var shownTime: Double { player.peeking ?? player.time }

    private var picture: some View {
        GeometryReader { g in
            ZStack(alignment: .topLeading) {
                Color.black
                StudioEditPlayerSurface(player: player.player)
                ForEach(shownText) { s in
                    StudioOverlayText(clip: s.clip, opacity: s.opacity, width: g.size.width,
                                      selected: store.selected == s.clip.id)
                }
                if case .kenburns(let id) = sheet, StudioEdit.clip(id, in: store.model)?.kenburns != nil {
                    Text("Start → end")
                        .font(.system(size: 13, weight: .medium)).foregroundStyle(.white)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(Color.black.opacity(0.6), in: Capsule())
                        .padding(10)
                }
            }
            .clipped()
        }
        .aspectRatio(16 / 9, contentMode: .fit)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Player")
        .accessibilityIdentifier("studioPlayer")
        .overlay(alignment: .topLeading) {
            // outside the player's one accessibility element, so it can be read on its own
            if let p = player.peeking {
                Text("Frame at \(StudioEdit.clock(p))")
                    .font(.system(size: 13, weight: .medium)).foregroundStyle(.white)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Color.black.opacity(0.6), in: Capsule())
                    .padding(10)
                    .accessibilityIdentifier("studioPeek")
            }
        }
    }

    private struct Shown: Identifiable {
        let clip: StudioClip
        let opacity: Double
        var id: String { clip.id }
    }

    private var shownText: [Shown] {
        StudioPreview.overlays(at: shownTime, draft?.model ?? store.model).map { Shown(clip: $0.clip, opacity: $0.opacity) }
    }

    private var transport: some View {
        ZStack {
            HStack(spacing: 0) {
                HStack(spacing: 0) {
                    Text(StudioEdit.clock(player.time, tenths: false)).foregroundStyle(Theme.title)
                    Text(" / \(StudioEdit.clock(store.duration, tenths: false))").foregroundStyle(Theme.secondary)
                }
                .font(.system(size: 15, weight: .medium).monospacedDigit())
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("studioTime")
                Spacer()
                icon("undo-2", "Undo", id: "studioUndo", on: store.canUndo) { Task { await store.undo() } }
                icon("redo-2", "Redo", id: "studioRedo", on: store.canRedo) { Task { await store.redo() } }
                icon("scan", "Full screen", id: "studioFull", on: true) { full = true }
            }
            Button { player.toggle(duration: store.duration) } label: {
                LucideIcon(name: player.playing ? "pause" : "play", size: 22).foregroundStyle(Theme.title)
                    .frame(width: 46, height: 46)
                    .background(Color(hex: 0x1C1C1E), in: Circle())
                    .overlay(Circle().stroke(Color(hex: 0x2A2A2A), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(player.playing ? "Pause" : "Play")
            .accessibilityIdentifier("studioPlay")
        }
        .padding(.horizontal, 16)
        .frame(height: 56)
    }

    private func icon(_ name: String, _ label: String, id: String, on: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            LucideIcon(name: name, size: 20).foregroundStyle(on ? Theme.title : Theme.secondary.opacity(0.5))
                .frame(width: 40, height: 40)
        }
        .buttonStyle(.plain)
        .disabled(!on)
        .accessibilityLabel(label)
        .accessibilityIdentifier(id)
    }

    @ViewBuilder
    private var loading: some View {
        if let e = store.error {
            VStack(spacing: 10) {
                Text(e.message).font(.system(size: 15)).foregroundStyle(Theme.secondary).multilineTextAlignment(.center)
                Button("Try again") { Task { await store.load() } }.foregroundStyle(Theme.blue)
            }
            .padding(24)
        } else {
            ProgressView().tint(Theme.secondary)
        }
    }

    @ViewBuilder
    private var toastView: some View {
        if let t = shownToast {
            HStack(spacing: 12) {
                Text(t.text).font(.system(size: 14)).foregroundStyle(Theme.title).lineLimit(2)
                if t.undo {
                    Button("Undo") { Task { await store.undo() }; shownToast = nil }
                        .font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.blue)
                        .accessibilityIdentifier("studioToastUndo")
                }
                if let id = t.show {
                    Button("Show") { store.selected = id; shownToast = nil }
                        .font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.blue)
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 11)
            .background(Color(hex: 0x2A2A2C), in: Capsule())
            .padding(.bottom, 86)
            .transition(.opacity)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("studioToast")
        }
    }

    // MARK: what happens

    private var openCut: String? {
        if case .transition(let id) = sheet { return id }
        return nil
    }

    private struct PlayKey: Equatable {
        var model: StudioModel
        var mix: StudioMix
        var voice: Int
        var ready: Int
        var mixdown: Bool
    }

    private var playKey: PlayKey {
        PlayKey(model: store.model, mix: store.mix, voice: store.voice.count, ready: cache.local.count,
                mixdown: player.useMixdown)
    }

    private func start() async {
        if store.view == nil { await store.load() }
        cache.fetch(store.view?.media.map { Array($0.keys) } ?? [], store: store)
        player.update(store, cache)
        if Demo.isOn { demoStart() }
        await store.follow()
    }

    /// the screenshot tests' flags: where the playhead is, what's selected and open
    private func demoStart() {
        if let p = Self.arg("-studioAddPhoto"), let ph = store.view?.photos.first(where: { $0.id == p }) {
            let at = Self.arg("-studioTime").flatMap(Double.init) ?? 0
            var id = ""
            store.change("Added \(ph.title)") { m in id = StudioEdit.addPhoto(&m, ph, at: at); return true }
            store.selected = id
        }
        if let t = Self.arg("-studioTime").flatMap(Double.init) { player.seek(t) }
        if let s = Self.arg("-studioSelect") { store.selected = s }
        if Demo.args.contains("-studioMixdown") { player.useMixdown = true }
        guard let name = Self.arg("-studioSheet") else { return }
        let sel = store.selected ?? ""
        switch name {
        case "sounds": sheet = .sounds
        case "photo": sheet = .photo
        case "mix": sheet = .mix
        case "shots": sheet = .shots
        case "text": sheet = .text(sel)
        case "voice": sheet = .voice(sel)
        case "transition": sheet = .transition(sel)
        case "kenburns": sheet = .kenburns(sel)
        case "replace": sheet = .replace(sel)
        case "sound": sheet = .sound(sel)
        default: break
        }
        if case .transition = sheet { store.selected = nil }
        if let q = Self.arg("-studioSearch") { Task { await store.search(q) } }
    }

    /// a voice line or a text clip opens its sheet at once; another clip closes a clip's sheet
    private func selected(_ id: String?) {
        withAnimation(.snappy(duration: 0.25)) {
            guard let id else {
                if sheet?.clip != nil { sheet = nil }
                return
            }
            if id.hasPrefix("voice:") {
                sheet = .voice(id)
            } else if store.model.overlay.contains(where: { $0.id == id }) {
                sheet = .text(id)
            } else if let c = sheet?.clip, c != id {
                sheet = nil
            }
        }
    }

    private func showToast(_ t: StudioEditStore.Toast?) {
        guard let t else { return }
        withAnimation(.easeOut(duration: 0.2)) { shownToast = t }
        Task {
            try? await Task.sleep(nanoseconds: 3_500_000_000)
            if shownToast?.n == t.n { withAnimation(.easeOut(duration: 0.2)) { shownToast = nil } }
        }
    }

    /// The video's chat, with what's selected riding along (28).
    private func openChat() {
        player.pause()
        let context: String = {
            guard let id = store.selected else { return "Edit" }
            if id.hasPrefix("voice:") { return "Edit · voice line \(id.dropFirst(6)) selected" }
            let n = StudioWords.names(store.model, store.view?.log)[id] ?? id
            return "Edit · \(n) selected"
        }()
        Task {
            guard let id = await store.chatId() else { return }
            openChatRoute?(ChatRoute(id: id, context: context))
        }
    }
}

// MARK: the toolbars

/// With nothing selected: what you can add (15); with a clip selected: that clip's tools (16).
struct StudioEditToolbar: View {
    @Bindable var store: StudioEditStore
    let player: StudioPlayer
    @Binding var sheet: StudioSheet?
    var chat: () -> Void

    var body: some View {
        Group {
            if let id = store.selected, !id.hasPrefix("voice:"), let t = StudioEdit.track(of: id, in: store.model) {
                clipTools(id, t)
            } else {
                mainTools
            }
        }
        .frame(height: 76)
        .padding(.bottom, 4)
    }

    private var mainTools: some View {
        HStack(spacing: 0) {
            tool("audio-lines", "Audio", id: "toolAudio") { open(.sounds) }
            tool("type", "Text", id: "toolText") { addText() }
            tool("image", "Photo", id: "toolPhoto") { open(.photo) }
            tool("film", "Shots", id: "toolShots") { open(.shots) }
            tool("sliders-horizontal", "Mix", id: "toolMix") { open(.mix) }
            tool("message-circle", "Chat", id: "toolChat") { chat() }
        }
        .frame(maxWidth: .infinity)
    }

    private func clipTools(_ id: String, _ t: StudioTrack) -> some View {
        HStack(spacing: 0) {
            Button { store.selected = nil } label: {
                LucideIcon(name: "chevron-left", size: 22).foregroundStyle(Theme.title).frame(width: 44, height: 60)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Back to the main tools")
            .accessibilityIdentifier("toolBack")
            Rectangle().fill(Color(hex: 0x2A2A2A)).frame(width: 1, height: 40)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    switch t {
                    case .video: videoTools(id)
                    case .overlay:
                        tool("pencil", "Edit", id: "toolEdit") { open(.text(id)) }
                        tool("square-split-horizontal", "Split", id: "toolSplit") { split(id) }
                        tool("chevrons-left-right", "Trim", id: "toolTrim") { trimHint() }
                        delete(id)
                    default:
                        tool("volume-2", "Volume", id: "toolVolume") { open(.sound(id)) }
                        tool("square-split-horizontal", "Split", id: "toolSplit") { split(id) }
                        tool("chevrons-left-right", "Trim", id: "toolTrim") { trimHint() }
                        delete(id)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func videoTools(_ id: String) -> some View {
        let c = StudioEdit.clip(id, in: store.model)
        let still = c.map { !StudioEdit.isVideo(StudioEdit.source($0, store.shots).src) } ?? false
        tool("square-split-horizontal", "Split", id: "toolSplit") { split(id) }
        tool("chevrons-left-right", "Trim", id: "toolTrim") { trimHint() }
        tool("replace", "Replace", id: "toolReplace") { open(.replace(id)) }
        if still { tool("scan", "Ken Burns", id: "toolKenBurns") { open(.kenburns(id)) } }
        if store.model.video.first?.id != id {
            tool("blend", "Transition", id: "toolTransition") { open(.transition(id)) }
        }
        delete(id)
    }

    private func delete(_ id: String) -> some View {
        tool("trash-2", "Delete", id: "toolDelete", color: Theme.red) {
            let n = StudioWords.names(store.model, store.view?.log)[id] ?? id
            if store.change("Deleted \(n)", toast: true, { StudioEdit.delete(&$0, id) }) { store.selected = nil }
        }
    }

    private func tool(_ icon: String, _ label: String, id: String, color: Color = Theme.title,
                      _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                LucideIcon(name: icon, size: 24)
                Text(label).font(.system(size: 12)).lineLimit(1)
            }
            .foregroundStyle(color)
            .frame(minWidth: 62, maxWidth: .infinity)
            .frame(height: 60)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(store.readonly && !["toolChat", "toolMix", "toolShots", "toolBack"].contains(id))
        .accessibilityIdentifier(id)
    }

    private func open(_ s: StudioSheet) {
        withAnimation(.snappy(duration: 0.25)) { sheet = s }
    }

    private func split(_ id: String) {
        let at = player.time
        let n = StudioWords.names(store.model, store.view?.log)[id] ?? id
        let ok = store.change("Split \(n) at \(StudioEdit.clock(at))", toast: true) { m in
            StudioEdit.split(&m, id, at: at) != nil
        }
        if !ok { store.show("Move the playhead over the clip to split it") }
    }

    private func trimHint() {
        store.show("Drag a white handle to trim")
    }

    private func addText() {
        let at = player.time
        var id = ""
        store.change("Added text at \(StudioEdit.clock(at))") { m in
            id = StudioEdit.addText(&m, at: at)
            return true
        }
        if !id.isEmpty { store.selected = id }
    }
}

// MARK: full screen

struct StudioFullScreen: View {
    let store: StudioEditStore
    let player: StudioPlayer
    var close: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            GeometryReader { g in
                ZStack {
                    StudioEditPlayerSurface(player: player.player)
                    ForEach(StudioPreview.overlays(at: player.time, store.model).map { $0.clip }) { c in
                        StudioOverlayText(clip: c, opacity: 1, width: g.size.width)
                    }
                }
                .aspectRatio(16 / 9, contentMode: .fit)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .contentShape(Rectangle())
            .onTapGesture { player.toggle(duration: store.duration) }
            Button(action: close) {
                LucideIcon(name: "x", size: 20).foregroundStyle(.white)
                    .frame(width: 42, height: 42)
                    .background(Color.white.opacity(0.12), in: Circle())
            }
            .padding(16)
            .accessibilityLabel("Close full screen")
            .accessibilityIdentifier("studioFullClose")
        }
    }
}
