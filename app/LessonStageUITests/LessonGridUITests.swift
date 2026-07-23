import XCTest

/// The lesson grid: full names and thumbnails for the open lessons, so long
/// filenames are legible where the tab strip truncates them.
final class LessonGridUITests: LessonStageUITestCase {
    private func openGrid(_ app: XCUIApplication) {
        app.buttons["openGrid"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["lessonGrid"].firstMatch.waitForExistence(timeout: 5))
    }

    func testGridShowsEveryOpenLessonByFullName() {
        let app = launchWithFixtures()
        XCTAssertTrue(app.buttons["openGrid"].waitForExistence(timeout: 10))

        openGrid(app)

        XCTAssertTrue(app.descendants(matching: .any)["gridCell-lesson-a"].firstMatch.exists)
        XCTAssertTrue(app.descendants(matching: .any)["gridCell-lesson-b"].firstMatch.exists)

        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "lesson-grid"
        shot.lifetime = .keepAlways
        add(shot)
    }

    func testTappingALessonOpensItAndClosesTheGrid() {
        let app = launchWithFixtures()
        XCTAssertTrue(app.buttons["openGrid"].waitForExistence(timeout: 10))

        // Confirm which document is showing via its page count (fixtures differ
        // in length: lesson-a is short, lesson-b is long).
        let indicator = app.staticTexts["pageIndicator"]
        XCTAssertTrue(indicator.waitForExistence(timeout: 5))
        XCTAssertEqual(indicator.label, "Page 1 of \(PDFFixture.shortPageCount)", "Starts on lesson-a")

        openGrid(app)
        app.descendants(matching: .any)["gridCell-lesson-b"].firstMatch.tap()

        // The grid dismisses and lesson-b is now the document on screen.
        XCTAssertTrue(waitForDisappearance(of: app.descendants(matching: .any)["lessonGrid"].firstMatch))
        let showsLong = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label == %@", "Page 1 of \(PDFFixture.longPageCount)"),
            object: indicator
        )
        XCTAssertEqual(XCTWaiter().wait(for: [showsLong], timeout: 5), .completed, "Tapping a cell opens that lesson")
    }

    func testClosingALessonFromTheGrid() {
        let app = launchWithFixtures()
        XCTAssertTrue(app.buttons["openGrid"].waitForExistence(timeout: 10))
        openGrid(app)

        let cellA = app.descendants(matching: .any)["gridCell-lesson-a"].firstMatch
        XCTAssertTrue(cellA.exists)
        app.descendants(matching: .any)["gridClose-lesson-a"].firstMatch.tap()

        XCTAssertTrue(waitForDisappearance(of: cellA), "The closed lesson leaves the grid")
        XCTAssertTrue(app.descendants(matching: .any)["gridCell-lesson-b"].firstMatch.exists, "The other stays")
    }
}
