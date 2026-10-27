import SwiftUI
import UIKit

// Claude's replies. The PC already cut each reply into blocks (paragraphs, headings, lists, quotes, code, tables,
// pictures); this file only draws them. Inline marks (bold, italics, `code`, links) use Apple's own Markdown parser.

enum ChatStyle {
    static let body = Color(hex: 0xD4D4D4)
    static let dim = Color(hex: 0x98989F)
    static let faint = Color(hex: 0x6F6F75)
    static let line = Color(hex: 0x2A2A2A)
    static let cardBG = Color(hex: 0x1A1A1C)
    static let cardBorder = Color(hex: 0x29292D)
    static let chevronBG = Color(hex: 0x1F1F22)
    static let bubble = Color(hex: 0x2F5FB3)
    static let codeBG = Color(hex: 0x24242A)
    static let codeText = Color(hex: 0xC9C9EA)
    static let add = Color(hex: 0x7FB07F)
    static let del = Color(hex: 0xE08A85)
    static let failed = Color(hex: 0xE08A85)
    static let done = Color(hex: 0x6FBF73)
    static let clock = Color(hex: 0x8A8A90)
}

enum Inline {
    /// One line of Markdown as styled text: **bold**, *italics*, `code` on its own tint, links in blue, and a small
    /// colour swatch before every #rrggbb (as the desktop draws them).
    static func text(_ s: String, size: CGFloat = 17, color: Color = ChatStyle.body) -> AttributedString {
        let opts = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace,
                                                           failurePolicy: .returnPartiallyParsedIfPossible)
        var a = (try? AttributedString(markdown: s, options: opts)) ?? AttributedString(s)
        a.foregroundColor = color
        for run in a.runs {
            guard let intent = run.inlinePresentationIntent else {
                if run.link != nil { a[run.range].foregroundColor = Theme.blue }
                continue
            }
            if intent.contains(.code) {
                a[run.range].font = .system(size: size - 2, design: .monospaced)
                a[run.range].foregroundColor = ChatStyle.codeText
                a[run.range].backgroundColor = ChatStyle.codeBG
            }
            if run.link != nil { a[run.range].foregroundColor = Theme.blue }
        }
        swatches(&a)
        return a
    }

    private static let hexColour = try! NSRegularExpression(pattern: "#[0-9a-fA-F]{6}\\b")

    private static func swatches(_ a: inout AttributedString) {
        let plain = String(a.characters)
        let ns = plain as NSString
        let hits = hexColour.matches(in: plain, range: NSRange(location: 0, length: ns.length))
        for m in hits.reversed() {
            guard let r = Range(m.range, in: plain),
                  let v = UInt32(plain[r].dropFirst(), radix: 16) else { continue }
            let offset = plain.distance(from: plain.startIndex, to: r.lowerBound)
            let at = a.characters.index(a.characters.startIndex, offsetBy: offset)
            var sw = AttributedString("\u{25A0}\u{2009}")
            sw.foregroundColor = Color(hex: v)
            a.insert(sw, at: at)
        }
    }
}

