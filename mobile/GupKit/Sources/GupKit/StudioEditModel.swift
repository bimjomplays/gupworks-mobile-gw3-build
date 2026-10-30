import Foundation

// The Edit stage's changes to the timeline model, as the desktop's editModel.ts and Timeline.tsx make them, so a
// change on the phone and on the PC is the same change. Each returns what the undo history calls it, or nil when
// nothing changed; the store then saves the whole model over the version it had (studio/edit/save).

enum StudioEdit {
    static let frame = 1.0 / 30

    static func r3(_ x: Double) -> Double { (x * 1000).rounded() / 1000 }

    static func isImage(_ f: String?) -> Bool { ext(f).map { ["png", "jpg", "jpeg", "webp", "gif"].contains($0) } ?? false }
    static func isVideo(_ f: String?) -> Bool { ext(f).map { ["mp4", "webm", "mov", "mkv"].contains($0) } ?? false }
    private static func ext(_ f: String?) -> String? {
        guard let f, let dot = f.lastIndex(of: ".") else { return nil }
        return f[f.index(after: dot)...].lowercased()
    }

    /// What a video clip shows: its own media, else its shot's render or draft; nil is a placeholder card.
    static func source(_ c: StudioClip, _ shots: [String: StudioShot]) -> (src: String?, how: String) {
        if let m = c.media, !m.isEmpty { return (m, m.hasPrefix("research/") ? "photo" : "file") }
        if let s = c.shot.flatMap({ shots[$0] }), let src = s.src { return (src, s.from ?? "shot") }
        return (nil, "placeholder")
    }

    static func track(of id: String, in m: StudioModel) -> StudioTrack? {
        StudioTrack.allCases.first { t in m[t].contains { $0.id == id } }
    }

    static func clip(_ id: String, in m: StudioModel) -> StudioClip? {
        for t in StudioTrack.allCases { if let c = m[t].first(where: { $0.id == id }) { return c } }
        return nil
    }

    static func newId(_ m: StudioModel, _ t: StudioTrack, base: String? = nil) -> String {
        let used = Set(StudioTrack.allCases.flatMap { m[$0].map(\.id) })
        if let base {
            var n = 2
            while used.contains("\(base)-\(n)") { n += 1 }
            return "\(base)-\(n)"
        }
        let p = ["video": "v", "overlay": "t", "music": "mu", "sfx": "fx"][t.rawValue]!
        var n = 1
        while used.contains("\(p)\(n)") { n += 1 }
        return "\(p)\(n)"
    }

    /// The video track as the service keeps it: in time order, a later shot cutting an earlier one short.
    static func tidy(_ m: inout StudioModel) {
        for t in StudioTrack.allCases {
            m[t].sort { $0.start != $1.start ? $0.start < $1.start : $0.id < $1.id }
        }
        var keep: [StudioClip] = []
        for c in m.video {
            if var last = keep.last, last.end > c.start + 1e-6 {
                last.dur = r3(c.start - last.start)
                keep.removeLast()
                if last.dur >= frame / 2 { keep.append(last) }
            }
            keep.append(c)
        }
        m.video = keep
    }

    /// a time on the frame grid
    static func onFrame(_ t: Double) -> Double { r3((t * 30).rounded() / 30) }

    // MARK: split, delete

    /// Splits a clip at `at` seconds; the second part gets a new id (returned), nil when `at` isn't inside it.
    static func split(_ m: inout StudioModel, _ id: String, at: Double) -> String? {
        guard let t = track(of: id, in: m), let i = m[t].firstIndex(where: { $0.id == id }) else { return nil }
        var c = m[t][i]
        guard at >= c.start + frame, at <= c.end - frame else { return nil }
        var b = c
        b.id = newId(m, t, base: c.id)
        b.start = r3(at)
        b.dur = r3(c.end - at)
        b.anchor = nil
        if c.trim != nil || isVideo(c.media) || t == .music || t == .sfx { b.trim = r3((c.trim ?? 0) + at - c.start) }
        if b.transition != nil { b.transition = nil; b.fade = nil }
        c.dur = r3(at - c.start)
        m[t][i] = c
        m[t].insert(b, at: i + 1)
        return b.id
    }

