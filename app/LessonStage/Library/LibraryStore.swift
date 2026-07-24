import Foundation
import os

/// Reads and writes the Load-from-Library settings.
///
/// Stored as JSON in Application Support, alongside `session.json` and for the
/// same reason: the payload carries a security-scoped bookmark (kilobytes),
/// which has no business in a `UserDefaults` plist.
struct LibraryStore {
    struct Persisted: Codable {
        /// Off until the user turns it on. A public build must never surface the
        /// library flow uninvited — ordinary readers only ever see the file
        /// picker.
        var enabled = false

        /// `nil` until a root folder is chosen. Once set it carries the
        /// bookmark and every discovery knob.
        var configuration: LibraryConfiguration?
    }

    private static let logger = Logger(subsystem: "com.popperbiz.LessonStage", category: "library")

    private let fileURL: URL

    init(filename: String = "library.json") {
        let base = URL.applicationSupportDirectory
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        self.fileURL = base.appending(path: filename)
    }

    func load() -> Persisted {
        guard let data = try? Data(contentsOf: fileURL) else { return Persisted() }
        do {
            return try JSONDecoder().decode(Persisted.self, from: data)
        } catch {
            // Unreadable settings are not worth failing a launch over; the
            // feature simply starts off, as it does for a fresh install.
            Self.logger.error("Discarding unreadable library settings: \(error.localizedDescription)")
            return Persisted()
        }
    }

    func save(_ persisted: Persisted) {
        do {
            let data = try JSONEncoder().encode(persisted)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            Self.logger.error("Could not save library settings: \(error.localizedDescription)")
        }
    }
}
