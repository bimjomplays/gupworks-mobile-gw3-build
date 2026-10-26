import Foundation

// D8's plain parts (Voice.swift has the recorder): what a press on the mic key does, the meter and clock maths, and
// where a transcript came from.

/// What the composer's mic key does with a press and its release, as the desktop's mic (Voice::Mic): a quick tap
/// starts a recording that stays on; a hold is push-to-talk, and letting go puts the words in the box. While
/// recording the key is ↑, and a tap on it sends.
struct MicPress {
    static let hold: TimeInterval = 0.3  // the desktop's kHoldMs

    enum Action: Equatable {
        case start      // begin recording
        case keep       // a tap: the recording goes on
        case insert     // push-to-talk let go: stop, words into the box
        case send       // ↑ while recording
        case nothing
    }

    private var downAt: Date?
    private var startedHere = false

    var isDown: Bool { downAt != nil }

    /// a finger came down (a drag gesture reports this over and over: only the first counts)
    mutating func down(at t: Date, recording: Bool) -> Action {
        guard downAt == nil else { return .nothing }
        downAt = t
        startedHere = !recording
        return recording ? .nothing : .start
    }

    mutating func up(at t: Date, recording: Bool) -> Action {
        // a quick tap can end before its touch-down was reported: it's still a tap
        guard let d = downAt else { return recording ? .send : .start }
        downAt = nil
        if !startedHere { return recording ? .send : .nothing }
        guard recording else { return .nothing }  // it never started (no permission, say)
        return t.timeIntervalSince(d) > Self.hold ? .insert : .keep
    }
}

enum VoiceMath {
    /// a meter reading (dBFS) as a bar height 0…1: -55 dB (room hiss) … -10 dB (loud speech), as the desktop
    static func level(db: Float) -> Float {
        guard db.isFinite else { return 0 }
        return min(1, max(0, (db + 55) / 45))
    }

    /// "0:04", "1:30", as the desktop's Voice::clock
    static func clock(_ seconds: TimeInterval) -> String {
        let s = max(0, Int(seconds))
        return "\(s / 60):" + String(format: "%02d", s % 60)
    }

    /// the words said, after what's already in the box
    static func merge(_ draft: String, _ said: String) -> String {
        let said = said.trimmingCharacters(in: .whitespacesAndNewlines)
        let draft = draft.trimmingCharacters(in: .whitespaces)
        if said.isEmpty { return draft }
        if draft.isEmpty { return said }
        return draft.hasSuffix("\n") ? draft + said : draft + " " + said
    }

    /// why the PC didn't turn a recording into text (the note under the box says the iPhone did)
    static func why(_ error: Error) -> String {
        switch error as? APIError {
        case .server(let text): return "the PC said: \(text)"
        case .notPaired: return "your PC doesn't know this phone anymore"
        default: return "your PC couldn't be reached"
        }
    }

    /// The PC transcribes when it answered the quick hello and knows /v1/voice (gw3-phone 0.5 or newer).
    static func usePC(_ hello: Hello?) -> Bool {
        hello?.features.contains("voice") == true
    }
}

/// The text of a recording and where it was made.
struct Transcript: Equatable {
    enum Source: Equatable { case pc, phone }
    var text: String
    var source: Source
    /// why the PC didn't do it (shown under the box when the iPhone did)
    var why: String?
}
