import SwiftUI

// A ```mockups block in a reply, drawn as the desktop's Set card (design A, docs/mockup-set-mockups) made for a phone:
// one framed card with a MOCKUP SET header, each option as a row ("Option 2 · Cards", how it differs, its screens
// named in words with their short code as a small tag, swiping sideways when there are several), then "How they
// differ" as a list. A tap on a screen opens the photo viewer on this set only, in set order, each picture titled
// "Option 2 · Cards — Overview". Words first: bare codes like "1b" were confusing (2026-10-26); the codes
// stay as small tags because he answers with them ("2", "2b").

struct MockupSetView: View {
    let mockup: MockupSet
    let base: URL?
    /// the block's place in the reply
    let slot: Int
    @Environment(\.photoScope) private var scope
    @State private var open: MediaOpen?

    private var photos: [MockupPhoto] { mockup.photos(scope: "\(scope ?? "reply")/m\(slot)") }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            ForEach(mockup.options, id: \.n) { o in
                line
                option(o)
            }
            let diffs = mockup.differences
            if !diffs.isEmpty {
                line
                differences(diffs)
            }
        }
        .background(ChatStyle.cardBG, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(ChatStyle.cardBorder, lineWidth: 1))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("mockupSet")
        .fullScreenCover(item: $open) { o in
            MediaViewer(open: o, base: base)
        }
    }

    private var line: some View {
        Rectangle().fill(ChatStyle.cardBorder).frame(height: 1)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("MOCKUP SET")
                    .font(.system(size: 11, weight: .bold))
                    .tracking(0.6)
                    .foregroundStyle(Theme.blue)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Theme.blue.opacity(0.14), in: RoundedRectangle(cornerRadius: 5))
                Spacer()
                Text(mockup.optionsLine)
                    .font(.system(size: 13))
                    .foregroundStyle(ChatStyle.dim)
            }
            Text(Inline.text(mockup.title, color: Theme.title))
                .font(.system(size: 17, weight: .semibold))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("mockupTitle")
            if let same = mockup.same, !same.isEmpty {
                Text(Inline.text(same, size: 15, color: ChatStyle.dim))
                    .font(.system(size: 15))
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
    }

    private func option(_ o: MockupOption) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(optionTitle(o))
                            .font(.system(size: 17, weight: .semibold))
                            .accessibilityIdentifier("mockupOptionTitle-\(o.n)")
                        Spacer(minLength: 8)
                        Text(o.shots.count == 1 ? "1 screen" : "\(o.shots.count) screens")
                            .font(.system(size: 13))
                            .foregroundStyle(ChatStyle.faint)
                    }
                    if let d = o.differs, !d.isEmpty {
                        Text(Inline.text(d, size: 15, color: ChatStyle.body))
                            .font(.system(size: 15))
                            .lineSpacing(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(.horizontal, 14)
            screens(o)
        }
        .padding(.vertical, 14)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("mockupOption-\(o.n)")
    }

    @ViewBuilder
    private func screens(_ o: MockupOption) -> some View {
        if o.shots.count == 1, let s = o.shots.first {
            shot(o, s, single: true)
                .padding(.horizontal, 14)
        } else if !o.shots.isEmpty {
            // several screens: side by side, the next one peeking in so it's clear there are more
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 10) {
                    ForEach(o.shots, id: \.badge) { s in
                        shot(o, s, single: false)
                            .containerRelativeFrame(.horizontal) { w, _ in (w - 28) * 0.8 }
                    }
                }
                .scrollTargetLayout()
            }
            .contentMargins(.horizontal, 14, for: .scrollContent)
            .scrollTargetBehavior(.viewAligned)
            .accessibilityIdentifier("mockupScreens-\(o.n)")
        }
    }

    private func shot(_ o: MockupOption, _ s: MockupShot, single: Bool) -> some View {
        let label = s.label ?? ""
        return Button { tap(s) } label: {
            VStack(alignment: .leading, spacing: 6) {
                if !single || !label.isEmpty {
                    // the screen in words, its code only as a small tag after it
                    HStack(spacing: 6) {
                        Text(label.isEmpty ? "Screen" : label)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(ChatStyle.body)
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        CodeTag(text: s.badge)
                    }
                }
                picture(s, single: single)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(s.url == nil)
        .accessibilityLabel(MockupSet.title(o, s))
        .accessibilityIdentifier("mockupShot-\(s.badge)")
    }

    @ViewBuilder
    private func picture(_ s: MockupShot, single: Bool) -> some View {
        let url = MediaLink.url(s.url, base: base)
        Group {
            if s.url == nil {
                VStack(spacing: 6) {
                    Image(systemName: "photo.badge.exclamationmark").font(.system(size: 22))
                    Text("\(s.badge) is missing").font(.system(size: 13))
                    if let m = s.missing { Text(m).font(.system(size: 12)).foregroundStyle(ChatStyle.faint) }
                }
                .foregroundStyle(ChatStyle.dim)
                .frame(maxWidth: .infinity)
                .frame(height: 140)
            } else if single {
                RemoteImage(url: url)
                    .frame(maxWidth: .infinity, maxHeight: 460)
            } else {
                // a phone-shaped frame; the whole picture fits inside it, nothing is cut off
                Color.clear
                    .aspectRatio(0.78, contentMode: .fit)
                    .overlay(RemoteImage(url: url))
            }
        }
        .background(Color(hex: 0x121214))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(ChatStyle.cardBorder, lineWidth: 1))
    }

    /// "Option 2 · Cards": the words "Option 2" in blue, the name in white
    private func optionTitle(_ o: MockupOption) -> AttributedString {
        var number = AttributedString("Option \(o.n)")
        number.foregroundColor = Theme.blue
        var dot = AttributedString(" · ")
        dot.foregroundColor = ChatStyle.faint
        return number + dot + Inline.text(o.name, color: Theme.title)
    }

    /// "Cards  Low, roomy": the option's name in bold grey, then its answer
    private func value(_ v: MockupDifference.Value) -> AttributedString {
        var name = Inline.text(v.name, size: 15, color: ChatStyle.dim)
        name.inlinePresentationIntent = .stronglyEmphasized
        return name + AttributedString("  ") + Inline.text(v.text, size: 15)
    }

    private func tap(_ s: MockupShot) {
        let all = photos
        let id = MockupSet.photoId(scope: "\(scope ?? "reply")/m\(slot)", badge: s.badge)
        guard let p = all.first(where: { $0.id == id }) else { return }
        open = MediaOpen(item: MDItem(kind: "image", url: p.link, name: p.title),
                         photos: all.map { ChatPhoto(id: $0.id, link: $0.link, mine: false, title: $0.title,
                                                     detail: $0.detail, tag: $0.tag) },
                         start: p.id)
    }

    private func differences(_ diffs: [MockupDifference]) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("HOW THEY DIFFER")
                .font(.system(size: 12, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(ChatStyle.dim)
            ForEach(Array(diffs.enumerated()), id: \.offset) { _, d in
                VStack(alignment: .leading, spacing: 6) {
                    Text(Inline.text(d.label, size: 15, color: Theme.title))
                        .font(.system(size: 15, weight: .semibold))
                        .fixedSize(horizontal: false, vertical: true)
                    ForEach(Array(d.values.enumerated()), id: \.offset) { _, v in
                        // the option by name: "Cards  Low, roomy"
                        Text(value(v))
                            .font(.system(size: 15))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("mockupDifferences")
    }
}

/// A screen's short code ("2b"), small and quiet: what you can type to answer, never the screen's name.
struct CodeTag: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .monospacedDigit()
            .foregroundStyle(ChatStyle.dim)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .overlay(Capsule().stroke(ChatStyle.cardBorder, lineWidth: 1))
            .accessibilityLabel("code \(text)")
    }
}
