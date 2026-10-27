import AVFoundation
import ImageIO
import Photos
import PhotosUI
import QuickLook
import SwiftUI
import UniformTypeIdentifiers

// File transfer (a144): a plain chat between this iPhone and the PC, no AI. The phone's own messages sit on the
// right in blue, the PC's on the left, like a chat with "My PC"; a glass pill at the top switches to the Library
// (every photo and video as a grid, other files as a list, newest first). Pictures open in the photo viewer, videos
// in the video player; other files download and open in Quick Look (Save to Files from its share button). Files from
// here go up in pieces in the background with their progress on the bubble (TransferStore).

struct TransferPage: View {
    let openMenu: () -> Void
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var phase
    @State private var tab: Tab
    @State private var opener = TransferOpener()
    @State private var position = ScrollPosition(edge: .bottom)
    @State private var atBottom = true
    @State private var jump: String?
    @Namespace private var pill

    enum Tab: String, CaseIterable {
        case chat, library
        var title: String { self == .chat ? "Chat" : "Library" }
    }

    init(openMenu: @escaping () -> Void) {
        self.openMenu = openMenu
        _tab = State(initialValue: Demo.isOn && Demo.args.contains("-library") ? .library : .chat)
    }

    private var store: TransferStore { model.transfer }
    private var base: URL? { model.pairing?.baseURL }

    var body: some View {
        Group {
            switch tab {
            case .chat: chat
            case .library:
                TransferLibraryView(store: store, opener: opener) { id in
                    jump = id
                    withAnimation(.snappy(duration: 0.25)) { tab = .chat }
                }
            }
        }
        .background(Theme.background)
        .navigationBarBackButtonHidden(true)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackgroundVisibility(.hidden, for: .navigationBar)
        .scrollEdgeEffectHidden(true, for: .top)
        .overlay(alignment: .top) { TopDim() }
        .overlay(alignment: .bottom) { toast }
        .toolbar { toolbar }
        .task(id: phase == .active) {
            if phase == .active { await store.run() }
        }
        .onAppear { opener.base = base }
        .onChange(of: base) { _, now in opener.base = now }
        .fullScreenCover(item: $opener.media) { o in
            MediaViewer(open: o, base: base, source: opener.source)
        }
        .quickLookPreview($opener.preview)
        .alert("That didn't work", isPresented: Binding(get: { opener.problem != nil || store.actionError != nil },
                                                       set: { if !$0 { opener.problem = nil; store.actionError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(opener.problem ?? store.actionError ?? "")
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button(action: openMenu) {
                Icons.menu()
                    .foregroundStyle(Theme.rowTitle)
                    .overlay(alignment: .topTrailing) {
                        if model.needsYou {
                            Circle().fill(Theme.violet).frame(width: 9, height: 9).offset(x: 3, y: -1)
                        }
                    }
            }
            .accessibilityLabel("Menu")
            .accessibilityIdentifier("menu")
        }
        ToolbarItem(placement: .principal) {
            HStack(spacing: 2) {
                ForEach(Tab.allCases, id: \.self) { t in
                    Button {
                        withAnimation(.snappy(duration: 0.25)) { tab = t }
                    } label: {
                        Text(t.title)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(tab == t ? Theme.title : Theme.secondary)
                            .padding(.horizontal, 18)
                            .frame(height: 36)
                            .background {
                                if tab == t {
                                    Capsule().fill(Color.white.opacity(0.14)).matchedGeometryEffect(id: "tab", in: pill)
                                }
                            }
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("tab-\(t.rawValue)")
                    .accessibilityAddTraits(tab == t ? .isSelected : [])
                }
            }
            .padding(.horizontal, 4)
            .frame(height: 44)
            .glassEffect(.regular.interactive(), in: .capsule)
        }
        .sharedBackgroundVisibility(.hidden)
    }

    @ViewBuilder
    private var toast: some View {
        if let t = opener.toast {
            Label(t, systemImage: "checkmark")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Theme.title)
                .padding(.horizontal, 18)
                .frame(height: 44)
                .glassEffect(.regular, in: .capsule)
                .padding(.bottom, tab == .chat ? 110 : 30)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
                .accessibilityIdentifier("transferToast")
        }
    }

    // MARK: the chat

    private var chat: some View {
        ScrollViewReader { reader in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if store.more || store.loadingOlder {
                        ProgressView().frame(maxWidth: .infinity).padding(.vertical, 16)
                    }
                    let lines = TransferLayout.timeLines(store.messages)
                    ForEach(Array(store.messages.enumerated()), id: \.element.id) { i, m in
                        if lines.contains(m.id) {
                            TimeLine(ms: m.ts)
                        }
                        TransferBubble(message: m, opener: opener)
                            .padding(.top, lines.contains(m.id) ? 0 :
                                        TransferLayout.spacing(m, after: i > 0 ? store.messages[i - 1] : nil))
                            .id(m.id)
                    }
                    ForEach(store.outbox) { o in
                        OutboxBubble(message: o, store: store)
                            .padding(.top, store.messages.last?.mine == false ? 14 : 4)
                    }
                    footer
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 12)
            }
            .defaultScrollAnchor(.bottom)
            .scrollPosition($position)
            .onScrollGeometryChange(for: Bool.self) { g in
                g.contentOffset.y + g.contentInsets.top < 300
            } action: { _, nearTop in
                if nearTop { Task { await store.loadOlder() } }
            }
            .onScrollGeometryChange(for: Bool.self) { g in
                g.contentOffset.y + g.containerSize.height - g.contentInsets.bottom >= g.contentSize.height - 120
            } action: { _, bottom in
                atBottom = bottom
            }
            .onChange(of: store.messages.isEmpty) { _, empty in
                guard !empty, jump == nil else { return }
                position.scrollTo(edge: .bottom)
                Task {
                    try? await Task.sleep(nanoseconds: 300_000_000)
                    position.scrollTo(edge: .bottom)
                }
            }
            .onChange(of: store.outbox.count) { old, new in
                if new > old { withAnimation(.easeOut(duration: 0.25)) { position.scrollTo(edge: .bottom) } }
            }
            .onChange(of: store.liveTick) {
                if atBottom { withAnimation(.easeOut(duration: 0.25)) { position.scrollTo(edge: .bottom) } }
            }
            .task(id: jump) {
                // the Library's "Show in chat": to that message once the chat is on screen
                guard let id = jump else { return }
                try? await Task.sleep(nanoseconds: 150_000_000)
                withAnimation(.easeOut(duration: 0.25)) { reader.scrollTo(id, anchor: .center) }
                jump = nil
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Theme.background)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                TransferComposer(store: store)
            }
            .environment(\.chatPhotos, opener.chatSource(store))
        }
    }

