import XCTest
@testable import LessonStage

/// Discovery against a temp folder that mirrors the real layout:
/// root / <year> / <month> / <day> / Handouts / *.pdf, with a couple of the
/// wrinkles the real tree has (a month folder that isn't a day, an empty
/// future day, ignore-matching filenames).
final class LessonLibraryTests: XCTestCase {
    private var root: URL!
    private var config: LibraryConfiguration!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appending(path: "library-tests-\(UUID().uuidString)", directoryHint: .isDirectory)

        // 2026 / 2026-07 Jul / <days> / Handouts
        try makeDay("2026/2026-07 Jul/2026-07-07", handouts: ["Morning Handouts.pdf"])
        try makeDay("2026/2026-07 Jul/2026-07-14", handouts: ["A.pdf", "B.pdf"])
        try makeDay(
            "2026/2026-07 Jul/2026-07-21",
            handouts: [
                "2026-07-21 Morning Handouts.pdf",
                "2026-07-21 Zoom Handouts.pdf",     // ignored
                "Sign-in Morning.pdf",              // ignored
                "notes.txt",                         // not a PDF
            ]
        )
        // A precreated-but-empty future day (no Handouts subfolder).
        try FileManager.default.createDirectory(
            at: root.appending(path: "2026/2026-07 Jul/2026-07-28"),
            withIntermediateDirectories: true
        )
        try makeDay("2026/2026-08 Aug/2026-08-04", handouts: ["C.pdf"])

        config = LibraryConfiguration(rootBookmark: Data())
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func makeDay(_ path: String, handouts: [String]) throws {
        let handoutsDir = root.appending(path: path).appending(path: "Handouts")
        try FileManager.default.createDirectory(at: handoutsDir, withIntermediateDirectories: true)
        for name in handouts {
            try Data("x".utf8).write(to: handoutsDir.appending(path: name))
        }
    }

    private func date(_ iso: String) -> Date {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.date(from: iso)!
    }

    func testFindsEveryDatedDayRegardlessOfMonthFolderNames() {
        let days = LessonLibrary.discoverDays(root: root, config: config)

        XCTAssertEqual(
            days.map { $0.folderURL.lastPathComponent },
            ["2026-07-07", "2026-07-14", "2026-07-21", "2026-07-28", "2026-08-04"],
            "Day folders found across months and sorted by date; month folders themselves are not days"
        )
    }

    func testHandoutsAreIgnoreFilteredAndPdfOnly() {
        let days = LessonLibrary.discoverDays(root: root, config: config)
        let july21 = days.first { $0.folderURL.lastPathComponent == "2026-07-21" }!

        XCTAssertEqual(
            july21.handouts.map(\.name),
            ["2026-07-21 Morning Handouts"],
            "Zoom and Sign-in are dropped, the .txt is not a handout"
        )
    }

    func testAnEmptyFutureDayIsListedButUnpopulated() {
        let days = LessonLibrary.discoverDays(root: root, config: config)
        let july28 = days.first { $0.folderURL.lastPathComponent == "2026-07-28" }!

        XCTAssertTrue(july28.handouts.isEmpty)
        XCTAssertFalse(july28.isPopulated, "A precreated but unplanned day shows with nothing to open")
    }

    func testWindowAnchorsOnTodayOrNext() {
        let days = LessonLibrary.discoverDays(root: root, config: config)

        // Mid-week: the 21st is the next class.
        let window = LessonLibrary.window(days, around: date("2026-07-16"), before: 3, after: 5)
        XCTAssertEqual(
            window.map { $0.folderURL.lastPathComponent },
            ["2026-07-07", "2026-07-14", "2026-07-21", "2026-07-28", "2026-08-04"]
        )

        let anchor = LessonLibrary.anchorDay(in: days, today: date("2026-07-16"))
        XCTAssertEqual(anchor?.folderURL.lastPathComponent, "2026-07-21", "Today-or-next is the anchor")
    }

    func testWindowClampsAndLimitsToBeforeCount() {
        let days = LessonLibrary.discoverDays(root: root, config: config)

        // Far future: everything is history; keep the last `before` days.
        let window = LessonLibrary.window(days, around: date("2027-01-01"), before: 2, after: 5)
        XCTAssertEqual(
            window.map { $0.folderURL.lastPathComponent },
            ["2026-07-28", "2026-08-04"],
            "With no future days, show the most recent `before` days"
        )
    }

    func testWindowLimitsForwardToAfterCount() {
        let days = LessonLibrary.discoverDays(root: root, config: config)

        // Before everything: today-or-next is the very first day, cap forward.
        let window = LessonLibrary.window(days, around: date("2026-01-01"), before: 3, after: 2)
        XCTAssertEqual(
            window.map { $0.folderURL.lastPathComponent },
            ["2026-07-07", "2026-07-14"],
            "Anchor at the first day; show it and one more, nothing before"
        )
    }

    func testLocalFilesReadAsAvailable() {
        let days = LessonLibrary.discoverDays(root: root, config: config)
        let handout = days.first { !$0.handouts.isEmpty }!.handouts[0]
        XCTAssertTrue(handout.isLocal, "A file on disk is openable")
    }
}

final class GlobTests: XCTestCase {
    func testStarMatchesAnywhere() {
        XCTAssertTrue(Glob.matches("*Zoom*", "2026-07-21 Zoom Handouts.pdf"))
        XCTAssertTrue(Glob.matches("*sign-in*", "Sign-in Morning.pdf"), "Case-insensitive")
        XCTAssertFalse(Glob.matches("*Zoom*", "Morning Handouts.pdf"))
    }

    func testAnchoredAndLiteral() {
        XCTAssertTrue(Glob.matches("Sign-in*", "Sign-in Afternoon.pdf"))
        XCTAssertFalse(Glob.matches("Sign-in*", "Afternoon Sign-in.pdf"), "Prefix glob is anchored at the start")
    }

    func testMatchesAny() {
        let globs = ["*Zoom*", "*sign-in*"]
        XCTAssertTrue(Glob.matchesAny(globs, "Zoom Handouts.pdf"))
        XCTAssertFalse(Glob.matchesAny(globs, "Morning Handouts.pdf"))
    }
}
