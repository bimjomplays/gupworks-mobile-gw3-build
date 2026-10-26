import AVFoundation
import Foundation
import Observation
import Speech

// D8: talking to a chat. The phone records AAC (16 kHz mono) while a meter drives the waveform; the PC turns it into
// text with the desktop's whisper (POST /v1/voice). When the PC can't be reached (or can't transcribe), the iPhone
// does it itself with Apple's on-device SpeechAnalyzer. The recording is removed from the phone once it's text.

/// The recorder in the composer: idle → recording → transcribing → idle.
@Observable
@MainActor
final class VoiceController {
    enum Phase: Equatable { case idle, recording, transcribing }

    static let barEvery: TimeInterval = 0.15  // one waveform bar per this much audio
    static let maxSeconds: TimeInterval = 600  // a forgotten recording stops itself, as on the desktop

    private(set) var phase: Phase = .idle
    /// bar heights 0…1, oldest first
    private(set) var levels: [Float] = []
    private(set) var elapsed: TimeInterval = 0
    /// transcribing on the iPhone (the PC couldn't be reached)
    private(set) var onPhone = false
    /// a short line under the box: nothing heard, transcribed on the iPhone, no microphone…
    var note: String?
    /// a press on the mic key (tap / hold), kept here so the key's gesture survives the composer redrawing
    var press = MicPress()
    /// bumps when a recording reached the 10-minute limit: the composer puts its words in the box
    private(set) var limitTick = 0

    private let pairing: Pairing?
    private let demo: Bool
    private let api = APIClient()
    private var recorder: AVAudioRecorder?
    private var file: URL?
    private var started = Date()
    private var meterTask: Task<Void, Never>?
    private var job: Task<Transcript?, Never>?
    /// the PC's quick hello, asked while recording so the answer is there when it stops
    private var pcCheck: Task<Hello?, Never>?
    private var noteTask: Task<Void, Never>?
    private var finishing = false
    private var peak: Float = 0
    private var lastBar: TimeInterval = 0
    private static var preparedPhone = false

    init(pairing: Pairing?, demo: Bool) {
        self.pairing = pairing
        self.demo = demo
    }

    /// the demo's PC answers unless the app was started with -voice-offline (the screenshot of the fallback)
    private var demoOffline: Bool { Demo.args.contains("-voice-offline") }

