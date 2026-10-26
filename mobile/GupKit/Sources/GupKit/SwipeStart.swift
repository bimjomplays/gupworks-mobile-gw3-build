import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// Which way a drag is heading when a swipe decides whether to start: the side menu's swipe (MenuSwipe) and the photo
/// viewer's swipe down (PhotoPagerView).
///
/// UIKit asks a pan's gestureRecognizerShouldBegin once the finger has passed its 10 pt slop. When the first move is
/// already past it (a fast flick: 1000 pt/s is 16 pt between two 60 Hz samples; or a busy phone that hands over a few
/// moves at once), the pan's velocity, and sometimes its translation, are still zero there. Read from the velocity
/// alone, such a flick didn't start the swipe: the menu stayed where it was and the row under the finger took the
/// touch as a tap (CI's first UI test on a cold simulator, about every other run), and the viewer didn't close.
/// So the finger's own travel since it touched down (TravelPan counts it) decides; the velocity only when no travel
/// was seen.
enum SwipeStart {
    /// the drag's direction so far
    static func heading(travel: CGPoint, velocity: CGPoint) -> CGPoint {
        abs(travel.x) + abs(travel.y) >= 1 ? travel : velocity
    }

    /// the menu's swipe: mostly sideways (half as much again across as up or down), left to close, right to open
    static func menu(closing: Bool, heading d: CGPoint) -> Bool {
        abs(d.x) > 1.5 * abs(d.y) && (closing ? d.x < 0 : d.x > 0)
    }

    /// the photo viewer's swipe down: down, and more down than sideways (sideways pages)
    static func down(_ d: CGPoint) -> Bool {
        d.y > 0 && abs(d.y) > abs(d.x) * 1.2
    }
}
