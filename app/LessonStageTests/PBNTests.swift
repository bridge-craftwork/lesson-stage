import XCTest
@testable import LessonStage

/// Pulling one board's game record out of a PBN file.
final class PBNTests: XCTestCase {
    private let twoBoards = """
    [Event "x"]
    [Board "1"]
    [Deal "S:AQ954.K73.A5.J84 - - -"]

    [Event "x"]
    [Board "2"]
    [Deal "N:KJ2.AQ.KQT.- - - -"]
    """

    func testFindsARecordByBoardNumber() {
        let record = PBN.record(board: 2, in: twoBoards)
        XCTAssertNotNil(record)
        XCTAssertTrue(record!.contains("[Board \"2\"]"))
        XCTAssertFalse(record!.contains("[Board \"1\"]"), "Returns only the matching game")
    }

    func testMissingBoardIsNil() {
        XCTAssertNil(PBN.record(board: 9, in: twoBoards))
    }

    func testSplitsGamesOnBlankLines() {
        XCTAssertEqual(PBN.records(in: twoBoards).count, 2)
    }

    func testToleratesCRLFLineEndings() {
        let crlf = twoBoards.replacingOccurrences(of: "\n", with: "\r\n")
        XCTAssertEqual(PBN.records(in: crlf).count, 2, "Windows line endings still split")
        XCTAssertNotNil(PBN.record(board: 1, in: crlf))
    }

    func testBoardNumberParsingIsWhitespaceTolerant() {
        XCTAssertEqual(PBN.boardNumber(of: #"[Board  "7"]"#), 7)
        XCTAssertNil(PBN.boardNumber(of: #"[Event "no board here"]"#))
    }
}
