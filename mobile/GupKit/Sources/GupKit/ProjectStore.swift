import Foundation
import Observation

/// D9's data for one project: the threads view (live from the PC's project stream while the main chat is open),
/// the Library and the Scheduled list. Every change goes through gw3-phone to the projects service, as the
/// desktop panel's own calls; the demo answers itself from mobile/fixtures/projects/<id>.json.
@Observable
@MainActor
final class ProjectStore {
    let id: String
    private(set) var view: ProjectView?
    private(set) var library: LibraryList?
    private(set) var schedules: ScheduleList?
    private(set) var ideas: IdeasList?
    private(set) var error: APIError?
    /// a move or new thread the PC refused or never got, for an alert
    var actionError: String?
    /// threads with a move on its way (their row shows a spinner)
    private(set) var busy: Set<String> = []

    let pairing: Pairing?
    let demo: Bool
    private let api = APIClient()
    private var fixture: ProjectFixture?

    init(id: String, pairing: Pairing?, demo: Bool) {
        self.id = id
        self.pairing = pairing
        self.demo = demo
    }

    var baseURL: URL? { pairing.map { Routes.shared.current(for: $0.baseURL) } }  // where pictures load now

    /// Loads the view, then follows the project's event stream until the task is cancelled.
    func follow() async {
        if demo {
            loadDemo()
            return
        }
        guard let p = pairing else { return }
        var wait: UInt64 = 1
        while !Task.isCancelled {
            do {
                for try await e in api.events(p, "/v1/projects/\(id)/events") {
                    let data = Data(e.data.utf8)
                    if e.name == "project", let v = try? JSONDecoder().decode(ProjectView.self, from: data) {
                        view = v
                        error = nil
                    } else if e.name == "error", let b = try? JSONDecoder().decode([String: String].self, from: data) {
                        error = .server(b["error"] ?? "The projects service didn't answer.")
                    }
                    wait = 1
                }
            } catch is CancellationError {
                return
            } catch let e as APIError {
                if Task.isCancelled { return }
                error = e
                if e == .notPaired { return }
            } catch {
                if Task.isCancelled { return }
            }
            try? await Task.sleep(nanoseconds: wait * 1_000_000_000)
            wait = min(wait * 2, 15)
        }
    }

    /// The view once (pull to refresh).
    func refresh() async {
        if demo { return loadDemo() }
        guard let p = pairing else { return }
        do {
            view = try await api.project(p, id)
            error = nil
        } catch {
            let e = APIError.from(error)
            if Task.isCancelled || e.isCancelled { return }
            self.error = e
        }
    }

    // MARK: threads

    /// A thread menu or swipe action; the row moves at once in the demo, else when the PC's view comes back.
    func move(_ move: String, thread: String) async {
        if demo {
            if let v = view { view = DemoProject.apply(move, to: thread, in: v) }
            return
        }
        guard let p = pairing else { return }
        busy.insert(thread)
        defer { busy.remove(thread) }
        do {
            view = try await api.moveThread(p, project: id, thread: thread, move)
        } catch {
            actionError = APIError.from(error).message
        }
    }

