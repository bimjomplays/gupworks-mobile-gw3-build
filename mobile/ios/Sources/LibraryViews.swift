import SwiftUI

// D9's Library tab: the project's pinned notes, its notes folder and what threads made, each opened inside the
// sheet; a note reads as Markdown and is edited as plain text, saved over the version the phone opened.

struct LibraryTab: View {
    let store: ProjectStore

    var body: some View {
        List {
            if let lib = store.library {
                LibraryGroups(groups: lib.groups)
                if lib.groups.allSatisfy({ $0.items.isEmpty }) {
                    LibraryNotice(text: "No notes yet.")
                }
            } else {
                ProgressView().frame(maxWidth: .infinity).padding(.vertical, 30).listRowBackground(Color.clear)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .refreshable { await store.loadLibrary() }
        .task { await store.loadLibrary() }
    }
}

struct LibraryFolderView: View {
    let store: ProjectStore
    let row: LibraryRow
    @State private var list: LibraryList?
    @State private var error: String?

    var body: some View {
        List {
            if let list {
                LibraryGroups(groups: list.groups)
                if list.groups.allSatisfy({ $0.items.isEmpty }) { LibraryNotice(text: "This folder is empty.") }
            } else if let error {
                LibraryNotice(text: error)
            } else {
                ProgressView().frame(maxWidth: .infinity).padding(.vertical, 30).listRowBackground(Color.clear)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .navigationTitle(row.title)
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await load() }
        .task { if list == nil { await load() } }
    }

    private func load() async {
        do {
            list = try await store.folder(row.path)
            error = nil
        } catch {
            self.error = APIError.from(error).message
        }
    }
}

private struct LibraryGroups: View {
    let groups: [LibraryGroup]

    var body: some View {
        ForEach(groups) { g in
            Section {
                ForEach(g.items) { r in
                    NavigationLink(value: r) { LibraryRowView(row: r) }
                        .disabled(!r.exists)
                        .listRowInsets(EdgeInsets(top: 4, leading: 20, bottom: 4, trailing: 16))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .accessibilityIdentifier("lib-\(r.title)")
                }
            } header: {
                if !g.label.isEmpty {
                    HStack {
                        Text(g.label)
                        Spacer()
                        if let n = g.count { Text("\(n)").monospacedDigit() }
                    }
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.section)
                    .textCase(nil)
                }
            }
        }
    }
}

private struct LibraryRowView: View {
    let row: LibraryRow

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 17))
                .foregroundStyle(row.kind == "folder" ? Theme.blue : ChatStyle.dim)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(row.title)
                    .font(.system(size: 17))
                    .foregroundStyle(row.exists ? Theme.rowTitle : ChatStyle.faint)
                    .lineLimit(1)
                Text(row.exists ? row.sub : "Gone from the PC")
                    .font(.system(size: 14))
                    .foregroundStyle(ChatStyle.dim)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    private var icon: String {
        switch row.kind {
        case "folder": return "folder"
        case "image": return "photo"
        case "note": return "doc.text"
        default: return "doc"
        }
    }
}

private struct LibraryNotice: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(ChatStyle.dim)
            .padding(.vertical, 16)
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
    }
}

/// A Library file: a note as Markdown (Edit for plain text), a picture, or the name of a file that opens on the PC.
struct NoteView: View {
    let store: ProjectStore
    let row: LibraryRow
    @State private var file: LibraryFile?
    @State private var error: String?
    @State private var editing = false
    @State private var draft = ""
    @State private var saving = false
    @State private var conflict: Conflict?
    @State private var confirmDiscard = false
    @State private var saved = false
    @FocusState private var focused: Bool

    /// the PC's text when a save found the note changed there
    struct Conflict: Identifiable {
        let theirs: String
        let version: String
        let message: String
        var id: String { version }
    }

