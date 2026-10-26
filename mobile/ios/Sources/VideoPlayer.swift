import AVFoundation
import AVKit
import SwiftUI
import UIKit

// The full-screen video player: the desktop player's features (VideoCard.cpp) in Liquid Glass controls.
//
// It plays the PC's stream of the video (gw3_phone_video: 2 s pieces at up to three sizes, so the player picks what
// the link can carry, starts after one piece and seeks by fetching just that piece) and falls back to the file itself
// when the stream can't be had (an older gw3-phone, or the demo's bundled clip).

// MARK: - Pure parts (Tests/VideoPlayerTests.swift)

enum VideoMath {
    static let speeds: [Float] = [0.5, 0.75, 1, 1.25, 1.5, 2]
    static let skip: Double = 10
    static let hideAfter: Double = 3

    /// 0:05, 12:03, 1:02:03
    static func clock(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds > 0 else { return "0:00" }
        let s = Int(seconds.rounded(.down))
        let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec) : String(format: "%d:%02d", m, sec)
    }

    /// 1×, 1.5×, 0.75×
    static func speedLabel(_ rate: Float) -> String {
        var t = String(format: "%.2f", rate)
        while t.hasSuffix("0") { t.removeLast() }
        if t.hasSuffix(".") { t.removeLast() }
        return t + "×"
    }

    /// The PC's stream of a video link: /v1/media/<link>/index.m3u8. Nil for anything else (a bundled file).
    static func stream(of url: URL) -> URL? {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else { return nil }
        let parts = url.path.split(separator: "/")
        guard parts.count == 3, parts[0] == "v1", parts[1] == "media", url.query == nil else { return nil }
        return url.appendingPathComponent("index.m3u8")
    }

    static func clamp(_ t: Double, _ duration: Double) -> Double {
        guard t.isFinite else { return 0 }
        guard duration.isFinite, duration > 0 else { return max(0, t) }
        return min(max(0, t), duration)
    }

    /// A double tap on the left third skips back (-1), the right third forward (1), the middle goes full screen (0).
    static func side(_ x: CGFloat, width: CGFloat) -> Int {
        guard width > 0 else { return 0 }
        if x < width / 3 { return -1 }
        if x > width * 2 / 3 { return 1 }
        return 0
    }

    /// Where to pick a video up again: only between its first and last five seconds.
    static func resume(_ saved: Double?, duration: Double) -> Double? {
        guard let saved, saved.isFinite, saved >= 5, duration.isFinite, saved < duration - 5 else { return nil }
        return saved
    }

    /// How far the player has loaded from `t` on (the end of the loaded range around it), as a time.
    static func loaded(_ ranges: [(start: Double, length: Double)], at t: Double) -> Double {
        for r in ranges where r.start <= t + 0.5 && t <= r.start + r.length {
            return r.start + r.length
        }
        return t
    }

    /// Short clips loop like the desktop's gifs; longer videos stop at the end.
    static func loopsByDefault(duration: Double, name: String?) -> Bool {
        (name ?? "").lowercased().hasSuffix(".gif") || (duration > 0 && duration <= 10)
    }

    /// The key a video's place is remembered by: its links change (signed for a day), its name and length don't.
    static func resumeKey(name: String?, duration: Double) -> String {
        "\(name ?? "video")#\(Int(duration.isFinite ? duration.rounded() : 0))"
    }
}

/// The places videos were left at (UserDefaults), at most 200.
struct VideoResume {
    var defaults: UserDefaults = .standard
    static let key = "videoResume"

    func time(for id: String) -> Double? {
        (defaults.dictionary(forKey: Self.key) as? [String: Double])?[id]
    }

    func save(_ t: Double, duration: Double, for id: String) {
        var all = (defaults.dictionary(forKey: Self.key) as? [String: Double]) ?? [:]
        all[id] = VideoMath.resume(t, duration: duration)
        if all.count > 200, let drop = all.keys.first(where: { $0 != id }) { all[drop] = nil }
        defaults.set(all, forKey: Self.key)
    }
}

