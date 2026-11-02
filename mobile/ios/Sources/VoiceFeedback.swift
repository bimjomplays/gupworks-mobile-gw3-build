import AudioToolbox
import Foundation
import UIKit

// a193: the haptic and chime around the mic key and the Voice memo (VoiceCue in GupKit says which). The start cue is
// played before the microphone starts and the recording waits for the chime to end, so the transcription never hears
// it (and iOS mutes haptics once the microphone is on). System sounds follow the ringer and silent switch.

@MainActor
enum VoiceFeedback {
    private static let impact = UIImpactFeedbackGenerator(style: .medium)
    private static let notice = UINotificationFeedbackGenerator()

    /// warms the haptic engine (the finger just touched the key), so the tap has no lag
    static func prepare() {
        impact.prepare()
        notice.prepare()
    }

    /// the cue's haptic and chime; with `wait`, returns once the chime has played (or after a short cap)
    static func play(_ cue: VoiceCue, wait: Bool = false) async {
        switch cue.haptic {
        case .impact: impact.impactOccurred()
        case .error: notice.notificationOccurred(.error)
        }
        guard let sound = cue.systemSound else { return }
        if wait {
            await chime(sound)
        } else {
            AudioServicesPlaySystemSound(sound)
        }
    }

    private static func chime(_ sound: UInt32) async {
        let once = Once()
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            once.set { c.resume() }
            AudioServicesPlaySystemSoundWithCompletion(sound) { once.fire() }
            Task {
                try? await Task.sleep(for: .seconds(VoiceCue.startChimeWait))
                once.fire()
            }
        }
    }

    /// runs its action the first time `fire` is called, from whichever thread
    private final class Once: @unchecked Sendable {
        private let lock = NSLock()
        private var action: (() -> Void)?
        private var fired = false

        func set(_ a: @escaping () -> Void) {
            lock.lock(); defer { lock.unlock() }
            action = a
        }

        func fire() {
            lock.lock()
            let a = fired ? nil : action
            fired = true
            lock.unlock()
            a?()
        }
    }
}
