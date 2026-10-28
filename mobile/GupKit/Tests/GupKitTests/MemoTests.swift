import XCTest
#if canImport(GupKit)
@testable import GupKit
#else
@testable import GupWorks3
#endif

final class MemoFlowTests: XCTestCase {
    func testRecordStopPreviewSend() {
        var f = MemoFlow()
        XCTAssertEqual(f.phase, .idle)
        XCTAssertTrue(f.start())
        XCTAssertTrue(f.recording)
        XCTAssertFalse(f.start(), "already recording")
        f.stop(seconds: 4.2)
        XCTAssertEqual(f.phase, .preview)
        XCTAssertTrue(f.hasMemo)
        f.reset()  // sent with the message
        XCTAssertEqual(f.phase, .idle)
    }

    func testTooShortIsNoMemo() {
        var f = MemoFlow()
        f.start()
        f.stop(seconds: 0.2)
        XCTAssertEqual(f.phase, .idle)
    }

    func testCancelAndReRecord() {
        var f = MemoFlow()
        f.start()
        f.reset()  // ✕ while recording
        XCTAssertEqual(f.phase, .idle)
        f.start()
        f.stop(seconds: 3)
        XCTAssertTrue(f.start(), "re-record from the preview")
        XCTAssertEqual(f.phase, .recording)
        f.stop(seconds: 2)
        XCTAssertEqual(f.phase, .preview)
        f.reset()  // Delete
        XCTAssertFalse(f.hasMemo)
    }

    func testStopWhenNotRecordingDoesNothing() {
        var f = MemoFlow()
        f.stop(seconds: 9)
        XCTAssertEqual(f.phase, .idle)
    }
}

final class MemoMathTests: XCTestCase {
    func testPeaksTakeTheLoudestOfEachSlice() {
        let levels: [Float] = [0, 0.5, 0.1, 1.2, 0.3, -0.1, 0.25, 0.75]
        XCTAssertEqual(MemoMath.peaks(levels, count: 4), [50, 100, 30, 75])
        XCTAssertEqual(MemoMath.peaks([], count: 4), [])
    }

    func testPeaksStretchAShortMemo() {
        let p = MemoMath.peaks([0.2, 0.9], count: 6)
        XCTAssertEqual(p.count, 6)
        XCTAssertEqual(p, [20, 20, 20, 90, 90, 90])
        XCTAssertEqual(MemoMath.peaks(Array(repeating: 0.5, count: 1000)).count, 96)
    }

    func testFileName() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let d = Date(timeIntervalSince1970: 1_793_197_805)  // 2026-10-28 14:30:05 UTC
        XCTAssertEqual(MemoMath.fileName(d, calendar: cal), "voice-memo-2026-10-28-143005.m4a")
    }

    func testTimer() {
        XCTAssertEqual(VoiceMath.clock(0), "0:00")
        XCTAssertEqual(VoiceMath.clock(7.9), "0:07")
        XCTAssertEqual(VoiceMath.clock(83), "1:23")
    }

    func testCardTitle() {
        XCTAssertEqual(AudioMath.title("voice-memo-2026-10-28-143005.m4a"), "Voice memo")
        XCTAssertEqual(AudioMath.title("20261028-143010-3fa2c1-voice-memo-2026-10-28-143005.m4a"), "Voice memo",
                       "as the PC saved the upload")
        XCTAssertEqual(AudioMath.title("hum-idea.m4a"), "hum-idea.m4a")
        XCTAssertEqual(AudioMath.title("my-voice-memo-notes.m4a"), "my-voice-memo-notes.m4a")
        XCTAssertEqual(AudioMath.title(nil), "Audio")
    }

    func testIsAudio() {
        XCTAssertTrue(MemoMath.isAudio(type: "audio/mp4", name: "x"))
        XCTAssertTrue(MemoMath.isAudio(type: "application/octet-stream", name: "Take.M4A"))
        XCTAssertFalse(MemoMath.isAudio(type: "image/jpeg", name: "a.jpg"))
    }
}

@MainActor
final class MemoSendTests: XCTestCase {
    func testDemoSendsAMemoAlone() async throws {
        let s = ChatStore(id: "", pairing: nil, demo: true)
        await s.run()
        let memo = Attachment(name: "voice-memo-2026-10-28-143005.m4a", type: MemoMath.type, data: Data([1, 2, 3]),
                              image: nil, uploaded: nil, duration: 4.5, peaks: [10, 80, 40])
        await s.send(text: "", attachments: [memo])
        XCTAssertEqual(s.turns.count, 1)
        let audio = try XCTUnwrap(s.turns[0].prompt.audio)
        XCTAssertEqual(audio.count, 1)
        XCTAssertEqual(audio[0].kind, "audio")
        XCTAssertEqual(audio[0].name, memo.name)
        XCTAssertEqual(audio[0].duration, 4.5)
        XCTAssertEqual(audio[0].peaks, [10, 80, 40])
        let url = try XCTUnwrap(URL(string: try XCTUnwrap(audio[0].url)))
        XCTAssertEqual(try Data(contentsOf: url), Data([1, 2, 3]), "the bubble plays the memo itself")
    }

    func testPhotosAreNoAudio() {
        let a = Attachment(name: "a.jpg", type: "image/jpeg", data: Data([1]), image: nil, uploaded: nil)
        XCTAssertNil(ChatStore.demoAudio([a]))
    }
}