    static func delete(_ m: inout StudioModel, _ id: String) -> Bool {
        guard let t = track(of: id, in: m) else { return false }
        m[t].removeAll { $0.id == id }
        return true
    }

    // MARK: trim and move (Timeline.tsx's drag)

    /// a time a dragged edge sticks to, and what it is ("the end of c3")
    struct SnapPoint: Equatable {
        var t: Double
        var what: String
    }

    /// Where edges snap: the start, the playhead, other clips' edges, voice lines and their words.
    static func snapPoints(_ m: StudioModel, voice: [StudioVoiceLine], playhead: Double, skip: String?,
                           names: [String: String] = [:]) -> [SnapPoint] {
        var out = [SnapPoint(t: 0, what: "the start"), SnapPoint(t: playhead, what: "the playhead")]
        for t in StudioTrack.allCases {
            for c in m[t] where c.id != skip {
                let n = names[c.id] ?? c.id
                out.append(SnapPoint(t: c.start, what: "the start of \(n)"))
                out.append(SnapPoint(t: c.end, what: "the end of \(n)"))
            }
        }
        for l in voice {
            out.append(SnapPoint(t: l.start, what: "the start of \(l.id)"))
            out.append(SnapPoint(t: l.end, what: "the end of \(l.id)"))
            for w in l.words {
                let word = w.w.trimmingCharacters(in: .punctuationCharacters.union(.whitespaces))
                out.append(SnapPoint(t: l.start + w.end, what: "“\(word)”"))
            }
        }
        return out
    }

    /// `t` moved to the nearest snap point within `within` seconds (the clip edges first on a tie)
    static func snap(_ t: Double, _ pts: [SnapPoint], within: Double) -> (t: Double, to: SnapPoint?) {
        var best: SnapPoint?
        var d = within
        for p in pts where abs(p.t - t) < d {
            d = abs(p.t - t)
            best = p
        }
        return (best?.t ?? t, best)
    }

    enum Edge { case left, right }

    /// A clip's edge dragged by `dt` seconds from the clip `o` as it was, as Timeline.tsx does: a shot can't pass its
    /// neighbours, a file's clip can't start before its file does. Returns the snap point it stuck to.
    @discardableResult
    static func trim(_ m: inout StudioModel, original o: StudioClip, edge: Edge, by dt: Double, shots: [String: StudioShot],
                     snaps: [SnapPoint], within: Double) -> SnapPoint? {
        guard let t = track(of: o.id, in: m), let i = m[t].firstIndex(where: { $0.id == o.id }) else { return nil }
        var c = m[t][i]
        let others = t == .video ? m[t].filter { $0.id != o.id } : []
        let stills = c.media == nil || isImage(c.media) ? !(t == .video && isVideo(source(c, shots).src)) : false
        var hit: SnapPoint?
        switch edge {
        case .left:
            let prevEnd = others.filter { $0.start < o.start }.map(\.end).max() ?? 0
            let (sn, p) = snap(o.start + dt, snaps, within: within)
            hit = p
            var s = min(o.end - frame, max(t == .video ? max(0, prevEnd) : 0, sn))
            if !stills || t != .video { s = max(s, o.start - (o.trim ?? 0)) }
            c.start = r3(s)
            c.dur = r3(o.end - s)
            if o.trim != nil || !stills || t != .video { c.trim = r3(max(0, (o.trim ?? 0) + s - o.start)) }
            c.anchor = nil
        case .right:
            let nextStart = others.filter { $0.start > o.start }.map(\.start).min() ?? .infinity
            let (sn, p) = snap(o.end + dt, snaps, within: within)
            hit = p
            let e = max(o.start + frame, min(t == .video ? nextStart : .infinity, sn))
            c.dur = r3(e - o.start)
        }
        if let h = hit, abs((edge == .left ? c.start : c.end) - h.t) > 0.002 { hit = nil }  // held back by a neighbour
        m[t][i] = c
        tidy(&m)
        return hit
    }

