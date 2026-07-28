import PDFKit
import XCTest
@testable import LessonStage

/// The Contract 5 payload path — attachment extraction and click-map parsing —
/// against the real `new-minor-forcing.pdf` fixture. Verifies the code against
/// a payload the print engine actually produced, as the contract requires.
final class LessonPayloadTests: XCTestCase {
    private func fixture() throws -> PDFDocument {
        try Fixtures.document(Fixtures.newMinorForcing)
    }

    // MARK: - Attachment extraction

    func testExtractsTheFourEmbeddedFilesWithRelationships() throws {
        let files = LessonAttachments.files(in: try fixture())

        XCTAssertEqual(
            Set(files.map(\.filename)),
            ["lesson-source.md", "lesson-provenance.json", "lesson-blocks.json", "lesson-hands.pbn"]
        )
        let byName = Dictionary(uniqueKeysWithValues: files.map { ($0.filename, $0) })
        XCTAssertEqual(byName["lesson-source.md"]?.relationship, "Source")
        XCTAssertEqual(byName["lesson-provenance.json"]?.relationship, "Supplement")
        XCTAssertEqual(byName["lesson-blocks.json"]?.relationship, "Data")
        XCTAssertEqual(byName["lesson-hands.pbn"]?.relationship, "Data")
        XCTAssertFalse(byName["lesson-blocks.json"]?.data.isEmpty ?? true, "Stream decoded to bytes")
    }

    // MARK: - Click map

    func testParsesTheClickMap() throws {
        let payload = try XCTUnwrap(LessonPayload.load(from: try fixture()))
        let map = payload.map

        XCTAssertEqual(map.version, 1)
        XCTAssertEqual(map.blocks.map(\.index), [0, 1, 2, 3])
        XCTAssertEqual(map.blocks.map(\.kind), ["auction", "hand", "response-box", "auction"])
        XCTAssertTrue(map.unlocatedIndices.isEmpty)
        XCTAssertTrue(map.blocks[1].body.contains("A Q 9 5 4"), "Hand body carries the cards")
    }

    func testBoardJoinSplitsByKind() throws {
        let map = try XCTUnwrap(LessonPayload.load(from: try fixture())).map

        XCTAssertNil(map.blocks[0].boardNumber, "Auction with a null deal has no board")
        XCTAssertEqual(map.blocks[1].boardNumber, 1, "Hand block joins via `board`")
        XCTAssertNil(map.blocks[2].boardNumber, "Response box has no deal")
        XCTAssertEqual(map.blocks[3].boardNumber, 1, "Auction block joins via `deal`")
    }

    func testRectDecodesAsMinMaxAndConvertsToPageRect() throws {
        let map = try XCTUnwrap(LessonPayload.load(from: try fixture())).map

        // rect [45, 261, 198, 352.5] is [minX, minY, maxX, maxY].
        XCTAssertEqual(map.blocks[0].pageRect, CGRect(x: 45, y: 261, width: 153, height: 91.5))
        XCTAssertEqual(map.blocks[0].pageIndex, 0, "page is 1-based in the file")
    }

    /// The two routes in must agree: the click-map rect and the link-annotation
    /// bounds are the same rectangle. Disagreement is the tell-tale of the
    /// y-flip mistake, which is exactly what the debug overlay guards against.
    func testClickMapRectsMatchTheLinkAnnotationBounds() throws {
        let document = try fixture()
        let map = try XCTUnwrap(LessonPayload.load(from: document)).map
        let targets = LessonBlockLinks.targets(in: document)
        XCTAssertEqual(targets.count, 4)

        for target in targets {
            let block = try XCTUnwrap(map.blocks.first { $0.index == target.index })
            let rect = try XCTUnwrap(block.pageRect)
            XCTAssertEqual(rect.minX, target.bounds.minX, accuracy: 0.5, "block \(target.index) x")
            XCTAssertEqual(rect.minY, target.bounds.minY, accuracy: 0.5, "block \(target.index) y")
            XCTAssertEqual(rect.width, target.bounds.width, accuracy: 0.5, "block \(target.index) w")
            XCTAssertEqual(rect.height, target.bounds.height, accuracy: 0.5, "block \(target.index) h")
        }
    }

