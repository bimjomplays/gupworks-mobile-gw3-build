import XCTest
@testable import GupWorks3

/// The video player's sums: the stream link, times, double-tap sides, where a video is picked up again.
final class VideoPlayerTests: XCTestCase {
    func testStreamLinkOfAPCVideo() {
        let link = URL(string: "https://pc.example:10005/v1/media/eyJjIjoieCJ9.0123abcd")!
        XCTAssertEqual(VideoMath.stream(of: link)?.absoluteString,
                       "https://pc.example:10005/v1/media/eyJjIjoieCJ9.0123abcd/index.m3u8")
        let byAddress = URL(string: "http://pc.local:10007/v1/media/abc.def")!
        XCTAssertEqual(VideoMath.stream(of: byAddress)?.path, "/v1/media/abc.def/index.m3u8")
    }

    func testNoStreamForAnythingElse() {
        XCTAssertNil(VideoMath.stream(of: URL(fileURLWithPath: "/app/fixtures/media/dusk-loop.mp4")))
        XCTAssertNil(VideoMath.stream(of: URL(string: "https://pc/v1/chats/abc")!))
        XCTAssertNil(VideoMath.stream(of: URL(string: "https://pc/v1/media/abc/index.m3u8")!), "already a stream")
        XCTAssertNil(VideoMath.stream(of: URL(string: "https://pc/v1/media/abc?x=1")!))
    }

    func testClock() {
        XCTAssertEqual(VideoMath.clock(0), "0:00")
        XCTAssertEqual(VideoMath.clock(5.9), "0:05")
        XCTAssertEqual(VideoMath.clock(723), "12:03")
        XCTAssertEqual(VideoMath.clock(3723), "1:02:03")
        XCTAssertEqual(VideoMath.clock(.nan), "0:00")
        XCTAssertEqual(VideoMath.clock(-3), "0:00")
    }

    func testSpeeds() {
        XCTAssertEqual(VideoMath.speeds.map(VideoMath.speedLabel), ["0.5×", "0.75×", "1×", "1.25×", "1.5×", "2×"])
    }

    func testSpeedIsRememberedForTheNextVideo() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "VideoSpeedTests"))
        defaults.removePersistentDomain(forName: "VideoSpeedTests")
        let store = VideoSpeed(defaults: defaults)
        XCTAssertEqual(store.current, 1, "normal speed until one is chosen")
        for s in VideoMath.speeds {
            store.current = s
            XCTAssertEqual(store.current, s)
        }
        defaults.set(3.0, forKey: VideoSpeed.key)
        XCTAssertEqual(store.current, 1, "a speed that isn't in the menu falls back to normal")
        defaults.set("1.5", forKey: VideoSpeed.key)
        XCTAssertEqual(store.current, 1.5, "launch arguments arrive as text")
        defaults.removePersistentDomain(forName: "VideoSpeedTests")
    }

    func testClamp() {
        XCTAssertEqual(VideoMath.clamp(-4, 30), 0)
        XCTAssertEqual(VideoMath.clamp(12, 30), 12)
        XCTAssertEqual(VideoMath.clamp(45, 30), 30)
        XCTAssertEqual(VideoMath.clamp(12, 0), 12, "length not known yet")
        XCTAssertEqual(VideoMath.clamp(.nan, 30), 0)
    }

    func testDoubleTapSides() {
        XCTAssertEqual(VideoMath.side(20, width: 390), -1)
        XCTAssertEqual(VideoMath.side(195, width: 390), 0)
        XCTAssertEqual(VideoMath.side(370, width: 390), 1)
        XCTAssertEqual(VideoMath.side(10, width: 0), 0)
    }

    func testResumeOnlyInTheMiddle() {
        XCTAssertNil(VideoMath.resume(nil, duration: 60))
        XCTAssertNil(VideoMath.resume(3, duration: 60), "the first seconds start over")
        XCTAssertEqual(VideoMath.resume(20, duration: 60), 20)
        XCTAssertNil(VideoMath.resume(57, duration: 60), "the last seconds start over")
        XCTAssertNil(VideoMath.resume(.infinity, duration: 60))
    }

    func testLoadedRange() {
        let ranges: [(start: Double, length: Double)] = [(0, 8), (20, 6)]
        XCTAssertEqual(VideoMath.loaded(ranges, at: 3), 8)
        XCTAssertEqual(VideoMath.loaded(ranges, at: 21), 26, "after a seek: the range around it")
        XCTAssertEqual(VideoMath.loaded(ranges, at: 12), 12, "nothing loaded here yet")
        XCTAssertEqual(VideoMath.loaded([], at: 5), 5)
    }

    func testShortClipsLoop() {
        XCTAssertTrue(VideoMath.loopsByDefault(duration: 2, name: "dusk-loop.mp4"))
        XCTAssertFalse(VideoMath.loopsByDefault(duration: 31, name: "harbour-walk.mp4"))
        XCTAssertTrue(VideoMath.loopsByDefault(duration: 31, name: "spinner.GIF"))
        XCTAssertFalse(VideoMath.loopsByDefault(duration: 0, name: nil))
    }

    func testResumeStoreKeepsThePlace() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "VideoPlayerTests"))
        defaults.removePersistentDomain(forName: "VideoPlayerTests")
        let store = VideoResume(defaults: defaults)
        let key = VideoMath.resumeKey(name: "harbour-walk.mp4", duration: 31.2)
        XCTAssertEqual(key, "harbour-walk.mp4#31")
        store.save(14.5, duration: 31.2, for: key)
        XCTAssertEqual(store.time(for: key), 14.5)
        store.save(30, duration: 31.2, for: key)
        XCTAssertNil(store.time(for: key), "watched to the end: next time from the start")
        for i in 0..<230 { store.save(10, duration: 60, for: "v\(i)") }
        XCTAssertLessThanOrEqual((defaults.dictionary(forKey: VideoResume.key) ?? [:]).count, 200)
        defaults.removePersistentDomain(forName: "VideoPlayerTests")
    }

    @MainActor
    func testPlaybackPicksTheStreamFirst() {
        let base = URL(string: "https://pc.example:10005")
        let p = VideoPlayback(item: MDItem(kind: "video", url: "/v1/media/abc.def", name: "clip.mp4"), base: base)
        XCTAssertEqual(p.original?.absoluteString, "https://pc.example:10005/v1/media/abc.def")
        XCTAssertEqual(p.stream?.absoluteString, "https://pc.example:10005/v1/media/abc.def/index.m3u8")
        let demo = VideoPlayback(item: MDItem(kind: "video", url: "demo:media/dusk-loop.mp4", name: "dusk"), base: nil)
        XCTAssertNil(demo.stream, "a bundled clip plays as it is")
    }
}
