import Foundation
import os

/// Reads and writes the open-tabs session.
///
/// Stored as JSON in Application Support rather than `UserDefaults`: the
/// payload is a list of security-scoped bookmarks, which run to kilobytes
/// each and have no business in a preferences plist.
struct SessionStore {
    struct PersistedTab: Codable {
        var id: UUID
        var bookmark: Data
        var title: String
        var pageIndex: Int
    }

    struct PersistedSession: Codable {
        var tabs: [PersistedTab] = []
        var selectedID: UUID?
    }

    private static let logger = Logger(subsystem: "com.popperbiz.LessonStage", category: "session")

    private let fileURL: URL

    init(filename: String = "session.json") {
        let base = URL.applicationSupportDirectory
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        self.fileURL = base.appending(path: filename)
    }

    func load() -> PersistedSession {
        guard let data = try? Data(contentsOf: fileURL) else { return PersistedSession() }
        do {
            return try JSONDecoder().decode(PersistedSession.self, from: data)
        } catch {
            // A session that cannot be read is not worth failing a launch over.
            Self.logger.error("Discarding unreadable session: \(error.localizedDescription)")
            return PersistedSession()
        }
    }

    func save(_ session: PersistedSession) {
        do {
            let data = try JSONEncoder().encode(session)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            Self.logger.error("Could not save session: \(error.localizedDescription)")
        }
    }

    /// Resolve a persisted bookmark back to a usable URL.
    ///
    /// Returns `nil` when the file has moved or been deleted — the tab is then
    /// dropped from the restored session rather than reopened as a broken tab.
    static func resolve(bookmark: Data) -> (url: URL, refreshed: Data?)? {
        var isStale = false
        guard let url = try? URL(
            resolvingBookmarkData: bookmark,
            options: [],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else {
            return nil
        }

        guard isStale else { return (url, nil) }

        // Stale means the file moved but is still reachable: re-issue the
        // bookmark now, or it will fail to resolve on some future launch.
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        let refreshed = try? url.bookmarkData()
        return (url, refreshed)
    }

    /// Make a bookmark for a URL that just came from the document picker.
    static func makeBookmark(for url: URL) -> Data? {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        return try? url.bookmarkData()
    }
}
