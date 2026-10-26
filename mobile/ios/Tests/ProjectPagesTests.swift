import UIKit
import XCTest
@testable import GupWorks3

/// a121: the Projects pages from docs/projects-mobile-mockups (01-12).
final class ProjectPagesTests: XCTestCase {
    func testLucideFontRegistersAndFindsIcons() {
        XCTAssertTrue(Lucide.registered)
        XCTAssertNotNil(UIFont(name: Lucide.family, size: 20))
        XCTAssertGreaterThan(Lucide.names.count, 1000)
        for name in ProjectLook.grid + [ProjectLook.defaultIcon] {
            XCTAssertNotNil(Lucide.character(name), name)
        }
        // a name that starts with the word first, then names containing it, then tagged ones
        let film = Lucide.search("film")
        XCTAssertEqual(film.first, "film")
        XCTAssertTrue(film.contains("clapperboard"), "clapperboard is tagged film")
        XCTAssertLessThan(film.firstIndex(of: "film")!, film.firstIndex(of: "clapperboard")!)
        XCTAssertTrue(Lucide.search("zzzz-not-an-icon").isEmpty)
        XCTAssertEqual(Lucide.search("  "), Lucide.names)
    }

    func testProjectColours() {
        XCTAssertNotNil(ProjectLook.color("violet"))
        XCTAssertNil(ProjectLook.color(nil))
        XCTAssertNil(ProjectLook.color("chartreuse"))
        XCTAssertEqual(ProjectLook.colors.count, 9)
    }

