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
        .presentationDetents([.large])  // D5: the whole sheet at once, the usage meters and cache included
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
                SheetHeader("Model")
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
                SheetHeader("Permissions")
            } footer: {
                Text(bypassNote(h))
            }

            if !h.usage.isEmpty || h.cache != nil {
                Section {
                    ForEach(h.usage, id: \.label) { m in meter(m) }
                    if let c = h.cache { cacheRow(c) }
                } header: {
                    SheetHeader("Usage")
                }
            }

            Section {
                if let p = h.project { detail("folder.badge.gearshape", "Project", p.name) }
                if let b = h.branch, !b.isEmpty { detail("arrow.triangle.branch", "Branch", b) }
                if let f = h.folder, !f.isEmpty { detail("folder", "Folder", f) }
            } header: {
                SheetHeader("Details")
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

/// D4/D5's section headers: small, grey, as typed (iOS 26 lists draw them large and bold otherwise)
struct SheetHeader: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).font(.system(size: 15)).foregroundStyle(ChatStyle.dim).textCase(nil)
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