    func start() async {
        guard phase == .idle else { return }
        note = nil
        levels = []
        elapsed = 0
        peak = 0
        lastBar = 0
        onPhone = false
        if demo {
            begin()
            return
        }
        // the system asks once; a "no" is remembered and only Settings changes it
        guard await AVAudioApplication.requestRecordPermission() else {
            show("GupWorks can't use the microphone. Allow it in Settings › GupWorks.")
            return
        }
        guard phase == .idle else { return }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetoothHFP])
            try session.setActive(true)
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("voice-\(UUID().uuidString).m4a")
            let settings: [String: Any] = [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: 16_000.0,
                AVNumberOfChannelsKey: 1,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
            ]
            let r = try AVAudioRecorder(url: url, settings: settings)
            r.isMeteringEnabled = true
            guard r.prepareToRecord(), r.record() else {
                try? FileManager.default.removeItem(at: url)
                endSession()
                show("The microphone didn't start.")
                return
            }
            recorder = r
            file = url
        } catch {
            endSession()
            show("The microphone didn't start: \(error.localizedDescription)")
            return
        }
        if let p = pairing {
            let api = self.api
            pcCheck = Task { try? await api.quickHello(p) }
        }
        if !Self.preparedPhone {  // the fallback's model, fetched while there's a connection (once per launch)
            Self.preparedPhone = true
            Task.detached(priority: .utility) { await OnDeviceSpeech.prepare() }
        }
        begin()
    }

    private func begin() {
        started = Date()
        phase = .recording
        meterTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, self.phase == .recording else { return }
                self.tick()
                try? await Task.sleep(for: .milliseconds(50))
            }
        }
    }

    private func tick() {
        elapsed = Date().timeIntervalSince(started)
        let level: Float
        if demo {
            // a made-up voice: syllables rising and falling
            let t = elapsed
            level = Float(max(0.08, min(1, 0.45 + 0.35 * sin(t * 9.1) * sin(t * 2.3 + 1) + 0.2 * sin(t * 23))))
        } else if let r = recorder {
            r.updateMeters()
            level = VoiceMath.level(db: r.averagePower(forChannel: 0))
        } else {
            level = 0
        }
        peak = max(peak, level)
        if elapsed - lastBar >= Self.barEvery {
            lastBar = elapsed
            levels.append(peak)
            peak = 0
            if levels.count > 120 { levels.removeFirst(levels.count - 120) }
        }
        if elapsed >= Self.maxSeconds, phase == .recording {
            stopRecording()
            limitTick += 1
        }
    }

    /// Stops and turns the recording into text: the PC first, the iPhone when the PC can't. nil when cancelled.
    func finish() async -> Transcript? {
        guard !finishing else { return nil }  // ■ and ↑ (or a release) together: the words go once
        if phase == .recording { stopRecording() }
        guard phase == .transcribing, let job else { return nil }
        finishing = true
        defer { finishing = false }
        let result = await job.value
        if self.job == job {
            self.job = nil
            phase = .idle
        }
        return result
    }

    /// ■ / ↑ / a push-to-talk release / the 10-minute limit: the recording ends and its transcription starts
    private func stopRecording() {
        guard phase == .recording else { return }
        meterTask?.cancel()
        meterTask = nil
        elapsed = Date().timeIntervalSince(started)
        recorder?.stop()
        recorder = nil
        endSession()
        phase = .transcribing
        let url = file
        file = nil
        let check = pcCheck
        pcCheck = nil
        let seconds = elapsed
        job = Task { [weak self] in
            defer { if let url { try? FileManager.default.removeItem(at: url) } }
            guard let self else { return nil }
            return await self.transcribe(url, seconds: seconds, check: check)
        }
    }

    private func transcribe(_ url: URL?, seconds: TimeInterval, check: Task<Hello?, Never>?) async -> Transcript? {
        if demo { return await demoTranscript() }
        guard let url else { return nil }
        if seconds < 0.25 { return Transcript(text: "", source: .pc) }  // nothing to hear, as on the desktop
        let hello = await check?.value
        var why = "your PC couldn't be reached"
        if let p = pairing, VoiceMath.usePC(hello) {
            do {
                let data = try Data(contentsOf: url)
                let reply = try await api.voice(p, data)
                if Task.isCancelled { return nil }
                return Transcript(text: reply.text, source: .pc)
            } catch {
                if Task.isCancelled { return nil }
                why = VoiceMath.why(error)
            }
        } else if hello != nil {
            why = "the PC's GupWorks is older (update it there)"
        }
        onPhone = true
        do {
            let text = try await OnDeviceSpeech.transcribe(url)
            if Task.isCancelled { return nil }
            return Transcript(text: text, source: .phone, why: why)
        } catch {
            if Task.isCancelled { return nil }
            show("Couldn't turn that into text: \(why), and this iPhone couldn't either (\(OnDeviceSpeech.describe(error))).")
            return nil
        }
    }

    private func demoTranscript() async -> Transcript? {
        if demoOffline { onPhone = true }
        try? await Task.sleep(for: .milliseconds(demoOffline ? 1500 : 700))
        if Task.isCancelled { return nil }
        let text = "Also let a swipe down close the lightbox on phones."
        return demoOffline ? Transcript(text: text, source: .phone, why: "your PC couldn't be reached")
                           : Transcript(text: text, source: .pc)
    }

    /// ×: nothing is kept or sent
    func cancel() {
        meterTask?.cancel()
        meterTask = nil
        job?.cancel()
        job = nil
        pcCheck?.cancel()
        pcCheck = nil
        if let r = recorder {
            r.stop()
            r.deleteRecording()
        }
        recorder = nil
        if let url = file { try? FileManager.default.removeItem(at: url) }
        file = nil
        endSession()
        phase = .idle
        onPhone = false
        press = MicPress()
    }

    private func endSession() {
        if demo { return }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    /// a note under the box for a few seconds
    func show(_ text: String, seconds: Double = 6) {
        note = text
        noteTask?.cancel()
        noteTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            if !Task.isCancelled, self?.note == text { self?.note = nil }
        }
    }
}

