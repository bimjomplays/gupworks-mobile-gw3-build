import SwiftUI
import UIKit

// a229: a reply's text selects where it stands, like any text on iOS: press on a word, drag the handles, Copy from the
// system's bubble. SwiftUI's Text only copies the whole text, so the words are drawn by a UITextView (not editable,
// not scrolling, as tall as its text, measured in the same layout pass so nothing measures late). Paragraphs, headings
// and lists next to each other are one text (MDPiece), so a selection runs across them; a code block, a quote and a
// message bubble are texts of their own; tables, pictures and mockup sets aren't selectable text.
//
// The message menu's actions are in the system bubble that comes with the selection: Copy (the selection), then
// Ask btw about it (the selection), Copy message (the whole message) and, on your own messages that are rewind
// points, Rewind to here; then the system's Look Up, Translate, Share...

/// What a message's selection bubble adds to the system's actions.
struct MessageMenuItems {
    /// the whole message as text, for Copy message
    var whole: String?
    /// your own message's Rewind to here
    var rewind: (() -> Void)?
}

extension EnvironmentValues {
    /// set by the chat for each message; elsewhere (a plan card, a note) the bubble has only the system's actions
    @Entry var messageMenuItems: MessageMenuItems? = nil
}

// MARK: the look: Markdown blocks as attributed text, the same sizes, colours and spacing as the SwiftUI views had

enum ReplyLook {
    static let size: CGFloat = 17
    static let body = UIColor(ChatStyle.body)
    static let dim = UIColor(ChatStyle.dim)
    static let title = UIColor(Theme.title)
    static let blue = UIColor(Theme.blue)
    static let codeText = UIColor(ChatStyle.codeText)
    static let codeBG = UIColor(ChatStyle.codeBG)
    static let done = UIColor(ChatStyle.done)

    /// paragraphs, headings and lists, one after another (12 points between blocks, as the stack had)
    static func flowing(_ blocks: [MD]) -> NSAttributedString {
        let out = NSMutableAttributedString()
        for (k, b) in blocks.enumerated() {
            let last = k == blocks.count - 1
            let after: CGFloat = last ? 0 : 12
            switch b.t {
            case "h":
                let level = b.level ?? 3
                let size: CGFloat = level <= 1 ? 22 : level == 2 ? 20 : 17
                let p = NSMutableParagraphStyle()
                p.paragraphSpacingBefore = k == 0 ? 0 : 4
                p.paragraphSpacing = after
                out.append(paragraph(inline(b.text ?? "", size: size, color: title, weight: .semibold), p, last: last))
            case "list":
                let items = b.items ?? []
                for (j, it) in items.enumerated() {
                    let end = j == items.count - 1
                    out.append(listItem(it, after: end ? after : 6, last: last && end))
                }
            default:
                let p = NSMutableParagraphStyle()
                p.lineSpacing = 5
                p.paragraphSpacing = max(0, after - 5)
                out.append(paragraph(inline(b.text ?? "", size: size, color: body), p, last: last))
            }
        }
        return out
    }

    /// a quote's words (the bar beside them is the view's)
    static func quote(_ text: String) -> NSAttributedString {
        let p = NSMutableParagraphStyle()
        p.lineSpacing = 4
        return paragraph(inline(text, size: size, color: dim), p, last: true)
    }

    /// a code block's lines, unwrapped
    static func code(_ code: String) -> NSAttributedString {
        let p = NSMutableParagraphStyle()
        p.lineSpacing = 3
        p.lineBreakMode = .byClipping
        return NSAttributedString(string: code, attributes: [
            .font: UIFont.monospacedSystemFont(ofSize: 14, weight: .regular),
            .foregroundColor: UIColor(Color(hex: 0xD8D8E0)),
            .paragraphStyle: p,
        ])
    }

    /// your message's words in its bubble
    static func bubble(_ text: String) -> NSAttributedString {
        let p = NSMutableParagraphStyle()
        p.lineSpacing = 2
        return NSAttributedString(string: text, attributes: [
            .font: UIFont.systemFont(ofSize: size), .foregroundColor: UIColor.white, .paragraphStyle: p,
        ])
    }

    private static func paragraph(_ s: NSMutableAttributedString, _ p: NSParagraphStyle, last: Bool) -> NSAttributedString {
        if !last { s.append(NSAttributedString(string: "\n", attributes: s.length > 0 ? s.attributes(at: s.length - 1, effectiveRange: nil) : [:])) }
        s.addAttribute(.paragraphStyle, value: p, range: NSRange(location: 0, length: s.length))
        return s
    }

