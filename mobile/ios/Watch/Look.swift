import SwiftUI

/// The watch app's look (docs/watch-mockups/round1/build.py's CSS, round 2's bar): black like watchOS, the app's blue,
/// violet questions, amber permissions, red memory; 16 pt body, nothing under 12 pt, 44 pt buttons.
enum Look {
    static let blue = Color(hex: 0x2F5FB3)
    static let light = Color(hex: 0x8FB8FF)
    static let recTag = Color(hex: 0x9CC0FF)
    static let recBG = Color(hex: 0x1B2A47)
    static let violet = Color(hex: 0xA78BFA)
    static let amber = Color(hex: 0xE0B060)
    static let red = Color(hex: 0xFF7B7B)
    static let row = Color(hex: 0x1D1D1F)
    static let button = Color(hex: 0x232325)
    static let mic = Color(hex: 0x2A2A2D)
    static let edge = Color(hex: 0x3A3A3E)
    static let source = Color(hex: 0xA0A0A6)
    static let dim = Color(hex: 0x77777D)
    static let summary = Color(hex: 0x9C9CA2)
    static let detail = Color(hex: 0x98989E)
    static let threadID = Color(hex: 0xD0D0D6)
    static let allowBG = Color(hex: 0x5A4316)
    static let command = Color(hex: 0xE8D3A6)
    static let commandBG = Color(hex: 0x141414)
    static let commandEdge = Color(hex: 0x3A3222)
    static let memoryBG = Color(hex: 0x4A1D1D)
    static let memoryInk = Color(hex: 0xFFD0D0)
    static let sentBG = Color(hex: 0x17301F)
    static let sentEdge = Color(hex: 0x2E5A39)
    static let sentInk = Color(hex: 0xC9F0CF)
    static let sentDetail = Color(hex: 0x8FBF97)
    static let undoBG = Color(hex: 0x24452D)
    static let undoInk = Color(hex: 0xE2F7E5)

    static func tone(_ t: NeedTone) -> Color {
        switch t {
        case .violet: return violet
        case .amber: return amber
        case .red: return red
        case .grey: return dim
        }
    }

    /// the glyph's colour on its mark
    static func ink(_ t: NeedTone) -> Color {
        switch t {
        case .violet: return Color(hex: 0x151021)
        case .amber: return Color(hex: 0x21180A)
        case .red: return Color(hex: 0x2A0F0F)
        case .grey: return .black
        }
    }

    /// the double tap mark (the hand), as drawn in round 2
    static let hand = "hand.raised.fingers.spread.fill"
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
}

/// The round mark before the source: "!" on violet or amber, the memory chip on red.
struct ToneMark: View {
    let tone: NeedTone
    var size: CGFloat = 16

    var body: some View {
        Circle()
            .fill(Look.tone(tone))
            .frame(width: size, height: size)
            .overlay {
                if tone == .red {
                    Image(systemName: "memorychip").font(.system(size: size * 0.55, weight: .bold))
                } else {
                    Text("!").font(.system(size: size * 0.7, weight: .heavy))
                }
            }
            .foregroundStyle(Look.ink(tone))
    }
}

/// "● Home server · 12m" (a chat gets the speech bubble too); the memory card's in red.
struct SourceLine: View {
    let card: WatchCard
    let now: Double

    var body: some View {
        HStack(spacing: 5) {
            ToneMark(tone: card.tone)
            if card.chat {
                Image(systemName: "bubble.left").font(.system(size: 12)).foregroundStyle(Look.source)
            }
            Text(card.source)
                .foregroundStyle(card.kind == .memory ? Look.red : Look.source)
                .lineLimit(1)
            Text("· " + WatchCard.wait(now - card.since))
                .foregroundStyle(card.kind == .memory ? Look.red : Look.dim)
                .fixedSize()
        }
        .font(.system(size: 13, weight: .medium))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("watchSource")
    }
}

/// "⑂ a14 · Memory limits"
struct ThreadLine: View {
    let card: WatchCard

    var body: some View {
        if let id = card.threadId {
            HStack(spacing: 5) {
                Image(systemName: "arrow.triangle.branch").font(.system(size: 12))
                (Text(id).fontWeight(.semibold).foregroundColor(Look.threadID)
                    + Text(card.threadTitle.map { " · \($0)" } ?? ""))
                    .lineLimit(1)
            }
            .font(.system(size: 13))
            .foregroundStyle(Look.source)
            .accessibilityIdentifier("watchThread")
        }
    }
}

/// A 44 pt pill button (Deny, Sleep idle chats, Open on iPhone, Undo).
struct PillLabel: View {
    let title: String
    var icon: String?
    var fill: Color = Look.button
    var ink: Color = .white

    var body: some View {
        HStack(spacing: 6) {
            if let icon { Image(systemName: icon) }
            Text(title).lineLimit(1)
        }
        .font(.system(size: 16, weight: .medium))
        .foregroundStyle(ink)
        .frame(maxWidth: .infinity, minHeight: 44)
        .background(Capsule().fill(fill))
        .contentShape(Capsule())
    }
}

extension View {
    /// Double tap presses this control (watchOS 11 and a watch that has double tap; a plain tap everywhere else).
    @ViewBuilder
    func doubleTap(_ on: Bool) -> some View {
        if on, #available(watchOS 11.0, *) {
            self.handGestureShortcut(.primaryAction)
        } else {
            self
        }
    }
}
