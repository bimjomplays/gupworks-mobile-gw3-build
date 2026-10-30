import SwiftUI

// YouTube Studio on the phone (a180, docs/studio-phone-mockups 01-03): the channels, a channel's videos and a video's
// overview. The stage screens are in StudioStages.swift and StudioScript.swift; the data comes from the PC's Studio
// through gw3-phone (StudioStore in GupKit).

/// A Studio page pushed over the Studio home.
enum StudioRoute: Hashable {
    case channel(String)
    /// a video; `stage` opens one of its stages instead of the overview
    case video(String, String, stage: String?)
}

extension EnvironmentValues {
    /// pushes a Studio page (MainView's stack)
    @Entry var openStudio: ((StudioRoute) -> Void)? = nil
    /// pushes any route on MainView's stack (a181's StudioEditRoute)
    @Entry var pushRoute: ((any Hashable) -> Void)? = nil
}

/// Studio's look: the chat cards' dark boxes and the mockups' capsules.
enum StudioLook {
    static let card = ChatStyle.cardBG
    static let border = ChatStyle.cardBorder
    static let chip = Color(hex: 0x232326)
    static let chipBorder = Color(hex: 0x323236)
    static let primary = Color(hex: 0x2F6FE0)
    static let needsBG = Color(hex: 0x17152A)
    static let needsBorder = Color(hex: 0x3A3360)
    static let label = Color(hex: 0x8E8E93)

    /// "Brief" for "brief"
    static func stageName(_ key: String) -> String {
        key.prefix(1).uppercased() + key.dropFirst()
    }
}

extension View {
    /// a Studio card: the chat cards' dark box with its thin border
    func studioCard(radius: CGFloat = 18) -> some View {
        self
            .background(StudioLook.card, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).stroke(StudioLook.border, lineWidth: 1))
    }
}

/// A small capsule button (Pin, Reject, Approve #2, Redo...); `primary` is the blue one.
struct StudioButton: View {
    let title: String
    var icon: String? = nil
    var primary = false
    var busy = false
    var id: String? = nil
    var height: CGFloat = 36
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                if busy {
                    ProgressView().controlSize(.small).tint(primary ? .white : Theme.rowTitle)
                } else if let icon {
                    LucideIcon(name: icon, size: 16)
                }
                Text(title).font(.system(size: 15, weight: .medium)).lineLimit(1)
            }
            .foregroundStyle(primary ? Color.white : Theme.rowTitle)
            .padding(.horizontal, 14)
            .frame(height: height)
            .background(primary ? StudioLook.primary : Color(hex: 0x1C1C1E), in: Capsule())
            .overlay(Capsule().stroke(primary ? Color.clear : StudioLook.chipBorder, lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(busy)
        .accessibilityIdentifier(id ?? title)
    }
}

/// A grey tag (a source, "Conflict", a fact id).
struct StudioTag: View {
    let text: String
    var color: Color = Color(hex: 0xB0B0B5)
    var background: Color = Color(hex: 0x2A2A2E)

    var body: some View {
        Text(text)
            .font(.system(size: 13))
            .foregroundStyle(color)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(background, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

/// "stage 6 of 8" as eight short bars: done light, the current one blue, the rest dim.
struct StagePips: View {
    let index: Int
    let count: Int

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<max(count, 1), id: \.self) { i in
                Capsule()
                    .fill(i < index ? Color(hex: 0xC8C8CC) : i == index ? Theme.blue : Color(hex: 0x3A3A3E))
                    .frame(width: 18, height: 3)
            }
        }
        .accessibilityHidden(true)
    }
}

/// The Studio pages' top bar: back (or the menu), a pill with the title, and the chat button.
struct StudioTopBar<Pill: View>: View {
    var back: (() -> Void)? = nil
    var menu: (() -> Void)? = nil
    var menuDot = false
    var chat: (() -> Void)? = nil
    var chatDot = false
    @ViewBuilder var pill: () -> Pill

