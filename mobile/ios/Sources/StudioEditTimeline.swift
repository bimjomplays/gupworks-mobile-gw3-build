import SwiftUI
import UIKit

// The Edit stage's timeline (mockups 15-18, 26, 27): every track on its own rows, scrolling under a fixed playhead in
// the middle. One Canvas draws what is in view; one drag decides what it is from where it starts (a handle of the
// selected clip trims it, a selected text or sound moves, anything else scrolls), a still touch is a tap (the ruler
// jumps, a clip selects, the square between two shots opens its transition), a hold lifts the shots into tiles to
// reorder, and a pinch zooms.

/// thumbnails: shot stills, video strips cut into their frames, photos; loaded once each
@Observable
@MainActor
final class StudioThumbs {
    private(set) var images: [String: UIImage] = [:]
    @ObservationIgnored private var running: Set<String> = []
    @ObservationIgnored private var frames: [String: [UIImage]] = [:]

    func image(_ link: String?, _ store: StudioEditStore) -> UIImage? {
        guard let link else { return nil }
        if let i = images[link] { return i }
        load(link, store)
        return nil
    }

    /// picture `i` of a strip of `n` side by side
    func frame(_ link: String?, _ n: Int, _ i: Int, _ store: StudioEditStore) -> UIImage? {
        guard let link, let img = image(link, store), n > 1, let cg = img.cgImage else { return image(link, store) }
        if frames[link] == nil {
            let w = cg.width / n
            frames[link] = (0..<n).compactMap { k in
                cg.cropping(to: CGRect(x: k * w, y: 0, width: w, height: cg.height)).map { UIImage(cgImage: $0) }
            }
        }
        let f = frames[link] ?? []
        return f.isEmpty ? img : f[max(0, min(f.count - 1, i))]
    }

    private func load(_ link: String, _ store: StudioEditStore) {
        guard !running.contains(link), let u = store.url(link) else { return }
        running.insert(link)
        Task {
            let data: Data?
            if u.isFileURL { data = try? Data(contentsOf: u) } else { data = try? await URLSession.shared.data(from: u).0 }
            if let data, let img = UIImage(data: data) { images[link] = img }
        }
    }
}

/// where everything sits on the timeline
struct StudioTimelineLayout {
    enum Kind: Equatable { case video, text, voice, music, sfx }
    struct Row: Equatable {
        var kind: Kind
        var y: CGFloat
        var h: CGFloat
        var first: Bool         // the first row of its track (it gets the icon)
    }

    static let ruler: CGFloat = 26
    static let gap: CGFloat = 6
    static let heights: [Kind: CGFloat] = [.video: 56, .text: 30, .voice: 44, .music: 40, .sfx: 30]

    let time: Double
    let pps: Double
    let width: CGFloat
    private(set) var rows: [Row] = []
    private(set) var rowOf: [String: Int] = [:]
    private(set) var height: CGFloat = 0

    init(_ m: StudioModel, time: Double, pps: Double, width: CGFloat) {
        (self.time, self.pps, self.width) = (time, pps, width)
        var y = Self.ruler + 4
        func add(_ k: Kind, _ lanes: [[StudioClip]]) {
            for (i, lane) in (lanes.isEmpty ? [[]] : lanes).enumerated() {
                for c in lane { rowOf[c.id] = rows.count }
                let h = Self.heights[k] ?? 30
                rows.append(Row(kind: k, y: y, h: h, first: i == 0))
                y += h + Self.gap
            }
        }
        let lanes = { (cs: [StudioClip]) in StudioPreview.lanes(cs, start: { $0.start }, end: { $0.end }) }
        add(.video, [m.video])
        add(.text, lanes(m.overlay))
        add(.voice, [[]])
        add(.music, lanes(m.music))
        add(.sfx, lanes(m.sfx))
        height = y + 8
    }

    var centerX: CGFloat { width / 2 }
    func x(_ t: Double) -> CGFloat { centerX + CGFloat((t - time) * pps) }
    func t(_ x: CGFloat) -> Double { time + Double(x - centerX) / pps }
    func row(_ k: Kind) -> Row? { rows.first { $0.kind == k } }

    func rect(_ c: StudioClip) -> CGRect? {
        guard let r = rowOf[c.id].map({ rows[$0] }) else { return nil }
        let x0 = x(c.start), x1 = x(c.end)
        return CGRect(x: x0 + 1, y: r.y, width: max(2, x1 - x0 - 2), height: r.h)
    }

    func rect(_ l: StudioVoiceLine) -> CGRect? {
        guard let r = row(.voice) else { return nil }
        let x0 = x(l.start), x1 = x(l.end)
        return CGRect(x: x0 + 1, y: r.y, width: max(2, x1 - x0 - 2), height: r.h)
    }

