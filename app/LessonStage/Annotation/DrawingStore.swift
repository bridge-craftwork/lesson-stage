import Foundation
import PencilKit
import os

/// Reads and writes the annotation sidecar for one document.
///
/// GoodReader's model, and the one the plan calls for: the original PDF is
/// never modified. Drawings live in a separate file keyed by the PDF's content
/// hash, so the lesson can be re-downloaded, re-synced, or shared without ever
/// being rewritten, and a corrupted sidecar costs annotations rather than the
/// lesson itself.
struct DrawingStore {
    /// Bumped only when the on-disk shape changes incompatibly. A sidecar
    /// whose version is unknown is left alone rather than overwritten — a
    /// newer build's annotations must not be destroyed by an older one.
    static let currentVersion = 1

    struct Sidecar: Codable {
        var version: Int = DrawingStore.currentVersion
        /// Page index (0-based) to `PKDrawing.dataRepresentation()`.
        var pages: [Int: Data] = [:]
        /// Page index to text highlights. Optional rather than defaulted:
        /// Swift's synthesised decoding treats a missing key as an error even
        /// when the property has a default, and sidecars written before
        /// highlights existed must still load.
        var highlights: [Int: [TextHighlight]]?
    }

    /// What a document's sidecar holds.
    struct Contents {
        var drawings: [Int: PKDrawing] = [:]
        var highlights: [Int: [TextHighlight]] = [:]

        var isEmpty: Bool {
            drawings.values.allSatisfy(\.strokes.isEmpty) && highlights.values.allSatisfy(\.isEmpty)
        }
    }

    private static let logger = Logger(subsystem: "com.popperbiz.LessonStage", category: "drawings")

    private let directory: URL

    init(directoryName: String = "Annotations") {
        directory = URL.applicationSupportDirectory.appending(path: directoryName)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func url(forHash hash: String) -> URL {
        directory.appending(path: "\(hash).json")
    }

    /// Load the sidecar for a document. Returns empty contents when there is
    /// none, which is the ordinary case for a lesson opened the first time.
    func load(hash: String) -> Contents {
        let fileURL = url(forHash: hash)
        guard let data = try? Data(contentsOf: fileURL) else { return Contents() }

        let sidecar: Sidecar
        do {
            sidecar = try JSONDecoder().decode(Sidecar.self, from: data)
        } catch {
            Self.logger.error("Unreadable sidecar \(hash): \(error.localizedDescription)")
            return Contents()
        }

        guard sidecar.version <= Self.currentVersion else {
            Self.logger.error("Sidecar \(hash) is version \(sidecar.version); refusing to read")
            return Contents()
        }

        let drawings = sidecar.pages.compactMapValues { data in
            do {
                return try PKDrawing(data: data)
            } catch {
                // One unreadable page should not cost the whole document.
                Self.logger.error("Dropping undecodable page drawing: \(error.localizedDescription)")
                return nil as PKDrawing?
            }
        }

        return Contents(drawings: drawings, highlights: sidecar.highlights ?? [:])
    }

    /// Write the sidecar. Empty pages are dropped rather than stored, so
    /// erasing everything leaves no residue.
    func save(_ contents: Contents, hash: String) {
        let pages = contents.drawings
            .filter { !$0.value.strokes.isEmpty }
            .mapValues { $0.dataRepresentation() }
        let highlights = contents.highlights.filter { !$0.value.isEmpty }

        let fileURL = url(forHash: hash)

        guard !pages.isEmpty || !highlights.isEmpty else {
            // Nothing left to remember: remove the file instead of leaving an
            // empty one behind.
            try? FileManager.default.removeItem(at: fileURL)
            return
        }

        do {
            let sidecar = Sidecar(pages: pages, highlights: highlights.isEmpty ? nil : highlights)
            try JSONEncoder().encode(sidecar).write(to: fileURL, options: .atomic)
        } catch {
            Self.logger.error("Could not save sidecar \(hash): \(error.localizedDescription)")
        }
    }
}
