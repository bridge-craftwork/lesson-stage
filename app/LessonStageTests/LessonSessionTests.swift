import XCTest
@testable import LessonStage

/// The tab-management rules, which have no screen and so belong here rather
/// than in a UI test: they run in milliseconds and fail for one reason each.
@MainActor
final class LessonSessionTests: XCTestCase {
    private var directory: URL!
    private var storeName: String!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appending(path: "lesson-session-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        // A distinct store per test: these all share one app container.
        storeName = "session-\(UUID().uuidString).json"
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func makeSession() -> LessonSession {
        LessonSession(store: SessionStore(filename: storeName))
    }

    private func makePDF(named name: String, pages: Int = 2) throws -> URL {
        let url = directory.appending(path: "\(name).pdf")
        try TestPDF.data(pages: pages).write(to: url, options: .atomic)
        return url
    }

    // MARK: - Opening

    func testOpeningAddsAndSelectsATab() throws {
        let session = makeSession()
        let url = try makePDF(named: "one")

        session.open(url: url)

        XCTAssertEqual(session.tabs.count, 1)
        XCTAssertEqual(session.selectedTab?.url, url)
        XCTAssertEqual(session.selectedTab?.title, "one")
        XCTAssertEqual(session.selectedTab?.pageCount, 2, "The document should be loaded")
    }

    func testOpeningTheSameFileTwiceSelectsTheExistingTab() throws {
        let session = makeSession()
        let first = try makePDF(named: "one")
        let second = try makePDF(named: "two")

        session.open(url: first)
        session.open(url: second)
        session.open(url: first)

        XCTAssertEqual(session.tabs.count, 2, "Reopening must not duplicate the tab")
        XCTAssertEqual(
            session.selectedTab?.url, first,
            "Reopening should select the existing tab — in class the same lesson gets tapped twice"
        )
    }

    func testOpeningSeveralActivatesOnlyTheFirst() throws {
        let session = makeSession()
        let urls = try [makePDF(named: "one"), makePDF(named: "two"), makePDF(named: "three")]

        session.open(urls: urls)

        XCTAssertEqual(session.tabs.count, 3)
        XCTAssertEqual(session.selectedTab?.url, urls[0], "The rest open behind the first")
    }

    // MARK: - Closing

    func testClosingRemovesTheTab() throws {
        let session = makeSession()
        let urls = try [makePDF(named: "one"), makePDF(named: "two")]
        session.open(urls: urls)

        session.close(session.tabs[0].id)

        XCTAssertEqual(session.tabs.map(\.url), [urls[1]])
    }

    func testClosingTheSelectedTabSelectsTheOneThatTookItsPlace() throws {
        let session = makeSession()
        let urls = try [makePDF(named: "one"), makePDF(named: "two"), makePDF(named: "three")]
        session.open(urls: urls)
        session.selectedTabID = session.tabs[1].id

        session.close(session.tabs[1].id)

        XCTAssertEqual(
            session.selectedTab?.url, urls[2],
            "The neighbour that slid into the closed index should be selected"
        )
    }

    func testClosingTheLastTabSelectsTheNewLast() throws {
        let session = makeSession()
        let urls = try [makePDF(named: "one"), makePDF(named: "two")]
        session.open(urls: urls)
        session.selectedTabID = session.tabs[1].id

        session.close(session.tabs[1].id)

        XCTAssertEqual(session.selectedTab?.url, urls[0], "Falls back to the new last tab")
    }

    func testClosingTheOnlyTabLeavesNothingSelected() throws {
        let session = makeSession()
        session.open(url: try makePDF(named: "one"))

        session.close(session.tabs[0].id)

        XCTAssertTrue(session.tabs.isEmpty)
        XCTAssertNil(session.selectedTabID, "Nothing left to select")
    }

    func testClosingAnUnselectedTabKeepsTheSelection() throws {
        let session = makeSession()
        let urls = try [makePDF(named: "one"), makePDF(named: "two")]
        session.open(urls: urls)
        session.selectedTabID = session.tabs[1].id

        session.close(session.tabs[0].id)

        XCTAssertEqual(session.selectedTab?.url, urls[1])
    }

    // MARK: - Reordering

    func testMovingATabLeftwards() throws {
        let session = makeSession()
        let urls = try [makePDF(named: "one"), makePDF(named: "two"), makePDF(named: "three")]
        session.open(urls: urls)

        session.move(id: session.tabs[2].id, before: session.tabs[0].id)

        XCTAssertEqual(session.tabs.map(\.title), ["three", "one", "two"])
    }

    func testMovingATabRightwards() throws {
        let session = makeSession()
        let urls = try [makePDF(named: "one"), makePDF(named: "two"), makePDF(named: "three")]
        session.open(urls: urls)

        session.move(id: session.tabs[0].id, before: session.tabs[2].id)

        XCTAssertEqual(
            session.tabs.map(\.title), ["two", "three", "one"],
            "Moving rightwards lands after the target, not before it"
        )
    }

    func testMovingATabOntoItselfChangesNothing() throws {
        let session = makeSession()
        session.open(urls: try [makePDF(named: "one"), makePDF(named: "two")])

        session.move(id: session.tabs[0].id, before: session.tabs[0].id)

        XCTAssertEqual(session.tabs.map(\.title), ["one", "two"])
    }

    // MARK: - Position tracking and restore

    func testRecordingAPagePersistsIt() throws {
        let session = makeSession()
        session.open(url: try makePDF(named: "one"))
        session.recordPage(1, for: session.tabs[0].id)

        let reopened = makeSession()
        reopened.restore()

        XCTAssertEqual(reopened.tabs.count, 1)
        XCTAssertEqual(reopened.tabs[0].pageIndex, 1, "Page position should survive a relaunch")
    }

    func testRestoreReopensTabsAndSelection() throws {
        let session = makeSession()
        let urls = try [makePDF(named: "one"), makePDF(named: "two")]
        session.open(urls: urls)
        session.selectedTabID = session.tabs[1].id
        session.recordPage(0, for: session.tabs[1].id)

        let reopened = makeSession()
        reopened.restore()

        XCTAssertEqual(reopened.tabs.map(\.title), ["one", "two"])
        XCTAssertEqual(reopened.selectedTab?.title, "two", "Selection should survive too")
    }

    func testRestoreDropsTabsWhoseFilesAreGone() throws {
        let session = makeSession()
        let kept = try makePDF(named: "kept")
        let doomed = try makePDF(named: "doomed")
        session.open(urls: [kept, doomed])

        try FileManager.default.removeItem(at: doomed)

        let reopened = makeSession()
        reopened.restore()

        XCTAssertEqual(
            reopened.tabs.map(\.title), ["kept"],
            "A deleted lesson should be dropped, not reopened as a broken tab"
        )
    }

    func testRestoreOfAnEmptySessionSelectsNothing() {
        let session = makeSession()
        session.restore()

        XCTAssertTrue(session.tabs.isEmpty)
        XCTAssertNil(session.selectedTabID)
    }

    func testOpeningAFileThatIsNotAPDFRecordsFailureWithoutCrashing() throws {
        let session = makeSession()
        let url = directory.appending(path: "not-a-pdf.pdf")
        try Data("this is not a PDF".utf8).write(to: url)

        session.open(url: url)

        XCTAssertEqual(session.tabs.count, 1, "The tab still opens…")
        XCTAssertNotNil(session.tabs[0].loadFailure, "…and reports the failure")
        XCTAssertEqual(session.tabs[0].pageCount, 0)
    }
}
