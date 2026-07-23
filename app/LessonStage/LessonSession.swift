import Foundation
import Observation

/// One open lesson. Phase 0 carries only identity — the document, its
/// annotations, and its Contract 5 payload arrive in Phases 1 and 3.
struct LessonTab: Identifiable, Hashable {
    let id = UUID()
    var title: String
    var url: URL?
}

/// The set of open lessons and which one is showing.
///
/// Session restore (Phase 1) will rehydrate this on launch, so tab state
/// lives here rather than in a view.
@Observable
final class LessonSession {
    var tabs: [LessonTab] = []
    var selectedTabID: LessonTab.ID?

    var selectedTab: LessonTab? {
        guard let selectedTabID else { return nil }
        return tabs.first { $0.id == selectedTabID }
    }

    func open(_ tab: LessonTab) {
        tabs.append(tab)
        selectedTabID = tab.id
    }

    func close(_ id: LessonTab.ID) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        tabs.remove(at: index)

        guard selectedTabID == id else { return }
        // Select the neighbour that took its place, else the new last tab.
        selectedTabID = tabs[safe: index]?.id ?? tabs.last?.id
    }
}

private extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
