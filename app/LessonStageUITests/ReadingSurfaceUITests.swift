import XCTest

/// The reading surface under real touch: zoom, the sidebar, presentation mode.
final class ReadingSurfaceUITests: LessonStageUITestCase {
    func testPinchToZoom() {
        let app = launchWithFixtures()
        let pdf = app.otherElements["pdfView"]
        XCTAssertTrue(pdf.waitForExistence(timeout: 10))

        // PDFView's scale factor is not visible to a UI test, so this asserts
        // what a test *can* see: the gesture is accepted, the view survives it,
        // and page tracking still works afterwards. It is a crash-and-wedge
        // guard, not a measurement of zoom.
        pdf.pinch(withScale: 3, velocity: 1)
        XCTAssertTrue(pdf.exists)

        pdf.pinch(withScale: 0.5, velocity: -1)
        XCTAssertTrue(pdf.exists)
        XCTAssertTrue(app.staticTexts["pageIndicator"].exists)
    }

    func testScrollingChangesReportedPage() {
        let app = launchWithFixtures()
        let pdf = app.otherElements["pdfView"]
        XCTAssertTrue(pdf.waitForExistence(timeout: 10))

        let indicator = app.staticTexts["pageIndicator"]
        XCTAssertTrue(indicator.waitForExistence(timeout: 5))
        XCTAssertEqual(indicator.label, "Page 1 of \(PDFFixture.shortPageCount)")

        // Continuous scroll: swiping up should walk into later pages, and the
        // indicator is fed by PDFView's own page-changed notification, so this
        // exercises the tracking that session restore depends on.
        for _ in 0..<6 where indicator.label == "Page 1 of \(PDFFixture.shortPageCount)" {
            pdf.swipeUp(velocity: .fast)
        }

        XCTAssertNotEqual(
            indicator.label,
            "Page 1 of \(PDFFixture.shortPageCount)",
            "Scrolling should advance the reported page"
        )
    }

    func testThumbnailSidebarToggles() {
        let app = launchWithFixtures()
        XCTAssertTrue(app.otherElements["pdfView"].waitForExistence(timeout: 10))

        let sidebar = app.otherElements["thumbnailSidebar"]
        XCTAssertFalse(sidebar.exists, "Sidebar starts hidden")

        app.buttons["Toggle page thumbnails"].tap()
        XCTAssertTrue(sidebar.waitForExistence(timeout: 5))

        app.buttons["Toggle page thumbnails"].tap()
        XCTAssertTrue(waitForDisappearance(of: sidebar))
    }

    func testRotatePageButtonIsAvailableAndStable() {
        let app = launchWithFixtures()
        let pdf = app.otherElements["pdfView"]
        XCTAssertTrue(pdf.waitForExistence(timeout: 10))

        // The page rotation is on the in-memory PDFPage and is not exposed to
        // the accessibility tree, so a UI test cannot read the angle. What it
        // can prove: the ribbon button exists, tapping it (a full turn) leaves
        // the reader working rather than crashing or wedging. The visual result
        // is a device check.
        let rotate = app.buttons["rotatePage"]
        XCTAssertTrue(rotate.waitForExistence(timeout: 5))

        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "rotate-ribbon"
        shot.lifetime = .keepAlways
        add(shot)

        for _ in 0..<4 { rotate.tap() }

        XCTAssertTrue(pdf.exists)
        XCTAssertTrue(app.staticTexts["pageIndicator"].exists, "The reader survives a full rotation")
    }

    func testPresentationModeHidesAndRestoresChrome() {
        let app = launchWithFixtures()
        XCTAssertTrue(tab("lesson-a").waitForExistence(timeout: 10))

        app.buttons["Enter presentation mode"].tap()

        XCTAssertTrue(
            waitForDisappearance(of: tab("lesson-a")),
            "Presentation mode should hide the tab strip"
        )
        XCTAssertFalse(app.staticTexts["pageIndicator"].exists, "…and the reading controls")
        XCTAssertTrue(app.otherElements["pdfView"].exists, "…but keep the page")

        app.buttons["Exit presentation mode"].tap()

        XCTAssertTrue(
            tab("lesson-a").waitForExistence(timeout: 5),
            "Exiting should bring the chrome back"
        )
    }
}
