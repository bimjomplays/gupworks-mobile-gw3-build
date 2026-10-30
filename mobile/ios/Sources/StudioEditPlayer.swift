import AVFoundation
import CoreImage
import SwiftUI
import UIKit

// The Edit stage's player: the timeline as it is now, built on the phone as one AVComposition from the PC's small
// copies of the media (640 px videos, JPEG stills, AAC sounds). A filler track of black runs the whole length; the
// shots' videos sit on their own tracks; a compositor draws each frame from StudioPreview.layers (Ken Burns,
// crossfades, dips, placeholder cards); every sound is placed with its volume ramps (gains, fades, the music ducked
// under the voice: the mixdown's sum). An edit rebuilds it in a moment, so the player always shows the current cut.

/// what the compositor draws from, made once a rebuild (read on the compositor's queue)
final class StudioScene: @unchecked Sendable {
    let model: StudioModel
    let shots: [String: StudioShot]
    let ready: Set<String>
    let images: [String: CIImage]
    let cards: [String: CIImage]
    let tracks: [String: CMPersistentTrackID]

    init(model: StudioModel, shots: [String: StudioShot], ready: Set<String>, images: [String: CIImage],
         cards: [String: CIImage], tracks: [String: CMPersistentTrackID]) {
        (self.model, self.shots, self.ready, self.images, self.cards, self.tracks) = (model, shots, ready, images, cards, tracks)
    }
}

final class StudioInstruction: NSObject, AVVideoCompositionInstructionProtocol, @unchecked Sendable {
    let timeRange: CMTimeRange
    let enablePostProcessing = false
    let containsTweening = true
    let requiredSourceTrackIDs: [NSValue]?
    let passthroughTrackID = kCMPersistentTrackID_Invalid
    let scene: StudioScene

    init(_ range: CMTimeRange, scene: StudioScene, tracks: [CMPersistentTrackID]) {
        timeRange = range
        self.scene = scene
        requiredSourceTrackIDs = tracks.map { NSNumber(value: $0) }
    }
}

final class StudioCompositor: NSObject, AVVideoCompositing, @unchecked Sendable {
    private static let format: [String: any Sendable] = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
    var sourcePixelBufferAttributes: [String: any Sendable]? { Self.format }
    var requiredPixelBufferAttributesForRenderContext: [String: any Sendable] { Self.format }
    private let ci = CIContext(options: [.cacheIntermediates: false])

    func renderContextChanged(_ newRenderContext: AVVideoCompositionRenderContext) {}

    func startRequest(_ r: AVAsynchronousVideoCompositionRequest) {
        guard let ins = r.videoCompositionInstruction as? StudioInstruction, let out = r.renderContext.newPixelBuffer() else {
            r.finish(with: NSError(domain: "studio", code: 1))
            return
        }
        let size = r.renderContext.size
        let frame = CGRect(origin: .zero, size: size)
        let s = ins.scene
        var img = CIImage(color: .black).cropped(to: frame)
        for l in StudioPreview.layers(at: r.compositionTime.seconds, s.model, shots: s.shots, ready: { s.ready.contains($0) }) {
            var src: CIImage?
            switch l.source {
            case .image(let f): src = s.images[f]
            case .video:
                if let id = s.tracks[l.clip], let pb = r.sourceFrame(byTrackID: id) { src = CIImage(cvPixelBuffer: pb) }
            case .card: src = nil
            }
            guard let pic = src ?? s.cards[l.clip] else { continue }
            var layer = Self.fill(pic, size, scale: l.scale, tx: l.tx).cropped(to: frame)
            if l.opacity < 0.999 {
                layer = layer.applyingFilter("CIColorMatrix", parameters: [
                    "inputAVector": CIVector(x: 0, y: 0, z: 0, w: CGFloat(max(0, l.opacity)))])
            }
            img = layer.composited(over: img)
        }
        ci.render(img, to: out, bounds: frame, colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
        r.finish(withComposedVideoFrame: out)
    }

    /// a picture filling the frame (cropped to fit), zoomed and moved by its Ken Burns
    static func fill(_ pic: CIImage, _ size: CGSize, scale: Double, tx: Double) -> CIImage {
        let e = pic.extent
        guard e.width > 0, e.height > 0 else { return pic }
        let s = max(size.width / e.width, size.height / e.height) * scale
        let t = CGAffineTransform(translationX: -e.midX, y: -e.midY)
            .concatenating(CGAffineTransform(scaleX: s, y: s))
            .concatenating(CGAffineTransform(translationX: size.width / 2 + tx * size.width, y: size.height / 2))
        return pic.transformed(by: t)
    }
}

/// Plays the Edit stage's timeline; `time` is the playhead (the timeline scrolls under it).
@Observable
@MainActor
final class StudioPlayer {
    let player = AVPlayer()
    private(set) var time: Double = 0
    private(set) var playing = false
    /// plays the PC's last mixdown (mix.wav) under the picture instead of the timeline's own mix
    var useMixdown = false
    private(set) var building = false
    /// the frame shown while a handle is dragged (nil: the playhead's)
    private(set) var peeking: Double?
    private var observer: Any?
    private var built: Key?
    private var waiting: Key?
    private var seeking = false
    private var nextSeek: Double?
    private var assets: [URL: AVURLAsset] = [:]
    private var lengths: [URL: Double] = [:]
    private var images: [String: CIImage] = [:]
    static let size = CGSize(width: 960, height: 540)

