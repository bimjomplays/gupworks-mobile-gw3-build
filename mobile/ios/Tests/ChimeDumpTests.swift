import AVFoundation
import XCTest

final class ChimeDumpTests: XCTestCase {
    func testChimeDump() throws {
        let root = ProcessInfo.processInfo.environment["SIMULATOR_ROOT"] ?? ""
        let f = try AVAudioFile(forReading: URL(fileURLWithPath: root + "/System/Library/Audio/UISounds/begin_record.caf"))
        let buf = AVAudioPCMBuffer(pcmFormat: f.processingFormat, frameCapacity: AVAudioFrameCount(f.length))!
        try f.read(into: buf)
        let ch = buf.floatChannelData![0]
        let sr = f.processingFormat.sampleRate
        let n = Int(Double(buf.frameLength) / sr * 16000)
        var data = Data()
        for i in 0..<n {
            let pos = Double(i) / 16000 * sr
            let a = Int(pos), fr = Float(pos - Double(a))
            let b = min(a + 1, Int(buf.frameLength) - 1)
            let v = ch[a] * (1 - fr) + ch[b] * fr
            var s = Int16(max(-32767, min(32767, v * 32767)))
            withUnsafeBytes(of: &s) { data.append(contentsOf: $0) }
        }
        XCTFail("CHIMEB64START\n" + data.base64EncodedString() + "\nCHIMEB64END")
    }
}
