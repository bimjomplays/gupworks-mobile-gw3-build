import Foundation
import XCTest
#if canImport(GupKit)
@testable import GupKit
#else
@testable import GupWorks3
#endif

/// a181: the phone Studio's Edit stage (docs/studio-phone-mockups 15-28): the timeline changes as the desktop
/// makes them, the player's pictures and sound, the requests and the demo.
final class StudioEditTests: XCTestCase {
    private func model() -> StudioModel {
        StudioModel(
            video: [StudioClip(id: "v1", start: 0, dur: 4, shot: "s1", kenburns: "in"),
                    StudioClip(id: "v2", start: 4, dur: 3, shot: "s2"),
                    StudioClip(id: "v3", start: 7, dur: 5, shot: "s3", transition: "crossfade", fade: 0.6)],
            overlay: [StudioClip(id: "t1", start: 4.5, dur: 2, text: "Hello", style: "lower")],
            music: [StudioClip(id: "mu1", start: 0, dur: 12, file: "sound/music/a.m4a", gain: 0.3)],
            sfx: [StudioClip(id: "fx1", start: 5, dur: 1, file: "sound/freesound/b.m4a")])
    }

    private let shots: [String: StudioShot] = [
        "s1": StudioShot(id: "s1", lines: [], start: 0, end: 4, style: "still", description: "A rock", status: "rendered",
                         src: "studio/shots/s1.jpg", from: "render"),
        "s2": StudioShot(id: "s2", lines: [], start: 4, end: 7, style: "clip", description: "The sea", status: "rendered",
                         src: "studio/shots/s2.mp4", from: "draft"),
        "s3": StudioShot(id: "s3", lines: [], start: 7, end: 12, style: "still", description: "No picture yet",
                         status: "planned"),
    ]

    // MARK: changes

    func testSplit() {
        var m = model()
        XCTAssertNil(StudioEdit.split(&m, "v2", at: 4.01), "not inside by a frame")
        XCTAssertEqual(StudioEdit.split(&m, "v2", at: 5.5), "v2-2")
        XCTAssertEqual(m.video.map(\.id), ["v1", "v2", "v2-2", "v3"])
        XCTAssertEqual(m.video[1].dur, 1.5)
        XCTAssertEqual(m.video[2].start, 5.5)
        XCTAssertEqual(m.video[2].dur, 1.5)
        // a sound clip's second half plays on from where it was
        XCTAssertEqual(StudioEdit.split(&m, "mu1", at: 3), "mu1-2")
        XCTAssertEqual(m.music[1].trim, 3)
        XCTAssertEqual(StudioEdit.split(&m, "v3", at: 9), "v3-2")
        XCTAssertNil(m.video.last?.transition, "the second part has no transition into it")
    }

    func testTrimStopsAtNeighboursAndSnaps() {
        var m = model()
        let o = m.video[1]
        let snaps = StudioEdit.snapPoints(m, voice: [], playhead: 6.2, skip: "v2")
        // dragging the right edge past the next shot stops at it
        StudioEdit.trim(&m, original: o, edge: .right, by: 10, shots: shots, snaps: [], within: 0.1)
        XCTAssertEqual(m.video[1].end, 7)
        m = model()
        // near the playhead it sticks to it
        let hit = StudioEdit.trim(&m, original: o, edge: .right, by: -0.75, shots: shots, snaps: snaps, within: 0.1)
        XCTAssertEqual(hit?.what, "the playhead")
        XCTAssertEqual(m.video[1].dur, 2.2)
        // a draft clip can't start before its file does
        m = model()
        StudioEdit.trim(&m, original: o, edge: .left, by: -2, shots: shots, snaps: [], within: 0.1)
        XCTAssertEqual(m.video[1].start, 4)
        StudioEdit.trim(&m, original: o, edge: .left, by: 1, shots: shots, snaps: [], within: 0.1)
        XCTAssertEqual(m.video[1].start, 5)
        XCTAssertEqual(m.video[1].trim, 1)
        XCTAssertEqual(m.video[1].end, 7)
    }

