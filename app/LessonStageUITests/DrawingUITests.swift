import XCTest

/// Drawing, exercised end to end without a Pencil.
///
/// The canvases are `.pencilOnly` in the real app so a finger still scrolls.
/// `-fingerDrawing` relaxes that to `.anyInput` so a synthesized drag can make
/// a stroke — otherwise nothing here would run outside a physical iPad, and
/// the whole drawing path would go unexercised until someone noticed in class.
///
/// Strokes are drawn against the `pdfView` element rather than the canvas.
/// The canvas is deliberately *not* an accessibility element — it sits over the
/// page, and making it one would hide the lesson's own text from VoiceOver —
/// so it never appears in the tree. Dragging over the page hits it anyway,
/// which is exactly what a Pencil does.
final class DrawingUITests: LessonStageUITestCase {
    private func launchDrawing(extraArguments: [String] = []) -> XCUIApplication {
        launchWithFixtures(extraArguments: ["-fingerDrawing"] + extraArguments)
    }

    /// Number of pages the app reports as carrying marks.
    private func annotatedPages(in app: XCUIApplication) -> XCUIElement {
        app.staticTexts["annotatedPageCount"]
    }

    private func expect(_ element: XCUIElement, toRead value: String, timeout: TimeInterval = 5) -> Bool {
        let matched = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label == %@", value),
            object: element
        )
        return XCTWaiter().wait(for: [matched], timeout: timeout) == .completed
    }

    /// Skip a stroke-making test when there is no input device that PencilKit
    /// will accept.
    ///
    /// Verified by instrumenting the running app: under `-fingerDrawing` the
    /// canvas is attached, sized to the page, interaction-enabled, its drawing
    /// gesture is enabled, and the `DrawingSet` is wired up — but a synthesized
    /// XCUITest drag still produces no stroke. PencilKit does not build strokes
    /// from injected touches in the simulator.
    ///
    /// These tests are real and should be run: on a paired iPad they exercise
    /// the whole path, because there a finger genuinely draws under
    /// `-fingerDrawing`. Skipping beats deleting — the coverage exists, it just
    /// needs hardware.
    private func skipUnlessStrokesArePossible() throws {
        #if targetEnvironment(simulator)
        throw XCTSkip("Needs a real touch device — synthesized touches don't reach this path in the simulator; run on a device.")
        #endif
    }

    /// Draw a short stroke across the upper half of the page, clear of the
    /// floating controls at the bottom.
    private func drawStroke(in app: XCUIApplication) {
        let page = app.otherElements["pdfView"]
        XCTAssertTrue(page.waitForExistence(timeout: 10))

        let start = page.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.35))
        let end = page.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.42))

        // A slow drag with a hold at each end. The default fast drag is
        // delivered as too few touch events for PencilKit to build a stroke
        // from — it needs the intermediate movement, not just endpoints.
        start.press(
            forDuration: 0.2,
            thenDragTo: end,
            withVelocity: .slow,
            thenHoldForDuration: 0.3
        )
    }

    func testDraggingMarksThePage() throws {
        try skipUnlessStrokesArePossible()
        let app = launchDrawing()
        let marks = annotatedPages(in: app)
        XCTAssertTrue(marks.waitForExistence(timeout: 10))
        XCTAssertEqual(marks.label, "0", "A freshly opened lesson carries no marks")

        drawStroke(in: app)

        XCTAssertTrue(expect(marks, toRead: "1"), "A stroke should mark the page")
    }

    func testDiagnosticsTabShowsInputActivity() {
        let app = launchDrawing()
        let debugTab = app.descendants(matching: .any)["tab-diagnostics"].firstMatch
        XCTAssertTrue(debugTab.waitForExistence(timeout: 10))

        debugTab.tap()

        XCTAssertTrue(app.descendants(matching: .any)["diagnosticsView"].firstMatch.waitForExistence(timeout: 5))
        // Attaching canvases records routing and placement, so the panel has
        // content even before anything is drawn.
        XCTAssertTrue(
            app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'routing'")).firstMatch
                .waitForExistence(timeout: 5),
            "The panel should already show what the input layer did on load"
        )

        debugTab.tap()
        XCTAssertTrue(waitForDisappearance(of: app.descendants(matching: .any)["diagnosticsView"].firstMatch))
    }

    /// Copy mode's highlight path is our own touch handling plus PDFKit text
    /// selection — it does not go through PencilKit's stroke builder, so unlike
    /// ink it may be reachable by a synthesized drag. If the simulator turns
    /// out to reject it too, this asserts nothing false; it just needs the same
    /// device skip. Kept separate from the ink tests for exactly that reason.
    func testHighlightingTextMarksThePage() {
        let app = launchDrawing()
        XCTAssertTrue(app.buttons["tool-Yellow highlighter"].waitForExistence(timeout: 10))
        app.buttons["tool-Yellow highlighter"].tap()

        let marks = annotatedPages(in: app)
        XCTAssertEqual(marks.label, "0")

        // Drag across the lesson title, which sits in the upper-left of page 1.
        let page = app.otherElements["pdfView"]
        let start = page.coordinate(withNormalizedOffset: CGVector(dx: 0.12, dy: 0.16))
        let end = page.coordinate(withNormalizedOffset: CGVector(dx: 0.45, dy: 0.16))
        start.press(forDuration: 0.2, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.2)

        XCTAssertTrue(expect(marks, toRead: "1"), "Dragging over text should leave a highlight")
    }

    /// The other half of the routing decision, read from the diagnostics panel
    /// rather than inferred from a mark count. A drag low on the page — well
    /// below any text in the fixture — must be routed to ink, not highlight.
    /// Reading the recorded decision makes this robust to where exactly the
    /// glyphs fell, which a mark count is not.
    func testDraggingBlankSpaceRoutesToInk() {
        let app = launchDrawing()
        app.buttons["tool-Yellow highlighter"].tap()
        XCTAssertTrue(annotatedPages(in: app).waitForExistence(timeout: 10))

        let page = app.otherElements["pdfView"]
        page.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.9))
            .press(
                forDuration: 0.2,
                thenDragTo: page.coordinate(withNormalizedOffset: CGVector(dx: 0.75, dy: 0.9)),
                withVelocity: .slow,
                thenHoldForDuration: 0.2
            )

        app.descendants(matching: .any)["tab-diagnostics"].firstMatch.tap()
        XCTAssertTrue(
            app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'whitespace, inking'"))
                .firstMatch.waitForExistence(timeout: 5),
            "A drag starting on blank space should be routed to ink, not highlighting"
        )
    }

    /// Erasing end-to-end depends on tapping exactly where PDFKit rendered the
    /// selection, which sits where its own geometry puts it — not precisely
    /// under the finger. That offset is part of the copy-mode feel still being
    /// tuned on a device, and makes a coordinate-precise tap unreliable in CI.
    /// The erase *logic* is covered by `DrawingSetTests.testErasingAHighlight`
    /// (remove-by-point); this verifies the touch wiring, on hardware.
    func testErasingAHighlight() throws {
        try skipUnlessStrokesArePossible()
        let app = launchDrawing()
        app.buttons["tool-Yellow highlighter"].tap()
        let marks = annotatedPages(in: app)
        XCTAssertTrue(marks.waitForExistence(timeout: 10))

        // Highlight the title with a tight drag, then erase by tapping the same
        // spot. Using one point for both sides means the test does not depend
        // on where PDFKit's selection geometry lands — only that the eraser
        // reaches whatever was highlighted under the finger.
        let page = app.otherElements["pdfView"]
        let onTitle = CGVector(dx: 0.2, dy: 0.155)
        page.coordinate(withNormalizedOffset: onTitle)
            .press(
                forDuration: 0.2,
                thenDragTo: page.coordinate(withNormalizedOffset: CGVector(dx: 0.35, dy: 0.155)),
                withVelocity: .slow,
                thenHoldForDuration: 0.2
            )
        XCTAssertTrue(expect(marks, toRead: "1"), "Precondition: a highlight to erase")

        app.buttons["tool-Eraser"].tap()
        page.coordinate(withNormalizedOffset: onTitle).tap()

        XCTAssertTrue(expect(marks, toRead: "0"), "Tapping a highlight with the eraser should remove it")
    }

    func testHighlightSurvivesRelaunch() {
        let app = launchDrawing()
        app.buttons["tool-Yellow highlighter"].tap()
        let marks = annotatedPages(in: app)
        XCTAssertTrue(marks.waitForExistence(timeout: 10))

        let page = app.otherElements["pdfView"]
        page.coordinate(withNormalizedOffset: CGVector(dx: 0.12, dy: 0.16))
            .press(
                forDuration: 0.2,
                thenDragTo: page.coordinate(withNormalizedOffset: CGVector(dx: 0.45, dy: 0.16)),
                withVelocity: .slow,
                thenHoldForDuration: 0.2
            )
        XCTAssertTrue(expect(marks, toRead: "1"))

        XCUIDevice.shared.press(.home)
        Thread.sleep(forTimeInterval: 2)
        app.terminate()

        let reopened = launchDrawing()
        let restored = annotatedPages(in: reopened)
        XCTAssertTrue(restored.waitForExistence(timeout: 10))
        XCTAssertTrue(expect(restored, toRead: "1"), "The highlight should be restored from the sidecar")
    }

    func testPaletteIsHiddenInPresentationMode() {
        let app = launchDrawing(extraArguments: ["-present"])
        XCTAssertTrue(app.otherElements["pdfView"].waitForExistence(timeout: 10))

        XCTAssertFalse(
            app.descendants(matching: .any)["drawToggle"].exists,
            "The class should see the lesson, not the teacher's toolbar"
        )
    }

    func testSelectingATool() {
        let app = launchDrawing()
        XCTAssertTrue(app.buttons["tool-Red pen"].waitForExistence(timeout: 10))

        app.buttons["tool-Red pen"].tap()

        XCTAssertTrue(app.buttons["tool-Red pen"].isSelected, "The chosen tool should read as selected")
    }

    func testTurningDrawingOffHidesTheTools() {
        let app = launchDrawing()
        let toggle = app.descendants(matching: .any)["drawToggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["tool-Black pen"].exists)

        toggle.tap()

        XCTAssertTrue(
            waitForDisappearance(of: app.buttons["tool-Black pen"]),
            "With marking off there is nothing to choose between"
        )
    }

    func testDrawingIsIgnoredWhenMarkingIsOff() {
        let app = launchDrawing()
        let toggle = app.descendants(matching: .any)["drawToggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 10))

        toggle.tap()
        drawStroke(in: app)

        // The count readout is hidden with the rest of the tools, so re-enable
        // marking and check nothing was recorded while it was off.
        toggle.tap()
        let marks = annotatedPages(in: app)
        XCTAssertTrue(marks.waitForExistence(timeout: 5))
        XCTAssertEqual(marks.label, "0", "With marking off the Pencil should scroll, not draw")
    }

    func testUndoRemovesTheStroke() throws {
        try skipUnlessStrokesArePossible()
        let app = launchDrawing()
        let marks = annotatedPages(in: app)
        XCTAssertTrue(marks.waitForExistence(timeout: 10))

        drawStroke(in: app)
        XCTAssertTrue(expect(marks, toRead: "1"), "The drag should have produced a stroke")

        app.buttons["undo"].tap()

        XCTAssertTrue(expect(marks, toRead: "0"), "Undo should take the page back to unmarked")
    }

    /// The one that matters: a mark must outlive the app that made it.
    func testAStrokeSurvivesRelaunch() throws {
        try skipUnlessStrokesArePossible()
        let app = launchDrawing()
        let marks = annotatedPages(in: app)
        XCTAssertTrue(marks.waitForExistence(timeout: 10))

        drawStroke(in: app)
        XCTAssertTrue(expect(marks, toRead: "1"))

        // Backgrounding flushes the save debounce.
        XCUIDevice.shared.press(.home)
        Thread.sleep(forTimeInterval: 2)
        app.terminate()

        // Reopen the same file. The sidecar is keyed by content hash, so it
        // should be found again — and the fixtures are rewritten identically
        // on each launch, which is the property that makes this work.
        let reopened = launchDrawing()
        let restored = annotatedPages(in: reopened)
        XCTAssertTrue(restored.waitForExistence(timeout: 10))

        XCTAssertTrue(
            expect(restored, toRead: "1"),
            "The stroke should have been restored from the sidecar"
        )
    }
}