/// A reply's blocks, top to bottom.
struct MarkdownView: View {
    let blocks: [MD]
    let base: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // `i` stays the block's place in the whole reply: picture ids (ChatPhotos) count every block
            ForEach(Array(blocks.enumerated()).filter { !$0.element.isFallback }, id: \.offset) { i, b in
                block(b, at: i)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func block(_ b: MD, at i: Int) -> some View {
        switch b.t {
        case "p":
            Text(Inline.text(b.text ?? ""))
                .font(.system(size: 17))
                .lineSpacing(5)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        case "h":
            Text(Inline.text(b.text ?? "", color: Theme.title))
                .font(.system(size: (b.level ?? 3) <= 1 ? 22 : (b.level ?? 3) == 2 ? 20 : 17, weight: .semibold))
                .padding(.top, 4)
                .fixedSize(horizontal: false, vertical: true)
        case "list":
            ListBlock(items: b.items ?? [])
        case "quote":
            HStack(alignment: .top, spacing: 12) {
                RoundedRectangle(cornerRadius: 1.5).fill(Color(hex: 0x3A3A3E)).frame(width: 3)
                Text(Inline.text(b.text ?? "", color: ChatStyle.dim))
                    .font(.system(size: 17))
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .fixedSize(horizontal: false, vertical: true)
        case "code":
            CodePanel(lang: b.lang ?? "", code: b.code ?? "")
        case "table":
            TableBlock(head: b.head ?? [], rows: b.rows ?? [], align: b.align ?? [])
        case "hr":
            Rectangle().fill(ChatStyle.line).frame(height: 1).padding(.vertical, 4)
        case "media":
            MediaGroup(items: b.items ?? [], base: base, slot: i)
        case "mockups":
            if let ms = b.set { MockupSetView(mockup: ms, base: base, slot: i) }
        default:
            if let t = b.text { Text(t).font(.system(size: 17)).foregroundStyle(ChatStyle.body) }
        }
    }
}

private struct ListBlock: View {
    let items: [MDItem]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, it in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    marker(it)
                        .frame(minWidth: 18, alignment: .trailing)
                    Text(Inline.text(it.text ?? ""))
                        .font(.system(size: 17))
                        .lineSpacing(4)
                        .strikethrough(it.done == true, color: ChatStyle.dim)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.leading, CGFloat(it.level ?? 0) * 20)
            }
        }
    }

    @ViewBuilder
    private func marker(_ it: MDItem) -> some View {
        if let done = it.done {
            Image(systemName: done ? "checkmark.square.fill" : "square")
                .font(.system(size: 15))
                .foregroundStyle(done ? ChatStyle.done : ChatStyle.dim)
        } else if let n = it.n {
            Text("\(n).").font(.system(size: 17)).foregroundStyle(ChatStyle.dim).monospacedDigit()
        } else {
            Text("\u{2022}").font(.system(size: 17)).foregroundStyle(ChatStyle.dim)
        }
    }
}

/// A code block: the language and Copy on top, the code below; long lines scroll sideways instead of wrapping.
struct CodePanel: View {
    let lang: String
    let code: String
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(lang.isEmpty ? "code" : lang)
                    .font(.system(size: 13))
                    .foregroundStyle(ChatStyle.dim)
                Spacer()
                Button {
                    UIPasteboard.general.string = code
                    copied = true
                    Task {
                        try? await Task.sleep(nanoseconds: 1_500_000_000)
                        copied = false
                    }
                } label: {
                    Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 13))
                        .foregroundStyle(copied ? ChatStyle.done : ChatStyle.dim)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("copyCode")
            }
            .padding(.horizontal, 12)
            .frame(height: 40)
            Rectangle().fill(ChatStyle.cardBorder).frame(height: 1)
            ScrollView(.horizontal, showsIndicators: false) {
                Text(code)
                    .font(.system(size: 14, design: .monospaced))
                    .foregroundStyle(Color(hex: 0xD8D8E0))
                    .lineSpacing(3)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: true, vertical: true)
                    .padding(12)
            }
        }
        .background(ChatStyle.cardBG, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(ChatStyle.cardBorder, lineWidth: 1))
    }
}

/// A Markdown table: header row, then the rows, in a rounded box no wider than the chat. Columns are as wide as
/// their widest cell (see `TableLayout`) and every row as tall as its tallest cell; a table still wider than the
/// chat scrolls sideways inside its box.
private struct TableBlock: View {
    let head: [String]
    let rows: [[String]]
    let align: [String]
    /// the chat column's width, and the table's own (0 until measured)
    @State private var room: CGFloat = 0
    @State private var natural: CGFloat = 0

    private var columns: Int { max(head.count, rows.map(\.count).max() ?? 0) }

