import Foundation
import XCTest
#if canImport(GupKit)
@testable import GupKit
#else
@testable import GupWorks3
#endif

// File transfer (a144): the models, the layout, the piece sizes and the outbox's delivery against a fake PC.

/// A PC in memory: uploads collect bytes, and it can drop the line, forget an upload or answer 409.
@MainActor
final class FakeTransferPC: TransferLink {
    var uploads: [String: (name: String, size: Int64, data: Data)] = [:]
    var sent: [TransferSend] = []
    var messages: [TransferMessage] = []
    /// the next n calls fail as if the PC didn't answer
    var dropNext = 0
    /// pieces that fail as unreachable after taking part of the bytes (the line broke partway)
    var breakAfterBytes: Int?
    /// the next send finds the uploads gone
    var forgetOnSend = false
    var puts = 0

    private func gate() throws {
        if dropNext > 0 {
            dropNext -= 1
            throw APIError.unreachable(.timeout)
        }
    }

    func page(before: String?) async throws -> TransferMessages {
        try gate()
        return TransferMessages(messages: messages, more: false, folder: "GupWorks Transfer", now: nil)
    }

    func library() async throws -> TransferLibraryList { .of(messages, folder: nil) }

    func startUpload(name: String, size: Int64, type: String) async throws -> UploadState {
        try gate()
        let id = String(format: "%016x", uploads.count + 1)
        uploads[id] = (name, size, Data())
        return UploadState(id: id, received: 0, size: size)
    }

    func uploadState(_ id: String) async throws -> UploadState {
        try gate()
        guard let u = uploads[id] else { throw TransferError.gone }
        return UploadState(id: id, received: Int64(u.data.count), size: u.size)
    }

    func putPiece(_ id: String, offset: Int64, _ data: Data) async throws -> UploadState {
        try gate()
        puts += 1
        guard var u = uploads[id] else { throw TransferError.gone }
        guard offset == Int64(u.data.count) else { throw TransferError.behind(Int64(u.data.count)) }
        if let cut = breakAfterBytes {
            breakAfterBytes = nil
            u.data.append(data.prefix(cut))
            uploads[id] = u
            throw APIError.unreachable(.dropped)
        }
        u.data.append(data)
        uploads[id] = u
        return UploadState(id: id, received: Int64(u.data.count), size: u.size)
    }

    func send(_ m: TransferSend) async throws -> TransferMessage {
        try gate()
        if forgetOnSend {
            forgetOnSend = false
            uploads = [:]
            throw TransferError.gone
        }
        if let old = messages.first(where: { $0.clientId == m.clientId }) { return old }
        var files: [TransferFile] = []
        for id in m.files {
            guard let u = uploads[id] else { throw TransferError.gone }
            guard Int64(u.data.count) == u.size else { throw TransferError.behind(Int64(u.data.count)) }
            files.append(TransferFile(name: u.name, size: u.size, kind: TransferKind.of(u.name), exists: true,
                                      url: "/v1/media/\(id)", thumb: nil, poster: nil))
        }
        sent.append(m)
        let msg = TransferMessage(id: "m\(messages.count + 1)", ts: Double(messages.count + 1), from: "phone",
                                  text: m.text, files: files, clientId: m.clientId)
        messages.append(msg)
        return msg
    }

    func events(after: String?) -> AsyncThrowingStream<SSEEvent, Error> {
        AsyncThrowingStream { $0.finish() }
    }
}

@MainActor
final class TransferStoreTests: XCTestCase {
    var dir: URL!
    var pc: FakeTransferPC!