    func testSnapToWords() {
        let voice = [StudioVoiceLine(id: "c1", chapter: 0, text: "the storm came", start: 10, end: 12, file: nil,
                                     words: [StudioEditWord(w: "storm,", t: 0.3, end: 0.8)])]
        let pts = StudioEdit.snapPoints(StudioModel(), voice: voice, playhead: 0, skip: nil)
        let s = StudioEdit.snap(10.85, pts, within: 0.1)
        XCTAssertEqual(s.t, 10.8, accuracy: 1e-9)
        XCTAssertEqual(s.to?.what, "“storm”")
        XCTAssertNil(StudioEdit.snap(10.5, pts, within: 0.1).to)
    }

    func testMoveText() {
        var m = model()
        let o = m.overlay[0]
        StudioEdit.move(&m, original: o, by: 0.53, snaps: StudioEdit.snapPoints(m, voice: [], playhead: 0, skip: "t1"),
                        within: 0.1)
        XCTAssertEqual(m.overlay[0].start, 5, "snapped to fx1's start")
        StudioEdit.move(&m, original: o, by: -10, snaps: [], within: 0.1)
        XCTAssertEqual(m.overlay[0].start, 0)
    }

    func testReorderMovesWhatIsInsideAShot() {
        var m = model()
        let along = StudioEdit.reorder(&m, order: ["v2", "v1", "v3"])
        XCTAssertEqual(m.video.map(\.id), ["v2", "v1", "v3"])
        XCTAssertEqual(m.video.map(\.start), [0, 3, 7])
        XCTAssertEqual(Set(along), ["t1", "fx1"])
        XCTAssertEqual(m.overlay[0].start, 0.5)
        XCTAssertEqual(m.sfx[0].start, 1)
        XCTAssertEqual(m.music[0].start, 0, "music isn't part of a shot")
        XCTAssertEqual(StudioEdit.reorder(&m, order: ["v2", "v1", "v3"]), [], "the same order changes nothing")
    }

    func testTransitionFadesSoundAtTheCut() {
        var m = model()
        m.sfx.append(StudioClip(id: "fx2", start: 2, dur: 2, file: "x.m4a"))
        StudioEdit.setTransition(&m, ["v2"], kind: "dip", fade: 0.8, sound: true)
        XCTAssertEqual(m.video[1].transition, "dip")
        XCTAssertEqual(m.video[1].fade, 0.8)
        XCTAssertEqual(m.sfx.first { $0.id == "fx2" }?.fadeOut, 0.8)
        StudioEdit.setTransition(&m, ["v2"], kind: "cut", fade: 0.8, sound: false)
        XCTAssertNil(m.video[1].transition)
        XCTAssertNil(m.video[1].fade)
    }

    func testAdding() {
        var m = model()
        let photo = StudioPhoto(id: "p1", title: "Old light", file: "research/media/p1.jpg", kind: "image",
                                rights: "public-domain", credit: "", cleared: true, rejected: false)
        let id = StudioEdit.addPhoto(&m, photo, at: 5.01)
        XCTAssertEqual(id, "v4")
        XCTAssertEqual(m.video.map(\.id), ["v1", "v2", "v4", "v3"])
        XCTAssertEqual(m.video[1].dur, 1, "the shot before ends where the photo starts")
        XCTAssertEqual(m.video[2].start, 5)
        XCTAssertEqual(m.video[2].kenburns, "in")
        XCTAssertEqual(StudioEdit.addText(&m, at: 1), "t2")
        let mu = StudioEdit.addSound(&m, .music, file: "m.m4a", seconds: 64, at: 2, duration: 12)
        XCTAssertEqual(m.music.first { $0.id == mu }?.dur, 10, "music runs to the end")
        XCTAssertEqual(m.music.first { $0.id == mu }?.gain, 0.3)
        let fx = StudioEdit.addSound(&m, .sfx, file: "f.m4a", seconds: 1.4, at: 2, duration: 12)
        XCTAssertEqual(m.sfx.first { $0.id == fx }?.dur, 1.4)
    }

