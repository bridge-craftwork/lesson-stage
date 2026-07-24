import PDFKit
import XCTest
@testable import LessonStage

/// Discovery of the `lesson-block:` link annotations Contract 5 leaves in a PDF.
/// The annotations are synthesised here (PDFKit can add link annotations even
/// though it cannot write the embedded attachments), so this needs no fixture.
final class LessonBlockLinksTests: XCTestCase {
    private func document(pages: Int = 1) -> PDFDocument {
        PDFDocument(data: TestPDF.data(pages: pages))!
    }

    private func addLink(_ uri: String, bounds: CGRect, to page: PDFPage) {
        let annotation = PDFAnnotation(bounds: bounds, forType: .link, withProperties: nil)
        annotation.action = PDFActionURL(url: URL(string: uri)!)
        page.addAnnotation(annotation)
    }

    func testFindsLessonBlockLinksWithIndexAndBounds() {
        let doc = document()
        let bounds = CGRect(x: 42, y: 235, width: 159, height: 130)
        addLink("lesson-block:0", bounds: bounds, to: doc.page(at: 0)!)

        let targets = LessonBlockLinks.targets(in: doc)
        XCTAssertEqual(targets.count, 1)
        XCTAssertEqual(targets[0].index, 0)
        XCTAssertEqual(targets[0].pageIndex, 0)
        // Bounds come straight from the annotation, in page space — no y-flip.
        XCTAssertEqual(targets[0].bounds.minX, 42, accuracy: 0.5)
        XCTAssertEqual(targets[0].bounds.minY, 235, accuracy: 0.5)
        XCTAssertEqual(targets[0].bounds.width, 159, accuracy: 0.5)
        XCTAssertEqual(targets[0].bounds.height, 130, accuracy: 0.5)
    }

    func testDuplicateIndexIsSeveralTargets() {
        // A block fragmented across columns: two annotations, one index.
        let doc = document()
        let page = doc.page(at: 0)!
        addLink("lesson-block:3", bounds: CGRect(x: 40, y: 400, width: 100, height: 200), to: page)
        addLink("lesson-block:3", bounds: CGRect(x: 320, y: 400, width: 100, height: 80), to: page)

        let targets = LessonBlockLinks.targets(in: doc)
        XCTAssertEqual(targets.count, 2, "Each fragment is its own tap target")
        XCTAssertEqual(Set(targets.map(\.index)), [3])
    }

    func testIgnoresNonLessonBlockLinksAndOtherAnnotations() {
        let doc = document()
        let page = doc.page(at: 0)!
        addLink("https://example.com", bounds: CGRect(x: 10, y: 10, width: 50, height: 20), to: page)
        page.addAnnotation(PDFAnnotation(bounds: CGRect(x: 10, y: 40, width: 50, height: 20), forType: .highlight, withProperties: nil))
        addLink("lesson-block:7", bounds: CGRect(x: 100, y: 100, width: 80, height: 40), to: page)

        let targets = LessonBlockLinks.targets(in: doc)
        XCTAssertEqual(targets.map(\.index), [7], "Only lesson-block links are targets")
    }

    func testMultiPageDetectionReportsThePage() {
        let doc = document(pages: 3)
        addLink("lesson-block:0", bounds: CGRect(x: 10, y: 10, width: 20, height: 20), to: doc.page(at: 0)!)
        addLink("lesson-block:1", bounds: CGRect(x: 10, y: 10, width: 20, height: 20), to: doc.page(at: 2)!)

        XCTAssertEqual(LessonBlockLinks.targets(in: doc).map(\.pageIndex), [0, 2])
    }

    func testBlockIndexParsing() {
        XCTAssertEqual(LessonBlockLinks.blockIndex(from: URL(string: "lesson-block:0")!), 0)
        XCTAssertEqual(LessonBlockLinks.blockIndex(from: URL(string: "lesson-block:42")!), 42)
        XCTAssertNil(LessonBlockLinks.blockIndex(from: URL(string: "https://x.com")!), "Wrong scheme")
        XCTAssertNil(LessonBlockLinks.blockIndex(from: URL(string: "lesson-block:nope")!), "Non-numeric index")
    }
}

/// The debug x-ray overlay: outlines added and cleared without disturbing the
/// source link annotations.
final class LessonBlockXrayTests: XCTestCase {
    private func documentWithBlocks(_ count: Int) -> PDFDocument {
        let doc = PDFDocument(data: TestPDF.data(pages: 1))!
        let page = doc.page(at: 0)!
        for index in 0..<count {
            let annotation = PDFAnnotation(
                bounds: CGRect(x: 40, y: 40 + index * 30, width: 100, height: 20),
                forType: .link,
                withProperties: nil
            )
            annotation.action = PDFActionURL(url: URL(string: "lesson-block:\(index)")!)
            page.addAnnotation(annotation)
        }
        return doc
    }

    func testApplyAddsOutlinesAndClearRemovesOnlyThem() {
        let doc = documentWithBlocks(2)
        let page = doc.page(at: 0)!
        let originalCount = page.annotations.count // the two source links

        LessonBlockXray.apply(true, to: doc)
        let overlay = page.annotations.filter { $0.userName == LessonBlockXray.ownerTag }
        XCTAssertEqual(overlay.count, 4, "Two blocks → an outline and a label each")
        XCTAssertEqual(page.annotations.count, originalCount + 4, "Source links untouched")

        LessonBlockXray.apply(false, to: doc)
        XCTAssertTrue(page.annotations.allSatisfy { $0.userName != LessonBlockXray.ownerTag })
        XCTAssertEqual(page.annotations.count, originalCount, "Clearing leaves only the originals")
    }

    func testApplyIsIdempotent() {
        let doc = documentWithBlocks(3)
        LessonBlockXray.apply(true, to: doc)
        LessonBlockXray.apply(true, to: doc)

        let overlay = doc.page(at: 0)!.annotations.filter { $0.userName == LessonBlockXray.ownerTag }
        XCTAssertEqual(overlay.count, 6, "Re-applying clears first, so overlays don't stack")
    }
}
