import PDFKit
import XCTest
@testable import LessonStage

/// Which text row a highlighter drag belongs to, and where that row actually is.
///
/// The hand below is measured from a real lesson handout, and is the case this
/// type exists for: four suit rows 14pt apart whose glyphs are under 10pt tall,
/// but whose PDFKit line boxes are 31pt tall — so each row's box swallows its
/// neighbours, and the rows are of very unequal length.
final class TextRowLayoutTests: XCTestCase {
    private typealias Line = (lineBox: CGRect, band: CGRect)

    private func line(box: ClosedRange<CGFloat>, glyphs: ClosedRange<CGFloat>,
                      x: ClosedRange<CGFloat>) -> Line {
        (lineBox: CGRect(x: x.lowerBound, y: box.lowerBound,
                         width: x.upperBound - x.lowerBound,
                         height: box.upperBound - box.lowerBound),
         band: CGRect(x: x.lowerBound, y: glyphs.lowerBound,
                      width: x.upperBound - x.lowerBound,
                      height: glyphs.upperBound - glyphs.lowerBound))
    }

    private lazy var spades = line(box: 611.2...642.2, glyphs: 617.2...626.9, x: 138.5...204.7)
    private lazy var hearts = line(box: 597.0...628.0, glyphs: 603.2...612.8, x: 138.5...168.9)
    private lazy var diamonds = line(box: 582.8...613.8, glyphs: 588.8...598.6, x: 138.5...191.3)
    private lazy var clubs = line(box: 568.7...599.7, glyphs: 572.6...584.4, x: 138.5...174.7)
    private var hand: TextRowLayout { TextRowLayout(lines: [spades, hearts, diamonds, clubs]) }

    private func rects(_ target: TextRowLayout.Target, _ message: String) -> [CGRect] {
        guard case .rows(let rects) = target else {
            XCTFail("\(message): expected rows, got \(target)")
            return []
        }
        return rects
    }

    // MARK: - The reported bug

    func testDragAlongASuitRowTakesOnlyThatRow() {
        // Along the hearts, finishing 40pt past its last card — under the spade
        // row above, which is both longer and where PDFKit's nearest-character
        // search goes.
        let got = rects(hand.target(from: CGPoint(x: 134, y: hearts.band.midY),
                                    to: CGPoint(x: 209, y: hearts.band.midY)), "heart row")
        XCTAssertEqual(got.count, 1)
        XCTAssertEqual(got.first?.minY ?? 0, hearts.band.minY, accuracy: 0.01)
        XCTAssertEqual(got.first?.maxY ?? 0, hearts.band.maxY, accuracy: 0.01)
    }

    func testARowsBandIsItsGlyphsNotPDFKitsLineBox() {
        // The line box is 31pt tall and reaches into both neighbours; the band
        // must be the ~10pt the glyphs occupy, or the highlight paints over the
        // suit above even when the right text was selected.
        let got = rects(hand.target(from: CGPoint(x: 134, y: hearts.band.midY),
                                    to: CGPoint(x: 209, y: hearts.band.midY)), "band")
        let band = try? XCTUnwrap(got.first)
        XCTAssertEqual(band?.height ?? 0, hearts.band.height, accuracy: 0.01)
        XCTAssertLessThan(band?.height ?? .infinity, hearts.lineBox.height / 2,
                          "The line box is more than twice the row pitch")
        for neighbour in [spades, diamonds] {
            XCTAssertFalse(band?.intersects(neighbour.band) ?? true,
                           "A row's band must not reach its neighbour's glyphs")
        }
    }

    func testEverySuitOfTheHandResolvesToItself() {
        for suit in [spades, hearts, diamonds, clubs] {
            let got = rects(hand.target(from: CGPoint(x: 134, y: suit.band.midY),
                                        to: CGPoint(x: 220, y: suit.band.midY)),
                            "row at \(suit.band.minY)")
            XCTAssertEqual(got.count, 1, "Row at \(suit.band.minY) took \(got.count) rows")
            XCTAssertEqual(got.first?.minY ?? 0, suit.band.minY, accuracy: 0.01)
        }
    }

    func testADragThatDriftsWithinItsRowStaysOnIt() {
        // A pencil dropping 3pt over the length of a 10pt-tall row is ordinary.
        let got = rects(hand.target(from: CGPoint(x: 134, y: hearts.band.midY + 3),
                                    to: CGPoint(x: 209, y: hearts.band.midY - 3)), "drift")
        XCTAssertEqual(got.count, 1)
        XCTAssertEqual(got.first?.minY ?? 0, hearts.band.minY, accuracy: 0.01)
    }

    // MARK: - Drags that really do cross rows

    func testADragAcrossThreeSuitsTakesExactlyThoseThree() {
        let got = rects(hand.target(from: CGPoint(x: 145, y: spades.band.midY),
                                    to: CGPoint(x: 160, y: diamonds.band.midY)), "three suits")
        XCTAssertEqual(got.map { $0.minY }, [spades, hearts, diamonds].map { $0.band.minY })
    }

    func testACrossingDragTrimsOnlyItsFirstAndLastRow() {
        let got = rects(hand.target(from: CGPoint(x: 160, y: spades.band.midY),
                                    to: CGPoint(x: 150, y: diamonds.band.midY)), "trim")
        XCTAssertEqual(got.count, 3)
        XCTAssertEqual(got[0].minX, 160, accuracy: 0.01, "Top row starts at the upper end")
        XCTAssertEqual(got[0].maxX, spades.band.maxX, accuracy: 0.01, "…and runs to the end of the row")
        XCTAssertEqual(got[1].minX, hearts.band.minX, accuracy: 0.01, "The middle row is taken whole")
        XCTAssertEqual(got[1].maxX, hearts.band.maxX, accuracy: 0.01)
        XCTAssertEqual(got[2].maxX, 150, accuracy: 0.01, "Bottom row stops at the lower end")
    }

