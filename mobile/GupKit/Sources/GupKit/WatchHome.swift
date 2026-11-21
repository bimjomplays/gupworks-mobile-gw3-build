import Foundation

// a235: the iPhone's side of the Running screen. The watch compiles Watch.swift and Needs.swift only, so what needs
// the home list (API.swift) lives here: the PC's project rows become the watch's.

extension WatchProject {
    init(_ row: ProjectRow) {
        self.init(id: row.id, name: row.name, working: row.working, checking: row.checking ?? 0,
                  main: !(row.mainChatId ?? "").isEmpty)
    }

    /// The projects the watch lists: the Projects list's rows (YouTube Studio included, without a main chat).
    static func list(_ home: Home?) -> [WatchProject]? {
        home.map { $0.listed.map(WatchProject.init) }
    }
}