    /// A text, music or effects clip moved by `dt` (its start or end snapping), as the desktop's drag does.
    @discardableResult
    static func move(_ m: inout StudioModel, original o: StudioClip, by dt: Double, snaps: [SnapPoint],
                     within: Double) -> SnapPoint? {
        guard let t = track(of: o.id, in: m), let i = m[t].firstIndex(where: { $0.id == o.id }) else { return nil }
        var s = max(0, o.start + dt)
        let a = snap(s, snaps, within: within), b = snap(s + o.dur, snaps, within: within)
        let useA = abs(a.t - s) <= abs(b.t - o.dur - s)
        s = useA ? a.t : b.t - o.dur
        m[t][i].start = r3(max(0, s))
        m[t][i].anchor = nil
        tidy(&m)
        return useA ? a.to : b.to
    }

    // MARK: reorder (long press on a shot)

    /// The shots in a new order, laid end to end from where the first one started; text and effects inside a moved
    /// shot move with it. Returns the ids of the clips that moved along.
    @discardableResult
    static func reorder(_ m: inout StudioModel, order: [String]) -> [String] {
        let old = m.video
        guard Set(order) == Set(old.map(\.id)), order.count == old.count, order != old.map(\.id),
              let t0 = old.map(\.start).min() else { return [] }
        var t = t0
        var shift: [(from: Double, to: Double, by: Double)] = []
        var video: [StudioClip] = []
        for id in order {
            var c = old.first { $0.id == id }!
            let by = r3(t - c.start)
            if abs(by) > 1e-6 {
                shift.append((c.start, c.end, by))
                c.start = r3(t)
                c.anchor = nil
                if c.transition != nil, video.isEmpty { c.transition = nil; c.fade = nil }
            }
            video.append(c)
            t += c.dur
        }
        m.video = video
        var along: [String] = []
        for tr in [StudioTrack.overlay, .sfx] {
            m[tr] = m[tr].map { c in
                guard let s = shift.first(where: { c.start >= $0.from - 1e-6 && c.start < $0.to - 1e-6 }) else { return c }
                var c = c
                c.start = r3(max(0, c.start + s.by))
                c.anchor = nil
                along.append(c.id)
                return c
            }
        }
        tidy(&m)
        return along
    }

    // MARK: setting a clip

    /// Sets clip fields; returns false when the clip isn't there.
    static func set(_ m: inout StudioModel, _ id: String, _ f: (inout StudioClip) -> Void) -> Bool {
        guard let t = track(of: id, in: m), let i = m[t].firstIndex(where: { $0.id == id }) else { return false }
        let before = m[t][i]
        f(&m[t][i])
        if m[t][i].start != before.start { m[t][i].anchor = nil }
        if m[t][i] == before { return false }
        tidy(&m)
        return true
    }

    /// The transition into `ids`' shots; with `sound`, sound clips that end or start at those cuts fade over it.
    static func setTransition(_ m: inout StudioModel, _ ids: [String], kind: String, fade: Double, sound: Bool) {
        let f = r3(min(5, max(0.05, fade)))
        var cuts: [Double] = []
        for id in ids {
            guard let i = m.video.firstIndex(where: { $0.id == id }) else { continue }
            if kind == "cut" {
                m.video[i].transition = nil
                m.video[i].fade = nil
            } else {
                m.video[i].transition = kind
                m.video[i].fade = f
                cuts.append(m.video[i].start)
            }
        }
        guard sound, !cuts.isEmpty else { return }
        for t in [StudioTrack.sfx, .music] {
            for j in m[t].indices {
                let c = m[t][j]
                if cuts.contains(where: { abs(c.end - $0) < 0.1 }) { m[t][j].fadeOut = r3(min(c.dur, max(c.fadeOut ?? 0, f))) }
                if cuts.contains(where: { abs(c.start - $0) < 0.1 }) { m[t][j].fadeIn = r3(min(c.dur, max(c.fadeIn ?? 0, f))) }
            }
        }
    }

