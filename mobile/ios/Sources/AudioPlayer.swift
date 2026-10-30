import AVFoundation
import SwiftUI
import UIKit

// a157: audio files in a chat play right where they are, in a flat card: a round play button, the file's waveform
// (tap or drag it to jump), the time and the speed. Claude's audio sits in its reply (MediaGroup); audio you sent sits
// under your bubble (Bubble). One sound plays at a time; the speed is the video player's (VideoSpeed), so a change in
// either carries over. The PC sends each file's length and loudness (gw3-phone's Media.audio_info); the plain math is
// in GupKit (Audio.swift).

/// The one playback all audio cards share.
@Observable
@MainActor
final class AudioPlayback {
    static let shared = AudioPlayback()

    /// the link that is playing or paused now
    private(set) var current: URL?
    private(set) var time: Double = 0
    private(set) var duration: Double = 0
    private(set) var playing = false     // playing or about to (waiting for data)
    private(set) var waiting = false
    private(set) var failed: String?
    /// the sound that last played to its end, and how many times one has (Studio's Listen reads on with it)
    private(set) var ended: URL?
    private(set) var ends = 0
    /// where each other sound was left (or was moved to before it played)
    private(set) var places: [URL: Double] = [:]
    var speed: Float = VideoSpeed().current {
        didSet {
            VideoSpeed().current = speed
            player.defaultRate = speed
            if player.rate != 0 { player.rate = speed }
        }
    }

    @ObservationIgnored let player = AVPlayer()
    @ObservationIgnored private var scrubbing = false
    @ObservationIgnored private var timeObserver: Any?
    @ObservationIgnored private var observations: [NSKeyValueObservation] = []
    @ObservationIgnored private var itemObservations: [NSKeyValueObservation] = []
    @ObservationIgnored private var notes: [NSObjectProtocol] = []

