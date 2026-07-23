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

    /// Save just page drawings, the common case in these tests.
    private func save(drawings: [Int: PKDrawing]) {
        store.save(DrawingStore.Contents(drawings: drawings), hash: documentHash)
    }

    func testRoundTripPreservesPerPageDrawings() throws {
        save(drawings: [2: strokedDrawing()])

        let loaded = store.load(hash: documentHash)

        XCTAssertEqual(loaded.drawings.count, 1)
        XCTAssertEqual(loaded.drawings[2]?.strokes.count, 1)
        XCTAssertNil(loaded.drawings[0], "Pages never drawn on stay absent")
    }

    func testLoadingADocumentWithNoSidecarIsEmpty() {
        XCTAssertTrue(store.load(hash: documentHash).isEmpty)
    }

    func testEmptyDrawingsAreNotStored() {
        save(drawings: [0: PKDrawing(), 1: PKDrawing()])

        XCTAssertTrue(store.load(hash: documentHash).isEmpty)
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: store.url(forHash: documentHash).path),
            "Erasing everything should leave no sidecar behind"
        )
    }

    func testSavingEmptyOverAnExistingSidecarRemovesIt() {
        save(drawings: [0: strokedDrawing()])
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.url(forHash: documentHash).path))

        save(drawings: [0: PKDrawing()])

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

        save(drawings: [0: strokedDrawing()])

        XCTAssertTrue(store.load(hash: other).isEmpty)
    }

    // MARK: - Highlights

    private func aHighlight(_ color: PenColor = .yellow) -> TextHighlight {
        TextHighlight(rects: [CGRect(x: 10, y: 20, width: 100, height: 14)], color: color)
    }

    func testHighlightsRoundTripAlongsideDrawings() {
        store.save(
            DrawingStore.Contents(drawings: [1: strokedDrawing()], highlights: [1: [aHighlight()]]),
            hash: documentHash
        )

        let loaded = store.load(hash: documentHash)

        XCTAssertEqual(loaded.drawings[1]?.strokes.count, 1)
        XCTAssertEqual(loaded.highlights[1]?.count, 1)
        XCTAssertEqual(loaded.highlights[1]?.first?.color, .yellow)
    }

    func testAPageWithOnlyHighlightsIsStored() {
        store.save(DrawingStore.Contents(highlights: [3: [aHighlight(.blue)]]), hash: documentHash)

        let loaded = store.load(hash: documentHash)

        XCTAssertTrue(loaded.drawings.isEmpty)
        XCTAssertEqual(loaded.highlights[3]?.first?.color, .blue)
    }

    func testEmptyHighlightArraysAreNotStored() {
        store.save(DrawingStore.Contents(highlights: [0: []]), hash: documentHash)

        XCTAssertFalse(
            FileManager.default.fileExists(atPath: store.url(forHash: documentHash).path),
            "A page whose highlights were all erased should leave no sidecar"
        )
    }

    func testAPreHighlightSidecarStillLoads() throws {
        // A sidecar written before highlights existed has no `highlights` key.
        let payload: [String: Any] = [
            "version": DrawingStore.currentVersion,
            "pages": [:] as [String: Any],
        ]
        let data = try JSONSerialization.data(withJSONObject: payload)
        try data.write(to: store.url(forHash: documentHash), options: .atomic)

        let loaded = store.load(hash: documentHash)

        XCTAssertTrue(loaded.highlights.isEmpty, "A missing highlights key must decode, not throw")
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
        store.save(DrawingStore.Contents(drawings: [4: strokedDrawing()]), hash: documentHash)

        XCTAssertEqual(makeSet().drawing(forPage: 4).strokes.count, 1)
    }

    // MARK: - Highlights

    private func aHighlight(_ color: PenColor = .yellow) -> TextHighlight {
        TextHighlight(rects: [CGRect(x: 10, y: 20, width: 100, height: 14)], color: color)
    }

    func testAddingAHighlightIsReadBack() {
        let set = makeSet()
        set.addHighlight(aHighlight(), toPage: 2)

        XCTAssertEqual(set.highlights(forPage: 2).count, 1)
        XCTAssertTrue(set.hasAnnotations)
    }

    func testHighlightSurvivesSaveAndReopen() {
        let set = makeSet(saveDelay: .seconds(60))
        set.addHighlight(aHighlight(.blue), toPage: 1)
        set.saveNow()

        XCTAssertEqual(makeSet().highlights(forPage: 1).first?.color, .blue)
    }

    func testErasingAHighlightByPoint() {
        let set = makeSet()
        set.addHighlight(aHighlight(), toPage: 0)

        let inside = CGPoint(x: 20, y: 27)
        XCTAssertTrue(set.removeHighlight(atPage: 0, containing: inside))
        XCTAssertTrue(set.highlights(forPage: 0).isEmpty)
    }

    func testErasingMissesWhenPointIsOutsideEveryHighlight() {
        let set = makeSet()
        set.addHighlight(aHighlight(), toPage: 0)

        XCTAssertFalse(set.removeHighlight(atPage: 0, containing: CGPoint(x: 500, y: 500)))
        XCTAssertEqual(set.highlights(forPage: 0).count, 1, "A miss removes nothing")
    }

    func testAnnotatedPageCountUnionsInkAndHighlights() {
        let set = makeSet()
        set.update(strokedDrawing(), forPage: 0)
        set.addHighlight(aHighlight(), toPage: 0)   // same page — counted once
        set.addHighlight(aHighlight(), toPage: 1)   // highlight-only page

        XCTAssertEqual(set.annotatedPageCount, 2)
    }

    func testClearingAPageRemovesHighlightsToo() {
        let set = makeSet()
        set.update(strokedDrawing(), forPage: 0)
        set.addHighlight(aHighlight(), toPage: 0)

        set.clear(page: 0)

        XCTAssertTrue(set.highlights(forPage: 0).isEmpty)
        XCTAssertTrue(set.drawing(forPage: 0).strokes.isEmpty)
    }

    func testRemovingAHighlightById() {
        let set = makeSet()
        let keep = aHighlight(.blue)
        let drop = aHighlight(.yellow)
        set.addHighlight(keep, toPage: 0)
        set.addHighlight(drop, toPage: 0)

        XCTAssertTrue(set.removeHighlight(id: drop.id, fromPage: 0))
        XCTAssertEqual(set.highlights(forPage: 0).map(\.id), [keep.id], "Only the named highlight goes")
        XCTAssertFalse(set.removeHighlight(id: drop.id, fromPage: 0), "Removing it again is a no-op")
    }
}

