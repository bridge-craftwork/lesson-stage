import Foundation
import Observation
import os

/// Owns the Load-from-Library feature: the enabled flag, the chosen root
/// folder, and the windowed list of lesson days discovered under it.
///
/// The counterpart to `LessonSession` for the library side. Discovery is
/// metadata-only (see `LessonLibrary`), so nothing downloads until a day's
/// handouts are actually opened.
@MainActor
@Observable
final class LibraryManager {
    private static let logger = Logger(subsystem: "com.popperbiz.LessonStage", category: "library")

    /// Whether the feature is turned on. Off by default; a public build hides
    /// the whole flow until the user enables it in Settings.
    private(set) var enabled: Bool

    /// How to find days under the root. `nil` until a folder is chosen.
    private(set) var configuration: LibraryConfiguration?

    /// The resolved root folder, valid while `configuration` is set. Reading
    /// its contents must happen inside `withRootAccess`.
    private(set) var rootURL: URL?

    /// The current windowed day list, refreshed by `refresh()`.
    private(set) var days: [LessonDay] = []

    /// The day to highlight — today or the next upcoming class.
    private(set) var anchorID: LessonDay.ID?

    var isConfigured: Bool { configuration != nil && rootURL != nil }

    private let store: LibraryStore

    init(store: LibraryStore = LibraryStore()) {
        self.store = store
        let persisted = store.load()
        self.enabled = persisted.enabled
        self.configuration = persisted.configuration
        self.rootURL = nil

        // Resolve the root bookmark now, refreshing it if the folder moved —
        // the same dance `SessionStore.resolve` does for open tabs.
        if let config = persisted.configuration,
           let (url, refreshed) = SessionStore.resolve(bookmark: config.rootBookmark) {
            self.rootURL = url
            if let refreshed {
                self.configuration?.rootBookmark = refreshed
                save()
            }
        }
    }

    // MARK: - Settings

    func setEnabled(_ value: Bool) {
        guard value != enabled else { return }
        enabled = value
        save()
    }

    /// Adopt a freshly picked root folder (from the directory picker, or a
    /// debug launch argument). Builds and stores the security-scoped bookmark,
    /// keeping any previously edited knobs.
    func configure(rootURL url: URL) {
        guard let bookmark = SessionStore.makeBookmark(for: url) else {
            Self.logger.error("Could not bookmark chosen library root")
            return
        }
        if configuration == nil {
            configuration = LibraryConfiguration(rootBookmark: bookmark)
        } else {
            configuration?.rootBookmark = bookmark
        }
        rootURL = url
        save()
        refresh()
    }

    /// Persist edits to the discovery knobs (globs, window sizes, …) and
    /// re-run discovery so the change is visible immediately.
    func updateConfiguration(_ update: (inout LibraryConfiguration) -> Void) {
        guard configuration != nil else { return }
        update(&configuration!)
        save()
        refresh()
    }

    // MARK: - Discovery

    /// Re-run discovery and windowing against the current root. Cheap — it reads
    /// folder and file names only — so it is safe to call on each sheet open.
    func refresh(today: Date = Date()) {
        guard let config = configuration, let rootURL else {
            days = []
            anchorID = nil
            return
        }

        let windowed: [LessonDay] = withRootAccess(rootURL) {
            let all = LessonLibrary.discoverDays(root: rootURL, config: config)
            return LessonLibrary.window(all, around: today, before: config.windowBefore, after: config.windowAfter)
        }
        days = windowed
        anchorID = LessonLibrary.anchorDay(in: windowed, today: today)?.id
    }

    // MARK: - Opening a day

    /// Replace the open tabs with a day's handouts.
    ///
    /// Remote handouts are kicked off downloading; every handout is opened as a
    /// tab regardless, so a day whose files are still arriving shows tabs that
    /// fill in as their PDFs land. Each tab gets its own bookmark, made while
    /// the root scope is held, so it reopens across launches like a picked file.
    func openDay(_ day: LessonDay, into session: LessonSession) {
        guard let rootURL else { return }

        let items: [(url: URL, bookmark: Data?)] = withRootAccess(rootURL) {
            day.handouts.map { handout in
                if !handout.isLocal {
                    // Trigger the download; opening will show a placeholder until
                    // the file is local. iCloud state can't be exercised on the
                    // simulator, so this path is confirmed on device.
                    try? FileManager.default.startDownloadingUbiquitousItem(at: handout.url)
                }
                return (handout.url, SessionStore.makeBookmark(for: handout.url))
            }
        }

        session.replaceTabs(with: items)
    }

    // MARK: - Internals

    /// Run `body` with the root folder's security scope held. A folder picked
    /// from outside the sandbox grants access to its children only while the
    /// scope is active.
    private func withRootAccess<T>(_ url: URL, _ body: () -> T) -> T {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        return body()
    }

    private func save() {
        store.save(LibraryStore.Persisted(enabled: enabled, configuration: configuration))
    }
}
