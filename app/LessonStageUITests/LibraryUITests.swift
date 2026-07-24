import XCTest

/// Load from Library: the Settings toggle that gates the feature, and the day
/// list it unlocks. The directory picker is a system UI a test cannot drive, so
/// the library root is handed in by path via `-libraryRoot` — the same trick
/// `-open` uses for the document picker.
final class LibraryUITests: LessonStageUITestCase {
    private var libraryRoot: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()

        // A tree mirroring the real layout: root / year / month / day / Handouts.
        // Today (per the test clock) is 2026-07-23, so the 28th is the anchor and
        // everything here falls inside the default -3/+5 window.
        libraryRoot = FileManager.default.temporaryDirectory
            .appending(path: "library-ui-\(UUID().uuidString)", directoryHint: .isDirectory)

        try makeDay("2026-07-16", handouts: [("Warm-up", 4)])
        try makeDay("2026-07-21", handouts: [("Monday Handout", 3)]) // distinctive page count
        try makeDay("2026-07-28", handouts: [("Tuesday A", 5), ("Tuesday B", 4)])
        // A precreated-but-unplanned day: a Handouts folder with nothing in it.
        try makeDay("2026-07-30", handouts: [])
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: libraryRoot)
    }

    private func makeDay(_ isoDay: String, handouts: [(name: String, pages: Int)]) throws {
        let month = "2026-07 Jul"
        let dir = libraryRoot
            .appending(path: "2026").appending(path: month).appending(path: isoDay).appending(path: "Handouts")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for handout in handouts {
            try PDFFixture.data(pageCount: handout.pages)
                .write(to: dir.appending(path: "\(handout.name).pdf"), options: .atomic)
        }
    }

    private func launchWithLibrary() -> XCUIApplication {
        app.launchArguments = ["-reset", "-noAutoHide", "-libraryEnabled", "-libraryRoot", libraryRoot.path]
        app.launch()
        return app
    }

    // MARK: - Settings toggle

    func testTheFeatureIsOffByDefaultAndTheToggleTurnsItOn() {
        let app = launchWithFixtures() // no library args: fresh, feature off

        // Off means no library button in the strip.
        XCTAssertTrue(app.buttons["openSettings"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["openLibrary"].exists, "The library button is hidden until the feature is on")

        app.buttons["openSettings"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["settingsSheet"].firstMatch.waitForExistence(timeout: 5))

        let toggle = app.switches["enableLibraryToggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        XCTAssertEqual(toggle.value as? String, "0", "Starts off")
        XCTAssertFalse(app.buttons["chooseFolder"].exists, "No folder chooser while off")

        // Tap the trailing switch control, not the row centre: in a Form a
        // Toggle's element spans the whole row but only the switch toggles.
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()

        // The behavioural signal that the flag flipped: the folder chooser, which
        // only exists when the feature is enabled.
        XCTAssertTrue(app.buttons["chooseFolder"].waitForExistence(timeout: 5), "Enabling reveals the folder chooser")
        let isOn = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == %@", "1"),
            object: toggle
        )
        XCTAssertEqual(XCTWaiter().wait(for: [isOn], timeout: 3), .completed, "The switch reads on")

        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "settings-library-enabled"
        shot.lifetime = .keepAlways
        add(shot)

        // Dismiss: the library button is now in the strip.
        app.buttons["Done"].tap()
        XCTAssertTrue(app.buttons["openLibrary"].waitForExistence(timeout: 5), "Enabling surfaces the library button")
    }

    // MARK: - Day list

    func testTheDayListShowsTheWindowWithTheAnchorAndEmptyDays() {
        let app = launchWithLibrary()
        XCTAssertTrue(app.buttons["openLibrary"].waitForExistence(timeout: 10))

        app.buttons["openLibrary"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["librarySheet"].firstMatch.waitForExistence(timeout: 5))

        // Every day in the window is listed, including the unplanned one.
        for day in ["2026-07-16", "2026-07-21", "2026-07-28", "2026-07-30"] {
            XCTAssertTrue(
                app.descendants(matching: .any)["day-\(day)"].firstMatch.exists,
                "\(day) should be in the window"
            )
        }

        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "library-day-list"
        shot.lifetime = .keepAlways
        add(shot)
    }

    func testTappingADayReplacesTheOpenTabsWithItsHandouts() {
        let app = launchWithLibrary()
        XCTAssertTrue(app.buttons["openLibrary"].waitForExistence(timeout: 10))

        app.buttons["openLibrary"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["librarySheet"].firstMatch.waitForExistence(timeout: 5))

        // The 21st has one handout, three pages — a page count no other day shares.
        app.descendants(matching: .any)["day-2026-07-21"].firstMatch.tap()

        XCTAssertTrue(
            waitForDisappearance(of: app.descendants(matching: .any)["librarySheet"].firstMatch),
            "Opening a day dismisses the sheet"
        )

        let indicator = app.staticTexts["pageIndicator"]
        XCTAssertTrue(indicator.waitForExistence(timeout: 5))
        XCTAssertEqual(indicator.label, "Page 1 of 3", "The 21st's handout is now open")
    }

    func testAnEmptyDayCannotBeOpened() {
        let app = launchWithLibrary()
        XCTAssertTrue(app.buttons["openLibrary"].waitForExistence(timeout: 10))

        app.buttons["openLibrary"].tap()
        let emptyDay = app.descendants(matching: .any)["day-2026-07-30"].firstMatch
        XCTAssertTrue(emptyDay.waitForExistence(timeout: 5))

        emptyDay.tap() // disabled — nothing should happen
        XCTAssertTrue(
            app.descendants(matching: .any)["librarySheet"].firstMatch.exists,
            "A not-planned day is inert: the sheet stays and nothing opens"
        )
    }
}
