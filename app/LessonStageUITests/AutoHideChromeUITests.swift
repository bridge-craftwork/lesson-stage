import XCTest

/// Chrome auto-hide for projection: the tab strip and controls fade after an
/// idle spell so the projector shows a clean page, and a tap brings them back.
/// `-fastChrome` shortens the idle so this runs without a real wait.
final class AutoHideChromeUITests: LessonStageUITestCase {
    func testChromeHidesWhenIdleAndRevealsOnTap() {
        let app = launchWithFixtures(extraArguments: ["-fastChrome"])
        let pdf = app.otherElements["pdfView"]
        XCTAssertTrue(pdf.waitForExistence(timeout: 10))
        let firstTab = tab("lesson-a")

        // Tap to reveal — this starts the idle window under the test's control,
        // rather than racing the launch, which eats the initial window.
        pdf.tap()
        XCTAssertTrue(firstTab.waitForExistence(timeout: 3), "A tap reveals the chrome")

        // Left idle, the chrome fades on its own.
        XCTAssertTrue(
            waitForDisappearance(of: firstTab, timeout: 6),
            "The chrome should auto-hide after the idle spell"
        )

        // And a tap brings it back again.
        pdf.tap()
        XCTAssertTrue(firstTab.waitForExistence(timeout: 3), "A tap reveals it again")
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