// MARK: - Orientation (the app is portrait; the player may turn)

@MainActor
enum Orientation {
    static var allowed: UIInterfaceOrientationMask = .portrait

    static func allow(_ mask: UIInterfaceOrientationMask, turnTo: UIInterfaceOrientationMask? = nil) {
        allowed = mask
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        for scene in scenes {
            for window in scene.windows {
                var vc = window.rootViewController
                while let c = vc {
                    c.setNeedsUpdateOfSupportedInterfaceOrientations()
                    vc = c.presentedViewController
                }
            }
            if let turnTo {
                scene.requestGeometryUpdate(.iOS(interfaceOrientations: turnTo)) { _ in }
            }
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        Orientation.allowed
    }
}

// MARK: - Playback

final class PlayerLayerView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
}

/// Picture in picture keeps a video going after its screen closes: the playback lives here meanwhile.
@MainActor
enum Floating {
    static var playback: VideoPlayback?
}

private final class PiPDelegate: NSObject, AVPictureInPictureControllerDelegate {
    var started: (@MainActor () -> Void)?
    var stopped: (@MainActor () -> Void)?

    func pictureInPictureControllerDidStartPictureInPicture(_ c: AVPictureInPictureController) {
        MainActor.assumeIsolated { started?() }
    }

    func pictureInPictureControllerDidStopPictureInPicture(_ c: AVPictureInPictureController) {
        MainActor.assumeIsolated { stopped?() }
    }

    func pictureInPictureController(_ c: AVPictureInPictureController,
                                    restoreUserInterfaceForPictureInPictureStopWithCompletionHandler done:
                                    @escaping (Bool) -> Void) {
        done(true)
    }
}

@Observable
@MainActor
final class VideoPlayback {
    let name: String?
    let original: URL?
    let stream: URL?
    let player = AVPlayer()
    let surface = PlayerLayerView()

    var time: Double = 0
    var duration: Double = 0
    var loadedTo: Double = 0
    var playing = false        // playing or about to (waiting for data)
    var waiting = false        // waiting for data: the spinner
    var ready = false
    var ended = false
    var failed: String?
    var hasSound = true
    var onStream = false
    var scrubbing = false
    var pipPossible = false
    var inPiP = false
    var muted = false { didSet { player.isMuted = muted } }
    var volume: Float = 1 { didSet { player.volume = volume } }
    var speed: Float = 1 {
        didSet {
            player.defaultRate = speed
            if player.rate != 0 { player.rate = speed }
        }
    }
    /// at the end: from the start without stopping (so the controls don't come back each time round)
    var loop = false { didSet { player.actionAtItemEnd = loop ? .none : .pause } }
    /// the screen closed while picture in picture went on; when that stops, so does the playback
    var screenGone = false
    /// picture in picture started from the button: the screen closes itself
    @ObservationIgnored var onPiPStarted: (() -> Void)?

    @ObservationIgnored private var started = false
    @ObservationIgnored private var resumed = false
    @ObservationIgnored private var loopChosen = false
    @ObservationIgnored private var timeObserver: Any?
    @ObservationIgnored private var observations: [NSKeyValueObservation] = []
    @ObservationIgnored private var itemObservations: [NSKeyValueObservation] = []
    @ObservationIgnored private var notes: [NSObjectProtocol] = []
    @ObservationIgnored private var pip: AVPictureInPictureController?
    private let pipDelegate = PiPDelegate()
    private let resume = VideoResume()

    init(item: MDItem, base: URL?) {
        name = item.name
        original = MediaLink.url(item.url, base: base)
        stream = original.flatMap(VideoMath.stream(of:))
    }

    // MARK: start and stop