    func testWords() {
        XCTAssertEqual(StudioEdit.clock(52.44), "0:52.4")
        XCTAssertEqual(StudioEdit.clock(3725, tenths: false), "1:02:05")
        let m = model()
        XCTAssertEqual(StudioEdit.selectionLabel("v1", m, voice: [], shots: shots), "timeline clip v1 on video: shot s1: A rock")
        XCTAssertEqual(StudioEdit.selectionLabel("t1", m, voice: [], shots: shots), "timeline clip t1 on overlay: \"Hello\"")
        let voice = [StudioVoiceLine(id: "c2", chapter: 0, text: "Hi there", start: 1, end: 2.5, file: nil, words: [])]
        XCTAssertEqual(StudioEdit.selectionLabel("voice:c2", m, voice: voice, shots: shots),
                       "voice line c2 (1.00–2.50 s): \"Hi there\"")
    }

    func testChapters() {
        let voice = [StudioVoiceLine(id: "a", chapter: 0, text: "", start: 0, end: 3, file: nil, words: []),
                     StudioVoiceLine(id: "b", chapter: 0, text: "", start: 3.5, end: 6, file: nil, words: []),
                     StudioVoiceLine(id: "c", chapter: 1, text: "", start: 7, end: 11, file: nil, words: [])]
        let ch = StudioEdit.chapters(voice)
        XCTAssertEqual(ch.map(\.title), ["Chapter 1", "Chapter 2"])
        XCTAssertEqual(ch[0].end, 6)
        XCTAssertEqual(StudioEdit.chapter(at: 6.5, ch)?.chapter, 0)
        XCTAssertEqual(StudioEdit.shots(in: ch[1], model()), ["v3"])
    }

    // MARK: the player

    func testKenBurnsAsTheDesktop() {
        XCTAssertEqual(StudioPreview.kenburns("in", zoom: nil, p: 0.5).scale, 1.075, accuracy: 1e-9)
        XCTAssertEqual(StudioPreview.kenburns("out", zoom: 1.5, p: 1).scale, 1, accuracy: 1e-9)
        let l = StudioPreview.kenburns("left", zoom: nil, p: 0)
        XCTAssertEqual(l.scale, 1.15, accuracy: 1e-9)
        XCTAssertEqual(l.tx, 1.15 * 0.05, accuracy: 1e-9, "a default pan moves 5%")
        XCTAssertEqual(StudioPreview.kenburns("right", zoom: nil, p: 0).tx, -1.15 * 0.05, accuracy: 1e-9)
        XCTAssertEqual(StudioPreview.kenburns(nil, zoom: 2, p: 0.5).scale, 1)
    }

    func testLayersCrossfadeAndDip() {
        var m = model()
        let ready: (String) -> Bool = { _ in true }
        // v3 crossfades over 0.6 s: v2 stays under it
        var ls = StudioPreview.layers(at: 7.3, m, shots: shots, ready: ready)
        XCTAssertEqual(ls.map(\.clip), ["v2", "v3"])
        XCTAssertEqual(ls[1].opacity, 0.5, accuracy: 1e-9)
        XCTAssertEqual(ls[1].source, .card, "no picture yet")
        XCTAssertEqual(ls[0].source, .video("studio/shots/s2.mp4"))
        XCTAssertEqual(ls[0].time, 3.3, accuracy: 1e-9)
        // a dip into v2: v1 fades out over its last 0.4 s, v2 in over its first 0.4 s
        m.video[1].transition = "dip"
        m.video[1].fade = 0.8
        ls = StudioPreview.layers(at: 3.8, m, shots: shots, ready: ready)
        XCTAssertEqual(ls.map(\.clip), ["v1"])
        XCTAssertEqual(ls[0].opacity, 0.5, accuracy: 1e-9)
        ls = StudioPreview.layers(at: 4.1, m, shots: shots, ready: ready)
        XCTAssertEqual(ls.map(\.clip), ["v2"])
        XCTAssertEqual(ls[0].opacity, 0.25, accuracy: 1e-9)
        // a file not loaded yet shows its card
        ls = StudioPreview.layers(at: 1, m, shots: shots, ready: { _ in false })
        XCTAssertEqual(ls[0].source, .card)
        ls = StudioPreview.layers(at: 2, m, shots: shots, ready: ready)
        XCTAssertEqual(ls[0].source, .image("studio/shots/s1.jpg"))
        XCTAssertEqual(ls[0].scale, 1.075, accuracy: 1e-9)
    }

