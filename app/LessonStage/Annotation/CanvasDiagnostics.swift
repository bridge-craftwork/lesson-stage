import Foundation
import Observation

/// A rolling on-screen log for diagnosing input problems on a device.
///
/// Exists because the failures that matter here are invisible to the
/// simulator — PencilKit ignores synthesized touches — and reading a device's
/// console from a Mac is a slow loop for something you need to watch while
/// your hand is on the iPad. This puts the same facts on the glass.
@MainActor
@Observable
final class CanvasDiagnostics {
    struct Entry: Identifiable {
        let id = UUID()
        let text: String
    }

    private(set) var entries: [Entry] = []

    /// Newest first, oldest dropped: this is watched live, not read back.
    private let limit = 14

    func record(_ text: String) {
        entries.insert(Entry(text: text), at: 0)
        if entries.count > limit { entries.removeLast(entries.count - limit) }
    }

    /// Collapse repeats. Touch events arrive in floods and would otherwise
    /// push everything else off the panel within a second.
    func recordCoalesced(_ text: String) {
        if let first = entries.first, first.text.hasPrefix(text) {
            let count = repeatCount(of: first.text) + 1
            entries[0] = Entry(text: "\(text) ×\(count)")
            return
        }
        record(text)
    }

    private func repeatCount(of text: String) -> Int {
        guard let marker = text.range(of: " ×", options: .backwards),
              let value = Int(text[marker.upperBound...]) else { return 1 }
        return value
    }

    func clear() { entries.removeAll() }
}
