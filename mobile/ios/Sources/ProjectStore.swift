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

    var baseURL: URL? { pairing?.baseURL }

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
            self.error = APIError.from(error)
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
        if demo { library = fixture?.library; return }
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
        if demo { schedules = fixture?.schedules; return }
        guard let p = pairing else { return }
        do {
            schedules = try await api.schedules(p, project: id)
        } catch {
            actionError = APIError.from(error).message
        }
    }

    // MARK: demo

    private static var demoConflict: Bool { ProcessInfo.processInfo.arguments.contains("-noteConflict") }
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
