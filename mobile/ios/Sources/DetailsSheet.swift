import SwiftUI

/// D5: tapping the chat's title or the usage pill. The model and effort (picked here, they apply from the next turn,
/// as the desktop's picker), Bypass with its red switch, the usage meters and the cache, the branch and folder.
struct ChatDetailsSheet: View {
    let store: ChatStore
    @Environment(\.dismiss) private var dismiss

    static let red = Color(hex: 0xE07C7C)

    var body: some View {
        NavigationStack {
            if let h = store.header {
                list(h)
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(h.title).font(.system(size: 17, weight: .semibold)).foregroundStyle(Theme.title)
                                    .lineLimit(1)
                                Text("Chat details").font(.system(size: 13)).foregroundStyle(ChatStyle.dim)
                            }
                            .fixedSize()
                        }
                        .sharedBackgroundVisibility(.hidden)
                        ToolbarItem(placement: .topBarTrailing) {
                            Button { dismiss() } label: { Image(systemName: "xmark") }
                                .accessibilityLabel("Close")
                                .accessibilityIdentifier("closeDetails")
                        }
                    }
                    .navigationBarTitleDisplayMode(.inline)
            }
        }
        .presentationDetents([.medium, .large])
        .task { await store.loadModels() }
    }

    private var current: ModelInfo? {
        guard let h = store.header else { return nil }
        return store.models.first { $0.id == h.modelId } ?? store.models.first { $0.label == h.model }
    }

    private func list(_ h: ChatHeader) -> some View {
        List {
            Section {
                NavigationLink {
                    ModelPicker(store: store)
                } label: {
                    HStack {
                        Text("Model")
                        Spacer(minLength: 12)
                        Text([h.model, h.provider ?? ""].filter { !$0.isEmpty }.joined(separator: " · "))
                            .foregroundStyle(ChatStyle.dim)
                            .lineLimit(1)
                    }
                }
                .accessibilityIdentifier("modelRow")
                effortRow(h)
            } header: {
                Text("Model")
            } footer: {
                if h.pending == true {
                    Text("Applies from the next turn.").accessibilityIdentifier("pending")
                }
            }

            Section {
                Toggle(isOn: Binding(get: { h.bypass }, set: { on in Task { await store.setBypass(on) } })) {
                    HStack(spacing: 8) {
                        Text("Bypass permissions").foregroundStyle(h.bypass ? Self.red : Theme.rowTitle)
                        if store.switchingMode { ProgressView().controlSize(.small) }
                    }
                }
                .tint(Color(hex: 0xB84A4A))
                .disabled(!canSwitch(h) || store.switchingMode)
                .accessibilityIdentifier("bypass")
            } header: {
                Text("Permissions")
            } footer: {
                Text(bypassNote(h))
            }

            if !h.usage.isEmpty || h.cache != nil {
                Section("Usage") {
                    ForEach(h.usage, id: \.label) { m in meter(m) }
                    if let c = h.cache { cacheRow(c) }
                }
            }

            Section("Details") {
                if let p = h.project { detail("folder.badge.gearshape", "Project", p.name) }
                if let b = h.branch, !b.isEmpty { detail("arrow.triangle.branch", "Branch", b) }
                if let f = h.folder, !f.isEmpty { detail("folder", "Folder", f) }
            }
        }
    }

    @ViewBuilder
    private func effortRow(_ h: ChatHeader) -> some View {
        let efforts = current?.efforts ?? (h.effort.isEmpty ? [] : [h.effort])
        if !efforts.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("Effort")
                Picker("Effort", selection: Binding(get: { h.effort }, set: { e in
                    guard let m = current, e != h.effort else { return }
                    Task { await store.pick(model: m, effort: e) }
                })) {
                    ForEach(efforts, id: \.self) { Text($0).tag($0) }
                }
                .pickerStyle(.segmented)
                .disabled(current == nil)
                .accessibilityIdentifier("effort")
            }
        }
    }

    private func canSwitch(_ h: ChatHeader) -> Bool { h.running && h.door != false }

    private func bypassNote(_ h: ChatHeader) -> String {
        if !h.running { return "The chat isn't running. Start it with a message to change this." }
        if h.door == false { return "This chat started on an older GupWorks: change Bypass on the PC, or restart the chat there." }
        return "Claude runs tools without asking. The safety rules still ask before risky commands."
    }

    private func meter(_ m: Meter) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(Self.meterName(m.label))
                Spacer()
                Text(Format.meterLine(m, now: Date())).foregroundStyle(ChatStyle.dim).monospacedDigit()
            }
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color(hex: 0x2C3346))
                    Capsule().fill(Theme.blue).frame(width: g.size.width * max(0, min(1, (m.percent ?? 0) / 100)))
                }
            }
            .frame(height: 5)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    private func cacheRow(_ c: ChatHeader.Cache) -> some View {
        let left = Format.cacheLeft(c, now: Date())
        return HStack {
            Text("Cache")
            Spacer()
            Circle().fill(left != nil ? Theme.green : Theme.idleDot).frame(width: 7, height: 7)
            Text(left.map { "warm · \($0) left" } ?? "cold").foregroundStyle(ChatStyle.dim)
        }
        .accessibilityElement(children: .combine)
    }

    private func detail(_ icon: String, _ name: String, _ value: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon).foregroundStyle(ChatStyle.dim).frame(width: 22)
            Text(name)
            Spacer(minLength: 12)
            Text(value).foregroundStyle(ChatStyle.dim).lineLimit(1).truncationMode(.middle)
        }
    }

    static func meterName(_ label: String) -> String {
        switch label {
        case "ctx": return "Context"
        case "5h": return "5-hour"
        case "wk": return "Week"
        default: return label
        }
    }
}

/// Every model in the desktop's picker, by provider; picking one applies from the chat's next turn.
private struct ModelPicker: View {
    let store: ChatStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let providers = store.models.reduce(into: [String]()) { if !$0.contains($1.provider) { $0.append($1.provider) } }
        List {
            if store.models.isEmpty {
                ProgressView().frame(maxWidth: .infinity)
            }
            ForEach(providers, id: \.self) { p in
                Section(p) {
                    ForEach(store.models.filter { $0.provider == p }) { m in
                        Button {
                            Task { await store.pick(model: m, effort: store.header?.effort) }
                            dismiss()
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(m.label).foregroundStyle(Theme.rowTitle)
                                    if let n = m.note, !n.isEmpty {
                                        Text(n).font(.system(size: 13)).foregroundStyle(ChatStyle.dim)
                                    }
                                }
                                Spacer()
                                if m.id == store.header?.modelId {
                                    Image(systemName: "checkmark").foregroundStyle(Theme.blue)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .accessibilityIdentifier("model-\(m.id)")
                    }
                }
            }
        }
        .navigationTitle("Model")
        .navigationBarTitleDisplayMode(.inline)
    }
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