    var body: some View {
        content
            .background(Theme.background.opacity(0.001))
            .navigationTitle(file?.title ?? row.title)
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(editing)
            .toolbar { toolbar }
            .task { if file == nil { await load() } }
            .alert("This note changed on the PC", isPresented: Binding(get: { conflict != nil },
                                                                      set: { if !$0 { conflict = nil } }),
                   presenting: conflict) { c in
                Button("Keep mine") { Task { await save(force: true) } }
                Button("Use the PC's") { usePCs(c) }
                Button("Cancel", role: .cancel) {}
            } message: { _ in
                Text("Someone changed it on the PC since you opened it. Keep yours (the PC's change is replaced) "
                     + "or use the PC's (your edit is dropped).")
            }
            .confirmationDialog("Drop your changes?", isPresented: $confirmDiscard, titleVisibility: .visible) {
                Button("Drop changes", role: .destructive) { editing = false }
                Button("Keep editing", role: .cancel) {}
            }
    }

    @ViewBuilder
    private var content: some View {
        if let f = file {
            if editing {
                TextEditor(text: $draft)
                    .font(.system(size: 16, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal, 14)
                    .focused($focused)
                    .accessibilityIdentifier("noteEditor")
            } else if f.kind == "image" {
                RemoteImage(url: MediaLink.url(f.url, base: store.baseURL))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(16)
                    .accessibilityIdentifier("libraryPicture")
            } else if f.text != nil || f.blocks != nil {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        if saved {
                            Label("Saved on the PC", systemImage: "checkmark")
                                .font(.system(size: 13))
                                .foregroundStyle(ChatStyle.done)
                                .accessibilityIdentifier("noteSaved")
                        }
                        if let blocks = f.blocks {
                            MarkdownView(blocks: blocks, base: store.baseURL)
                        } else {
                            Text(f.text ?? "")
                                .font(.system(size: 14, design: .monospaced))
                                .foregroundStyle(ChatStyle.body)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(20)
                }
                .accessibilityIdentifier("noteText")
            } else {
                notice("doc", "\(f.name) opens on the PC.")
            }
        } else if let error {
            notice("exclamationmark.triangle", error)
        } else {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func notice(_ icon: String, _ text: String) -> some View {
        Label(text, systemImage: icon)
            .font(.subheadline)
            .foregroundStyle(ChatStyle.dim)
            .padding(20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        if editing {
            ToolbarItem(placement: .topBarLeading) {
                Button("Cancel") {
                    if draft != file?.text { confirmDiscard = true } else { editing = false }
                }
                .accessibilityIdentifier("noteCancel")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await save(force: false) }
                } label: {
                    if saving { ProgressView() } else { Text("Save") }
                }
                .buttonStyle(.glassProminent)
                .disabled(saving || draft == file?.text)
                .accessibilityIdentifier("noteSave")
            }
        } else if file?.editable == true {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Edit") {
                    draft = file?.text ?? ""
                    saved = false
                    editing = true
                    focused = true
                }
                .accessibilityIdentifier("noteEdit")
            }
        }
    }

    private func load() async {
        do {
            file = try await store.file(row.path)
            error = nil
        } catch {
            self.error = APIError.from(error).message
        }
    }

    private func save(force: Bool) async {
        guard let f = file else { return }
        saving = true
        defer { saving = false }
        do {
            let r = try await store.save(path: f.path, text: draft, version: f.version, force: force)
            file?.text = draft
            file?.version = r.version
            file?.mtime = r.mtime
            file?.blocks = r.blocks
            editing = false
            saved = true
        } catch APIError.conflict(let message, let theirs, let version) {
            conflict = Conflict(theirs: theirs, version: version, message: message)
        } catch {
            store.actionError = APIError.from(error).message
        }
    }

    /// The PC's text wins: your edit goes, and the note is read again (with its pictures).
    private func usePCs(_ c: Conflict) {
        file?.text = c.theirs
        file?.version = c.version
        editing = false
        if store.demo { return }
        Task {
            if let fresh = try? await store.file(row.path) { file = fresh }
        }
    }
}
