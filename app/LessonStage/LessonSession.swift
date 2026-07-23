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
    var selectedTabID: LessonTab.ID?

    /// Chrome hidden for projection. Survives tab switches, not launches —
    /// starting up in presentation mode with no way back would be a trap.
    var isPresenting = false

    var showsThumbnails = false

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
    func restore() {
        let persisted = store.load()
        var restored: [LessonTab] = []

        for entry in persisted.tabs {
            guard let (url, refreshed) = SessionStore.resolve(bookmark: entry.bookmark) else { continue }
            let tab = LessonTab(
                id: entry.id,
                url: url,
                title: entry.title,
                bookmark: refreshed ?? entry.bookmark,
                pageIndex: entry.pageIndex
            )
            restored.append(tab)
        }

        tabs = restored
        selectedTabID = persisted.selectedID.flatMap { id in
            restored.contains(where: { $0.id == id }) ? id : nil
        } ?? restored.first?.id

        // Only the visible tab parses now; the rest load when selected.
        selectedTab?.load()

        // Write back if anything was dropped or any bookmark was refreshed.
        if restored.count != persisted.tabs.count { persist() }
    }

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
