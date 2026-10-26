import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// 5a/5e: ChatGPT's rounded box. The words on top; below them + (Photos, Camera, Files), the gauge (model and effort,
/// 5f), the three usage rings (5g), then / commands, the mic and send (■ stop while Claude works).
/// 5h: the mic turns the row into the recorder (× cancel, waveform, ■ words into the box, ↑ send).
struct Composer: View {
    @Bindable var store: ChatStore
    /// context, 5-hour and weekly meters (a new chat: the account's, from home)
    let usage: [Meter]
    let asking: Bool
    /// the usage card (5g) is open; the chat draws it above the box
    @Binding var usageOpen: Bool

    @State private var showCommands = false
    @State private var showModels = false
    /// /model or /effort picked in the commands: the model sheet opens once they've gone
    @State private var thenModels = false
    @State private var attachments: [Attachment] = []
    @State private var pickingPhotos = false
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var camera = false
    @State private var files = false
    @State private var problem: String?
    @FocusState private var focused: Bool

    static let fill = Color(hex: 0x1B1B1B)
    static let border = Color(hex: 0x2B2B2B)
    static let ink = Color(hex: 0xECECEC)
    static let uploadMax = 30 * 1024 * 1024  // gw3-phone's UPLOAD_MAX

    private var voice: VoiceController { store.voice }
    /// the box is the recorder (5h)
    private var recorder: Bool { voice.phase != .idle }

    private var hasContent: Bool {
        !store.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !attachments.isEmpty
    }

    private var placeholder: String {
        if asking { return "Answer or ask\u{2026}" }
        return store.temporary ? "Temporary chat" : "Ask GupWorks"
    }

    var body: some View {
        VStack(spacing: 6) {
            // above the box, so the keyboard that comes up with the words never hides it
            if let note = voice.note {
                Text(note)
                    .font(.system(size: 13))
                    .foregroundStyle(ChatStyle.dim)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 24)
                    .accessibilityIdentifier("voiceNote")
            }
            box
                .padding(.horizontal, 12)
        }
        .padding(.top, 6)
        .padding(.bottom, 8)
        .background(alignment: .bottom) {
            // the chat scrolls under the box's corners, not under its row of keys
            Theme.background.frame(height: 40).ignoresSafeArea(edges: .bottom)
        }
        .disabled(store.gone)
        .photosPicker(isPresented: $pickingPhotos, selection: $photoItems, maxSelectionCount: 10, matching: .images)
        .onChange(of: photoItems) { _, items in loadPhotos(items) }
        .fullScreenCover(isPresented: $camera) {
            CameraPicker { image in
                camera = false
                if let image { addPhoto(image, name: "photo.jpg") }
            }
            .ignoresSafeArea()
        }
        .fileImporter(isPresented: $files, allowedContentTypes: [.item], allowsMultipleSelection: true) { result in
            addFiles(result)
        }
        .sheet(isPresented: $showCommands, onDismiss: {
            if thenModels {
                thenModels = false
                showModels = true
            }
        }) {
            CommandsSheet(store: store) { thenModels = true }
        }
        .sheet(isPresented: $showModels) {
            ModelEffortSheet(store: store)
        }
        .onChange(of: store.draft) { old, new in
            // typing / first in an empty box opens the commands, as the desktop's palette
            if old.isEmpty && new == "/" {
                store.draft = ""
                showCommands = true
            }
        }
        .onChange(of: store.focusTick, initial: true) { _, tick in if tick > 0 { focused = true } }
        .onChange(of: voice.limitTick) { Task { await finishVoice(send: false) } }
        .onChange(of: recorder) { _, on in if on { usageOpen = false } }
        .onDisappear { voice.cancel() }
        .alert("Can't attach that", isPresented: Binding(get: { problem != nil }, set: { if !$0 { problem = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(problem ?? "")
        }
    }

    private var box: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !attachments.isEmpty {
                AttachmentStrip(attachments: $attachments)
                    .padding(.top, 8)
            }
            if recorder {
                // the placeholder stays on top while recording, as Claude's
                Text(placeholder)
                    .font(.system(size: 17))
                    .foregroundStyle(Color(hex: 0x8E8E93))
                    .padding(.top, 14)
                    .padding(.horizontal, 20)
                    .frame(minHeight: 37, alignment: .top)
                    .accessibilityHidden(true)
            } else {
                TextField("", text: $store.draft, prompt: Text(placeholder).foregroundStyle(Color(hex: 0x8E8E93)),
                          axis: .vertical)
                    .font(.system(size: 17))
                    .foregroundStyle(Self.ink)
                    .tint(Color(hex: 0x3D7BFD))
                    .lineLimit(1...8)
                    .focused($focused)
                    .padding(.top, 14)
                    .padding(.leading, 20)
                    .padding(.trailing, 16)
                    .frame(minHeight: 37, alignment: .top)
                    .accessibilityIdentifier("composer")
            }
            row
                .frame(height: 48)
                .padding(.leading, 8)
                .padding(.trailing, 8)
                .padding(.bottom, 4)
        }
        .background(Self.fill, in: RoundedRectangle(cornerRadius: 28))
        .overlay(RoundedRectangle(cornerRadius: 28).stroke(Self.border, lineWidth: 1))
        .contentShape(RoundedRectangle(cornerRadius: 28))
        .onTapGesture { if !recorder { focused = true } }
    }

