import AudioToolbox
import AVFoundation
import Foundation
import UIKit

// a193: the haptic and chime around the mic key and the Voice memo (VoiceCue in GupKit says which). System sounds
// follow the ringer and silent switch.
// a194: the start doesn't wait for the chime. The haptic fires (iOS mutes haptics once the microphone is on), the
// microphone starts at once and the chime plays as it starts. The microphone hears the chime, and it is left in the
// recording: cutting the first moments off would cut off a first word spoken at once (push-to-talk). begin_record.caf
// is 0.45 s but all its sound is in the first ~0.2 s (peak 13% of full scale); tested with the PC's whisper-cli, a
// sentence starting during the chime comes out whole even with the chime 8 times louder than the file, and the chime
// at its own level with no speech gives no text.

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
