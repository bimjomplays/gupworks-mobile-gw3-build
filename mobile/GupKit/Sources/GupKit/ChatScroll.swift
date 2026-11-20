import Foundation

/// a229: when a chat's scroll view may move on its own, and by how much.
///
/// The chat follows the newest text only while it sits at the bottom with no finger on it. A finger on the chat
/// stops following at once; letting go at the bottom (or where following left it, after only holding or tapping)
/// takes it up again. Scrolled away from the bottom, nothing moves what is on screen: content growing or shrinking
/// below stays below, and content changing size above the line being read (older turns loading, a picture getting
/// its size, a fold) is made up for by moving the offset by the same amount, so that line stays put.
///
/// Rows are the chat's parts (a turn's prompt, fold, blocks) with their tops in the content's own coordinates;
/// `top` is the content's y at the top of the readable area (contentOffset + the top inset). The view (ChatScrollKeeper)
/// feeds it UIKit's touches and offsets and SwiftUI's row positions, and does the moves it returns.
struct ChatScroll {
    /// within this many points of the bottom counts as at the bottom
    static let slack = 8.0

    enum Move: Equatable {
        case none
        /// to the bottom (animated after a letting go or your own message; a plain jump while following)
        case bottom(animated: Bool)
        /// the offset moves by this much (content above the line being read changed size)
        case by(Double)
    }

    private(set) var following = true
    private(set) var touching = false
    /// following was stopped by the app (a fold opened, a jump to a message): only reaching the bottom again takes it up
    private(set) var held = false
    private var followedAtTouch = false
    private var topAtTouch = 0.0
    private var released = false
    /// the finger (or the fling after it) last left the view at the bottom
    private var leftAtBottom = false

    /// the rows' tops in the content
    private(set) var rows: [String: Double] = [:]
    /// the row the reading line is in, and how far its top was from the reading line when the user left it there
    private(set) var anchor: String?
    private var anchorGap = 0.0
    /// the reading line a correction asked for: when the view gets there it is that correction, not a scroll, and the
    /// kept row stays (rows below it may not have told their new tops yet)
    private var correctedTop: Double?

    // MARK: touches

    /// a finger came down on the chat (`top`: the reading line now)
    mutating func touchDown(top: Double) {
        if !touching {
            followedAtTouch = following && !held
            topAtTouch = top
        }
        touching = true
        released = false
        leftAtBottom = false
        following = false
        held = false
    }

    /// the view moved while a finger has it or right after one let go (a fling, a bounce): whether that motion left it
    /// at the bottom (text arriving afterwards doesn't change that; it only moves the bottom)
    mutating func moved(gap: Double) {
        guard touching || released else { return }
        leftAtBottom = gap <= Self.slack
    }

    /// the last finger left
    mutating func touchUp() {
        guard touching else { return }
        touching = false
        released = true
    }

    /// the scroll came to rest after a letting go (no finger, no fling): follow again when at the bottom (`gap`: how far
    /// the bottom of the content is below the screen's), or when it was following and the finger only held or tapped
    /// or pushed toward the bottom
    mutating func rest(top: Double, gap: Double) -> Move {
        guard released, !touching else { return .none }
        released = false
        if gap <= Self.slack || leftAtBottom {
            // at the bottom, or taken there by the finger while new text kept coming: follow again
            following = true
            return gap > 0.5 ? .bottom(animated: gap > Self.slack) : .none
        }
        if followedAtTouch && !held && top >= topAtTouch - Self.slack {
            following = true
            return .bottom(animated: true)
        }
        return .none
    }

    // MARK: what the app does

    /// your own message: to the bottom, following
    mutating func follow() -> Move {
        following = true
        held = false
        return .bottom(animated: true)
    }

    /// the app moves what you look at (a fold opens, a jump to a message): stop following until the bottom is reached
    mutating func hold() {
        following = false
        held = true
        followedAtTouch = false
    }

    // MARK: geometry

    /// the content, the screen or their insets changed size: following stays at the bottom
    func resized(gap: Double) -> Move {
        following && !touching && abs(gap) > 0.5 ? .bottom(animated: false) : .none
    }

    /// the view moved (the user, a correction, following): the row at the reading line becomes the one kept in place
    mutating func scrolled(top: Double) {
        if let want = correctedTop {
            correctedTop = nil
            if abs(want - top) <= 0.5, anchor != nil { return }
        }
        guard !rows.isEmpty else { anchor = nil; return }
        // the last row starting at or above the reading line, else the first row (the line is above all of them)
        var best: (id: String, top: Double)?
        var first: (id: String, top: Double)?
        for (id, t) in rows {
            if t <= top + 0.5, best == nil || t > best!.top || (t == best!.top && id < best!.id) { best = (id, t) }
            if first == nil || t < first!.top || (t == first!.top && id < first!.id) { first = (id, t) }
        }
        guard let pick = best ?? first else { return }
        anchor = pick.id
        anchorGap = pick.top - top
    }

    /// a row's top in the content now; `top` is the reading line now. When the kept row moved and the chat isn't
    /// following, the offset moves with it.
    mutating func row(_ id: String, top rowTop: Double, readingTop top: Double) -> Move {
        rows[id] = rowTop
        if anchor == nil { scrolled(top: top) }
        guard !following, id == anchor else { return .none }
        let delta = (rowTop - anchorGap) - top
        guard abs(delta) > 0.5 else { return .none }
        correctedTop = top + delta
        return .by(delta)
    }

    /// a row left the chat (rewound, folded away): another one is picked at the next scroll
    mutating func rowGone(_ id: String, readingTop top: Double) {
        rows[id] = nil
        if anchor == id { scrolled(top: top) }
    }
}

/// a229: a reply's blocks as the pieces it is drawn in. Paragraphs, headings and lists next to each other are one
/// piece of text, so a selection can run across all of them; code, quotes, tables, rules, pictures and mockup sets
/// are pieces of their own. `index` is each block's place in the whole reply (picture ids count every block).
struct MDPiece: Equatable {
    /// the first block's place
    var start: Int
    var blocks: [MD]
    /// paragraphs, headings and lists drawn as one text
    var text: Bool

    static let flowing: Set<String> = ["p", "h", "list"]

    static func split(_ blocks: [MD]) -> [MDPiece] {
        var out: [MDPiece] = []
        for (i, b) in blocks.enumerated() where !b.isFallback {
            let flows = flowing.contains(b.t)
            if flows, var last = out.last, last.text {
                last.blocks.append(b)
                out[out.count - 1] = last
            } else {
                out.append(MDPiece(start: i, blocks: [b], text: flows))
            }
        }
        return out
    }
}
