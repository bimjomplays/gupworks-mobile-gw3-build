import SwiftUI

/// a151: the health line at the top of Quick actions. One row (CPU, GPU, free space, services); a tap shows the
/// details under it.
struct PcHealthSection: View {
    let store: QuickPcStore
    @State private var open = false

    var body: some View {
        Section {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) { open.toggle() }
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("PC health").foregroundStyle(Theme.rowTitle)
                        Spacer()
                        Image(systemName: "chevron.down")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.icon)
                            .rotationEffect(.degrees(open ? 180 : 0))
                    }
                    if let line = store.health?.line, !line.isEmpty {
                        Text(Self.line(line)).font(.system(size: 13))
                            .accessibilityIdentifier("quick-health-line")
                    } else if store.state == nil && store.error == nil {
                        Text("Reading…").font(.system(size: 13)).foregroundStyle(Theme.secondary)
                    }
                    ForEach(problems, id: \.self) { e in
                        Text(e).font(.system(size: 13)).foregroundStyle(Theme.red)
                            .accessibilityIdentifier("quick-health-error")
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("quick-health")
            .accessibilityHint(open ? "Hides the details" : "Shows the details")
            if open {
                ForEach(Array((store.health?.sections ?? []).enumerated()), id: \.offset) { _, s in
                    VStack(alignment: .leading, spacing: 5) {
                        Text(s.title).font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.section)
                        ForEach(Array(s.rows.enumerated()), id: \.offset) { _, r in
                            HStack {
                                Text(r.label).font(.system(size: 14)).foregroundStyle(Theme.rowTitle)
                                Spacer()
                                Text(r.value).font(.system(size: 14)).foregroundStyle(Self.color(r.level, ok: Theme.secondary))
                            }
                        }
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("quick-health-\(s.title)")
                }
            }
        }
    }

    private var problems: [String] {
        var all = store.health?.problems ?? []
        if let e = store.error { all.append(e) }
        return all
    }

    /// "CPU 61°C · GPU 41°C · Free 920 GB / 480 GB · Services all up", the values coloured by level
    static func line(_ items: [QuickHealthItem]) -> AttributedString {
        var out = AttributedString()
        for (i, item) in items.enumerated() {
            if i > 0 {
                var dot = AttributedString("  ·  ")
                dot.foregroundColor = Theme.idleDot
                out += dot
            }
            var label = AttributedString(item.label + " ")
            label.foregroundColor = Theme.secondary
            var value = AttributedString(item.value)
            value.foregroundColor = color(item.level, ok: Theme.rowTitle)
            out += label + value
        }
        return out
    }

    static func color(_ level: String?, ok: Color) -> Color {
        switch level {
        case "bad": return Theme.red
        case "warn": return Theme.amber
        default: return ok
        }
    }
}

/// a151: Media (now playing and its controls), Volume, Open on the PC and Discord call, under the switches.
struct QuickPcSections: View {
    @Bindable var store: QuickPcStore
    @State private var level: Double = 0
    @State private var sliding = false
    @State private var link = ""
    @FocusState private var linkFocused: Bool

    var body: some View {
        Section("Media") { mediaRow }
        Section("Volume") { volumeRow }
        Section {
            openRow
        } header: {
            Text("Open on the PC")
        } footer: {
            Text("Paste a link; it opens on the PC in the browser you pick. Only http and https links.")
        }
        Section {
            discordRow
        } header: {
            Text("Discord call")
        } footer: {
            if let how = store.discord?.how, !how.isEmpty {
                Text(how + " Discord in a web browser isn't seen.")
            }
        }
    }

    // MARK: media

