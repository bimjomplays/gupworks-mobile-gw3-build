import Foundation

/// Open chat with the card in view (README feature 6; the desktop's NeedsModel::reveal): the ask card in a project's
/// main chat that asks this question, else its newest open one. Its row id is the one ChatView gives the card
/// (`<turn>/outside/<id>`), which the chat's ChatScrollKeeper scrolls to.
enum NeedsReveal {
    static func row(in turns: [Turn], question: String?) -> String? {
        let want = (question ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        var newestOpen: String?
        var newestAny: String?
        for t in turns {
            for o in t.outside ?? [] where o.type == "ask" {
                let id = "\(t.id)/outside/\(o.id)"
                newestAny = id
                if o.answered != true { newestOpen = id }
                if !want.isEmpty, (o.question ?? "").trimmingCharacters(in: .whitespacesAndNewlines) == want { return id }
            }
        }
        return newestOpen ?? newestAny
    }
}

struct NeedsRevealRequest: Equatable {
    var chatId: String
    /// the main chat's ask card that asks this (nil: a plain chat, whose question is its dialog at the end)
    var question: String?

    init?(_ item: NeedItem) {
        guard let c = item.openChat, !c.isEmpty else { return nil }
        chatId = c
        question = item.source == "project" ? (item.question ?? "") : nil
    }
}