    /// a list item: its mark right-aligned in at least 18 points, 8 points, then the words (wrapped lines under the
    /// words), 20 points in per level
    private static func listItem(_ it: MDItem, after: CGFloat, last: Bool) -> NSAttributedString {
        let lead = CGFloat(it.level ?? 0) * 20
        let mark = NSMutableAttributedString()
        if let done = it.done {
            let cfg = UIImage.SymbolConfiguration(pointSize: 15)
            let img = UIImage(systemName: done ? "checkmark.square.fill" : "square", withConfiguration: cfg)?
                .withTintColor(done ? ReplyLook.done : dim, renderingMode: .alwaysOriginal)
            let a = NSTextAttachment()
            a.image = img
            let s = img?.size ?? CGSize(width: 17, height: 17)
            a.bounds = CGRect(x: 0, y: -2.5, width: s.width, height: s.height)
            mark.append(NSAttributedString(attachment: a))
        } else if let n = it.n {
            mark.append(NSAttributedString(string: "\(n).", attributes: [
                .font: UIFont.monospacedDigitSystemFont(ofSize: size, weight: .regular), .foregroundColor: dim,
            ]))
        } else {
            mark.append(NSAttributedString(string: "\u{2022}", attributes: [.font: UIFont.systemFont(ofSize: size),
                                                                            .foregroundColor: dim]))
        }
        let w = max(18, ceil(mark.size().width))
        let p = NSMutableParagraphStyle()
        p.lineSpacing = 4
        p.paragraphSpacing = max(0, after - 4)
        p.firstLineHeadIndent = lead
        p.headIndent = lead + w + 8
        p.tabStops = [NSTextTab(textAlignment: .right, location: lead + w), NSTextTab(textAlignment: .left, location: lead + w + 8)]
        let tab = NSAttributedString(string: "\t", attributes: [.font: UIFont.systemFont(ofSize: size)])
        let s = NSMutableAttributedString()
        s.append(tab)
        s.append(mark)
        s.append(tab)
        let words = inline(it.text ?? "", size: size, color: body)
        if it.done == true {
            words.addAttributes([.strikethroughStyle: NSUnderlineStyle.single.rawValue, .strikethroughColor: dim],
                                range: NSRange(location: 0, length: words.length))
        }
        s.append(words)
        return paragraph(s, p, last: last)
    }

    /// one block's inline Markdown: **bold**, *italics*, ~~struck~~, `code` on its own tint, links in blue, and a
    /// colour swatch before every #rrggbb (as Inline.text draws them)
    static func inline(_ s: String, size: CGFloat, color: UIColor, weight: UIFont.Weight = .regular) -> NSMutableAttributedString {
        let opts = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace,
                                                           failurePolicy: .returnPartiallyParsedIfPossible)
        let a = (try? AttributedString(markdown: s, options: opts)) ?? AttributedString(s)
        let out = NSMutableAttributedString()
        for run in a.runs {
            let text = String(a[run.range].characters)
            var font = UIFont.systemFont(ofSize: size, weight: weight)
            var attrs: [NSAttributedString.Key: Any] = [.foregroundColor: color]
            if let intent = run.inlinePresentationIntent {
                if intent.contains(.code) {
                    font = .monospacedSystemFont(ofSize: size - 2, weight: .regular)
                    attrs[.foregroundColor] = codeText
                    attrs[.backgroundColor] = codeBG
                } else {
                    if intent.contains(.stronglyEmphasized) { font = .systemFont(ofSize: size, weight: .bold) }
                    if intent.contains(.emphasized), let d = font.fontDescriptor.withSymbolicTraits(
                        font.fontDescriptor.symbolicTraits.union(.traitItalic)) {
                        font = UIFont(descriptor: d, size: size)
                    }
                }
                if intent.contains(.strikethrough) { attrs[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
            }
            if let link = run.link { attrs[.link] = link }
            attrs[.font] = font
            out.append(NSAttributedString(string: text, attributes: attrs))
        }
        swatches(out)
        return out
    }

    private static let hexColour = try! NSRegularExpression(pattern: "#[0-9a-fA-F]{6}\\b")
    static let swatch = "\u{25A0}\u{2009}"

    private static func swatches(_ a: NSMutableAttributedString) {
        let plain = a.string as NSString
        for m in hexColour.matches(in: a.string, range: NSRange(location: 0, length: plain.length)).reversed() {
            guard let v = UInt32(plain.substring(with: m.range).dropFirst(), radix: 16) else { continue }
            var attrs = a.attributes(at: m.range.location, effectiveRange: nil)
            attrs[.foregroundColor] = UIColor(Color(hex: v))
            attrs[.backgroundColor] = nil
            attrs[.link] = nil
            a.insert(NSAttributedString(string: swatch, attributes: attrs), at: m.range.location)
        }
    }

    /// what Copy puts on the clipboard: the words without the list marks' tabs or the colour swatches
    static func copyable(_ s: String) -> String {
        s.components(separatedBy: "\n").map { line -> String in
            var l = line.replacingOccurrences(of: swatch, with: "").replacingOccurrences(of: "\u{FFFC}", with: "")
            if l.hasPrefix("\t") {
                l.removeFirst()
                if let t = l.firstIndex(of: "\t") { l.replaceSubrange(t...t, with: " ") }
            }
            return l
        }.joined(separator: "\n")
    }
}

// MARK: the text view

/// Selectable text as tall as its words. `fit`: as wide as its longest line (a bubble, a code block); else the width
/// it is offered (a reply).
struct SelectableText: UIViewRepresentable {
    let text: NSAttributedString
    var fit = false
    var id: String? = nil
    @Environment(\.messageActions) private var actions
    @Environment(\.messageMenuItems) private var items

