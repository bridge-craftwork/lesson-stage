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

    /// The in-flight discovery, if any. Enumerating a large iCloud tree is slow,
    /// so it runs off the main thread; this drives a loading state and lets
    /// `settle()` await it.
    private var refreshTask: Task<Void, Never>?
    var isRefreshing: Bool { refreshTask != nil }

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

    /// Re-run discovery and windowing against the current root, off the main
    /// thread. Metadata-only, but a deep iCloud tree still takes long enough to
    /// stall the UI if done inline, so it is dispatched and published back.
    func refresh(today: Date = Date()) {
        guard let config = configuration, let rootURL else {
            days = []
            anchorID = nil
            return
        }

        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            let windowed = await LibraryManager.discover(root: rootURL, config: config, today: today)
            guard let self, !Task.isCancelled else { return }
            self.days = windowed
            self.anchorID = LessonLibrary.anchorDay(in: windowed, today: today)?.id
            self.refreshTask = nil
        }
    }

    /// Await the in-flight discovery. Tests use this; the UI shows a spinner.
    func settle() async {
        await refreshTask?.value
    }

    private static func discover(root: URL, config: LibraryConfiguration, today: Date) async -> [LessonDay] {
        await Task.detached(priority: .userInitiated) {
            let accessing = root.startAccessingSecurityScopedResource()
            defer { if accessing { root.stopAccessingSecurityScopedResource() } }
            let all = LessonLibrary.discoverDays(root: root, config: config)
            return LessonLibrary.window(all, around: today, before: config.windowBefore, after: config.windowAfter)
        }.value
    }

    // MARK: - Opening a day

    /// Replace the open tabs with a day's handouts.
    ///
    /// Each handout is opened by its *own* security-scoped bookmark, resolved
    /// here while the root scope is held — the same shape a picked or restored
    /// tab has. Handing the tab the raw enumerated URL instead fails once this
    /// method's root scope is released: that URL is not itself scoped, so the
    /// tab cannot read it ("could not open"). Resolving gives a URL that grants
    /// access on its own, and the bookmark also lets the tab reopen next launch.
    func openDay(_ day: LessonDay, into session: LessonSession) {
        guard let rootURL else { return }

        let items: [(url: URL, bookmark: Data?)] = withRootAccess(rootURL) {
            day.handouts.compactMap { handout in
                guard let bookmark = SessionStore.makeBookmark(for: handout.url),
                      let resolved = SessionStore.resolve(bookmark: bookmark) else { return nil }
                return (resolved.url, resolved.refreshed ?? bookmark)
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

    #if DEBUG
    /// Reset to a fresh-install state so a UI test starts from a known point.
    /// Each launch reuses the same app container; without this a prior test's
    /// enabled flag or chosen root would leak into the next.
    func discardSettings() {
        enabled = false
        configuration = nil
        rootURL = nil
        days = []
        anchorID = nil
        save()
    }
    #endif
}