    var body: some View {
        ZStack {
            HStack {
                if let back {
                    RoundButton(label: "Back", id: "back", action: back) {
                        Image(systemName: "chevron.left").font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(Theme.rowTitle)
                    }
                } else if let menu {
                    RoundButton(label: "Menu", id: "menu", action: menu) {
                        Icons.menu().foregroundStyle(Theme.rowTitle)
                    }
                    .overlay(alignment: .topTrailing) {
                        if menuDot {
                            Circle().fill(Theme.violet).frame(width: 9, height: 9)
                                .overlay(Circle().stroke(Color(hex: 0x161616), lineWidth: 2))
                                .offset(x: -8, y: 9)
                        }
                    }
                }
                Spacer()
                if let chat {
                    RoundButton(label: "Video chat", id: "videoChat", action: chat) {
                        LucideIcon(name: "message-circle", size: 21).foregroundStyle(Theme.rowTitle)
                    }
                    .overlay(alignment: .topTrailing) {
                        if chatDot {
                            Circle().fill(Theme.violet).frame(width: 8, height: 8).offset(x: -9, y: 9)
                        }
                    }
                    .accessibilityValue(chatDot ? "Needs you" : "")
                }
            }
            pill().frame(maxWidth: 220)
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
        .padding(.bottom, 8)
    }
}

/// The pill in the middle: a title over a small grey line ("Script" over "Buchanan").
struct StudioPill: View {
    let title: String
    var subtitle: String? = nil

    var body: some View {
        VStack(spacing: 0) {
            Text(title).font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.title)
            if let subtitle {
                Text(subtitle).font(.system(size: 12)).foregroundStyle(StudioLook.label)
            }
        }
        .lineLimit(1)
        .padding(.horizontal, 20)
        .frame(height: 44)
        .glassEffect(.regular, in: .capsule)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
        .accessibilityIdentifier("studioPill")
    }
}

/// A short line in the middle of an empty or broken page.
struct StudioNote: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 15))
            .foregroundStyle(Theme.secondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 30)
            .padding(.vertical, 40)
    }
}

/// A violet "<video> needs you" line or a blue spinner line under a card.
struct StudioStateLine: View {
    let text: String
    var working = false

    var body: some View {
        HStack(spacing: 6) {
            if working {
                Spinner().scaleEffect(0.8)
            } else {
                Circle().fill(Theme.violet).frame(width: 7, height: 7)
            }
            Text(text).font(.system(size: 14)).lineLimit(1)
        }
        .foregroundStyle(working ? Theme.blue : Theme.violetText)
    }
}

// MARK: - 01 Channels

