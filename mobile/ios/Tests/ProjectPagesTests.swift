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
}
