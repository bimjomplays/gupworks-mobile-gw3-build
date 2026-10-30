import Foundation

// What the phone's player plays for a timeline: the pictures on screen at a time (with Ken Burns, crossfades and
// dips, the desktop EditComp's), and every sound placed with its volume over time (the PC mixdown's sum:
// clip gain × track gain, fades, the music ducked under the narrator's words; gw3_studio_sound.mix_plan). The
// iPhone builds an AVComposition from it (StudioEditPlayer.swift); this part is plain logic, tested on Linux.

enum StudioPreview {
    // MARK: pictures

    enum Source: Equatable {
        case video(String)          // a file, played from `time`
        case image(String)
        case card                   // the shot's placeholder card (no picture yet, or not loaded yet)
    }

    /// One picture on screen, bottom to top: `scale` and `tx` (a share of the width) are its Ken Burns move.
    struct Layer: Equatable {
        var clip: String
        var source: Source
        var opacity: Double
        var scale = 1.0
        var tx = 0.0
        var time = 0.0              // seconds into a video file
    }

    /// Ken Burns at progress p (0-1) with zoom z: (scale, x shift as a share of the width).
    static func kenburns(_ kind: String?, zoom: Double?, p: Double) -> (scale: Double, tx: Double) {
        let z = zoom ?? 1.15, p = min(1, max(0, p))
        switch kind {
        case "in": return (1 + (z - 1) * p, 0)
        case "out": return (z - (z - 1) * p, 0)
        case "left": return (z, z * (4 - 8 * p) * (z - 1) / 0.12 / 100)
        case "right": return (z, z * (-4 + 8 * p) * (z - 1) / 0.12 / 100)
        default: return (1, 0)
        }
    }

    /// How long clip i stays on screen after its end: under the next one's crossfade.
    static func hold(_ v: [StudioClip], _ i: Int) -> Double {
        guard i + 1 < v.count else { return 0 }
        let n = v[i + 1]
        return n.transition == "crossfade" && abs(n.start - v[i].end) < 0.05 ? (n.fade ?? 0.5) : 0
    }

    /// The pictures at time t. `ready` says which files are loaded (others show their card).
    static func layers(at t: Double, _ m: StudioModel, shots: [String: StudioShot], ready: (String) -> Bool) -> [Layer] {
        let v = m.video
        var out: [Layer] = []
        for (i, c) in v.enumerated() {
            guard t >= c.start - 1e-9, t < c.end + hold(v, i) else { continue }
            var opacity = 1.0
            if c.transition == "crossfade" {
                opacity = min(1, max(0, (t - c.start) / max(0.001, c.fade ?? 0.5)))
            } else if c.transition == "dip" {
                opacity = min(1, max(0, (t - c.start) / max(0.001, (c.fade ?? 0.5) / 2)))
            }
            if i + 1 < v.count, v[i + 1].transition == "dip", abs(v[i + 1].start - c.end) < 0.05 {
                let half = max(0.001, (v[i + 1].fade ?? 0.5) / 2)
                opacity = min(opacity, max(0, min(1, (c.end - t) / half)))
            }
            let (src, _) = StudioEdit.source(c, shots)
            var l = Layer(clip: c.id, source: .card, opacity: opacity)
            if let src, ready(src), StudioEdit.isImage(src) {
                l.source = .image(src)
                (l.scale, l.tx) = kenburns(c.kenburns, zoom: c.kbZoom, p: (t - c.start) / max(0.001, c.dur))
            } else if let src, ready(src), StudioEdit.isVideo(src) {
                l.source = .video(src)
                l.time = t - c.start + (c.trim ?? 0)
            }
            out.append(l)
        }
        return out
    }

    /// A video file's part on the timeline, for the composition's video tracks.
    struct Placement: Equatable {
        var clip: String
        var file: String
        var start: Double           // on the timeline
        var from: Double            // into the file
        var dur: Double
    }

    /// The video files the pictures play, with each crossfade's extra hold.
    static func videoPlacements(_ m: StudioModel, shots: [String: StudioShot], ready: (String) -> Bool) -> [Placement] {
        m.video.enumerated().compactMap { i, c in
            guard let src = StudioEdit.source(c, shots).src, StudioEdit.isVideo(src), ready(src) else { return nil }
            return Placement(clip: c.id, file: src, start: c.start, from: c.trim ?? 0, dur: c.dur + hold(m.video, i))
        }
    }