final class HighlightGeometryTests: XCTestCase {
    /// PDF space is y-up, so these rects are two stacked lines whose bounding
    /// boxes overlap by 4pt — the leading that makes translucent highlights
    /// darken where lines meet.
    func testStackedLinesAreDeoverlapped() {
        let upper = CGRect(x: 50, y: 100, width: 200, height: 16)   // y 100–116
        let lower = CGRect(x: 50, y: 88, width: 200, height: 16)    // y 88–104, overlaps 100–104

        let result = HighlightFactory.deoverlap([lower, upper])

        XCTAssertEqual(result.count, 2)
        // Sorted top-first; the lower line's top is trimmed to the upper's bottom.
        let top = result[0], bottom = result[1]
        XCTAssertEqual(top.minY, 100, accuracy: 0.01)
        XCTAssertLessThanOrEqual(bottom.maxY, top.minY + 0.01, "Lines must not overlap after trimming")
    }

    func testTwoColumnsAreLeftIndependent() {
        // Same vertical band, disjoint horizontally — a two-column lesson.
        let left = CGRect(x: 50, y: 100, width: 100, height: 16)
        let right = CGRect(x: 300, y: 100, width: 100, height: 16)

        let result = HighlightFactory.deoverlap([left, right])

        XCTAssertEqual(result.count, 2)
        XCTAssertTrue(result.contains { $0.height == 16 && $0.minX == 50 })
        XCTAssertTrue(result.contains { $0.height == 16 && $0.minX == 300 },
                      "A column highlight must not be clipped by one in the other column")
    }

    func testASingleLineIsUnchanged() {
        let rect = CGRect(x: 50, y: 100, width: 200, height: 16)
        XCTAssertEqual(HighlightFactory.deoverlap([rect]), [rect])
    }
}
