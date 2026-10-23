import SwiftUI
import UIKit

/// What a long-press on a message (D7) and the thread card's answers can do; ChatView hands it down the turns.
struct MessageActions {
    /// Rewind to here: nil while Claude works (the PC can't rewind then)
    var rewind: ((Turn) -> Void)? = nil
    var btw: (String) -> Void = { _ in }
    var select: (String) -> Void = { _ in }
    /// sends words in this chat (the thread card's answers)
    var reply: (String) -> Void = { _ in }

    /// a message cut to one line of about 80 characters, to quote in /btw or the rewind confirm
    static func quote(_ text: String, max: Int = 80) -> String {
        let one = text.split(whereSeparator: \.isNewline).joined(separator: " ").trimmingCharacters(in: .whitespaces)
        return one.count > max ? String(one.prefix(max - 1)).trimmingCharacters(in: .whitespaces) + "\u{2026}" : one
    }

    /// an answer's words as text to copy: paragraphs, list items, code and table rows, one per line
    static func plain(_ blocks: [MD]) -> String {
        blocks.compactMap { b -> String? in
            switch b.t {
            case "code": return b.code ?? b.text
            case "list":
                return (b.items ?? []).compactMap { i in
                    guard let t = i.text else { return nil }
                    let indent = String(repeating: "  ", count: max(0, (i.level ?? 0)))
                    let mark = i.done.map { $0 ? "[x] " : "[ ] " } ?? ""
                    return indent + (i.n.map { "\($0). " } ?? "- ") + mark + t
                }.joined(separator: "\n")
            case "table":
                return ([b.head ?? []] + (b.rows ?? [])).filter { !$0.isEmpty }.map { $0.joined(separator: "\t") }.joined(separator: "\n")
            case "media", "image", "video": return nil
            default: return b.text
            }
        }
        .filter { !$0.isEmpty }
        .joined(separator: "\n\n")
    }
}

extension EnvironmentValues {
    @Entry var messageActions = MessageActions()
}

private struct MessageMenu: ViewModifier {
    let text: String
    let turn: Turn?
    @Environment(\.messageActions) private var actions

    func body(content: Content) -> some View {
        content.contextMenu {
            if let t = turn, let rewind = actions.rewind {
                Button { rewind(t) } label: {
                    Label("Rewind to here", systemImage: "arrow.uturn.backward")
                    Text("go back and edit this message")
                }
            }
            if !text.isEmpty {
                Button("Copy", systemImage: "doc.on.doc") { UIPasteboard.general.string = text }
                Button("Ask btw about it", systemImage: "bubble.left") { actions.btw(text) }
                Button("Select text", systemImage: "selection.pin.in.out") { actions.select(text) }
            }
        }
    }
}

extension View {
    /// D7: Rewind to here (your own messages that are rewind points), Copy, Ask btw about it, Select text
    func messageMenu(text: String, turn: Turn?) -> some View {
        modifier(MessageMenu(text: text, turn: turn))
    }
}

struct SelectedText: Identifiable {
    let id = UUID()
    let text: String
}

/// Select text: the message in a page of its own, to pick any part of it and copy.
struct SelectTextSheet: View {
    let text: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            SelectableText(text: text)
                .padding(.horizontal, 14)
                .background(Theme.background)
                .navigationTitle("Select text")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }.accessibilityIdentifier("doneSelecting")
                    }
                }
        }
    }
}

/// UITextView's own selection (handles, Copy, Look Up): SwiftUI's Text selects only the whole text.
private struct SelectableText: UIViewRepresentable {
    let text: String

    func makeUIView(context: Context) -> UITextView {
        let v = UITextView()
        v.isEditable = false
        v.isSelectable = true
        v.backgroundColor = .clear
        v.font = .systemFont(ofSize: 17)
        v.textColor = UIColor(white: 0.9, alpha: 1)
        v.textContainerInset = UIEdgeInsets(top: 16, left: 0, bottom: 24, right: 0)
        v.accessibilityIdentifier = "selectText"
        return v
    }

    func updateUIView(_ v: UITextView, context: Context) {
        if v.text != text { v.text = text }
    }
}