    @ViewBuilder
    private var footer: some View {
        if let e = store.error {
            TransferNotice(icon: "exclamationmark.triangle",
                           text: e.isUnreachable ? "Reconnecting\u{2026} " + e.message : e.message)
        } else if !store.loaded {
            ProgressView().frame(maxWidth: .infinity).padding(.vertical, 40)
        } else if store.messages.isEmpty && store.outbox.isEmpty {
            TransferNotice(icon: "arrow.up.arrow.down",
                           text: "Photos, videos, files and notes you send here land on your PC in "
                               + (store.folder ?? "GupWorks Transfer") + "; what the PC sends shows up here.")
                .padding(.top, 40)
        }
    }
}

/// "Today 9:41 PM" between messages: before the first, after a half-hour gap and at a new day
private struct TimeLine: View {
    let ms: Double

    var body: some View {
        Text(Format.dayTime(ms))
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(ChatStyle.faint)
            .frame(maxWidth: .infinity)
            .padding(.top, 18)
            .padding(.bottom, 8)
            .accessibilityIdentifier("timeLine")
    }
}

private struct TransferNotice: View {
    let icon: String
    let text: String

    var body: some View {
        Label(text, systemImage: icon)
            .font(.subheadline)
            .foregroundStyle(ChatStyle.dim)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 20)
            .accessibilityIdentifier("transferNotice")
    }
}

// MARK: - opening, saving and sharing

/// What a tap or a long press on a file does: pictures in the photo viewer, videos in the video player, other files
/// downloaded (with progress) and opened in Quick Look; Save to Photos and Share from the long-press menu.
@Observable
@MainActor
final class TransferOpener {
    var base: URL?
    var media: MediaOpen?
    var source: PhotoSource?
    var preview: URL?
    var problem: String?
    var toast: String?
    /// downloads in flight, 0...1, by "<message id>/<index>"
    private(set) var progress: [String: Double] = [:]
    @ObservationIgnored private var done: [String: URL] = [:]
    @ObservationIgnored private var watching: [String: NSKeyValueObservation] = [:]
    @ObservationIgnored private var toastTask: Task<Void, Never>?
    @ObservationIgnored private let session: URLSession = {
        let c = URLSessionConfiguration.default
        c.timeoutIntervalForRequest = 60
        c.timeoutIntervalForResource = 6 * 3600
        c.urlCache = nil
        return URLSession(configuration: c)
    }()

    /// the chat's pictures for the viewer, oldest first
    func chatSource(_ store: TransferStore) -> PhotoSource {
        PhotoSource(photos: {
            store.messages.flatMap { m in
                m.files.enumerated().compactMap { i, f in
                    f.kind == "image" && f.there ? ChatPhoto(id: "\(m.id)/\(i)", link: f.url ?? "", mine: m.mine) : nil
                }
            }
        }, more: { store.more }, loadOlder: { await store.loadOlder() })
    }

