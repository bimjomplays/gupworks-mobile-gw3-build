import AVFoundation
import XCTest

final class ChimeProbeTests: XCTestCase {
    func testChimeProbe() throws {
        let env = ProcessInfo.processInfo.environment
        var roots = ["", env["SIMULATOR_ROOT"] ?? ""]
        roots = Array(Set(roots))
        var out = "SIMROOT=\(env["SIMULATOR_ROOT"] ?? "nil")\n"
        for root in roots {
            for name in ["begin_record", "end_record"] {
                let p = root + "/System/Library/Audio/UISounds/\(name).caf"
                if let f = try? AVAudioFile(forReading: p.isEmpty ? URL(fileURLWithPath: "/nonexistent") : URL(fileURLWithPath: p)) {
                    out += "\(p): \(Double(f.length) / f.processingFormat.sampleRate)s \(f.processingFormat)\n"
                    let buf = AVAudioPCMBuffer(pcmFormat: f.processingFormat, frameCapacity: AVAudioFrameCount(f.length))!
                    try? f.read(into: buf)
                    if let ch = buf.floatChannelData?[0] {
                        let sr = f.processingFormat.sampleRate
                        var lastLoud = 0
                        var peak: Float = 0
                        for i in 0..<Int(buf.frameLength) { peak = max(peak, abs(ch[i])) }
                        for i in 0..<Int(buf.frameLength) where abs(ch[i]) > peak * 0.05 { lastLoud = i }
                        out += "  peak \(peak), last >5%: \(Double(lastLoud) / sr)s\n"
                        for ms in stride(from: 0, to: Int(Double(buf.frameLength) / sr * 1000), by: 50) {
                            let a = Int(Double(ms) / 1000 * sr), b = min(Int(buf.frameLength), a + Int(0.05 * sr))
                            var m: Float = 0
                            for i in a..<b { m = max(m, abs(ch[i])) }
                            out += "  \(ms)ms:\(String(format: "%.2f", m / max(peak, 0.0001))) "
                        }
                        out += "\n"
                    }
                } else { out += "\(p): none\n" }
            }
        }
        if let l = try? FileManager.default.contentsOfDirectory(atPath: (env["SIMULATOR_ROOT"] ?? "") + "/System/Library/Audio/UISounds") {
            out += "UISounds: " + l.sorted().joined(separator: ",") + "\n"
        }
        XCTFail("PROBE\n" + out)
    }
}