    func start() {
        guard !started else { return }
        started = true
        screenGone = false
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        try? AVAudioSession.sharedInstance().setActive(true)
        player.automaticallyWaitsToMinimizeStalling = true
        player.defaultRate = speed
        surface.backgroundColor = .black
        surface.playerLayer.videoGravity = .resizeAspect
        surface.playerLayer.player = player
        observePlayer()
        setUpPiP()
        load(stream ?? original, isStream: stream != nil, at: 0)
    }

    /// The screen closed: remember the place and let go, unless picture in picture carries on.
    func close() {
        if inPiP {
            screenGone = true
            Floating.playback = self
            return
        }
        stop()
    }

    func stop() {
        guard started else { return }
        started = false
        remember()
        player.pause()
        if let timeObserver { player.removeTimeObserver(timeObserver) }
        timeObserver = nil
        observations.removeAll()
        itemObservations.removeAll()
        for n in notes { NotificationCenter.default.removeObserver(n) }
        notes.removeAll()
        player.replaceCurrentItem(with: nil)
        pip = nil
        if Floating.playback === self { Floating.playback = nil }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    func remember() {
        guard duration > 0 else { return }
        resume.save(ended ? 0 : time, duration: duration, for: VideoMath.resumeKey(name: name, duration: duration))
    }

    private func load(_ url: URL?, isStream: Bool, at t: Double) {
        guard let url else {
            failed = "This video's link is missing."
            return
        }
        failed = nil
        ready = false
        onStream = isStream
        itemObservations.removeAll()
        let item = AVPlayerItem(asset: AVURLAsset(url: url))
        itemObservations.append(item.observe(\.status, options: [.new]) { [weak self] item, _ in
            Task { @MainActor in self?.status(of: item) }
        })
        itemObservations.append(item.observe(\.tracks, options: [.new]) { [weak self] item, _ in
            Task { @MainActor in self?.tracks(of: item) }
        })
        player.replaceCurrentItem(with: item)
        if t > 0 { player.seek(to: CMTime(seconds: t, preferredTimescale: 600)) }
        player.play()  // plays as soon as enough is in (automaticallyWaitsToMinimizeStalling)
    }

    private func observePlayer() {
        observations.append(player.observe(\.timeControlStatus, options: [.initial, .new]) { [weak self] p, _ in
            Task { @MainActor in self?.control(p.timeControlStatus) }
        })
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(value: 1, timescale: 4), queue: .main) {
            [weak self] t in
            MainActor.assumeIsolated { self?.tick(t) }
        }
        let center = NotificationCenter.default
        notes.append(center.addObserver(forName: AVPlayerItem.didPlayToEndTimeNotification, object: nil,
                                        queue: .main) { [weak self] n in
            let item = n.object as AnyObject?
            MainActor.assumeIsolated {
                guard let self, item === self.player.currentItem else { return }
                self.reachedEnd()
            }
        })
        notes.append(center.addObserver(forName: AVPlayerItem.failedToPlayToEndTimeNotification, object: nil,
                                        queue: .main) { [weak self] n in
            let item = n.object as AnyObject?
            let error = (n.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error)?.localizedDescription
            MainActor.assumeIsolated {
                guard let self, item === self.player.currentItem else { return }
                self.fail(error)
            }
        })
    }

    private func setUpPiP() {
        guard pip == nil, AVPictureInPictureController.isPictureInPictureSupported() else { return }
        let c: AVPictureInPictureController? = AVPictureInPictureController(playerLayer: surface.playerLayer)
        c?.canStartPictureInPictureAutomaticallyFromInline = true
        pipDelegate.started = { [weak self] in
            guard let self else { return }
            self.inPiP = true
            self.onPiPStarted?()
        }
        pipDelegate.stopped = { [weak self] in
            guard let self else { return }
            self.inPiP = false
            if self.screenGone { self.stop() }
        }
        c?.delegate = pipDelegate
        pip = c
        if let c {
            observations.append(c.observe(\.isPictureInPicturePossible, options: [.initial, .new]) { [weak self] c, _ in
                Task { @MainActor in self?.pipPossible = c.isPictureInPicturePossible }
            })
        }
    }

