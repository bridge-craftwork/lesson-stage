import Foundation

/// Just enough PBN handling for the seam: pull one board's game record out of a
/// lesson's `lesson-hands.pbn`. Parsing a record into a deal is the popout's
/// job — this only has to hand the right record across.
enum PBN {
    /// The game record whose `[Board "n"]` matches, or nil if absent.
    static func record(board: Int, in pbn: String) -> String? {
        records(in: pbn).first { boardNumber(of: $0) == board }
    }

    /// Split a PBN file into game records. Records are separated by blank lines;
    /// `\r\n` is normalised first so the split holds regardless of line endings.
    ///
    /// A blank line inside `{…}` commentary is part of the commentary, not a
    /// record break. pbn-to-pdf copies records verbatim, and multi-paragraph
    /// commentary is common in them, so splitting on every blank line would cut
    /// a record short.
    static func records(in pbn: String) -> [String] {
        var records: [String] = []
        var current: [Substring] = []
        var inBrace = false
        func flush() {
            let record = current.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if !record.isEmpty { records.append(record) }
            current = []
        }
        let text = pbn.replacingOccurrences(of: "\r\n", with: "\n")
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            if !inBrace && line.trimmingCharacters(in: .whitespaces).isEmpty {
                flush()
                continue
            }
            current.append(line)
            for character in line where character == "{" || character == "}" {
                inBrace = character == "{"
            }
        }
        flush()
        return records
    }

    /// The board number from a record's `[Board "n"]` tag.
    static func boardNumber(of record: String) -> Int? {
        guard let regex = try? NSRegularExpression(pattern: #"\[Board\s+"(\d+)"\]"#) else { return nil }
        let range = NSRange(record.startIndex..., in: record)
        guard let match = regex.firstMatch(in: record, range: range),
              let group = Range(match.range(at: 1), in: record) else { return nil }
        return Int(record[group])
    }
}
