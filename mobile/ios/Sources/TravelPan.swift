import UIKit
import UIKit.UIGestureRecognizerSubclass

/// A pan that counts how far its finger has travelled since it touched down, in the window's points, before UIKit
/// asks whether the pan may begin. UIKit's own velocity (and sometimes translation) is still zero at that moment when
/// the first move already passes the slop, so the swipes that decide by direction read `travel` (SwipeStart, a131).
final class TravelPan: UIPanGestureRecognizer {
    private var start: CGPoint?
    /// the finger's move since it touched down (zero until it moves)
    private(set) var travel: CGPoint = .zero

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        if start == nil, let t = touches.first {
            start = t.location(in: nil)
            travel = .zero
        }
        super.touchesBegan(touches, with: event)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        if let s = start, let t = touches.first {
            let p = t.location(in: nil)
            travel = CGPoint(x: p.x - s.x, y: p.y - s.y)
        }
        super.touchesMoved(touches, with: event)
    }

    override func reset() {
        super.reset()
        start = nil
        travel = .zero
    }

    /// which way the finger is heading (the travel, or the velocity when no travel was seen)
    var heading: CGPoint {
        SwipeStart.heading(travel: travel, velocity: velocity(in: nil))
    }
}
