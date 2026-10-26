import XCTest
@testable import GupWorks3

/// The side menu's swipe (MenuDrag): the chat follows the finger 1:1 both ways, and opening and closing end by the
/// same rules.
final class MenuSwipeTests: XCTestCase {
    let drag = MenuDrag(width: 311)

    func testFollowsTheFinger() {
        // closed: right moves it out point for point, left does nothing
        XCTAssertEqual(drag.x(open: false, dx: 120), 120)
        XCTAssertEqual(drag.x(open: false, dx: -40), 0)
        XCTAssertEqual(drag.x(open: false, dx: 500), 311)
        // open: left moves it back point for point, from wherever the swipe started
        XCTAssertEqual(drag.x(open: true, dx: -120), 191)
        XCTAssertEqual(drag.x(open: true, dx: 60), 311)
        XCTAssertEqual(drag.x(open: true, dx: -400), 0)
    }

    func testClosesPastAThirdOrOnAFlick() {
        XCTAssertFalse(drag.endsOpen(open: true, dx: -120, velocity: 0), "past 35%: closes")
        XCTAssertTrue(drag.endsOpen(open: true, dx: -60, velocity: 0), "a short slow drag snaps back")
        XCTAssertFalse(drag.endsOpen(open: true, dx: -25, velocity: -900), "a short flick closes")
        XCTAssertTrue(drag.endsOpen(open: true, dx: -200, velocity: 700), "a flick back keeps it open")
        XCTAssertTrue(drag.endsOpen(open: true, dx: 0, velocity: 0), "a cancelled swipe keeps it open")
    }

    func testOpensTheSameWay() {
        XCTAssertTrue(drag.endsOpen(open: false, dx: 120, velocity: 0))
        XCTAssertFalse(drag.endsOpen(open: false, dx: 60, velocity: 0))
        XCTAssertTrue(drag.endsOpen(open: false, dx: 25, velocity: 900))
        XCTAssertFalse(drag.endsOpen(open: false, dx: 200, velocity: -700))
        XCTAssertFalse(drag.endsOpen(open: false, dx: 0, velocity: 0))
    }
}
