import XCTest
@testable import GupWorks3

/// a124: a table's column widths (TableLayout.widths), from the widest cell's one-line width per column.
@MainActor
final class TableLayoutTests: XCTestCase {
    func testNarrowColumnsKeepTheirWidth() {
        XCTAssertEqual(TableLayout.widths([60, 90.2, 100], fit: 353), [60, 91, 100])
    }

    func testOneLongColumnStopsAtSixtyPercent() {
        let w = TableLayout.widths([60, 900], fit: 353)
        XCTAssertEqual(w[0], 60)
        XCTAssertEqual(w[1], 211)
    }

    func testLongColumnsShareTheChatsWidth() {
        // Step | What | Result with long cells: the short column stays, the long ones split what is left
        let w = TableLayout.widths([59, 700, 500], fit: 353)
        XCTAssertEqual(w[0], 59)
        XCTAssertEqual(w[1], w[2])
        XCTAssertLessThanOrEqual(w.reduce(0, +), 353)
        XCTAssertGreaterThan(w.reduce(0, +), 350)
    }

    func testManyColumnsStopAtTheLeastAndScroll() {
        let w = TableLayout.widths([130, 80, 110, 190, 120, 230], fit: 353)
        XCTAssertEqual(w, [120, 80, 110, 120, 120, 120])
        XCTAssertGreaterThan(w.reduce(0, +), 353, "wider than the chat: it scrolls")
    }

    func testEveryColumnIsAtMostSixtyPercent() {
        for fit in [320.0, 353, 402, 700] as [CGFloat] {
            for w in TableLayout.widths([2000, 10, 3000], fit: fit) {
                XCTAssertLessThanOrEqual(w, fit * 0.6, "\(fit)")
            }
        }
    }
}
