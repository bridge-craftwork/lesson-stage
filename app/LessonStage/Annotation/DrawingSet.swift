import Foundation
import Observation
import PencilKit

/// The annotations for one open document, held in memory while it is open.
///
/// Saving is debounced: `canvasViewDrawingDidChange` fires continuously during
/// a stroke, and writing the sidecar on every callback would put a file write
/// in the middle of the Pencil's input path — the one place latency is
/// unforgivable.
@MainActor
@Observable
final class DrawingSet {
    let contentHash: String

    private(set) var drawings: [Int: PKDrawing]
    /// Text highlights, per page. The ink's counterpart from copy mode.
    private(set) var highlights: [Int: [TextHighlight]]
    private let store: DrawingStore
    private var saveTask: Task<Void, Never>?

    /// How long after the last change to write. Long enough to coalesce a
    /// flurry of stroke updates, short enough that a crash costs one stroke.
    private let saveDelay: Duration

    init(contentHash: String, store: DrawingStore = DrawingStore(), saveDelay: Duration = .seconds(2)) {
        self.contentHash = contentHash
        self.store = store
        self.saveDelay = saveDelay
        let contents = store.load(hash: contentHash)
        self.drawings = contents.drawings
        self.highlights = contents.highlights
    }

    var hasAnnotations: Bool {
        drawings.values.contains { !$0.strokes.isEmpty } || highlights.values.contains { !$0.isEmpty }
    }

    /// How many pages carry marks — ink or highlight. Surfaced in debug builds
    /// so a UI test can assert on annotation state, which it otherwise cannot
    /// see at all: neither a `PKDrawing` nor a PDF annotation is in the
    /// accessibility tree.
    var annotatedPageCount: Int {
        let inked = Set(drawings.filter { !$0.value.strokes.isEmpty }.keys)
        let highlighted = Set(highlights.filter { !$0.value.isEmpty }.keys)
        return inked.union(highlighted).count
    }

    func drawing(forPage index: Int) -> PKDrawing {
        drawings[index] ?? PKDrawing()
    }

    func update(_ drawing: PKDrawing, forPage index: Int) {
        // Identical redraws arrive routinely — attaching a canvas to a page
        // reports its own initial contents as a change.
        guard drawings[index] != drawing else { return }
        drawings[index] = drawing
        scheduleSave()
    }

    func clear(page index: Int) {
        let hadInk = drawings[index] != nil
        let hadHighlights = highlights[index] != nil
        guard hadInk || hadHighlights else { return }
        drawings[index] = nil
        highlights[index] = nil
        scheduleSave()
    }

    // MARK: - Highlights

    func highlights(forPage index: Int) -> [TextHighlight] {
        highlights[index] ?? []
    }

    func addHighlight(_ highlight: TextHighlight, toPage index: Int) {
        highlights[index, default: []].append(highlight)
        scheduleSave()
    }

    /// Remove any highlight on `page` covering `point` — the eraser reaching a
    /// highlight rather than ink. Returns whether anything was removed.
    @discardableResult
    func removeHighlight(atPage index: Int, containing point: CGPoint) -> Bool {
        guard var pageHighlights = highlights[index] else { return false }
        let before = pageHighlights.count
        pageHighlights.removeAll { $0.contains(point) }
        guard pageHighlights.count != before else { return false }

        highlights[index] = pageHighlights.isEmpty ? nil : pageHighlights
        scheduleSave()
        return true
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            guard let delay = self?.saveDelay else { return }
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.saveNow()
        }
    }

    /// Write immediately. Called when the document closes or the app leaves
    /// the foreground, where waiting out the debounce would lose work.
    func saveNow() {
        saveTask?.cancel()
        saveTask = nil
        store.save(DrawingStore.Contents(drawings: drawings, highlights: highlights), hash: contentHash)
    }
}
