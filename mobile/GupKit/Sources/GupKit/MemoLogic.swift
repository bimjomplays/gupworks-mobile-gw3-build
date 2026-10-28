import Foundation

/// A voice memo in the composer (a161): the + menu's "Voice memo" records his voice into an m4a that goes out as
/// an audio file (played in his bubble), apart from the mic key that turns speech into text.
struct MemoFlow: Equatable {
    enum Phase: Equatable { case idle, recording, preview }
    private(set) var phase: Phase = .idle

    /// start recording; from a preview it is a re-record (the old memo is dropped)
    @discardableResult
    mutating func start() -> Bool {
        guard phase != .recording else { return false }
        phase = .recording
        return true
    }

    /// stop recording: a preview to play and send, or nothing when it was too short to be a memo
    mutating func stop(seconds: Double) {
        guard phase == .recording else { return }
        phase = seconds >= MemoMath.minSeconds ? .preview : .idle
    }

    /// ✕ while recording, Delete on the preview, or the memo went out with a message
    mutating func reset() { phase = .idle }

    var recording: Bool { phase == .recording }
    var hasMemo: Bool { phase == .preview }
}

enum MemoMath {
    /// shorter than this is a slip of the finger, not a memo
    static let minSeconds = 0.5
    /// a memo stops by itself at 30 minutes (about 14 MB at 64 kbps, under the 30 MB upload limit)
    static let maxSeconds: Double = 30 * 60
    static let type = "audio/mp4"
    /// how many loudness values the player's waveform gets, as the PC's audio cards
    static let peakCount = 96

    /// `count` loudness values 0-100 across the memo, each the loudest meter level (0-1) its slice covers
    static func peaks(_ levels: [Float], count: Int = peakCount) -> [Int] {
        guard !levels.isEmpty, count > 0 else { return [] }
        return (0..<count).map { i in
            let from = i * levels.count / count
            let to = max(from + 1, (i + 1) * levels.count / count)
            let top = levels[from..<min(to, levels.count)].max() ?? 0
            return Int((min(max(top, 0), 1) * 100).rounded())
        }
    }

    /// "voice-memo-2026-10-28-143005.m4a": no spaces, so the PC's path for it goes into the prompt as it is
    static func fileName(_ date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        func two(_ n: Int?) -> String { String(format: "%02d", n ?? 0) }
        return "voice-memo-\(c.year ?? 0)-\(two(c.month))-\(two(c.day))-\(two(c.hour))\(two(c.minute))\(two(c.second)).m4a"
    }

    /// an attachment that is a sound (a voice memo or an audio file from Files)
    static func isAudio(type: String, name: String) -> Bool {
        if type.hasPrefix("audio/") { return true }
        let ext = (name as NSString).pathExtension.lowercased()
        return ["m4a", "mp3", "wav", "aac", "ogg", "opus", "flac", "caf"].contains(ext)
    }
}
