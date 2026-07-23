import PDFKit
import SwiftUI

/// Page thumbnails for the open document.
///
/// `PDFThumbnailView` is driven by a `PDFView`, not by a document — it needs
/// the same view instance the reader is looking at, so the two are built
/// together and the thumbnail strip is handed the live one.
struct ThumbnailSidebar: UIViewRepresentable {
    let host: PDFViewHost

    func makeUIView(context: Context) -> PDFThumbnailView {
        let view = PDFThumbnailView()
        view.pdfView = host.pdfView
        view.layoutMode = .vertical
        view.thumbnailSize = CGSize(width: 108, height: 140)
        view.backgroundColor = UIColor(Color.sidebarSurface)
        view.accessibilityIdentifier = "thumbnailSidebar"
        return view
    }

    func updateUIView(_ view: PDFThumbnailView, context: Context) {
        if view.pdfView !== host.pdfView { view.pdfView = host.pdfView }
    }
}