    struct Key: Equatable {
        var model: StudioModel
        var voice: [StudioVoiceLine]
        var mix: StudioMix
        var ready: Set<String>
        var mixdown: String?
        var duration: Double
    }

    init() {
        player.actionAtItemEnd = .pause
        observer = player.addPeriodicTimeObserver(forInterval: CMTime(value: 1, timescale: 30), queue: .main) { [weak self] t in
            MainActor.assumeIsolated {
                guard let self, self.playing else { return }
                self.time = max(0, t.seconds)
                if self.player.rate == 0, self.player.currentItem?.status == .readyToPlay { self.playing = false }
            }
        }
    }

    func toggle(duration: Double) {
        if playing {
            player.pause()
            playing = false
        } else {
            if time >= duration - 0.05 { seek(0) }
            playing = true
            player.play()
        }
    }

    func pause() {
        player.pause()
        playing = false
    }

    /// the playhead moved by hand: the picture follows (one seek at a time, the latest wins)
    func seek(_ t: Double) {
        time = max(0, t)
        if playing { player.pause(); playing = false }
        guard !seeking else { nextSeek = time; return }
        seeking = true
        player.seek(to: CMTime(seconds: time, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.seeking = false
                if let n = self.nextSeek { self.nextSeek = nil; self.peekOrSeek(n) }
            }
        }
    }

    /// Shows the frame at `t` without moving the playhead (a handle being dragged); nil goes back to the playhead.
    func peek(_ t: Double?) {
        peeking = t
        let to = t ?? time
        guard !seeking else { nextSeek = to; return }
        seeking = true
        player.seek(to: CMTime(seconds: max(0, to), preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.seeking = false
                if let n = self.nextSeek { self.nextSeek = nil; self.peekOrSeek(n) }
            }
        }
    }

    private func peekOrSeek(_ t: Double) {
        if peeking != nil { peek(t) } else { seek(t) }
    }

