import Foundation
import Observation

// File transfer (a144): the phone side of the plain phone-to-PC chat. Messages come from GET /v1/transfer and stay
// live from /v1/transfer/events while the page is open. Files go up in pieces (the phone reaches the PC over
// Tailscale's relay, a few Mbit/s): each waits in the outbox (a copy in Application Support, listed in outbox.json),
// survives the app closing and goes on from where the PC's copy stands. See tools/gw3_transfer.py for the routes.

/// What the store asks of the PC (APIClient's transfer routes, or a test's fake).
@MainActor
protocol TransferLink {
    func page(before: String?) async throws -> TransferMessages
    func library() async throws -> TransferLibraryList
    func startUpload(name: String, size: Int64, type: String) async throws -> UploadState
    func uploadState(_ id: String) async throws -> UploadState
    func putPiece(_ id: String, offset: Int64, _ data: Data) async throws -> UploadState
    func send(_ m: TransferSend) async throws -> TransferMessage
    func events(after: String?) -> AsyncThrowingStream<SSEEvent, Error>
}

/// The paired PC's transfer routes.
struct PairedTransferLink: TransferLink {
    let api: APIClient
    let pairing: Pairing

    func page(before: String?) async throws -> TransferMessages { try await api.transferPage(pairing, before: before) }
    func library() async throws -> TransferLibraryList { try await api.transferLibrary(pairing) }
    func startUpload(name: String, size: Int64, type: String) async throws -> UploadState {
        try await api.startUpload(pairing, name: name, size: size, type: type)
    }
    func uploadState(_ id: String) async throws -> UploadState { try await api.uploadState(pairing, id) }
    func putPiece(_ id: String, offset: Int64, _ data: Data) async throws -> UploadState {
        try await api.putPiece(pairing, id, offset: offset, data)
    }
    func send(_ m: TransferSend) async throws -> TransferMessage { try await api.sendTransfer(pairing, m) }
    func events(after: String?) -> AsyncThrowingStream<SSEEvent, Error> {
        api.events(pairing, "/v1/transfer/events", query: after.map { [URLQueryItem(name: "after", value: $0)] } ?? [])
    }
}

/// A file of a message still on the phone.
struct OutFile: Codable, Equatable, Identifiable {
    var id: String
    var name: String
    var size: Int64
    var kind: String
    /// the copy's file name in the message's outbox folder
    var local: String
    /// the PC's upload, once started
    var upload: String?
    /// how much of it the PC has
    var sent: Int64 = 0

    var done: Bool { upload != nil && sent >= size }
}

/// A message from this phone the PC doesn't have yet: its files going up, or stopped with why.
struct OutMessage: Codable, Equatable, Identifiable {
    var clientId: String
    var ts: Double
    var text: String
    var files: [OutFile]
    var failed: String?

    var id: String { clientId }
    var total: Int64 { files.reduce(0) { $0 + $1.size } }
    var sent: Int64 { files.reduce(0) { $0 + min($1.sent, $1.size) } }
    var progress: Double { total > 0 ? Double(sent) / Double(total) : (failed == nil ? 1 : 0) }
}

/// A file picked in the composer, copied into the staging folder until it's sent.
struct StagedFile: Identifiable, Equatable {
    let id = UUID()
    var url: URL
    var name: String
    var size: Int64
    var kind: String
}

/// How big each piece is: about three seconds of what the line carried last time, so progress moves often on a slow
/// relay and a fast line isn't slowed by many small requests. Grows at most twice a step; shrinks at once.
struct PieceSizer: Equatable {
    static let smallest = 256 * 1024
    static let largest = 8 * 1024 * 1024    // gw3_transfer's CHUNK_MAX
    static let seconds = 3.0
    private(set) var size = 1024 * 1024

    mutating func took(_ seconds: Double, bytes: Int) {
        guard seconds > 0, bytes > 0 else { return }
        let want = Int(Double(bytes) / seconds * Self.seconds)
        let next = min(Self.largest, max(Self.smallest, min(want, size * 2)))
        size = next / (64 * 1024) * (64 * 1024)
    }
}

