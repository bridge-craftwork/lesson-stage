import CryptoKit
import Foundation

/// Content hash of a document, used to key its annotation sidecar.
///
/// Keyed by content rather than by path so annotations survive a rename, a
/// move, or an iCloud re-download — all of which happen routinely to a lesson
/// that lives in a shared folder. The trade is the opposite failure: editing
/// the PDF orphans its annotations. For lesson PDFs, which are regenerated
/// wholesale rather than edited in place, that is the right way round.
enum ContentHash {
    /// Streamed rather than `Data(contentsOf:)`: this runs on every document
    /// open, and a merged handout can be tens of megabytes.
    static func sha256(of url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }

        var hasher = SHA256()
        while let chunk = try? handle.read(upToCount: 1 << 18), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
