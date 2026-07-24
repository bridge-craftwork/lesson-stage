import Foundation

/// How to find lesson days under a chosen root folder. Saved once and kept in
/// app memory; nothing here is hardcoded, so the same app serves any folder
/// layout that files days under dated folders.
struct LibraryConfiguration: Codable, Equatable {
    /// Security-scoped bookmark to the folder the user picked (e.g. their
    /// current-year folder, to avoid scanning past years every time).
    var rootBookmark: Data

    /// The subfolder inside a day folder that holds the handouts. Empty means
    /// the PDFs sit directly in the day folder.
    var leafSubfolder = "Handouts"

    /// A date embedded in a day folder's name is matched by this pattern and
    /// parsed by `dateFormat`. The default finds an ISO date anywhere in the
    /// name, so `2026-07-21` and `2026-07-21 Special` both work while
    /// `2026-07 Jul` (a month folder) does not.
    var datePattern = #"\d{4}-\d{2}-\d{2}"#
    var dateFormat = "yyyy-MM-dd"

    /// Handout filenames matching any of these globs are skipped. `*` matches
    /// any run of characters; matching is case-insensitive.
    var ignoreGlobs = ["*Zoom*", "*sign-in*"]

    /// The window of day folders shown around today: this many before, this
    /// many from today-or-next forward.
    var windowBefore = 3
    var windowAfter = 5

    /// How deep to recurse under the root looking for day folders. The default
    /// covers year / month / day without walking a whole drive.
    var maxDepth = 4
}