@Observable
@MainActor
final class TransferStore {
    private(set) var messages: [TransferMessage] = []
    private(set) var more = false
    private(set) var loaded = false
    private(set) var loadingOlder = false
    private(set) var error: APIError?
    private(set) var library: TransferLibraryList?
    private(set) var libraryError: APIError?
    private(set) var outbox: [OutMessage] = []
    /// where the files are on the PC (GupWorks Transfer in the home folder)
    private(set) var folder: String?
    /// bumps when a message arrives, so the chat can follow the bottom
    private(set) var liveTick = 0
    /// the composer's words and picked files: they stay when you leave the page and come back
    var draft = ""
    var staged: [StagedFile] = []
    /// a send or pick that didn't work, for an alert
    var actionError: String?
    /// the app is in front: uploads wait (without giving up) while it isn't
    var active = true {
        didSet { if active && !oldValue { pump() } }
    }

    let demo: Bool
    /// outbox.json and one folder per message with its files' copies
    let outboxDir: URL
    /// picked files wait here until sent
    let stagingDir: URL
    private let link: TransferLink?
    private var pumpTask: Task<Void, Never>?
    /// something new to send came while the pump ran (a retry): it goes round once more
    private var pumpAgain = false
    private var sizer = PieceSizer()
    private var libraryLoad: Task<Void, Never>?
    /// tries in a row that moved nothing, before a message says it couldn't be sent
    static let patience = 6
    /// waits between tries; tests make it short
    var backoff: (Int) -> UInt64 = { n in UInt64(min(15, 1 << min(n, 4))) * 1_000_000_000 }

    init(link: TransferLink?, demo: Bool, folder: URL? = nil) {
        self.link = link
        self.demo = demo
        let root = folder ?? Self.defaultFolder
        outboxDir = root.appendingPathComponent("outbox", isDirectory: true)
        stagingDir = root.appendingPathComponent("staging", isDirectory: true)
        try? FileManager.default.createDirectory(at: outboxDir, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: stagingDir, withIntermediateDirectories: true)
        if !demo { loadOutbox() }
    }

    convenience init(pairing: Pairing?, demo: Bool) {
        self.init(link: pairing.map { PairedTransferLink(api: APIClient(), pairing: $0) }, demo: demo)
    }

