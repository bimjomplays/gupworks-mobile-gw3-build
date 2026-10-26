import SwiftUI

/// A project's look: its Lucide icon on its colour (docs/projects-mobile-mockups 01 and 04). Claude's ten swatches,
/// muted to the app's palette; the same names the desktop and the projects service keep.
enum ProjectLook {
    static let colors: [(name: String, hex: UInt32)] = [
        ("grey", 0x9A9A9F), ("red", 0xE5736F), ("orange", 0xE08A52), ("amber", 0xD6A845), ("green", 0x6CBF6C),
        ("teal", 0x4FB3A0), ("blue", 0x6EA8FF), ("violet", 0xA78BFA), ("pink", 0xE07AA8),
    ]

    static func color(_ name: String?) -> Color? {
        guard let name, let c = colors.first(where: { $0.name == name }) else { return nil }
        return Color(hex: c.hex)
    }

    /// the icon picker's first page (the mockup's grid); search reaches every other Lucide icon
    static let grid = ["box", "folder", "code-xml", "database", "server", "flask-conical", "wrench",
                       "chart-column", "users", "book-open", "layers", "file-text", "lightbulb", "palette",
                       "star", "flag", "house", "sun", "moon", "clock", "calendar",
                       "globe", "cloud", "hammer", "key", "shield", "camera", "mic",
                       "coffee", "gift", "ghost", "graduation-cap", "tv", "film", "clapperboard",
                       "gamepad-2", "music", "rocket", "heart", "zap", "bot", "smartphone",
                       "activity", "clipboard-list", "mail", "map-pin", "store", "brain", "target",
                       "bell", "calendar-clock", "notebook-pen", "chart-pie", "hard-drive", "sparkles", "image",
                       "file-video", "users-round", "git-branch", "message-circle", "paperclip", "user", "pin"]

    static let defaultIcon = "box"
    static let plainBackground = Color(hex: 0x1C1C1E)
    static let plainIcon = Color(hex: 0xB4B4B8)
}

/// The project's icon on its colour: a rounded square in lists, a circle in the chat's pill.
struct ProjectTile: View {
    let icon: String?
    let color: String?
    var size: CGFloat = 28
    var iconSize: CGFloat = 17
    var radius: CGFloat = 8
    /// the colour's strength behind the icon (0x33 in lists, 0x24 in the picker)
    var tint: Double = 0x33 / 255

    var body: some View {
        let c = ProjectLook.color(color)
        LucideIcon(name: icon ?? ProjectLook.defaultIcon, size: iconSize)
            .foregroundStyle(c ?? ProjectLook.plainIcon)
            .frame(width: size, height: size)
            .background(c.map { $0.opacity(tint) } ?? ProjectLook.plainBackground,
                        in: RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}

/// 04: pick a colour, then an icon; every Lucide icon by name through the search. Pushed inside New project and
/// Settings; ✓ keeps the pick.
struct IconPickerView: View {
    let icon: String?
    let color: String?
    let done: (String, String?) -> Void
    @State private var pickedIcon: String
    @State private var pickedColor: String?
    @State private var query = ""
    @Environment(\.dismiss) private var dismiss

    init(icon: String?, color: String?, done: @escaping (String, String?) -> Void) {
        self.icon = icon
        self.color = color
        self.done = done
        _pickedIcon = State(initialValue: icon ?? ProjectLook.defaultIcon)
        _pickedColor = State(initialValue: color)
    }

    private var shown: [String] {
        let q = query.trimmingCharacters(in: .whitespaces)
        return q.isEmpty ? ProjectLook.grid : Array(Lucide.search(q).prefix(280))
    }

    var body: some View {
        let tint = ProjectLook.color(pickedColor)
        ScrollView {
            VStack(spacing: 0) {
                swatches
                SheetSearchField(text: $query, prompt: "Search for an icon\u{2026}")
                    .padding(.top, 20)
                    .accessibilityIdentifier("iconSearch")
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7), spacing: 12) {
                    ForEach(shown, id: \.self) { name in
                        let on = name == pickedIcon
                        Button { pickedIcon = name } label: {
                            LucideIcon(name: name, size: 20)
                                .foregroundStyle(tint ?? ProjectLook.plainIcon)
                                .frame(width: 40, height: 40)
                                .background((tint?.opacity(0x24 / 255) ?? Color(hex: 0x2C2C2E)), in: Circle())
                                .overlay {
                                    if on {
                                        Circle().stroke(tint ?? Theme.rowTitle, lineWidth: 1.5).padding(-3.5)
                                    }
                                }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(name)
                        .accessibilityAddTraits(on ? .isSelected : [])
                        .accessibilityIdentifier("icon-\(name)")
                    }
                }
                .padding(.top, 22)
                if shown.isEmpty {
                    Text("No icon has that name.")
                        .font(.system(size: 15)).foregroundStyle(Theme.secondary).padding(.top, 30)
                }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 30)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(SheetStyle.background)
        .navigationTitle("Project icon")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { dismiss() } label: { Image(systemName: "chevron.left") }
                    .accessibilityLabel("Back")
                    .accessibilityIdentifier("iconBack")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    done(pickedIcon, pickedColor)
                    dismiss()
                } label: { Image(systemName: "checkmark") }
                .buttonStyle(.glassProminent)
                .tint(Color(hex: 0xECECEC))
                .foregroundStyle(.black)
                .accessibilityLabel("Done")
                .accessibilityIdentifier("iconDone")
            }
        }
    }

    private var swatches: some View {
        HStack(spacing: 0) {
            swatch(nil)
            ForEach(ProjectLook.colors, id: \.name) { c in
                Spacer(minLength: 0)
                swatch(c.name)
            }
        }
        .padding(.horizontal, -6)
        .padding(.top, 16)
    }

    private func swatch(_ name: String?) -> some View {
        let on = pickedColor == name
        return Button { pickedColor = name } label: {
            ZStack {
                if let c = ProjectLook.color(name) {
                    Circle().fill(c)
                    if on {
                        Image(systemName: "checkmark").font(.system(size: 14, weight: .bold)).foregroundStyle(.white)
                    }
                } else {
                    Circle().fill(Color(hex: 0x2C2C2E))
                    Circle().stroke(on ? Theme.rowTitle : Color(hex: 0x3A3A3C), lineWidth: on ? 1.5 : 1)
                    Image(systemName: "xmark").font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color(hex: 0x7C7C80))
                }
            }
            .frame(width: 34, height: 34)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(name.map { $0.capitalized } ?? "No colour")
        .accessibilityAddTraits(on ? .isSelected : [])
        .accessibilityIdentifier("colour-\(name ?? "none")")
    }
}