/// 01: the Studio home, one card per channel with its latest covers, what needs you and what's working.
struct StudioHomePage: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openStudio) private var openStudio
    let openMenu: () -> Void
    @State private var store: StudioStore?
    @State private var searching = false
    @State private var query = ""
    @State private var newChannel = false

    var body: some View {
        VStack(spacing: 0) {
            StudioTopBar(menu: openMenu, menuDot: model.needsYou) { EmptyView() }
                .overlay(alignment: .trailing) {
                    RoundButton(label: "Search", id: "studioSearch", action: {
                        withAnimation(.snappy(duration: 0.2)) {
                            searching.toggle()
                            if !searching { query = "" }
                        }
                    }) {
                        LucideIcon(name: searching ? "x" : "search", size: 20).foregroundStyle(Theme.rowTitle)
                    }
                    .padding(.trailing, 16)
                    .padding(.bottom, 4)
                }
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Studio")
                        .font(.system(size: 32, weight: .bold))
                        .foregroundStyle(Theme.title)
                        .accessibilityAddTraits(.isHeader)
                        .padding(.horizontal, 4)
                    if searching {
                        TextField("", text: $query, prompt: Text("Search channels and videos").foregroundStyle(SheetStyle.optional))
                            .font(.system(size: 17))
                            .foregroundStyle(Theme.rowTitle)
                            .autocorrectionDisabled()
                            .padding(.horizontal, 16)
                            .frame(height: 46)
                            .background(Color(hex: 0x161616), in: Capsule())
                            .overlay(Capsule().stroke(Color(hex: 0x262626), lineWidth: 1))
                            .accessibilityIdentifier("studioQuery")
                    }
                    content
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 90)
            }
            .refreshable { await store?.refresh() }
        }
        .overlay(alignment: .bottomTrailing) {
            Button { newChannel = true } label: {
                HStack(spacing: 9) {
                    LucideIcon(name: "plus", size: 22)
                    Text("New channel").font(.system(size: 17, weight: .semibold))
                }
                .foregroundStyle(.white)
                .padding(.leading, 18)
                .padding(.trailing, 22)
                .frame(height: 50)
                .background(StudioLook.primary, in: Capsule())
            }
            .buttonStyle(.plain)
            .padding(.trailing, 20)
            .padding(.bottom, 8)
            .accessibilityIdentifier("newChannel")
        }
        .background(Theme.background)
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $newChannel) {
            if let store {
                StudioNewChannelSheet(store: store) { pid in
                    Task {
                        try? await Task.sleep(nanoseconds: 450_000_000)
                        openStudio?(.channel(pid))
                    }
                }
            }
        }
        .alert("That didn't work", isPresented: Binding(get: { store?.actionError != nil },
                                                       set: { if !$0 { store?.actionError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(store?.actionError ?? "")
        }
        .task {
            if store == nil { store = StudioStore(pairing: model.pairing, demo: model.demo) }
            guard let store else { return }
            await store.follow(every: 6) { await store.refresh() }
        }
    }

    @ViewBuilder
    private var content: some View {
        if let home = store?.home {
            let rows = shown(home.channels)
            if rows.isEmpty {
                StudioNote(text: home.channels.isEmpty ? "No Studio channels yet. New channel starts one."
                                                      : "No channel has that name.")
            }
            ForEach(rows) { c in
                Button { openStudio?(.channel(c.projectId)) } label: {
                    StudioChannelCard(row: c, base: store?.baseURL)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("channel-\(c.projectId)")
            }
        } else if let e = store?.error {
            StudioNote(text: e.message)
        } else {
            ProgressView().frame(maxWidth: .infinity).padding(.vertical, 40)
        }
    }

    private func shown(_ rows: [StudioChannelRow]) -> [StudioChannelRow] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard searching, !q.isEmpty else { return rows }
        return rows.filter { r in
            r.name.lowercased().contains(q) || r.latest.contains { $0.lowercased().contains(q) }
        }
    }
}

/// One channel on 01: up to three covers, its tile and name, what it holds, and what needs you or works.
struct StudioChannelCard: View {
    let row: StudioChannelRow
    let base: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !row.covers.isEmpty {
                covers
                    .frame(height: 150)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .padding([.horizontal, .top], 10)
            }
            HStack(alignment: .top, spacing: 12) {
                ProjectTile(icon: row.icon, color: row.color, size: 28, iconSize: 16, radius: 8).padding(.top, 2)
                VStack(alignment: .leading, spacing: 4) {
                    Text(row.name).font(.system(size: 18, weight: .semibold)).foregroundStyle(Theme.title)
                    Text(holds).font(.system(size: 14)).foregroundStyle(StudioLook.label).lineLimit(1)
                    states
                }
                Spacer(minLength: 0)
            }
            .padding(14)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .studioCard()
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private var holds: String {
        var parts: [String] = []
        if row.longVideos > 0 { parts.append(Format.plural(row.longVideos, "long video")) }
        if row.shorts > 0 { parts.append(Format.plural(row.shorts, "Short")) }
        if parts.isEmpty { parts = row.latest.prefix(2).map { $0 } }
        if parts.isEmpty { parts.append(row.about.isEmpty ? "No videos yet" : row.about) }
        parts.append("Style guide")
        return parts.joined(separator: " \u{00B7} ")
    }

    @ViewBuilder
    private var states: some View {
        if let n = row.needs.first {
            HStack(spacing: 14) {
                StudioStateLine(text: "\(n.title) needs you")
                if row.working > 0 { StudioStateLine(text: "\(row.working) working", working: true) }
            }
            .padding(.top, 2)
        } else if row.working > 0 {
            StudioStateLine(text: "\(row.working) working", working: true).padding(.top, 2)
        } else {
            Text("All done \u{00B7} changed \(Format.ago(row.updated, now: Date()).replacingOccurrences(of: "Yesterday", with: "yesterday"))")
                .font(.system(size: 14)).foregroundStyle(StudioLook.label).padding(.top, 2)
        }
    }

    @ViewBuilder
    private var covers: some View {
        let urls = row.covers.prefix(3).map { MediaLink.url($0, base: base) }
        if urls.count >= 3 {
            HStack(spacing: 3) {
                RemoteImage(url: urls[0], fill: true).frame(maxWidth: .infinity, maxHeight: .infinity).clipped()
                VStack(spacing: 3) {
                    RemoteImage(url: urls[1], fill: true).frame(maxWidth: .infinity, maxHeight: .infinity).clipped()
                    RemoteImage(url: urls[2], fill: true).frame(maxWidth: .infinity, maxHeight: .infinity).clipped()
                }
                .frame(width: 122)
            }
        } else {
            HStack(spacing: 3) {
                ForEach(Array(urls.enumerated()), id: \.offset) { _, u in
                    RemoteImage(url: u, fill: true).frame(maxWidth: .infinity, maxHeight: .infinity).clipped()
                }
            }
        }
    }
}

/// New channel: a name and what it's about; the PC makes the Studio project with its videos folder and style guide.
struct StudioNewChannelSheet: View {
    let store: StudioStore
    let created: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var about = ""
    @State private var creating = false
    @FocusState private var focused: Bool

    private var ready: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty && !creating && !store.demo }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                SheetLabel(text: "Name")
                TextField("", text: $name, prompt: Text("Channel name\u{2026}").foregroundStyle(SheetStyle.optional))
                    .font(.system(size: 17))
                    .foregroundStyle(Theme.rowTitle)
                    .focused($focused)
                    .padding(.horizontal, 18)
                    .frame(minHeight: 56)
                    .background(SheetStyle.field, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
                    .accessibilityIdentifier("channelName")
                SheetLabel(text: "About", optional: true)
                TextField("", text: $about, prompt: Text("Calm, sourced true crime").foregroundStyle(SheetStyle.optional),
                          axis: .vertical)
                    .lineLimit(2...5)
                    .font(.system(size: 17))
                    .foregroundStyle(Theme.rowTitle)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 15)
                    .background(SheetStyle.field, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .accessibilityIdentifier("channelAbout")
                Spacer()
            }
            .padding(.horizontal, 16)
            .background(SheetStyle.background)
            .navigationTitle("New channel")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel("Close")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    SheetDoneButton(on: ready, busy: creating, id: "createChannel", label: "Create") {
                        creating = true
                        Task {
                            let pid = await store.newChannel(name: name, about: about)
                            creating = false
                            if let pid {
                                dismiss()
                                created(pid)
                            }
                        }
                    }
                }
            }
        }
        .presentationDetents([.medium])
        .presentationBackground(SheetStyle.background)
        .task { focused = true }
    }
}

