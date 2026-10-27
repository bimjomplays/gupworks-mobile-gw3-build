import PhotosUI
import SwiftUI

/// 03: Claude's new-project sheet. A name (the keyboard up at once) with its icon (04), a goal, files for the
/// Library, and the folder: new in the projects folder or one already there. ✓ makes it on the PC and opens its main chat,
/// which asks a few questions and sets it up.
struct NewProjectSheet: View {
    let created: (NewProjectReply) -> Void
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var goal = ""
    @State private var icon: String?
    @State private var color: String?
    @State private var files: [Attachment] = []
    @State private var folders: FoldersReply?
    @State private var folder = "new"
    @State private var pickingPhotos = false
    @State private var pickingFiles = false
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var pickIcon: Bool
    @State private var creating = false
    @State private var problem: String?
    @State private var clientId = UUID().uuidString.lowercased()
    @FocusState private var nameFocused: Bool

    init(created: @escaping (NewProjectReply) -> Void) {
        self.created = created
        _pickIcon = State(initialValue: Demo.isOn && Demo.args.contains("-iconPicker"))
        if Demo.isOn, Demo.args.contains("-iconPicker") {
            _icon = State(initialValue: "clapperboard")
            _color = State(initialValue: "red")
        }
    }

    private var ready: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty && !creating }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    SheetLabel(text: "Name")
                    nameField
                    SheetLabel(text: "Goal", optional: true)
                    TextField("", text: $goal,
                              prompt: Text("Track my TV, films and books, all on my PC").foregroundStyle(SheetStyle.optional),
                              axis: .vertical)
                        .lineLimit(2...6)
                        .font(.system(size: 17))
                        .foregroundStyle(Theme.rowTitle)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 15)
                        .frame(minHeight: 74, alignment: .topLeading)
                        .background(SheetStyle.field, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                        .accessibilityIdentifier("newGoal")
                    SheetLabel(text: "Files", optional: true)
                    addFiles
                    if !files.isEmpty {
                        AttachmentStrip(attachments: $files).padding(.horizontal, -16).padding(.top, 8)
                    }
                    folderRow.padding(.top, 14)
                    if let problem {
                        Text(problem)
                            .font(.system(size: 15))
                            .foregroundStyle(Theme.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 8)
                            .padding(.top, 14)
                            .accessibilityIdentifier("newProblem")
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 30)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(SheetStyle.background)
            .navigationTitle("New project")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel("Close")
                        .accessibilityIdentifier("newClose")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    SheetDoneButton(on: ready, busy: creating, id: "newCreate", label: "Create") { create() }
                }
            }
            .navigationDestination(isPresented: $pickIcon) {
                IconPickerView(icon: icon, color: color) { i, c in
                    icon = i
                    color = c
                }
            }
        }
        .presentationDetents([.large])
        .presentationBackground(SheetStyle.background)
        .interactiveDismissDisabled(creating)
        .photosPicker(isPresented: $pickingPhotos, selection: $photoItems, maxSelectionCount: 10, matching: .images)
        .onChange(of: photoItems) { _, items in loadPhotos(items) }
        .fileImporter(isPresented: $pickingFiles, allowedContentTypes: [.item], allowsMultipleSelection: true) { r in
            guard case .success(let urls) = r else { return }
            for url in urls {
                guard files.count < 10 else { problem = "Up to 10 files."; return }
                switch Attachment.file(url) {
                case .success(let a): files.append(a)
                case .failure(let e): problem = e.message
                }
            }
        }
        .task {
            if !pickIcon { nameFocused = true }
            folders = await model.projectFolders()
        }
    }

    private var nameField: some View {
        HStack(spacing: 12) {
            Button { pickIcon = true } label: {
                ProjectTile(icon: icon, color: color, size: 40, iconSize: 21, radius: 12)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Project icon")
            .accessibilityIdentifier("newIcon")
            TextField("", text: $name, prompt: Text("Project name\u{2026}").foregroundStyle(SheetStyle.optional))
                .font(.system(size: 17))
                .foregroundStyle(Theme.rowTitle)
                .focused($nameFocused)
                .submitLabel(.done)
                .onSubmit { if ready { create() } }
                .accessibilityIdentifier("newName")
        }
        .padding(.leading, 8)
        .padding(.trailing, 16)
        .frame(minHeight: 56)
        .background(SheetStyle.field, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
    }

    private var addFiles: some View {
        Menu {
            Button("Photos", systemImage: "photo.on.rectangle") { pickingPhotos = true }
            Button("Files", systemImage: "folder") { pickingFiles = true }
        } label: {
            HStack(spacing: 14) {
                LucideIcon(name: "plus", size: 22)
                Text("Add files").font(.system(size: 17))
                Spacer()
            }
            .foregroundStyle(Theme.rowTitle)
            .padding(.horizontal, 16)
            .frame(height: 56)
            .background(SheetStyle.field, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
            .contentShape(Rectangle())
        }
        .accessibilityIdentifier("newFiles")
    }

    private var folderText: String {
        if folder == "new" { return "New in \(folders?.root ?? "Projects")" }
        return folders?.folders.first { $0.path == folder }?.name ?? folder
    }

    private var folderRow: some View {
        Menu {
            Button("New in \(folders?.root ?? "Projects")", systemImage: folder == "new" ? "checkmark" : "plus") {
                folder = "new"
            }
            if let list = folders?.folders, !list.isEmpty {
                Section("A folder you have") {
                    ForEach(list) { f in
                        Button {
                            folder = f.path
                        } label: {
                            if folder == f.path { Label(f.name, systemImage: "checkmark") } else { Text(f.name) }
                            Text(f.project.map { "Already \($0)" } ?? f.short)
                        }
                        .disabled(f.project != nil)
                    }
                }
            }
        } label: {
            HStack(spacing: 14) {
                LucideIcon(name: "hard-drive", size: 22).foregroundStyle(ProjectLook.plainIcon)
                Text("Folder").font(.system(size: 17)).foregroundStyle(Theme.rowTitle)
                Spacer(minLength: 8)
                Text(folderText).font(.system(size: 17)).foregroundStyle(Color(hex: 0x8E8E93)).lineLimit(1)
                Image(systemName: "chevron.up.chevron.down").font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color(hex: 0x8E8E93))
            }
            .padding(.horizontal, 16)
            .frame(height: 56)
            .background(SheetStyle.field, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
            .contentShape(Rectangle())
        }
        .accessibilityIdentifier("newFolder")
    }

    private func loadPhotos(_ items: [PhotosPickerItem]) {
        guard !items.isEmpty else { return }
        photoItems = []
        Task {
            for item in items {
                guard files.count < 10 else { problem = "Up to 10 files."; return }
                if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data),
                   let a = Attachment.photo(image, name: "photo.jpg") {
                    files.append(a)
                } else {
                    problem = "That photo couldn't be read."
                }
            }
        }
    }

    private func create() {
        guard ready else { return }
        creating = true
        problem = nil
        Task {
            do {
                let r = try await model.createProject(name: name.trimmingCharacters(in: .whitespaces),
                                                      goal: goal.trimmingCharacters(in: .whitespacesAndNewlines),
                                                      icon: icon, color: color, folder: folder, files: files,
                                                      clientId: clientId)
                dismiss()
                created(r)
            } catch {
                problem = APIError.from(error).message
            }
            creating = false
        }
    }
}

/// A sheet's ✓ (03, 11): grey until there's something to save, then white with a black check.
struct SheetDoneButton: View {
    let on: Bool
    var busy = false
    let id: String
    var label = "Done"
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            if busy {
                ProgressView().tint(.black)
            } else {
                Image(systemName: "checkmark").foregroundStyle(on ? Color.black : Color(hex: 0x7C7C80))
            }
        }
        .buttonStyle(.glassProminent)
        .tint(on ? Color(hex: 0xECECEC) : Color(hex: 0x3A3A3C))
        .allowsHitTesting(on && !busy)
        .accessibilityLabel(label)
        .accessibilityAddTraits(on ? [] : .isStaticText)
        .accessibilityIdentifier(id)
    }
}

