import AudioToolbox
import AVFoundation
import Foundation
import UIKit

// a193: the haptic and chime around the mic key and the Voice memo (VoiceCue in GupKit says which). System sounds
// follow the ringer and silent switch.
// a194: the start doesn't wait for the chime. The haptic fires (iOS mutes haptics once the microphone is on), the
// microphone starts at once and the chime plays as it starts. The microphone hears the chime, so the recording's first
// moments are cut off before it is transcribed or kept as a memo (StartChime in GupKit, AudioTrim).

@MainActor
enum VoiceFeedback {
    private static let impact = UIImpactFeedbackGenerator(style: .medium)
    private static let notice = UINotificationFeedbackGenerator()

    /// warms the haptic engine (the finger just touched the key), so the tap has no lag
    static func prepare() {
        impact.prepare()
        notice.prepare()
    }

    /// the cue's haptic and chime
    static func play(_ cue: VoiceCue) async {
        switch cue.haptic {
        case .impact: impact.impactOccurred()
        case .error: notice.notificationOccurred(.error)
        }
        if let sound = cue.systemSound { AudioServicesPlaySystemSound(sound) }
    }

    /// the start haptic alone, before the microphone is on
    static func tap() { impact.impactOccurred() }

    /// the start chime, once the microphone is recording
    static func playStartChime() {
        if let sound = VoiceCue.start.systemSound { AudioServicesPlaySystemSound(sound) }
    }

    /// The recording session. Haptics and system sounds stay on while it records, or iOS would mute the start chime
    /// (and the stop haptic) as the microphone starts.
    static func openRecordingSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetoothHFP])
        try? session.setAllowHapticsAndSystemSoundsDuringRecording(true)
        try session.setActive(true)
    }
}
