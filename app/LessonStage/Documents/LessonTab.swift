import Foundation
import Observation
import PDFKit

/// One open lesson.
///
/// The tab owns the security-scoped access to its file for as long as it is
/// open. Files arrive from the document picker outside the app's sandbox, so
/// access must be claimed before reading and released on close — leaking a
/// claim eventually exhausts a per-process limit.
@Observable
final class LessonTab: Identifiable {
    let id: UUID
    let url: URL
    var title: String

    /// Persisted handle for reopening across launches. `nil` when the file was
    /// opened from somewhere that does not need one (the app's own container).
    var bookmark: Data?

    /// Loaded lazily so a session restore of eight tabs does not parse eight
    /// PDFs before the first frame.
    private(set) var document: PDFDocument?
    private(set) var loadFailure: String?

    /// 0-based page the tab was last showing. Restored on reopen.
    var pageIndex: Int

    private var isAccessing = false

    init(id: UUID = UUID(), url: URL, title: String? = nil, bookmark: Data? = nil, pageIndex: Int = 0) {
        self.id = id
        self.url = url
        self.title = title ?? url.deletingPathExtension().lastPathComponent
        self.bookmark = bookmark
        self.pageIndex = pageIndex
    }

    var pageCount: Int { document?.pageCount ?? 0 }

    /// Claim access and parse the PDF. Safe to call repeatedly.
    @discardableResult
    func load() -> Bool {
        if document != nil { return true }

        // A URL from the picker needs its security scope started before any
        // read. One that is already inside our container does not, and returns
        // false here — which is not an error.
        if !isAccessing {
            isAccessing = url.startAccessingSecurityScopedResource()
        }

        guard let document = PDFDocument(url: url) else {
            loadFailure = "Could not open \(url.lastPathComponent)."
            releaseAccess()
            return false
        }

        self.document = document
        self.loadFailure = nil
        // A restored page index can be stale if the file changed underneath us.
        self.pageIndex = min(pageIndex, max(0, document.pageCount - 1))
        return true
    }

    /// Release the file. Called when the tab closes.
    func close() {
        document = nil
        releaseAccess()
    }

    private func releaseAccess() {
        guard isAccessing else { return }
        url.stopAccessingSecurityScopedResource()
        isAccessing = false
    }

    deinit {
        // `deinit` is the last line of defence, not the intended path: closing
        // a tab should release its claim explicitly.
        if isAccessing {
            url.stopAccessingSecurityScopedResource()
        }
    }
}

extension LessonTab: Equatable, Hashable {
    static func == (lhs: LessonTab, rhs: LessonTab) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
