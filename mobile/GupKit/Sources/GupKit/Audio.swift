import Foundation

// a157: the plain parts of the chat's audio player (ios/Sources/AudioPlayer.swift draws it). The PC sends an audio
// file's length and 96 loudness values 0-100 (mods/gupworks-images/bin/audio-poster); the card draws as many bars as
// fit its width and seeks where it's touched.

enum AudioMath {
    /// the same speeds as the video player (VideoMath.speeds); the last one picked is shared (VideoSpeed)
    static let speeds: [Float] = [0.5, 0.75, 1, 1.25, 1.5, 2]
    /// a silent part still shows as a short bar, so the waveform reads as one line
    static let floor = 0.12
    /// one bar and its gap, in points
    static let pitch: Double = 4
    static let minBars = 12
    static let maxBars = 96

    /// `count` bar heights 0...1: each bar the loudest value of its slice of `peaks` (stretched when there are fewer
    /// peaks than bars); never below `floor`.
    static func bars(_ peaks: [Int]?, count: Int) -> [Double] {
        guard count > 0 else { return [] }
        let p = (peaks ?? []).map { Double(min(100, max(0, $0))) / 100 }
        guard !p.isEmpty else { return Array(repeating: floor, count: count) }
        return (0..<count).map { i in
            let a = i * p.count / count
            let b = max(a + 1, (i + 1) * p.count / count)
            let v = p[a..<min(b, p.count)].max() ?? 0
            return max(floor, v)
        }
    }

    static func barCount(width: Double) -> Int {
        guard width.isFinite, width > 0 else { return minBars }
        return min(maxBars, max(minBars, Int(width / pitch)))
    }

    /// how far along 0...1
    static func progress(time: Double, duration: Double) -> Double {
        guard time.isFinite, duration.isFinite, duration > 0 else { return 0 }
        return min(1, max(0, time / duration))
    }

    /// the time a touch at `x` on a waveform `width` wide points at
    static func seek(x: Double, width: Double, duration: Double) -> Double {
        guard width > 0, duration.isFinite, duration > 0, x.isFinite else { return 0 }
        return min(1, max(0, x / width)) * duration
    }

    /// "0:08" at rest at the start; "0:03 / 0:08" once it plays or has a place
    static func timeLabel(time: Double, duration: Double, playing: Bool) -> String {
        let d = Format.clock((duration.isFinite ? duration : 0) * 1000)
        guard playing || (time.isFinite && time >= 0.5) else { return d }
        return Format.clock((time.isFinite ? time : 0) * 1000) + " / " + d
    }

    /// 1×, 1.5×, 0.75×
    static func speedLabel(_ rate: Float) -> String {
        var t = String(format: "%.2f", rate)
        while t.hasSuffix("0") { t.removeLast() }
        if t.hasSuffix(".") { t.removeLast() }
        return t + "×"
    }
}

/// The demo's chat with a voice memo you sent and Claude's audio reply (tools/gw3_phone_demo.py `voice`).
enum AudioDemo {
    static let chat = "00000019-1111-4222-8333-000000000019"
}
