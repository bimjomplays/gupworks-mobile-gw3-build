import SwiftUI

/// D4: the / button. Search, your pinned commands as chips (Edit to unpin), the recent ones, then every command by
/// group, each with a 44 pt pin (blue = pinned). A tap runs it in the chat; one that needs words goes into the box.
struct CommandsSheet: View {
    let store: ChatStore
    /// opens D5 (model and effort are picked there, not on the PC's own picker)
    var details: () -> Void = {}
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""
    @State private var editing = false
    @State private var hint: String?

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Commands")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { dismiss() } label: { Image(systemName: "xmark") }
                            .accessibilityLabel("Close")
                            .accessibilityIdentifier("closeCommands")
                    }
                }
                .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search commands")
        }
        .presentationDetents([.medium, .large])
        .task { await store.loadCommands() }
        .alert("Commands", isPresented: Binding(get: { hint != nil }, set: { if !$0 { hint = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(hint ?? "")
        }
    }

    @ViewBuilder
    private var content: some View {
        if let c = store.commands {
            List {
                let q = search.trimmingCharacters(in: .whitespaces).lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                if q.isEmpty {
                    if !c.pinned.isEmpty { pinnedSection(c) }
                    let recent = c.recent.compactMap { r in c.commands.first { $0.name == r } }
                    if !recent.isEmpty {
                        Section("Recent") { ForEach(recent) { row($0, c) } }
                    }
                    ForEach(groups(c), id: \.self) { g in
                        Section(g) { ForEach(c.commands.filter { $0.group == g }) { row($0, c) } }
                    }
                } else {
                    let found = c.commands.filter { $0.name.lowercased().contains(q) || ($0.summary ?? "").lowercased().contains(q) }
                    ForEach(found) { row($0, c) }
                    if found.isEmpty {
                        Button {
                            let words = search.trimmingCharacters(in: .whitespaces)
                            store.put(words.hasPrefix("/") ? words + " " : "/\(words) ")
                            dismiss()
                        } label: {
                            Label("Type /\(q) in the box", systemImage: "text.cursor")
                        }
                        .accessibilityIdentifier("typeCommand")
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Color(hex: 0x1B1B1E))
        } else {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func groups(_ c: CommandsReply) -> [String] {
        let listed = c.groups ?? []
        let extra = c.commands.map(\.group).reduce(into: [String]()) { if !listed.contains($1) && !$0.contains($1) { $0.append($1) } }
        return (listed + extra).filter { g in c.commands.contains { $0.group == g } }
    }

    private func pinnedSection(_ c: CommandsReply) -> some View {
        Section {
            FlowLayout(spacing: 10) {
                ForEach(c.pinned, id: \.self) { name in
                    Button {
                        if editing {
                            Task { await store.togglePin(name) }
                        } else if let cmd = c.commands.first(where: { $0.name == name }) {
                            tap(cmd)
                        } else {
                            tap(CommandInfo(name: name, group: ""))
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: editing ? "xmark.circle.fill" : Self.icon(name))
                                .font(.system(size: 15))
                                .foregroundStyle(editing ? ChatStyle.dim : Theme.rowTitle)
                            Text(name).font(.system(size: 17)).foregroundStyle(Theme.rowTitle)
                        }
                        .padding(.horizontal, 16)
                        .frame(minHeight: 44)
                        .background(Color(hex: 0x2A2A2E), in: Capsule())
                        .overlay(Capsule().stroke(Color(hex: 0x38383E), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(editing ? "Unpin \(name)" : name)
                    .accessibilityIdentifier("pinned-\(name)")
                }
            }
            .padding(.vertical, 6)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
        } header: {
            HStack {
                Text("Pinned")
                Spacer()
                Button(editing ? "Done" : "Edit") { withAnimation { editing.toggle() } }
                    .font(.system(size: 15))
                    .textCase(nil)
                    .accessibilityIdentifier("editPins")
            }
        }
    }

    private func row(_ cmd: CommandInfo, _ c: CommandsReply) -> some View {
        let pinned = c.pinned.contains(cmd.name)
        return HStack(spacing: 8) {
            Button { tap(cmd) } label: {
                VStack(alignment: .leading, spacing: 3) {
                    Text("/\(cmd.name)\(cmd.args.map { $0.isEmpty ? "" : " " + $0 } ?? "")")
                        .font(.system(size: 17))
                        .foregroundStyle(Theme.rowTitle)
                    if let s = cmd.summary, !s.isEmpty {
                        Text(s).font(.system(size: 14)).foregroundStyle(ChatStyle.dim).lineLimit(2)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("cmd-\(cmd.name)")
            Button {
                Task { await store.togglePin(cmd.name) }
            } label: {
                Image(systemName: pinned ? "pin.fill" : "pin")
                    .font(.system(size: 17))
                    .foregroundStyle(pinned ? Theme.blue : ChatStyle.dim)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(pinned ? "Unpin /\(cmd.name)" : "Pin /\(cmd.name)")
            .accessibilityIdentifier("pin-\(cmd.name)")
        }
        .listRowBackground(Color(hex: 0x232327))
    }

    /// what a tap does: most commands run in the chat now; a few open the phone's own page for the same thing
    private func tap(_ cmd: CommandInfo) {
        switch cmd.name {
        case "model", "effort":
            details()
            dismiss()
        case "rewind":
            hint = "Long-press one of your messages and pick Rewind to here."
        case "btw":
            store.put("/btw ")
            dismiss()
        default:
            dismiss()
            Task { await store.run(cmd) }
        }
    }

    static func icon(_ name: String) -> String {
        switch name {
        case "btw": return "bubble.left"
        case "rewind": return "arrow.uturn.backward"
        case "copy": return "doc.on.doc"
        case "compact": return "arrow.down.right.and.arrow.up.left"
        case "idea": return "lightbulb"
        case "code-review", "review", "security-review": return "chevron.left.forwardslash.chevron.right"
        case "loop": return "repeat"
        case "context": return "chart.pie"
        case "clear": return "eraser"
        case "model": return "cpu"
        case "effort": return "gauge.with.dots.needle.50percent"
        case "init": return "doc.badge.plus"
        case "plan": return "list.bullet.clipboard"
        default: return "slash.circle"
        }
    }
}