    // MARK: - Columns, and paper with nothing on it

    func testADragInOneColumnIgnoresRowsInTheOther() {
        let left = line(box: 600...615, glyphs: 602...612, x: 42...202)
        let right = line(box: 596...611, glyphs: 598...608, x: 300...390)
        let layout = TextRowLayout(lines: [left, right])

        let got = rects(layout.target(from: CGPoint(x: 296, y: 603),
                                      to: CGPoint(x: 420, y: 603)), "column")
        XCTAssertEqual(got.count, 1)
        XCTAssertEqual(got.first?.minY ?? 0, right.band.minY, accuracy: 0.01,
                       "The left column's row is nearer in y but far away in x")
    }

    func testADragOverBlankPaperSelectsNothing() {
        XCTAssertEqual(hand.target(from: CGPoint(x: 400, y: 300),
                                   to: CGPoint(x: 480, y: 300)), .noText)
    }

    func testARowDoesNotClaimAllTheWhiteSpaceAroundIt() {
        // A lone row must not reach so far that a drag well clear of it is
        // still counted as being on it.
        let lonely = line(box: 400...440, glyphs: 415...425, x: 100...200)
        let layout = TextRowLayout(lines: [lonely])
        XCTAssertEqual(layout.target(from: CGPoint(x: 110, y: 460),
                                     to: CGPoint(x: 190, y: 460)), .noText)
    }

    func testAPageWithNoTextSelectsNothing() {
        XCTAssertEqual(TextRowLayout(lines: []).target(from: CGPoint(x: 10, y: 20),
                                                       to: CGPoint(x: 90, y: 20)), .noText)
    }

    // MARK: - Pulling a painted highlight back onto the glyphs

    func testTightenPullsALineBoxDownOntoItsGlyphs() {
        // What PDFKit hands back for a selected heart row, and what must be
        // painted for it.
        let selected = CGRect(x: 138.5, y: 597.0, width: 30.4, height: 31.0)
        let painted = hand.tighten(selected)

        XCTAssertEqual(painted.minX, selected.minX, accuracy: 0.01, "Only the vertical extent moves")
        XCTAssertEqual(painted.width, selected.width, accuracy: 0.01)
        XCTAssertEqual(painted.minY, hearts.band.minY, accuracy: 0.01)
        XCTAssertEqual(painted.height, hearts.band.height, accuracy: 0.01)
        XCTAssertFalse(painted.intersects(spades.band), "The paint must not reach the spade row")
    }

    func testTightenLeavesARectItCannotPlaceAlone() {
        let stranger = CGRect(x: 10, y: 10, width: 50, height: 12)
        XCTAssertEqual(hand.tighten(stranger), stranger)
    }

    // MARK: - Against a real lesson PDF

    /// The end-to-end property: dragging along any row and overshooting its
    /// right-hand end — what a teacher does to be sure of catching the last card
    /// of a suit — must never reach the row above or below.
    func testOvershootingAnyRowOnARealLessonNeverLeavesItsBand() throws {
        let document = try Fixtures.document(Fixtures.newMinorForcing)
        let page = try XCTUnwrap(document.page(at: 0))
        let layout = TextRowLayout(page: page)
        XCTAssertGreaterThan(layout.rows.count, 20, "Fixture should have a page of text")

        for row in layout.rows {
            let band = row.band
            guard case .rows(let rects) = layout.target(
                from: CGPoint(x: band.minX - 4, y: band.midY),
                to: CGPoint(x: band.maxX + 25, y: band.midY)
            ) else { continue }

            let strayed = rects.compactMap { page.selection(for: $0) }
                .flatMap { $0.selectionsByLine() }
                .map { layout.tighten($0.bounds(for: page)) }
                .filter { $0.midY < band.minY - 1 || $0.midY > band.maxY + 1 }
            XCTAssertTrue(strayed.isEmpty,
                          "Overshooting the row at \(band) reached \(strayed.count) row(s) outside it")
        }
    }

    /// The specific complaint: highlighting one suit of a hand. Each suit row
    /// must come back whole, and alone.
    func testDraggingAlongASuitRowSelectsThatSuitAndNothingElse() throws {
        let document = try Fixtures.document(Fixtures.newMinorForcing)
        let page = try XCTUnwrap(document.page(at: 0))
        let layout = TextRowLayout(page: page)

        let suits = layout.rows.filter {
            (page.selection(for: $0.band)?.string ?? "").first.map { "♠♥♦♣".contains($0) } == true
        }
        XCTAssertFalse(suits.isEmpty, "Fixture should contain a bridge hand")

        for suit in suits {
            let want = page.selection(for: suit.band)?.string
            guard case .rows(let rects) = layout.target(
                from: CGPoint(x: suit.band.minX - 4, y: suit.band.midY),
                to: CGPoint(x: suit.band.maxX + 25, y: suit.band.midY)
            ) else { return XCTFail("Suit row '\(want ?? "")' selected nothing") }

            let got = rects.compactMap { page.selection(for: $0)?.string }.joined()
            XCTAssertEqual(got, want)
        }
    }
}