// MARK: - 02 Channel

/// 02: a channel's videos as cards (stage, state, running work), its Shorts in a row, New video; and its style guide.
struct StudioChannelPage: View {
    let projectId: String
    @Environment(AppModel.self) private var model
    @Environment(\.openStudio) private var openStudio
    @Environment(\.openChat) private var openChat
    @Environment(\.dismiss) private var dismiss
    @State private var store: StudioStore?
    @State private var tab = 0
    @State private var newVideo = false

    var body: some View {
        let channel = store?.channels[projectId]
        VStack(spacing: 0) {
            StudioTopBar(back: { dismiss() },
                         chat: channel?.row.mainChatId.map { id in { openChat?(id) } }) {
                HStack(spacing: 9) {
                    ProjectTile(icon: channel?.row.icon, color: channel?.row.color, size: 30, iconSize: 17, radius: 15)
                    Text(channel?.row.name ?? "Channel").font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Theme.title).lineLimit(1)
                }
                .padding(.leading, 7)
                .padding(.trailing, 18)
                .frame(height: 44)
                .glassEffect(.regular, in: .capsule)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("studioPill")
            }
            tabs
            ScrollView {
                if let channel {
                    if tab == 0 { videos(channel) } else { styleGuide(channel) }
                } else if let e = store?.error {
                    StudioNote(text: e.message)
                } else {
                    ProgressView().frame(maxWidth: .infinity).padding(.vertical, 40)
                }
            }
            .refreshable { await store?.refresh(channel: projectId) }
        }
        .overlay(alignment: .bottomTrailing) {
            if tab == 0 {
                Button { newVideo = true } label: {
                    HStack(spacing: 9) {
                        LucideIcon(name: "plus", size: 22)
                        Text("New video").font(.system(size: 17, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.leading, 18)
                    .padding(.trailing, 22)
                    .frame(height: 50)
                    .background(StudioLook.primary, in: Capsule())
                }
                .buttonStyle(.plain)
                .padding(.trailing, 20)
                .padding(.bottom, 8)
                .accessibilityIdentifier("newVideo")
            }
        }
        .background(Theme.background)
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $newVideo) {
            if let store {
                StudioNewVideoSheet(store: store, projectId: projectId) { card in
                    Task {
                        try? await Task.sleep(nanoseconds: 450_000_000)
                        openStudio?(.video(projectId, card.id, stage: nil))
                    }
                }
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
                store = StudioStore(pairing: model.pairing, demo: model.demo)
                if Demo.isOn && Demo.args.contains("-styleGuide") { tab = 1 }
            }
            guard let store else { return }
            let pid = projectId
            await store.follow(every: 6) { await store.refresh(channel: pid) }
        }
    }