    // MARK: what the player says

    private func status(of item: AVPlayerItem) {
        guard item === player.currentItem else { return }
        switch item.status {
        case .readyToPlay:
            ready = true
            let d = item.duration.seconds
            if d.isFinite, d > 0 { duration = d }
            if !loopChosen {
                loopChosen = true
                loop = VideoMath.loopsByDefault(duration: duration, name: name)
            }
            if !resumed {
                resumed = true
                if let t = VideoMath.resume(resume.time(for: VideoMath.resumeKey(name: name, duration: duration)),
                                            duration: duration) {
                    seek(to: t, exact: true)
                }
            }
        case .failed:
            fail(item.error?.localizedDescription)
        default:
            break
        }
    }

    private func fail(_ message: String?) {
        if onStream, let original {
            // the stream didn't work (an older PC service, say): the file itself, from where it was
            load(original, isStream: false, at: time)
            return
        }
        failed = message ?? "The video couldn't be loaded."
        playing = false
        waiting = false
    }

    private func tracks(of item: AVPlayerItem) {
        guard item === player.currentItem, !item.tracks.isEmpty else { return }
        hasSound = item.tracks.contains { $0.assetTrack?.mediaType == .audio }
    }

    private func control(_ s: AVPlayer.TimeControlStatus) {
        playing = s != .paused
        waiting = s == .waitingToPlayAtSpecifiedRate
        if s == .playing { ended = false }
    }

    private func tick(_ t: CMTime) {
        guard let item = player.currentItem else { return }
        if !scrubbing, t.seconds.isFinite { time = max(0, t.seconds) }
        let d = item.duration.seconds
        if d.isFinite, d > 0, d != duration { duration = d }
        let ranges = item.loadedTimeRanges.map { r -> (start: Double, length: Double) in
            (r.timeRangeValue.start.seconds, r.timeRangeValue.duration.seconds)
        }
        loadedTo = VideoMath.loaded(ranges, at: time)
    }

    private func reachedEnd() {
        if loop {
            player.seek(to: .zero)
            if player.rate == 0 { player.play() }
            return
        }
        ended = true
        time = duration
        resume.save(0, duration: duration, for: VideoMath.resumeKey(name: name, duration: duration))
    }

    // MARK: what you do

    func toggle() {
        if failed != nil { return retry() }
        if playing {
            player.pause()
        } else {
            if ended || (duration > 0 && time >= duration - 0.1) {
                ended = false
                seek(to: 0, exact: true)
            }
            player.play()
        }
    }

    func skip(_ seconds: Double) {
        seek(to: time + seconds, exact: true)
    }

    func seek(to t: Double, exact: Bool) {
        let to = VideoMath.clamp(t, duration)
        time = to
        if to < duration - 0.1 { ended = false }
        let tolerance = exact ? CMTime.zero : CMTime(seconds: 0.5, preferredTimescale: 600)
        player.seek(to: CMTime(seconds: to, preferredTimescale: 600), toleranceBefore: tolerance,
                    toleranceAfter: tolerance)
    }

    func retry() {
        failed = nil
        load(stream ?? original, isStream: stream != nil, at: time)
    }

    func startPiP() {
        pip?.startPictureInPicture()
    }
}

// MARK: - The screen

/// One chat video, full screen: plays at once, controls in glass that fade while it plays.
struct VideoPlayerScreen: View {
    let item: MDItem
    let base: URL?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var phase
    @State private var playback: VideoPlayback
    @State private var controls = true
    @State private var hideTask: Task<Void, Never>?
    @State private var drag: CGFloat = 0
    @State private var flash: Int = 0       // -1 / 1: the "10 s" bubble on that side
    @State private var flashTask: Task<Void, Never>?
    @State private var landscape = false
    @State private var preparing = false
    @State private var shareError: String?
    private let keepControls = ProcessInfo.processInfo.arguments.contains("-keepControls")