    /// Times where what's on screen can change, for the composition's instructions.
    static func cuts(_ m: StudioModel, duration: Double) -> [Double] {
        var ts: Set<Double> = [0, max(duration, 0.1)]
        for (i, c) in m.video.enumerated() {
            ts.insert(c.start)
            ts.insert(c.end)
            ts.insert(c.end + hold(m.video, i))
        }
        return ts.filter { $0 >= 0 && $0 <= max(duration, 0.1) }.sorted()
    }

    /// The text on screen at t and how far it has faded in (6 frames in and out).
    static func overlays(at t: Double, _ m: StudioModel) -> [(clip: StudioClip, opacity: Double)] {
        m.overlay.compactMap { c in
            guard t >= c.start, t < c.end else { return nil }
            let f = 6.0 / 30, a = (t - c.start) / f, b = (c.end - t) / f
            return (c, min(1, max(0, min(a, b))))
        }
    }

    // MARK: sound

    /// One sound file's part on the timeline with its volume: `gain` points (timeline time, linear gain) between
    /// which the volume ramps straight.
    struct Sound: Equatable {
        var id: String              // the clip, or "voice:<line>"
        var file: String
        var bus: String             // voice | music | sfx
        var start: Double
        var from: Double
        var dur: Double
        var gain: [Point]
    }

    struct Point: Equatable {
        var t: Double
        var g: Double
    }

    /// When the narrator speaks: each word's span (each line's without word times), gaps under `hold` filled.
    static func duckRanges(_ voice: [StudioVoiceLine], hold: Double) -> [(Double, Double)] {
        var spans: [(Double, Double)] = []
        for l in voice {
            let words = l.words.filter { $0.end > $0.t }
            if !words.isEmpty {
                spans += words.map { (l.start + $0.t, l.start + $0.end) }
            } else if l.end > l.start {
                spans.append((l.start, l.end))
            }
        }
        spans.sort { $0.0 != $1.0 ? $0.0 < $1.0 : $0.1 < $1.1 }
        var out: [(Double, Double)] = []
        for (a, b) in spans {
            if let last = out.last, a - last.1 <= hold {
                out[out.count - 1].1 = max(last.1, b)
            } else {
                out.append((a, b))
            }
        }
        return out.map { (StudioEdit.r3($0.0), StudioEdit.r3($0.1)) }
    }

    /// 0-1: how far the music is down at t (gw3_studio_sound.duck_amount).
    static func duckAmount(_ t: Double, _ ranges: [(Double, Double)], attack: Double, release: Double) -> Double {
        var a = 0.0
        for (s, e) in ranges {
            if s - attack > t { break }
            if t <= e {
                a = max(a, t >= s ? 1 : (t - (s - attack)) / max(attack, 1e-6))
            } else if t < e + release {
                a = max(a, 1 - (t - e) / max(release, 1e-6))
            }
            if a >= 1 { return 1 }
        }
        return a
    }

    static func duckGain(_ t: Double, _ ranges: [(Double, Double)], _ d: StudioDuck) -> Double {
        d.on ? pow(10, -d.depth * duckAmount(t, ranges, attack: d.attack, release: d.release) / 20) : 1
    }

    /// whether a clip goes under the voice: music unless told not to, effects only when told to
    static func ducks(_ t: StudioTrack, _ c: StudioClip) -> Bool {
        c.duck != false && (t == .music || c.duck == true)
    }

    /// Every sound with its volume over time. `ready` says which files are loaded.
    static func sounds(_ m: StudioModel, voice: [StudioVoiceLine], mix: StudioMix, lengths: [String: Double] = [:],
                       ready: (String) -> Bool) -> [Sound] {
        var out: [Sound] = []
        let ranges = duckRanges(voice, hold: mix.duck.hold)
        for l in voice {
            guard let f = l.file, ready(f) else { continue }
            let own = mix.lines?[l.id]
            let dur = max(0, l.end - l.start)
            let g = (own?.gain ?? 1) * mix.voice.gain
            let play = max(dur, lengths[f] ?? dur)  // the mixdown plays the whole file from the line's start
            out.append(Sound(id: "voice:\(l.id)", file: f, bus: "voice", start: l.start, from: 0, dur: play,
                             gain: envelope(start: l.start, dur: dur, play: play, gain: g, fadeIn: own?.fadeIn ?? 0,
                                            fadeOut: own?.fadeOut ?? 0, duck: nil)))
        }
        for t in [StudioTrack.music, .sfx] {
            for c in m[t] {
                guard let f = c.file, ready(f) else { continue }
                let g = (c.gain ?? (t == .music ? 0.3 : 1)) * mix.gain(t)
                let under = ducks(t, c) && mix.duck.on && mix.duck.depth > 0 ? (ranges, mix.duck) : nil
                out.append(Sound(id: c.id, file: f, bus: t.rawValue, start: c.start, from: c.trim ?? 0, dur: c.dur,
                                 gain: envelope(start: c.start, dur: c.dur, play: c.dur, gain: g, fadeIn: c.fadeIn ?? 0,
                                                fadeOut: c.fadeOut ?? 0, duck: under)))
            }
        }
        return out
    }

