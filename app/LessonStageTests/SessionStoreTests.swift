import XCTest
@testable import LessonStage

/// Persistence and bookmark handling — the parts most likely to break
/// silently, because a bad bookmark only shows up a launch later.
final class SessionStoreTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appending(path: "session-store-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func makeStore() -> SessionStore {
        SessionStore(filename: "session-\(UUID().uuidString).json")
    }

    func testRoundTrip() throws {
        let store = makeStore()
        let id = UUID()
        let session = SessionStore.PersistedSession(
            tabs: [
                .init(id: id, bookmark: Data("bookmark".utf8), title: "one", pageIndex: 3),
            ],
            selectedID: id
        )

        store.save(session)
        let loaded = store.load()

        XCTAssertEqual(loaded.tabs.count, 1)
        XCTAssertEqual(loaded.tabs[0].id, id)
        XCTAssertEqual(loaded.tabs[0].title, "one")
        XCTAssertEqual(loaded.tabs[0].pageIndex, 3)
        XCTAssertEqual(loaded.selectedID, id)
    }

    func testLoadingWhenNothingWasEverSavedReturnsAnEmptySession() {
        XCTAssertTrue(makeStore().load().tabs.isEmpty)
    }

    func testUnreadableSessionIsDiscardedRatherThanThrown() throws {
        let filename = "corrupt-\(UUID().uuidString).json"
        let path = URL.applicationSupportDirectory.appending(path: filename)
        try Data("{ this is not json".utf8).write(to: path, options: .atomic)
        defer { try? FileManager.default.removeItem(at: path) }

        // A session that cannot be read must not be able to fail a launch.
        let loaded = SessionStore(filename: filename).load()

        XCTAssertTrue(loaded.tabs.isEmpty)
        XCTAssertNil(loaded.selectedID)
    }

    func testBookmarkRoundTripResolvesToTheSameFile() throws {
        let url = directory.appending(path: "lesson.pdf")
        try TestPDF.data().write(to: url, options: .atomic)

        let bookmark = try XCTUnwrap(SessionStore.makeBookmark(for: url))
        let resolved = try XCTUnwrap(SessionStore.resolve(bookmark: bookmark))

        XCTAssertEqual(
            resolved.url.resolvingSymlinksInPath(),
            url.resolvingSymlinksInPath()
        )
    }

    func testResolvingABookmarkToADeletedFileFails() throws {
        let url = directory.appending(path: "doomed.pdf")
        try TestPDF.data().write(to: url, options: .atomic)
        let bookmark = try XCTUnwrap(SessionStore.makeBookmark(for: url))

        try FileManager.default.removeItem(at: url)

        XCTAssertNil(
            SessionStore.resolve(bookmark: bookmark),
            "A bookmark to a deleted file must fail so the tab can be dropped"
        )
    }

    func testResolvingAGarbageBookmarkFails() {
        XCTAssertNil(SessionStore.resolve(bookmark: Data("not a bookmark".utf8)))
    }
}
