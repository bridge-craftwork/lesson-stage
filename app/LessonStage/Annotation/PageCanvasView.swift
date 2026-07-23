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

    /// The in-progress text selection, while a touch is routed to highlighting
    /// rather than to the canvas. Non-nil means "this touch is a highlight".
    private var activeSelection: PDFSelection?
    private var selectionStart: CGPoint?

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        report(touches, phase: "began")

        if let touch = touches.first {
            // The eraser reaches highlights too: a tap on a highlight removes
            // it. Ink is erased by the canvas's own eraser, so fall through
            // when nothing was hit.
            if eraseHighlightIfHit(at: touch) { return }
            // Copy mode: a stroke starting on text highlights instead of inks.
            if beginHighlightIfOnText(at: touch) { return }
        }
        super.touchesBegan(touches, with: event)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        report(touches, phase: "moved")

        if activeSelection != nil, let touch = touches.first {
            extendSelection(to: touch)
            return
        }
        super.touchesMoved(touches, with: event)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        if activeSelection != nil {
            commitHighlight()
            return
        }
        super.touchesEnded(touches, with: event)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        report(touches, phase: "CANCELLED")

        if activeSelection != nil {
            // A cancel drops the highlight rather than committing a partial one.
            activeSelection = nil
            selectionStart = nil
            router?.clearLiveSelection()
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

    /// Decide, once, whether this touch highlights or inks.
    private func beginHighlightIfOnText(at touch: UITouch) -> Bool {
        guard let router, router.isCopyModeActive else { return false }

        let point = hostPoint(for: touch)
        guard router.hasCharacter(at: point) else {
            diagnostics?.recordCoalesced("copy-mode — whitespace, inking")
            return false
        }

        selectionStart = point
        activeSelection = router.selection(from: point, to: point)
        router.showLiveSelection(activeSelection)
        diagnostics?.record("copy-mode — on text, highlighting")
        return true
    }

    private func extendSelection(to touch: UITouch) {
        guard let start = selectionStart else { return }
        let point = hostPoint(for: touch)
        activeSelection = router?.selection(from: start, to: point)
        router?.showLiveSelection(activeSelection)
    }

    private func commitHighlight() {
        defer {
            activeSelection = nil
            selectionStart = nil
            router?.clearLiveSelection()
        }
        guard let selection = activeSelection else { return }
        router?.commitHighlight(selection, onPage: tag)
        diagnostics?.record("highlight committed — page \(tag)")
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

    /// Whether a character sits under a point in PDF-view space. False for
    /// whitespace. This is the whole routing decision.
    func hasCharacter(at point: CGPoint) -> Bool

    /// A selection between two points in PDF-view space.
    func selection(from: CGPoint, to: CGPoint) -> PDFSelection?

    /// Show the selection as it is dragged, and clear it on lift or cancel.
    func showLiveSelection(_ selection: PDFSelection?)
    func clearLiveSelection()

    /// Persist a finished selection as a highlight on the given page.
    func commitHighlight(_ selection: PDFSelection, onPage index: Int)
}