    /// the Library's pictures, oldest first like the chat's
    func librarySource(_ store: TransferStore) -> PhotoSource {
        PhotoSource(photos: {
            (store.library?.media ?? []).reversed().compactMap { it in
                it.kind == "image" ? ChatPhoto(id: it.id, link: it.url ?? "", mine: it.mine) : nil
            }
        }, more: { false }, loadOlder: {})
    }

    func open(_ f: TransferFile, key: String, source: PhotoSource?) {
        guard f.there else { return }
        switch f.kind {
        case "image":
            let item = MDItem(kind: "image", url: f.url, name: f.name)
            self.source = source
            media = MediaOpen.picture(item, id: key, source: source)
        case "video":
            self.source = nil
            media = MediaOpen(item: MDItem(kind: "video", url: f.url, name: f.name, poster: f.poster))
        default:
            Task {
                if let u = await local(f, key: key) { preview = u }
            }
        }
    }

    func share(_ f: TransferFile, key: String) {
        Task {
            if let u = await local(f, key: key) { ShareSheet.present([u]) }
        }
    }

    func saveToPhotos(_ f: TransferFile, key: String) {
        Task {
            guard let u = await local(f, key: key) else { return }
            let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
            guard status == .authorized || status == .limited else {
                problem = "GupWorks can't add to your photos. Allow it in Settings › GupWorks › Photos."
                return
            }
            let video = f.kind == "video"
            do {
                try await PHPhotoLibrary.shared().performChanges {
                    if video {
                        PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: u)
                    } else {
                        PHAssetChangeRequest.creationRequestForAssetFromImage(atFileURL: u)
                    }
                }
                show("Saved to Photos")
            } catch {
                problem = "\(f.name) couldn't be saved to Photos."
            }
        }
    }

    func show(_ text: String) {
        toastTask?.cancel()
        withAnimation(.easeOut(duration: 0.2)) { toast = text }
        toastTask = Task {
            try? await Task.sleep(nanoseconds: 1_800_000_000)
            if Task.isCancelled { return }
            withAnimation(.easeIn(duration: 0.2)) { toast = nil }
        }
    }

    /// The file on this phone: downloaded once into the caches (by its message and place), named as it was sent.
    func local(_ f: TransferFile, key: String) async -> URL? {
        if let u = done[key], FileManager.default.fileExists(atPath: u.path) { return u }
        guard progress[key] == nil else { return nil }  // already on its way
        guard let src = MediaLink.url(f.url, base: base) else {
            problem = "\(f.name) isn't on the PC anymore."
            return nil
        }
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let dir = caches.appendingPathComponent("Transfer", isDirectory: true)
            .appendingPathComponent(key.replacingOccurrences(of: "/", with: "-"), isDirectory: true)
        let dest = dir.appendingPathComponent(f.name.replacingOccurrences(of: "/", with: "-"))
        if FileManager.default.fileExists(atPath: dest.path) {
            done[key] = dest
            return dest
        }
        progress[key] = 0
        defer {
            progress[key] = nil
            watching[key] = nil
        }
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            if src.isFileURL {
                try FileManager.default.copyItem(at: src, to: dest)
            } else {
                let got = try await download(src, key: key)
                try FileManager.default.moveItem(at: got, to: dest)
            }
            done[key] = dest
            return dest
        } catch {
            problem = "\(f.name) couldn't be downloaded. " + APIError.from(error).message
            return nil
        }
    }

    private func download(_ src: URL, key: String) async throws -> URL {
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<URL, Error>) in
            let task = session.downloadTask(with: src) { url, response, error in
                if let error {
                    c.resume(throwing: error)
                    return
                }
                guard let url, (response as? HTTPURLResponse)?.statusCode == 200 else {
                    c.resume(throwing: APIError.server("The PC didn't send the file."))
                    return
                }
                // the system deletes its copy when this returns
                let keep = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
                do {
                    try FileManager.default.moveItem(at: url, to: keep)
                    c.resume(returning: keep)
                } catch {
                    c.resume(throwing: error)
                }
            }
            watching[key] = task.progress.observe(\.fractionCompleted) { [weak self] p, _ in
                let v = p.fractionCompleted
                Task { @MainActor in
                    if self?.progress[key] != nil { self?.progress[key] = v }
                }
            }
            task.resume()
        }
    }

    func downloading(_ key: String) -> Double? { progress[key] }
}

/// The long-press menu of a file: Save to Photos (pictures and videos), Share, and in the Library Show in chat.
private struct FileMenu: View {
    let file: TransferFile
    let key: String
    let opener: TransferOpener
    var showInChat: (() -> Void)? = nil