    /// the cuts between shots that touch: (the shot after it, where)
    func cuts(_ m: StudioModel) -> [(id: String, x: CGFloat)] {
        zip(m.video, m.video.dropFirst()).compactMap { a, b in abs(a.end - b.start) < 0.05 ? (b.id, x(b.start)) : nil }
    }

    enum Hit: Equatable {
        case ruler(Double)
        case handle(String, left: Bool)
        case cut(String)
        case clip(String)
        case voice(String)
        case none
    }

    func hit(_ p: CGPoint, _ m: StudioModel, voice: [StudioVoiceLine], selected: String?) -> Hit {
        if p.y < Self.ruler + 2 { return .ruler(t(p.x)) }
        if let s = selected, let c = StudioEdit.clip(s, in: m), let r = rect(c), p.y >= r.minY - 6, p.y <= r.maxY + 6 {
            if abs(p.x - r.minX) < 18 { return .handle(s, left: true) }
            if abs(p.x - r.maxX) < 18 { return .handle(s, left: false) }
        }
        if let v = row(.video), p.y >= v.y, p.y <= v.y + v.h, pps >= 12 {
            if let c = cuts(m).first(where: { abs($0.x - p.x) < 13 && abs(p.y - (v.y + v.h / 2)) < 16 }) { return .cut(c.id) }
        }
        for t in StudioTrack.allCases {
            for c in m[t] { if let r = rect(c), r.insetBy(dx: -1, dy: -2).contains(p) { return .clip(c.id) } }
        }
        for l in voice { if let r = rect(l), r.contains(p) { return .voice("voice:\(l.id)") } }
        return .none
    }
}

/// a trim or move in progress
struct StudioDraft {
    var model: StudioModel
    var bubble: String
    var snapped: String?
    var label: String
}

struct StudioEditTimeline: View {
    @Bindable var store: StudioEditStore
    let cache: StudioMediaCache
    let player: StudioPlayer
    let thumbs: StudioThumbs
    @Binding var pps: Double
    @Binding var draft: StudioDraft?
    /// the square between two shots that is open (its transition sheet)
    var openCut: String?
    var onCut: (String) -> Void
    var onAdd: () -> Void

    @State private var gesture = GestureState()
    @State private var pinchFrom: Double?
    @State private var reorder: Reorder?
    @State private var chip: String?
    @State private var fling: Task<Void, Never>?

    private struct GestureState {
        enum Mode { case undecided, scroll, trim(String, left: Bool), move(String), reorder, none }
        var mode = Mode.undecided
        var startTime = 0.0
        var original: StudioClip?
        var hold: Task<Void, Never>?
        var still: Task<Void, Never>?
        var snapOff = false
        var lastMove = Date()
        var held = false
    }

