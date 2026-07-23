import XCTest

/// Shared setup for the UI tests.
///
/// These tests exist to cover the one thing no other kind of test can reach:
/// real touch. Everything here is driven through synthesized taps, drags, and
/// pinches against the accessibility tree, exactly as a finger would.
class LessonStageUITestCase: XCTestCase {
    var app: XCUIApplication!

    /// Fixture PDFs, written to a temporary directory the app can read.
    ///
    /// The app sandbox and the test runner share a filesystem on the
    /// simulator, so a plain path works and no document picker is involved —
    /// which matters, because the picker is a system UI that cannot be driven
    /// reliably from a test.
    private(set) var fixtureURLs: [URL] = []

    override func setUpWithError() throws {
        continueAfterFailure = false

        let directory = FileManager.default.temporaryDirectory
            .appending(path: "lesson-stage-fixtures", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        // lesson-a is short, lesson-b is long, so "Page 1 of N" identifies
        // which document is on screen.
        fixtureURLs = try [
            ("lesson-a", "", PDFFixture.shortPageCount),
            ("lesson-b", "Weak Twos: ", PDFFixture.longPageCount),
        ].map { name, prefix, pages in
            let url = directory.appending(path: "\(name).pdf")
            try PDFFixture.data(titlePrefix: prefix, pageCount: pages)
                .write(to: url, options: .atomic)
            return url
        }

        app = XCUIApplication()
    }

    /// Launch with both fixtures open and a clean session.
    ///
    /// Chrome auto-hide is pinned off by default — a fade mid-test would pull
    /// tabs and tools out from under assertions. The auto-hide test opts back
    /// in with `-fastChrome` and omits `-noAutoHide`.
    @discardableResult
    func launchWithFixtures(extraArguments: [String] = []) -> XCUIApplication {
        var args = ["-reset", "-open"] + fixtureURLs.map(\.path) + extraArguments
        if !extraArguments.contains("-fastChrome") { args.append("-noAutoHide") }
        app.launchArguments = args
        app.launch()
        return app
    }

    /// A tab in the strip, addressed by lesson title.
    ///
    /// Queried across every element type rather than one: SwiftUI decides what
    /// an accessibility element becomes from its traits, so a container with
    /// `.isButton` surfaces as a button while one without is an
    /// `otherElement`. Matching on the identifier alone survives that choice.
    func tab(_ title: String) -> XCUIElement {
        app.descendants(matching: .any)["tab-\(title)"]
    }

    /// `waitForExistence` has no negative counterpart, and asserting
    /// `!exists` immediately races every disappearance that is animated.
    func waitForDisappearance(of element: XCUIElement, timeout: TimeInterval = 5) -> Bool {
        let gone = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"),
            object: element
        )
        return XCTWaiter().wait(for: [gone], timeout: timeout) == .completed
    }
}