    /// + gauge rings · / mic send; recording: × waveform ■ ↑. The mic key keeps its place in both, so a hold that
    /// starts on the mic ends on it as ↑.
    private var row: some View {
        HStack(spacing: 2) {
            if recorder {
                recorderParts
            } else {
                plusMenu
                gaugeButton
                ringsButton
                Spacer(minLength: 4)
                slash
            }
            VoiceKey(recording: voice.phase == .recording, busy: voice.phase == .transcribing, down: micDown, up: micUp)
                .padding(.horizontal, voice.phase == .recording || voice.phase == .transcribing ? -1 : -3.5)
            if !recorder {
                if store.working {
                    if hasContent { sendButton }
                    stopButton
                } else {
                    sendButton
                }
            }
        }
    }

    private var plusMenu: some View {
        Menu {
            Button("Photos", systemImage: "photo.on.rectangle") { pickingPhotos = true }
            Button("Camera", systemImage: "camera") { camera = true }
                .disabled(!UIImagePickerController.isSourceTypeAvailable(.camera))
            Button("Files", systemImage: "folder") { files = true }
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(Self.ink)
                .frame(width: 37, height: 40)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("Attach")
        .accessibilityIdentifier("attach")
    }

    /// the gauge: model and effort (5f); its needle shows the effort, a red dot while Bypass is on
    private var gaugeButton: some View {
        let model = store.currentModel?.label ?? store.header?.model ?? ""
        let effort = store.currentEffort ?? ""
        let bypass = store.header?.bypass == true
        return Button { showModels = true } label: {
            Icons.gauge(store.currentEffort)
                .foregroundStyle(Self.ink)
                .overlay(alignment: .topTrailing) {
                    if bypass {
                        Circle().fill(Theme.red).frame(width: 7, height: 7).offset(x: 2, y: -1)
                    }
                }
                .frame(width: 37, height: 40)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .task { await store.loadModels() }
        .accessibilityLabel("Model and effort")
        .accessibilityValue([model, effort, bypass ? "Bypass" : ""].filter { !$0.isEmpty }.joined(separator: " · "))
        .accessibilityIdentifier("gauge")
    }

    /// the three rings: context, 5-hour, weekly (5g's card). Before a chat exists (home, a new chat) they draw
    /// empty and the button does nothing; the first message, or any existing chat, brings them to life.
    private var ringsButton: some View {
        let live = !store.isNew
        let ctx = live ? usage.first { $0.label == "ctx" }?.percent : nil
        return Button { if live { usageOpen.toggle() } } label: {
            UsageRings(percents: live
                       ? [ctx, usage.first { $0.label == "5h" }?.percent, usage.first { $0.label == "wk" }?.percent]
                       : [nil, nil, nil])
                .frame(width: 37, height: 40)
                .background(usageOpen ? Color(hex: 0x2C2C2E) : .clear, in: RoundedRectangle(cornerRadius: 20))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Usage")
        .accessibilityValue(live ? "Context \(Int((ctx ?? 0).rounded())) percent used" : "No chat yet")
        .accessibilityIdentifier("usage")
    }

    /// × · waveform (or Transcribing…) · ■
    @ViewBuilder
    private var recorderParts: some View {
        Button { voice.cancel() } label: {
            Image(systemName: "xmark")
                .font(.system(size: 17, weight: .regular))
                .foregroundStyle(Self.ink)
                .frame(width: 40, height: 40)
                .background(Color(hex: 0x333338), in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Cancel recording")
        .accessibilityIdentifier("voiceCancel")
        if voice.phase == .recording {
            Waveform(levels: voice.levels)
                .frame(height: 24)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 8)
                .accessibilityElement()
                .accessibilityLabel("Listening\u{2026}")
            // no clock on screen (5h), but VoiceOver still hears how long it's been
            Color.clear.frame(width: 1, height: 1)
                .accessibilityElement()
                .accessibilityLabel("Recording, \(Int(voice.elapsed)) seconds")
                .accessibilityIdentifier("voiceTimer")
            intoBoxButton
        } else {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small).tint(Self.ink)
                Text(voice.onPhone ? "Transcribing on this iPhone\u{2026}" : "Transcribing\u{2026}")
                    .font(.system(size: 16))
                    .foregroundStyle(Self.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .accessibilityIdentifier("transcribing")
            }
            .frame(maxWidth: .infinity)
        }
    }

    /// ■ in the recorder: the words go in the box to check first
    private var intoBoxButton: some View {
        Button {
            Task { await finishVoice(send: false) }
        } label: {
            RoundedRectangle(cornerRadius: 2.5)
                .fill(Self.ink)
                .frame(width: 12, height: 12)
                .frame(width: 40, height: 40)
                .background(Color(hex: 0x333338), in: Circle())
        }
        .buttonStyle(.plain)
        .padding(.trailing, 2)
        .accessibilityLabel("Stop and put the words in the box")
        .accessibilityIdentifier("voiceStop")
    }

    // MARK: voice (5h)

    /// `at` is the touch's own time, not when the handler ran: a busy first start can delay the
    /// release by more than the hold time, and a tap mustn't turn into push-to-talk because of that
    private func micDown(at t: Date) {
        switch voice.press.down(at: t, recording: voice.phase == .recording) {
        case .start:
            focused = false
            Task { await voice.start() }
        default: break
        }
    }

    private func micUp(at t: Date) {
        switch voice.press.up(at: t, recording: voice.phase == .recording) {
        case .start:
            focused = false
            Task { await voice.start() }
        case .insert: Task { await finishVoice(send: false) }
        case .send: Task { await finishVoice(send: true) }
        default: break
        }
    }

    /// The recording becomes text: in the box (■, push-to-talk) or sent as it is (↑).
    private func finishVoice(send: Bool) async {
        guard let t = await voice.finish() else { return }
        let said = t.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if said.isEmpty {
            voice.show("Nothing heard. Try again a little closer to the microphone.")
            return
        }
        if t.source == .phone {
            voice.show("Transcribed on this iPhone: \(t.why ?? "your PC couldn't be reached").", seconds: 8)
        }
        let words = VoiceMath.merge(store.draft, said)
        if send {
            store.draft = ""
            let picked = attachments
            attachments = []
            await store.send(text: words, attachments: picked)
        } else {
            store.put(words)
        }
    }

    /// / in a square: the commands
    private var slash: some View {
        Button { showCommands = true } label: {
            Icons.slash()
                .foregroundStyle(Color(hex: 0xB4B4B8))
                .frame(width: 37, height: 40)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Commands")
        .accessibilityIdentifier("commands")
    }

    /// ↑: grey until there's something to send
    private var sendButton: some View {
        Button(action: send) {
            Image(systemName: "arrow.up")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(hasContent ? Color.black : Color(hex: 0x8E8E93))
                .frame(width: 38, height: 38)
                .background(hasContent ? Self.ink : Color(hex: 0x3A3A3C), in: Circle())
                .padding(.leading, 4)
        }
        .buttonStyle(.plain)
        .disabled(!hasContent)
        .accessibilityLabel(store.working ? "Send when Claude is done" : "Send")
        .accessibilityIdentifier("send")
    }

    /// ■ while Claude works (beside ↑ once there's something to queue)
    private var stopButton: some View {
        Button {
            Task { await store.stop() }
        } label: {
            RoundedRectangle(cornerRadius: 2.5)
                .fill(hasContent ? Self.ink : Color.black)
                .frame(width: 12, height: 12)
                .frame(width: 38, height: 38)
                .background(hasContent ? Color(hex: 0x3A3A3C) : Self.ink, in: Circle())
                .padding(.leading, 4)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Stop")
        .accessibilityIdentifier("stop")
    }

    private func send() {
        guard hasContent else { return }
        let words = store.draft, picked = attachments
        store.draft = ""
        attachments = []
        Task { await store.send(text: words, attachments: picked) }
    }

    // MARK: attachments

    private func loadPhotos(_ items: [PhotosPickerItem]) {
        guard !items.isEmpty else { return }
        photoItems = []
        Task {
            for item in items {
                if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                    addPhoto(image, name: "photo.jpg")
                } else {
                    problem = "That photo couldn't be read."
                }
            }
        }
    }

    private func addPhoto(_ image: UIImage, name: String) {
        guard attachments.count < 10 else { problem = "Up to 10 at a time."; return }
        guard let a = Attachment.photo(image, name: name) else { problem = "That photo couldn't be read."; return }
        attachments.append(a)
    }

    private func addFiles(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result else { return }
        for url in urls {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            let name = url.lastPathComponent
            guard let data = try? Data(contentsOf: url) else { problem = "\(name) couldn't be read."; continue }
            let type = UTType(filenameExtension: url.pathExtension)
            if type?.conforms(to: .image) == true, !Attachment.readableImage(url.pathExtension), let image = UIImage(data: data) {
                // HEIC and the like: sent as JPEG, which Claude can open
                addPhoto(image, name: (name as NSString).deletingPathExtension + ".jpg")
                continue
            }
            guard data.count <= Self.uploadMax else { problem = "\(name) is over 30 MB."; continue }
            guard attachments.count < 10 else { problem = "Up to 10 at a time."; return }
            let isImage = type?.conforms(to: .image) == true
            attachments.append(Attachment(name: name, type: type?.preferredMIMEType ?? "application/octet-stream",
                                          data: data, image: isImage ? UIImage(data: data) : nil))
        }
    }
}

extension Attachment {
    /// A photo as the PC gets it: JPEG, at most 2048 px on its long side.
    static func photo(_ image: UIImage, name: String) -> Attachment? {
        let small = image.scaledDown(to: 2048)
        guard let data = small.jpegData(compressionQuality: 0.85) else { return nil }
        return Attachment(name: name, type: "image/jpeg", data: data, image: small)
    }

    /// the picture kinds Claude opens as they are (gw3-phone's IMAGE_EXT)
    static func readableImage(_ ext: String) -> Bool {
        ["png", "jpg", "jpeg", "gif", "webp"].contains(ext.lowercased())
    }
}

extension UIImage {
    func scaledDown(to side: CGFloat) -> UIImage {
        let longest = max(size.width, size.height)
        guard longest > side, longest > 0 else { return self }
        let k = side / longest
        let target = CGSize(width: (size.width * k).rounded(), height: (size.height * k).rounded())
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: target))
        }
    }
}

/// The picked photos and files above the field, each with an × to take it out again.
private struct AttachmentStrip: View {
    @Binding var attachments: [Attachment]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(attachments) { a in
                    ZStack(alignment: .topTrailing) {
                        thumb(a)
                        Button {
                            attachments.removeAll { $0.id == a.id }
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(Theme.title)
                                .frame(width: 22, height: 22)
                                .background(Color.black.opacity(0.7), in: Circle())
                                .frame(width: 44, height: 44, alignment: .topTrailing)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Remove \(a.name)")
                    }
                }
            }
            .padding(.horizontal, 16)
        }
        .accessibilityIdentifier("attachments")
    }