    var body: some View {
        let n = columns
        let layout = TableLayout(columns: n, fit: room > 0 ? room : TableLayout.guess)
        ScrollView(.horizontal) {
            layout {
                ForEach(0..<n, id: \.self) { c in
                    cell(c < head.count ? head[c] : "", row: 0, column: c)
                }
                ForEach(Array(rows.enumerated()), id: \.offset) { r, row in
                    ForEach(0..<n, id: \.self) { c in
                        cell(c < row.count ? row[c] : "", row: r + 1, column: c)
                    }
                }
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { natural = $0 }
        }
        .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
        .scrollIndicatorsFlash(onAppear: true)
        // a narrow table keeps a narrow box; a wide one fills the chat's width and scrolls inside it
        .frame(maxWidth: natural > 0 ? natural : nil, alignment: .leading)
        .background(ChatStyle.cardBG, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(ChatStyle.cardBorder, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("table")
        .frame(maxWidth: .infinity, alignment: .leading)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { room = $0 }
    }

    private func cell(_ s: String, row: Int, column: Int) -> some View {
        let a = column < align.count ? align[column] : ""
        let h: HorizontalAlignment = a == "right" ? .trailing : a == "center" ? .center : .leading
        let bold = row == 0
        return Text(Inline.text(s, size: 15, color: bold ? Theme.title : ChatStyle.body))
            .font(.system(size: 15, weight: bold ? .semibold : .regular))
            .multilineTextAlignment(a == "right" ? .trailing : a == "center" ? .center : .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            // filled to the row's height, so the header's tint and the lines between rows run edge to edge
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: Alignment(horizontal: h, vertical: .top))
            .background(bold ? Color(hex: 0x202024) : .clear)
            .overlay(alignment: .top) {
                if row > 0 { Rectangle().fill(ChatStyle.cardBorder).frame(height: 1) }
            }
            .accessibilityIdentifier("cell-\(row)-\(column)")
    }
}

/// Lays a table's cells (row by row, `columns` to a row) in columns. A column is as wide as its widest cell, at most
/// `most` of the chat's width; if they still add up to more than `fit`, the widest columns give way first, down to
/// `least`, and only then is the table wider than the chat (it scrolls). Every row is as tall as its tallest cell at
/// its column's width, so wrapped text never runs into the next row, at any text size.
struct TableLayout: Layout {
    var columns: Int
    /// the chat column's width
    var fit: CGFloat

    /// the width used before the chat's is known (one layout pass)
    static let guess: CGFloat = 353
    static let most: CGFloat = 0.6
    static let least: CGFloat = 120

    /// the columns' widths from their widest cells' one-line widths
    static func widths(_ ideal: [CGFloat], fit: CGFloat) -> [CGFloat] {
        let least = min(Self.least, fit * 0.45)
        let cap = floor(max(fit * most, least))
        let w = ideal.map { min(ceil($0), cap) }
        guard w.reduce(0, +) > fit else { return w }
        // the widest give way first: the cap c where the columns, each at most c, just fill the chat
        var left = fit
        var c = least
        let sorted = w.sorted()
        for (k, x) in sorted.enumerated() {
            let share = left / CGFloat(sorted.count - k)
            if x <= share { left -= x } else { c = share; break }
        }
        c = max(floor(c), least)
        return w.map { min($0, c) }
    }

    /// the columns' widths and the rows' heights
    func measure(_ subviews: Subviews) -> (widths: [CGFloat], heights: [CGFloat]) {
        let n = max(columns, 1)
        var ideal = [CGFloat](repeating: 0, count: n)
        for (i, s) in subviews.enumerated() {
            ideal[i % n] = max(ideal[i % n], s.sizeThatFits(.unspecified).width)
        }
        let widths = Self.widths(ideal, fit: fit)
        var heights = [CGFloat](repeating: 0, count: (subviews.count + n - 1) / n)
        for (i, s) in subviews.enumerated() {
            let h = s.sizeThatFits(ProposedViewSize(width: widths[i % n], height: nil)).height
            heights[i / n] = max(heights[i / n], ceil(h))
        }
        return (widths, heights)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let m = measure(subviews)
        return CGSize(width: m.widths.reduce(0, +), height: m.heights.reduce(0, +))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let m = measure(subviews)
        let n = m.widths.count
        var y = bounds.minY
        for (r, h) in m.heights.enumerated() {
            var x = bounds.minX
            for (c, w) in m.widths.enumerated() where r * n + c < subviews.count {
                subviews[r * n + c].place(at: CGPoint(x: x, y: y), anchor: .topLeading,
                                          proposal: ProposedViewSize(width: w, height: h))
                x += w
            }
            y += h
        }
    }
}