    var body: some View {
        if file.isMedia {
            Button("Save to Photos", systemImage: "square.and.arrow.down") { opener.saveToPhotos(file, key: key) }
        }
        Button(file.isMedia ? "Share\u{2026}" : "Share or save\u{2026}", systemImage: "square.and.arrow.up") {
            opener.share(file, key: key)
        }
        if let showInChat {
            Button("Show in chat", systemImage: "bubble.left.and.text.bubble.right", action: showInChat)
        }
    }
}

// MARK: - a message

/// One message: its pictures and videos as tiles, other files as cards, then the words in a bubble; the phone's on
/// the right in blue, the PC's on the left in grey.
struct TransferBubble: View {
    let message: TransferMessage
    let opener: TransferOpener
    @Environment(\.chatPhotos) private var photos

    private var mine: Bool { message.mine }
    private var side: Alignment { mine ? .trailing : .leading }

    var body: some View {
        let indexed = Array(message.files.enumerated())
        let media = indexed.filter { $0.element.isMedia && $0.element.there }
        let others = indexed.filter { !($0.element.isMedia && $0.element.there) }
        VStack(alignment: mine ? .trailing : .leading, spacing: 6) {
            if !media.isEmpty {
                PhotoGrid(tile: media.count == 1 ? 230 : media.count == 2 ? 150 : 110, leading: !mine) {
                    ForEach(media, id: \.offset) { i, f in
                        let key = "\(message.id)/\(i)"
                        Button { opener.open(f, key: key, source: photos) } label: {
                            PhotoTile { MediaThumb(file: f, base: opener.base) }
                        }
                        .buttonStyle(.plain)
                        .contextMenu { FileMenu(file: f, key: key, opener: opener) }
                        .accessibilityLabel((f.kind == "video" ? "Video " : "Picture ") + f.name)
                        .accessibilityIdentifier(f.kind == "video" ? "transferVideo" : "transferPicture")
                    }
                }
                .padding(mine ? .leading : .trailing, 60)
                .frame(maxWidth: .infinity, alignment: side)
            }
            ForEach(others, id: \.offset) { i, f in
                FileCard(file: f, key: "\(message.id)/\(i)", opener: opener)
                    .padding(mine ? .leading : .trailing, 60)
                    .frame(maxWidth: .infinity, alignment: side)
            }
            if !message.text.isEmpty {
                HStack {
                    if mine { Spacer(minLength: 60) }
                    Text(TransferText.linked(message.text))
                        .font(.system(size: 17))
                        .lineSpacing(2)
                        .foregroundStyle(mine ? Color.white : ChatStyle.body)
                        .tint(mine ? Color.white : Theme.blue)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(mine ? ChatStyle.bubble : TransferText.pcBubble, in: RoundedRectangle(cornerRadius: 14))
                        .contextMenu {
                            Button("Copy", systemImage: "doc.on.doc") { UIPasteboard.general.string = message.text }
                        }
                        .accessibilityIdentifier(mine ? "transferMine" : "transferPC")
                    if !mine { Spacer(minLength: 60) }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: side)
    }
}

enum TransferText {
    /// the desktop's phone-side bubble grey, 0x262626
    static let pcBubble = Color(hex: 0x262626)

    /// the words with their web links tappable
    static func linked(_ s: String) -> AttributedString {
        var a = AttributedString(s)
        guard let d = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return a }
        for r in d.matches(in: s, range: NSRange(location: 0, length: (s as NSString).length)) {
            guard let url = r.url, let range = Range(r.range, in: a) else { continue }
            a[range].link = url
            a[range].underlineStyle = .single
        }
        return a
    }

    /// a file's SF Symbol by its kind
    static func icon(_ name: String) -> String {
        switch (name as NSString).pathExtension.lowercased() {
        case "pdf": return "doc.richtext"
        case "txt", "md", "rtf", "csv", "log": return "doc.text"
        case "zip", "gz", "tar", "7z", "rar": return "doc.zipper"
        case "mp3", "m4a", "wav", "aac", "flac": return "waveform"
        case "doc", "docx", "pages": return "doc.text.fill"
        case "xls", "xlsx", "numbers": return "tablecells"
        default: return "doc"
        }
    }
}

/// a picture's small version, or a video's first frame with a play mark
private struct MediaThumb: View {
    let file: TransferFile
    let base: URL?

    var body: some View {
        let link = file.kind == "video" ? (file.poster ?? file.thumb) : (file.thumb ?? file.url)
        ZStack {
            RemoteImage(url: MediaLink.url(link, base: base), fill: true)
            if file.kind == "video" { PlayMark() }
        }
    }
}

private struct PlayMark: View {
    var size: CGFloat = 40

    var body: some View {
        Image(systemName: "play.circle.fill")
            .font(.system(size: size))
            .symbolRenderingMode(.palette)
            .foregroundStyle(.white, .black.opacity(0.45))
    }
}

/// A file that isn't a picture or video: its kind, name and size; a tap downloads it and opens it in Quick Look.
private struct FileCard: View {
    let file: TransferFile
    let key: String
    let opener: TransferOpener