/// 11: the project's own settings, laid out as Claude's: name and icon, goal, instructions; the folder, parts and
/// models; usage (12), pause, archive and delete. ✓ saves what changed.
struct ProjectSettingsSheet: View {
    let projectId: String
    /// it was archived or deleted: whoever opened it leaves the project
    var left: (() -> Void)?
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openChat) private var openChat
    @State private var saved: ProjectSettings?
    @State private var loadError: String?
    @State private var name = ""
    @State private var goal = ""
    @State private var instructions = ""
    @State private var icon: String?
    @State private var color: String?
    @State private var mainModel = ""
    @State private var mainEffort = ""
    /// nil: unchanged; "": Automatic; else every thread on that model
    @State private var threadModel: String?
    @State private var threadEffort = ""
    @State private var saving = false
    @State private var problem: String?
    @State private var pickIcon = false
    @State private var showUsage: Bool
    @State private var confirmDelete = false
    @State private var deleteWord = ""

    init(projectId: String, left: (() -> Void)? = nil) {
        self.projectId = projectId
        self.left = left
        _showUsage = State(initialValue: Demo.isOn && Demo.args.contains("-usage"))
    }

    var body: some View {
        NavigationStack {
            Group {
                if let s = saved {
                    form(s)
                } else if let loadError {
                    Text(loadError).font(.system(size: 15)).foregroundStyle(Theme.secondary)
                        .multilineTextAlignment(.center).padding(30)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .background(SheetStyle.background)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel("Close")
                        .accessibilityIdentifier("settingsClose")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    SheetDoneButton(on: patch != nil && !saving, busy: saving, id: "settingsSave", label: "Save") {
                        save()
                    }
                }
            }
            .navigationDestination(isPresented: $pickIcon) {
                IconPickerView(icon: icon, color: color) { i, c in
                    icon = i
                    color = c
                }
            }
            .navigationDestination(isPresented: $showUsage) {
                ProjectUsageView(projectId: projectId) { chatId in
                    dismiss()
                    openChat?(chatId)
                }
            }
        }
        .presentationDetents([.large])
        .presentationBackground(SheetStyle.background)
        .task { await load() }
        .alert("Delete \(saved?.name ?? "this project")?", isPresented: $confirmDelete) {
            TextField("delete", text: $deleteWord)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Button("Cancel", role: .cancel) { deleteWord = "" }
            Button("Delete", role: .destructive) { delete() }
                .disabled(deleteWord.trimmingCharacters(in: .whitespaces).lowercased() != "delete")
        } message: {
            Text("Its threads and settings go. The folder and notes stay on your PC. Type delete to delete it.")
        }
    }

    private func form(_ s: ProjectSettings) -> some View {
        ScrollView {
            VStack(spacing: 0) {
                SheetLabel(text: "Name")
                HStack(spacing: 12) {
                    Button { pickIcon = true } label: {
                        ProjectTile(icon: icon, color: color, size: 40, iconSize: 21, radius: 12)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Project icon")
                    .accessibilityIdentifier("settingsIcon")
                    TextField("", text: $name, prompt: Text("Project name\u{2026}").foregroundStyle(SheetStyle.optional))
                        .font(.system(size: 17))
                        .foregroundStyle(Theme.rowTitle)
                        .accessibilityIdentifier("settingsName")
                }
                .padding(.leading, 8)
                .padding(.trailing, 16)
                .frame(minHeight: 56)
                .background(SheetStyle.field, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
                SheetLabel(text: "Goal")
                area($goal, prompt: "What the project is for", id: "settingsGoal")
                SheetLabel(text: "Instructions")
                area($instructions, prompt: "Rules every chat in the project follows", id: "settingsInstructions")
                SheetGroup {
                    NavigationLink {
                        FolderInfoView(settings: s)
                    } label: {
                        SheetRow(icon: "hard-drive", text: "Folder") {
                            HStack(spacing: 8) {
                                Text(s.folder.isEmpty ? "None" : s.folder).truncationMode(.head)
                                RowChevron()
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("settingsFolder")
                    NavigationLink {
                        PartsView(parts: s.parts)
                    } label: {
                        SheetRow(icon: "layers", text: "Parts", divider: true) {
                            HStack(spacing: 8) {
                                Text(s.parts.isEmpty ? "None" : s.parts.count == 1 ? s.parts[0] : "\(s.parts.count)")
                                RowChevron()
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("settingsParts")
                    mainModelRow(s)
                    threadModelRow(s)
                }
                .padding(.top, 14)
                SheetGroup {
                    Button { showUsage = true } label: {
                        SheetRow(icon: "chart-pie", text: "Usage") {
                            HStack(spacing: 8) {
                                Text(s.usage)
                                RowChevron()
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("settingsUsage")
                    Button { pause(!s.paused) } label: {
                        SheetRow(icon: s.paused ? "play" : "pause", text: s.paused ? "Resume project" : "Pause project",
                                 divider: true) { EmptyView() }
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("settingsPause")
                    Button { archive(!s.archived) } label: {
                        SheetRow(icon: s.archived ? "archive-restore" : "archive",
                                 text: s.archived ? "Unarchive" : "Archive", divider: true) { EmptyView() }
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("settingsArchive")
                    Button {
                        deleteWord = ""
                        confirmDelete = true
                    } label: {
                        SheetRow(icon: "trash-2", text: "Delete", color: Color(hex: 0xF07470), divider: true) {
                            EmptyView()
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("settingsDelete")
                }
                .padding(.top, 14)
                if let problem {
                    Text(problem)
                        .font(.system(size: 15))
                        .foregroundStyle(Theme.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 8)
                        .padding(.top, 14)
                        .accessibilityIdentifier("settingsProblem")
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 30)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private func area(_ text: Binding<String>, prompt: String, id: String) -> some View {
        TextField("", text: text, prompt: Text(prompt).foregroundStyle(SheetStyle.optional), axis: .vertical)
            .lineLimit(1...8)
            .font(.system(size: 17))
            .foregroundStyle(Theme.rowTitle)
            .padding(.horizontal, 18)
            .padding(.vertical, 15)
            .frame(maxWidth: .infinity, minHeight: 56, alignment: .topLeading)
            .background(SheetStyle.field, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .accessibilityIdentifier(id)
    }

    private func label(_ id: String, _ effort: String, in s: ProjectSettings) -> String {
        let name = s.models.first { $0.id == id }?.label ?? id
        return [name, effort].filter { !$0.isEmpty }.joined(separator: " \u{00B7} ")
    }

    private func mainModelRow(_ s: ProjectSettings) -> some View {
        Menu {
            ForEach(s.models) { m in
                Menu(m.label) {
                    ForEach(m.efforts, id: \.self) { e in
                        Button {
                            mainModel = m.id
                            mainEffort = e
                        } label: {
                            if mainModel == m.id && mainEffort == e { Label(e, systemImage: "checkmark") } else { Text(e) }
                        }
                    }
                }
            }
        } label: {
            SheetRow(icon: "brain", text: "Main chat", divider: true) {
                HStack(spacing: 8) {
                    Text(mainModel.isEmpty ? (s.mainLabel.isEmpty ? "Default" : s.mainLabel)
                                           : label(mainModel, mainEffort, in: s))
                    Image(systemName: "chevron.up.chevron.down").font(.system(size: 13, weight: .semibold))
                }
            }
        }
        .accessibilityIdentifier("settingsMainModel")
    }

    private func threadModelRow(_ s: ProjectSettings) -> some View {
        Menu {
            Button {
                threadModel = ""
                threadEffort = ""
            } label: {
                Text("Automatic")
                Text("The main chat picks for each job")
            }
            ForEach(s.models) { m in
                Menu(m.label) {
                    ForEach(m.efforts, id: \.self) { e in
                        Button(e) {
                            threadModel = m.id
                            threadEffort = e
                        }
                    }
                }
            }
        } label: {
            SheetRow(icon: "sparkles", text: "Thread models", divider: true) {
                HStack(spacing: 8) {
                    Text(threadText(s))
                    Image(systemName: "chevron.up.chevron.down").font(.system(size: 13, weight: .semibold))
                }
            }
        }
        .accessibilityIdentifier("settingsThreadModels")
    }

    private func threadText(_ s: ProjectSettings) -> String {
        guard let t = threadModel else { return s.threadLabel }
        return t.isEmpty ? "Automatic" : label(t, threadEffort, in: s)
    }

    /// what ✓ sends: only what changed (nil when nothing did)
    private var patch: ProjectPatch? {
        guard let s = saved else { return nil }
        var p = ProjectPatch()
        var any = false
        let n = name.trimmingCharacters(in: .whitespaces)
        if n != s.name && !n.isEmpty { p.name = n; any = true }
        if goal != s.goal { p.goal = goal; any = true }
        if instructions != s.instructions { p.instructions = instructions; any = true }
        if icon != s.icon { p.icon = icon ?? ProjectLook.defaultIcon; any = true }
        if color != s.color { p.color = color ?? ""; any = true }
        if !mainModel.isEmpty && (mainModel != s.mainModel || mainEffort != s.mainEffort) {
            p.mainModel = mainModel
            p.mainEffort = mainEffort
            any = true
        }
        if let t = threadModel {
            p.threadModel = t
            p.threadEffort = threadEffort
            any = true
        }
        return any ? p : nil
    }

    private func show(_ s: ProjectSettings) {
        saved = s
        name = s.name
        goal = s.goal
        instructions = s.instructions
        icon = s.icon
        color = s.color
        mainModel = s.mainModel
        mainEffort = s.mainEffort
        threadModel = nil
        threadEffort = ""
    }

    private func load() async {
        do {
            show(try await model.projectSettings(projectId))
        } catch {
            loadError = APIError.from(error).message
        }
    }

    private func save() {
        guard let p = patch else { return }
        saving = true
        problem = nil
        Task {
            do {
                show(try await model.updateProject(projectId, p))
                dismiss()
            } catch {
                problem = APIError.from(error).message
            }
            saving = false
        }
    }

    private func pause(_ on: Bool) {
        Task {
            do {
                try await model.pauseProject(projectId, on)
                saved?.paused = on
            } catch {
                problem = APIError.from(error).message
            }
        }
    }

    private func archive(_ on: Bool) {
        Task {
            await model.setArchived(project: projectId, on)
            saved?.archived = on
            if on {
                dismiss()
                left?()
            }
        }
    }

    private func delete() {
        Task {
            do {
                try await model.deleteProject(projectId)
                dismiss()
                left?()
            } catch {
                problem = APIError.from(error).message
            }
        }
    }
}

/// Settings' Folder: where the project's code and its notes live on the PC.
private struct FolderInfoView: View {
    let settings: ProjectSettings

    var body: some View {
        ScrollView {
            SheetGroup {
                SheetRow(icon: "hard-drive", text: "Folder") { Text(settings.folder.isEmpty ? "None" : settings.folder) }
                SheetRow(icon: "notebook-pen", text: "Notes", divider: true) { Text(settings.notes) }
            }
            .padding(16)
            Text("Threads work in their own copies of this folder and land their changes in it.")
                .font(.system(size: 15))
                .foregroundStyle(SheetStyle.label)
                .padding(.horizontal, 24)
        }
        .background(SheetStyle.background)
        .navigationTitle("Folder")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Settings' Parts: the pieces a project is split into (an app's iPhone and Apple TV sides).
private struct PartsView: View {
    let parts: [String]

    var body: some View {
        ScrollView {
            if parts.isEmpty {
                Text("No parts. The main chat splits the project into parts when it gets big enough to need them.")
                    .font(.system(size: 15))
                    .foregroundStyle(SheetStyle.label)
                    .padding(24)
            } else {
                SheetGroup {
                    ForEach(Array(parts.enumerated()), id: \.offset) { i, p in
                        SheetRow(icon: "layers", text: p, divider: i > 0) { EmptyView() }
                    }
                }
                .padding(16)
            }
        }
        .background(SheetStyle.background)
        .navigationTitle("Parts")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// 12: what the project used, from its chats' transcripts: the total, main chat against threads, by model, the
/// biggest threads (a tap opens one) and the plan's limits.
struct ProjectUsageView: View {
    let projectId: String
    let openThread: (String) -> Void
    @Environment(AppModel.self) private var model
    @State private var usage: ProjectUsage?
    @State private var error: String?

    var body: some View {
        ScrollView {
            if let u = usage {
                content(u)
            } else if let error {
                Text(error).font(.system(size: 15)).foregroundStyle(Theme.secondary).padding(30)
            } else {
                ProgressView().padding(.top, 60)
            }
        }
        .background(SheetStyle.background)
        .navigationTitle("Usage")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            do { usage = try await model.projectUsage(projectId) } catch { self.error = APIError.from(error).message }
        }
    }

    private func content(_ u: ProjectUsage) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(u.totalText)
                .font(.system(size: 36, weight: .bold))
                .foregroundStyle(Theme.title)
                .padding(.horizontal, 8)
                .padding(.top, 18)
                .accessibilityIdentifier("usageTotal")
            Text(u.since)
                .font(.system(size: 15))
                .foregroundStyle(SheetStyle.label)
                .padding(.horizontal, 8)
                .padding(.top, 4)
            if u.total > 0 {
                GeometryReader { geo in
                    let main = geo.size.width * CGFloat(u.main / u.total)
                    HStack(spacing: 0) {
                        Rectangle().fill(Theme.blue).frame(width: main)
                        Rectangle().fill(Theme.violet)
                    }
                    .clipShape(Capsule())
                }
                .frame(height: 8)
                .padding(.horizontal, 8)
                .padding(.top, 16)
                HStack(spacing: 18) {
                    legend(Theme.blue, "Main chat \(u.mainText)")
                    legend(Theme.violet, "Threads \(u.threadsText)")
                }
                .padding(.horizontal, 8)
                .padding(.top, 12)
            }
            if !u.models.isEmpty {
                SheetLabel(text: "By model").padding(.top, 8)
                SheetGroup {
                    ForEach(Array(u.models.enumerated()), id: \.offset) { i, m in
                        VStack(spacing: 10) {
                            HStack {
                                Text(m.name).foregroundStyle(Theme.rowTitle)
                                Spacer()
                                Text("\(m.value) \u{00B7} \(m.percent)%").foregroundStyle(Color(hex: 0x8E8E93))
                            }
                            .font(.system(size: 17))
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    Capsule().fill(Color(hex: 0x3A3A3C))
                                    Capsule().fill(Color(hex: 0xD8D8DC))
                                        .frame(width: geo.size.width * CGFloat(min(max(m.percent, 1), 100)) / 100)
                                }
                            }
                            .frame(height: 6)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                        .overlay(alignment: .top) {
                            if i > 0 {
                                Rectangle().fill(SheetStyle.separator).frame(height: 1).padding(.horizontal, 16)
                            }
                        }
                    }
                }
            }
            if !u.biggest.isEmpty {
                SheetLabel(text: "Biggest threads").padding(.top, 8)
                SheetGroup {
                    ForEach(Array(u.biggest.enumerated()), id: \.offset) { i, b in
                        Button { if let c = b.chatId { openThread(c) } } label: {
                            HStack(spacing: 14) {
                                ThreadMark(glyph: b.glyph)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(b.title).font(.system(size: 17)).foregroundStyle(Theme.rowTitle).lineLimit(1)
                                    Text(b.line).font(.system(size: 15)).foregroundStyle(Color(hex: 0x8E8E93))
                                        .lineLimit(1)
                                }
                                Spacer(minLength: 8)
                                Text(b.value).font(.system(size: 16)).foregroundStyle(Color(hex: 0x8E8E93))
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .contentShape(Rectangle())
                            .overlay(alignment: .top) {
                                if i > 0 {
                                    Rectangle().fill(SheetStyle.separator).frame(height: 1)
                                        .padding(.leading, 52).padding(.trailing, 16)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .disabled(b.chatId == nil)
                        .accessibilityIdentifier("biggest-\(b.id)")
                    }
                }
            }
            if !u.footer.isEmpty {
                Text(u.footer)
                    .font(.system(size: 15))
                    .foregroundStyle(SheetStyle.label)
                    .padding(.horizontal, 8)
                    .padding(.top, 16)
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 30)
    }

    private func legend(_ c: Color, _ text: String) -> some View {
        HStack(spacing: 7) {
            Circle().fill(c).frame(width: 8, height: 8)
            Text(text).font(.system(size: 16)).foregroundStyle(SheetStyle.label)
        }
    }
}

/// a121's thread marks (05-08, 12): a green tick for landed or done, the spinner while working, violet for
/// needs you; the panel's others otherwise.
struct ThreadMark: View {
    let glyph: String
    var size: CGFloat = 22

    var body: some View {
        Group {
            switch glyph {
            case "check":
                Image(systemName: "checkmark")
                    .font(.system(size: size * 0.5, weight: .bold))
                    .foregroundStyle(Color(hex: 0x0E2A12))
                    .frame(width: size, height: size)
                    .background(Color(hex: 0x5DB868), in: Circle())
                    .accessibilityLabel("Done")
            case "spin":
                Spinner().scaleEffect(size / 16 * 0.9)
            case "needs":
                Circle().fill(Theme.violet).frame(width: size * 0.45, height: size * 0.45)
                    .accessibilityLabel("Needs you")
            default:
                Glyph(name: glyph, size: size * 0.7)
            }
        }
        .frame(width: size, height: size)
    }
}
