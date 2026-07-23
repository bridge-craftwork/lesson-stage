import CoreGraphics
import Foundation
import PDFKit

/// A highlight over text, stored as the rects the selection occupied.
///
/// Rects rather than character offsets, deliberately. Offsets would be
/// smaller and would survive re-flow, but PDFKit's character indices are a
/// property of how a particular PDF was laid out — the same lesson re-rendered
/// renumbers them. Since annotations are already keyed to one exact byte-stream
/// by content hash, positions are no less durable than the key that finds them,
/// and they draw without re-running text layout.
struct TextHighlight: Codable, Equatable, Identifiable {
    var id: UUID = UUID()
    /// One rect per line of the selection: a highlight across a line break is
    /// two boxes, never one box swallowing the margin between them.
    var rects: [CGRect]
    var color: PenColor

    func contains(_ point: CGPoint) -> Bool {
        rects.contains { $0.contains(point) }
    }
}

extension PenColor: Codable {}

/// Builds highlights from a PDFKit selection.
enum HighlightFactory {
    /// `selectionsByLine` is what keeps a multi-line highlight from becoming
    /// one rect spanning everything between the first and last character —
    /// which on a two-column lesson would paint straight across the gutter.
    static func make(from selection: PDFSelection, on page: PDFPage, color: PenColor) -> TextHighlight? {
        let rects = selection.selectionsByLine()
            .map { $0.bounds(for: page) }
            .filter { !$0.isEmpty && $0.width > 1 && $0.height > 1 }

        guard !rects.isEmpty else { return nil }
        return TextHighlight(rects: rects, color: color)
    }

    /// The PDF annotations that draw a highlight.
    ///
    /// Added to the in-memory document only. The file on disk is never
    /// written — same rule as the ink, and the reason both live in the sidecar.
    static func annotations(for highlight: TextHighlight) -> [PDFAnnotation] {
        highlight.rects.map { rect in
            let annotation = PDFAnnotation(bounds: rect, forType: .highlight, withProperties: nil)
            annotation.color = highlight.color.uiColor
            // Tagged so our own annotations can be told apart from the ones
            // the lesson shipped with — Contract 5's `lesson-block:` links are
            // annotations too, and must never be swept up.
            annotation.userName = Self.ownerTag
            return annotation
        }
    }

    static let ownerTag = "lesson-stage.highlight"
}