/// Apple's on-device speech to text (iOS 26 SpeechAnalyzer): SpeechTranscriber where the iPhone has it, else
/// DictationTranscriber (older iPhones). The model is downloaded once while online and then works in Airplane Mode.
enum OnDeviceSpeech {
    enum Failure: Error {
        case notInstalled
    }

    /// the desktop's language (whisper -l en) unless the iPhone's own is supported
    static func language() async -> Locale {
        if let l = await SpeechTranscriber.supportedLocale(equivalentTo: Locale.current),
           l.language.languageCode == Locale.current.language.languageCode {
            return l
        }
        return await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: "en_US")) ?? Locale(identifier: "en_US")
    }

    /// Reserves the language and fetches its model when it's missing (needs a connection; later runs are offline).
    static func prepare() async {
        guard SpeechTranscriber.isAvailable else { return }
        let locale = await language()
        let transcriber = SpeechTranscriber(locale: locale, preset: .transcription)
        _ = try? await AssetInventory.reserve(locale: locale)
        if let request = try? await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            try? await request.downloadAndInstall()
        }
    }

    static func transcribe(_ url: URL) async throws -> String {
        let locale = await language()
        if SpeechTranscriber.isAvailable {
            let transcriber = SpeechTranscriber(locale: locale, preset: .transcription)
            try await install([transcriber], locale: locale)
            let analyzer = SpeechAnalyzer(modules: [transcriber])
            async let words = transcriber.results.reduce(into: AttributedString()) { acc, r in
                if r.isFinal { acc += r.text }
            }
            try await analyze(analyzer, url)
            return text(try await words)
        }
        // iPhones without SpeechTranscriber's model: the dictation one
        let transcriber = DictationTranscriber(locale: locale, preset: .longDictation)
        try await install([transcriber], locale: locale)
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        async let words = transcriber.results.reduce(into: AttributedString()) { acc, r in
            if r.isFinal { acc += r.text }
        }
        try await analyze(analyzer, url)
        return text(try await words)
    }

    /// the whole file through the analyzer; its transcriber's results end once it's finished
    private static func analyze(_ analyzer: SpeechAnalyzer, _ url: URL) async throws {
        do {
            let file = try AVAudioFile(forReading: url)
            if let last = try await analyzer.analyzeSequence(from: file) {
                try await analyzer.finalizeAndFinish(through: last)
            } else {
                await analyzer.cancelAndFinishNow()
            }
        } catch {
            await analyzer.cancelAndFinishNow()
            throw error
        }
    }

    private static func text(_ words: AttributedString) -> String {
        String(words.characters).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func install(_ modules: [any SpeechModule], locale: Locale) async throws {
        _ = try? await AssetInventory.reserve(locale: locale)
        if let request = try await AssetInventory.assetInstallationRequest(supporting: modules) {
            do {
                try await request.downloadAndInstall()
            } catch {
                throw Failure.notInstalled  // offline before the model was ever fetched
            }
        }
        guard await AssetInventory.status(forModules: modules) == .installed else { throw Failure.notInstalled }
    }

    static func describe(_ error: Error) -> String {
        switch error {
        case Failure.notInstalled: return "its speech model isn't downloaded yet; connect to the internet once"
        default: return error.localizedDescription
        }
    }
}