    /// The shots that start inside a chapter (each but the timeline's first has a cut before it).
    static func shots(in ch: StudioChapter, _ m: StudioModel) -> [String] {
        let first = m.video.first?.id
        return m.video.filter { $0.start >= ch.start - 0.05 && $0.start < ch.end - 0.05 && $0.id != first }.map(\.id)
    }

    /// The chapter a time is in (the last that started by then).
    static func chapter(at t: Double, _ chapters: [StudioChapter]) -> StudioChapter? {
        chapters.last { $0.start <= t + 1e-6 } ?? chapters.first
    }

    /// Chapters from the voice lines, when the PC sent none.
    static func chapters(_ voice: [StudioVoiceLine]) -> [StudioChapter] {
        var out: [StudioChapter] = []
        for l in voice {
            if var last = out.last, last.chapter == l.chapter {
                last.end = l.end
                out[out.count - 1] = last
            } else {
                out.append(StudioChapter(chapter: l.chapter, title: "Chapter \(l.chapter + 1)", start: l.start, end: l.end))
            }
        }
        return out
    }

    // MARK: adding

    static func addPhoto(_ m: inout StudioModel, _ p: StudioPhoto, at: Double, dur: Double = 4,
                         kenburns: String? = "in") -> String {
        let id = newId(m, .video)
        m.video.append(StudioClip(id: id, start: onFrame(at), dur: dur, label: p.title, media: p.file, kenburns: kenburns))
        tidy(&m)
        return id
    }

    static func addText(_ m: inout StudioModel, at: Double, text: String = "New text", style: String = "lower") -> String {
        let id = newId(m, .overlay)
        m.overlay.append(StudioClip(id: id, start: onFrame(at), dur: 3, text: text, style: style))
        tidy(&m)
        return id
    }

    /// A sound in at `at`: music runs on (to the end, 30 s at most unless its file is longer) with fades, effects
    /// play their length.
    static func addSound(_ m: inout StudioModel, _ t: StudioTrack, file: String, seconds: Double?, at: Double,
                         duration: Double) -> String {
        let id = newId(m, t)
        let t0 = onFrame(at)
        let len = seconds ?? (t == .music ? 30 : 2)
        let dur = r3(max(frame, t == .music ? min(len, max(2, duration - t0)) : len))
        var c = StudioClip(id: id, start: t0, dur: dur, file: file, gain: t == .music ? 0.3 : 1)
        if t == .music { c.fadeIn = 0.5; c.fadeOut = r3(min(2, dur / 3)) }
        m[t].append(c)
        tidy(&m)
        return id
    }

    // MARK: words for the history and the chat

    /// "0:52.4"
    static func clock(_ t: Double, tenths: Bool = true) -> String {
        let t = max(0, t)
        if !tenths {
            let s = Int(t.rounded(.down))
            return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60)
                : String(format: "%d:%02d", s / 60, s % 60)
        }
        let d = Int((t * 10).rounded())
        return String(format: "%d:%02d.%d", d / 600, d / 10 % 60, d % 10)
    }

    /// What the video chat is told is selected (the desktop Edit.tsx's words).
    static func selectionLabel(_ id: String, _ m: StudioModel, voice: [StudioVoiceLine],
                               shots: [String: StudioShot]) -> String? {
        if id.hasPrefix("voice:") {
            guard let l = voice.first(where: { "voice:\($0.id)" == id }) else { return nil }
            return String(format: "voice line %@ (%.2f–%.2f s): \"%@\"", l.id, l.start, l.end, cut(l.text, 200))
        }
        guard let t = track(of: id, in: m), let c = clip(id, in: m) else { return nil }
        let what: String
        switch t {
        case .video:
            if let me = c.media { what = me } else if let s = c.shot {
                what = "shot \(s)" + (shots[s].map { ": " + cut($0.description, 120) } ?? "")
            } else { what = "" }
        case .overlay: what = "\"\(cut(c.text ?? "", 120))\""
        default: what = c.file ?? ""
        }
        return "timeline clip \(c.id) on \(t.rawValue): \(what)"
    }

    static func cut(_ s: String, _ n: Int) -> String {
        s.count <= n ? s : String(s.prefix(n - 1)) + "…"
    }
}
