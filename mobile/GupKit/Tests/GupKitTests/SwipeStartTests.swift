import Foundation
import XCTest
#if canImport(GupKit)
@testable import GupKit
#else
@testable import GupWorks3
#endif

/// a131: which way a swipe is heading when it decides to start. UIKit can report a zero velocity there (a fast flick
/// whose first move already passes the slop), so the finger's own travel decides.
final class SwipeStartTests: XCTestCase {
    func testTheFingersTravelDecidesWhenTheVelocityIsZero() {
        // a flick left from a menu row: first move 28 pt, UIKit's velocity still zero
        let d = SwipeStart.heading(travel: CGPoint(x: -28, y: 1), velocity: .zero)
        XCTAssertTrue(SwipeStart.menu(closing: true, heading: d), "the close swipe starts")
        XCTAssertFalse(SwipeStart.menu(closing: false, heading: d), "it doesn't count as opening")
        // the photo viewer: a quick swipe down
        XCTAssertTrue(SwipeStart.down(SwipeStart.heading(travel: CGPoint(x: 2, y: 30), velocity: .zero)))
    }

    func testTheTravelWinsOverAStrayVelocity() {
        // the finger went left; one odd sample says up
        let d = SwipeStart.heading(travel: CGPoint(x: -24, y: 3), velocity: CGPoint(x: 0, y: -400))
        XCTAssertTrue(SwipeStart.menu(closing: true, heading: d))
    }

    func testTheVelocityWhenNoTravelWasSeen() {
        let d = SwipeStart.heading(travel: .zero, velocity: CGPoint(x: -900, y: 40))
        XCTAssertTrue(SwipeStart.menu(closing: true, heading: d))
        XCTAssertFalse(SwipeStart.menu(closing: true, heading: SwipeStart.heading(travel: .zero, velocity: .zero)),
                       "nothing known: no swipe")
    }

    func testMostlySidewaysAndTheRightWay() {
        XCTAssertTrue(SwipeStart.menu(closing: false, heading: CGPoint(x: 30, y: 10)), "a swipe right opens")
        XCTAssertFalse(SwipeStart.menu(closing: false, heading: CGPoint(x: 30, y: 25)), "too steep: the chat scrolls")
        XCTAssertFalse(SwipeStart.menu(closing: true, heading: CGPoint(x: 30, y: 0)), "right doesn't close")
        XCTAssertTrue(SwipeStart.down(CGPoint(x: 10, y: 30)))
        XCTAssertFalse(SwipeStart.down(CGPoint(x: 28, y: 30)), "as much sideways as down: paging, not closing")
        XCTAssertFalse(SwipeStart.down(CGPoint(x: 0, y: -30)), "up doesn't close")
    }
}