    init(item: MDItem, base: URL?) {
        self.item = item
        self.base = base
        _playback = State(initialValue: VideoPlayback(item: item, base: base))
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black
                    .opacity(1 - min(0.6, Double(drag) / 400))
                    .ignoresSafeArea()
                ZStack {
                    PlayerSurface(view: playback.surface)
                        .ignoresSafeArea()
                        .accessibilityElement()
                        .accessibilityLabel("Video \(item.name ?? "")")
                        .accessibilityIdentifier("videoPlayer")
                    Color.clear
                        .contentShape(Rectangle())
                        .ignoresSafeArea()
                        .gesture(
                            SpatialTapGesture(count: 2)
                                .onEnded { v in doubleTap(v.location.x, width: geo.size.width) }
                                .exclusively(before: TapGesture().onEnded { tapped() })
                        )
                    flashBubble
                    if playback.waiting && !(controls || !playback.playing) && playback.failed == nil {
                        spinner.allowsHitTesting(false)
                    }
                    if playback.failed != nil {
                        errorCard
                    } else if controls || !playback.playing {
                        controlsLayer
                            .transition(.opacity)
                    }
                }
                .offset(y: drag)
            }
            .simultaneousGesture(
                DragGesture(minimumDistance: 24)
                    .onChanged { v in
                        guard !playback.scrubbing, !landscape, v.translation.height > 0,
                              abs(v.translation.height) > abs(v.translation.width) else { return }
                        drag = v.translation.height
                    }
                    .onEnded { v in
                        if drag > 120 || (drag > 40 && v.predictedEndTranslation.height > 300) {
                            close()
                        } else {
                            withAnimation(.spring(duration: 0.3)) { drag = 0 }
                        }
                    }
            )
        }
        .statusBarHidden(!controls && playback.playing)
        .persistentSystemOverlays(controls ? .automatic : .hidden)
        .onAppear {
            Orientation.allow(.allButUpsideDown)
            playback.onPiPStarted = { close() }
            playback.start()
            poke()
        }
        .onDisappear {
            hideTask?.cancel()
            playback.close()
            Orientation.allow(.portrait, turnTo: .portrait)
        }
        .onChange(of: phase) { _, p in
            if p != .active { playback.remember() }
        }
        .onChange(of: playback.playing) { _, playing in
            if playing { poke() } else { withAnimation { controls = true } }
        }
        .onGeometryChange(for: Bool.self) { $0.size.width > $0.size.height } action: { landscape = $0 }
        .alert("Couldn't get the video", isPresented: .init(get: { shareError != nil }, set: { if !$0 { shareError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(shareError ?? "")
        }
    }

    // MARK: layers

    private var controlsLayer: some View {
        VStack(spacing: 0) {
            topBar
            Spacer(minLength: 12)
            centerButtons
            Spacer(minLength: 12)
            bottomPanel
        }
        .padding(.horizontal, landscape ? 24 : 12)
        .padding(.vertical, 8)
        .foregroundStyle(.white)
    }

    private var topBar: some View {
        HStack(spacing: 10) {
            roundButton("xmark", label: "Close", id: "videoClose") { close() }
            if let name = item.name, !name.isEmpty {
                Text(name)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .padding(.horizontal, 14)
                    .frame(height: 44)
                    .glassEffect(.regular, in: .capsule)
                    .accessibilityIdentifier("videoName")
            }
            Spacer(minLength: 0)
            GlassEffectContainer(spacing: 10) {
                HStack(spacing: 10) {
                    if playback.pipPossible {
                        roundButton("pip.enter", label: "Picture in picture", id: "pip") { playback.startPiP() }
                    }
                    AirPlayButton()
                        .frame(width: 44, height: 44)
                        .glassEffect(.regular.interactive(), in: .circle)
                        .accessibilityLabel("AirPlay")
                        .accessibilityIdentifier("airplay")
                    moreMenu
                }
            }
        }
    }

    private var centerButtons: some View {
        GlassEffectContainer(spacing: 28) {
            HStack(spacing: 28) {
                roundButton("gobackward.10", label: "Back 10 seconds", id: "skipBack", size: 60, font: 24) {
                    playback.skip(-VideoMath.skip)
                    poke()
                }
                Button {
                    playback.toggle()
                    poke()
                } label: {
                    ZStack {
                        if playback.waiting && playback.failed == nil {
                            ProgressView().controlSize(.large).tint(.white)
                        } else {
                            Image(systemName: playback.playing ? "pause.fill" : "play.fill")
                                .font(.system(size: 34, weight: .semibold))
                                .contentTransition(.symbolEffect(.replace))
                        }
                    }
                    .frame(width: 84, height: 84)
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .accessibilityLabel(playback.playing ? "Pause" : "Play")
                .accessibilityIdentifier("playPause")
                roundButton("goforward.10", label: "Forward 10 seconds", id: "skipForward", size: 60, font: 24) {
                    playback.skip(VideoMath.skip)
                    poke()
                }
            }
        }
    }

    private var bottomPanel: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                Text(VideoMath.clock(playback.time))
                    .accessibilityIdentifier("videoTime")
                Scrubber(playback: playback, poke: poke)
                Text(VideoMath.clock(playback.duration))
                    .accessibilityIdentifier("videoDuration")
            }
            .font(.footnote.monospacedDigit().weight(.medium))
            HStack(spacing: 6) {
                Button {
                    playback.muted.toggle()
                    poke()
                } label: {
                    Image(systemName: !playback.hasSound ? "speaker.slash" :
                            playback.muted || playback.volume == 0 ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(width: 40, height: 36)
                }
                .disabled(!playback.hasSound)
                .accessibilityLabel(!playback.hasSound ? "No sound" : playback.muted ? "Unmute" : "Mute")
                .accessibilityIdentifier("mute")
                if playback.hasSound {
                    Slider(value: Binding(get: { Double(playback.volume) }, set: {
                        playback.volume = Float($0)
                        if $0 > 0 { playback.muted = false }
                        poke()
                    }), in: 0...1)
                    .frame(maxWidth: landscape ? 160 : 110)
                    .tint(.white)
                    .accessibilityLabel("Volume")
                    .accessibilityIdentifier("volume")
                } else {
                    Text("No sound")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.white.opacity(0.7))
                        .accessibilityIdentifier("noSound")
                }
                Spacer(minLength: 4)
                speedMenu
                Button {
                    playback.loop.toggle()
                    poke()
                } label: {
                    Image(systemName: "repeat")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(playback.loop ? Theme.blue : .white)
                        .frame(width: 40, height: 36)
                }
                .accessibilityLabel("Loop")
                .accessibilityValue(playback.loop ? "On" : "Off")
                .accessibilityIdentifier("loop")
                Button {
                    rotate()
                } label: {
                    Image(systemName: landscape ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(width: 40, height: 36)
                }
                .accessibilityLabel(landscape ? "Exit full screen" : "Full screen")
                .accessibilityIdentifier("rotate")
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .glassEffect(.regular, in: .rect(cornerRadius: 26))
        .frame(maxWidth: 640)
    }

    private var speedMenu: some View {
        Menu {
            Picker("Speed", selection: Binding(get: { playback.speed }, set: { playback.speed = $0; poke() })) {
                ForEach(VideoMath.speeds, id: \.self) { s in
                    Text(VideoMath.speedLabel(s)).tag(s)
                }
            }
        } label: {
            Text(VideoMath.speedLabel(playback.speed))
                .font(.footnote.monospacedDigit().weight(.semibold))
                .frame(minWidth: 40, minHeight: 36)
        }
        .accessibilityLabel("Speed")
        .accessibilityValue(VideoMath.speedLabel(playback.speed))
        .accessibilityIdentifier("speed")
    }

    private var moreMenu: some View {
        Menu {
            Button {
                shareVideo()
            } label: {
                Label(preparing ? "Getting the video…" : "Share or save…", systemImage: "square.and.arrow.up")
            }
            .disabled(preparing)
            Button {
                playback.seek(to: 0, exact: true)
                if !playback.playing { playback.toggle() }
            } label: {
                Label("Play from the start", systemImage: "backward.end")
            }
            Divider()
            Text(playback.onStream ? "Streaming from your PC" : "Playing the file")
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 17, weight: .semibold))
                .frame(width: 44, height: 44)
                .glassEffect(.regular.interactive(), in: .circle)
        }
        .accessibilityLabel("More")
        .accessibilityIdentifier("videoMore")
    }

    private var spinner: some View {
        ProgressView()
            .controlSize(.large)
            .tint(.white)
            .frame(width: 84, height: 84)
            .glassEffect(.regular, in: .circle)
            .accessibilityIdentifier("videoLoading")
    }

    private var errorCard: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 28))
                .foregroundStyle(.yellow)
            Text("Can't play \(item.name ?? "this video")")
                .font(.headline)
                .multilineTextAlignment(.center)
            Text(playback.failed ?? "")
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.75))
                .multilineTextAlignment(.center)
            HStack(spacing: 12) {
                Button("Close") { close() }
                    .buttonStyle(.glass)
                Button("Try again") { playback.retry() }
                    .buttonStyle(.glassProminent)
                    .accessibilityIdentifier("videoRetry")
            }
        }
        .foregroundStyle(.white)
        .padding(24)
        .frame(maxWidth: 320)
        .glassEffect(.regular, in: .rect(cornerRadius: 28))
        .accessibilityIdentifier("videoError")
    }

    @ViewBuilder
    private var flashBubble: some View {
        if flash != 0 {
            HStack {
                if flash > 0 { Spacer() }
                Label("10 s", systemImage: flash < 0 ? "gobackward" : "goforward")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .glassEffect(.regular, in: .capsule)
                    .padding(.horizontal, 36)
                if flash < 0 { Spacer() }
            }
            .allowsHitTesting(false)
            .transition(.opacity)
        }
    }

    private func roundButton(_ symbol: String, label: String, id: String, size: CGFloat = 44, font: CGFloat = 17,
                             action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: font, weight: .semibold))
                .frame(width: size, height: size)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .accessibilityLabel(label)
        .accessibilityIdentifier(id)
    }

    // MARK: actions

    private func tapped() {
        if controls && playback.playing {
            hideTask?.cancel()
            withAnimation(.easeOut(duration: 0.2)) { controls = false }
        } else {
            poke()
        }
    }

    private func doubleTap(_ x: CGFloat, width: CGFloat) {
        let side = VideoMath.side(x, width: width)
        if side == 0 {
            rotate()
            return
        }
        playback.skip(Double(side) * VideoMath.skip)
        withAnimation(.easeOut(duration: 0.15)) { flash = side }
        flashTask?.cancel()
        flashTask = Task {
            try? await Task.sleep(for: .milliseconds(700))
            if !Task.isCancelled { withAnimation(.easeIn(duration: 0.25)) { flash = 0 } }
        }
    }

    /// Show the controls; they fade after a few seconds while the video plays.
    private func poke() {
        withAnimation(.easeOut(duration: 0.2)) { controls = true }
        hideTask?.cancel()
        guard !keepControls else { return }
        hideTask = Task {
            try? await Task.sleep(for: .seconds(VideoMath.hideAfter))
            guard !Task.isCancelled, playback.playing, !playback.scrubbing, playback.failed == nil else { return }
            withAnimation(.easeIn(duration: 0.3)) { controls = false }
        }
    }

    private func rotate() {
        if landscape {
            Orientation.allow(.allButUpsideDown, turnTo: .portrait)
        } else {
            Orientation.allow(.allButUpsideDown, turnTo: .landscapeRight)
        }
        poke()
    }

    private func close() {
        dismiss()
    }

    /// The original file to the share sheet (Save Video, AirDrop, Files...); a PC link is downloaded first.
    private func shareVideo() {
        guard let url = playback.original else { return }
        if url.isFileURL {
            ShareSheet.present([url])
            return
        }
        preparing = true
        Task {
            defer { preparing = false }
            do {
                let (tmp, response) = try await URLSession.shared.download(from: url)
                if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                    throw URLError(.badServerResponse)
                }
                let name = (item.name?.isEmpty == false ? item.name! : "video.mp4")
                let dir = FileManager.default.temporaryDirectory.appendingPathComponent("shared-video", isDirectory: true)
                try? FileManager.default.removeItem(at: dir)
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                let dest = dir.appendingPathComponent((name as NSString).lastPathComponent)
                try FileManager.default.moveItem(at: tmp, to: dest)
                ShareSheet.present([dest])
            } catch {
                shareError = error.localizedDescription
            }
        }
    }
}