    private var tabs: some View {
        HStack(spacing: 2) {
            tabButton("Videos", 0)
            tabButton("Style guide", 1)
        }
        .padding(3)
        .glassEffect(.regular, in: .capsule)
        .padding(.bottom, 10)
    }

    private func tabButton(_ title: String, _ i: Int) -> some View {
        Button { withAnimation(.snappy(duration: 0.2)) { tab = i } } label: {
            Text(title)
                .font(.system(size: 15, weight: tab == i ? .semibold : .regular))
                .foregroundStyle(tab == i ? Color.black : Theme.rowTitle)
                .padding(.horizontal, 18)
                .frame(height: 34)
                .background(tab == i ? Color(hex: 0xF0F0F0) : .clear, in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(tab == i ? .isSelected : [])
        .accessibilityIdentifier("tab-\(title)")
    }

    private func videos(_ c: StudioChannel) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if c.videos.isEmpty && c.shortsList.isEmpty {
                StudioNote(text: "No videos yet. New video starts one.")
            }
            ForEach(c.videos) { v in
                Button { openStudio?(.video(projectId, v.id, stage: nil)) } label: {
                    StudioVideoCard(card: v, base: store?.baseURL)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("video-\(v.id)")
            }
            if !c.shortsList.isEmpty {
                HStack {
                    Text("Shorts")
                    Spacer()
                    Text("\(c.shortsList.count)")
                }
                .font(.system(size: 15))
                .foregroundStyle(StudioLook.label)
                .padding(.horizontal, 4)
                .padding(.top, 8)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 10) {
                        ForEach(c.shortsList) { s in
                            Button { openStudio?(.video(projectId, s.id, stage: nil)) } label: {
                                StudioShortTile(card: s, base: store?.baseURL)
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("short-\(s.id)")
                        }
                    }
                }
                .scrollClipDisabled()
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 90)
    }

    private func styleGuide(_ c: StudioChannel) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if c.styleGuide.text.isEmpty {
                StudioNote(text: "This channel has no style guide yet.")
            } else {
                MarkdownView(blocks: c.styleGuide.blocks ?? DemoProject.blocks(c.styleGuide.text), base: store?.baseURL)
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .studioCard()
                Text(c.styleGuide.path)
                    .font(.system(size: 13))
                    .foregroundStyle(StudioLook.label)
                    .padding(.horizontal, 4)
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 30)
        .accessibilityIdentifier("styleGuide")
    }
}

/// A long video on 02: its cover with the length, title, stage with its bars, and what runs or needs you.
struct StudioVideoCard: View {
    let card: StudioCard
    let base: URL?

