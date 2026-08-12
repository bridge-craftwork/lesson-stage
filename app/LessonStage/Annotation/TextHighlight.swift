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

    /// Whether this highlight covers any of the same area as another — used to
    /// decide which existing highlight a new one replaces.
    func overlaps(_ other: TextHighlight) -> Bool {
        rects.contains { rect in other.rects.contains { $0.intersects(rect) } }
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
        return TextHighlight(rects: deoverlap(rects), color: color)
    }

    /// Trim vertical overlap between stacked line rects so a translucent
    /// `.highlight` annotation does not double up and darken where consecutive
    /// lines' bounding boxes overlap (they include leading, so they do).
    ///
    /// Only rects that share horizontal span are trimmed against each other —
    /// two columns of a lesson have disjoint x-ranges and must stay
    /// independent, or a highlight in the left column would be clipped by one
    /// in the right.
    static func deoverlap(_ rects: [CGRect]) -> [CGRect] {
        // Top line first: PDF space is y-up, so a higher minY is higher on the page.
        let ordered = rects.sorted { $0.minY > $1.minY }
        var placed: [CGRect] = []

        for var rect in ordered {
            for above in placed where horizontallyOverlaps(above, rect) {
                // Lower the top of this rect to meet the bottom of the one above.
                if rect.maxY > above.minY {
                    let newMaxY = above.minY
                    rect = CGRect(x: rect.minX, y: rect.minY,
                                  width: rect.width, height: max(0, newMaxY - rect.minY))
                }
            }
            if rect.height > 0.5 { placed.append(rect) }
        }
        return placed
    }

    private static func horizontallyOverlaps(_ a: CGRect, _ b: CGRect) -> Bool {
        a.minX < b.maxX && b.minX < a.maxX
    }

    /// Collapse rects that cover the same line of text into one, so a span
    /// highlighted twice — or two highlights that meet — becomes a single quad
    /// instead of two translucent ones stacking into a darker band. Rects on
    /// different lines, or in different columns, stay separate; the vertical
    /// de-overlap then trims the leading where adjacent lines' boxes touch.
    static func mergeRects(_ rects: [CGRect]) -> [CGRect] {
        var lines: [CGRect] = []
        for rect in rects where rect.width > 1 && rect.height > 1 {
            if let i = lines.firstIndex(where: { sameLine($0, rect) }) {
                lines[i] = lines[i].union(rect)
            } else {
                lines.append(rect)
            }
        }
        return deoverlap(lines)
    }

    /// Two rects lie on the same line when they overlap horizontally and share
    /// most of their height — as opposed to consecutive lines, whose boxes touch
    /// only by the small leading between them.
    private static func sameLine(_ a: CGRect, _ b: CGRect) -> Bool {
        guard horizontallyOverlaps(a, b) else { return false }
        let overlapY = min(a.maxY, b.maxY) - max(a.minY, b.minY)
        return overlapY > 0.5 * min(a.height, b.height)
    }

    /// One merged annotation per colour for a page's highlights.
    ///
    /// A `.highlight` annotation multiplies its colour onto the page, so two of
    /// them over the same text darken where they meet — that is the "keeps
    /// getting darker" seen when re-marking a span. Merging every same-colour
    /// highlight into a single de-overlapped annotation makes the multiply
    /// apply exactly once, so re-marking stays at one level.
    static func mergedAnnotations(for highlights: [TextHighlight]) -> [PDFAnnotation] {
        Dictionary(grouping: highlights, by: \.color).compactMap { color, group in
            let rects = mergeRects(group.flatMap(\.rects))
            guard !rects.isEmpty else { return nil }
            return annotation(rects: rects, color: color)
        }
    }

    /// The single PDF annotation that draws a highlight.
    ///
    /// One annotation with a quad per line, **not** one annotation per line.
    /// A `.highlight` annotation multiplies its colour onto the page, so two
    /// of them touching darken where they meet — the banding seen across
    /// multi-line highlights. Collapsing the lines into one annotation's
    /// quads makes the multiply apply once, uniformly.
    ///
    /// Added to the in-memory document only; the file on disk is never written.
    static func annotation(for highlight: TextHighlight) -> PDFAnnotation {
        annotation(rects: highlight.rects, color: highlight.color)
    }

    static func annotation(rects: [CGRect], color: PenColor) -> PDFAnnotation {
        let bounds = rects.reduce(CGRect.null) { $0.union($1) }
        let annotation = PDFAnnotation(bounds: bounds, forType: .highlight, withProperties: nil)
        annotation.color = color.uiColor

        // Four points per line. Despite the SDK header saying "page space",
        // PDFKit reads quadrilateralPoints **relative to the annotation's
        // bounds origin** — the well-known gotcha, and the cause of highlights
        // landing up and to the right of the text. Offset each corner by the
        // bounds origin. PDF QuadPoints order is UL, UR, LL, LR.
        annotation.quadrilateralPoints = rects.flatMap { rect -> [NSValue] in
            let x0 = rect.minX - bounds.minX
            let x1 = rect.maxX - bounds.minX
            let y0 = rect.minY - bounds.minY
            let y1 = rect.maxY - bounds.minY
            return [
                NSValue(cgPoint: CGPoint(x: x0, y: y1)),
                NSValue(cgPoint: CGPoint(x: x1, y: y1)),
                NSValue(cgPoint: CGPoint(x: x0, y: y0)),
                NSValue(cgPoint: CGPoint(x: x1, y: y0)),
            ]
        }

        // Tagged so our own annotations can be told apart from the ones the
        // lesson shipped with — Contract 5's `lesson-block:` links are
        // annotations too, and must never be swept up.
        annotation.userName = Self.ownerTag
        return annotation
    }

    static let ownerTag = "lesson-stage.highlight"
}