    @ViewBuilder
    private func thumb(_ a: Attachment) -> some View {
        if let image = a.image {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 64, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .padding(.top, 6)
                .padding(.trailing, 6)
                .accessibilityLabel("Photo")
        } else {
            VStack(spacing: 4) {
                Image(systemName: "doc").font(.system(size: 18)).foregroundStyle(Theme.rowTitle)
                Text(a.name).font(.system(size: 10)).foregroundStyle(ChatStyle.dim).lineLimit(1).truncationMode(.middle)
            }
            .padding(6)
            .frame(width: 84, height: 64)
            .background(Composer.fill, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Composer.border, lineWidth: 1))
            .padding(.top, 6)
            .padding(.trailing, 6)
            .accessibilityLabel(a.name)
        }
    }
}

/// The phone's camera for one photo (not on the simulator: the + menu turns Camera off there).
struct CameraPicker: UIViewControllerRepresentable {
    let done: (UIImage?) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let c = UIImagePickerController()
        c.sourceType = .camera
        c.delegate = context.coordinator
        return c
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(done: done) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let done: (UIImage?) -> Void

        init(done: @escaping (UIImage?) -> Void) {
            self.done = done
        }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            done(info[.originalImage] as? UIImage)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            done(nil)
        }
    }
}

// MARK: - the phone's own messages before they're turns