    struct Reorder: Equatable {
        var order: [String]
        var lifted: String
        var from: Int
        var to: Int
        var x: CGFloat
        var startX: CGFloat
        var along: [String]
    }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width - 40
            let m = draft?.model ?? store.model
            let lay = StudioTimelineLayout(m, time: player.time, pps: pps, width: w)
            HStack(spacing: 0) {
                icons(lay)
                    .frame(width: 40)
                ZStack(alignment: .topLeading) {
                    Canvas(rendersAsynchronously: false) { ctx, size in
                        draw(&ctx, size, lay, m)
                    }
                    .contentShape(Rectangle())
                    .gesture(drag(lay, m, w))
                    .simultaneousGesture(pinch(w))
                    marks(lay, m)
                    playhead(lay, geo.size.height)
                    if reorder == nil, let v = lay.row(.video) {
                        Button(action: onAdd) {
                            LucideIcon(name: "plus", size: 20).foregroundStyle(.black)
                                .frame(width: 34, height: 34)
                                .background(Color.white, in: RoundedRectangle(cornerRadius: 8))
                        }
                        .accessibilityIdentifier("studioAdd")
                        .position(x: w - 24, y: v.y + v.h / 2)
                    }
                    overlayChips(lay, w)
                }
                .clipped()
                .task(id: m.video.count) { await demoGesture(lay, m) }
            }
        }
        .onChange(of: store.selected) { _, _ in chip = nil }
    }

    // MARK: drawing

    private func icons(_ lay: StudioTimelineLayout) -> some View {
        ZStack(alignment: .top) {
            Color.clear
            ForEach(Array(lay.rows.enumerated()), id: \.offset) { _, r in
                if r.first {
                    LucideIcon(name: Self.icon(r.kind), size: 18)
                        .foregroundStyle(Theme.secondary)
                        .position(x: 20, y: r.y + r.h / 2)
                }
            }
            Rectangle().fill(Color(hex: 0x222222)).frame(width: 1).frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    static func icon(_ k: StudioTimelineLayout.Kind) -> String {
        switch k {
        case .video: return "film"
        case .text: return "type"
        case .voice: return "mic"
        case .music: return "music"
        case .sfx: return "audio-lines"
        }
    }

    private func visible(_ r: CGRect, _ size: CGSize) -> Bool { r.maxX >= -4 && r.minX <= size.width + 4 }

    private func draw(_ ctx: inout GraphicsContext, _ size: CGSize, _ lay: StudioTimelineLayout, _ m: StudioModel) {
        let t0 = lay.t(0), t1 = lay.t(size.width)
        // the ruler
        let scale = StudioScale(pps: pps)
        for t in scale.ticks(from: t0 - scale.step, to: t1) where t <= store.duration + 0.01 {
            let x = lay.x(t)
            ctx.draw(Text(scale.label(t)).font(.system(size: 11)).foregroundStyle(Theme.secondary),
                     at: CGPoint(x: x, y: 13))
            let mid = lay.x(t + scale.step / 2)
            ctx.fill(Path(ellipseIn: CGRect(x: mid - 1.5, y: 11.5, width: 3, height: 3)), with: .color(Color(hex: 0x555555)))
        }
        // chapters, when zoomed out
        if pps < 14 {
            for ch in store.chapters.dropFirst() {
                let x = lay.x(ch.start)
                var p = Path()
                p.move(to: CGPoint(x: x, y: StudioTimelineLayout.ruler))
                p.addLine(to: CGPoint(x: x, y: size.height))
                ctx.stroke(p, with: .color(Theme.violet.opacity(0.8)), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                ctx.draw(Text("Ch \(ch.chapter)").font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.violet),
                         at: CGPoint(x: x + 5, y: StudioTimelineLayout.ruler + 10), anchor: .leading)
            }
        }
        if let r = reorder { drawTiles(&ctx, size, lay, m, r) } else { drawVideo(&ctx, size, lay, m) }
        let dim = reorder != nil ? 0.35 : 1.0
        // text
        for c in m.overlay {
            guard let r = lay.rect(c), visible(r, size) else { continue }
            clip(&ctx, r, Theme.violet, fill: 0x2A2440, label: "T  " + (c.text ?? "").replacingOccurrences(of: "\n", with: " · "),
                 selected: c.id == store.selected, dim: dim)
        }
        // voice
        for l in store.voice {
            guard let r = lay.rect(l), visible(r, size) else { continue }
            let sel = store.selected == "voice:\(l.id)"
            clip(&ctx, r, Theme.blue, fill: 0x17243A, label: "\(l.id)  \(l.text)", selected: sel, dim: dim) { ctx in
                if let f = l.file { wave(&ctx, r, f, from: 0, color: Theme.blue, top: 18) }
            }
        }
        // music, with its level (the dips are the ducking)
        let levels = Dictionary(grouping: StudioPreview.sounds(m, voice: store.voice, mix: store.mix, ready: { _ in true })
            .filter { $0.bus == "music" }, by: \.id)
        let top = max(0.001, levels.values.flatMap { $0.flatMap { $0.gain.map(\.g) } }.max() ?? 1)
        for c in m.music {
            guard let r = lay.rect(c), visible(r, size) else { continue }
            clip(&ctx, r, Theme.green, fill: 0x1C2A1C, label: name(c), selected: c.id == store.selected, dim: dim) { ctx in
                if let f = c.file { wave(&ctx, r, f, from: c.trim ?? 0, color: Theme.green.opacity(0.7), top: 20) }
                if let pts = levels[c.id]?.first?.gain, pts.count > 1 {
                    var p = Path()
                    for (i, g) in pts.enumerated() {
                        let pt = CGPoint(x: lay.x(g.t), y: r.maxY - 4 - CGFloat(g.g / top) * (r.height - 22))
                        if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
                    }
                    ctx.stroke(p, with: .color(Color(hex: 0xBFE8BF)), lineWidth: 1.5)
                }
            }
        }
        // effects
        for c in m.sfx {
            guard let r = lay.rect(c), visible(r, size) else { continue }
            clip(&ctx, r, Theme.amber, fill: 0x2E2314, label: name(c), selected: c.id == store.selected, dim: dim) { ctx in
                if let f = c.file { wave(&ctx, r, f, from: c.trim ?? 0, color: Theme.amber.opacity(0.7), top: 16) }
            }
        }
    }

    /// a sound clip's name: its title in the library and where it came from ("Soft room tone · CC0")
    private func name(_ c: StudioClip) -> String {
        if let l = c.label { return l }
        let s = store.view?.log?.first { $0.file == c.file }
        let title = s?.title ?? ((c.file ?? c.id) as NSString).lastPathComponent
        let from: String? = switch s?.source {
        case "freesound": "CC0"
        case "eleven-music": "Eleven Music"
        case "elevenlabs": "ElevenLabs"
        case "recorded": "Recorded"
        default: nil
        }
        return from.map { "\(title) · \($0)" } ?? title
    }

    private func clip(_ ctx: inout GraphicsContext, _ r: CGRect, _ color: Color, fill: UInt32, label: String, selected: Bool,
                      dim: Double, inside: ((inout GraphicsContext) -> Void)? = nil) {
        let shape = Path(roundedRect: r, cornerRadius: 6)
        ctx.drawLayer { l in
            l.opacity = dim
            l.fill(shape, with: .color(Color(hex: fill)))
            l.clip(to: shape)
            inside?(&l)
            if r.width > 24 {
                l.draw(Text(label).font(.system(size: 12, weight: .medium)).foregroundStyle(color),
                       at: CGPoint(x: max(r.minX, 0) + 8, y: r.minY + 9), anchor: .leading)
            }
        }
        ctx.stroke(shape, with: .color(selected ? .white : color.opacity(0.55 * dim)), lineWidth: selected ? 2.5 : 1)
        if selected { handles(&ctx, r) }
    }

    private func handles(_ ctx: inout GraphicsContext, _ r: CGRect) {
        for x in [r.minX - 6, r.maxX - 6] {
            let h = CGRect(x: x, y: r.minY, width: 12, height: r.height)
            ctx.fill(Path(roundedRect: h, cornerRadius: 4), with: .color(.white))
            ctx.fill(Path(roundedRect: CGRect(x: h.midX - 1, y: h.midY - 7, width: 2, height: 14), cornerRadius: 1),
                     with: .color(.black))
        }
    }

    private func wave(_ ctx: inout GraphicsContext, _ r: CGRect, _ file: String, from: Double, color: Color, top: CGFloat) {
        guard let pk = cache.peaks[file], !pk.isEmpty else { return }
        let area = CGRect(x: r.minX, y: r.minY + top, width: r.width, height: r.height - top - 3)
        var p = Path()
        var x = max(r.minX + 2, -2)
        let end = min(r.maxX - 2, CGFloat(4000))
        while x < end {
            let t = from + Double(x - r.minX) / pps
            let i = Int(t * 25)
            if i >= 0, i < pk.count {
                let h = max(1, CGFloat(pk[i]) * area.height)
                p.addRect(CGRect(x: x, y: area.midY - h / 2, width: 1.6, height: h))
            }
            x += 3
        }
        ctx.fill(p, with: .color(color))
    }

    private func drawVideo(_ ctx: inout GraphicsContext, _ size: CGSize, _ lay: StudioTimelineLayout, _ m: StudioModel) {
        let shots = store.shots
        for (i, c) in m.video.enumerated() {
            guard let r = lay.rect(c), visible(r, size) else { continue }
            let shape = Path(roundedRect: r, cornerRadius: 5)
            let (src, _) = StudioEdit.source(c, shots)
            let md = store.media(src)
            ctx.drawLayer { l in
                l.clip(to: shape)
                l.fill(shape, with: .color(Color(hex: 0x1E1E1E)))
                if src != nil, md != nil {
                    let tile = r.height * 16 / 9
                    var x = r.minX
                    // tiles that line up with the time, so the strip doesn't slide inside the clip
                    while x < r.maxX {
                        if x + tile >= -2, x <= size.width + 2 {
                            let img: UIImage?
                            if let n = md?.frames, n > 1, let len = md?.seconds, len > 0 {
                                let t = (c.trim ?? 0) + Double(x + tile / 2 - r.minX) / pps
                                img = thumbs.frame(md?.thumb, n, Int(t / len * Double(n)), store)
                            } else {
                                img = thumbs.image(md?.thumb ?? md?.url, store)
                            }
                            if let img { l.draw(Image(uiImage: img), in: CGRect(x: x, y: r.minY, width: tile, height: r.height)) }
                        }
                        x += tile
                    }
                } else {
                    // planned: no picture yet
                    l.stroke(Path(roundedRect: r.insetBy(dx: 1, dy: 1), cornerRadius: 5), with: .color(Color(hex: 0x555555)),
                             style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    let what = c.shot.flatMap { shots[$0] }?.description ?? (c.label ?? "No picture yet")
                    l.draw(Text(what).font(.system(size: 11)).foregroundStyle(Theme.secondary),
                           in: r.insetBy(dx: 26, dy: 18))
                }
                if c.id != store.selected, r.width > 22 {
                    let n = CGRect(x: r.minX + 5, y: r.minY + 5, width: 18, height: 16)
                    l.fill(Path(roundedRect: n, cornerRadius: 4), with: .color(.black.opacity(0.6)))
                    l.draw(Text("\(i + 1)").font(.system(size: 11, weight: .semibold)).foregroundStyle(.white),
                           at: CGPoint(x: n.midX, y: n.midY))
                }
            }
            if c.id == store.selected {
                ctx.stroke(Path(roundedRect: r.insetBy(dx: -1, dy: -1), cornerRadius: 6), with: .color(.white), lineWidth: 3)
                handles(&ctx, r)
                let label = String(format: "%.1fs", c.dur)
                let chip = CGRect(x: r.minX + 10, y: r.minY + 5, width: CGFloat(label.count) * 7 + 10, height: 18)
                ctx.fill(Path(roundedRect: chip, cornerRadius: 5), with: .color(.white))
                ctx.draw(Text(label).font(.system(size: 11, weight: .semibold)).foregroundStyle(.black),
                         at: CGPoint(x: chip.midX, y: chip.midY))
            }
        }
        // the squares between shots: how one goes into the next
        guard pps >= 12, let v = lay.row(.video) else { return }
        for cut in lay.cuts(m) where cut.x > -12 && cut.x < size.width + 12 {
            let open = cut.id == openCut
            let kind = StudioEdit.clip(cut.id, in: m)?.transition
            let sq = CGRect(x: cut.x - 10, y: v.y + v.h / 2 - 10, width: 20, height: 20)
            ctx.fill(Path(roundedRect: sq, cornerRadius: 5), with: .color(open ? Theme.blue : .white))
            if kind == "crossfade" || kind == "dip" {
                ctx.stroke(Path(ellipseIn: sq.insetBy(dx: 5, dy: 5).offsetBy(dx: -2, dy: 0)), with: .color(.black), lineWidth: 1.4)
                ctx.stroke(Path(ellipseIn: sq.insetBy(dx: 5, dy: 5).offsetBy(dx: 2, dy: 0)), with: .color(.black), lineWidth: 1.4)
            } else {
                ctx.fill(Path(CGRect(x: sq.midX - 0.75, y: sq.minY + 5, width: 1.5, height: 10)), with: .color(.black))
            }
        }
    }

    /// the shots as tiles while one is lifted (27)
    private func drawTiles(_ ctx: inout GraphicsContext, _ size: CGSize, _ lay: StudioTimelineLayout, _ m: StudioModel,
                           _ r: Reorder) {
        guard let v = lay.row(.video) else { return }
        let shots = store.shots
        let ids = r.order.filter { $0 != r.lifted }
        var order = ids
        order.insert(r.lifted, at: min(r.to, ids.count))
        let x0 = r.startX - CGFloat(r.from) * 64 - 32
        for (k, id) in order.enumerated() where id != r.lifted {
            let rect = CGRect(x: x0 + CGFloat(k) * 64 + 3, y: v.y + 2, width: 58, height: v.h - 4)
            tile(&ctx, rect, id, m, shots, n: (m.video.firstIndex { $0.id == id } ?? 0) + 1)
        }
        // the drop mark and the lifted tile under the finger
        let drop = x0 + CGFloat(min(r.to, ids.count)) * 64
        ctx.fill(Path(CGRect(x: drop - 1, y: v.y + v.h + 1, width: 2, height: 8)), with: .color(Theme.blue))
        let lifted = CGRect(x: r.x - 34, y: v.y - 8, width: 68, height: v.h + 4)
        var l = ctx
        l.addFilter(.shadow(color: .black.opacity(0.6), radius: 8))
        tile(&l, lifted, r.lifted, m, shots, n: (m.video.firstIndex { $0.id == r.lifted } ?? 0) + 1)
        ctx.stroke(Path(roundedRect: lifted, cornerRadius: 8), with: .color(.white), lineWidth: 2.5)
    }

    private func tile(_ ctx: inout GraphicsContext, _ r: CGRect, _ id: String, _ m: StudioModel,
                      _ shots: [String: StudioShot], n: Int) {
        guard let c = StudioEdit.clip(id, in: m) else { return }
        let shape = Path(roundedRect: r, cornerRadius: 8)
        let md = store.media(StudioEdit.source(c, shots).src)
        ctx.drawLayer { l in
            l.clip(to: shape)
            l.fill(shape, with: .color(Color(hex: 0x242424)))
            let img = md?.frames.map { thumbs.frame(md?.thumb, $0, $0 / 2, store) } ?? thumbs.image(md?.thumb ?? md?.url, store)
            if let img {
                let w = r.height * 16 / 9
                l.draw(Image(uiImage: img), in: CGRect(x: r.midX - w / 2, y: r.minY, width: w, height: r.height))
            }
            let b = CGRect(x: r.minX + 5, y: r.minY + 5, width: 18, height: 16)
            l.fill(Path(roundedRect: b, cornerRadius: 4), with: .color(.black.opacity(0.6)))
            l.draw(Text("\(n)").font(.system(size: 11, weight: .semibold)).foregroundStyle(.white), at: CGPoint(x: b.midX, y: b.midY))
        }
        ctx.stroke(shape, with: .color(Color(hex: 0x3A3A3A)), lineWidth: 1)
    }

    private func playhead(_ lay: StudioTimelineLayout, _ h: CGFloat) -> some View {
        ZStack(alignment: .top) {
            Rectangle().fill(.white).frame(width: 2)
            Capsule().fill(.white).frame(width: 12, height: 8).offset(y: StudioTimelineLayout.ruler - 6)
        }
        .frame(height: max(0, min(h, lay.height) - 4))
        .position(x: lay.centerX, y: max(0, min(h, lay.height) - 4) / 2 + 2)
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func overlayChips(_ lay: StudioTimelineLayout, _ w: CGFloat) -> some View {
        VStack(spacing: 6) {
            if let d = draft {
                Text(d.bubble)
                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(.black)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(Color.white, in: Capsule())
                    .accessibilityIdentifier("studioTrimBubble")
            }
            Spacer()
            if let s = draft?.snapped {
                Text("Snapped to \(s)")
                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                    .padding(.horizontal, 12).padding(.vertical, 5)
                    .background(Theme.blue.opacity(0.9), in: Capsule())
                    .accessibilityIdentifier("studioSnapped")
            } else if draft != nil {
                Text(gesture.snapOff ? "Snapping off · let go to place" : "Snaps to words, cuts and the playhead · hold to turn off")
                    .font(.system(size: 12)).foregroundStyle(Theme.title)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(Color(hex: 0x262626), in: Capsule())
            } else if let c = chip ?? zoomChip {
                Text(c)
                    .font(.system(size: 13, weight: .medium)).foregroundStyle(reorder != nil ? Theme.amber : Theme.title)
                    .padding(.horizontal, 12).padding(.vertical, 5)
                    .background(reorder != nil ? Color(hex: 0x2E2314) : Color(hex: 0x262626), in: Capsule())
                    .accessibilityIdentifier("studioChip")
            }
        }
        .padding(.top, 0).padding(.bottom, 10)
        .frame(width: w, height: max(lay.height, 120))
        .allowsHitTesting(false)
    }

    /// zoomed out far: the chapter at the playhead, its length and shots (26)
    private var zoomChip: String? {
        guard pps < 14, let ch = StudioEdit.chapter(at: player.time, store.chapters) else { return nil }
        let n = store.model.video.filter { $0.start >= ch.start - 0.05 && $0.start < ch.end - 0.05 }.count
        return "\(ch.title) · \(StudioEdit.clock(ch.end - ch.start, tenths: false)) · \(n) shot\(n == 1 ? "" : "s")"
    }

    /// invisible marks where the clips are, so the screen tests (and VoiceOver) can find them
    private func marks(_ lay: StudioTimelineLayout, _ m: StudioModel) -> some View {
        let w = lay.width
        let all = StudioTrack.allCases.flatMap { m[$0] }.compactMap { c in lay.rect(c).map { ("clip-\(c.id)", $0) } }
            + store.voice.compactMap { l in lay.rect(l).map { ("voice-\(l.id)", $0) } }
            + (pps >= 12 ? lay.cuts(m).compactMap { c in lay.row(.video).map { v in
                ("cut-\(c.id)", CGRect(x: c.x - 10, y: v.y + v.h / 2 - 10, width: 20, height: 20)) } } : [])
        let shown = all.compactMap { id, r -> (String, CGRect)? in
            let v = r.intersection(CGRect(x: 0, y: 0, width: w, height: lay.height))
            return v.isNull || v.width < 4 ? nil : (id, v)
        }
        var out = shown
        if let s = store.selected, !s.hasPrefix("voice:"), let c = StudioEdit.clip(s, in: m), let r = lay.rect(c) {
            out.append(("handle-left", CGRect(x: r.minX - 6, y: r.minY, width: 12, height: r.height)))
            out.append(("handle-right", CGRect(x: r.maxX - 6, y: r.minY, width: 12, height: r.height)))
        }
        out.append(("studioRuler", CGRect(x: 0, y: 0, width: w, height: StudioTimelineLayout.ruler)))
        return ZStack(alignment: .topLeading) {
            ForEach(out, id: \.0) { id, r in
                Rectangle().fill(.white.opacity(0.001))
                    .frame(width: r.width, height: r.height)
                    .position(x: r.midX, y: r.midY)
                    .accessibilityElement()
                    .accessibilityIdentifier(id)
                    .accessibilityAddTraits(.isButton)
            }
        }
        .allowsHitTesting(false)
    }

    // MARK: touches

    private func drag(_ lay: StudioTimelineLayout, _ m: StudioModel, _ w: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { v in
                let d = hypot(v.translation.width, v.translation.height)
                if case .undecided = gesture.mode, !gesture.held {
                    if gesture.hold == nil {
                        fling?.cancel()
                        gesture.startTime = player.time
                        let at = v.startLocation
                        let hit = lay.hit(at, m, voice: store.voice, selected: store.selected)
                        gesture.hold = Task { @MainActor in
                            try? await Task.sleep(nanoseconds: 400_000_000)
                            guard !Task.isCancelled else { return }
                            if case .clip(let id) = hit, StudioEdit.track(of: id, in: m) == .video { lift(id, at: at.x, lay, m) }
                        }
                    }
                    guard d > 6 else { return }
                    gesture.hold?.cancel()
                    switch lay.hit(v.startLocation, m, voice: store.voice, selected: store.selected) {
                    case .handle(let id, let left):
                        gesture.mode = .trim(id, left: left)
                        gesture.original = StudioEdit.clip(id, in: m)
                        player.pause()
                    case .clip(let id) where id == store.selected && StudioEdit.track(of: id, in: m) != .video:
                        gesture.mode = .move(id)
                        gesture.original = StudioEdit.clip(id, in: m)
                    default:
                        gesture.mode = .scroll
                    }
                }
                switch gesture.mode {
                case .scroll:
                    player.seek(min(store.duration, max(0, gesture.startTime - Double(v.translation.width) / pps)))
                case .trim(_, let left):
                    trimMove(v.translation.width, left: left, lay)
                case .move:
                    moveClip(v.translation.width, lay)
                case .reorder:
                    reorderMove(v.location.x)
                default: break
                }
            }
            .onEnded { v in
                gesture.hold?.cancel()
                gesture.still?.cancel()
                let mode = gesture.mode
                let original = gesture.original
                gesture = GestureState()
                switch mode {
                case .undecided:
                    tap(lay.hit(v.startLocation, m, voice: store.voice, selected: store.selected))
                case .scroll:
                    let extra = Double(v.predictedEndTranslation.width - v.translation.width) / pps
                    if abs(extra) > 0.2 { glide(by: -extra) }
                case .trim, .move:
                    player.peek(nil)
                    if let d = draft, let o = original {
                        store.change(d.label, toast: false) { mm in
                            mm = d.model
                            return true
                        }
                        store.selected = o.id
                    }
                    draft = nil
                case .reorder:
                    dropTile()
                case .none: break
                }
            }
    }

    private func pinch(_ w: CGFloat) -> some Gesture {
        MagnifyGesture()
            .onChanged { v in
                if pinchFrom == nil { pinchFrom = pps; gesture.mode = .none; gesture.hold?.cancel() }
                pps = StudioScale(pps: (pinchFrom ?? pps) * v.magnification).clamped(duration: store.duration, width: w).pps
            }
            .onEnded { _ in pinchFrom = nil }
    }

    private func tap(_ hit: StudioTimelineLayout.Hit) {
        switch hit {
        case .ruler(let t): player.seek(min(store.duration, max(0, t)))
        case .cut(let id): onCut(id)
        case .clip(let id), .voice(let id): store.selected = store.selected == id ? nil : id
        case .handle: break
        case .none: store.selected = nil
        }
    }

    /// a fling keeps the timeline going for a moment
    private func glide(by dt: Double) {
        fling?.cancel()
        let from = player.time
        fling = Task { @MainActor in
            let steps = 24
            for i in 1...steps {
                try? await Task.sleep(nanoseconds: 16_000_000)
                if Task.isCancelled { return }
                let p = 1 - pow(1 - Double(i) / Double(steps), 3)
                player.seek(min(store.duration, max(0, from + dt * p)))
            }
        }
    }

    private func names() -> [String: String] {
        var n: [String: String] = [:]
        for (i, c) in store.model.video.enumerated() { n[c.id] = "shot \(i + 1)" }
        for c in store.model.overlay { n[c.id] = "“\(StudioEdit.cut(c.text ?? "", 24))”" }
        for t in [StudioTrack.music, .sfx] { for c in store.model[t] { n[c.id] = name(c) } }
        return n
    }

    /// holding still a moment while dragging turns snapping off
    private func watchStill() {
        gesture.still?.cancel()
        gesture.still = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 700_000_000)
            if !Task.isCancelled { gesture.snapOff = true }
        }
    }

    private func trimMove(_ dx: CGFloat, left: Bool, _ lay: StudioTimelineLayout) {
        guard let o = gesture.original else { return }
        watchStill()
        var m = store.model
        let snaps = gesture.snapOff ? [] : StudioEdit.snapPoints(m, voice: store.voice, playhead: player.time, skip: o.id,
                                                                names: names())
        let hit = StudioEdit.trim(&m, original: o, edge: left ? .left : .right, by: Double(dx) / pps, shots: store.shots,
                                  snaps: snaps, within: 8 / pps)
        guard let c = StudioEdit.clip(o.id, in: m) else { return }
        let edge = left ? c.start : c.end
        let change = c.dur - o.dur
        let n = names()[o.id] ?? o.id
        draft = StudioDraft(model: m,
                            bubble: String(format: "%@ · %.1f s · %@%.1f", StudioEdit.clock(edge), c.dur,
                                           change < 0 ? "−" : "+", abs(change)),
                            snapped: hit?.what, label: "Trimmed \(n) to \(String(format: "%.1f", c.dur)) s")
        player.peek(edge - (left ? 0 : StudioEdit.frame))
    }

    private func moveClip(_ dx: CGFloat, _ lay: StudioTimelineLayout) {
        guard let o = gesture.original else { return }
        watchStill()
        var m = store.model
        let snaps = gesture.snapOff ? [] : StudioEdit.snapPoints(m, voice: store.voice, playhead: player.time, skip: o.id,
                                                                names: names())
        let hit = StudioEdit.move(&m, original: o, by: Double(dx) / pps, snaps: snaps, within: 8 / pps)
        guard let c = StudioEdit.clip(o.id, in: m) else { return }
        let n = names()[o.id] ?? o.id
        draft = StudioDraft(model: m, bubble: "\(StudioEdit.clock(c.start)) – \(StudioEdit.clock(c.end))",
                            snapped: hit?.what, label: "Moved \(n) to \(StudioEdit.clock(c.start))")
    }

    // MARK: the demo's held gestures (the screen pictures 17 and 27 show a drag mid-way)

    /// `-studioTrim v6:right:-0.6` holds a trim; `-studioLift v6:1` holds shot v6 lifted, moved one place on
    @State private var demoDone = false

    private func demoGesture(_ lay: StudioTimelineLayout, _ m: StudioModel) async {
        guard Demo.isOn, !demoDone, !m.video.isEmpty else { return }
        let a = Demo.args
        func arg(_ f: String) -> [String]? {
            a.firstIndex(of: f).flatMap { $0 + 1 < a.count ? a[$0 + 1].components(separatedBy: ":") : nil }
        }
        guard arg("-studioTrim") != nil || arg("-studioLift") != nil else { return }
        demoDone = true
        try? await Task.sleep(nanoseconds: 600_000_000)
        let m = store.model
        if let t = arg("-studioTrim"), t.count == 3, let c = StudioEdit.clip(t[0], in: m), let by = Double(t[2]) {
            store.selected = c.id
            gesture.original = c
            gesture.mode = .trim(c.id, left: t[1] == "left")
            trimMove(CGFloat(by * pps), left: t[1] == "left", lay)
        }
        if let l = arg("-studioLift"), l.count == 2, m.video.contains(where: { $0.id == l[0] }), let by = Int(l[1]) {
            // the shot comes under the playhead as it's lifted, so the finger is there
            let x = lay.centerX
            lift(l[0], at: x, lay, m)
            reorderMove(x + CGFloat(by) * 64)
        }
    }

    // MARK: reorder

    private func lift(_ id: String, at x: CGFloat, _ lay: StudioTimelineLayout, _ m: StudioModel) {
        guard let i = m.video.firstIndex(where: { $0.id == id }) else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        gesture.mode = .reorder
        gesture.held = true
        store.selected = nil
        // the clips that ride along with the shot
        var test = m
        var order = m.video.map(\.id)
        order.swapAt(i, i == 0 ? min(1, order.count - 1) : i - 1)
        let along = StudioEdit.reorder(&test, order: order)
        reorder = Reorder(order: m.video.map(\.id), lifted: id, from: i, to: i, x: x, startX: x, along: along)
        let shot = "shot \(i + 1)"
        chip = along.isEmpty ? "Drag \(shot) to its new place" : "\(along.count == 1 ? "1 sound" : "\(along.count) clips") moves with \(shot)"
        player.seek(m.video[i].start + min(0.5, m.video[i].dur / 2))
    }

    private func reorderMove(_ x: CGFloat) {
        guard var r = reorder else { return }
        r.x = x
        let n = r.order.count
        r.to = max(0, min(n - 1, r.from + Int(((x - r.startX) / 64).rounded())))
        reorder = r
    }

    private func dropTile() {
        defer { reorder = nil; chip = nil }
        guard let r = reorder, r.to != r.from else { return }
        var order = r.order.filter { $0 != r.lifted }
        order.insert(r.lifted, at: r.to)
        let n = (r.order.firstIndex(of: r.lifted) ?? 0) + 1
        store.change("Moved shot \(n) to place \(r.to + 1)", toast: true) { m in
            StudioEdit.reorder(&m, order: order)
            return true
        }
        store.selected = r.lifted
    }
}