private struct PlayerSurface: UIViewRepresentable {
    let view: PlayerLayerView

    func makeUIView(context: Context) -> PlayerLayerView { view }
    func updateUIView(_ v: PlayerLayerView, context: Context) {}
}

private struct AirPlayButton: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let v = AVRoutePickerView()
        v.tintColor = .white
        v.activeTintColor = UIColor(Theme.blue)
        v.prioritizesVideoDevices = true
        return v
    }

    func updateUIView(_ v: AVRoutePickerView, context: Context) {}
}

/// The position bar: played, loaded and the rest; drag anywhere on it to scrub.
private struct Scrubber: View {
    let playback: VideoPlayback
    let poke: () -> Void
    @State private var dragging = false

    var body: some View {
        GeometryReader { geo in
            let w = max(1, geo.size.width)
            let d = max(playback.duration, 0.001)
            let played = CGFloat(min(1, playback.time / d)) * w
            let loaded = CGFloat(min(1, max(playback.loadedTo, playback.time) / d)) * w
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.22)).frame(height: dragging ? 8 : 5)
                Capsule().fill(.white.opacity(0.45)).frame(width: loaded, height: dragging ? 8 : 5)
                Capsule().fill(.white).frame(width: played, height: dragging ? 8 : 5)
                Circle()
                    .fill(.white)
                    .frame(width: dragging ? 22 : 14, height: dragging ? 22 : 14)
                    .shadow(color: .black.opacity(0.3), radius: 2)
                    .offset(x: played - (dragging ? 11 : 7))
                if dragging {
                    Text(VideoMath.clock(playback.time))
                        .font(.footnote.monospacedDigit().weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .glassEffect(.regular, in: .capsule)
                        .fixedSize()
                        .offset(x: min(max(0, played - 28), w - 56), y: -34)
                }
            }
            .frame(height: geo.size.height)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { v in
                        if !dragging {
                            withAnimation(.easeOut(duration: 0.12)) { dragging = true }
                            playback.scrubbing = true
                        }
                        playback.seek(to: Double(v.location.x / w) * playback.duration, exact: false)
                        poke()
                    }
                    .onEnded { v in
                        playback.seek(to: Double(v.location.x / w) * playback.duration, exact: true)
                        playback.scrubbing = false
                        withAnimation(.easeOut(duration: 0.12)) { dragging = false }
                        poke()
                    }
            )
        }
        .frame(height: 30)
        .accessibilityElement()
        .accessibilityLabel("Position")
        .accessibilityValue("\(VideoMath.clock(playback.time)) of \(VideoMath.clock(playback.duration))")
        .accessibilityAdjustableAction { dir in
            switch dir {
            case .increment: playback.skip(VideoMath.skip)
            case .decrement: playback.skip(-VideoMath.skip)
            @unknown default: break
            }
        }
        .accessibilityIdentifier("scrubber")
    }
}