    private init() {
        player.automaticallyWaitsToMinimizeStalling = true
        player.actionAtItemEnd = .pause
        observations.append(player.observe(\.timeControlStatus, options: [.initial, .new]) { [weak self] p, _ in
            let s = p.timeControlStatus
            Task { @MainActor in self?.control(s) }
        })
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(value: 1, timescale: 10), queue: .main) {
            [weak self] t in
            MainActor.assumeIsolated { self?.tick(t) }
        }
        notes.append(NotificationCenter.default.addObserver(forName: AVPlayerItem.didPlayToEndTimeNotification,
                                                            object: nil, queue: .main) { [weak self] n in
            let item = n.object as AnyObject?
            MainActor.assumeIsolated {
                guard let self, item === self.player.currentItem else { return }
                self.reachedEnd()
            }
        })
    }

    /// where `url` is: the live time when it's the one playing, else where it was left
    func place(of url: URL?) -> Double {
        guard let url else { return 0 }
        return url == current ? time : places[url] ?? 0
    }

    func isPlaying(_ url: URL?) -> Bool { url != nil && url == current && playing }
    func isWaiting(_ url: URL?) -> Bool { url != nil && url == current && waiting }
    func failure(of url: URL?) -> String? { url != nil && url == current ? failed : nil }

    /// Play or pause `url`; starting it pauses whatever else played.
    func toggle(_ url: URL) {
        if url == current, failed == nil {
            if playing {
                player.pause()
            } else {
                activate()
                if duration > 0, time >= duration - 0.05 { seek(url, to: 0) }
                player.playImmediately(atRate: speed)
            }
            return
        }
        if let current { places[current] = time }
        current = url
        failed = nil
        time = places[url] ?? 0
        duration = 0
        speed = VideoSpeed().current  // the video player may have changed it
        activate()
        itemObservations.removeAll()
        let item = AVPlayerItem(asset: AVURLAsset(url: url))
        item.audioTimePitchAlgorithm = .spectral  // faster or slower keeps the voice's pitch
        itemObservations.append(item.observe(\.status, options: [.new]) { [weak self] item, _ in
            Task { @MainActor in self?.status(of: item) }
        })
        player.replaceCurrentItem(with: item)
        if time > 0 { player.seek(to: CMTime(seconds: time, preferredTimescale: 600)) }
        player.defaultRate = speed
        player.play()
    }

    /// Jump: the playing sound seeks, another one remembers the place for when it plays.
    func seek(_ url: URL, to t: Double, done: Bool = true) {
        guard url == current else {
            places[url] = max(0, t)
            return
        }
        scrubbing = !done
        time = max(0, t)
        player.seek(to: CMTime(seconds: time, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
    }

    func pause() {
        player.pause()
    }

    private func activate() {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        try? AVAudioSession.sharedInstance().setActive(true)
    }

    private func status(of item: AVPlayerItem) {
        guard item === player.currentItem else { return }
        switch item.status {
        case .readyToPlay:
            let d = item.duration.seconds
            if d.isFinite, d > 0 { duration = d }
        case .failed:
            failed = item.error?.localizedDescription ?? "It couldn't be played."
            playing = false
            waiting = false
        default:
            break
        }
    }

    private func control(_ s: AVPlayer.TimeControlStatus) {
        playing = s != .paused
        waiting = s == .waitingToPlayAtSpecifiedRate
    }

    private func tick(_ t: CMTime) {
        guard !scrubbing, player.currentItem != nil, t.seconds.isFinite else { return }
        time = max(0, t.seconds)
        if let d = player.currentItem?.duration.seconds, d.isFinite, d > 0, d != duration { duration = d }
    }

    /// At the end it goes back to the start, ready to play again.
    private func reachedEnd() {
        ended = current
        ends += 1
        playing = false
        time = 0
        player.seek(to: .zero)
    }
}

/// One audio file in the chat.
struct AudioCard: View {
    let item: MDItem
    let base: URL?
    /// a file on the phone (the voice memo being previewed or sent, a161) instead of the item's link
    let local: URL?
    @State private var dragging: Double?
    @State private var waveWidth: Double = 1
    @State private var dragID = UUID()
    private var playback: AudioPlayback { .shared }

    init(item: MDItem, base: URL?, local: URL? = nil) {
        self.item = item
        self.base = base
        self.local = local
    }

    private var url: URL? { local ?? MediaLink.url(item.url, base: base) }
    private var name: String { AudioMath.title(item.name) }

    /// the PC's measured length first (the player's own can come out a hair short, 0:08 turning 0:07 on play)
    private var duration: Double {
        if let d = item.duration, d > 0 { return d }
        return url == playback.current ? playback.duration : 0
    }

    private var time: Double { dragging ?? playback.place(of: url) }

    var body: some View {
        Group {
            if let error = item.error {
                problem(error)
            } else if url == nil {
                problem("Its link is missing.")
            } else {
                player
            }
        }
        .background(ChatStyle.cardBG, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(ChatStyle.cardBorder, lineWidth: 1))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("audio")
    }

    private var player: some View {
        HStack(spacing: 12) {
            playButton
            VStack(alignment: .leading, spacing: 5) {
                AudioWaveform(bars: item.peaks, progress: AudioMath.progress(time: time, duration: duration))
                    .frame(height: 30)
                    .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { waveWidth = $0 }
                    // a sideways drag here scrubs: the menu's and the Overview's swipes leave it alone
                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { MenuSwipe.ownDrag[dragID] = $0 }
                    .onDisappear { MenuSwipe.ownDrag[dragID] = nil }
                    .contentShape(Rectangle())
                    .onTapGesture { p in
                        guard let url, duration > 0 else { return }
                        playback.seek(url, to: AudioMath.seek(x: p.x, width: waveWidth, duration: duration))
                    }
                    .gesture(scrub)
                    .accessibilityElement()
                    .accessibilityLabel("Waveform")
                    .accessibilityValue(AudioMath.timeLabel(time: time, duration: duration, playing: true))
                    .accessibilityAdjustableAction { dir in
                        guard let url else { return }
                        playback.seek(url, to: min(duration, max(0, time + (dir == .increment ? 5 : -5))))
                    }
                    .accessibilityIdentifier("audio-wave")
                HStack(spacing: 8) {
                    Text(name)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 4)
                    if let failed = playback.failure(of: url) {
                        Text("Couldn't play")
                            .foregroundStyle(ChatStyle.failed)
                            .accessibilityLabel("Couldn't play: \(failed)")
                    } else {
                        Text(AudioMath.timeLabel(time: time, duration: duration,
                                                 playing: playback.isPlaying(url) || url == playback.current))
                            .monospacedDigit()
                            .accessibilityIdentifier("audio-time")
                    }
                }
                .font(.system(size: 12))
                .foregroundStyle(ChatStyle.dim)
            }
            speedMenu
        }
        .padding(.leading, 10)
        .padding(.trailing, 6)
        .padding(.vertical, 9)
    }

    private var playButton: some View {
        Button {
            if let url { playback.toggle(url) }
        } label: {
            ZStack {
                Circle().fill(Color(hex: 0xECECEC))
                if playback.isWaiting(url) {
                    ProgressView().tint(.black).controlSize(.small)
                } else {
                    Image(systemName: playback.isPlaying(url) ? "pause.fill" : "play.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color(hex: 0x1A1A1C))
                        .offset(x: playback.isPlaying(url) ? 0 : 1.5)
                }
            }
            .frame(width: 40, height: 40)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(playback.isPlaying(url) ? "Pause \(name)" : "Play \(name)")
        .accessibilityValue(playback.isPlaying(url) ? "playing" : "paused")
        .accessibilityIdentifier("audio-play")
    }

    private var speedMenu: some View {
        Menu {
            Picker("Speed", selection: Binding(get: { playback.speed }, set: { playback.speed = $0 })) {
                ForEach(AudioMath.speeds, id: \.self) { s in
                    Text(AudioMath.speedLabel(s)).tag(s)
                }
            }
        } label: {
            Text(AudioMath.speedLabel(playback.speed))
                .font(.system(size: 13, weight: .semibold).monospacedDigit())
                .foregroundStyle(ChatStyle.body)
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(ChatStyle.chevronBG, in: Capsule())
                .overlay(Capsule().stroke(ChatStyle.cardBorder, lineWidth: 1))
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("Speed")
        .accessibilityValue(AudioMath.speedLabel(playback.speed))
        .accessibilityIdentifier("audio-speed")
    }

    /// a tap on the waveform jumps there (above); a drag follows the finger and lands where it lets go. Not from
    /// the first touch, so a scroll that starts on a card still scrolls the chat
    private var scrub: some Gesture {
        DragGesture(minimumDistance: 6)
            .onChanged { v in
                guard let url, duration > 0 else { return }
                let t = AudioMath.seek(x: v.location.x, width: waveWidth, duration: duration)
                dragging = t
                playback.seek(url, to: t, done: false)
            }
            .onEnded { v in
                guard let url, duration > 0 else { dragging = nil; return }
                playback.seek(url, to: AudioMath.seek(x: v.location.x, width: waveWidth, duration: duration))
                dragging = nil
            }
    }

    private func problem(_ why: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "waveform.slash")
                .font(.system(size: 18))
                .foregroundStyle(ChatStyle.dim)
                .frame(width: 40, height: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text("Can't play \(name)")
                    .font(.system(size: 15))
                    .foregroundStyle(ChatStyle.body)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(why)
                    .font(.system(size: 13))
                    .foregroundStyle(ChatStyle.dim)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .accessibilityElement(children: .combine)
    }
}

/// The waveform: rounded bars, the played part bright and the rest dim.
struct AudioWaveform: View {
    let bars: [Int]?
    let progress: Double

    var body: some View {
        Canvas { ctx, size in
            let n = AudioMath.barCount(width: size.width)
            let heights = AudioMath.bars(bars, count: n)
            let pitch = size.width / CGFloat(n)
            let w = max(1.5, pitch * 0.55)
            let played = size.width * progress
            for (i, h) in heights.enumerated() {
                let x = CGFloat(i) * pitch + (pitch - w) / 2
                let barH = max(w, size.height * h)
                let rect = CGRect(x: x, y: (size.height - barH) / 2, width: w, height: barH)
                let on = x + w / 2 <= played
                ctx.fill(Path(roundedRect: rect, cornerRadius: w / 2),
                         with: .color(on ? Color(hex: 0xECECEC) : Color(hex: 0x5A5A62)))
            }
        }
    }
}

/// Audio cards stacked: Claude's at the column's width, yours on the right under your bubble.
struct AudioList: View {
    let items: [MDItem]
    let base: URL?
    var mine = false

    var body: some View {
        VStack(alignment: mine ? .trailing : .leading, spacing: 8) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, it in
                AudioCard(item: it, base: base)
                    .frame(maxWidth: mine ? 340 : .infinity)
            }
        }
        .frame(maxWidth: .infinity, alignment: mine ? .trailing : .leading)
        .padding(.leading, mine ? 48 : 0)
    }
}
