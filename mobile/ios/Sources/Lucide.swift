import CoreText
import SwiftUI
import UIKit

/// Lucide's icons (lucide-static 1.61.0, ISC: Resources/lucide-LICENSE.txt) as a font: every icon by its name, for
/// the project icons and the icon picker's search. Resources/lucide.json maps each name to its character and the
/// words it's found by.
enum Lucide {
    static let family = "lucide"

    /// Registers the bundled font once (the app's first icon does it).
    static let registered: Bool = {
        guard let url = Bundle.main.url(forResource: "lucide", withExtension: "woff2") else { return false }
        var error: Unmanaged<CFError>?
        if CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error) { return true }
        // already registered by an earlier run in the same process (the unit tests)
        return UIFont(name: family, size: 12) != nil
    }()

    /// name → (character, search words), from lucide.json
    static let catalog: [String: (UInt32, [String])] = {
        guard let url = Bundle.main.url(forResource: "lucide", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let raw = try? JSONSerialization.jsonObject(with: data) as? [String: [Any]] else { return [:] }
        var out: [String: (UInt32, [String])] = [:]
        out.reserveCapacity(raw.count)
        for (name, v) in raw {
            guard let cp = (v.first as? NSNumber)?.uint32Value else { continue }
            out[name] = (cp, v.dropFirst().compactMap { $0 as? String })
        }
        return out
    }()

    /// every icon name, A to Z
    static let names: [String] = catalog.keys.sorted()

    static func character(_ name: String) -> String? {
        guard let cp = catalog[name]?.0, let s = UnicodeScalar(cp) else { return nil }
        return String(Character(s))
    }

    /// Icons for a search: names that start with a word first, then names containing it, then the ones tagged
    /// with it; every word has to match.
    static func search(_ query: String, in names: [String] = Lucide.names) -> [String] {
        let words = query.lowercased().split(whereSeparator: { $0 == " " || $0 == "-" }).map(String.init)
        guard !words.isEmpty else { return names }
        var starts: [String] = [], contains: [String] = [], tagged: [String] = []
        for n in names {
            let tags = catalog[n]?.1 ?? []
            var rank = 0
            for w in words {
                if n.hasPrefix(w) || n.contains("-" + w) {
                    continue
                } else if n.contains(w) {
                    rank = max(rank, 1)
                } else if tags.contains(where: { $0.lowercased().contains(w) }) {
                    rank = 2
                } else {
                    rank = 3
                    break
                }
            }
            switch rank {
            case 0: starts.append(n)
            case 1: contains.append(n)
            case 2: tagged.append(n)
            default: break
            }
        }
        return starts + contains + tagged
    }
}

/// One Lucide icon at `size` points (its 24-point box), in the foreground colour.
struct LucideIcon: View {
    let name: String
    var size: CGFloat = 20

    var body: some View {
        Group {
            if Lucide.registered, let ch = Lucide.character(name) ?? Lucide.character("box") {
                Text(ch).font(.custom(Lucide.family, fixedSize: size))
            } else {
                Image(systemName: "folder").font(.system(size: size * 0.8))
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
