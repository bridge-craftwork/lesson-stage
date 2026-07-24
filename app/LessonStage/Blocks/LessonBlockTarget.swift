import CoreGraphics
import Foundation

/// A tappable lesson block located on a page by a `lesson-block:<index>` link
/// annotation embedded in the PDF (Contract 5).
///
/// `index` is the block's position in the click map — the join to
/// `lesson-blocks.json`, *not* a board number. Several targets can share one
/// index: a block that fragments across columns emits one annotation per piece,
/// and the contract says to treat duplicate URIs as several tap targets for one
/// block.
struct LessonBlockTarget: Hashable {
    let index: Int
    let pageIndex: Int

    /// In `PDFPage` coordinate space — pdf-points, origin bottom-left — taken
    /// straight from the annotation's own bounds. On iOS this is already the
    /// page space, so it maps to the view with `PDFView.convert(_:to:)` and
    /// nothing else: no `y = height − y` flip (that is for web consumers, and
    /// applying it here would put every target in the wrong half of the page).
    let bounds: CGRect
}
