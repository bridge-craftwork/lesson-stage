import XCTest

/// Chrome auto-hide for projection, plus the manual dismiss the teacher drives:
/// the tab strip and toolbar fade after an idle spell so the projector shows a
/// clean page; a finger tap toggles them; and picking a tool dismisses them at
/// once (undo excepted). `-fastChrome` shortens the idle so this runs without a
/// real wait — and, unlike `-noAutoHide`, leaves the dismiss behaviour active.
final class AutoHideChromeUITests: LessonStageUITestCase {
    func testChromeTogglesOnTapAndAutoHides() {
        let app = launchWithFixtures(extraArguments: ["-fastChrome"])
        let pdf = app.otherElements["pdfView"]
        XCTAssertTrue(pdf.waitForExistence(timeout: 10))
        let firstTab = tab("lesson-a")

        // Starts revealed, then fades on its own after the idle spell.
        XCTAssertTrue(waitForDisappearance(of: firstTab, timeout: 6), "The chrome auto-hides when idle")

        // Hidden → a tap brings it back.
        pdf.tap()
        XCTAssertTrue(firstTab.waitForExistence(timeout: 3), "A tap reveals the hidden chrome")

        // Visible → a tap dismisses it, and faster than the idle spell would.
        pdf.tap()
        XCTAssertTrue(waitForDisappearance(of: firstTab, timeout: 2), "A tap dismisses the visible chrome")
    }

    func testSelectingAToolDismissesTheChrome() {
        let app = launchWithFixtures(extraArguments: ["-fastChrome"])
        XCTAssertTrue(app.otherElements["pdfView"].waitForExistence(timeout: 10))
        let firstTab = tab("lesson-a")

        // The toolbar is up at launch; pick a tool inside that window. It gets
        // out of the way at once — sooner than the idle spell (2.5s) would.
        XCTAssertTrue(firstTab.waitForExistence(timeout: 5), "Precondition: toolbar up at launch")
        app.buttons["tool-Yellow highlighter"].tap()
        XCTAssertTrue(waitForDisappearance(of: firstTab, timeout: 2), "Picking a tool dismisses the toolbar")
    }

    func testUndoKeepsTheChromeUp() {
        let app = launchWithFixtures(extraArguments: ["-fastChrome"])
        XCTAssertTrue(app.otherElements["pdfView"].waitForExistence(timeout: 10))
        let firstTab = tab("lesson-a")

        XCTAssertTrue(firstTab.waitForExistence(timeout: 5), "Precondition: toolbar up at launch")
        // Undo is the exception: repeated undos are expected, so it must not pull
        // the toolbar away. Checked at once, before the idle spell elapses.
        app.buttons["undo"].tap()
        XCTAssertTrue(firstTab.exists, "Undo leaves the toolbar up")
    }

    func testPencilDrawingDoesNotRevealChrome() {
        // Draw with a finger (as -fingerDrawing allows) while chrome is hidden;
        // the drawing must not count as the reveal tap — students see a clean,
        // live-annotated page.
        let app = launchWithFixtures(extraArguments: ["-fastChrome", "-fingerDrawing"])
        let pdf = app.otherElements["pdfView"]
        XCTAssertTrue(pdf.waitForExistence(timeout: 10))
        let firstTab = tab("lesson-a")
        XCTAssertTrue(waitForDisappearance(of: firstTab, timeout: 6), "Precondition: chrome idle-hidden")

        // A drag (not a tap) over the page: this is drawing, not a reveal.
        pdf.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.5))
            .press(forDuration: 0.1, thenDragTo: pdf.coordinate(withNormalizedOffset: CGVector(dx: 0.6, dy: 0.55)))

        XCTAssertFalse(
            firstTab.waitForExistence(timeout: 2),
            "Drawing should leave the chrome hidden"
        )
    }
}