/// A message the PC has: *queued* (dimmer bubble, "queued · sends when Claude is done"), sent (a normal bubble, its
/// turn is on its way) or failed.
struct QueuedBubble: View {
    let item: QueueItem
    let base: URL?

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            Bubble(prompt: Prompt(text: item.text, images: item.images), base: base, queued: item.state == "queued")
            if let files = item.files, !files.isEmpty {
                FileLine(names: files)
            }
            if item.state == "failed" {
                Text("Didn't send: \(item.error ?? "the chat didn't take it")")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.red)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(item.state == "queued" ? "queued" : "queue-\(item.state)")
    }
}

/// A message still on the phone: sending, or not sent with Retry and Discard.
struct OutgoingBubble: View {
    let message: Outgoing
    let retry: () -> Void
    let discard: () -> Void

    var body: some View {
        VStack(alignment: .trailing, spacing: 6) {
            let photos = message.attachments.compactMap(\.image)
            if !photos.isEmpty {
                PhotoGrid {
                    ForEach(Array(photos.enumerated()), id: \.offset) { _, image in
                        PhotoTile { Image(uiImage: image).resizable().scaledToFill() }
                    }
                }
                .padding(.leading, 60)
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
            let others = message.attachments.filter { $0.image == nil }.map(\.name)
            if !others.isEmpty { FileLine(names: others) }
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
            if let why = message.failed {
                Text("Not sent: \(why)")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.red)
                    .multilineTextAlignment(.trailing)
                HStack(spacing: 16) {
                    Button("Discard", action: discard).foregroundStyle(ChatStyle.dim)
                    Button("Retry", action: retry).foregroundStyle(Theme.blue)
                }
                .font(.system(size: 15, weight: .medium))
                .frame(minHeight: 44)
            } else {
                Text(message.attachments.contains { $0.uploaded == nil } ? "Sending photos\u{2026}" : "Sending\u{2026}")
                    .font(.system(size: 13))
                    .foregroundStyle(ChatStyle.dim)
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .padding(.top, 14)
        .accessibilityIdentifier(message.failed == nil ? "sending" : "notSent")
    }
}

private struct FileLine: View {
    let names: [String]

    var body: some View {
        Label(names.joined(separator: ", "), systemImage: "doc")
            .font(.system(size: 13))
            .foregroundStyle(ChatStyle.dim)
            .lineLimit(1)
            .truncationMode(.middle)
    }
}

/// The mic at rest, ↑ while recording. Tap: record (it stays on). Hold: push-to-talk, letting go puts the words in the
/// box. ↑: send what was said. One view in both looks, so a hold that starts on the mic ends on it.
struct VoiceKey: View {
    let recording: Bool
    let busy: Bool
    let down: (Date) -> Void
    let up: (Date) -> Void

    var body: some View {
        ZStack {
            if recording || busy {
                Circle().fill(Composer.ink).frame(width: 38, height: 38)
                Image(systemName: "arrow.up")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(Color.black)
            } else {
                Image(systemName: "mic")
                    .font(.system(size: 19))
                    .foregroundStyle(Composer.ink)
            }
        }
        // a 44 pt target that lays out as the mockup's narrower slot (the rest overlaps the gaps beside it)
        .frame(width: 44, height: 44)
        .opacity(busy ? 0.4 : 1)
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 0)
            .onChanged { down($0.time) }
            .onEnded { up($0.time) })
        .accessibilityElement()
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(recording || busy ? "Send what you said" : "Record")
        .accessibilityHint(recording || busy ? "" : "Tap to record, or hold to talk and let go to put it in the box")
        .accessibilityIdentifier("mic")
        .accessibilityAction {
            let now = Date()
            down(now)
            up(now)
        }
    }
}

/// Claude's recorder wave (5h): white bars for the voice, newest on the right, after dots where nothing was heard.
struct Waveform: View {
    let levels: [Float]

    var body: some View {
        Canvas { ctx, size in
            let step: CGFloat = 5, w: CGFloat = 2.5
            let slots = max(4, Int(size.width / step))
            let shown = Array(levels.suffix(slots))
            let start = slots - shown.count  // the dots fill in from the left until the voice reaches them
            for i in 0..<slots {
                let x = CGFloat(i) * step
                let level = i >= start ? CGFloat(shown[i - start]) : 0
                if level < 0.12 {
                    let r = CGRect(x: x, y: (size.height - w) / 2, width: w, height: w)
                    ctx.fill(Path(ellipseIn: r), with: .color(i >= start ? .white : Color(hex: 0xD4D4D4).opacity(0.8)))
                } else {
                    let h = max(5, min(1, level) * size.height)
                    let r = CGRect(x: x, y: (size.height - h) / 2, width: w, height: h)
                    ctx.fill(Path(roundedRect: r, cornerRadius: w / 2), with: .color(.white))
                }
            }
        }
    }
}
