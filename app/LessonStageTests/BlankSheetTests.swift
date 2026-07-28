import PDFKit
import XCTest
@testable import LessonStage

/// Blank sheets are real one-page PDFs, each with distinct bytes so their
/// annotations don't collide.
final class BlankSheetTests: XCTestCase {
    private var created: [URL] = []

    override func tearDownWithError() throws {
        for url in created { try? FileManager.default.removeItem(at: url) }
    }

    func testCreatesAOnePagePDF() throws {
        let url = try XCTUnwrap(BlankSheet.create())
        created.append(url)
        let document = try XCTUnwrap(PDFDocument(url: url))
        XCTAssertEqual(document.pageCount, 1)
    }

    func testEachBlankHasUniqueContent() throws {
        let a = try XCTUnwrap(BlankSheet.create()); created.append(a)
        let b = try XCTUnwrap(BlankSheet.create()); created.append(b)
        XCTAssertNotEqual(
            ContentHash.sha256(of: a), ContentHash.sha256(of: b),
            "Distinct content → distinct annotation sidecars, so two blanks don't share drawings"
        )
    }
}