    /// The volume points of one sound: its gain, its fades (ffmpeg's straight afade), the duck sampled every 50 ms
    /// where it ramps.
    static func envelope(start: Double, dur: Double, play: Double, gain: Double, fadeIn: Double, fadeOut: Double,
                         duck: ([(Double, Double)], StudioDuck)?) -> [Point] {
        let fi = min(max(0, fadeIn), dur), fo = min(max(0, fadeOut), dur)
        let end = start + play
        var ts: Set<Double> = [start, end, start + fi, start + dur - fo, start + dur]
        if let (ranges, d) = duck {
            for (s, e) in ranges where e + d.release > start && s - d.attack < end {
                for (a, b) in [(s - d.attack, s), (e, e + d.release)] {
                    var x = a
                    while x < b { ts.insert(x); x += 0.05 }
                    ts.insert(b)
                }
            }
        }
        let times = ts.filter { $0 >= start - 1e-9 && $0 <= end + 1e-9 }.sorted()
        func at(_ t: Double) -> Double {
            let rel = t - start
            var f = 1.0
            if fi > 0, rel < fi { f = min(f, max(0, rel / fi)) }
            if fo > 0, rel > dur - fo { f = min(f, max(0, (dur - rel) / fo)) }
            if rel > dur + 1e-9 { f = play > dur ? f : 0 }
            var g = gain * f
            if let (ranges, d) = duck { g *= duckGain(t, ranges, d) }
            return g
        }
        var pts: [Point] = []
        for t in times {
            let p = Point(t: StudioEdit.r3(t), g: (at(t) * 10000).rounded() / 10000)
            if let last = pts.last, abs(last.t - p.t) < 1e-6 { continue }
            pts.append(p)
        }
        // drop points in the middle of a straight run
        var lean: [Point] = []
        for (i, p) in pts.enumerated() {
            if i > 0, i + 1 < pts.count {
                let a = lean.last!, b = pts[i + 1]
                let mid = a.g + (b.g - a.g) * (p.t - a.t) / max(1e-9, b.t - a.t)
                if abs(mid - p.g) < 1e-4 { continue }
            }
            lean.append(p)
        }
        return lean
    }

    /// Lanes where no two parts overlap: one composition track each.
    static func lanes<T>(_ items: [T], start: (T) -> Double, end: (T) -> Double) -> [[T]] {
        var lanes: [[T]] = []
        var ends: [Double] = []
        for x in items.sorted(by: { start($0) < start($1) }) {
            if let i = ends.firstIndex(where: { $0 <= start(x) + 1e-6 }) {
                lanes[i].append(x)
                ends[i] = end(x)
            } else {
                lanes.append([x])
                ends.append(end(x))
            }
        }
        return lanes
    }
}

/// The timeline's scale: points a second, the ruler's ticks and how far a pinch can go.
struct StudioScale: Equatable {
    var pps: Double

    static let steps: [Double] = [0.5, 1, 2, 5, 10, 15, 30, 60, 120, 300, 600]

    /// the closest a pinch zooms in, and the farthest out (the whole video across `width`)
    static func range(duration: Double, width: Double) -> ClosedRange<Double> {
        let lo = max(0.2, (width - 32) / max(duration, 1))
        return min(lo, 120)...max(lo, 120)
    }

    func clamped(duration: Double, width: Double) -> StudioScale {
        let r = Self.range(duration: duration, width: width)
        return StudioScale(pps: min(r.upperBound, max(r.lowerBound, pps)))
    }

    /// a tick every this many seconds: the first step at least 56 points apart
    var step: Double { Self.steps.first { $0 * pps >= 56 } ?? 600 }

    func ticks(from a: Double, to b: Double) -> [Double] {
        let s = step
        var t = (max(0, a) / s).rounded(.down) * s
        var out: [Double] = []
        while t <= b + 1e-9 {
            out.append(StudioEdit.r3(t))
            t += s
        }
        return out
    }

    /// "0:52", or "0:52.5" for ticks under a second apart
    func label(_ t: Double) -> String {
        if step < 1 { return StudioEdit.clock(t) }
        return StudioEdit.clock(t, tenths: false)
    }
}
