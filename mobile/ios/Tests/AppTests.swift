import UIKit
import XCTest
@testable import GupWorks3

// UIKit and SwiftUI checks; the plain logic's tests are in mobile/GupKit/Tests (they run here too).

/// Logic that lives on SwiftUI views (cards, sheets, the usage card), and App Transport Security.
final class ViewLogicTests: XCTestCase {
    private func ip(_ parts: Int...) -> String { parts.map(String.init).joined(separator: ".") }

    func testCardStatsGiveTimeToTheDiff() {
        var b = Block(type: "card")
        b.stats = "2 steps · 4.4s"
        XCTAssertEqual(StepCard.stats(b), "2 steps · 4.4s")
        b.add = 6
        b.del = 2
        XCTAssertEqual(StepCard.stats(b), "2 steps")
        b.stats = "3 steps · 1 failed · 2.4s"
        b.add = nil
        b.del = nil
        XCTAssertEqual(StepCard.stats(b), "3 steps · 1 failed · 2.4s")
    }

    func testSwatchBeforeHexColours() {
        let a = Inline.text("from #b8572a to `x`")
        XCTAssertEqual(String(a.characters), "from \u{25A0}\u{2009}#b8572a to x")
    }

    func testMessageTextForCopy() {
        let md = [MD(t: "p", text: "Fixed it."),
                  MD(t: "list", items: [MDItem(level: 0, text: "one", n: 1), MDItem(level: 1, text: "two")]),
                  MD(t: "code", lang: "sh", code: "ls")]
        XCTAssertEqual(MessageActions.plain(md), "Fixed it.\n\n1. one\n  - two\n\nls")
        XCTAssertEqual(MessageActions.quote("a\nb"), "a b")
        XCTAssertEqual(MessageActions.quote(String(repeating: "x", count: 100)).count, 80)
    }

    /// App Transport Security lets the app's plain HTTP reach a tailnet address (the ATS exception for Tailscale's
    /// range in project.yml), and still blocks it for any other address. Nothing listens there on the CI runner, so
    /// an allowed request fails to connect or times out, while a blocked one fails at once with -1022.
    func testPlainHTTPIsAllowedOnlyToTailnetAddresses() async {
        let s = URLSession(configuration: .ephemeral)
        func code(_ host: String) async -> Int? {
            var r = URLRequest(url: URL(string: "http://\(host):9/v1/health")!)
            r.timeoutInterval = 3
            do { _ = try await s.data(for: r); return nil } catch { return (error as? URLError)?.code.rawValue }
        }
        let blocked = URLError.Code.appTransportSecurityRequiresSecureConnection.rawValue
        let tailnet = await code(ip(100, 64, 0, 1))
        XCTAssertNotEqual(tailnet, blocked, "ATS blocks plain HTTP to a tailnet address")
        let elsewhere = await code(ip(192, 0, 2, 1))  // TEST-NET-1: the control, so this test can tell ATS is on
        XCTAssertEqual(elsewhere, blocked, "ATS let plain HTTP through to a non-tailnet address")
    }

    func testModelSheetWords() {
        func m(_ id: String, note: String? = nil) -> ModelInfo {
            ModelInfo(id: id, label: id, provider: "Claude", note: note, efforts: [])
        }
        XCTAssertEqual(ModelEffortSheet.blurb(m("claude-opus-5-5")), "everyday, strong")
        XCTAssertEqual(ModelEffortSheet.blurb(m("claude-haiku-5-5")), "quickest, cheapest")
        XCTAssertNil(ModelEffortSheet.blurb(m("gpt-6-sol", note: "subscription")))
        XCTAssertEqual(ModelEffortSheet.blurb(m("local-qwen", note: "runs on the GPU")), "runs on the GPU")
        XCTAssertEqual(ModelEffortSheet.providerName("local"), "On your PC")
        XCTAssertEqual(Icons.needle("low"), -90)
        XCTAssertEqual(Icons.needle("high"), 0)
        XCTAssertEqual(Icons.needle("max"), 90)
    }