    override func setUp() async throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("a144-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        pc = FakeTransferPC()
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: dir)
    }

    func store() -> TransferStore {
        let s = TransferStore(link: pc, demo: false, folder: dir)
        s.backoff = { _ in 1_000_000 }
        return s
    }

    /// a picked file of n bytes (a counting pattern, so a misplaced piece shows)
    func pick(_ name: String, _ n: Int) -> URL {
        let u = dir.appendingPathComponent("picked-" + name)
        let bytes = (0..<n).map { UInt8(truncatingIfNeeded: $0 &* 31 &+ $0 / 251) }
        try! Data(bytes).write(to: u)
        return u
    }

    func testTextGoesAlone() async {
        let s = store()
        s.draft = "  hello PC  "
        XCTAssertTrue(s.canSend)
        s.send()
        XCTAssertEqual(s.draft, "")
        XCTAssertEqual(s.outbox.count, 1)
        await s.drain()
        XCTAssertEqual(pc.sent.map(\.text), ["hello PC"])
        XCTAssertEqual(pc.sent.first?.files, [])
        XCTAssertEqual(s.outbox, [])
        XCTAssertEqual(s.messages.map(\.text), ["hello PC"])
        XCTAssertTrue(s.messages[0].mine)
    }

    func testFileGoesUpInPiecesAndTheCopyIsRemoved() async throws {
        let s = store()
        let src = pick("clip.mov", 2_500_000)
        s.stage(src, name: "clip.mov")
        XCTAssertEqual(s.staged.first?.kind, "video")
        XCTAssertEqual(s.staged.first?.size, 2_500_000)
        s.send()
        let cid = try XCTUnwrap(s.outbox.first?.clientId)
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent("outbox/\(cid)/clip.mov").path))
        await s.drain()
        XCTAssertEqual(pc.uploads.values.first?.data, try Data(contentsOf: src))
        XCTAssertGreaterThan(pc.puts, 1)
        XCTAssertEqual(s.outbox, [])
        XCTAssertEqual(s.messages.first?.files.first?.name, "clip.mov")
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.appendingPathComponent("outbox/\(cid)").path))
        // the picked original is the user's: it stays
        XCTAssertTrue(FileManager.default.fileExists(atPath: src.path))
    }

    func testABrokenLineGoesOnFromWhereThePCStands() async throws {
        let s = store()
        let src = pick("big.bin", 3_000_000)
        s.stage(src)
        pc.breakAfterBytes = 300_000
        s.send()
        await s.drain()
        XCTAssertEqual(pc.uploads.count, 1)
        XCTAssertEqual(pc.uploads.values.first?.data, try Data(contentsOf: src))
        XCTAssertEqual(pc.sent.count, 1)
    }

    func testAWhileWithoutThePCStopsWithRetryThenRetrySends() async throws {
        let s = store()
        s.stage(pick("photo.jpg", 10_000))
        s.draft = "look"
        pc.dropNext = TransferStore.patience
        s.send()
        await s.drain()
        XCTAssertEqual(s.outbox.count, 1)
        XCTAssertNotNil(s.outbox[0].failed)
        XCTAssertEqual(pc.sent.count, 0)
        // it waits in the outbox across a restart
        let again = store()
        XCTAssertEqual(again.outbox.map(\.clientId), s.outbox.map(\.clientId))
        again.retry(again.outbox[0].clientId)
        XCTAssertNil(again.outbox.first?.failed)
        await again.drain()
        XCTAssertEqual(again.outbox, [])
        XCTAssertEqual(pc.sent.map(\.text), ["look"])
    }

    func testAnUploadThePCForgotStartsOver() async throws {
        let s = store()
        let src = pick("doc.pdf", 600_000)
        s.stage(src)
        pc.forgetOnSend = true
        s.send()
        await s.drain()
        XCTAssertEqual(pc.sent.count, 1)
        XCTAssertEqual(pc.uploads.count, 1)
        XCTAssertEqual(pc.uploads.values.first?.data, try Data(contentsOf: src))
        XCTAssertEqual(s.outbox, [])
    }

    func testAfterARestartTheSameUploadGoesOn() async throws {
        let src = pick("half.bin", 2_000_000)
        let s = store()
        s.stage(src)
        pc.breakAfterBytes = 500_000
        pc.dropNext = 1000      // after the broken piece the PC is gone: the message stops with Retry
        s.send()
        // the first piece breaks before dropNext counts: let the break happen first
        pc.dropNext = 0
        let breakThenGone = Task { @MainActor in
            while self.pc.breakAfterBytes != nil { try? await Task.sleep(nanoseconds: 1_000_000) }
            self.pc.dropNext = 1000
        }
        await s.drain()
        await breakThenGone.value
        XCTAssertNotNil(s.outbox.first?.failed)
        XCTAssertEqual(pc.uploads.values.first?.data.count, 500_000)
        pc.dropNext = 0
        let again = store()
        XCTAssertEqual(again.outbox.first?.files.first?.upload, pc.uploads.keys.first)
        again.retry(again.outbox[0].clientId)
        await again.drain()
        XCTAssertEqual(pc.uploads.count, 1)   // the same upload, not a new one
        XCTAssertEqual(pc.uploads.values.first?.data, try Data(contentsOf: src))
        XCTAssertEqual(again.outbox, [])
    }

    func testSameMessageTwiceIsOneMessage() async {
        let s = store()
        let m = TransferMessage(id: "a", ts: 1, from: "pc", text: "hi", files: [], clientId: nil)
        s.upsert([m])
        s.upsert([m, TransferMessage(id: "b", ts: 2, from: "phone", text: "yo", files: [], clientId: "phone-x")])
        XCTAssertEqual(s.messages.map(\.id), ["a", "b"])
        XCTAssertEqual(s.messages.map(\.mine), [false, true])
    }

    func testLiveEvents() {
        let s = store()
        s.handle(SSEEvent(name: "message", data: #"{"id":"1-a","ts":1,"from":"pc","text":"from the PC","files":[]}"#))
        XCTAssertEqual(s.messages.map(\.text), ["from the PC"])
        XCTAssertEqual(s.liveTick, 1)
        s.handle(SSEEvent(name: "reset", data: #"{"messages":[{"id":"2-b","ts":2,"from":"phone","text":"new","files":[]}],"more":true}"#))
        XCTAssertEqual(s.messages.map(\.id), ["2-b"])
        XCTAssertTrue(s.more)
        s.handle(SSEEvent(name: "ping", data: "{}"))
        XCTAssertEqual(s.messages.count, 1)
    }

    func testUnstageRemovesOnlyStagingCopies() {
        let s = store()
        let mine = pick("keep.txt", 10)
        let copy = s.stagingDir.appendingPathComponent("copy.txt")
        try! Data("x".utf8).write(to: copy)
        s.stage(mine)
        s.stage(copy)
        s.unstage(s.staged[0].id)
        s.unstage(s.staged[0].id)
        XCTAssertTrue(FileManager.default.fileExists(atPath: mine.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: copy.path))
        XCTAssertFalse(s.canSend)
    }

    func testDemoLoadsTheFixturesAndALibrary() async {
        let old = Demo.args
        Demo.args = ["-demo", "-transferUploading"]
        defer { Demo.args = old }
        let s = TransferStore(link: nil, demo: true, folder: dir)
        await s.run()
        XCTAssertGreaterThan(s.messages.count, 8)
        XCTAssertTrue(s.messages.contains { $0.mine } && s.messages.contains { !$0.mine })
        XCTAssertLessThan(abs((s.messages.last?.ts ?? 0) - Date().timeIntervalSince1970 * 1000), 10 * 60_000)
        XCTAssertEqual(s.outbox.first?.files.first?.name, "Lake swim.mov")
        XCTAssertEqual(s.outbox.first.map { Int($0.progress * 100) }, 42)
        await s.loadLibrary()
        let lib = s.library!
        XCTAssertEqual(lib.items.map(\.ts), lib.items.map(\.ts).sorted(by: >))
        XCTAssertEqual(lib.media.count, 5)
        XCTAssertEqual(Set(lib.files.map(\.name)), ["Shelf cut list.pdf", "backyard-notes.txt"])
        for item in lib.items {
            XCTAssertNotNil(MediaLink.url(item.url, base: nil), item.name)
            if item.isMedia { XCTAssertNotNil(MediaLink.url(item.thumb ?? item.poster, base: nil), item.name) }
        }
        XCTAssertNotNil(MediaLink.url(s.outbox[0].files[0].local, base: nil))
    }
}

final class TransferLogicTests: XCTestCase {
    func testDecodesTheServersMessages() throws {
        let json = #"""
        {"messages":[{"id":"1790000000000-ab12cd","ts":1790000000000,"from":"pc","text":"","files":[
          {"name":"a.jpg","size":12,"kind":"image","exists":true,"url":"/v1/media/x.y","thumb":"/v1/media/t.y"},
          {"name":"gone.pdf","size":3,"kind":"file","exists":false}],"clientId":"pc-1"}],
         "more":true,"folder":"GupWorks Transfer"}
        """#
        let p = try JSONDecoder().decode(TransferMessages.self, from: Data(json.utf8))
        XCTAssertEqual(p.messages.count, 1)
        XCTAssertFalse(p.messages[0].mine)
        XCTAssertEqual(p.messages[0].files.map(\.there), [true, false])
        XCTAssertEqual(p.messages[0].files.map(\.isMedia), [true, false])
        let lib = TransferLibraryList.of(p.messages, folder: p.folder)
        XCTAssertEqual(lib.items.map(\.id), ["1790000000000-ab12cd/0"])
    }

    func testUploadAnswers() throws {
        XCTAssertEqual(try APIClient.uploadAnswer(200, Data(#"{"id":"ab","received":5,"size":9}"#.utf8)),
                       UploadState(id: "ab", received: 5, size: 9))
        XCTAssertThrowsError(try APIClient.uploadAnswer(404, Data())) { XCTAssertEqual($0 as? TransferError, .gone) }
        XCTAssertThrowsError(try APIClient.uploadAnswer(409, Data(#"{"error":"offset","received":7}"#.utf8))) {
            XCTAssertEqual($0 as? TransferError, .behind(7))
        }
        XCTAssertThrowsError(try APIClient.uploadAnswer(401, Data())) { XCTAssertEqual($0 as? APIError, .notPaired) }
        XCTAssertThrowsError(try APIClient.uploadAnswer(500, Data(#"{"error":"disk full"}"#.utf8)))
    }

    func testKinds() {
        XCTAssertEqual(TransferKind.of("IMG_1.HEIC"), "image")
        XCTAssertEqual(TransferKind.of("clip.MOV"), "video")
        XCTAssertEqual(TransferKind.of("notes"), "file")
        XCTAssertEqual(TransferKind.mime("a.heic"), "image/heic")
        XCTAssertEqual(TransferKind.mime("x.weird"), "application/octet-stream")
    }

    func testBytes() {
        XCTAssertEqual(Format.bytes(900), "900 B")
        XCTAssertEqual(Format.bytes(37_000), "36 KB")
        XCTAssertEqual(Format.bytes(5_000_000), "4.8 MB")
        XCTAssertEqual(Format.bytes(98_900_000), "94 MB")
        XCTAssertEqual(Format.bytes(2_300_000_000), "2.1 GB")
        XCTAssertEqual(Format.bytes(-5), "0 B")
    }

    func testDayTime() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let loc = Locale(identifier: "en_US")
        let now = Date(timeIntervalSince1970: 1_790_000_000)  // Sat 2026-09-21 ~ 13:33 UTC
        let ms = { (d: Date) in d.timeIntervalSince1970 * 1000 }
        XCTAssertTrue(Format.dayTime(ms(now), now: now, calendar: cal, locale: loc).hasPrefix("Today "))
        XCTAssertTrue(Format.dayTime(ms(now) - 86_400_000, now: now, calendar: cal, locale: loc).hasPrefix("Yesterday "))
        let three = Format.dayTime(ms(now) - 3 * 86_400_000, now: now, calendar: cal, locale: loc)
        XCTAssertFalse(three.hasPrefix("Today") || three.hasPrefix("Yesterday"))
        XCTAssertFalse(three.contains(where: \.isNumber) && three.first!.isNumber)
        let old = Format.dayTime(ms(now) - 40 * 86_400_000, now: now, calendar: cal, locale: loc)
        XCTAssertTrue(old.contains("Aug"), old)
    }

    func testLayout() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let base = 1_790_000_000_000.0
        let m = { (id: String, min: Double, from: String) in
            TransferMessage(id: id, ts: base + min * 60_000, from: from, text: id, files: [], clientId: nil)
        }
        let list = [m("a", 0, "pc"), m("b", 1, "pc"), m("c", 2, "phone"), m("d", 40, "phone")]
        XCTAssertEqual(TransferLayout.timeLines(list, calendar: cal), ["a", "d"])
        XCTAssertEqual(TransferLayout.spacing(list[0], after: nil), 0)
        XCTAssertEqual(TransferLayout.spacing(list[1], after: list[0]), 4)
        XCTAssertEqual(TransferLayout.spacing(list[2], after: list[1]), 14)
    }

    func testPieceSizer() {
        var s = PieceSizer()
        XCTAssertEqual(s.size, 1024 * 1024)
        // a fast line: grows at most twice a step, up to the PC's limit
        for _ in 0..<10 { s.took(0.1, bytes: s.size) }
        XCTAssertEqual(s.size, PieceSizer.largest)
        // the relay at ~3 Mbit/s: about three seconds' worth (~1.1 MB)
        s.took(8 * 1024 * 1024 / 375_000.0, bytes: 8 * 1024 * 1024)
        XCTAssertEqual(Double(s.size), 1_125_000, accuracy: 70_000)
        // very slow: never under the floor
        s.took(60, bytes: 300_000)
        XCTAssertEqual(s.size, PieceSizer.smallest)
        XCTAssertEqual(s.size % (64 * 1024), 0)
    }

    func testFreeNames() {
        var taken: Set<String> = []
        XCTAssertEqual(TransferStore.free("photo.jpg", taken: &taken), "photo.jpg")
        XCTAssertEqual(TransferStore.free("Photo.JPG", taken: &taken), "Photo 2.JPG")
        XCTAssertEqual(TransferStore.free("a/b", taken: &taken), "a-b")
        XCTAssertEqual(TransferStore.free("", taken: &taken), "file")
    }
}
