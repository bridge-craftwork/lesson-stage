import PDFKit
import UIKit

/// Debug-only overlay that outlines every `lesson-block:` tap target on the
/// page, so Contract 5 detection can be eyeballed on the glass before the popout
/// exists — the answer to "are we picking the blocks up correctly, and in the
/// right place?".
///
/// It draws from each annotation's *own* bounds, added back as `.square`
/// annotations in the same page space, so what you see is exactly what will be
/// tappable — and because no coordinate conversion is involved, it also stands
/// as the reference the click-map path (which does convert) can be checked
/// against for the easy-to-make y-flip mistake.
enum LessonBlockXray {
    /// Distinguishes the overlay's annotations from the app's highlights, so
    /// toggling it off removes only its own marks and never a real highlight.
    static let ownerTag = "lesson-stage.block-xray"

    /// Show or clear the overlay on a document, honouring `on`. Idempotent:
    /// existing overlay marks are cleared first, so repeated calls don't stack.
    static func apply(_ on: Bool, to document: PDFDocument) {
        clear(from: document)
        guard on else { return }
        for target in LessonBlockLinks.targets(in: document) {
            guard let page = document.page(at: target.pageIndex) else { continue }
            page.addAnnotation(outline(for: target))
            page.addAnnotation(label(for: target))
        }
    }

    static func clear(from document: PDFDocument) {
        for pageIndex in 0..<document.pageCount {
            guard let page = document.page(at: pageIndex) else { continue }
            for annotation in page.annotations where annotation.userName == ownerTag {
                page.removeAnnotation(annotation)
            }
        }
    }

    private static let tint = UIColor.systemPink

    private static func outline(for target: LessonBlockTarget) -> PDFAnnotation {
        let annotation = PDFAnnotation(bounds: target.bounds, forType: .square, withProperties: nil)
        annotation.color = tint                                    // stroke
        annotation.interiorColor = tint.withAlphaComponent(0.12)   // faint fill
        let border = PDFBorder()
        border.lineWidth = 1.5
        annotation.border = border
        annotation.userName = ownerTag
        return annotation
    }

    /// A small `#index` tag tucked into the block's top-left corner.
    private static func label(for target: LessonBlockTarget) -> PDFAnnotation {
        let size = CGSize(width: 34, height: 15)
        // maxY is the top edge in page space (origin bottom-left); sit just inside it.
        let origin = CGPoint(x: target.bounds.minX, y: target.bounds.maxY - size.height)
        let annotation = PDFAnnotation(
            bounds: CGRect(origin: origin, size: size),
            forType: .freeText,
            withProperties: nil
        )
        annotation.contents = "#\(target.index)"
        annotation.font = UIFont.boldSystemFont(ofSize: 9)
        annotation.fontColor = .white
        annotation.color = tint
        annotation.userName = ownerTag
        return annotation
    }
}
