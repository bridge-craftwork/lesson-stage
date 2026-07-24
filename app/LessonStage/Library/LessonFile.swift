import Foundation

/// One PDF discovered in a day's handouts folder.
///
/// A value type describing what the folder holds, distinct from `LessonTab`,
/// which is an *open* document. A file becomes a tab when opened.
struct LessonFile: Identifiable, Hashable {
    var id: URL { url }
    let url: URL
    let name: String

    /// iCloud state. A lesson in a shared folder may not be on the device yet;
    /// opening it has to wait for, or trigger, a download.
    enum Availability: Hashable {
        /// On the device, ready to open.
        case local
        /// In iCloud, not yet downloaded.
        case remote
        /// Download in progress.
        case downloading(fraction: Double)
    }
    var availability: Availability

    var isLocal: Bool {
        if case .local = availability { return true }
        return false
    }
}

/// One class day: a dated folder, and the handout PDFs inside its leaf folder.
struct LessonDay: Identifiable, Hashable {
    var id: URL { folderURL }
    let date: Date
    /// The dated folder itself (e.g. `.../2026-07-21`).
    let folderURL: URL
    /// The handouts to open for this day, ignore-filtered and sorted by name.
    var handouts: [LessonFile]

    var isPopulated: Bool { !handouts.isEmpty }
}
