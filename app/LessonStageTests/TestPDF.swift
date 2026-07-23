import UIKit

/// A minimal valid PDF for tests that need a real document on disk.
///
/// Deliberately plain: these tests care about tab bookkeeping and bookmarks,
/// not about what is on the page. The lesson-shaped fixture lives in the UI
/// test target, where the content is what gets asserted on.
enum TestPDF {
    static func data(pages: Int = 1) -> Data {
        let renderer = UIGraphicsPDFRenderer(
            bounds: CGRect(x: 0, y: 0, width: 612, height: 792)
        )
        return renderer.pdfData { context in
            for page in 1...max(1, pages) {
                context.beginPage()
                "Page \(page)".draw(
                    at: CGPoint(x: 72, y: 72),
                    withAttributes: [.font: UIFont.systemFont(ofSize: 24)]
                )
            }
        }
    }
}
