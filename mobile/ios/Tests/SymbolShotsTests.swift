import UIKit
import XCTest
@testable import GupWorks3

/// a137: the menu's SF Symbols drawn big with their metrics, so the desktop app's copies in src/Icons.cpp can be
/// traced from the real shapes (tools/sf_symbol_trace.py) instead of by eye. Written to SHOTS_DIR as symbol-*. (A PDF
/// gets the symbol only as a picture, not its outline.)
@MainActor
final class SymbolShotsTests: XCTestCase {
    private let names = ["folder", "clock", "bolt", "arrow.up.arrow.down"]

    private func write(_ data: Data, _ file: String) {
        let a = XCTAttachment(data: data, uniformTypeIdentifier: file.hasSuffix(".png") ? "public.png" : "public.data")
        a.name = file
        a.lifetime = .keepAlways
        add(a)
        guard let dir = ProcessInfo.processInfo.environment["SHOTS_DIR"], !dir.isEmpty else { return }
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        try? data.write(to: URL(fileURLWithPath: dir).appendingPathComponent(file))
    }

    /// the symbol as the menu draws it (.font(.system(size:)), regular weight), black on white
    private func image(_ name: String, _ size: CGFloat) throws -> UIImage {
        let config = UIImage.SymbolConfiguration(pointSize: size, weight: .regular, scale: .medium)
        let img = try XCTUnwrap(UIImage(systemName: name, withConfiguration: config))
        return img.withTintColor(.black, renderingMode: .alwaysOriginal)
    }

    func testMenuSymbolsBig() throws {
        var info = ""
        for name in names {
            let file = "symbol-" + name.replacingOccurrences(of: ".", with: "-")
            // big: 1000 pt at 1x, the shape to trace
            let big = try image(name, 1000)
            let fmt = UIGraphicsImageRendererFormat()
            fmt.scale = 1
            fmt.opaque = true
            let png = UIGraphicsImageRenderer(size: big.size, format: fmt).pngData { _ in
                UIColor.white.setFill()
                UIRectFill(CGRect(origin: .zero, size: big.size))
                big.draw(at: .zero)
            }
            write(png, file + "-1000pt.png")
            // real size: the menu's 19 pt at the phone's 3x
            let small = try image(name, 19)
            let fmt3 = UIGraphicsImageRendererFormat()
            fmt3.scale = 3
            fmt3.opaque = true
            write(UIGraphicsImageRenderer(size: small.size, format: fmt3).pngData { _ in
                UIColor.white.setFill()
                UIRectFill(CGRect(origin: .zero, size: small.size))
                small.draw(at: .zero)
            }, file + "-19pt@3x.png")
            let font = UIFont.systemFont(ofSize: 1000)
            info += "\(name) 1000pt: size \(big.size) alignmentRectInsets \(big.alignmentRectInsets) "
                + "baselineFromBottom \(big.baselineOffsetFromBottom ?? -1) | 19pt: size \(small.size) "
                + "insets \(small.alignmentRectInsets) | font1000 capHeight \(font.capHeight) ascender \(font.ascender) "
                + "descender \(font.descender) xHeight \(font.xHeight)\n"
        }
        print("SYMBOLS\n" + info)
        write(Data(info.utf8), "symbol-metrics.txt")
    }
}