    /// Starts your own thread with its first message; true when the PC started it.
    func newThread(_ text: String) async -> Bool {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return false }
        if demo {
            if let v = view { view = DemoProject.add(text, to: v) }
            return true
        }
        guard let p = pairing else { return false }
        do {
            view = try await api.newThread(p, project: id, text: text).project
            return true
        } catch {
            actionError = APIError.from(error).message
            return false
        }
    }

    /// The project ⋯ menu's Pause / Resume and Archive.
    func setPaused(_ on: Bool) async {
        if demo { view?.paused = on; return }
        guard let p = pairing else { return }
        do {
            view = try await api.pauseProject(p, id, on)
        } catch {
            actionError = APIError.from(error).message
        }
    }

    func setArchived(_ on: Bool) async -> Bool {
        if demo { view?.archived = on; return true }
        guard let p = pairing else { return false }
        do {
            view = try await api.archiveProject(p, id, on)
            return true
        } catch {
            actionError = APIError.from(error).message
            return false
        }
    }

    // MARK: Library and Scheduled

    func loadLibrary() async {
        if demo { library = library ?? fixture?.library; return }
        guard let p = pairing else { return }
        do {
            library = try await api.library(p, project: id)
        } catch {
            actionError = APIError.from(error).message
        }
    }

    func folder(_ path: String) async throws -> LibraryList {
        if demo {
            guard let f = fixture?.folders[path] else { throw APIError.server("This folder is gone.") }
            return f
        }
        guard let p = pairing else { throw APIError.notPaired }
        return try await api.library(p, project: id, folder: path)
    }

    func file(_ path: String) async throws -> LibraryFile {
        if demo {
            guard let f = fixture?.files[path] else { throw APIError.server("This file is gone.") }
            return f
        }
        guard let p = pairing else { throw APIError.notPaired }
        return try await api.libraryFile(p, project: id, path: path)
    }

    /// Saves a note over `version` (the text the phone opened); `force` saves over a change made on the PC.
    func save(path: String, text: String, version: String?, force: Bool = false) async throws -> NoteSaved {
        if demo {
            // the demo's note "changed on the PC" once, so the conflict can be seen (`-noteConflict`)
            if !force, Self.demoConflict, !demoConflicted.contains(path) {
                demoConflicted.insert(path)
                let theirs = (fixture?.files[path]?.text ?? "") + "\n- Added on the PC meanwhile\n"
                throw APIError.conflict("This note changed on the PC since you opened it.", theirs: theirs,
                                        version: "pc")
            }
            fixture?.files[path]?.text = text
            fixture?.files[path]?.blocks = DemoProject.blocks(text)
            return NoteSaved(ok: true, path: path, version: "demo-\(text.count)", mtime: Date().timeIntervalSince1970 * 1000,
                             blocks: DemoProject.blocks(text))
        }
        guard let p = pairing else { throw APIError.notPaired }
        return try await api.saveNote(p, project: id, NoteSave(path: path, text: text, version: version,
                                                                force: force ? true : nil))
    }

    func loadSchedules() async {
        if demo { schedules = schedules ?? fixture?.schedules; return }
        guard let p = pairing else { return }
        do {
            schedules = try await api.schedules(p, project: id)
        } catch {
            actionError = APIError.from(error).message
        }
    }

    /// run | pause | resume one schedule (Scheduled's swipes, 10)
    func scheduleMove(_ schedule: String, _ move: String) async {
        if demo {
            guard var s = schedules else { return }
            for g in s.groups.indices {
                for i in s.groups[g].items.indices where s.groups[g].items[i].id == schedule {
                    switch move {
                    case "pause": s.groups[g].items[i].paused = true
                    case "resume": s.groups[g].items[i].paused = false
                    case "run": s.groups[g].items[i].running = true
                    default: break
                    }
                }
            }
            schedules = DemoProject.regroupSchedules(s)
            return
        }
        guard let p = pairing else { return }
        do {
            schedules = try await api.scheduleMove(p, project: id, schedule: schedule, move)
        } catch {
            actionError = APIError.from(error).message
        }
    }

    // MARK: Ideas (09) and adding to the Library (08)

    func loadIdeas() async {
        if demo { loadDemo(); ideas = ideas ?? fixture?.ideas; return }
        guard let p = pairing else { return }
        do {
            ideas = try await api.ideas(p, project: id)
        } catch {
            actionError = APIError.from(error).message
        }
    }

    /// Adds an idea under "Ideas for later" (the bottom bar); true when it was saved.
    func addIdea(_ text: String, section: String = "Ideas for later") async -> Bool {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return false }
        if demo {
            guard var l = ideas else { return false }
            let item = IdeaItem(raw: text, text: text, date: nil, ai: false)
            if let i = l.sections.firstIndex(where: { $0.name == section }) {
                l.sections[i].items.append(item)
            } else {
                l.sections.append(IdeasSection(name: section, items: [item], empty: ""))
            }
            l.count += 1
            ideas = l
            return true
        }
        guard let p = pairing else { return false }
        do {
            ideas = try await api.addIdea(p, project: id, text: text, section: section)
            return true
        } catch {
            actionError = APIError.from(error).message
            return false
        }
    }

    /// Edits, deletes or moves one idea.
    func changeIdea(_ c: IdeaChange) async {
        if demo {
            if let l = ideas { ideas = DemoProject.change(c, in: l) }
            return
        }
        guard let p = pairing else { return }
        do {
            ideas = try await api.changeIdea(p, project: id, c)
        } catch {
            actionError = APIError.from(error).message
        }
    }

    /// Photos or files from the phone, copied into the project's notes folder; true when they all went in.
    func addToLibrary(_ files: [Attachment]) async -> Bool {
        guard !files.isEmpty else { return false }
        if demo {
            guard var l = library else { return false }
            let rows = files.map { a in
                LibraryRow(path: "/Notes/Demo/\(a.name)", kind: a.type.hasPrefix("image/") ? "image" : "file",
                           title: a.name, sub: "just now", mtime: Date().timeIntervalSince1970 * 1000, exists: true,
                           workId: nil, editable: false, thumb: nil, url: nil, group: "notes")
            }
            if let i = l.groups.firstIndex(where: { $0.id == "notes" }) {
                l.groups[i].items.insert(contentsOf: rows, at: 0)
            } else {
                l.groups.append(LibraryGroup(id: "notes", label: "Notes", count: rows.count, items: rows))
            }
            l.count += rows.count
            library = l
            return true
        }
        guard let p = pairing else { return false }
        do {
            var paths: [String] = []
            for a in files {
                paths.append(try await api.upload(p, a.data, name: a.name, type: a.type,
                                                  chat: view?.mainChatId ?? "new").path)
            }
            library = try await api.libraryAdd(p, project: id, files: paths).library
            return true
        } catch {
            actionError = APIError.from(error).message
            return false
        }
    }

    // MARK: demo

    private static var demoConflict: Bool { Demo.args.contains("-noteConflict") }
    private var demoConflicted: Set<String> = []

    private func loadDemo() {
        if fixture == nil { fixture = Demo.load(id, in: "fixtures/projects") }
        guard let f = fixture else {
            error = .server("No such project.")
            return
        }
        if view == nil { view = f.view }
    }
}
