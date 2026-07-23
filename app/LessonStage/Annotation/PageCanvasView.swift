import PDFKit
import PencilKit
import UIKit

/// The per-page canvas, plus copy-mode routing.
///
/// Copy mode is the GoodReader gesture: a stroke that starts on a character
/// becomes a text highlight; a stroke that starts on whitespace becomes ink.
/// The decision is made once, at touch-down, by hit-testing the page's text
/// layout — never mid-stroke, so a highlight that drifts off the text does not
/// suddenly turn into a scribble.
///
/// When copy mode is off, or the tool is not a highlighter, the canvas behaves
/// as a plain `PKCanvasView` and every stroke is ink.
final class PageCanvasView: PKCanvasView {
    /// Debug-only; nil in a shipping build, where the touch overrides reduce
    /// to a plain `super` call.
    weak var diagnostics: CanvasDiagnostics?

    /// Supplies the page's text layout and receives committed highlights.
    /// Weak: the provider owns this view, not the other way round.
    weak var router: (any CopyModeRouter)?

    /// The PDF view this canvas overlays. Touch points are handed to the
    /// router in *this* view's coordinate space, so the router can use PDFKit's
    /// own conversion to reach page space — the canvas must not assume the
    /// overlay's coordinate origin matches a PDF page's (it does not: UIKit is
    /// top-left, PDF space is bottom-left).
    weak var hostPDFView: UIView?

    /// A touch point translated into the host PDF view's coordinate space.
    private func hostPoint(for touch: UITouch) -> CGPoint {
        let local = touch.location(in: self)
        guard let hostPDFView else { return local }
        return convert(local, to: hostPDFView)
    }

    /// The current text selection under the drag, or nil while the drag has
    /// not yet crossed any text.
    private var activeSelection: PDFSelection?
    /// Where the highlighter drag began. Non-nil means a selection gesture is
    /// in progress — even before any text is under it.
    private var selectionStart: CGPoint?

    /// Preview throttle. Coalesced touch-moves arrive in floods — a normal
    /// drag fires hundreds — and rebuilding the preview annotation on each one
    /// saturates the main thread, so CoreAnimation never gets a gap to paint
    /// and nothing shows until the flood ends on release. Rebuilding at most
    /// once per frame leaves those gaps.
    private var lastPreviewTime: CFTimeInterval = 0
    private var pendingPoint: CGPoint?
    private let previewInterval: CFTimeInterval = 1.0 / 60

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        report(touches, phase: "began")

        if let touch = touches.first {
            // The eraser reaches highlights too: a tap on a highlight removes
            // it. Ink is erased by the canvas's own eraser, so fall through
            // when nothing was hit.
            if eraseHighlightIfHit(at: touch) { return }
            // The highlighter claims the whole gesture as a text selection.
            if beginSelectionIfHighlighter(at: touch) { return }
        }
        super.touchesBegan(touches, with: event)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        report(touches, phase: "moved")

        if selectionStart != nil, let touch = touches.first {
            extendSelection(to: touch)
            return
        }
        super.touchesMoved(touches, with: event)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        if let start = selectionStart {
            // The final selection uses the actual end point, unthrottled, so a
            // fast flick that skipped every preview frame still commits the
            // full span.
            if let touch = touches.first {
                activeSelection = router?.selection(from: start, to: hostPoint(for: touch))
            }
            commitHighlight()
            return
        }
        super.touchesEnded(touches, with: event)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        report(touches, phase: "CANCELLED")