    var body: some View {
        let loading = opener.downloading(key)
        Button { opener.open(file, key: key, source: nil) } label: {
            HStack(spacing: 12) {
                FileGlyph(name: file.name, dim: !file.there)
                VStack(alignment: .leading, spacing: 3) {
                    Text(file.name)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(file.there ? Theme.title : ChatStyle.dim)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if let loading {
                        ProgressView(value: loading)
                            .tint(Theme.blue)
                            .frame(maxWidth: 150)
                            .padding(.vertical, 4)
                    } else {
                        Text(file.there ? Format.bytes(file.size) : "Not on the PC anymore")
                            .font(.system(size: 13))
                            .foregroundStyle(ChatStyle.dim)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 10)
            .padding(.leading, 10)
            .padding(.trailing, 14)
            .frame(maxWidth: 280, alignment: .leading)
            .background(ChatStyle.cardBG, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(ChatStyle.cardBorder, lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .disabled(!file.there)
        .contextMenu { if file.there { FileMenu(file: file, key: key, opener: opener) } }
        .accessibilityLabel("File \(file.name), \(Format.bytes(file.size))")
        .accessibilityIdentifier("transferFile")
    }
}

private struct FileGlyph: View {
    let name: String
    var dim = false

    var body: some View {
        Image(systemName: TransferText.icon(name))
            .font(.system(size: 19))
            .foregroundStyle(dim ? ChatStyle.faint : Theme.rowTitle)
            .frame(width: 40, height: 40)
            .background(Color(hex: 0x26262A), in: RoundedRectangle(cornerRadius: 9))
    }
}

// MARK: - a message still on its way

/// A message of this phone the PC doesn't have yet: its files from the phone's own copies, a bar and "12 of 94 MB"
/// while they go up, or why it stopped with Retry and Discard.
private struct OutboxBubble: View {
    let message: OutMessage
    let store: TransferStore

    var body: some View {
        let media = message.files.filter { $0.kind == "image" || $0.kind == "video" }
        let others = message.files.filter { $0.kind != "image" && $0.kind != "video" }
        VStack(alignment: .trailing, spacing: 6) {
            if !media.isEmpty {
                PhotoGrid(tile: media.count == 1 ? 230 : media.count == 2 ? 150 : 110) {
                    ForEach(media) { f in
                        PhotoTile {
                            ZStack {
                                LocalThumb(url: store.localURL(message, f), video: f.kind == "video")
                                Color.black.opacity(0.25)
                                if f.kind == "video" { PlayMark(size: 34).opacity(0.8) }
                            }
                        }
                        .accessibilityLabel("Sending \(f.name)")
                    }
                }
                .padding(.leading, 60)
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
            ForEach(others) { f in
                HStack(spacing: 12) {
                    FileGlyph(name: f.name)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(f.name).font(.system(size: 15, weight: .medium)).foregroundStyle(Theme.title)
                            .lineLimit(1).truncationMode(.middle)
                        Text(Format.bytes(f.size)).font(.system(size: 13)).foregroundStyle(ChatStyle.dim)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 10).padding(.leading, 10).padding(.trailing, 14)
                .frame(maxWidth: 280, alignment: .leading)
                .background(ChatStyle.cardBG, in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(ChatStyle.cardBorder, lineWidth: 1))
                .opacity(0.8)
                .padding(.leading, 60)
            }
            if !message.text.isEmpty {
                HStack {
                    Spacer(minLength: 60)
                    Text(message.text)
                        .font(.system(size: 17))
                        .lineSpacing(2)
                        .foregroundStyle(.white)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(ChatStyle.bubble.opacity(message.failed == nil ? 0.7 : 0.4),
                                    in: RoundedRectangle(cornerRadius: 14))
                }
            }
            status
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(message.failed == nil ? "transferSending" : "transferNotSent")
    }

    @ViewBuilder
    private var status: some View {
        if let why = message.failed {
            Text("Not sent: \(why)")
                .font(.system(size: 13))
                .foregroundStyle(Theme.red)
                .multilineTextAlignment(.trailing)
            HStack(spacing: 16) {
                Button("Discard") { store.discard(message.clientId) }.foregroundStyle(ChatStyle.dim)
                    .accessibilityIdentifier("transferDiscard")
                Button("Retry") { store.retry(message.clientId) }.foregroundStyle(Theme.blue)
                    .accessibilityIdentifier("transferRetry")
            }
            .font(.system(size: 15, weight: .medium))
            .frame(minHeight: 44)
        } else if message.total > 0 {
            VStack(alignment: .trailing, spacing: 4) {
                ProgressView(value: message.progress)
                    .tint(Theme.blue)
                    .frame(width: 180)
                Text(waiting ? "Waiting for the PC\u{2026} \(amount)" : amount)
                    .font(.system(size: 13).monospacedDigit())
                    .foregroundStyle(ChatStyle.dim)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Sending, \(amount)")
            .accessibilityIdentifier("transferProgress")
        } else {
            Text("Sending\u{2026}")
                .font(.system(size: 13))
                .foregroundStyle(ChatStyle.dim)
        }
    }

    private var waiting: Bool { store.error?.isUnreachable == true }

    private var amount: String {
        "\(Format.bytes(message.sent)) of \(Format.bytes(message.total)) · \(Int((message.progress * 100).rounded(.down)))%"
    }
}

/// a small picture of a file on this phone: a photo's (read at thumbnail size) or a video's first frame
struct LocalThumb: View {
    let url: URL
    let video: Bool
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            Rectangle().fill(ChatStyle.cardBG)
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            }
        }
        .task(id: url) { image = await Self.thumb(url, video: video) }
    }

    static func thumb(_ url: URL, video: Bool) async -> UIImage? {
        if video {
            let gen = AVAssetImageGenerator(asset: AVURLAsset(url: url))
            gen.appliesPreferredTrackTransform = true
            gen.maximumSize = CGSize(width: 480, height: 480)
            guard let frame = try? await gen.image(at: .zero) else { return nil }
            return UIImage(cgImage: frame.image)
        }
        return await Task.detached(priority: .userInitiated) { () -> UIImage? in
            guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
            let opts: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                         kCGImageSourceThumbnailMaxPixelSize: 480,
                                         kCGImageSourceCreateThumbnailWithTransform: true]
            guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { return nil }
            return UIImage(cgImage: cg)
        }.value
    }
}

// MARK: - the box

/// The chat's box without the AI parts: + (Photos & videos, Camera, Files), the words, ↑. Photos and videos come as
/// their originals (HEIC, HEVC); every pick is copied into the store's staging folder at once, so the picker's
/// files can go and a big video doesn't wait in memory.
struct TransferComposer: View {
    @Bindable var store: TransferStore
    @State private var pickingPhotos = false
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var camera = false
    @State private var files = false
    @State private var copying = 0
    @FocusState private var focused: Bool

    static let most = 30

    var body: some View {
        box
            .padding(.horizontal, 12)
            .padding(.top, 6)
            .padding(.bottom, 8)
            .background(alignment: .bottom) {
                Theme.background.frame(height: 40).ignoresSafeArea(edges: .bottom)
            }
            .photosPicker(isPresented: $pickingPhotos, selection: $photoItems, maxSelectionCount: Self.most,
                          matching: .any(of: [.images, .videos]), preferredItemEncoding: .current)
            .onChange(of: photoItems) { _, items in loadPhotos(items) }
            .fullScreenCover(isPresented: $camera) {
                CameraPicker { image in
                    camera = false
                    if let image { addCameraPhoto(image) }
                }
                .ignoresSafeArea()
            }
            .fileImporter(isPresented: $files, allowedContentTypes: [.item], allowsMultipleSelection: true) { result in
                addFiles(result)
            }
    }

    private var box: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !store.staged.isEmpty || copying > 0 {
                StagedStrip(store: store, copying: copying)
                    .padding(.top, 8)
            }
            TextField("", text: $store.draft, prompt: Text("Message your PC").foregroundStyle(Color(hex: 0x8E8E93)),
                      axis: .vertical)
                .font(.system(size: 17))
                .foregroundStyle(Composer.ink)
                .tint(Color(hex: 0x3D7BFD))
                .lineLimit(1...8)
                .focused($focused)
                .padding(.top, 14)
                .padding(.leading, 20)
                .padding(.trailing, 16)
                .frame(minHeight: 37, alignment: .top)
                .accessibilityIdentifier("composer")
            HStack(spacing: 2) {
                plusMenu
                Spacer(minLength: 4)
                sendButton
            }
            .frame(height: 48)
            .padding(.horizontal, 8)
            .padding(.bottom, 4)
        }
        .background(Composer.fill, in: RoundedRectangle(cornerRadius: 28))
        .overlay(RoundedRectangle(cornerRadius: 28).stroke(Composer.border, lineWidth: 1))
        .contentShape(RoundedRectangle(cornerRadius: 28))
        .onTapGesture { focused = true }
    }

    private var plusMenu: some View {
        Menu {
            Button("Photos & videos", systemImage: "photo.on.rectangle") { pickingPhotos = true }
            Button("Camera", systemImage: "camera") { camera = true }
                .disabled(!UIImagePickerController.isSourceTypeAvailable(.camera))
            Button("Files", systemImage: "folder") { files = true }
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(Composer.ink)
                .frame(width: 37, height: 40)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("Attach")
        .accessibilityIdentifier("attach")
    }

    private var ready: Bool { store.canSend && copying == 0 }

    private var sendButton: some View {
        Button {
            store.send()
        } label: {
            Image(systemName: "arrow.up")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(ready ? Color.black : Color(hex: 0x8E8E93))
                .frame(width: 38, height: 38)
                .background(ready ? Composer.ink : Color(hex: 0x3A3A3C), in: Circle())
                .padding(.leading, 4)
        }
        .buttonStyle(.plain)
        .disabled(!ready)
        .accessibilityLabel("Send")
        .accessibilityIdentifier("send")
    }

    // MARK: picking

    private var room: Int { Self.most - store.staged.count - copying }

    private func loadPhotos(_ items: [PhotosPickerItem]) {
        guard !items.isEmpty else { return }
        photoItems = []
        let take = Array(items.prefix(max(0, room)))
        if take.count < items.count { store.actionError = "Up to \(Self.most) at a time." }
        copying += take.count
        for item in take {
            Task {
                defer { copying -= 1 }
                do {
                    if let picked = try await item.loadTransferable(type: PickedFile.self) {
                        store.stage(picked.url, name: picked.name)
                    } else {
                        store.actionError = "That photo or video couldn't be read."
                    }
                } catch {
                    store.actionError = "That photo or video couldn't be read."
                }
            }
        }
    }

    private func addCameraPhoto(_ image: UIImage) {
        guard room > 0, let data = image.jpegData(compressionQuality: 0.9) else { return }
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH.mm.ss"
        let name = "Photo \(f.string(from: Date())).jpg"
        let u = PickedFile.stagingURL(name)
        do {
            try data.write(to: u)
            store.stage(u, name: name)
        } catch {
            store.actionError = "The photo couldn't be kept."
        }
    }

    private func addFiles(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result else { return }
        let take = Array(urls.prefix(max(0, room)))
        if take.count < urls.count { store.actionError = "Up to \(Self.most) at a time." }
        copying += take.count
        for url in take {
            Task {
                defer { copying -= 1 }
                let name = url.lastPathComponent
                // a copy off the main thread: a big file takes a moment
                let copy = await Task.detached { () -> URL? in
                    let scoped = url.startAccessingSecurityScopedResource()
                    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                    let dest = PickedFile.stagingURL(name)
                    return (try? FileManager.default.copyItem(at: url, to: dest)) != nil ? dest : nil
                }.value
                if let copy { store.stage(copy, name: name) } else { store.actionError = "\(name) couldn't be read." }
            }
        }
    }
}

/// A photo or video from the picker as its original file, copied into the staging folder.
struct PickedFile: Transferable {
    let url: URL
    let name: String

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .movie) { received in try keep(received.file) }
        FileRepresentation(importedContentType: .image) { received in try keep(received.file) }
        FileRepresentation(importedContentType: .item) { received in try keep(received.file) }
    }

    private static func keep(_ file: URL) throws -> PickedFile {
        let name = file.lastPathComponent
        let dest = stagingURL(name)
        try FileManager.default.copyItem(at: file, to: dest)
        return PickedFile(url: dest, name: name)
    }

    /// a new place in the staging folder for a file called `name`
    static func stagingURL(_ name: String) -> URL {
        let dir = TransferStore.defaultFolder.appendingPathComponent("staging", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let safe = name.replacingOccurrences(of: "/", with: "-")
        return dir.appendingPathComponent(String(UUID().uuidString.prefix(8)) + "-" + safe)
    }
}

/// The picked files above the words, each with an × to take it out again.
private struct StagedStrip: View {
    let store: TransferStore
    let copying: Int

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(store.staged) { f in
                    ZStack(alignment: .topTrailing) {
                        thumb(f)
                        Button { store.unstage(f.id) } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(Theme.title)
                                .frame(width: 22, height: 22)
                                .background(Color.black.opacity(0.7), in: Circle())
                                .frame(width: 44, height: 44, alignment: .topTrailing)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Remove \(f.name)")
                    }
                }
                ForEach(0..<copying, id: \.self) { _ in
                    ProgressView()
                        .frame(width: 64, height: 64)
                        .background(Composer.fill, in: RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Composer.border, lineWidth: 1))
                        .padding(.top, 6)
                        .padding(.trailing, 6)
                }
            }
            .padding(.horizontal, 16)
        }
        .accessibilityIdentifier("attachments")
    }

    @ViewBuilder
    private func thumb(_ f: StagedFile) -> some View {
        if f.kind == "image" || f.kind == "video" {
            LocalThumb(url: f.url, video: f.kind == "video")
                .frame(width: 64, height: 64)
                .overlay { if f.kind == "video" { PlayMark(size: 22) } }
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .padding(.top, 6)
                .padding(.trailing, 6)
                .accessibilityLabel(f.name)
        } else {
            VStack(spacing: 4) {
                Image(systemName: TransferText.icon(f.name)).font(.system(size: 18)).foregroundStyle(Theme.rowTitle)
                Text(f.name).font(.system(size: 10)).foregroundStyle(ChatStyle.dim).lineLimit(1).truncationMode(.middle)
                Text(Format.bytes(f.size)).font(.system(size: 10)).foregroundStyle(ChatStyle.faint)
            }
            .padding(6)
            .frame(width: 84, height: 64)
            .background(Composer.fill, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Composer.border, lineWidth: 1))
            .padding(.top, 6)
            .padding(.trailing, 6)
            .accessibilityLabel(f.name)
        }
    }
}