    private var mediaRow: some View {
        let player = store.media?.player
        let busy = store.busy.contains("media")
        return VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    if let p = player {
                        Text(p.nowPlaying).foregroundStyle(Theme.rowTitle).lineLimit(2)
                            .accessibilityIdentifier("quick-media-title")
                        Text("\(p.app ?? "Player") · \(busy ? "…" : (p.status ?? ""))")
                            .font(.system(size: 13)).foregroundStyle(Theme.secondary)
                            .accessibilityIdentifier("quick-media-detail")
                    } else {
                        Text(store.state == nil && store.error == nil ? "Reading…" : "Nothing is playing on the PC")
                            .font(.system(size: 15)).foregroundStyle(Theme.secondary)
                            .accessibilityIdentifier("quick-media-detail")
                    }
                }
                Spacer(minLength: 4)
                mediaButton("backward.fill", "Previous", "previous", on: player?.canPrevious == true && !busy)
                mediaButton(player?.playing == true ? "pause.fill" : "play.fill",
                            player?.playing == true ? "Pause" : "Play", "play-pause", on: player != nil && !busy)
                mediaButton("forward.fill", "Next", "next", on: player?.canNext == true && !busy)
            }
            errorText("media")
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("quick-media")
    }

    private func mediaButton(_ icon: String, _ name: String, _ action: String, on: Bool) -> some View {
        Button {
            Task { await store.mediaAction(action) }
        } label: {
            Image(systemName: icon).font(.system(size: 17)).frame(width: 36, height: 36)
        }
        .buttonStyle(.borderless)
        .tint(Theme.rowTitle)
        .disabled(!on)
        .accessibilityLabel(name)
        .accessibilityIdentifier("quick-media-\(action)")
    }

    // MARK: volume

    private var volumeRow: some View {
        let v = store.media?.volume
        let busy = store.busy.contains("volume")
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                Button {
                    if let v { Task { await store.setMuted(!v.muted) } }
                } label: {
                    Image(systemName: v?.muted == true ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        .font(.system(size: 16)).frame(width: 30, height: 30)
                }
                .buttonStyle(.borderless)
                .tint(v?.muted == true ? Theme.red : Theme.rowTitle)
                .disabled(v == nil || busy)
                .accessibilityLabel(v?.muted == true ? "Unmute" : "Mute")
                .accessibilityIdentifier("quick-volume-mute")
                Slider(value: $level, in: 0...1) { editing in
                    sliding = editing
                    if !editing { Task { await store.setVolume(level) } }
                }
                .tint(Theme.rowTitle)
                .disabled(v == nil)
                .accessibilityLabel("Volume")
                .accessibilityIdentifier("quick-volume-slider")
            }
            Text(v.map { sliding ? "\($0.device ?? "Default output") · \(Int((level * 100).rounded()))%" : $0.detail }
                 ?? (store.state == nil && store.error == nil ? "Reading…" : "No volume read"))
                .font(.system(size: 13)).foregroundStyle(Theme.secondary)
                .accessibilityIdentifier("quick-volume-detail")
            errorText("volume")
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("quick-volume")
        .onAppear { if let v { level = v.level } }
        .onChange(of: store.media?.volume?.level) { _, l in
            if let l, !sliding, !busy { level = l }
        }
    }

    // MARK: open on the PC

    private var openRow: some View {
        let browsers = store.browsers?.list ?? []
        let busy = store.busy.contains("open")
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                TextField("https://…", text: $link)
                    .keyboardType(.URL)
                    .textContentType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.go)
                    .focused($linkFocused)
                    .onSubmit { open() }
                    .accessibilityIdentifier("quick-open-url")
                PasteButton(payloadType: String.self) { strings in
                    guard let text = strings.first else { return }
                    Task { @MainActor in link = QuickPcText.firstLink(in: text) }
                }
                .labelStyle(.iconOnly)
                .buttonBorderShape(.circle)
                .accessibilityIdentifier("quick-open-paste")
            }
            HStack {
                Picker("Browser", selection: Binding(get: { store.browser ?? "" }, set: { store.picked = $0 })) {
                    ForEach(browsers) { b in Text(b.label).tag(b.id) }
                }
                .pickerStyle(.menu)
                .tint(Theme.rowTitle)
                .disabled(browsers.isEmpty || busy)
                .accessibilityIdentifier("quick-open-browser")
                Spacer()
                if busy { ProgressView().controlSize(.small) }
                Button("Open") { open() }
                    .buttonStyle(.bordered)
                    .tint(Theme.blue)
                    .disabled(browsers.isEmpty || busy)
                    .accessibilityIdentifier("quick-open-button")
            }
            if let note = store.openNote {
                Text(note).font(.system(size: 13)).foregroundStyle(Theme.secondary)
                    .accessibilityIdentifier("quick-open-note")
            }
            errorText("open")
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("quick-open")
    }

    private func open() {
        let text = link
        linkFocused = false
        Task {
            if await store.open(text) { link = "" }
        }
    }

    // MARK: Discord

    private var discordRow: some View {
        let d = store.discord
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                if let on = d?.inCall {
                    Circle().fill(on ? Color(hex: 0x7FD17F) : Theme.idleDot).frame(width: 9, height: 9)
                }
                Text(d.flatMap { QuickPcText.nonEmpty($0.detail) }
                     ?? (store.state == nil && store.error == nil ? "Reading…" : "Not known"))
                    .foregroundStyle(d?.inCall == true ? Theme.rowTitle : Theme.secondary)
                    .accessibilityIdentifier("quick-discord-detail")
                Spacer()
            }
            errorText("discord")
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("quick-discord")
    }

    @ViewBuilder
    private func errorText(_ row: String) -> some View {
        if let e = store.errorText(row) {
            Text(e).font(.system(size: 13)).foregroundStyle(Theme.red)
                .accessibilityIdentifier("quick-\(row)-error")
        }
    }
}
