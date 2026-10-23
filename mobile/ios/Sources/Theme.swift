import SwiftUI

/// The D mockups' colours (docs/mobile-mockups/build_d.py): flat, dark, no gradients.
enum Theme {
    static let background = Color(hex: 0x181818)
    static let title = Color(hex: 0xF0F0F0)
    static let rowTitle = Color(hex: 0xE2E2E2)
    static let secondary = Color(hex: 0x8A8A8A)
    static let section = Color(hex: 0x7A7A7A)
    static let time = Color(hex: 0x7A7A7A)
    static let icon = Color(hex: 0x8A8A8A)
    static let violet = Color(hex: 0xA78BFA)
    static let violetText = Color(hex: 0xB9A3F5)
    static let amber = Color(hex: 0xE8B04A)
    static let blue = Color(hex: 0x6EA8FF)
    static let green = Color(hex: 0x7FB07F)
    static let idleDot = Color(hex: 0x555555)
    static let red = Color(hex: 0xFF7B7B)
}

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255, opacity: 1)
    }
}

enum Format {
    /// "now", "2:15 PM" (today), "Yesterday", "Oct 18", "Oct 18, 2025"; `ms` is milliseconds since 1970.
    static func time(_ ms: Double, now: Date = Date(), calendar: Calendar = .current, locale: Locale = .current) -> String {
        guard ms > 0 else { return "" }
        let date = Date(timeIntervalSince1970: ms / 1000)
        if now.timeIntervalSince(date) < 60 { return "now" }
        func styled(_ style: Date.FormatStyle) -> String {
            var style = style.locale(locale)
            style.calendar = calendar
            style.timeZone = calendar.timeZone
            return date.formatted(style)
        }
        if calendar.isDate(date, inSameDayAs: now) {
            return styled(Date.FormatStyle(date: .omitted, time: .shortened))
        }
        if let y = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: y) {
            return "Yesterday"
        }
        let sameYear = calendar.component(.year, from: date) == calendar.component(.year, from: now)
        return styled(sameYear ? Date.FormatStyle().month(.abbreviated).day() : Date.FormatStyle().month(.abbreviated).day().year())
    }

    static func plural(_ n: Int, _ word: String) -> String { "\(n) \(word)\(n == 1 ? "" : "s")" }
}