    func testAgo() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let ms = now.timeIntervalSince1970 * 1000
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let en = Locale(identifier: "en_US")
        XCTAssertEqual(Format.ago(ms - 20_000, now: now, calendar: cal, locale: en), "just now")
        XCTAssertEqual(Format.ago(ms - 4 * 60_000, now: now, calendar: cal, locale: en), "4 min ago")
        XCTAssertEqual(Format.ago(ms - 3_600_000, now: now, calendar: cal, locale: en), "1 hour ago")
        XCTAssertEqual(Format.ago(ms - 7 * 3_600_000, now: now, calendar: cal, locale: en), "7 hours ago")
        XCTAssertEqual(Format.ago(ms - 3 * 86_400_000, now: now, calendar: cal, locale: en), "3 days ago")
        XCTAssertEqual(Format.ago(0, now: now), "")
    }

    func testNewestFirst() throws {
        let home: Home = try XCTUnwrap(Demo.load("home"))
        let sorted = ProjectsPage.newestFirst(home.projects)
        XCTAssertEqual(sorted.first?.id, "lumen-studio")
        let times = sorted.map { $0.lastActive ?? $0.created ?? 0 }
        XCTAssertEqual(times, times.sorted(by: >))
        XCTAssertEqual(home.archivedProjects?.first?.name, "Old blog")
    }

    func testProjectFixturesDecode() throws {
        let folders: FoldersReply = try XCTUnwrap(Demo.load("folders"))
        XCTAssertFalse(folders.folders.isEmpty)
        XCTAssertTrue(folders.folders.contains { $0.project != nil }, "a folder already used by a project")
        let search: ProjectSearchReply = try XCTUnwrap(Demo.load("search"))
        XCTAssertEqual(search.projects.first?.title, "Contrast pass")
        let f: ProjectFixture = try XCTUnwrap(Demo.load("lumen-studio", in: "fixtures/projects"))
        XCTAssertEqual(f.view.icon, "camera")
        XCTAssertNotNil(f.view.mainNeeds?.options)
        XCTAssertEqual(f.settings?.threadLabel, "Automatic")
        XCTAssertFalse(f.ideas?.sections.isEmpty ?? true)
        XCTAssertEqual(f.usage?.biggest.first?.id, "a6")
    }

    func testSettingsPatchSendsOnlyWhatChanged() throws {
        let p = ProjectPatch(name: "Film shelf", color: "")
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(p)) as? [String: Any])
        XCTAssertEqual(Set(json.keys), ["name", "color"])
        XCTAssertEqual(json["color"] as? String, "")
    }

    @MainActor
    func testDemoCreateArchiveAndDelete() async throws {
        let model = AppModel(demo: true)
        await model.refresh()
        let before = model.home?.projects.count ?? 0
        let r = try await model.createProject(name: "Film shelf", goal: "", icon: "film", color: "red", folder: "new",
                                              files: [], clientId: "c1")
        XCTAssertEqual(model.home?.projects.count, before + 1)
        XCTAssertEqual(model.projectRow(r.projectId)?.icon, "film")
        await model.setArchived(project: r.projectId, true)
        XCTAssertTrue(model.home?.archivedProjects?.contains { $0.id == r.projectId } ?? false)
        await model.setArchived(project: r.projectId, false)
        XCTAssertTrue(model.home?.projects.contains { $0.id == r.projectId } ?? false)
        let s = try await model.updateProject(r.projectId, ProjectPatch(name: "Films", color: ""))
        XCTAssertEqual(s.name, "Films")
        XCTAssertNil(model.projectRow(r.projectId)?.color)
        try await model.deleteProject(r.projectId)
        XCTAssertNil(model.projectRow(r.projectId))
    }

    func testIdeaChanges() throws {
        let f: ProjectFixture = try XCTUnwrap(Demo.load("lumen-studio", in: "fixtures/projects"))
        let l = try XCTUnwrap(f.ideas)
        let todo = try XCTUnwrap(l.sections.first { $0.name == "To do" }?.items.first)
        // edit keeps the date the note had
        let edited = DemoProject.change(IdeaChange(op: "edit", section: "To do", old: todo.raw, text: "Book from a photo"), in: l)
        XCTAssertEqual(edited.sections[0].items[0].text, "Book from a photo")
        XCTAssertEqual(edited.sections[0].items[0].raw, "Book from a photo (2026-10-24)")
        // an empty edit deletes it
        let cleared = DemoProject.change(IdeaChange(op: "edit", section: "To do", old: todo.raw, text: "  "), in: l)
        XCTAssertTrue(cleared.sections[0].items.isEmpty)
        XCTAssertEqual(cleared.count, l.count - 1)
        let moved = DemoProject.change(IdeaChange(op: "move", section: "To do", old: todo.raw, to: "Done"), in: l)
        XCTAssertTrue(moved.sections[0].items.isEmpty)
        XCTAssertEqual(moved.sections.first { $0.name == "Done" }?.items.last?.text, "Booking straight from the gallery")
        XCTAssertEqual(moved.count, l.count)
        // unknown items, sections and ops leave the note as it was
        XCTAssertEqual(DemoProject.change(IdeaChange(op: "delete", section: "To do", old: "nope"), in: l), l)
        XCTAssertEqual(DemoProject.change(IdeaChange(op: "move", section: "To do", old: todo.raw, to: "To do"), in: l), l)
        XCTAssertEqual(DemoProject.change(IdeaChange(op: "shout", section: "To do", old: todo.raw), in: l), l)
    }

    func testScheduleRegroup() throws {
        let f: ProjectFixture = try XCTUnwrap(Demo.load("lumen-studio", in: "fixtures/projects"))
        XCTAssertEqual(f.schedules.groups.map(\.label), ["Scheduled", "Running now", "Paused"])
        var s = f.schedules
        for g in s.groups.indices {
            for i in s.groups[g].items.indices where s.groups[g].items[i].id == "s3" { s.groups[g].items[i].paused = false }
            for i in s.groups[g].items.indices where s.groups[g].items[i].id == "s1" { s.groups[g].items[i].running = true }
        }
        let out = DemoProject.regroupSchedules(s)
        XCTAssertEqual(out.groups.map(\.label), ["Scheduled", "Running now"])
        XCTAssertEqual(Set(out.groups[1].items.map(\.id)), ["s1", "s4"])
        XCTAssertEqual(out.groups[1].items.first { $0.id == "s1" }?.when, "Running as a thread \u{00B7} open it")
        XCTAssertTrue(out.groups[0].items.contains { $0.id == "s3" })
        XCTAssertEqual(out.count, 4)
    }

    @MainActor
    func testDemoIdeasLibraryAndScheduleMoves() async throws {
        let s = ProjectStore(id: "lumen-studio", pairing: nil, demo: true)
        await s.refresh()
        await s.loadIdeas()
        let before = try XCTUnwrap(s.ideas?.count)
        let added = await s.addIdea("  Gift cards  ")
        XCTAssertTrue(added)
        XCTAssertEqual(s.ideas?.count, before + 1)
        let later = s.ideas?.sections.first { $0.name == "Ideas for later" }?.items.last
        XCTAssertEqual(later?.text, "Gift cards")
        let blank = await s.addIdea("   ")
        XCTAssertFalse(blank)
        await s.changeIdea(IdeaChange(op: "delete", section: "Ideas for later", old: try XCTUnwrap(later?.raw)))
        XCTAssertEqual(s.ideas?.count, before)

        await s.loadLibrary()
        let count = try XCTUnwrap(s.library?.count)
        let photo = Attachment(name: "studio.jpg", type: "image/jpeg", data: Data([1]), image: nil, uploaded: nil)
        let ok = await s.addToLibrary([photo])
        XCTAssertTrue(ok)
        XCTAssertEqual(s.library?.count, count + 1)
        XCTAssertEqual(s.library?.groups.first { $0.id == "notes" }?.items.first?.kind, "image")
        let none = await s.addToLibrary([])
        XCTAssertFalse(none)

        await s.loadSchedules()
        await s.scheduleMove("s3", "resume")
        XCTAssertFalse(s.schedules?.groups.contains { $0.label == "Paused" } ?? true)
        await s.scheduleMove("s1", "pause")
        XCTAssertEqual(s.schedules?.groups.first { $0.label == "Paused" }?.items.map(\.id), ["s1"])
        await s.scheduleMove("s2", "run")
        XCTAssertTrue(s.schedules?.groups.first { $0.label == "Running now" }?.items.contains { $0.id == "s2" } ?? false)
    }

    func testThreadChatFixture() throws {
        let c: ChatFixture = try XCTUnwrap(Demo.load("00000074-2222-4222-8333-000000000074", in: "fixtures/chats"))
        XCTAssertEqual(c.header.role, "worker")
        let w = try XCTUnwrap(c.header.work)
        XCTAssertEqual([w.id, w.glyph, w.from ?? ""], ["a4", "spin", "main"])
        XCTAssertEqual(w.criteria.count, 3)
        XCTAssertEqual(c.header.project?.icon, "camera")
        let main: ChatFixture = try XCTUnwrap(Demo.load("00000066-1111-4222-8333-000000000066", in: "fixtures/chats"))
        let outside = main.turns.turns.flatMap { $0.outside ?? [] }
        XCTAssertEqual(outside.filter { $0.type == "threads" }.flatMap { $0.threads ?? [] }.map(\.id), ["a3", "a4", "a5", "a6"])
        let ask = try XCTUnwrap(outside.first { $0.type == "ask" })
        XCTAssertEqual(ask.work ?? "", "")
        XCTAssertEqual(ask.options ?? [], ["Looks good", "Show me first"])
    }
}
