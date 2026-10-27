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
}
