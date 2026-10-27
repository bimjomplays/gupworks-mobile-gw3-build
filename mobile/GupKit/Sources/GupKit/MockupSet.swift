import Foundation

// A ```mockups block in a reply (docs/mockup-set-mockups, Set card design A): the PC sends it parsed
// (gw3_mockups.as_block) as a `mockups` block; the phone draws it as one set card (MockupSetView).

/// The set: its name (and round), what stays the same, the numbered options, and the differences table with the
/// options as columns (`head` like ["", "1 Ledger", "2 Paper"], each row a difference and one cell per option).
struct MockupSet: Codable, Equatable {
    var title: String
    var same: String?
    var options: [MockupOption]
    var head: [String]?
    var rows: [[String]]?
}

/// One option: `n Name: how it differs`, with its screens in order.
struct MockupOption: Codable, Equatable {
    var n: Int
    var name: String
    var differs: String?
    var shots: [MockupShot]
}

/// One screen of an option: its badge (`2b`, or just `2` when the option has one), its label ("Overview") and its
/// picture's link; `missing` names the file when the picture is gone.
struct MockupShot: Codable, Equatable {
    var badge: String
    var label: String?
    var url: String?
    var missing: String?
}

/// A picture of the set as the viewer shows it: in set order, titled in words ("Option 2 · Cards — Overview"), with
/// how its option differs under it and its short code ("2b", what you type to answer) as a small tag.
struct MockupPhoto: Equatable {
    var id: String
    var link: String
    var title: String
    var detail: String
    var tag: String
}

/// One row of "How they differ": what differs, then each option's answer by number.
struct MockupDifference: Equatable {
    var label: String
    var values: [Value]

    struct Value: Equatable {
        var key: String     // the option's number ("2"), or the column's name when it has none
        var name: String    // in words: the option's name ("Cards"), else the column's name
        var text: String
    }
}

extension MockupSet {
    var optionsLine: String { options.count == 1 ? "1 option" : "\(options.count) options" }

    /// every picture in set order (1, 2a, 2b, 3 ...); missing ones are left out. Ids are `scope/set/badge`.
    func photos(scope: String) -> [MockupPhoto] {
        options.flatMap { o in
            o.shots.compactMap { s -> MockupPhoto? in
                guard let link = s.url, !link.isEmpty else { return nil }
                return MockupPhoto(id: Self.photoId(scope: scope, badge: s.badge), link: link,
                                   title: Self.title(o, s), detail: o.differs ?? "", tag: s.badge)
            }
        }
    }

    static func photoId(scope: String, badge: String) -> String { "\(scope)/set/\(badge)" }

    /// "Option 2 · Cards": an option in words (bare codes like "1b" were confusing, 2026-10-26)
    static func optionTitle(_ o: MockupOption) -> String { "Option \(o.n) · \(o.name)" }

    /// a screen in words: "Option 2 · Cards — Overview"; "Option 1 · Sections" for an option's only, unlabelled one
    static func title(_ o: MockupOption, _ s: MockupShot) -> String {
        let label = (s.label ?? "").trimmingCharacters(in: .whitespaces)
        return optionTitle(o) + (label.isEmpty ? "" : " — \(label)")
    }

    /// "How they differ" as rows for a phone-width list; empty when the set has no table
    var differences: [MockupDifference] {
        guard let head, head.count > 1, let rows else { return [] }
        let columns = head.dropFirst().map { h in (key: Self.key(h), name: name(h)) }
        return rows.compactMap { r in
            guard let label = r.first else { return nil }
            let values = zip(columns, r.dropFirst()).compactMap { c, v -> MockupDifference.Value? in
                let t = v.trimmingCharacters(in: .whitespaces)
                return t.isEmpty ? nil : .init(key: c.key, name: c.name, text: t)
            }
            return values.isEmpty ? nil : MockupDifference(label: label, values: values)
        }
    }

    /// a column in words: "2 Paper" -> "Paper" (the option's own name when the column has only its number)
    func name(_ header: String) -> String {
        let h = header.trimmingCharacters(in: .whitespaces)
        let k = Self.key(h)
        guard !k.isEmpty, k.allSatisfy(\.isNumber) else { return h }
        let rest = h.dropFirst(k.count).trimmingCharacters(in: .whitespaces.union(CharacterSet(charactersIn: ".:·-")))
        if !rest.isEmpty { return rest }
        return options.first { "\($0.n)" == k }?.name ?? h
    }

    /// a column's option number ("2 Paper" -> "2"), else the column's own name
    static func key(_ header: String) -> String {
        let h = header.trimmingCharacters(in: .whitespaces)
        let digits = h.prefix { $0.isNumber }
        return digits.isEmpty || digits.count > 3 ? h : String(digits)
    }

    /// the set as text to copy: name, what's the same, each option, the differences
    var plain: String {
        var out = ["Mockup set: \(title)"]
        if let same, !same.isEmpty { out.append(same) }
        for o in options {
            var line = Self.optionTitle(o)
            if let d = o.differs, !d.isEmpty { line += ": \(d)" }
            if o.shots.count > 1 {
                line += "\nScreens: " + o.shots.map { s in
                    let label = (s.label ?? "").trimmingCharacters(in: .whitespaces)
                    return label.isEmpty ? s.badge : "\(label) (\(s.badge))"
                }.joined(separator: ", ")
            }
            out.append(line)
        }
        let diffs = differences
        if !diffs.isEmpty {
            out.append("How they differ\n" + diffs.map { d in
                ([d.label] + d.values.map { "  \($0.name): \($0.text)" }).joined(separator: "\n")
            }.joined(separator: "\n"))
        }
        return out.joined(separator: "\n\n")
    }
}

extension MD {
    /// a block the PC sends only for older apps (a mockup set written out as text and pictures): not drawn
    var isFallback: Bool { fallback == true }
}
