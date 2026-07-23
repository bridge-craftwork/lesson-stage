import XCTest

/// The interactions `simctl` cannot reach: tapping, closing, and dragging tabs.
final class TabStripUITests: LessonStageUITestCase {
    func testOpensBothFixturesAsTabs() {
        let app = launchWithFixtures()

        XCTAssertTrue(tab("lesson-a").waitForExistence(timeout: 10))
        XCTAssertTrue(tab("lesson-b").exists)
        XCTAssertTrue(app.staticTexts["pageIndicator"].waitForExistence(timeout: 5))
    }

    func testTappingATabSwitchesDocument() {
        let app = launchWithFixtures()
        XCTAssertTrue(tab("lesson-b").waitForExistence(timeout: 10))

        let indicator = app.staticTexts["pageIndicator"]
        XCTAssertTrue(indicator.waitForExistence(timeout: 5))
        XCTAssertEqual(indicator.label, "Page 1 of \(PDFFixture.shortPageCount)")

        // The fixtures differ in length, so the reported page count proves the
        // document swapped rather than only the tab highlight moving.
        tab("lesson-b").tap()

        let showsLongDocument = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label == %@", "Page 1 of \(PDFFixture.longPageCount)"),
            object: indicator
        )
        XCTAssertEqual(
            XCTWaiter().wait(for: [showsLongDocument], timeout: 5), .completed,
            "Tapping lesson-b should show lesson-b's document, not lesson-a's"
        )
    }

    func testClosingATabRemovesIt() {
        let app = launchWithFixtures()
        XCTAssertTrue(tab("lesson-a").waitForExistence(timeout: 10))

        app.buttons["Close lesson-a"].tap()

        XCTAssertTrue(
            waitForDisappearance(of: tab("lesson-a")),
            "Closed tab should be gone"
        )
        XCTAssertTrue(tab("lesson-b").exists, "The other tab should survive")
    }

    func testClosingTheSelectedTabSelectsItsNeighbour() {
        let app = launchWithFixtures()
        XCTAssertTrue(tab("lesson-a").waitForExistence(timeout: 10))

        // lesson-a is selected on launch; closing it must leave a document
        // showing rather than dropping to the empty state.
        app.buttons["Close lesson-a"].tap()

        let indicator = app.staticTexts["pageIndicator"]
        let showsLongDocument = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label == %@", "Page 1 of \(PDFFixture.longPageCount)"),
            object: indicator
        )
        XCTAssertEqual(
            XCTWaiter().wait(for: [showsLongDocument], timeout: 5), .completed,
            "Closing the selected tab should select its neighbour, not show the empty state"
        )
    }

    func testDraggingReordersTabs() {
        let app = launchWithFixtures()
        let first = tab("lesson-a")
        let second = tab("lesson-b")
        XCTAssertTrue(first.waitForExistence(timeout: 10))

        let originalFirstX = first.frame.minX
        XCTAssertLessThan(originalFirstX, second.frame.minX, "lesson-a starts on the left")

        // A drag needs a hold before it moves, or it reads as a tap.
        first.press(forDuration: 1.0, thenDragTo: second)

        // Reordering is animated; poll rather than assert on the first frame.
        let reordered = expectation(description: "tabs reordered")
        let poll = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { [self] _ in
            if tab("lesson-b").exists,
               tab("lesson-a").exists,
               tab("lesson-b").frame.minX < tab("lesson-a").frame.minX {
                reordered.fulfill()
            }
        }
        defer { poll.invalidate() }

        wait(for: [reordered], timeout: 10)
    }
}