/// Claude's sheets (03, 04, 11): a grey card, round buttons, grey rounded fields.
enum SheetStyle {
    static let background = Color(hex: 0x1C1C1E)
    static let field = Color(hex: 0x2C2C2E)
    static let label = Color(hex: 0x98989F)
    static let optional = Color(hex: 0x6C6C70)
    static let separator = Color(hex: 0x3A3A3C)
}

/// "Goal (optional)" over a field
struct SheetLabel: View {
    let text: String
    var optional = false

    var body: some View {
        (Text(text) + (optional ? Text(" (optional)").foregroundStyle(SheetStyle.optional) : Text("")))
            .font(.system(size: 15))
            .foregroundStyle(SheetStyle.label)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8)
            .padding(.top, 18)
            .padding(.bottom, 8)
    }
}

struct SheetSearchField: View {
    @Binding var text: String
    let prompt: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").font(.system(size: 17)).foregroundStyle(SheetStyle.optional)
            TextField(prompt, text: $text)
                .font(.system(size: 16.5))
                .foregroundStyle(Theme.rowTitle)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .submitLabel(.search)
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(SheetStyle.optional)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear")
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 48)
        .background(SheetStyle.field, in: Capsule())
        .overlay(Capsule().stroke(Color(hex: 0x333336), lineWidth: 1))
    }
}

/// A grouped card of rows (Folder, Usage, Pause…), as Claude's settings.
struct SheetGroup<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(spacing: 0) { content() }
            .background(SheetStyle.field, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}

/// One row of a SheetGroup: icon, words, value on the right; `divider` draws the line above it.
struct SheetRow<Trailing: View>: View {
    let icon: String
    let text: String
    var color: Color = Theme.rowTitle
    var divider = false
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 13) {
            LucideIcon(name: icon, size: 21).foregroundStyle(color == Theme.rowTitle ? ProjectLook.plainIcon : color)
            Text(text).font(.system(size: 17)).foregroundStyle(color).lineLimit(1)
            Spacer(minLength: 8)
            trailing()
                .font(.system(size: 16))
                .foregroundStyle(Color(hex: 0x8E8E93))
                .lineLimit(1)
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 50)
        .contentShape(Rectangle())
        .overlay(alignment: .top) {
            if divider {
                Rectangle().fill(SheetStyle.separator).frame(height: 1).padding(.leading, 50).padding(.trailing, 16)
            }
        }
    }
}

/// a chevron on a row's right
struct RowChevron: View {
    var body: some View {
        Image(systemName: "chevron.right").font(.system(size: 14, weight: .semibold)).foregroundStyle(Color(hex: 0x6C6C70))
    }
}
