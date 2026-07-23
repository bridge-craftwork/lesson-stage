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
    private let store: DrawingStore
    private var saveTask: Task<Void, Never>?

    /// How long after the last change to write. Long enough to coalesce a
    /// flurry of stroke updates, short enough that a crash costs one stroke.
    private let saveDelay: Duration

    init(contentHash: String, store: DrawingStore = DrawingStore(), saveDelay: Duration = .seconds(2)) {
        self.contentHash = contentHash
        self.store = store
        self.saveDelay = saveDelay
        self.drawings = store.load(hash: contentHash)
    }

    var hasAnnotations: Bool {
        drawings.values.contains { !$0.strokes.isEmpty }
    }

    /// How many pages carry marks. Surfaced in debug builds so a UI test can
    /// assert on drawing state, which it otherwise cannot see at all — a
    /// `PKDrawing` is invisible to the accessibility tree.
    var annotatedPageCount: Int {
        drawings.values.filter { !$0.strokes.isEmpty }.count
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
        guard drawings[index] != nil else { return }
        drawings[index] = nil
        scheduleSave()
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
        store.save(drawings, hash: contentHash)
    }
}
