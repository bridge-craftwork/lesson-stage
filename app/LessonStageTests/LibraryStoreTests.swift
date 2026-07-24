import XCTest
@testable import LessonStage

/// The library settings persist across launches, and the manager resolves its
/// root bookmark on the next launch — the same guarantees `SessionStore` gives
/// the open tabs, for the library side.
final class LibraryStoreTests: XCTestCase {
    private var filenames: [String] = []

    override func tearDownWithError() throws {
        // Each store writes into the shared app-support container; clean up so
        // one test's file cannot bleed into another's.
        for name in filenames {
            try? FileManager.default.removeItem(at: URL.applicationSupportDirectory.appending(path: name))
        }
    }

    private func uniqueStore() -> (LibraryStore, String) {
        let name = "library-tests-\(UUID().uuidString).json"
        filenames.append(name)
        return (LibraryStore(filename: name), name)
    }

    func testDefaultsToDisabledAndUnconfigured() {
        let (store, _) = uniqueStore()
        let loaded = store.load()
        XCTAssertFalse(loaded.enabled, "The feature is off until turned on")
        XCTAssertNil(loaded.configuration, "No root chosen yet")
    }

    func testRoundTripsEnabledAndConfiguration() {
        let (store, name) = uniqueStore()

        var config = LibraryConfiguration(rootBookmark: Data([1, 2, 3, 4]))
        config.ignoreGlobs = ["*Zoom*", "*draft*"]
        config.windowBefore = 1
        config.windowAfter = 9
        store.save(.init(enabled: true, configuration: config))

        let reloaded = LibraryStore(filename: name).load()
        XCTAssertTrue(reloaded.enabled)
        XCTAssertEqual(reloaded.configuration, config, "Every knob survives the round trip")
    }
}

/// End-to-end through the manager: choosing a folder, discovering its days,
/// and resolving the saved root on a fresh launch.
@MainActor
final class LibraryManagerTests: XCTestCase {
    private var root: URL!
    private var filenames: [String] = []

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appending(path: "library-manager-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try makeDay("2026/2026-07 Jul/2026-07-14", handouts: ["A.pdf", "B.pdf"])
        try makeDay("2026/2026-07 Jul/2026-07-21", handouts: ["Morning.pdf", "Zoom notes.pdf"])
        try makeDay("2026/2026-07 Jul/2026-07-28", handouts: ["C.pdf"])
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
        for name in filenames {
            try? FileManager.default.removeItem(at: URL.applicationSupportDirectory.appending(path: name))
        }
    }

    private func makeDay(_ path: String, handouts: [String]) throws {
        let dir = root.appending(path: path).appending(path: "Handouts")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for name in handouts { try Data("x".utf8).write(to: dir.appending(path: name)) }
    }

    private func uniqueStore() -> (LibraryStore, String) {
        let name = "library-manager-\(UUID().uuidString).json"
        filenames.append(name)
        return (LibraryStore(filename: name), name)
    }

    func testConfiguringDiscoversDaysUnderTheRoot() async {
        let (store, _) = uniqueStore()
        let manager = LibraryManager(store: store)
        XCTAssertFalse(manager.isConfigured)

        manager.setEnabled(true)
        manager.configure(rootURL: root)
        await manager.settle() // discovery runs off-main now

        XCTAssertTrue(manager.isConfigured)
        XCTAssertEqual(
            manager.days.map { $0.folderURL.lastPathComponent },
            ["2026-07-14", "2026-07-21", "2026-07-28"],
            "Configuring runs discovery immediately"
        )
    }

    func testTheEnabledFlagAndRootSurviveARelaunch() async {
        let (_, name) = uniqueStore()

        let first = LibraryManager(store: LibraryStore(filename: name))
        first.setEnabled(true)
        first.configure(rootURL: root)
        await first.settle()

        // A second manager over the same store is the next launch.
        let second = LibraryManager(store: LibraryStore(filename: name))
        XCTAssertTrue(second.enabled, "The enabled flag persists")
        XCTAssertTrue(second.isConfigured, "The root bookmark resolves on launch")

        second.refresh()
        await second.settle()
        XCTAssertEqual(second.days.count, 3, "And discovery works against the resolved root")
    }

    func testEditingTheGlobsRefiltersHandouts() async {
        let (store, _) = uniqueStore()
        let manager = LibraryManager(store: store)
        manager.configure(rootURL: root)
        await manager.settle()

        let july21 = manager.days.first { $0.folderURL.lastPathComponent == "2026-07-21" }!
        XCTAssertEqual(july21.handouts.map(\.name), ["Morning"], "Default *Zoom* glob drops the Zoom notes")

        manager.updateConfiguration { $0.ignoreGlobs = [] }
        await manager.settle()
        let refiltered = manager.days.first { $0.folderURL.lastPathComponent == "2026-07-21" }!
        XCTAssertEqual(refiltered.handouts.map(\.name).sorted(), ["Morning", "Zoom notes"], "Clearing globs shows both")
    }
}
