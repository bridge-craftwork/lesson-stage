import UIKit

/// Generates a multi-page lesson-shaped PDF for the tests to open.
///
/// Generated rather than checked in so the tests carry no binary fixtures and
/// the page count is a fact of the test rather than of a file someone has to
/// remember to keep in sync. `/fixtures` is for real lesson PDFs with Contract
/// 5 payloads, which is a Phase 3 concern and a different thing entirely.
enum PDFFixture {
    /// The two fixtures differ in length on purpose. Page count is reported by
    /// the reading controls and is reliably exposed to the accessibility tree,
    /// which makes it the sturdiest available proof that a tab switch actually
    /// swapped the document — PDF page *text* is not dependably queryable.
    static let shortPageCount = 4
    static let longPageCount = 6

    static func data(titlePrefix: String = "", pageCount: Int = shortPageCount) -> Data {
        let pageSize = CGSize(width: 612, height: 792)
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: pageSize))

        let names = [
            "New Minor Forcing",
            "Responder's Second Bid",
            "Practice Deals",
            "Quiz: Which Call?",
            "Declarer Play",
            "Defensive Signals",
        ]
        let titles = (0..<pageCount).map { index in
            (index == 0 ? titlePrefix : "") + names[index % names.count]
        }

        return renderer.pdfData { context in
            for (index, title) in titles.enumerated() {
                context.beginPage()

                title.draw(
                    at: CGPoint(x: 54, y: 64),
                    withAttributes: [.font: UIFont.boldSystemFont(ofSize: 28)]
                )
                "Page \(index + 1) of \(titles.count) — Bridge Classroom".draw(
                    at: CGPoint(x: 54, y: 104),
                    withAttributes: [
                        .font: UIFont.systemFont(ofSize: 13),
                        .foregroundColor: UIColor.darkGray,
                    ]
                )

                var y: CGFloat = 160
                for line in [
                    "After 1♣ — 1♥ — 1NT, a bid of 2♦ is New Minor Forcing.",
                    "♠ A K Q 4      Opener rebids 2♥ with three hearts.",
                    "♥ K J 3        With neither, opener bids 2NT.",
                    "♦ A 7 2",
                    "♣ K J 5        21 HCP — far too strong for 1NT.",
                ] {
                    line.draw(
                        at: CGPoint(x: 54, y: y),
                        withAttributes: [.font: UIFont.systemFont(ofSize: 15)]
                    )
                    y += 28
                }

                let box = CGRect(x: 54, y: 420, width: 300, height: 160)
                UIColor.black.setStroke()
                UIBezierPath(rect: box).stroke()
                "Board \(index + 1)".draw(
                    at: CGPoint(x: 64, y: 430),
                    withAttributes: [.font: UIFont.boldSystemFont(ofSize: 28)]
                )
            }
        }
    }
}