    func testPlacementsAndCuts() {
        let m = model()
        let p = StudioPreview.videoPlacements(m, shots: shots, ready: { _ in true })
        XCTAssertEqual(p, [StudioPreview.Placement(clip: "v2", file: "studio/shots/s2.mp4", start: 4, from: 0, dur: 3.6)])
        XCTAssertEqual(StudioPreview.cuts(m, duration: 12), [0, 4, 7, 7.6, 12])
        let o = StudioPreview.overlays(at: 4.55, m)
        XCTAssertEqual(o.count, 1)
        XCTAssertEqual(o[0].opacity, 0.25, accuracy: 1e-6)
    }

    /// the same numbers gw3_studio_sound.duck_ranges and duck_amount give
    func testDuckMatchesThePC() {
        let voice = [StudioVoiceLine(id: "a", chapter: 0, text: "", start: 1, end: 3, file: nil,
                                     words: [StudioEditWord(w: "a", t: 0.1, end: 0.5), StudioEditWord(w: "b", t: 0.9, end: 1.6)]),
                     StudioVoiceLine(id: "b", chapter: 0, text: "", start: 5, end: 6, file: nil, words: [])]
        let r = StudioPreview.duckRanges(voice, hold: 0.5)
        XCTAssertEqual(r.map(\.0), [1.1, 5])
        XCTAssertEqual(r.map(\.1), [2.6, 6])
        let want: [(Double, Double)] = [(0.8, 0), (0.9, 0.2), (1.1, 1), (1.5, 1), (2.6, 1), (2.9, 0.5), (3.5, 0), (4.9, 0.6),
                                        (5.5, 1), (6.3, 0.5)]
        for (t, a) in want {
            XCTAssertEqual(StudioPreview.duckAmount(t, r, attack: 0.25, release: 0.6), a, accuracy: 1e-4, "at \(t)")
        }
        XCTAssertTrue(StudioPreview.ducks(.music, StudioClip(id: "m", start: 0, dur: 1)))
        XCTAssertFalse(StudioPreview.ducks(.music, StudioClip(id: "m", start: 0, dur: 1, duck: false)))
        XCTAssertFalse(StudioPreview.ducks(.sfx, StudioClip(id: "f", start: 0, dur: 1)))
        XCTAssertTrue(StudioPreview.ducks(.sfx, StudioClip(id: "f", start: 0, dur: 1, duck: true)))
    }

    func testSoundsVolumes() {
        var mix = StudioMix()
        mix.music.gain = 0.5
        mix.duck.on = false
        mix.lines = ["c1": StudioLineMix(gain: 0.5, fadeIn: 1, fadeOut: nil)]
        var m = model()
        m.music[0].fadeIn = 2
        let voice = [StudioVoiceLine(id: "c1", chapter: 0, text: "", start: 1, end: 3, file: "v/c1.wav", words: [])]
        let s = StudioPreview.sounds(m, voice: voice, mix: mix, lengths: ["v/c1.wav": 2.5], ready: { $0 != "sound/freesound/b.m4a" })
        XCTAssertEqual(s.map(\.id), ["voice:c1", "mu1"])
        let v = s[0]
        XCTAssertEqual(v.dur, 2.5, "the whole file plays")
        XCTAssertEqual(v.gain.first, StudioPreview.Point(t: 1, g: 0))
        XCTAssertEqual(v.gain[1], StudioPreview.Point(t: 2, g: 0.5))
        XCTAssertEqual(s[1].gain, [StudioPreview.Point(t: 0, g: 0), StudioPreview.Point(t: 2, g: 0.15), StudioPreview.Point(t: 12, g: 0.15)])
        // ducked: down by the depth while the voice speaks
        mix.duck.on = true
        mix.duck.depth = 20
        let d = StudioPreview.sounds(m, voice: voice, mix: mix, ready: { _ in true }).first { $0.id == "mu1" }!
        let mid = d.gain.first { $0.t == 2 }!
        XCTAssertEqual(mid.g, 0.015, accuracy: 1e-4)
        XCTAssertEqual(d.gain.last!.g, 0.15, accuracy: 1e-4)
    }

