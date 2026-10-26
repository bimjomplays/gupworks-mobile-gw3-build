import SwiftUI

/// 5f: the gauge's sheet. Every model by provider (a tick on the one in use), then the effort; picking applies from
/// the chat's next turn (a new chat starts on it). Swipe down or × to close.
struct ModelEffortSheet: View {
    let store: ChatStore
    @Environment(\.dismiss) private var dismiss
    @State private var moreOpen: Set<String> = []

    static let bg = Color(hex: 0x1C1C1E)
    static let group = Color(hex: 0x2C2C2E)
    static let line = Color(hex: 0x38383A)
    static let grey = Color(hex: 0x8E8E93)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                if store.models.isEmpty {
                    ProgressView().frame(maxWidth: .infinity).padding(.vertical, 40)
                }
                ForEach(providers, id: \.self) { p in
                    label(Self.providerName(p))
                    group(p)
                }
                if let m = store.currentModel, !m.efforts.isEmpty {
                    label("Effort")
                    EffortPicker(efforts: m.efforts, current: store.currentEffort) { e in
                        Task { await store.pick(model: m, effort: e) }
                    }
                }
                if let note {
                    Text(note)
                        .font(.system(size: 13))
                        .foregroundStyle(Self.grey)
                        .padding(.horizontal, 4)
                        .padding(.top, 9)
                        .accessibilityIdentifier("cacheNote")
                }
                if store.header?.pending == true {
                    Text("Applies from the next turn.")
                        .font(.system(size: 13))
                        .foregroundStyle(Self.grey)
                        .padding(.horizontal, 4)
                        .padding(.top, 6)
                        .accessibilityIdentifier("pending")
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 30)
        }
        .scrollIndicators(.hidden)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Self.bg)
        .task { await store.loadModels() }
    }

    private var header: some View {
        HStack(spacing: 9) {
            Icons.gauge(store.currentEffort, size: 22, width: 2).foregroundStyle(Composer.ink)
            Text("Model and effort").font(.system(size: 18, weight: .semibold)).foregroundStyle(Color(hex: 0xF2F2F2))
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Color(hex: 0xB4B4B8))
                    .frame(width: 32, height: 32)
                    .background(Self.group, in: Circle())
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")
            .accessibilityIdentifier("closeModels")
        }
        .frame(height: 50)
        .padding(.top, 18)
    }

    private var providers: [String] {
        store.models.reduce(into: [String]()) { if !$0.contains($1.provider) { $0.append($1.provider) } }
    }

    private func label(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13.5, weight: .medium))
            .foregroundStyle(Self.grey)
            .padding(.horizontal, 4)
            .padding(.top, 10)
            .padding(.bottom, 6)
    }

    /// one provider's models; OpenAI's past the first two fold under "N more"
    private func group(_ p: String) -> some View {
        let all = store.models.filter { $0.provider == p }
        let current = store.currentModel?.id
        let folds = p == "OpenAI" && all.count > 3 && !moreOpen.contains(p) && !all.dropFirst(2).contains { $0.id == current }
        let shown = folds ? Array(all.prefix(2)) : all
        return VStack(spacing: 0) {
            ForEach(Array(shown.enumerated()), id: \.element.id) { i, m in
                if i > 0 { Self.line.frame(height: 1) }
                Button {
                    Task { await store.pick(model: m, effort: store.currentEffort) }
                } label: {
                    HStack(spacing: 8) {
                        Text(m.label).font(.system(size: 16.5)).foregroundStyle(Composer.ink).lineLimit(1)
                        if let n = Self.blurb(m) {
                            Text(n).font(.system(size: 14)).foregroundStyle(Self.grey).lineLimit(1)
                        }
                        Spacer(minLength: 8)
                        if m.id == current {
                            Image(systemName: "checkmark").font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.blue)
                        }
                    }
                    .padding(.horizontal, 14)
                    .frame(height: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(m.id == current ? .isSelected : [])
                .accessibilityIdentifier("model-\(m.id)")
            }
            if folds {
                Self.line.frame(height: 1)
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { _ = moreOpen.insert(p) }
                } label: {
                    HStack {
                        Text("\(all.count - 2) more").font(.system(size: 16.5)).foregroundStyle(Composer.ink)
                        Spacer()
                        Image(systemName: "chevron.right").font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Self.grey)
                    }
                    .padding(.horizontal, 14)
                    .frame(height: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("moreModels")
            }
        }
        .background(Self.group, in: RoundedRectangle(cornerRadius: 14))
    }

    /// Switching restarts the prompt cache: only said in a chat whose cache is still warm, as the desktop does.
    private var note: String? {
        guard let h = store.header, !store.isNew, let c = h.cache, Format.cacheLeft(c, now: Date()) != nil else {
            return nil
        }
        let tokens = h.usage.first { $0.label == "ctx" }?.tokens
        let what = tokens.map { "\(Format.tokens($0)) tokens" } ?? "the whole chat"
        return "Switching restarts the prompt cache: your next message re-sends \(what) at full cost."
    }

    static func providerName(_ p: String) -> String {
        switch p.lowercased() {
        case "local": return "On your PC"
        case "openai": return "OpenAI"
        case "claude": return "Claude"
        default: return p
        }
    }

    /// what each model is for, in a few words (the PC's note for local models; "subscription" says nothing here)
    static func blurb(_ m: ModelInfo) -> String? {
        let id = m.id.lowercased()
        if id.contains("opus") { return "everyday, strong" }
        if id.contains("sonnet") { return "faster, lighter" }
        if id.contains("haiku") { return "quickest, cheapest" }
        if id.contains("fable") { return "hardest problems" }
        guard let n = m.note, !n.isEmpty, n.lowercased() != "subscription" else { return nil }
        return n
    }
}

