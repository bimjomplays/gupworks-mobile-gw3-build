import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// D3: + (Photos, Camera, Files), the text field, / and the mic at rest; ↑ once there's something to send, and ■ while
/// Claude works (a message sent then waits as *queued*). The usage pill floats above it.
struct Composer: View {
    let store: ChatStore
    let usage: [Meter]
    let asking: Bool

    @State private var text = ""
    @State private var attachments: [Attachment] = []
    @State private var pickingPhotos = false
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var camera = false
    @State private var files = false
    @State private var problem: String?
    @FocusState private var focused: Bool

    static let fill = Color(hex: 0x1F1F22)
    static let border = Color(hex: 0x2E2E33)
    static let uploadMax = 30 * 1024 * 1024  // gw3-phone's UPLOAD_MAX

    private var hasContent: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !attachments.isEmpty
    }

    var body: some View {
        VStack(alignment: .trailing, spacing: 6) {
            if !asking, let ctx = usage.first(where: { $0.label == "ctx" })?.percent {
                UsagePill(ctx: ctx, fiveHours: usage.first { $0.label == "5h" }?.percent)
                    .padding(.horizontal, 16)
            }
            if !attachments.isEmpty {
                AttachmentStrip(attachments: $attachments)
            }
            HStack(alignment: .bottom, spacing: 8) {
                plusMenu
                field
            }
            .padding(.horizontal, 16)
        }
        .padding(.top, 6)
        .padding(.bottom, 6)
        .background(Theme.background.ignoresSafeArea(edges: .bottom))
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
        .alert("Can't attach that", isPresented: Binding(get: { problem != nil }, set: { if !$0 { problem = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(problem ?? "")
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
                .font(.system(size: 20, weight: .regular))
                .foregroundStyle(Theme.rowTitle)
                .frame(width: 52, height: 52)
                .background(Self.fill, in: Circle())
                .overlay(Circle().stroke(Self.border, lineWidth: 1))
                .contentShape(Circle())
        }
        .accessibilityLabel("Attach")
        .accessibilityIdentifier("attach")
    }

    private var field: some View {
        HStack(alignment: .bottom, spacing: 0) {
            TextField("", text: $text,
                      prompt: Text(asking ? "Answer or ask\u{2026}" : "Ask Claude anything\u{2026}")
                          .foregroundStyle(Color(hex: 0x8A8A90)),
                      axis: .vertical)
                .font(.system(size: 17))
                .foregroundStyle(Theme.title)
                .lineLimit(1...6)
                .focused($focused)
                .padding(.vertical, 15)
                .accessibilityIdentifier("composer")
            Spacer(minLength: 4)
            trailing
        }
        .padding(.leading, 18)
        .padding(.trailing, 4)
        .frame(minHeight: 52)
        .background(Self.fill, in: RoundedRectangle(cornerRadius: 26))
        .overlay(RoundedRectangle(cornerRadius: 26).stroke(Self.border, lineWidth: 1))
    }

    @ViewBuilder
    private var trailing: some View {
        HStack(spacing: 2) {
            if store.working {
                if hasContent { sendButton }
                stopButton(small: hasContent)
            } else if hasContent {
                slash
                sendButton
            } else {
                slash
                // voice comes with slice 5
                Image(systemName: "mic")
                    .font(.system(size: 18))
                    .foregroundStyle(Theme.rowTitle)
                    .frame(width: 44, height: 44)
                    .accessibilityHidden(true)
            }
        }
        .padding(.bottom, 4)
    }

    /// "/" in a small square: commands (slice 4)
    private var slash: some View {
        Text("/")
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(Color(hex: 0xB4B4B8))
            .frame(width: 19, height: 19)
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color(hex: 0xB4B4B8), lineWidth: 1.5))
            .frame(width: 44, height: 44)
            .accessibilityHidden(true)
    }

    private var sendButton: some View {
        Button(action: send) {
            Image(systemName: "arrow.up")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color(hex: 0x181818))
                .frame(width: 44, height: 44)
                .background(Color(hex: 0xF0F0F0), in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(store.working ? "Send when Claude is done" : "Send")
        .accessibilityIdentifier("send")
    }

    private func stopButton(small: Bool) -> some View {
        Button {
            Task { await store.stop() }
        } label: {
            Image(systemName: "stop.fill")
                .font(.system(size: small ? 12 : 14, weight: .semibold))
                .foregroundStyle(small ? Theme.rowTitle : Color(hex: 0x181818))
                .frame(width: small ? 34 : 44, height: small ? 34 : 44)
                .background(small ? Color(hex: 0x3A3A40) : Color(hex: 0xF0F0F0), in: Circle())
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Stop")
        .accessibilityIdentifier("stop")
    }

    private func send() {
        guard hasContent else { return }
        let words = text, picked = attachments
        text = ""
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
                HStack(spacing: 6) {
                    Spacer(minLength: 60)
                    ForEach(Array(photos.enumerated()), id: \.offset) { _, image in
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 96, height: 96)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                }
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

/// "◔ 34% | 5h 5%": the context ring and the five-hour use.
struct UsagePill: View {
    let ctx: Double
    let fiveHours: Double?

    var body: some View {
        HStack(spacing: 8) {
            ZStack {
                Circle().stroke(Color.white.opacity(0.15), lineWidth: 2.5)
                Circle()
                    .trim(from: 0, to: max(0.02, min(1, ctx / 100)))
                    .stroke(Theme.blue, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: 15, height: 15)
            Text("\(Int(ctx.rounded()))%").foregroundStyle(Theme.rowTitle)
            if let f = fiveHours {
                Rectangle().fill(Color.white.opacity(0.2)).frame(width: 1, height: 14)
                Text("\(Text("5h").foregroundStyle(ChatStyle.dim)) \(Text("\(Int(f.rounded()))%").foregroundStyle(Theme.rowTitle))")
            }
        }
        .font(.system(size: 15))
        .monospacedDigit()
        .padding(.horizontal, 14)
        .frame(height: 36)
        .background(Composer.fill, in: Capsule())
        .overlay(Capsule().stroke(Composer.border, lineWidth: 1))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Context \(Int(ctx.rounded())) percent used")
    }
}
