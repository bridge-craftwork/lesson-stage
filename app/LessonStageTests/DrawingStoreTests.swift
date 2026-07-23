import PencilKit
import XCTest
@testable import LessonStage

final class ContentHashTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appending(path: "content-hash-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func write(_ contents: String, named name: String) throws -> URL {
        let url = directory.appending(path: name)
        try Data(contents.utf8).write(to: url, options: .atomic)
        return url
    }

    func testSameContentHashesTheSameRegardlessOfName() throws {
        let first = try write("a lesson", named: "one.pdf")
        let second = try write("a lesson", named: "renamed.pdf")

        XCTAssertEqual(
            ContentHash.sha256(of: first), ContentHash.sha256(of: second),
            "Annotations must survive a rename, which is why the key is content"
        )
    }

    func testDifferentContentHashesDifferently() throws {
        let first = try write("lesson one", named: "one.pdf")
        let second = try write("lesson two", named: "two.pdf")

        XCTAssertNotEqual(ContentHash.sha256(of: first), ContentHash.sha256(of: second))
    }

    func testHashIsStableAcrossTheChunkBoundary() throws {
        // The reader streams in 256 KB chunks; a file spanning several of them
        // must hash the same as the one-shot digest of its bytes.
        let url = directory.appending(path: "large.pdf")
        let bytes = Data((0..<(1 << 20)).map { UInt8($0 % 251) })
        try bytes.write(to: url, options: .atomic)

        let streamed = ContentHash.sha256(of: url)
        let rewritten = try write(String(decoding: Data("x".utf8), as: UTF8.self), named: "small.pdf")

        XCTAssertNotNil(streamed)
        XCTAssertEqual(streamed?.count, 64, "SHA-256 renders as 64 hex characters")
        XCTAssertNotEqual(streamed, ContentHash.sha256(of: rewritten))
    }

    func testMissingFileHashesToNil() {
        XCTAssertNil(ContentHash.sha256(of: directory.appending(path: "absent.pdf")))
    }
}

final class DrawingStoreTests: XCTestCase {
    private var store: DrawingStore!
    private var documentHash: String!

    override func setUp() {
        super.setUp()
        store = DrawingStore(directoryName: "AnnotationTests-\(UUID().uuidString)")
        documentHash = UUID().uuidString
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: store.url(forHash: documentHash))
        super.tearDown()
    }

    /// A drawing with one real stroke, built without a Pencil.
    private func strokedDrawing(from: CGPoint = .zero, to: CGPoint = CGPoint(x: 100, y: 100)) -> PKDrawing {
        let ink = PKInk(.pen, color: .black)
        let points = stride(from: 0.0, through: 1.0, by: 0.1).map { t in
            PKStrokePoint(
                location: CGPoint(
                    x: from.x + (to.x - from.x) * t,
                    y: from.y + (to.y - from.y) * t
                ),
                timeOffset: t,
                size: CGSize(width: 3, height: 3),
                opacity: 1,
                force: 1,
                azimuth: 0,
                altitude: .pi / 2
            )
        }
        let path = PKStrokePath(controlPoints: points, creationDate: Date(timeIntervalSince1970: 0))
        return PKDrawing(strokes: [PKStroke(ink: ink, path: path)])
    }

    func testRoundTripPreservesPerPageDrawings() throws {
        let drawing = strokedDrawing()
        store.save([2: drawing], hash: documentHash)

        let loaded = store.load(hash: documentHash)

        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded[2]?.strokes.count, 1)
        XCTAssertNil(loaded[0], "Pages never drawn on stay absent")
    }

    func testLoadingADocumentWithNoSidecarIsEmpty() {
        XCTAssertTrue(store.load(hash: documentHash).isEmpty)
    }

    func testEmptyDrawingsAreNotStored() {
        store.save([0: PKDrawing(), 1: PKDrawing()], hash: documentHash)

        XCTAssertTrue(store.load(hash: documentHash).isEmpty)
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: store.url(forHash: documentHash).path),
            "Erasing everything should leave no sidecar behind"
        )
    }

    func testSavingEmptyOverAnExistingSidecarRemovesIt() {
        store.save([0: strokedDrawing()], hash: documentHash)
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.url(forHash: documentHash).path))

        store.save([0: PKDrawing()], hash: documentHash)

        XCTAssertFalse(FileManager.default.fileExists(atPath: store.url(forHash: documentHash).path))
    }

    func testCorruptSidecarIsDiscardedRatherThanThrown() throws {
        try Data("{ not json".utf8).write(to: store.url(forHash: documentHash), options: .atomic)

        XCTAssertTrue(store.load(hash: documentHash).isEmpty, "A bad sidecar costs annotations, not a launch")
    }

    func testSidecarFromAFutureVersionIsNotRead() throws {
        let payload: [String: Any] = ["version": DrawingStore.currentVersion + 1, "pages": [:]]
        let data = try JSONSerialization.data(withJSONObject: payload)
        try data.write(to: store.url(forHash: documentHash), options: .atomic)

        XCTAssertTrue(
            store.load(hash: documentHash).isEmpty,
            "An older build must not read — and then overwrite — a newer sidecar"
        )
    }

    func testDocumentsWithDifferentHashesDoNotShareAnnotations() {
        let other = UUID().uuidString
        defer { try? FileManager.default.removeItem(at: store.url(forHash: other)) }

        store.save([0: strokedDrawing()], hash: documentHash)

        XCTAssertTrue(store.load(hash: other).isEmpty)
    }
}

