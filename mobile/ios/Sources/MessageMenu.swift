import SwiftUI

/// What a long-press on a message (D7) and the thread card's answers can do; ChatView hands it down the turns.
struct MessageActions {
    /// Rewind to here: nil while Claude works (the PC can't rewind then)
    var rewind: ((Turn) -> Void)? = nil
    var btw: (String) -> Void = { _ in }
    /// sends words in this chat (the thread card's answers), naming the bar's question when the card knows it
    var reply: (String, AskPick?) -> Void = { _, _ in }

    /// a message cut to one line of about 80 characters, to quote in /btw or the rewind confirm
    static func quote(_ text: String, max: Int = 80) -> String {
        let one = text.split(whereSeparator: \.isNewline).joined(separator: " ").trimmingCharacters(in: .whitespaces)
        return one.count > max ? String(one.prefix(max - 1)).trimmingCharacters(in: .whitespaces) + "\u{2026}" : one
    }

    /// an answer's words as text to copy: paragraphs, list items, code and table rows, one per line
    static func plain(_ blocks: [MD]) -> String {
        blocks.filter { !$0.isFallback }.compactMap { b -> String? in
            switch b.t {
            case "mockups": return b.set?.plain
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

/// D7, a229: a message's own actions. Its words select where they stand (ReplyText.swift) and the selection's bubble
/// has Copy, Ask btw about it, Copy message and, on your own messages that are rewind points, Rewind to here. A
/// message with no words (only pictures) keeps the press menu for Rewind to here.
private struct MessageMenu: ViewModifier {
    let text: String
    let turn: Turn?
    @Environment(\.messageActions) private var actions

    func body(content: Content) -> some View {
        let rewind: (() -> Void)? = turn.flatMap { t in actions.rewind.map { r in { r(t) } } }
        if text.isEmpty, let rewind {
            content.contextMenu {
                Button(action: rewind) {
                    Label("Rewind to here", systemImage: "arrow.uturn.backward")
                    Text("go back and edit this message")
                }
            }
        } else {
            content.environment(\.messageMenuItems, MessageMenuItems(whole: text, rewind: rewind))
        }
    }
}

extension View {
    /// D7: the message's actions in its selection's bubble (Rewind to here on your own messages that are rewind points)
    func messageMenu(text: String, turn: Turn?) -> some View {
        modifier(MessageMenu(text: text, turn: turn))
    }
}