    /// Rebuilds the composition when the timeline, the mix or the loaded files changed.
    func update(_ store: StudioEditStore, _ cache: StudioMediaCache) {
        guard store.view != nil else { return }
        let ready = Set(cache.local.keys)
        let mixdown = useMixdown ? store.view?.mixdown?.file : nil
        let key = Key(model: store.model, voice: store.voice, mix: store.mix, ready: ready, mixdown: mixdown,
                      duration: store.duration)
        guard key != built, key != waiting else { return }
        waiting = key
        guard !building else { return }
        building = true
        Task {
            while let k = waiting {
                waiting = nil
                let item = await build(k, shots: store.shots, cache: cache)
                built = k
                if let item {
                    let wasPlaying = playing
                    player.replaceCurrentItem(with: item)
                    await player.seek(to: CMTime(seconds: time, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
                    if wasPlaying { player.play() }
                }
            }
            building = false
        }
    }

    private func asset(_ u: URL) -> AVURLAsset {
        if let a = assets[u] { return a }
        let a = AVURLAsset(url: u)
        assets[u] = a
        return a
    }

    private func length(_ u: URL) async -> Double {
        if let l = lengths[u] { return l }
        let l = (try? await asset(u).load(.duration).seconds) ?? 0
        lengths[u] = l
        return l
    }

    private func build(_ k: Key, shots: [String: StudioShot], cache: StudioMediaCache) async -> AVPlayerItem? {
        let comp = AVMutableComposition()
        let total = CMTime(seconds: max(k.duration, 0.5), preferredTimescale: 600)
        let ts = { (s: Double) in CMTime(seconds: s, preferredTimescale: 600) }
        // the black that runs the whole length
        guard let blackURL = Bundle.main.url(forResource: "studio-black", withExtension: "mp4"),
              let blackTrack = try? await asset(blackURL).loadTracks(withMediaType: .video).first,
              let base = comp.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
        else { return nil }
        let blackLen = CMTime(seconds: min(2, await length(blackURL)), preferredTimescale: 600)
        try? base.insertTimeRange(CMTimeRange(start: .zero, duration: blackLen), of: blackTrack, at: .zero)
        base.scaleTimeRange(CMTimeRange(start: .zero, duration: blackLen), toDuration: total)
        var trackIds = [base.trackID]
        var clipTrack: [String: CMPersistentTrackID] = [:]
        // the shots' videos, on as many tracks as their overlaps need
        let places = StudioPreview.videoPlacements(k.model, shots: shots, ready: { k.ready.contains($0) })
        for lane in StudioPreview.lanes(places, start: { $0.start }, end: { $0.start + $0.dur }) {
            guard let t = comp.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else { continue }
            for p in lane {
                guard let u = cache.local[p.file], let src = try? await asset(u).loadTracks(withMediaType: .video).first else { continue }
                let len = await length(u)
                let from = min(p.from, max(0, len - 0.05))
                let dur = min(p.dur, len - from)
                guard dur > 0.02 else { continue }
                try? t.insertTimeRange(CMTimeRange(start: ts(from), duration: ts(dur)), of: src, at: ts(p.start))
                clipTrack[p.clip] = t.trackID
            }
            trackIds.append(t.trackID)
        }
        // the sound
        var params: [AVMutableAudioMixInputParameters] = []
        var sounds: [StudioPreview.Sound]
        if let md = k.mixdown, k.ready.contains(md) {
            sounds = [StudioPreview.Sound(id: "mixdown", file: md, bus: "mix", start: 0, from: 0, dur: k.duration,
                                          gain: [StudioPreview.Point(t: 0, g: 1)])]
        } else {
            var lens: [String: Double] = [:]
            for l in k.voice { if let f = l.file, let u = cache.local[f] { lens[f] = await length(u) } }
            sounds = StudioPreview.sounds(k.model, voice: k.voice, mix: k.mix, lengths: lens, ready: { k.ready.contains($0) })
        }
        for lane in StudioPreview.lanes(sounds, start: { $0.start }, end: { $0.start + $0.dur }) {
            guard let t = comp.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else { continue }
            let p = AVMutableAudioMixInputParameters(track: t)
            for s in lane {
                guard let u = cache.local[s.file], let src = try? await asset(u).loadTracks(withMediaType: .audio).first else { continue }
                let len = await length(u)
                let from = min(s.from, max(0, len - 0.05))
                let dur = min(s.dur, len - from, max(0, k.duration - s.start))
                guard dur > 0.02 else { continue }
                try? t.insertTimeRange(CMTimeRange(start: ts(from), duration: ts(dur)), of: src, at: ts(s.start))
                let pts = s.gain.filter { $0.t <= s.start + dur + 1e-6 }
                if let first = pts.first { p.setVolume(Float(min(1, first.g)), at: ts(s.start)) }
                for (a, b) in zip(pts, pts.dropFirst()) where b.t > a.t {
                    p.setVolumeRamp(fromStartVolume: Float(min(1, a.g)), toEndVolume: Float(min(1, b.g)),
                                    timeRange: CMTimeRange(start: ts(a.t), end: ts(b.t)))
                }
            }
            params.append(p)
        }
        // the pictures
        var cards: [String: CIImage] = [:]
        for c in k.model.video {
            let (src, _) = StudioEdit.source(c, shots)
            if let src, StudioEdit.isImage(src), k.ready.contains(src), images[src] == nil, let u = cache.local[src] {
                images[src] = CIImage(contentsOf: u, options: [.applyOrientationProperty: true])
            }
            if src == nil || !k.ready.contains(src!) || (StudioEdit.isVideo(src) && clipTrack[c.id] == nil) {
                cards[c.id] = Self.card(c, shots)
            }
        }
        let scene = StudioScene(model: k.model, shots: shots, ready: k.ready, images: images, cards: cards, tracks: clipTrack)
        let vc = AVMutableVideoComposition()
        vc.customVideoCompositorClass = StudioCompositor.self
        vc.frameDuration = CMTime(value: 1, timescale: 30)
        vc.renderSize = Self.size
        vc.instructions = [StudioInstruction(CMTimeRange(start: .zero, duration: total), scene: scene, tracks: trackIds)]
        let item = AVPlayerItem(asset: comp)
        item.videoComposition = vc
        let mix = AVMutableAudioMix()
        mix.inputParameters = params
        item.audioMix = mix
        return item
    }

    /// the placeholder of a shot with no picture yet: its number and what it will show
    static func card(_ c: StudioClip, _ shots: [String: StudioShot]) -> CIImage? {
        let shot = c.shot.flatMap { shots[$0] }
        let r = UIGraphicsImageRenderer(size: CGSize(width: 480, height: 270))
        let img = r.image { ctx in
            UIColor(white: 0.13, alpha: 1).setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 480, height: 270))
            let title = shot.map { "Shot \($0.id.dropFirst())" } ?? (c.label ?? c.id)
            let body = shot?.description ?? "No picture yet"
            let p = NSMutableParagraphStyle()
            p.alignment = .center
            (title as NSString).draw(in: CGRect(x: 30, y: 90, width: 420, height: 30), withAttributes: [
                .font: UIFont.systemFont(ofSize: 22, weight: .semibold), .foregroundColor: UIColor(white: 0.85, alpha: 1),
                .paragraphStyle: p])
            (body as NSString).draw(in: CGRect(x: 40, y: 128, width: 400, height: 60), withAttributes: [
                .font: UIFont.systemFont(ofSize: 16), .foregroundColor: UIColor(white: 0.55, alpha: 1), .paragraphStyle: p])
        }
        return CIImage(image: img)
    }
}

/// the player's picture
struct StudioPlayerSurface: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> PlayerLayerView {
        let v = PlayerLayerView()
        v.playerLayer.player = player
        v.playerLayer.videoGravity = .resizeAspect
        v.backgroundColor = .black
        return v
    }

