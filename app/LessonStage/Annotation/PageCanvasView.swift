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

    /// True while the smart hold-to-highlight gesture is driving a selection in
    /// pen mode (see `installSmartHighlightGesture`). Distinguishes it from the
    /// highlighter tool's own copy-mode selection so cleanup can restore inking.
    private var smartHighlightActive = false

    /// The pen tap-to-rotate recognizer, kept so the delegate can tell it apart
    /// from the others when deciding which touches it may receive.
    private var tapRotateGesture: UITapGestureRecognizer?

    /// Preview throttle. Coalesced touch-moves arrive in floods — a normal
    /// drag fires hundreds — and rebuilding the preview annotation on each one
    /// saturates the main thread, so CoreAnimation never gets a gap to paint
    /// and nothing shows until the flood ends on release. Rebuilding at most
    /// once per frame leaves those gaps.
    private var lastPreviewTime: CFTimeInterval = 0
    private var pendingPoint: CGPoint?
    private let previewInterval: CFTimeInterval = 1.0 / 60

    /// A gesture that moves less than this (in PDF-view points) is a tap, not a
    /// drag — it rotates a tapped highlight's colour rather than laying a new
    /// highlight down.
    private static let tapMovementThreshold: CGFloat = 10

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

        // Skipped while a smart pen-hold highlight is running: that gesture is
        // driven by its own recognizer, so letting this path also extend the
        // selection would double-drive it.
        if selectionStart != nil, !smartHighlightActive, let touch = touches.first {
            extendSelection(to: touch)
            return
        }
        super.touchesMoved(touches, with: event)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        // The smart pen-hold highlight ends on its own recognizer, not here.
        if let start = selectionStart, !smartHighlightActive {
            let endPoint = touches.first.map { hostPoint(for: $0) } ?? start

            // A tap, not a drag: rotate the colour of a highlight under it, and
            // lay down nothing from a stray tap that spanned no real distance.
            if hypot(endPoint.x - start.x, endPoint.y - start.y) < Self.tapMovementThreshold {
                _ = router?.rotateHighlightColor(at: endPoint)
                endSelection()
                return
            }

            // The final selection uses the actual end point, unthrottled, so a
            // fast flick that skipped every preview frame still commits the
            // full span.
            activeSelection = router?.selection(from: start, to: endPoint)
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

        // If this was the smart pen-hold highlight, hand the pen back: re-enable
        // inking and drop the colour override.
        if smartHighlightActive {
            smartHighlightActive = false
            drawingGestureRecognizer.isEnabled = true
            router?.endSmartHighlight()
        }
    }

    // MARK: - Smart hold-to-highlight

    /// A brief press-and-hold on text while a pen is selected highlights instead
    /// of inking, then hands the pen straight back — the GoodReader-ish shortcut
    /// for grabbing a phrase without switching tools.
    ///
    /// A gesture recognizer, not the touch overrides copy mode uses, because in
    /// pen mode PencilKit claims the touch immediately to ink it — the view then
    /// stops seeing the moves. A recognizer gets its own location stream, so the
    /// selection can be driven even after PencilKit has taken the touch. It is
    /// pencil-only: a finger in draw mode scrolls the page, and must not trip a
    /// highlight, and it keeps the gesture out of the finger-driven UI tests.
    ///
    /// Fail-safe: if the pencil moves past `allowableMovement` before the hold
    /// elapses the recognizer fails and inking proceeds untouched, so ordinary
    /// writing is never disturbed. `cancelsTouchesInView = false` so merely
    /// observing the touch doesn't cancel the ink — that happens only when a
    /// hold on text actually wins.
    func installSmartHighlightGesture() {
        let hold = UILongPressGestureRecognizer(target: self, action: #selector(handleSmartHold(_:)))
        hold.minimumPressDuration = 0.18
        hold.allowableMovement = 10
        hold.cancelsTouchesInView = false
        hold.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.pencil.rawValue)]
        hold.delegate = self
        addGestureRecognizer(hold)

        // Tap-to-rotate, also on the pen. Pencil-only, and — via the delegate's
        // `shouldReceive` — it only engages for a tap that lands on an existing
        // highlight, so ordinary taps are ignored by it. PencilKit's drawing
        // recognizer is required to fail behind it, so a tap that rotates a
        // colour never also inks a dot; because the recognizer only takes
        // highlight-touches, drawing anywhere else is not gated or delayed.
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTapRotate(_:)))
        tap.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.pencil.rawValue)]
        tap.delegate = self
        addGestureRecognizer(tap)
        tapRotateGesture = tap
        drawingGestureRecognizer.require(toFail: tap)
    }

    @objc private func handleTapRotate(_ gesture: UITapGestureRecognizer) {
        guard let router, router.isPenActive else { return }
        if router.rotateHighlightColor(at: hostPoint(fromGesture: gesture)) {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            diagnostics?.record("smart rotate — pen tap on highlight, page \(tag)")
        }
    }

    @objc private func handleSmartHold(_ gesture: UILongPressGestureRecognizer) {
        guard let router, router.isPenActive else { return }
        let host = hostPoint(fromGesture: gesture)

        switch gesture.state {
        case .began:
            // Only over text — a hold on blank space stays an ordinary pen dot,
            // so this leaves PencilKit alone in that case.
            guard let selection = router.initialSelection(at: host) else { return }
            smartHighlightActive = true
            // Cancel the stationary ink the hold just started, and stop further
            // inking for the rest of this gesture.
            drawingGestureRecognizer.isEnabled = false
            router.beginSmartHighlight()
            selectionStart = host
            activeSelection = selection
            router.showLiveSelection(activeSelection)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            diagnostics?.record("smart highlight — pen hold on text, page \(tag)")

        case .changed:
            guard smartHighlightActive, let start = selectionStart else { return }
            activeSelection = router.selection(from: start, to: host)
            router.showLiveSelection(activeSelection)

        case .ended:
            guard smartHighlightActive else { return }
            if let start = selectionStart {
                activeSelection = router.selection(from: start, to: host)
            }
            commitHighlight() // commits, then `endSelection` restores the pen

        case .cancelled, .failed:
            guard smartHighlightActive else { return }
            endSelection()

        default:
            break
        }
    }

    /// A gesture's location translated into the host PDF view's space, matching
    /// `hostPoint(for:)` but for a recognizer rather than a raw touch.
    private func hostPoint(fromGesture gesture: UIGestureRecognizer) -> CGPoint {
        let local = gesture.location(in: self)
        guard let hostPDFView else { return local }
        return convert(local, to: hostPDFView)
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

extension PageCanvasView: UIGestureRecognizerDelegate {
    /// The smart-hold recognizer must track the pencil alongside PencilKit's own
    /// drawing recognizer (which has the touch), so it has to recognize
    /// simultaneously; it stays dormant until a hold on text wins.
    nonisolated func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
    ) -> Bool {
        true
    }

    /// Gate the tap-to-rotate recognizer to touches that start on a highlight
    /// while a pen is active. Everything else — and every other recognizer —
    /// takes its touches as usual, so PencilKit is never made to wait behind the
    /// tap except where a tap could actually rotate a colour.
    nonisolated func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldReceive touch: UITouch
    ) -> Bool {
        MainActor.assumeIsolated {
            guard gestureRecognizer === tapRotateGesture else { return true }
            guard let router, router.isPenActive, touch.type == .pencil else { return false }
            return router.highlightExists(at: hostPoint(for: touch))
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

    /// A pen (not highlighter, not eraser) is the active tool — the mode the
    /// smart hold-to-highlight gesture applies in.
    var isPenActive: Bool { get }

    /// Begin / end a smart hold-to-highlight gesture, which highlights with the
    /// last-used tint while a pen is selected, then restores pen colouring.
    func beginSmartHighlight()
    func endSmartHighlight()

    /// Remove a highlight under a point in PDF-view space. Returns whether one
    /// was there.
    func eraseHighlight(at point: CGPoint) -> Bool

    /// Whether a highlight sits under a point in PDF-view space — the test that
    /// decides whether a pen tap should rotate a colour rather than ink.
    func highlightExists(at point: CGPoint) -> Bool

    /// Cycle the colour of a highlight under a point (PDF-view space) to the
    /// next highlighter tint, leaving the tool's own colour alone. Returns
    /// whether a highlight was there to rotate.
    func rotateHighlightColor(at point: CGPoint) -> Bool

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
