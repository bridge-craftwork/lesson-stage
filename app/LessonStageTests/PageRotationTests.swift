import XCTest
@testable import LessonStage

/// The 90°-counter-clockwise page turn, in PDFKit's clockwise-degrees model.
final class PageRotationTests: XCTestCase {
    func testEachQuarterTurnCounterclockwise() {
        XCTAssertEqual(PageRotation.counterclockwise(from: 0), 270)
        XCTAssertEqual(PageRotation.counterclockwise(from: 270), 180)
        XCTAssertEqual(PageRotation.counterclockwise(from: 180), 90)
        XCTAssertEqual(PageRotation.counterclockwise(from: 90), 0, "Wraps back to upright")
    }

    func testFourTurnsReturnToStart() {
        var rotation = 0
        for _ in 0..<4 { rotation = PageRotation.counterclockwise(from: rotation) }
        XCTAssertEqual(rotation, 0, "A full circle is a no-op")
    }

    func testNormalisesOutOfRangeInput() {
        XCTAssertEqual(PageRotation.counterclockwise(from: 360), 270, "360 is upright")
        XCTAssertEqual(PageRotation.counterclockwise(from: -90), 180, "Negative input still normalises to [0,360)")
    }
}
