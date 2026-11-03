import AVFoundation
import Foundation

// a194: the start of a recording holds the quick start's chime (StartChime in GupKit); this cuts it off.

enum AudioTrim {
    /// a copy of the m4a without its first `seconds` (no re-encoding), or nil when that wasn't possible: the caller
    /// then keeps the whole file
    static func dropHead(_ url: URL, seconds: TimeInterval) async -> URL? {
        guard seconds > 0 else { return nil }
        let asset = AVURLAsset(url: url)
        guard let total = try? await asset.load(.duration), total.seconds > seconds,
              let export = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetPassthrough) else { return nil }
        let out = url.deletingLastPathComponent().appendingPathComponent("trim-\(UUID().uuidString).m4a")
        export.timeRange = CMTimeRange(start: CMTime(seconds: seconds, preferredTimescale: 600), end: total)
        do {
            try await export.export(to: out, as: .m4a)
            return out
        } catch {
            try? FileManager.default.removeItem(at: out)
            return nil
        }
    }
}
