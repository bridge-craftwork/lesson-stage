import Foundation
import os

/// Finds lesson days under a root folder, per a `LibraryConfiguration`.
///
/// Enumeration is metadata-only — it reads folder and file *names* and iCloud
/// status, never file contents — so pointing this at an iCloud folder does not
/// download anything. The download happens only when a day's PDFs are opened.
enum LessonLibrary {
    private static let logger = Logger(subsystem: "com.popperbiz.LessonStage", category: "library")

    /// Every day folder under `root`, sorted by date ascending. `today` is a
    /// parameter so the windowing can be tested deterministically.
    static func discoverDays(root: URL, config: LibraryConfiguration) -> [LessonDay] {
        let dateParser = DayDateParser(pattern: config.datePattern, format: config.dateFormat)
        var days: [LessonDay] = []

        let dayFolders = dayFolders(under: root, maxDepth: config.maxDepth, parser: dateParser)
        for (folder, date) in dayFolders {
            let handoutsFolder = config.leafSubfolder.isEmpty
                ? folder
                : folder.appending(path: config.leafSubfolder, directoryHint: .isDirectory)

            let handouts = handouts(in: handoutsFolder, ignoring: config.ignoreGlobs)
            days.append(LessonDay(date: date, folderURL: folder, handouts: handouts))
        }

        return days.sorted { $0.date < $1.date }
    }

    /// The `before`/`after` window of days around today. `after` counts from
    /// the first day that is today or later, so the current or next class is
    /// always the anchor and the entries ahead of it are what's coming.
    static func window(
        _ days: [LessonDay],
        around today: Date,
        before: Int,
        after: Int,
        calendar: Calendar = .current
    ) -> [LessonDay] {
        guard !days.isEmpty else { return [] }
        let startOfToday = calendar.startOfDay(for: today)

        // Index of the anchor: the first day that is today or in the future.
        let anchor = days.firstIndex { $0.date >= startOfToday } ?? days.count

        let lower = max(0, anchor - before)
        let upper = min(days.count, anchor + after)
        return Array(days[lower..<upper])
    }

    /// The day that is today or the next upcoming — the one to highlight.
    static func anchorDay(in days: [LessonDay], today: Date, calendar: Calendar = .current) -> LessonDay? {
        let startOfToday = calendar.startOfDay(for: today)
        return days.first { $0.date >= startOfToday } ?? days.last
    }

    // MARK: - Enumeration

    /// Folders under `root` whose name carries a date, with that date. Recurses
    /// to `maxDepth`, reading names only.
    private static func dayFolders(
        under root: URL,
        maxDepth: Int,
        parser: DayDateParser
    ) -> [(URL, Date)] {
        var found: [(URL, Date)] = []

        func walk(_ folder: URL, depth: Int) {
            guard depth <= maxDepth else { return }
            let entries = (try? FileManager.default.contentsOfDirectory(
                at: folder,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )) ?? []

            for entry in entries where entry.hasDirectoryPath {
                if let date = parser.date(in: entry.lastPathComponent) {
                    // A dated folder is a leaf of the search: its contents are a
                    // day's material, not more day folders.
                    found.append((entry, date))
                } else {
                    walk(entry, depth: depth + 1)
                }
            }
        }

        walk(root, depth: 1)
        return found
    }

    /// The openable PDFs in a handouts folder, ignore-filtered and name-sorted.
    private static func handouts(in folder: URL, ignoring globs: [String]) -> [LessonFile] {
        let entries = (try? FileManager.default.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: [.ubiquitousItemDownloadingStatusKey, .isUbiquitousItemKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        return entries
            .filter { $0.pathExtension.lowercased() == "pdf" }
            .filter { !Glob.matchesAny(globs, $0.lastPathComponent) }
            .map { LessonFile(url: $0, name: $0.deletingPathExtension().lastPathComponent, availability: availability(of: $0)) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private static func availability(of url: URL) -> LessonFile.Availability {
        let values = try? url.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey, .isUbiquitousItemKey])
        guard values?.isUbiquitousItem == true else { return .local }

        switch values?.ubiquitousItemDownloadingStatus {
        case .current, .downloaded: return .local
        default: return .remote
        }
    }
}

/// Extracts the date embedded in a folder name.
private struct DayDateParser {
    let regex: NSRegularExpression?
    let formatter: DateFormatter

    init(pattern: String, format: String) {
        regex = try? NSRegularExpression(pattern: pattern)
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = format
        f.timeZone = .current
        formatter = f
    }

    func date(in name: String) -> Date? {
        guard let regex else { return nil }
        let range = NSRange(name.startIndex..., in: name)
        guard let match = regex.firstMatch(in: name, range: range),
              let matched = Range(match.range, in: name) else { return nil }
        return formatter.date(from: String(name[matched]))
    }
}

/// Minimal case-insensitive glob matching: `*` matches any run of characters.
enum Glob {
    static func matchesAny(_ globs: [String], _ name: String) -> Bool {
        globs.contains { matches($0, name) }
    }

    static func matches(_ glob: String, _ name: String) -> Bool {
        // Escape regex metacharacters, then turn the glob's `*` into `.*`.
        let escaped = NSRegularExpression.escapedPattern(for: glob)
            .replacingOccurrences(of: "\\*", with: ".*")
        let pattern = "^\(escaped)$"
        return name.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }
}
