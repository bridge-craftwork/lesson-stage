import Foundation
import Observation
import PDFKit

/// One open lesson.
///
/// The tab owns the security-scoped access to its file for as long as it is
/// open. Files arrive from the document picker outside the app's sandbox, so
/// access must be claimed before reading and released on close — leaking a
/// claim eventually exhausts a per-process limit.
@MainActor
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

    /// Annotations for this document, loaded alongside it. `nil` until the
    /// document has been read, since the sidecar is keyed by content hash.
    private(set) var drawings: DrawingSet?

    /// The Contract 5 payload — the click map and PBN — parsed once when the
    /// document loads, off the main thread. `nil` for a plain PDF (no
    /// attachments) or an unsupported payload version.
    private(set) var payload: LessonPayload?

    /// `nonisolated` so `deinit` — which cannot hop to the main actor — can
    /// still release a leaked claim. Only ever mutated on the main actor, by
    /// `load` and `releaseAccess`.
    private nonisolated(unsafe) var isAccessing = false

    /// The in-flight load, if any. Held so repeated `load()` calls coalesce and
    /// `loaded()` can await the result. Its presence is the "is loading" signal.
    private var loadTask: Task<Void, Never>?

    init(id: UUID = UUID(), url: URL, title: String? = nil, bookmark: Data? = nil, pageIndex: Int = 0) {
        self.id = id
        self.url = url
        self.title = title ?? url.deletingPathExtension().lastPathComponent
        self.bookmark = bookmark
        self.pageIndex = pageIndex
    }

    var pageCount: Int { document?.pageCount ?? 0 }

    /// Whether a parse is in flight. Drives the reading view's loading state.
    var isLoading: Bool { loadTask != nil }

    /// Claim access and parse the PDF — off the main thread. Safe to call
    /// repeatedly: the first call wins and later ones no-op while it runs.
    ///
    /// The parse and the content hash both stream the whole file, and for an
    /// iCloud file the read blocks on a download of tens of megabytes. Doing
    /// that on the main actor froze the UI to a black screen for the length of
    /// the download; it now runs on a background task and publishes back.
    func load() {
        guard document == nil, loadTask == nil else { return }

        // A URL from the picker (or resolved from a bookmark) needs its security
        // scope started before any read. One already inside our container does
        // not, and returns false here — which is not an error.
        if !isAccessing {
            isAccessing = url.startAccessingSecurityScopedResource()
        }

        let url = self.url
        loadTask = Task { [weak self] in
            let loaded = await LessonTab.parse(url: url)
            guard let self else { return }
            self.finishLoading(loaded)
            self.loadTask = nil
        }
    }

    /// Kick off (or join) the load and await the resulting document. For
    /// callers that need the parsed document, like thumbnail rendering.
    func loaded() async -> PDFDocument? {
        load()
        await loadTask?.value
        return document
    }

    /// Parsed off the main actor. A non-`Sendable` `PDFDocument` is handed back
    /// in a box: it is constructed here and never touched again off-main, so the
    /// crossing is safe.
    private struct Loaded: @unchecked Sendable {
        let document: PDFDocument?
        let hash: String?
        let payload: LessonPayload?
    }

    private static func parse(url: URL) async -> Loaded {
        // Wait for an iCloud placeholder to materialise before reading it, so a
        // not-yet-downloaded handout opens once it lands rather than failing
        // with "could not open". A local file returns immediately.
        await ensureDownloaded(url)
        return await Task.detached(priority: .userInitiated) {
            // Read the bytes through a file coordinator, exactly as the document
            // picker does — this is what forces the *current* version of a file
            // that was regenerated in the folder (a new iCloud version, or a
            // replaced file at the same path). Reading with a plain
            // `PDFDocument(url:)` can serve a stale local copy, which is why
            // re-opening an updated lesson kept showing the old content while
            // the single-file picker showed the new one.
            let data = coordinatedRead(url)
            let document = data.flatMap { PDFDocument(data: $0) }
            let hash = data.map { ContentHash.sha256(of: $0) }
            // Parse the Contract 5 payload here too, off the main thread — the
            // CGPDF attachment walk and JSON decode should not block the UI.
            let payload = document.flatMap { LessonPayload.load(from: $0) }
            return Loaded(document: document, hash: hash, payload: payload)
        }.value
    }

    /// Read a file's bytes under `NSFileCoordinator`, so an iCloud item is
    /// materialised to its latest version before the read — the coordinated
    /// read the document picker performs, which a direct `PDFDocument(url:)`
    /// does not. Returns nil if the file cannot be read (opens as a failure).
    private nonisolated static func coordinatedRead(_ url: URL) -> Data? {
        var coordinationError: NSError?
        var data: Data?
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordinationError) { readURL in
            data = try? Data(contentsOf: readURL)
        }
        return data
    }

    private static func ensureDownloaded(_ url: URL) async {
        let keys: Set<URLResourceKey> = [.isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey]
        guard let values = try? url.resourceValues(forKeys: keys), values.isUbiquitousItem == true else { return }

        func isReady() -> Bool {
            let status = (try? url.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey]))?
                .ubiquitousItemDownloadingStatus
            return status == .current || status == .downloaded
        }
        guard !isReady() else { return }

        try? FileManager.default.startDownloadingUbiquitousItem(at: url)
        // Poll off the main thread — the UI shows a spinner meanwhile. Bounded
        // so a download that never arrives eventually surfaces as a load
        // failure rather than a spinner forever.
        for _ in 0..<600 {
            if isReady() { return }
            try? await Task.sleep(for: .milliseconds(100))
        }
    }

    private func finishLoading(_ loaded: Loaded) {
        guard let document = loaded.document else {
            loadFailure = "Could not open \(url.lastPathComponent)."
            releaseAccess()
            return
        }
        self.document = document
        self.loadFailure = nil
        // Clamp against the *current* page index, which may have been recorded
        // while the parse was in flight; a stale restored index is also caught.
        self.pageIndex = min(pageIndex, max(0, document.pageCount - 1))

        if let hash = loaded.hash {
            drawings = DrawingSet(contentHash: hash)
        }
        payload = loaded.payload
    }

    /// Release the file. Called when the tab closes.
    func close() {
        // Flush before releasing: waiting out the save debounce would lose
        // whatever was drawn in the last couple of seconds.
        loadTask?.cancel()
        loadTask = nil
        drawings?.saveNow()
        drawings = nil
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
