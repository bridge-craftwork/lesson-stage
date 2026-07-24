import PDFKit

/// Finds the `lesson-block:` link annotations Contract 5 leaves in a lesson PDF.
///
/// The cheap route in, and the hot path: PDFKit exposes link annotations
/// first-class (`page.annotations`), so tap targets cost nothing to enumerate —
/// no attachment parsing required. The bodies and board numbers those indices
/// join to come separately, from the embedded click map (`lesson-blocks.json`),
/// which is parsed once per document rather than on every touch.
enum LessonBlockLinks {
    static let scheme = "lesson-block"

    /// Every `lesson-block:` tap target in the document, in page order then the
    /// order PDFKit returns a page's annotations.
    static func targets(in document: PDFDocument) -> [LessonBlockTarget] {
        var targets: [LessonBlockTarget] = []
        for pageIndex in 0..<document.pageCount {
            guard let page = document.page(at: pageIndex) else { continue }
            for annotation in page.annotations {
                guard let index = blockIndex(of: annotation) else { continue }
                targets.append(LessonBlockTarget(index: index, pageIndex: pageIndex, bounds: annotation.bounds))
            }
        }
        return targets
    }

    /// The block index a link annotation points at, or `nil` if it is not a
    /// `lesson-block:` link.
    static func blockIndex(of annotation: PDFAnnotation) -> Int? {
        guard let url = url(of: annotation) else { return nil }
        return blockIndex(from: url)
    }

    /// Parse the index out of a `lesson-block:<index>` URI. The index is the
    /// opaque part after the scheme — the URIs carry no `//host`.
    static func blockIndex(from url: URL) -> Int? {
        guard url.scheme == scheme else { return nil }
        let body = url.absoluteString.dropFirst(scheme.count + 1) // drop "lesson-block:"
        return Int(body)
    }

    /// The URL a link annotation carries. A URL action is the standard shape
    /// PDFKit surfaces for a URI link, which is what the print engine emits.
    private static func url(of annotation: PDFAnnotation) -> URL? {
        (annotation.action as? PDFActionURL)?.url
    }
}
