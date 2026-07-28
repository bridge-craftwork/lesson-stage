import PDFKit
import UIKit

/// Generates a blank, off-white sheet to write or draw on — a tab with no
/// lesson behind it, just the canvas. It's a real one-page PDF written into the
/// app's container, so every existing path (annotation, save, session restore,
/// the grid thumbnail) works on it unchanged.
enum BlankSheet {
    /// A warm off-white, softer than paper-white so it isn't stark on the
    /// projector.
    static let pageColor = UIColor(red: 0.98, green: 0.97, blue: 0.94, alpha: 1)

    /// US Letter, portrait — the shape a handout is, so a blank sits naturally
    /// beside the lessons.
    private static let pageSize = CGSize(width: 612, height: 792)

    /// Create a new blank sheet PDF in the app's container and return its URL.
    /// Each carries a unique id in its metadata, so its bytes — and therefore
    /// the content hash its annotations key to — differ from every other blank.
    static func create() -> URL? {
        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = [
            kCGPDFContextTitle as String: "Blank Sheet",
            kCGPDFContextKeywords as String: UUID().uuidString,
        ]
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: pageSize), format: format)
        let data = renderer.pdfData { context in
            context.beginPage()
            context.cgContext.setFillColor(pageColor.cgColor)
            context.cgContext.fill(CGRect(origin: .zero, size: pageSize))
        }

        let directory = URL.applicationSupportDirectory.appending(path: "Blanks", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appending(path: "\(UUID().uuidString).pdf")
        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }
}
