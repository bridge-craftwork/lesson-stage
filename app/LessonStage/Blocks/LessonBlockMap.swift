import CoreGraphics
import Foundation

/// The Contract 5 click map (`lesson-blocks.json`) — block bodies, positions,
/// and the board join. Decoded from the embedded file; version 1.
///
/// Unknown fields are ignored (that is the contract: adding one is a MINOR
/// change), which `JSONDecoder` does for free — `pageSize`, `coordinateSpace`,
/// and a `fragmented` array seen in real payloads simply aren't modelled here.
struct LessonBlockMap: Decodable {
    let version: Int
    let blocks: [Block]

    private let unlocated: [Int]?
    /// Indices of blocks that could not be positioned — present in `blocks` with
    /// a body but no page/rect. Normative, not diagnostic: never infer a
    /// position for one.
    var unlocatedIndices: [Int] { unlocated ?? [] }

    struct Block: Decodable {
        let index: Int
        let kind: String
        let body: String

        /// 1-based in the file; absent for an unlocated block.
        let page: Int?
        /// `[minX, minY, maxX, maxY]` in PDFPage space; absent when unlocated.
        let rect: [Double]?

        /// The PBN board join. A `hand` block carries `board`; an `auction`
        /// block carries `deal` (a board number, or null). Both are board
        /// numbers — the key name just differs by kind.
        private let board: Int?
        private let deal: Int?
        var boardNumber: Int? { board ?? deal }

        /// 0-based page index for `PDFDocument`, or nil if unlocated.
        var pageIndex: Int? { page.map { $0 - 1 } }

        /// `rect` as a `CGRect` in PDFPage space (origin bottom-left), or nil if
        /// unlocated. The stored form is `[minX, minY, maxX, maxY]`, so width and
        /// height are differences — not the last two components directly.
        var pageRect: CGRect? {
            guard let rect, rect.count == 4 else { return nil }
            return CGRect(x: rect[0], y: rect[1], width: rect[2] - rect[0], height: rect[3] - rect[1])
        }
    }
}
