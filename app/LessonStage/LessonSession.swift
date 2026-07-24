import Foundation
import Observation

/// The set of open lessons, which one is showing, and where each was left.
///
/// This is the thing session restore rehydrates, so tab state lives here
/// rather than in a view.
@MainActor
@Observable
final class LessonSession {
    private(set) var tabs: [LessonTab] = []

    /// Which tab is showing.
    ///
    /// Persisted on change: switching tabs is a session edit like any other,
    /// and without this the app reopens on whichever tab happened to be
    /// selected the last time something *else* triggered a save.
    var selectedTabID: LessonTab.ID? {
        didSet {
            guard selectedTabID != oldValue, !isRestoring else { return }
            persist()
        }
    }

    /// Suppresses persistence while `restore` is rebuilding state, so the
    /// restore does not write its own half-built result back over the file it
    /// is still reading from.
    private var isRestoring = false

    /// Chrome hidden for projection. Survives tab switches, not launches —
    /// starting up in presentation mode with no way back would be a trap.
    var isPresenting = false

    var showsThumbnails = false

    /// Whether the Pencil marks the page or scrolls it. Not persisted: which
    /// mode you want depends on what you are doing right now, and inheriting
    /// last week's answer is worse than starting from the same place daily.
    var isDrawingEnabled = true

    var tool: DrawingTool = .pen(.black)

    /// The tool to return to when the eraser is toggled off. Only meaningful
    /// while the eraser is the current tool.
    private var toolBeforeEraser: DrawingTool?

    /// Flip between the eraser and the last drawing tool — the Apple Pencil
    /// double-tap. A second double-tap returns to whatever was selected before.
    func toggleEraser() {
        if tool == .eraser {
            tool = toolBeforeEraser ?? .pen(.black)
            toolBeforeEraser = nil
        } else {
            toolBeforeEraser = tool
            tool = .eraser
        }
    }

    #if DEBUG
    /// The diagnostics tab, and whether it is the one showing. Debug builds
    /// only — this is a development instrument, not a feature.
    let diagnostics = CanvasDiagnostics()
    var showsDiagnostics = false
    #endif

    private let store: SessionStore

    init(store: SessionStore = SessionStore()) {
        self.store = store
    }

    var selectedTab: LessonTab? {
        guard let selectedTabID else { return nil }
        return tabs.first { $0.id == selectedTabID }
    }

    // MARK: - Opening and closing

    /// Open a document, or select it if it is already open.
    ///
    /// Reopening rather than duplicating matters in class: the same lesson
    /// gets tapped twice and a second tab scrolled to a different page is
    /// never what was wanted.
    func open(url: URL, bookmark: Data? = nil, activate: Bool = true) {
        if let existing = tabs.first(where: { $0.url == url }) {
            if activate { selectedTabID = existing.id }
            return
        }

        let tab = LessonTab(
            url: url,
            bookmark: bookmark ?? SessionStore.makeBookmark(for: url)
        )
        tab.load()
        tabs.append(tab)
        if activate { selectedTabID = tab.id }
        persist()
    }

    func open(urls: [URL]) {
        for (index, url) in urls.enumerated() {
            // Activate the first of a multi-select; the rest open behind it.
            open(url: url, activate: index == 0)
        }
    }

    /// Swap the whole open set for a new one — the Load-from-Library "open this
    /// day" action. The current tabs are flushed and closed first, so switching
    /// days replaces the week's handouts rather than piling onto them.
    func replaceTabs(with items: [(url: URL, bookmark: Data?)]) {
        for tab in tabs { tab.close() }
        isRestoring = true
        tabs = []
        selectedTabID = nil
        isRestoring = false

        for (index, item) in items.enumerated() {
            // Activate the first; the rest open behind it, as a multi-select does.
            open(url: item.url, bookmark: item.bookmark, activate: index == 0)
        }
        // `open` already persisted; an empty set still needs the cleared state written.
        if items.isEmpty { persist() }
    }

    func close(_ id: LessonTab.ID) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        tabs[index].close()
        tabs.remove(at: index)

        if selectedTabID == id {
            // Select the neighbour that took its place, else the new last tab.
            selectedTabID = tabs[safe: index]?.id ?? tabs.last?.id
        }
        persist()
    }

    func move(from source: IndexSet, to destination: Int) {
        tabs.move(fromOffsets: source, toOffset: destination)
        persist()
    }

    /// Move a single tab, addressed by id — what a drag on the strip produces.
    func move(id: LessonTab.ID, before targetID: LessonTab.ID) {
        guard id != targetID,
              let from = tabs.firstIndex(where: { $0.id == id }),
              let to = tabs.firstIndex(where: { $0.id == targetID }) else { return }
        tabs.move(fromOffsets: IndexSet(integer: from), toOffset: to > from ? to + 1 : to)
        persist()
    }

    // MARK: - Position tracking

    func recordPage(_ pageIndex: Int, for id: LessonTab.ID) {
        guard let tab = tabs.first(where: { $0.id == id }), tab.pageIndex != pageIndex else { return }
        tab.pageIndex = pageIndex
        persist()
    }

    // MARK: - Persistence

    /// Restore the previous session. Tabs whose files have moved or been
    /// deleted are dropped rather than reopened broken.
    ///
    /// Bookmark resolution runs off the main thread: for an iCloud item it can
    /// block, and this is on the launch path — doing it inline froze the first
    /// frame to a black screen until every tab resolved.
    func restore() async {
        let persisted = store.load()

        let resolved = await Task.detached {
            persisted.tabs.map { entry in (entry, SessionStore.resolve(bookmark: entry.bookmark)) }
        }.value

        var restored: [LessonTab] = []
        for (entry, resolution) in resolved {
            guard let (url, refreshed) = resolution else { continue }
            let tab = LessonTab(
                id: entry.id,
                url: url,
                title: entry.title,
                bookmark: refreshed ?? entry.bookmark,
                pageIndex: entry.pageIndex
            )
            restored.append(tab)
        }

        isRestoring = true
        tabs = restored
        selectedTabID = persisted.selectedID.flatMap { id in
            restored.contains(where: { $0.id == id }) ? id : nil
        } ?? restored.first?.id
        isRestoring = false

        // No PDF is parsed here — the reading view loads the selected tab in
        // its own task after the first frame, so launch never blocks on
        // parsing a document (which streams the whole file to hash it).

        // Write back if anything was dropped or any bookmark was refreshed.
        if restored.count != persisted.tabs.count { persist() }
    }

    /// Write every open document's annotations immediately.
    ///
    /// Called when the app leaves the foreground: iPadOS can suspend or
    /// terminate us at any point after that, and the save debounce would
    /// otherwise be holding the last few strokes in memory.
    func flushDrawings() {
        for tab in tabs { tab.drawings?.saveNow() }
    }

    #if DEBUG
    /// Throw away the saved session so a test starts from a known state.
    /// Each UI test launches a fresh app against the same container, so
    /// without this every test would inherit the previous one's tabs.
    func discardSavedSession() {
        tabs.forEach { $0.close() }
        tabs = []
        selectedTabID = nil
        store.save(SessionStore.PersistedSession())
    }
    #endif

    private func persist() {
        let entries = tabs.compactMap { tab -> SessionStore.PersistedTab? in
            guard let bookmark = tab.bookmark else { return nil }
            return SessionStore.PersistedTab(
                id: tab.id,
                bookmark: bookmark,
                title: tab.title,
                pageIndex: tab.pageIndex
            )
        }
        store.save(SessionStore.PersistedSession(tabs: entries, selectedID: selectedTabID))
    }
}

extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