    func testUsageCardRows() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let now = Date(timeIntervalSince1970: 1_792_000_000)  // Wed Oct 14 2026, 17:46:40 UTC
        let iso = ISO8601DateFormatter()
        let usage = [Meter(label: "ctx", percent: 34, tokens: 68_000, switchAt: 200_000),
                     Meter(label: "5h", percent: 18, resets: iso.string(from: now.addingTimeInterval(3 * 3600 + 12 * 60 + 30))),
                     Meter(label: "wk", percent: 41, resets: iso.string(from: now.addingTimeInterval(3 * 86_400 - 6 * 60 - 40)))]
        let rows = UsageCard.rows(usage, now: now, calendar: cal)
        XCTAssertEqual(rows.map(\.label), ["ctx", "5h", "wk"])
        XCTAssertEqual(rows.map(\.percent), [34, 18, 41])
        XCTAssertEqual(rows[0].detail, "68K of 200K tokens")
        XCTAssertEqual(rows[1].detail, "resets in 3h 12m")
        XCTAssertEqual(rows[2].detail, "resets Sat 17:40")

        let fresh = UsageCard.rows([], now: now, calendar: cal)
        XCTAssertEqual(fresh[0].detail, "A new chat starts empty")
        XCTAssertEqual(fresh[0].percent, 0)
        XCTAssertEqual(fresh[1].detail, "Not known yet")
        XCTAssertNil(fresh[2].percent)
        let past = UsageCard.rows([Meter(label: "5h", percent: 99, resets: iso.string(from: now.addingTimeInterval(-60)))],
                                  now: now, calendar: cal)
        XCTAssertEqual(past[1].detail, "Reset")
    }
}

/// Photos sent from the phone go small and JPEG.
final class PhotoAttachmentTests: XCTestCase {
    func testPhotosGoSmallAndJPEG() throws {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let big = UIGraphicsImageRenderer(size: CGSize(width: 4000, height: 3000), format: format).image { c in
            UIColor.orange.setFill()
            c.fill(CGRect(x: 0, y: 0, width: 4000, height: 3000))
        }
        let a = try XCTUnwrap(Attachment.photo(big, name: "photo.jpg"))
        XCTAssertEqual(a.type, "image/jpeg")
        let back = try XCTUnwrap(UIImage(data: a.data))
        XCTAssertEqual(back.size.width * back.scale, 2048)
        XCTAssertEqual(back.size.height * back.scale, 1536)
        XCTAssertTrue(Attachment.readableImage("JPG"))
        XCTAssertFalse(Attachment.readableImage("heic"))
    }
}

/// Your photos in a message never get wider than the room they're given (a row of six once widened the whole chat).
final class PhotoGridTests: XCTestCase {
    private func width(_ s: PhotoGrid.Shape, spacing: CGFloat = 6) -> CGFloat {
        CGFloat(s.columns) * s.side + CGFloat(max(s.columns - 1, 0)) * spacing
    }

    func testFitsEveryCountOnEveryPhone() {
        // the bubble's room on a 375, 393 and 440 pt wide iPhone (screen - 2 × 18 - 60), and something narrow
        for room in [279.0, 297.0, 344.0, 120.0, 40.0] as [CGFloat] {
            for n in 1...24 {
                let s = PhotoGrid.shape(count: n, width: room)
                XCTAssertLessThanOrEqual(width(s), room, "\(n) photos in \(room) pt")
                XCTAssertEqual(s.rows, (n + s.columns - 1) / s.columns)
                XCTAssertGreaterThanOrEqual(s.columns * s.rows, n)
                XCTAssertGreaterThan(s.side, 0)
            }
        }
    }

    func testShapes() {
        XCTAssertEqual(PhotoGrid.shape(count: 1, width: 297), .init(columns: 1, rows: 1, side: 96))
        XCTAssertEqual(PhotoGrid.shape(count: 3, width: 297), .init(columns: 3, rows: 1, side: 95))
        XCTAssertEqual(PhotoGrid.shape(count: 6, width: 297), .init(columns: 3, rows: 2, side: 95))
        XCTAssertEqual(PhotoGrid.shape(count: 12, width: 297), .init(columns: 4, rows: 3, side: 69))
        XCTAssertEqual(PhotoGrid.shape(count: 2, width: 344), .init(columns: 2, rows: 1, side: 96))
        XCTAssertEqual(PhotoGrid.shape(count: 4, width: 297), .init(columns: 2, rows: 2, side: 96))
        XCTAssertEqual(PhotoGrid.shape(count: 9, width: 297), .init(columns: 3, rows: 3, side: 95))
        XCTAssertEqual(PhotoGrid.shape(count: 0, width: 297).columns, 0)
        // asked how wide it likes to be: three 96 pt tiles, never one long row
        XCTAssertEqual(PhotoGrid.shape(count: 6, width: nil), .init(columns: 3, rows: 2, side: 96))
        XCTAssertEqual(PhotoGrid.shape(count: 6, width: .infinity), .init(columns: 3, rows: 2, side: 96))
    }
}