    var body: some View {
        if let cover = card.cover {
            VStack(alignment: .leading, spacing: 0) {
                RemoteImage(url: MediaLink.url(cover, base: base), fill: true)
                    .frame(maxWidth: .infinity)
                    .aspectRatio(16 / 9, contentMode: .fit)
                    .clipped()
                    .overlay(alignment: .bottomTrailing) {
                        if let d = card.duration {
                            Text(d)
                                .font(.system(size: 13, weight: .medium)).monospacedDigit()
                                .foregroundStyle(.white)
                                .padding(.horizontal, 7).padding(.vertical, 3)
                                .background(Color.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 6))
                                .padding(10)
                        }
                    }
                VStack(alignment: .leading, spacing: 6) {
                    Text(card.title).font(.system(size: 18, weight: .semibold)).foregroundStyle(Theme.title)
                    HStack {
                        Text("\(card.stageName) \u{00B7} stage \(card.stageIndex + 1) of \(card.stages)")
                            .font(.system(size: 14)).foregroundStyle(Theme.rowTitle)
                        Spacer()
                        StagePips(index: card.stageIndex, count: card.stages)
                    }
                    lines
                }
                .padding(14)
            }
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .studioCard()
            .accessibilityElement(children: .combine)
        } else {
            HStack(alignment: .top, spacing: 12) {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(hex: 0x111113))
                    .overlay(LucideIcon(name: "film", size: 22).foregroundStyle(Color(hex: 0x55555A)))
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(StudioLook.border, lineWidth: 1))
                    .frame(width: 110, height: 66)
                VStack(alignment: .leading, spacing: 4) {
                    Text(card.title).font(.system(size: 17, weight: .semibold)).foregroundStyle(Theme.title).lineLimit(2)
                    Text("\(card.stageName) \u{00B7} stage \(card.stageIndex + 1) of \(card.stages)")
                        .font(.system(size: 14)).foregroundStyle(StudioLook.label)
                    lines
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .studioCard()
            .accessibilityElement(children: .combine)
        }
    }

    @ViewBuilder
    private var lines: some View {
        let working = card.working ?? card.jobs.first.map { "\($0.title) \u{00B7} \($0.id)" }
        if working != nil || card.needs != nil {
            HStack {
                if let working { StudioStateLine(text: working, working: true) }
                Spacer(minLength: 8)
                if card.needs != nil { StudioStateLine(text: "Needs you") }
            }
        }
    }
}

/// A Short on 02: its 9:16 cover, title and stage.
struct StudioShortTile: View {
    let card: StudioCard
    let base: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Group {
                if let cover = card.cover {
                    RemoteImage(url: MediaLink.url(cover, base: base), fill: true)
                } else {
                    Color(hex: 0x111113).overlay(LucideIcon(name: "smartphone", size: 20).foregroundStyle(Color(hex: 0x55555A)))
                }
            }
            .frame(width: 66, height: 117)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(StudioLook.border, lineWidth: 1))
            .overlay(alignment: .topTrailing) {
                if card.needs != nil { Circle().fill(Theme.violet).frame(width: 9, height: 9).padding(6) }
            }
            Text(card.title).font(.system(size: 14)).foregroundStyle(Theme.title).lineLimit(1).padding(.top, 4)
            Text(card.stageName).font(.system(size: 12)).foregroundStyle(StudioLook.label)
        }
        .frame(width: 70, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// New video: long or Short, and a working title; opens the new video's overview.
struct StudioNewVideoSheet: View {
    let store: StudioStore
    let projectId: String
    let created: (StudioCard) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var kind = "long"
    @State private var creating = false
    @FocusState private var focused: Bool

    private var ready: Bool { !title.trimmingCharacters(in: .whitespaces).isEmpty && !creating }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Kind", selection: $kind) {
                    Text("Long video").tag("long")
                    Text("Short").tag("short")
                }
                .pickerStyle(.segmented)
                .padding(.top, 14)
                .accessibilityIdentifier("videoKind")
                SheetLabel(text: "Working title")
                TextField("", text: $title, prompt: Text("The Bell Witch").foregroundStyle(SheetStyle.optional))
                    .font(.system(size: 17))
                    .foregroundStyle(Theme.rowTitle)
                    .focused($focused)
                    .submitLabel(.done)
                    .onSubmit { if ready { create() } }
                    .padding(.horizontal, 18)
                    .frame(minHeight: 56)
                    .background(SheetStyle.field, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
                    .accessibilityIdentifier("videoTitle")
                Spacer()
            }
            .padding(.horizontal, 16)
            .background(SheetStyle.background)
            .navigationTitle("New video")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel("Close")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    SheetDoneButton(on: ready, busy: creating, id: "createVideo", label: "Create") { create() }
                }
            }
        }
        .presentationDetents([.medium])
        .presentationBackground(SheetStyle.background)
        .task { focused = true }
    }

    private func create() {
        creating = true
        Task {
            let card = await store.newVideo(in: projectId, title: title, kind: kind)
            creating = false
            if let card {
                dismiss()
                created(card)
            }
        }
    }
}