    func makeUIView(context: Context) -> ReplyTextView {
        let v = ReplyTextView(frame: .zero, textContainer: nil)
        v.setUp()
        v.attributedText = text
        return v
    }

    func updateUIView(_ v: ReplyTextView, context: Context) {
        if !v.attributedText.isEqual(to: text) {
            v.attributedText = text
            v.invalidateIntrinsicContentSize()
        }
        // Ask btw only on a chat's messages (a plan card or a note has just the system's actions)
        v.btw = items != nil ? actions.btw : nil
        v.items = items
        v.accessibilityIdentifier = id
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView v: ReplyTextView, context: Context) -> CGSize? {
        let room = proposal.width.map { $0.isFinite ? $0 : 100_000 } ?? 100_000
        let r = text.boundingRect(with: CGSize(width: room, height: .greatestFiniteMagnitude),
                                  options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
        let offered = proposal.width.flatMap { $0.isFinite ? $0 : nil }
        let width = fit ? min(room, ceil(r.width)) : (offered ?? ceil(r.width))
        if !v.attributedText.isEqual(to: text) { v.attributedText = text }
        let h = v.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude)).height
        return CGSize(width: width, height: ceil(h))
    }
}

final class ReplyTextView: UITextView, UITextViewDelegate {
    var btw: ((String) -> Void)?
    var items: MessageMenuItems?

    func setUp() {
        isEditable = false
        isSelectable = true
        isScrollEnabled = false
        backgroundColor = .clear
        textContainerInset = .zero
        textContainer.lineFragmentPadding = 0
        dataDetectorTypes = []
        linkTextAttributes = [.foregroundColor: ReplyLook.blue]
        // a press on selected words selects (no lifting them out to drag)
        textDragInteraction?.isEnabled = false
        setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        setContentHuggingPriority(.defaultLow, for: .horizontal)
        delegate = self
        isAccessibilityElement = true
    }

    // read as plain words (VoiceOver and the screen tests find a message by its words)
    override var accessibilityLabel: String? {
        get { ReplyLook.copyable(text ?? "") }
        set {}
    }
    override var accessibilityValue: String? {
        get { nil }
        set {}
    }
    override var accessibilityTraits: UIAccessibilityTraits {
        get { .staticText }
        set {}
    }

    private var selected: String {
        guard let r = Range(selectedRange, in: text ?? "") else { return "" }
        return ReplyLook.copyable(String((text ?? "")[r]))
    }

    override func copy(_ sender: Any?) {
        UIPasteboard.general.string = selected
    }

    func textView(_ textView: UITextView, editMenuForTextIn range: NSRange,
                  suggestedActions: [UIMenuElement]) -> UIMenu? {
        var mine: [UIMenuElement] = []
        if let btw {
            mine.append(UIAction(title: "Ask btw about it", image: UIImage(systemName: "bubble.left")) { [weak self] _ in
                guard let self else { return }
                btw(self.selected)
                self.selectedRange = NSRange(location: 0, length: 0)
            })
        }
        if let whole = items?.whole, !whole.isEmpty {
            mine.append(UIAction(title: "Copy message", image: UIImage(systemName: "doc.on.doc")) { [weak self] _ in
                UIPasteboard.general.string = whole
                self?.selectedRange = NSRange(location: 0, length: 0)
            })
        }
        if let rewind = items?.rewind {
            mine.append(UIAction(title: "Rewind to here", image: UIImage(systemName: "arrow.uturn.backward")) { [weak self] _ in
                self?.selectedRange = NSRange(location: 0, length: 0)
                rewind()
            })
        }
        guard !mine.isEmpty else { return nil }
        // the system's Copy first, then these, then the rest (Look Up, Translate, Share...)
        let first = suggestedActions.prefix(1)
        return UIMenu(children: Array(first) + [UIMenu(options: .displayInline, children: mine)] + suggestedActions.dropFirst())
    }
}