@MainActor
final class DrawingSetTests: XCTestCase {
    private var store: DrawingStore!
    private var documentHash: String!

    override func setUp() {
        super.setUp()
        store = DrawingStore(directoryName: "AnnotationSetTests-\(UUID().uuidString)")
        documentHash = UUID().uuidString
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: store.url(forHash: documentHash))
        super.tearDown()
    }

    private func strokedDrawing() -> PKDrawing {
        let points = (0...5).map { i in
            PKStrokePoint(
                location: CGPoint(x: Double(i) * 10, y: 0),
                timeOffset: Double(i) / 10,
                size: CGSize(width: 3, height: 3),
                opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2
            )
        }
        return PKDrawing(strokes: [
            PKStroke(
                ink: PKInk(.pen, color: .black),
                path: PKStrokePath(controlPoints: points, creationDate: Date(timeIntervalSince1970: 0))
            )
        ])
    }

    private func makeSet(saveDelay: Duration = .milliseconds(20)) -> DrawingSet {
        DrawingSet(contentHash: documentHash, store: store, saveDelay: saveDelay)
    }

    func testUpdatingAPageIsReadBack() {
        let set = makeSet()
        set.update(strokedDrawing(), forPage: 1)

        XCTAssertEqual(set.drawing(forPage: 1).strokes.count, 1)
        XCTAssertTrue(set.hasAnnotations)
    }

    func testUntouchedPagesAreEmpty() {
        XCTAssertTrue(makeSet().drawing(forPage: 7).strokes.isEmpty)
    }

    func testSaveNowPersistsForTheNextOpen() {
        let set = makeSet(saveDelay: .seconds(60))
        set.update(strokedDrawing(), forPage: 0)
        set.saveNow()

        let reopened = makeSet()

        XCTAssertEqual(
            reopened.drawing(forPage: 0).strokes.count, 1,
            "Annotations should survive closing and reopening the document"
        )
    }

    func testDebouncedSaveEventuallyWrites() async throws {
        let set = makeSet(saveDelay: .milliseconds(20))
        set.update(strokedDrawing(), forPage: 0)

        try await Task.sleep(for: .milliseconds(400))

        XCTAssertEqual(makeSet().drawing(forPage: 0).strokes.count, 1)
    }

    func testClearingAPageRemovesIt() {
        let set = makeSet(saveDelay: .seconds(60))
        set.update(strokedDrawing(), forPage: 3)
        set.clear(page: 3)
        set.saveNow()

        XCTAssertTrue(set.drawing(forPage: 3).strokes.isEmpty)
        XCTAssertTrue(makeSet().drawing(forPage: 3).strokes.isEmpty)
    }

    func testLoadsExistingAnnotationsOnInit() {
        store.save([4: strokedDrawing()], hash: documentHash)

        XCTAssertEqual(makeSet().drawing(forPage: 4).strokes.count, 1)
    }
}