// MARK: - the Library

/// Every file sent either way that's still on the PC, newest first: photos and videos as a grid of squares, other
/// files as a list. A tap opens; a long press saves, shares or shows the message in the chat.
private struct TransferLibraryView: View {
    let store: TransferStore
    let opener: TransferOpener
    let showInChat: (String) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if let lib = store.library {
                    if lib.items.isEmpty {
                        TransferNotice(icon: "photo.on.rectangle",
                                       text: "Nothing here yet: photos, videos and files sent either way show up here.")
                            .padding(.horizontal, 6)
                            .padding(.top, 30)
                    }
                    if !lib.media.isEmpty {
                        header("Photos & videos", count: lib.media.count)
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 3), count: 3), spacing: 3) {
                            ForEach(lib.media) { it in
                                tile(it)
                            }
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    if !lib.files.isEmpty {
                        header("Files", count: lib.files.count)
                        VStack(spacing: 0) {
                            ForEach(Array(lib.files.enumerated()), id: \.element.id) { k, it in
                                if k > 0 { Divider().overlay(ChatStyle.line).padding(.leading, 64) }
                                row(it)
                            }
                        }
                        .background(ChatStyle.cardBG, in: RoundedRectangle(cornerRadius: 14))
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(ChatStyle.cardBorder, lineWidth: 1))
                    }
                    if !lib.items.isEmpty {
                        Label("On your PC in \(lib.folder ?? store.folder ?? "GupWorks Transfer")", systemImage: "desktopcomputer")
                            .font(.system(size: 13))
                            .foregroundStyle(ChatStyle.faint)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 22)
                            .accessibilityIdentifier("transferFolder")
                    }
                } else if let e = store.libraryError {
                    TransferNotice(icon: "exclamationmark.triangle", text: e.message).padding(.horizontal, 6)
                } else {
                    ProgressView().frame(maxWidth: .infinity).padding(.vertical, 40)
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 30)
        }
        .refreshable { await store.loadLibrary() }
        .task { await store.loadLibrary() }
        .accessibilityIdentifier("transferLibrary")
    }

    private func header(_ title: String, count: Int) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.system(size: 20, weight: .semibold)).foregroundStyle(Theme.title)
            Text("\(count)").font(.system(size: 15)).foregroundStyle(ChatStyle.dim)
            Spacer()
        }
        .padding(.horizontal, 6)
        .padding(.top, 18)
        .padding(.bottom, 10)
        .accessibilityAddTraits(.isHeader)
    }

    private func tile(_ it: TransferItem) -> some View {
        Button { opener.open(it.file, key: it.id, source: opener.librarySource(store)) } label: {
            Color.clear
                .aspectRatio(1, contentMode: .fit)
                .overlay { MediaThumb(file: it.file, base: opener.base) }
                .clipped()
                .overlay(alignment: .bottomLeading) {
                    if !it.mine {
                        Image(systemName: "desktopcomputer")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(5)
                            .background(.black.opacity(0.45), in: Circle())
                            .padding(5)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            FileMenu(file: it.file, key: it.id, opener: opener) { showInChat(it.messageId) }
        }
        .accessibilityLabel((it.kind == "video" ? "Video " : "Picture ") + it.name)
        .accessibilityIdentifier(it.kind == "video" ? "transferLibVideo" : "transferLibPicture")
    }

    private func row(_ it: TransferItem) -> some View {
        let loading = opener.downloading(it.id)
        return Button { opener.open(it.file, key: it.id, source: nil) } label: {
            HStack(spacing: 12) {
                FileGlyph(name: it.name)
                VStack(alignment: .leading, spacing: 3) {
                    Text(it.name)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(Theme.title)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if let loading {
                        ProgressView(value: loading).tint(Theme.blue).padding(.vertical, 4)
                    } else {
                        Text("\(Format.bytes(it.size)) · \(it.mine ? "From iPhone" : "From PC") · \(Format.dayTime(it.ts))")
                            .font(.system(size: 13))
                            .foregroundStyle(ChatStyle.dim)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPress())
        .contextMenu {
            FileMenu(file: it.file, key: it.id, opener: opener) { showInChat(it.messageId) }
        }
        .accessibilityIdentifier("transferLibFile")
    }
}
