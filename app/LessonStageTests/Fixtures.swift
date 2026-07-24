import Foundation
import PDFKit
import XCTest

/// Locates the repo's `/fixtures` — the known-good lesson PDFs the Contract 5
/// notes call for. Resolved relative to this source file, which works on the
/// simulator where the test runner shares the host filesystem.
enum Fixtures {
    static let newMinorForcing = "new-minor-forcing.pdf"

    static func url(_ name: String) -> URL {
        // .../app/LessonStageTests/Fixtures.swift → up to the repo root, /fixtures.
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // LessonStageTests
            .deletingLastPathComponent()   // app
            .deletingLastPathComponent()   // repo root
            .appending(path: "fixtures")
            .appending(path: name)
    }

    /// Load a fixture PDF, skipping the test if it is not present (so the suite
    /// stays runnable without the fixtures checked out).
    static func document(_ name: String) throws -> PDFDocument {
        let url = url(name)
        guard let document = PDFDocument(url: url) else {
            throw XCTSkip("Fixture missing at \(url.path)")
        }
        return document
    }
}
