import Foundation

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

extension Format {
    /// 51000 -> "51K", 1_200_000 -> "1.2M"
    static func tokens(_ n: Double) -> String {
        if n >= 1_000_000 {
            let m = n / 1_000_000
            return (m >= 10 || m == m.rounded() ? String(Int(m.rounded())) : String(format: "%.1f", m)) + "M"
        }
        if n >= 1000 { return "\(Int((n / 1000).rounded()))K" }
        return String(Int(n))
    }

    /// D5's right side of a meter: "51K of 150K · 34%", "5% · resets in 3h 15m", "36%"
    static func meterLine(_ m: Meter, now: Date) -> String {
        let pct = m.percent.map { "\(Int($0.rounded()))%" } ?? "\u{2013}"
        if m.label == "ctx", let t = m.tokens, let of = m.switchAt, of > 0 {
            return "\(tokens(t)) of \(tokens(of)) · \(pct)"
        }
        if let r = m.resets, let at = isoDate(r), at > now {
            return "\(pct) · resets in \(span(at.timeIntervalSince(now)))"
        }
        return pct
    }

    /// "3h 15m", "45m", "2d 4h"
    static func span(_ seconds: TimeInterval) -> String {
        let m = max(0, Int(seconds / 60))
        if m >= 24 * 60 { return "\(m / 1440)d \((m % 1440) / 60)h" }
        if m >= 60 { return "\(m / 60)h \(m % 60)m" }
        return "\(m)m"
    }

    /// how long the prompt cache stays warm, or nil once it's cold
    static func cacheLeft(_ c: ChatHeader.Cache, now: Date) -> String? {
        guard let at = c.at, let ttl = c.ttlMin else { return nil }
        let end = at / 1000 + ttl * 60
        let left = end - now.timeIntervalSince1970
        return left > 0 ? span(left + 59) : nil
    }

    static func isoDate(_ s: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: s) { return d }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: s)
    }
}

extension Format {
    /// "just now", "4 min ago", "2 hours ago", "Yesterday", "3 days ago", "Oct 12"; `ms` since 1970.
    static func ago(_ ms: Double, now: Date = Date(), calendar: Calendar = .current, locale: Locale = .current) -> String {
        guard ms > 0 else { return "" }
        let s = now.timeIntervalSince1970 - ms / 1000
        if s < 60 { return "just now" }
        if s < 3600 { return "\(Int(s / 60)) min ago" }
        if s < 86_400 { return Int(s / 3600) == 1 ? "1 hour ago" : "\(Int(s / 3600)) hours ago" }
        let date = Date(timeIntervalSince1970: ms / 1000)
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date),
                                           to: calendar.startOfDay(for: now)).day ?? 0
        if days <= 1 { return "Yesterday" }
        if days < 7 { return "\(days) days ago" }
        return time(ms, now: now, calendar: calendar, locale: locale)
    }
}