    func updateUIView(_ v: PlayerLayerView, context: Context) {
        if v.playerLayer.player !== player { v.playerLayer.player = player }
    }
}

/// The text on screen at the playhead, drawn over the picture as the desktop's EditComp draws it.
struct StudioOverlayText: View {
    let clip: StudioClip
    let opacity: Double
    let width: CGFloat
    var selected = false

    var body: some View {
        let lines = (clip.text ?? "").components(separatedBy: "\n")
        let k = width / 390
        Group {
            switch clip.style {
            case "title":
                Text(clip.text ?? "")
                    .font(.system(size: 26 * k, weight: .bold, design: .serif))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.7), radius: 6)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case "caption":
                Text(clip.text ?? "")
                    .font(.system(size: 13 * k, weight: .medium))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8 * k).padding(.vertical, 4 * k)
                    .background(Color.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 4))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, 14 * k)
            default:
                HStack(spacing: 0) {
                    Rectangle().fill(.white).frame(width: 3 * k)
                    VStack(alignment: .leading, spacing: 2 * k) {
                        Text(lines.first ?? "").font(.system(size: 17 * k, weight: .bold, design: .serif))
                        if lines.count > 1 {
                            Text(lines.dropFirst().joined(separator: " ")).font(.system(size: 11 * k))
                        }
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 9 * k).padding(.vertical, 6 * k)
                    .background(Color.black.opacity(0.55))
                }
                .fixedSize()
                .overlay {
                    if selected { Rectangle().stroke(style: StrokeStyle(lineWidth: 1, dash: [3, 3])).foregroundStyle(.white) }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                .padding(.leading, 18 * k).padding(.bottom, 16 * k)
            }
        }
        .opacity(opacity)
        .allowsHitTesting(false)
    }
}