/// low · medium · high · xhigh · max, as the mockup's segmented control (the levels follow the model)
private struct EffortPicker: View {
    let efforts: [String]
    let current: String?
    let pick: (String) -> Void

    var body: some View {
        HStack(spacing: 0) {
            ForEach(efforts, id: \.self) { e in
                Button { pick(e) } label: {
                    Text(e)
                        .font(.system(size: 15, weight: e == current ? .semibold : .regular))
                        .foregroundStyle(e == current ? .white : Color(hex: 0xB4B4B8))
                        .frame(maxWidth: .infinity)
                        .frame(height: 34)
                        .background(e == current ? Color(hex: 0x5A5A5E) : .clear, in: RoundedRectangle(cornerRadius: 9))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(e == current ? .isSelected : [])
                .accessibilityIdentifier("effort-\(e)")
            }
        }
        .padding(3)
        .background(ModelEffortSheet.group, in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("effort")
    }
}

/// 5g: what the three rings mean, with their numbers, above the box. Tap anywhere to close.
struct UsageCard: View {
    let usage: [Meter]
    let now: Date
    /// where the rings icon is, from the card's left edge: the tail points at it
    var tailX: CGFloat = 104

    static let bg = Color(hex: 0x1C1C1E)
    static let edge = Color(hex: 0x2F2F31)

    var body: some View {
        let rows = UsageCard.rows(usage, now: now)
        HStack(spacing: 16) {
            UsageRings(percents: rows.map(\.percent), size: 92, width: 2.4)
            VStack(alignment: .leading, spacing: 11) {
                ForEach(Array(rows.enumerated()), id: \.offset) { i, r in
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(spacing: 7) {
                            Circle().fill(UsageRings.colors[i]).frame(width: 9, height: 9)
                            Text(r.name).font(.system(size: 15.5, weight: .medium)).foregroundStyle(Composer.ink)
                            Spacer(minLength: 6)
                            Text(r.percent.map { "\(Int($0.rounded()))%" } ?? "\u{2013}")
                                .font(.system(size: 15.5, weight: .semibold))
                                .foregroundStyle(Composer.ink)
                                .monospacedDigit()
                        }
                        Text(r.detail)
                            .font(.system(size: 13))
                            .foregroundStyle(ModelEffortSheet.grey)
                            .lineLimit(1)
                            .padding(.leading, 16)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("usage-\(r.label)")
                }
            }
        }
        .padding(.leading, 16)
        .padding(.trailing, 18)
        .padding(.vertical, 16)
        .background(Self.bg, in: RoundedRectangle(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(Self.edge, lineWidth: 1))
        .overlay(alignment: .bottomLeading) {
            // the tail toward the rings in the box
            Rectangle()
                .fill(Self.bg)
                .frame(width: 14, height: 14)
                .overlay(alignment: .bottomTrailing) {
                    Path { p in
                        p.move(to: CGPoint(x: 14, y: 0)); p.addLine(to: CGPoint(x: 14, y: 14)); p.addLine(to: CGPoint(x: 0, y: 14))
                    }
                    .stroke(Self.edge, lineWidth: 1)
                }
                .rotationEffect(.degrees(45))
                .offset(x: tailX - 7, y: 7)
        }
        .shadow(color: .black.opacity(0.6), radius: 17, y: 14)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("usageCard")
    }

    struct Row: Equatable {
        var label: String
        var name: String
        var percent: Double?
        var detail: String
    }

    /// Context ("68K of 200K tokens"), the 5-hour limit ("resets in 3h 12m") and the week ("resets Thu 09:00").
    static func rows(_ usage: [Meter], now: Date, calendar: Calendar = .current) -> [Row] {
        func meter(_ l: String) -> Meter? { usage.first { $0.label == l } }
        let ctx = meter("ctx")
        var ctxLine = "A new chat starts empty"
        if let t = ctx?.tokens, let of = ctx?.switchAt, of > 0 {
            ctxLine = "\(Format.tokens(t)) of \(Format.tokens(of)) tokens"
        } else if let t = ctx?.tokens {
            ctxLine = "\(Format.tokens(t)) tokens"
        } else if ctx != nil {
            ctxLine = "How full this chat is"
        }
        func resets(_ m: Meter?, weekday: Bool) -> String {
            guard let r = m?.resets, let at = Format.isoDate(r) else { return m == nil ? "Not known yet" : "" }
            guard at > now else { return "Reset" }
            if !weekday { return "resets in \(Format.span(at.timeIntervalSince(now)))" }
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.calendar = calendar
            f.timeZone = calendar.timeZone
            f.dateFormat = "EEE HH:mm"
            return "resets \(f.string(from: at))"
        }
        let five = meter("5h"), week = meter("wk")
        return [Row(label: "ctx", name: "Context", percent: ctx?.percent ?? (ctx == nil ? 0 : nil), detail: ctxLine),
                Row(label: "5h", name: "5-hour limit", percent: five?.percent, detail: resets(five, weekday: false)),
                Row(label: "wk", name: "Weekly limit", percent: week?.percent, detail: resets(week, weekday: true))]
    }
}
