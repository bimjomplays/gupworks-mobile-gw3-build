import Foundation
import XCTest
#if canImport(GupKit)
@testable import GupKit
#else
@testable import GupWorks3
#endif

// a157: audio files in chats play in a waveform player (AudioCard). The PC sends each file's length and 96 loudness
// values (mods/gupworks-images/bin/audio-poster); the card draws as many bars as fit and seeks where it's touched.

final class AudioMathTests: XCTestCase {
    func testBarsKeepTheLoudestOfEachSlice() {
        let peaks = [0, 100, 20, 40, 60, 10]
        XCTAssertEqual(AudioMath.bars(peaks, count: 3), [1.0, 0.4, 0.6])
        XCTAssertEqual(AudioMath.bars(peaks, count: 6).count, 6)
    }

    func testBarsStretchWhenThereAreFewerPeaksThanBars() {
        let b = AudioMath.bars([0, 100], count: 4)
        XCTAssertEqual(b.count, 4)
        XCTAssertEqual(b.last, 1.0)
    }

    func testQuietBarsStillShowAndNoPeaksIsAFlatLine() {
        let floor = AudioMath.floor
        XCTAssertEqual(AudioMath.bars([0, 0, 0], count: 3), [floor, floor, floor])
        XCTAssertEqual(AudioMath.bars([], count: 5), Array(repeating: floor, count: 5))
        XCTAssertEqual(AudioMath.bars(nil, count: 2), [floor, floor])
        XCTAssertEqual(AudioMath.bars([50], count: 0), [])
        XCTAssertEqual(AudioMath.bars([250, -4], count: 2), [1.0, floor], "clamped to 0...100")
    }

    func testBarCountFitsTheWidth() {
        XCTAssertEqual(AudioMath.barCount(width: 200), 50)
        XCTAssertEqual(AudioMath.barCount(width: 10), AudioMath.minBars)
        XCTAssertEqual(AudioMath.barCount(width: 4000), AudioMath.maxBars)
        XCTAssertEqual(AudioMath.barCount(width: .nan), AudioMath.minBars)
    }

    func testProgressAndSeek() {
        XCTAssertEqual(AudioMath.progress(time: 2, duration: 8), 0.25)
        XCTAssertEqual(AudioMath.progress(time: 20, duration: 8), 1)
        XCTAssertEqual(AudioMath.progress(time: 2, duration: 0), 0)
        XCTAssertEqual(AudioMath.progress(time: .nan, duration: 8), 0)
        XCTAssertEqual(AudioMath.seek(x: 50, width: 200, duration: 8), 2)
        XCTAssertEqual(AudioMath.seek(x: -10, width: 200, duration: 8), 0)
        XCTAssertEqual(AudioMath.seek(x: 900, width: 200, duration: 8), 8)
        XCTAssertEqual(AudioMath.seek(x: 50, width: 0, duration: 8), 0)
    }

    func testTimeLabel() {
        XCTAssertEqual(AudioMath.timeLabel(time: 0, duration: 8.4, playing: false), "0:08")
        XCTAssertEqual(AudioMath.timeLabel(time: 3.2, duration: 8.4, playing: true), "0:03 / 0:08")
        XCTAssertEqual(AudioMath.timeLabel(time: 3.2, duration: 8.4, playing: false), "0:03 / 0:08",
                       "a paused place shows where it is")
        XCTAssertEqual(AudioMath.timeLabel(time: 0, duration: 0, playing: false), "0:00")
        XCTAssertEqual(AudioMath.timeLabel(time: 65, duration: 3725, playing: true), "1:05 / 1:02:05")
    }

    func testSpeedLabel() {
        XCTAssertEqual(AudioMath.speedLabel(1), "1×")
        XCTAssertEqual(AudioMath.speedLabel(1.5), "1.5×")
        XCTAssertEqual(AudioMath.speedLabel(0.75), "0.75×")
        XCTAssertEqual(AudioMath.speeds, [0.5, 0.75, 1, 1.25, 1.5, 2])
    }
}

final class AudioModelTests: XCTestCase {
    func testAReplysAudioItemDecodes() throws {
        let json = #"{"kind":"audio","url":"/v1/media/abc","name":"Hum idea","duration":8.0,"peaks":[1,50,100]}"#
        let it = try JSONDecoder().decode(MDItem.self, from: Data(json.utf8))
        XCTAssertEqual(it.kind, "audio")
        XCTAssertEqual(it.duration, 8)
        XCTAssertEqual(it.peaks, [1, 50, 100])
        XCTAssertNil(it.error)
        let bad = try JSONDecoder().decode(MDItem.self, from: Data(#"{"kind":"audio","url":"/v1/media/x","name":"a.mp3","error":"No sound in this file"}"#.utf8))
        XCTAssertEqual(bad.error, "No sound in this file")
        XCTAssertNil(bad.peaks)
    }

    func testYourSentAudioDecodesOnThePromptAndTheQueue() throws {
        let p = try JSONDecoder().decode(Prompt.self, from: Data(
            #"{"text":"the tune","audio":[{"kind":"audio","url":"/v1/media/abc","name":"hum.m4a","duration":5,"peaks":[3]}]}"#.utf8))
        XCTAssertEqual(p.audio?.first?.name, "hum.m4a")
        let q = try JSONDecoder().decode(QueueItem.self, from: Data(
            #"{"clientId":"c1","text":"","ts":1,"state":"queued","audio":[{"kind":"audio","url":"/v1/media/abc","name":"hum.m4a"}]}"#.utf8))
        XCTAssertEqual(q.audio?.count, 1)
    }

    func testTheDemoVoiceChatHasAudioInAReplyAndInYourMessage() throws {
        let f: ChatFixture = try XCTUnwrap(Demo.load(AudioDemo.chat, in: "fixtures/chats"))
        let mine = f.turns.turns.compactMap { $0.prompt.audio }.flatMap { $0 }
        XCTAssertFalse(mine.isEmpty, "your voice memo")
        XCTAssertNotNil(mine.first?.duration)
        let replies = f.turns.turns.flatMap { $0.blocks }.flatMap { $0.md ?? [] }.flatMap { $0.items ?? [] }
            .filter { $0.kind == "audio" }
        XCTAssertGreaterThanOrEqual(replies.count, 1, "audio in Claude's reply")
        for a in mine + replies {
            XCTAssertEqual(a.peaks?.count, 96, a.name ?? "")
            XCTAssertNotNil(MediaLink.url(a.url, base: nil), "\(a.url ?? "") is in the app")
        }
    }
}
