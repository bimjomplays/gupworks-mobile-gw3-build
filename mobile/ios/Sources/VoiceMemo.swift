import AVFoundation
import Foundation
import Observation
import UIKit

// a161: a voice memo from the composer's + menu. The phone records AAC (44.1 kHz mono, 64 kbps) into an m4a while a
// meter drives the waveform; stop gives a preview to play, re-record or delete, and the memo goes out as an audio file
// that the chat plays in his bubble. Apart from the mic key (Voice.swift), which turns speech into text.

/// The memo recorder: idle → recording → preview → (sent | deleted).
@Observable
@MainActor
final class MemoRecorder {
    private(set) var flow = MemoFlow()
    /// the live waveform's bars 0…1, oldest first (the last 120)
    private(set) var levels: [Float] = []
    private(set) var elapsed: TimeInterval = 0
    /// the memo to preview and send
    private(set) var file: URL?
    private(set) var duration: Double = 0
    private(set) var peaks: [Int] = []
    private(set) var name = ""
    /// the microphone is turned off for GupWorks: the composer offers Settings
    var denied = false
    /// why it didn't record, for the composer's alert
    var problem: String?

    private let demo: Bool
    private var recorder: AVAudioRecorder?
    private var started = Date()
    private var meterTask: Task<Void, Never>?
    private var all: [Float] = []  // every meter level, for the memo's peaks
    private var peak: Float = 0
    private var lastBar: TimeInterval = 0
    private var interruption: NSObjectProtocol?

    init(demo: Bool = Demo.isOn) {
        self.demo = demo
    }

    var recording: Bool { flow.recording }
    var hasMemo: Bool { flow.hasMemo && file != nil }

    /// + › Voice memo, or Re-record on the preview (the old memo goes)
    func start() async {
        guard !flow.recording else { return }
        if !demo {
            // the system asks once; a "no" is remembered and only Settings changes it
            guard await AVAudioApplication.requestRecordPermission() else {
                denied = true
                return
            }
        }
        guard !flow.recording else { return }
        AudioPlayback.shared.pause()
        let old = file
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("memo-\(UUID().uuidString).m4a")
        if !demo {
            do {
                let session = AVAudioSession.sharedInstance()
                try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetoothHFP])
                try session.setActive(true)
                let settings: [String: Any] = [
                    AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                    AVSampleRateKey: 44_100.0,
                    AVNumberOfChannelsKey: 1,
                    AVEncoderBitRateKey: 64_000,
                    AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
                ]
                let r = try AVAudioRecorder(url: url, settings: settings)
                r.isMeteringEnabled = true
                guard r.prepareToRecord(), r.record(forDuration: MemoMath.maxSeconds) else {
                    try? FileManager.default.removeItem(at: url)
                    endSession()
                    problem = "The microphone didn't start."
                    return
                }
                recorder = r
            } catch {
                endSession()
                problem = "The microphone didn't start: \(error.localizedDescription)"
                return
            }
            // a call or Siri takes the microphone: stop there and keep what was recorded
            interruption = NotificationCenter.default.addObserver(
                forName: AVAudioSession.interruptionNotification, object: nil, queue: .main
            ) { [weak self] note in
                let began = (note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt)
                    == AVAudioSession.InterruptionType.began.rawValue
                if began { Task { @MainActor in await self?.stop() } }
            }
        }
        if let old { forget(old) }
        file = url
        name = MemoMath.fileName(Date())
        duration = 0
        peaks = []
        levels = []
        all = []
        elapsed = 0
        peak = 0
        lastBar = 0
        started = Date()
        flow.start()
        meterTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, self.flow.recording else { return }
                await self.tick()
                try? await Task.sleep(for: .milliseconds(50))
            }
        }
    }

    private func tick() async {
        elapsed = Date().timeIntervalSince(started)
        let level: Float
        if demo {
            // a made-up voice: syllables rising and falling
            let t = elapsed
            level = Float(max(0.08, min(1, 0.45 + 0.35 * sin(t * 9.1) * sin(t * 2.3 + 1) + 0.2 * sin(t * 23))))
        } else if let r = recorder {
            if !r.isRecording { return await stop() }  // the 30-minute limit
            r.updateMeters()
            level = VoiceMath.level(db: r.averagePower(forChannel: 0))
        } else {
            level = 0
        }
        all.append(level)
        peak = max(peak, level)
        if elapsed - lastBar >= VoiceController.barEvery {
            lastBar = elapsed
            levels.append(peak)
            peak = 0
            if levels.count > 120 { levels.removeFirst(levels.count - 120) }
        }
    }

    /// ■: the memo is kept for the preview (too short to be one, it's dropped)
    func stop() async {
        guard flow.recording else { return }
        meterTask?.cancel()
        meterTask = nil
        dropObserver()
        elapsed = Date().timeIntervalSince(started)
        recorder?.stop()
        recorder = nil
        endSession()
        guard let url = file else { return reset() }
        if demo {
            // the demo's memo is a short hum from the fixtures, so the preview has something to play
            try? FileManager.default.removeItem(at: url)
            if let hum = Demo.file("hum-idea.m4a", in: "fixtures/media") {
                try? FileManager.default.copyItem(at: hum, to: url)
            }
        }
        var seconds = elapsed
        if let d = try? await AVURLAsset(url: url).load(.duration).seconds, d.isFinite, d > 0 { seconds = d }
        flow.stop(seconds: seconds)
        guard flow.hasMemo, FileManager.default.fileExists(atPath: url.path) else { return reset() }
        duration = seconds
        peaks = MemoMath.peaks(all)
    }

    /// ✕ while recording, or Delete on the preview
    func discard() {
        meterTask?.cancel()
        meterTask = nil
        dropObserver()
        if let r = recorder {
            r.stop()
            r.deleteRecording()
            endSession()
        }
        recorder = nil
        reset()
    }

    /// the memo as an attachment for the message (nil when it can't be read); the preview is cleared once it's sent
    func attachment() -> Attachment? {
        guard hasMemo, let url = file, let data = try? Data(contentsOf: url) else { return nil }
        return Attachment(name: name, type: MemoMath.type, data: data, image: nil, uploaded: nil,
                          duration: duration, peaks: peaks, local: url)
    }

    /// it went out with the message: its file stays for the sending bubble's player (a temporary file)
    func sent() {
        file = nil
        reset()
    }

    private func reset() {
        if let url = file { forget(url) }
        file = nil
        duration = 0
        peaks = []
        levels = []
        all = []
        flow.reset()
    }

    private func forget(_ url: URL) {
        if AudioPlayback.shared.current == url { AudioPlayback.shared.pause() }
        try? FileManager.default.removeItem(at: url)
    }

    private func dropObserver() {
        if let o = interruption { NotificationCenter.default.removeObserver(o) }
        interruption = nil
    }

    private func endSession() {
        if demo { return }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    static func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
    }
}