    // MARK: - PBN

    func testCarriesTheRawPBN() throws {
        let payload = try XCTUnwrap(LessonPayload.load(from: try fixture()))
        let pbn = try XCTUnwrap(payload.pbn)
        XCTAssertTrue(pbn.contains("[Board \"1\"]"))
        XCTAssertTrue(pbn.contains("[Deal \"S:AQ954.K73.A5.J84 - - -\"]"), "A partial deal — only South")
    }

    // MARK: - Resolving a tapped block

    func testResolveJoinsBodyAndDealForAHandBlock() throws {
        let payload = try XCTUnwrap(LessonPayload.load(from: try fixture()))

        // Block 1 is the hand, joined to board 1.
        let resolved = try XCTUnwrap(payload.resolve(index: 1))
        XCTAssertEqual(resolved.kind, "hand")
        XCTAssertTrue(resolved.body.contains("A Q 9 5 4"))
        XCTAssertEqual(resolved.pbn?.contains("[Board \"1\"]"), true, "The hand carries its board's PBN")
    }

    func testResolveForAnAuctionBoundToADeal() throws {
        let payload = try XCTUnwrap(LessonPayload.load(from: try fixture()))

        // Block 3 is the second auction, bound to deal 1.
        let resolved = try XCTUnwrap(payload.resolve(index: 3))
        XCTAssertEqual(resolved.kind, "auction")
        XCTAssertEqual(resolved.pbn?.contains("[Board \"1\"]"), true)
    }

    func testResolveForABlockWithNoDealCarriesNoPBN() throws {
        let payload = try XCTUnwrap(LessonPayload.load(from: try fixture()))

        // Block 0 is an auction with `deal: null`; block 2 is a response box.
        XCTAssertNil(try XCTUnwrap(payload.resolve(index: 0)).pbn)
        XCTAssertNil(try XCTUnwrap(payload.resolve(index: 2)).pbn)
    }

    func testResolveUnknownIndexIsNil() throws {
        let payload = try XCTUnwrap(LessonPayload.load(from: try fixture()))
        XCTAssertNil(payload.resolve(index: 99))
    }

    func testResolvedMessageIsTheSeamPayload() throws {
        let payload = try XCTUnwrap(LessonPayload.load(from: try fixture()))
        let message = try XCTUnwrap(payload.resolve(index: 1)).message

        XCTAssertEqual(message["kind"] as? String, "hand")
        XCTAssertNotNil(message["blockBody"] as? String)
        XCTAssertNotNil(message["pbn"] as? String)
    }

    // MARK: - Degraded PDFs

    func testPlainPDFHasNoPayload() {
        let doc = PDFDocument(data: TestPDF.data(pages: 1))!
        XCTAssertNil(LessonPayload.load(from: doc), "A PDF with no attachments falls back to plain-PDF mode")
    }

    /// The app now opens files as `Data` (a coordinated read, for fresh content),
    /// so the Contract 5 walk must work on a `Data`-backed document, not only a
    /// URL-backed one.
    func testPayloadAndBlocksLoadFromADataBackedDocument() throws {
        let url = Fixtures.url(Fixtures.newMinorForcing)
        guard let data = try? Data(contentsOf: url) else { throw XCTSkip("Fixture missing at \(url.path)") }
        let document = try XCTUnwrap(PDFDocument(data: data))

        let payload = try XCTUnwrap(LessonPayload.load(from: document), "documentRef walk works from Data")
        XCTAssertEqual(payload.map.blocks.count, 4)
        XCTAssertEqual(LessonBlockLinks.targets(in: document).count, 4, "Link annotations resolve too")
    }
}