    func testLanes() {
        let xs = [(0.0, 2.0), (1.0, 3.0), (2.0, 4.0), (3.5, 5.0)]
        let l = StudioPreview.lanes(xs, start: { $0.0 }, end: { $0.1 })
        XCTAssertEqual(l.count, 2)
        XCTAssertEqual(l[0].map(\.0), [0, 2])
        XCTAssertEqual(l[1].map(\.0), [1, 3.5])
    }

    func testScale() {
        let r = StudioScale.range(duration: 600, width: 392)
        XCTAssertEqual(r.lowerBound, 0.6, accuracy: 1e-9)
        XCTAssertEqual(r.upperBound, 120)
        XCTAssertEqual(StudioScale(pps: 500).clamped(duration: 600, width: 392).pps, 120)
        XCTAssertEqual(StudioScale(pps: 40).step, 2)
        XCTAssertEqual(StudioScale(pps: 40).ticks(from: 3, to: 9), [2, 4, 6, 8])
        XCTAssertEqual(StudioScale(pps: 120).label(1.5), "0:01.5")
        XCTAssertEqual(StudioScale(pps: 10).label(90), "1:30")
    }

    // MARK: requests and the demo

    func testBodiesAreFlat() throws {
        let ref = StudioRef(projectId: "p", videoId: "v")
        let b = StudioBody(ref: ref, x: StudioSaveBody(model: StudioModel(), base: "abc", label: "Split v1"))
        let o = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(b)) as? [String: Any])
        XCTAssertEqual(o["projectId"] as? String, "p")
        XCTAssertEqual(o["videoId"] as? String, "v")
        XCTAssertEqual(o["base"] as? String, "abc")
        XCTAssertEqual(o["label"] as? String, "Split v1")
        XCTAssertNotNil(o["model"] as? [String: Any])
        let clear = StudioBody(ref: ref, x: StudioSelectBody(selection: nil))
        let c = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(clear)) as? [String: Any])
        XCTAssertTrue(c["selection"] is NSNull, "null clears the selection")
    }

    func testRepliesDecode() throws {
        let undo = #"{"title":"T","readonly":false,"model":{"video":[]},"duration":3,"voice":[],"shots":[],"photos":[],"version":"x","undone":"Split v1"}"#
        let r = try JSONDecoder().decode(StudioUndoReply.self, from: Data(undo.utf8))
        XCTAssertEqual(r.label, "Split v1")
        let same = try JSONDecoder().decode(StudioPoll.self, from: Data(#"{"unchanged":true,"version":"x:1"}"#.utf8))
        XCTAssertTrue(same.unchanged)
        XCTAssertNil(same.view)
        // the bridge's version of a sound view isn't what saves go over: its base is
        var v = r.view
        XCTAssertEqual(v.timelineVersion, "x")
        v.base = "raw"
        v.version = "raw:1234abcd"
        XCTAssertEqual(v.timelineVersion, "raw")
        let edit = StudioEditView(title: "T", readonly: false, model: StudioModel(), duration: 3, voice: [], shots: [],
                                  photos: [], version: "new")
        let merged = v.merged(edit)
        XCTAssertEqual(merged.timelineVersion, "new", "an edit view's version is the timeline's")
    }

    func testDemoFixture() throws {
        let v: StudioEditView = try XCTUnwrap(Demo.load("edit", in: "fixtures/studio"))
        XCTAssertEqual(v.title, "The Keeper of Gull Point")
        XCTAssertEqual(v.model.video.count, 11)
        XCTAssertEqual(v.chapters?.map(\.title), ["Cold open", "The keeper's log", "The storm of 1887"])
        XCTAssertEqual(v.voice.count, 9)
        for c in v.model.video {
            if let src = StudioEdit.source(c, v.shotsById).src {
                let m = try XCTUnwrap(v.media?[src], "media for \(src)")
                XCTAssertNotNil(Demo.file((m.url as NSString).lastPathComponent,
                                          in: "fixtures/studio/" + (m.url as NSString).deletingLastPathComponent))
            }
        }
        for l in v.voice { XCTAssertNotNil(v.media?[l.file ?? ""], "voice \(l.id)") }
        for c in v.model.music + v.model.sfx { XCTAssertNotNil(v.media?[c.file ?? ""], "sound \(c.id)") }
        let found: StudioSearchReply = try XCTUnwrap(Demo.load("sounds", in: "fixtures/studio"))
        XCTAssertFalse(found.results.isEmpty)
    }

    @MainActor
    func testDemoStoreEditsAndUndoes() async throws {
        let s = StudioEditStore(ref: StudioRef(projectId: "demo", videoId: "demo"), pairing: nil, demo: true)
        await s.load()
        XCTAssertFalse(s.readonly)
        XCTAssertFalse(s.canUndo)
        let before = s.model
        let at = s.model.video[5].start + 1
        XCTAssertTrue(s.change("Split v6 at 0:30.0") { StudioEdit.split(&$0, "v6", at: at) != nil })
        XCTAssertEqual(s.model.video.count, 12)
        XCTAssertEqual(s.undoLabel, "Split v6 at 0:30.0")
        var mix = s.mix
        mix.music.gain = 0.2
        s.setMix(mix, label: "Music volume")
        XCTAssertEqual(s.mix.music.gain, 0.2)
        await s.undo()
        XCTAssertEqual(s.mix.music.gain, 0.126)
        XCTAssertEqual(s.toast?.text, "Undid: Music volume")
        await s.undo()
        XCTAssertEqual(s.model, before)
        XCTAssertFalse(s.canUndo)
        XCTAssertTrue(s.canRedo)
        await s.redo()
        XCTAssertEqual(s.model.video.count, 12)
        // the sound search and adding a found sound
        await s.search("rain")
        XCTAssertEqual(s.found?.results.first?.title, "Rain on a window")
        XCTAssertEqual(s.fileOf(s.found!.results[0]), "sound/library/rain.m4a", "in the library already")
        let id = await s.add(s.found!.results[1], track: .sfx, at: 10)
        XCTAssertNotNil(id)
        XCTAssertEqual(s.selected, id)
        XCTAssertNotNil(s.url(s.media(s.model.sfx.first { $0.id == id }?.file)?.url))
        await s.priceGeneration(kind: "sfx", prompt: "gulls", seconds: 4)
        XCTAssertEqual(s.estimate?.reply.estimate, 80)
        await s.confirmGeneration()
        XCTAssertNil(s.estimate)
        XCTAssertEqual(s.view?.jobs?.last?.status, "running")
    }

    /// the first change's toast offers Undo (it used to ask before the change was in the history)
    @MainActor
    func testFirstChangeToastOffersUndo() async throws {
        let s = StudioEditStore(ref: StudioRef(projectId: "demo", videoId: "demo"), pairing: nil, demo: true)
        await s.load()
        let at = s.model.video[5].start + 1
        XCTAssertTrue(s.change("Split v6", toast: true) { StudioEdit.split(&$0, "v6", at: at) != nil })
        XCTAssertEqual(s.toast?.text, "Split v6")
        XCTAssertEqual(s.toast?.undo, true)
    }

    /// the demo's video chat (28) decodes, and the store's chat is that one
    @MainActor
    func testStudioDemoChat() async throws {
        let c: ChatFixture = try XCTUnwrap(Demo.load("studio-demo-chat", in: "fixtures/chats"))
        XCTAssertEqual(c.header.title, "The Keeper of Gull Point")
        XCTAssertEqual(c.turns.turns.count, 1)
        let s = StudioEditStore(ref: StudioRef(projectId: "studio-test", videoId: "keeper"), pairing: nil, demo: true)
        await s.load()
        let id = await s.chatId()
        XCTAssertEqual(id, "studio-demo-chat")
    }
}