        if selectionStart != nil {
            endSelection()
            return
        }
        super.touchesCancelled(touches, with: event)
    }

    // MARK: - Copy-mode routing

    /// With the eraser active, remove a highlight under the touch. Returns
    /// whether one was hit — if not, the canvas's own eraser handles ink.
    private func eraseHighlightIfHit(at touch: UITouch) -> Bool {
        guard let router, router.isEraserActive else { return false }
        let hit = router.eraseHighlight(at: hostPoint(for: touch))
        if hit { diagnostics?.record("highlight erased — page \(tag)") }
        return hit
    }

    /// Claim the whole gesture for text selection whenever the highlighter is
    /// active — no whitespace gate.
    ///
    /// The routing decision used to be made once, at touch-down, from whether
    /// that exact point sat on a glyph. That made starting a hair left of the
    /// first letter fail: the touch landed in the margin, was called ink, and
    /// the drag onto text was ignored. GoodReader is forgiving here. So the
    /// highlighter now selects whatever text the drag *spans*, deciding on
    /// release, not at the start — begin just before the word and it still
    /// grabs it. A drag that never crosses text selects nothing and commits
    /// nothing.
    private func beginSelectionIfHighlighter(at touch: UITouch) -> Bool {
        guard let router, router.isCopyModeActive else { return false }

        selectionStart = hostPoint(for: touch)
        // Seed with the character under the start, if any, so a tap that lands
        // on a glyph shows feedback from the first frame.
        activeSelection = router.initialSelection(at: selectionStart!)
        router.showLiveSelection(activeSelection)
        diagnostics?.record("copy-mode — selecting")
        return true
    }

    private func extendSelection(to touch: UITouch) {
        pendingPoint = hostPoint(for: touch)

        // At most one preview rebuild per frame; intermediate moves just record
        // the latest point. The end point is always applied in `touchesEnded`.
        let now = CACurrentMediaTime()
        guard now - lastPreviewTime >= previewInterval else { return }
        lastPreviewTime = now

        guard let start = selectionStart, let point = pendingPoint else { return }
        activeSelection = router?.selection(from: start, to: point)
        router?.showLiveSelection(activeSelection)
    }

    private func commitHighlight() {
        defer { endSelection() }
        guard let selection = activeSelection, !(selection.string ?? "").isEmpty else {
            diagnostics?.recordCoalesced("copy-mode — no text spanned")
            return
        }
        router?.commitHighlight(selection, onPage: tag)
        diagnostics?.record("highlight committed — page \(tag)")
    }

    private func endSelection() {
        activeSelection = nil
        selectionStart = nil
        pendingPoint = nil
        lastPreviewTime = 0
        router?.clearLiveSelection()
    }

    // MARK: - Diagnostics

    private func report(_ touches: Set<UITouch>, phase: String) {
        guard let diagnostics, let touch = touches.first else { return }
        let kind = switch touch.type {
        case .direct: "finger"
        case .pencil: "pencil"
        case .indirectPointer: "pointer"
        default: "other(\(touch.type.rawValue))"
        }
        MainActor.assumeIsolated {
            diagnostics.recordCoalesced("touch \(phase) — \(kind), page \(tag)")
        }
    }
}

/// What the canvas needs from the page to route a copy-mode stroke, and where
/// it sends a committed highlight. The provider implements it; the canvas
/// stays free of PDFKit and of the annotation store.
@MainActor
protocol CopyModeRouter: AnyObject {
    /// Copy mode is on and the current tool highlights rather than inks.
    var isCopyModeActive: Bool { get }

    /// The eraser is the active tool.
    var isEraserActive: Bool { get }

    /// Remove a highlight under a point in PDF-view space. Returns whether one
    /// was there.
    func eraseHighlight(at point: CGPoint) -> Bool

    /// The selection of the single character under a point in PDF-view space,
    /// or nil for whitespace. Non-nil is the whole routing decision *and* the
    /// first frame of selection feedback — the reason it returns the selection
    /// rather than a bare bool.
    func initialSelection(at point: CGPoint) -> PDFSelection?

    /// A selection between two points in PDF-view space.
    func selection(from: CGPoint, to: CGPoint) -> PDFSelection?

    /// Show the selection as it is dragged, and clear it on lift or cancel.
    func showLiveSelection(_ selection: PDFSelection?)
    func clearLiveSelection()

    /// Persist a finished selection as a highlight on the given page.
    func commitHighlight(_ selection: PDFSelection, onPage index: Int)
}