    /// Application Support/Transfer (not backed up: the files are on their way to the PC)
    nonisolated static var defaultFolder: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        var u = base.appendingPathComponent("Transfer", isDirectory: true)
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        var v = URLResourceValues()
        v.isExcludedFromBackup = true
        try? u.setResourceValues(v)
        return u
    }

    // MARK: messages

    /// Loads the newest page, then follows the PC's stream until the task is cancelled (the page closed). Sends what
    /// waits in the outbox meanwhile.
    func run() async {
        if demo {
            loadDemo()
            return
        }
        guard let link else { return }
        pump()
        var wait: UInt64 = 1
        while !Task.isCancelled {
            do {
                if !loaded {
                    let page = try await link.page(before: nil)
                    take(page)
                    loaded = true
                }
                error = nil
                for try await e in link.events(after: messages.last?.id) {
                    handle(e)
                    error = nil
                    wait = 1
                }
            } catch is CancellationError {
                return
            } catch let e as APIError {
                if Task.isCancelled || e.isCancelled { return }
                error = e
                if e == .notPaired { return }
            } catch {
                if Task.isCancelled { return }
            }
            try? await Task.sleep(nanoseconds: wait * 1_000_000_000)
            wait = min(wait * 2, 15)
        }
    }

    func handle(_ e: SSEEvent) {
        let data = Data(e.data.utf8)
        switch e.name {
        case "message":
            if let m = try? JSONDecoder().decode(TransferMessage.self, from: data) {
                upsert([m])
                liveTick += 1
                if !m.files.isEmpty { libraryChanged() }
            }
        case "reset":
            if let p = try? JSONDecoder().decode(TransferMessages.self, from: data) {
                messages = []
                take(p)
                liveTick += 1
                libraryChanged()
            }
        default:
            break
        }
    }

    private func take(_ p: TransferMessages) {
        upsert(p.messages)
        more = p.more
        if let f = p.folder { folder = f }
    }

    /// adds or replaces messages by id, oldest first; a message of ours that arrived leaves the outbox
    func upsert(_ new: [TransferMessage]) {
        var byId = Dictionary(messages.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        for m in new { byId[m.id] = m }
        messages = byId.values.sorted { $0.ts == $1.ts ? $0.id < $1.id : $0.ts < $1.ts }
        let arrived = Set(new.compactMap(\.clientId))
        if outbox.contains(where: { arrived.contains($0.clientId) }) {
            for cid in arrived { dropOut(cid) }
        }
    }

    func loadOlder() async {
        guard more, !loadingOlder, let oldest = messages.first?.id, let link, !demo else { return }
        loadingOlder = true
        defer { loadingOlder = false }
        do {
            let p = try await link.page(before: oldest)
            upsert(p.messages)
            more = p.more
        } catch let e as APIError {
            if !e.isCancelled { error = e }
        } catch {}
    }

    // MARK: the Library

    func loadLibrary() async {
        if demo {
            library = TransferLibraryList.of(messages, folder: folder)
            return
        }
        guard let link else { return }
        do {
            library = try await link.library()
            libraryError = nil
        } catch let e as APIError {
            if !e.isCancelled { libraryError = e }
        } catch {}
    }

    /// a file came or went: the Library loads again once things settle (only once it was opened)
    private func libraryChanged() {
        guard library != nil else { return }
        libraryLoad?.cancel()
        libraryLoad = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 800_000_000)
            if Task.isCancelled { return }
            await self?.loadLibrary()
        }
    }

    // MARK: sending

    /// whether ↑ has anything to send
    var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !staged.isEmpty
    }

    /// A file picked in the composer (already a copy in `stagingDir`, or anywhere for the tests).
    func stage(_ url: URL, name: String? = nil) {
        let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value ?? 0
        let n = name ?? url.lastPathComponent
        staged.append(StagedFile(url: url, name: n, size: size, kind: TransferKind.of(n)))
    }

    func unstage(_ id: UUID) {
        guard let i = staged.firstIndex(where: { $0.id == id }) else { return }
        let f = staged.remove(at: i)
        if f.url.path.hasPrefix(stagingDir.path) { try? FileManager.default.removeItem(at: f.url) }
    }

    /// The box's words and picked files as a message: text alone goes at once; files wait in the outbox, a copy each,
    /// and go up in the background with the bubble showing how far.
    func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        let picked = staged
        guard !text.isEmpty || !picked.isEmpty else { return }
        draft = ""
        staged = []
        let cid = "phone-" + UUID().uuidString.lowercased()
        let dir = outboxDir.appendingPathComponent(cid, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var files: [OutFile] = []
        var taken: Set<String> = []
        for f in picked {
            let local = Self.free(f.name, taken: &taken)
            let dest = dir.appendingPathComponent(local)
            do {
                if f.url.path.hasPrefix(stagingDir.path) {
                    try FileManager.default.moveItem(at: f.url, to: dest)
                } else {
                    try FileManager.default.copyItem(at: f.url, to: dest)
                }
            } catch {
                actionError = "\(f.name) couldn't be read."
                continue
            }
            files.append(OutFile(id: UUID().uuidString, name: f.name, size: f.size, kind: f.kind, local: local))
        }
        if files.isEmpty && text.isEmpty {
            try? FileManager.default.removeItem(at: dir)
            return
        }
        outbox.append(OutMessage(clientId: cid, ts: Date().timeIntervalSince1970 * 1000, text: text, files: files))
        saveOutbox()
        liveTick += 1
        if demo { demoDeliver(cid) } else { pump() }
    }

    /// "photo.jpg", then "photo 2.jpg": names in one message's folder don't clash
    nonisolated static func free(_ name: String, taken: inout Set<String>) -> String {
        let clean = name.replacingOccurrences(of: "/", with: "-")
        var n = clean.isEmpty ? "file" : clean
        let stem = (n as NSString).deletingPathExtension, ext = (n as NSString).pathExtension
        var k = 2
        while taken.contains(n.lowercased()) {
            n = ext.isEmpty ? "\(stem) \(k)" : "\(stem) \(k).\(ext)"
            k += 1
        }
        taken.insert(n.lowercased())
        return n
    }

    func retry(_ cid: String) {
        guard let i = outbox.firstIndex(where: { $0.clientId == cid }) else { return }
        outbox[i].failed = nil
        saveOutbox()
        if demo { demoDeliver(cid) } else { pump() }
    }

    func discard(_ cid: String) {
        dropOut(cid)
    }

    /// the local file of an outbox file (its picture before it's on the PC)
    func localURL(_ m: OutMessage, _ f: OutFile) -> URL {
        if demo, f.local.hasPrefix("demo:") { return MediaLink.url(f.local, base: nil) ?? outboxDir }
        return outboxDir.appendingPathComponent(m.clientId, isDirectory: true).appendingPathComponent(f.local)
    }

    private func dropOut(_ cid: String) {
        guard let i = outbox.firstIndex(where: { $0.clientId == cid }) else { return }
        outbox.remove(at: i)
        try? FileManager.default.removeItem(at: outboxDir.appendingPathComponent(cid, isDirectory: true))
        saveOutbox()
    }

    /// Sends the outbox in order, one message at a time, until it's empty or all that's left couldn't be sent.
    func pump() {
        guard !demo, link != nil else { return }
        if pumpTask != nil {
            pumpAgain = true
            return
        }
        pumpTask = Task { [weak self] in
            while let self {
                self.pumpAgain = false
                var skip: Set<String> = []
                while let m = self.outbox.first(where: { $0.failed == nil && !skip.contains($0.clientId) }) {
                    await self.deliver(m.clientId)
                    skip.insert(m.clientId)
                }
                if !self.pumpAgain { break }
            }
            self?.pumpTask = nil
        }
    }

    /// for the tests: sends what waits and returns when the pump is done
    func drain() async {
        pump()
        await pumpTask?.value
    }

    private func deliver(_ cid: String) async {
        guard let link else { return }
        var misses = 0
        while let m = outbox.first(where: { $0.clientId == cid }), m.failed == nil {
            let before = m.sent
            do {
                for f in m.files where !f.done {
                    try await upload(cid, f.id, link)
                }
                guard let now = outbox.first(where: { $0.clientId == cid }) else { return }
                let reply = try await link.send(TransferSend(text: now.text, files: now.files.compactMap(\.upload),
                                                             clientId: cid))
                upsert([reply])
                dropOut(cid)
                liveTick += 1
                if !reply.files.isEmpty { libraryChanged() }
                return
            } catch TransferError.gone {
                // the PC dropped an upload (a week unfinished): those files go up again
                await forgetGone(cid, link)
            } catch TransferError.behind(let at) {
                _ = at  // the send found a file not all there: the uploads look again
                await recheck(cid, link)
            } catch let e as APIError where e.isUnreachable {
                // the app went to the back (iOS stops its requests): it goes on when it's in front again
                if !active {
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                    continue
                }
                let moved = (outbox.first { $0.clientId == cid }?.sent ?? 0) > before
                misses = moved ? 1 : misses + 1
                if misses >= Self.patience {
                    fail(cid, e.message)
                    return
                }
                try? await Task.sleep(nanoseconds: backoff(misses))
            } catch let e as APIError {
                fail(cid, e.message)
                return
            } catch let e as LocalProblem {
                fail(cid, e.message)
                return
            } catch {
                fail(cid, error.localizedDescription)
                return
            }
        }
    }

    private struct LocalProblem: Error {
        let message: String
    }

    /// one file, from where the PC's copy stands to its end
    private func upload(_ cid: String, _ fid: String, _ link: TransferLink) async throws {
        guard var (m, f) = find(cid, fid) else { return }
        if f.upload == nil {
            let st = try await link.startUpload(name: f.name, size: f.size, type: TransferKind.mime(f.name))
            update(cid, fid) { $0.upload = st.id; $0.sent = st.received }
            guard let found = find(cid, fid) else { return }
            (m, f) = found
        }
        guard let uid = f.upload else { return }
        let url = localURL(m, f)
        while let (_, cur) = find(cid, fid), cur.sent < cur.size {
            let offset = cur.sent
            let count = Int(min(Int64(sizer.size), cur.size - offset))
            let piece: Data
            do {
                piece = try await Task.detached { try Self.readPiece(url, at: offset, count: count) }.value
            } catch {
                throw LocalProblem(message: "\(cur.name) isn't on this iPhone anymore.")
            }
            let t0 = Date()
            do {
                let st = try await link.putPiece(uid, offset: offset, piece)
                sizer.took(Date().timeIntervalSince(t0), bytes: piece.count)
                update(cid, fid) { $0.sent = st.received }
            } catch TransferError.behind(let at) {
                update(cid, fid) { $0.sent = at }
            }
        }
    }

    /// after a send found an upload gone: those start over
    private func forgetGone(_ cid: String, _ link: TransferLink) async {
        guard let m = outbox.first(where: { $0.clientId == cid }) else { return }
        for f in m.files {
            guard let uid = f.upload else { continue }
            if case .some(.gone) = await stateError(uid, link) {
                update(cid, f.id) { $0.upload = nil; $0.sent = 0 }
            }
        }
    }

    /// after a send found a file not all there: each upload's real state
    private func recheck(_ cid: String, _ link: TransferLink) async {
        guard let m = outbox.first(where: { $0.clientId == cid }) else { return }
        for f in m.files {
            guard let uid = f.upload else { continue }
            if let st = try? await link.uploadState(uid) {
                update(cid, f.id) { $0.sent = st.received }
            } else {
                update(cid, f.id) { $0.upload = nil; $0.sent = 0 }
            }
        }
    }

    private func stateError(_ uid: String, _ link: TransferLink) async -> TransferError? {
        do {
            _ = try await link.uploadState(uid)
            return nil
        } catch let e as TransferError {
            return e
        } catch {
            return nil
        }
    }

    private func find(_ cid: String, _ fid: String) -> (OutMessage, OutFile)? {
        guard let m = outbox.first(where: { $0.clientId == cid }), let f = m.files.first(where: { $0.id == fid }) else {
            return nil
        }
        return (m, f)
    }

    private func update(_ cid: String, _ fid: String, _ change: (inout OutFile) -> Void) {
        guard let i = outbox.firstIndex(where: { $0.clientId == cid }),
              let j = outbox[i].files.firstIndex(where: { $0.id == fid }) else { return }
        change(&outbox[i].files[j])
        saveOutbox()
    }

    private func fail(_ cid: String, _ why: String) {
        guard let i = outbox.firstIndex(where: { $0.clientId == cid }) else { return }
        outbox[i].failed = why
        saveOutbox()
    }

    nonisolated static func readPiece(_ url: URL, at offset: Int64, count: Int) throws -> Data {
        let h = try FileHandle(forReadingFrom: url)
        defer { try? h.close() }
        try h.seek(toOffset: UInt64(offset))
        let data = try h.read(upToCount: count) ?? Data()
        guard data.count == count else { throw CocoaError(.fileReadCorruptFile) }
        return data
    }

    // MARK: the outbox on disk

    private var outboxFile: URL { outboxDir.appendingPathComponent("outbox.json") }

    private func saveOutbox() {
        guard !demo else { return }
        if let data = try? JSONEncoder().encode(outbox) { try? data.write(to: outboxFile, options: .atomic) }
    }

    private func loadOutbox() {
        guard let data = try? Data(contentsOf: outboxFile),
              let list = try? JSONDecoder().decode([OutMessage].self, from: data) else { return }
        outbox = list
    }

    // MARK: demo

    private func loadDemo() {
        guard !loaded else { return }
        loaded = true
        guard let page: TransferMessages = Demo.load("messages", in: "fixtures/transfer") else { return }
        let shift = Date().timeIntervalSince1970 * 1000 - (page.now ?? 0)
        messages = page.messages.map { var m = $0; m.ts += shift; return m }
        more = false
        folder = page.folder
        let args = Demo.args
        if args.contains("-transferUploading") || args.contains("-transferFailed") {
            let failed = args.contains("-transferFailed")
            let video = OutFile(id: "demo-up", name: "Lake swim.mov", size: 98_900_000, kind: "video",
                                local: "demo:media/dusk-loop.mp4", upload: "demo", sent: failed ? 63_100_000 : 41_600_000)
            outbox = [OutMessage(clientId: "phone-demo", ts: Date().timeIntervalSince1970 * 1000 - 40_000,
                                 text: "the whole swim, sound on", files: [video],
                                 failed: failed ? NoAnswer.timeout.message : nil)]
        }
    }

    /// the demo's send: the files "go up" in a second or two, then the message is there
    private func demoDeliver(_ cid: String) {
        Task { [weak self] in
            guard let self else { return }
            for step in 1...6 {
                try? await Task.sleep(nanoseconds: 250_000_000)
                guard let i = outbox.firstIndex(where: { $0.clientId == cid }) else { return }
                for j in outbox[i].files.indices {
                    outbox[i].files[j].sent = outbox[i].files[j].size * Int64(step) / 6
                }
            }
            guard let m = outbox.first(where: { $0.clientId == cid }) else { return }
            if m.clientId == "phone-demo" { return }  // the seeded upload stays as it is
            let files = m.files.map { f -> TransferFile in
                let link = self.localURL(m, f).absoluteString
                return TransferFile(name: f.name, size: f.size, kind: f.kind, exists: true, url: link,
                                    thumb: f.kind == "image" ? link : nil, poster: nil)
            }
            let msg = TransferMessage(id: "\(Int(m.ts))-demo", ts: m.ts, from: "phone", text: m.text, files: files,
                                      clientId: cid)
            // its copies stay: the demo's message points at them
            outbox.removeAll { $0.clientId == cid }
            upsert([msg])
            liveTick += 1
        }
    }
}
