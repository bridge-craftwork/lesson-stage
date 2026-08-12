import PDFKit
import PencilKit
import os

/// Hangs a `PKCanvasView` on every page PDFKit displays.
///
/// `PDFPageOverlayViewProvider` is the API this exists for, and the reason the
/// deployment floor is iPadOS 17: PDFKit sizes each overlay to its page and
/// keeps it registered through scroll and zoom, so the canvas shares the
/// page's coordinate space and a drawing stays put on the paper rather than on
/// the screen.
@MainActor
final class PageCanvasProvider: NSObject {
    static let logger = Logger(subsystem: "com.popperbiz.LessonStage", category: "canvas")

    /// The document being annotated. Swapped when the tab changes.
    var drawings: DrawingSet?

    /// On-screen input diagnostics. Debug builds only.
    var diagnostics: CanvasDiagnostics?

    var tool: DrawingTool = .pen(.black) {
        didSet {
            guard tool != oldValue else { return }
            if case .highlighter(let color) = tool { lastHighlighterColor = color }
            for canvas in liveCanvases.values { apply(tool, to: canvas) }
        }
    }

    /// The highlighter tint to fall back to when the smart hold-to-highlight
    /// gesture fires in pen mode — the last one the teacher actually chose.
    private var lastHighlighterColor: PenColor = .yellow

    /// While the smart hold-to-highlight gesture is running in pen mode, the
    /// colour to highlight with. Non-nil overrides the tool's own colour so the
    /// live and committed highlight render even though the tool is a pen.
    private var smartHighlightColor: PenColor?

    /// The colour a highlight should use right now: the smart-gesture override
    /// if one is running, otherwise the highlighter tool's own colour (nil when
    /// no highlighter is in play).
    private var activeHighlightColor: PenColor? {
        if let smartHighlightColor { return smartHighlightColor }
        if case .highlighter(let color) = tool { return color }
        return nil
    }

    /// Point a canvas at the current tool, and switch PencilKit's ink off for
    /// the highlighter so the only feedback on text is the selection — no stray
    /// marker painting under the Pencil. Done at tool-switch, never mid-touch:
    /// disabling the drawing recognizer during a gesture cancels it.
    ///
    /// Exception under `-fingerDrawing`: the tests drive the highlighter with a
    /// finger, and in marking mode fingers scroll — so with ink off the scroll
    /// pan would claim the finger before the selection could form. Keeping ink
    /// enabled makes PencilKit's recognizer block the pan, letting the finger
    /// reach the canvas. On a real device the highlighter is a Pencil, which
    /// never triggers the fingers-only pan, so ink stays off and the marker
    /// never shows.
    private func apply(_ tool: DrawingTool, to canvas: PageCanvasView) {
        canvas.tool = tool.pkTool
        canvas.drawingGestureRecognizer.isEnabled = !isCopyModeActive || Self.fingerDrawingForTests
    }

    private static let fingerDrawingForTests: Bool = {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains("-fingerDrawing")
        #else
        return false
        #endif
    }()

    /// When false the canvases stop taking input entirely, so a Pencil scrolls
    /// the lesson instead of marking it — which is what you want mid-lesson
    /// with the page on a projector.
    var isDrawingEnabled = true {
        didSet {
            guard isDrawingEnabled != oldValue else { return }
            for canvas in liveCanvases.values { canvas.isUserInteractionEnabled = isDrawingEnabled }
            applyTouchRouting()
        }
    }

    /// The PDF view whose scrolling has to yield to the Pencil. Weak: PDFKit
    /// owns it, and this provider outlives any single page.
    private weak var pdfView: PDFView?

    /// `.pencilOnly` is the default so a finger still scrolls and zooms while
    /// the Pencil draws — no mode switching, which is the behaviour being
    /// replaced. Relaxed to `.anyInput` only under a debug flag, because the
    /// simulator has no Pencil and a drawing path that is never exercised in
    /// a test is a drawing path that silently rots.
    var drawingPolicy: PKCanvasViewDrawingPolicy = .pencilOnly {
        didSet {
            guard drawingPolicy != oldValue else { return }
            for canvas in liveCanvases.values { canvas.drawingPolicy = drawingPolicy }
        }
    }

    /// Canvases currently on screen, by page index.
    private var liveCanvases: [Int: PageCanvasView] = [:]

    /// The page last drawn on, so undo has something to aim at. Undo is
    /// per-canvas in PencilKit; with a canvas per page there is no single
    /// undo stack to consult.
    private(set) var lastEditedPage: Int?

    /// The page a selection is currently being dragged on, if any. The live
    /// highlight is rendered together with that page's committed highlights (see
    /// `renderHighlights`), so dragging back over already-marked text stays one
    /// level of colour rather than doubling.
    private var liveHighlightPage: Int?


    func undo() {
        guard let page = lastEditedPage, let canvas = liveCanvases[page] else { return }
        canvas.undoManager?.undo()
    }

    func canUndo() -> Bool {
        guard let page = lastEditedPage, let canvas = liveCanvases[page] else { return false }
        return canvas.undoManager?.canUndo ?? false
    }

    /// Drop every canvas, e.g. when switching documents. Their drawings are
    /// already in the `DrawingSet`; this only releases the views.
    func reset() {
        liveCanvases.removeAll()
        lastEditedPage = nil
    }

    var hasMarks: Bool { drawings?.hasAnnotations ?? false }

    /// Erase every mark on the document — ink and highlights, all pages — in
    /// one step. No confirmation, by request, because it is a single undo away
    /// from being restored: the whole prior state is snapshotted and the
    /// restore registered as the undo.
    func clearAllMarks() {
        guard let drawings, drawings.hasAnnotations else { return }
        replaceMarks(with: .init(), previous: drawings.snapshot)
    }

    /// Swap the entire annotation set, syncing the live canvases and pages, and
    /// register the inverse so one undo brings it all back. Used by clear-all
    /// and its own undo.
    private func replaceMarks(with contents: DrawingStore.Contents, previous: DrawingStore.Contents) {
        guard let drawings else { return }
        drawings.replaceAll(with: contents)

        // Ink: push the new drawing into every on-screen canvas.
        for (index, canvas) in liveCanvases {
            canvas.drawing = drawings.drawing(forPage: index)
        }
        // Highlights: redraw every page that had, or now has, any.
        let touched = Set(previous.highlights.keys).union(contents.highlights.keys)
        for index in touched { renderHighlights(onPage: index) }

        // One undo restores the whole prior state.
        undoManagerForClearing?.registerUndo(withTarget: self) { provider in
            provider.replaceMarks(with: previous, previous: contents)
        }
    }

    /// Clear-all is document-wide, so its undo cannot hang off one page's
    /// canvas. Any live canvas's undo manager will do — they share the window's
    /// — falling back to the first available.
    private var undoManagerForClearing: UndoManager? {
        liveCanvases[lastEditedPage ?? -1]?.undoManager ?? liveCanvases.values.first?.undoManager
    }
}

extension PageCanvasProvider: PDFPageOverlayViewProvider {
    func pdfView(_ view: PDFView, overlayViewFor page: PDFPage) -> UIView? {
        guard let index = view.document?.index(for: page) else { return nil }

        let canvas = liveCanvases[index] ?? makeCanvas(forPage: index)
        canvas.drawing = drawings?.drawing(forPage: index) ?? PKDrawing()
        liveCanvases[index] = canvas
        return canvas
    }

    func pdfView(_ pdfView: PDFView, willDisplayOverlayView overlayView: UIView, for page: PDFPage) {
        self.pdfView = pdfView
        // Set here, not in `makeCanvas`: `overlayViewFor` runs before this, so
        // the pdfView reference is not yet available when the canvas is built.
        (overlayView as? PageCanvasView)?.hostPDFView = pdfView
        enableInteraction(from: overlayView, upTo: pdfView)
        pinScrollContentToSafeArea(in: pdfView)
        applyTouchRouting()

        #if DEBUG
        if let canvas = overlayView as? PKCanvasView { logCanvasPlacement(canvas) }
        #endif
    }

    /// Stop PDFKit's scroll view from insetting its content for the safe area.
    ///
    /// The page is drawn edge-to-edge with the tab strip and toolbar floating
    /// over it, so the chrome can show and hide without moving it. But PDFKit's
    /// internal scroll view defaults to adjusting its content inset for the safe
    /// area, and the status bar hides and shows with the chrome — so every
    /// toggle shifted the page (and every canvas on it) up or down by the status
    /// bar's height, dropping letters onto the wrong row. Pinning the inset to
    /// `.never` keeps the page still regardless of the status bar.
    ///
    /// This is device-only: the simulator's status bar does not change the safe
    /// area the same way, which is why screenshots there showed the page holding
    /// position while the classroom iPad did not.
    private func pinScrollContentToSafeArea(in pdfView: PDFView) {
        // PDFKit's document scroll view, not a page's canvas (also a scroll
        // view) — skip those so their own behaviour is untouched.
        func apply(in view: UIView) {
            for subview in view.subviews {
                if subview is PKCanvasView { continue }
                if let scroll = subview as? UIScrollView {
                    scroll.contentInsetAdjustmentBehavior = .never
                }
                apply(in: subview)
            }
        }
        apply(in: pdfView)
    }

    /// Re-enable touch delivery on the views PDFKit parents the overlay under.
    ///
    /// `PDFPageView` ships with `isUserInteractionEnabled = false` — PDFKit
    /// hit-tests at the `PDFView` level and has no need for its page views to
    /// take touches. A disabled view drops touches for its whole subtree, so
    /// an overlay added beneath one is unreachable no matter what it or any
    /// gesture recognizer is configured to do. That is the real reason strokes
    /// never arrived, and it is invisible from the canvas's own state: it is
    /// enabled, sized, visible, and never asked.
    ///
    /// Safe for scrolling: these views carry no recognizers of their own, and
    /// a recognizer on an ancestor still sees touches that land on a
    /// descendant — so PDFKit's pan continues to work for fingers.
    private func enableInteraction(from overlayView: UIView, upTo pdfView: PDFView) {
        var node: UIView? = overlayView
        while let current = node, current !== pdfView {
            if !current.isUserInteractionEnabled { current.isUserInteractionEnabled = true }
            node = current.superview
        }
    }

    /// Decide, by touch *type*, what PDFKit is allowed to react to.
    ///
    /// Stating it this way rather than with gesture failure requirements,
    /// which is what this used to do and what did not work on device: a
    /// failure requirement defers exactly one recognizer, and `PKCanvasView`
    /// is itself a `UIScrollView`, so a search for "the" scroll view could
    /// just as easily defer a canvas's own pan and leave PDFKit's untouched.
    ///
    /// Applied to **every** recognizer PDFKit owns, not only the scroll pan.
    /// Deferring the pan alone stopped the page moving but the Pencil still
    /// drew nothing, because PDFKit's other recognizers — text selection is
    /// the obvious one — went on claiming the touch and cancelling it before
    /// it reached the canvas. A recognizer that never sees a Pencil touch
    /// cannot swallow it.
    ///
    /// Canvases are skipped entirely: their own recognizers are the ones that
    /// must keep working.
    private func applyTouchRouting() {
        guard let pdfView else { return }

        // A finger and a trackpad always drive the PDF; only the Pencil is
        // switched between marking and driving.
        var pdfTouchTypes: [UITouch.TouchType] = [.direct, .indirectPointer]
        if !isDrawingEnabled { pdfTouchTypes.append(.pencil) }
        let allowed = pdfTouchTypes.map { NSNumber(value: $0.rawValue) }

        let recognizers = Self.recognizers(in: pdfView)
        for recognizer in recognizers {
            if recognizer is UILongPressGestureRecognizer {
                // PDFKit's own text-selection recognizer. The app does its own
                // highlighting through copy mode and never wants the native
                // blue selection or the system edit menu it raises ("Select
                // All / Insert Space", the Pencil-Scribble items) — so starve
                // it of every input type rather than hand it the Pencil.
                recognizer.allowedTouchTypes = []
            } else {
                recognizer.allowedTouchTypes = allowed
            }
        }

        diagnostics?.recordCoalesced(
            "routing — marking \(isDrawingEnabled ? "on" : "off"), \(recognizers.count) PDF recognizers restricted"
        )
    }

    /// Every gesture recognizer in the PDF's hierarchy, skipping the subtrees
    /// rooted at a canvas.
    private static func recognizers(in view: UIView) -> [UIGestureRecognizer] {
        if view is PKCanvasView { return [] }
        var found = view.gestureRecognizers ?? []
        for subview in view.subviews {
            found.append(contentsOf: recognizers(in: subview))
        }
        return found
    }

    /// Describe where a canvas actually sits, for diagnosing "the Pencil does
    /// nothing" on a device, which no simulator test can reach.
    #if DEBUG
    private func logCanvasPlacement(_ canvas: PKCanvasView) {
        var ancestry: [String] = []
        var blocked: String?
        var node: UIView? = canvas
        while let current = node {
            ancestry.append(String(describing: type(of: current)))
            if !current.isUserInteractionEnabled, blocked == nil {
                blocked = String(describing: type(of: current))
            }
            node = current.superview
        }

        // Report only the broken case. PDFKit re-attaches a page's overlay
        // every time it recycles during scroll and zoom, so logging each healthy
        // attachment floods the panel and Console — dozens of identical "canvas
        // attached" lines while pinching — and buries the touch and stroke lines
        // that actually matter. A healthy canvas is confirmed by those instead.
        guard let blocked else { return }

        let message = """
            canvas placement: page \(canvas.tag) BLOCKED BY \(blocked) \
            policy=\(canvas.drawingPolicy.rawValue) \
            enabled=\(canvas.isUserInteractionEnabled) \
            frame=\(canvas.frame) \
            hidden=\(canvas.isHidden) alpha=\(canvas.alpha) \
            ancestry=\(ancestry.joined(separator: " < "))
            """

        Self.logger.debug("\(message, privacy: .public)")
        diagnostics?.recordCoalesced(message)
    }
    #endif

    func pdfView(_ pdfView: PDFView, willEndDisplayingOverlayView overlayView: UIView, for page: PDFPage) {
        guard let canvas = overlayView as? PKCanvasView else { return }
        let index = canvas.tag

        // Persist only a canvas we still own for this page. On a tab switch
        // `reset()` clears the live canvases and `drawings` is swapped to the new
        // tab *before* the old document's overlays are torn down — so writing an
        // ending overlay's ink here would land it in the new tab's drawing set,
        // smearing one lesson's marks onto another (and onto its saved sidecar).
        // The previous document's strokes are already saved continuously by
        // `canvasViewDrawingDidChange`, so skipping a canvas we no longer track
        // loses nothing.
        guard liveCanvases[index] === canvas else { return }

        // Capture before the view goes away: PDFKit recycles overlays as pages
        // leave the viewport, and a stroke made on a page scrolled off screen
        // is otherwise lost.
        drawings?.update(canvas.drawing, forPage: index)
        liveCanvases[index] = nil
    }

    private func makeCanvas(forPage index: Int) -> PageCanvasView {
        let canvas = PageCanvasView()
        canvas.diagnostics = diagnostics
        canvas.router = self
        canvas.tag = index
        canvas.delegate = self
        canvas.drawingPolicy = drawingPolicy
        apply(tool, to: canvas)
        canvas.isUserInteractionEnabled = isDrawingEnabled
        canvas.backgroundColor = .clear
        canvas.isOpaque = false

        // PencilKit lightens ink under a dark interface style so it stays
        // visible on a dark canvas — which is why a black pen drew grey: the
        // app forces dark chrome and the canvas inherited it. But this canvas
        // is over a white PDF page, not over the chrome, so it must be told
        // the surface it is actually marking. Same lesson as the popout's
        // vendored components: match the surface, don't fight the framework.
        canvas.overrideUserInterfaceStyle = .light
        // The canvas must not scroll: PDFKit owns scrolling, and a canvas that
        // scrolls independently detaches the ink from the page under it.
        canvas.isScrollEnabled = false
        canvas.accessibilityIdentifier = "pageCanvas"
        canvas.installSmartHighlightGesture()
        return canvas
    }
}

extension PageCanvasProvider: CopyModeRouter {
    var isCopyModeActive: Bool {
        if case .highlighter = tool { return true }
        return false
    }

    var isEraserActive: Bool { tool == .eraser }

    var isPenActive: Bool {
        if case .pen = tool { return true }
        return false
    }

    /// Enter the smart hold-to-highlight gesture: highlight with the last-used
    /// highlighter tint even though a pen is selected. The canvas has already
    /// stopped inking; `endSmartHighlight` restores pen colouring on release.
    func beginSmartHighlight() {
        smartHighlightColor = lastHighlighterColor
    }

    func endSmartHighlight() {
        smartHighlightColor = nil
    }

    func eraseHighlight(at viewPoint: CGPoint) -> Bool {
        guard let pdfView, let page = pdfView.page(for: viewPoint, nearest: true),
              let index = pdfView.document?.index(for: page) else { return false }
        let pagePoint = pdfView.convert(viewPoint, to: page)

        guard drawings?.removeHighlight(atPage: index, containing: pagePoint) == true else { return false }
        renderHighlights(onPage: index)
        lastEditedPage = index
        return true
    }

    /// Render page `index`'s committed highlights — plus, mid-drag, the one
    /// growing under the Pencil — as a single merged layer per colour, so
    /// overlapping or re-marked spans stay one level of colour instead of
    /// multiplying into a darker band.
    ///
    /// The fresh annotations are added *before* the previous ones are removed,
    /// so the page never flashes empty for a frame. Only this app's own
    /// highlight annotations are swept; any the lesson shipped with — Contract
    /// 5's `lesson-block:` links included — are left untouched.
    private func renderHighlights(onPage index: Int, live: TextHighlight? = nil) {
        guard let page = pdfView?.document?.page(at: index) else { return }
        let committed = drawings?.highlights(forPage: index) ?? []
        let merged = HighlightFactory.mergedAnnotations(for: committed + (live.map { [$0] } ?? []))

        for annotation in merged { page.addAnnotation(annotation) }

        let fresh = Set(merged.map(ObjectIdentifier.init))
        for annotation in page.annotations
        where annotation.userName == HighlightFactory.ownerTag && !fresh.contains(ObjectIdentifier(annotation)) {
            page.removeAnnotation(annotation)
        }
    }

    /// Whether a character sits under a point given in PDF-view space.
    ///
    /// Conversion goes through `PDFView`, which owns the mapping from its own
    /// coordinates to a page's — UIKit is top-left, PDF space is bottom-left,
    /// and letting PDFKit bridge the two is what keeps the hit-test landing
    /// where the finger actually is.
    func initialSelection(at viewPoint: CGPoint) -> PDFSelection? {
        guard let pdfView, let page = pdfView.page(for: viewPoint, nearest: true) else { return nil }
        let pagePoint = pdfView.convert(viewPoint, to: page)

        // `characterIndex(at:)` does NOT return -1 for a point off every glyph
        // — it returns the *nearest* character, so it reports "on text"
        // everywhere, including the margins. That would route every copy-mode
        // touch to highlighting and make inking impossible. The real test is
        // whether that character's bounds actually contain the point.
        let index = page.characterIndex(at: pagePoint)
        guard index >= 0 else { return nil }

        let bounds = page.characterBounds(at: index)
        // A small inset of slack, so a touch just above or below a glyph still
        // counts as "on the line" — matching the feel of dragging a highlight
        // along text rather than needing to be dead-centre on the glyph.
        guard bounds.insetBy(dx: -2, dy: -2).contains(pagePoint) else { return nil }

        // Select that one character, so the drag has visible feedback from the
        // very first frame rather than only on release.
        return page.selection(for: NSRange(location: index, length: 1))
    }

    func selection(from: CGPoint, to: CGPoint) -> PDFSelection? {
        guard let pdfView,
              let fromPage = pdfView.page(for: from, nearest: true),
              let toPage = pdfView.page(for: to, nearest: true) else { return nil }
        return pdfView.document?.selection(
            from: fromPage, at: pdfView.convert(from, to: fromPage),
            to: toPage, at: pdfView.convert(to, to: toPage)
        )
    }

    func showLiveSelection(_ selection: PDFSelection?) {
        // Draw the live highlight in the tool's colour — the actual highlight
        // growing under the Pencil, so you can see the text you have grabbed.
        // Rendered together with the page's committed highlights, so dragging
        // back over already-marked text shows one level, not a darker overlap.
        guard let selection, !(selection.string ?? "").isEmpty,
              let color = activeHighlightColor,
              let page = selection.pages.first,
              let index = pdfView?.document?.index(for: page),
              let highlight = HighlightFactory.make(from: selection, on: page, color: color)
        else {
            clearLiveSelection()
            return
        }

        liveHighlightPage = index
        renderHighlights(onPage: index, live: highlight)
    }

    func clearLiveSelection() {
        guard let index = liveHighlightPage else { return }
        liveHighlightPage = nil
        // Drop the live overlay and leave only the committed highlights.
        renderHighlights(onPage: index)
    }

    func commitHighlight(_ selection: PDFSelection, onPage index: Int) {
        guard let page = pdfView?.document?.page(at: index),
              let color = activeHighlightColor,
              let highlight = HighlightFactory.make(from: selection, on: page, color: color)
        else { return }

        // Replace any *different*-colour highlight this one lands on, so marking
        // an orange span blue swaps the colour instead of layering a second
        // wash over it. Same-colour overlaps are left to merge in rendering.
        let replaced = (drawings?.highlights(forPage: index) ?? [])
            .filter { $0.color != color && $0.overlaps(highlight) }
        applyHighlightEdit(add: [highlight], remove: replaced, onPage: index)
        lastEditedPage = index
    }

    /// Apply a highlight change — remove some, add some — as one undoable step,
    /// registering the exact inverse so a single undo restores what was there.
    ///
    /// Registered on the committing canvas's undo manager, the same one
    /// PencilKit uses for ink, so the single undo button steps back through ink
    /// and highlights together in the order they were made.
    private func applyHighlightEdit(add: [TextHighlight], remove: [TextHighlight], onPage index: Int) {
        for highlight in remove { drawings?.removeHighlight(id: highlight.id, fromPage: index) }
        for highlight in add { drawings?.addHighlight(highlight, toPage: index) }
        renderHighlights(onPage: index)
        liveCanvases[index]?.undoManager?.registerUndo(withTarget: self) { provider in
            provider.applyHighlightEdit(add: remove, remove: add, onPage: index)
        }
    }

    private func highlightExists(at viewPoint: CGPoint) -> Bool {
        guard let pdfView, let page = pdfView.page(for: viewPoint, nearest: true),
              let index = pdfView.document?.index(for: page) else { return false }
        let pagePoint = pdfView.convert(viewPoint, to: page)
        return drawings?.highlights(forPage: index).contains { $0.contains(pagePoint) } ?? false
    }

    func canTapHighlight(at viewPoint: CGPoint) -> Bool {
        highlightExists(at: viewPoint) || initialSelection(at: viewPoint) != nil
    }

    func startOrRotateHighlight(at viewPoint: CGPoint) -> Bool {
        // On an existing highlight → rotate its colour.
        if rotateHighlightColor(at: viewPoint) { return true }

        // Otherwise, if the tap landed on a character, start a highlight on it in
        // the first tint — the beginning of the rotation.
        guard let pdfView, let page = pdfView.page(for: viewPoint, nearest: true),
              let index = pdfView.document?.index(for: page),
              let selection = initialSelection(at: viewPoint),
              let highlight = HighlightFactory.make(from: selection, on: page, color: PenColor.highlighterCases[0])
        else { return false }
        applyHighlightEdit(add: [highlight], remove: [], onPage: index)
        lastEditedPage = index
        return true
    }

    func rotateHighlightColor(at viewPoint: CGPoint) -> Bool {
        guard let pdfView, let page = pdfView.page(for: viewPoint, nearest: true),
              let index = pdfView.document?.index(for: page) else { return false }
        let pagePoint = pdfView.convert(viewPoint, to: page)
        guard let target = drawings?.highlights(forPage: index).first(where: { $0.contains(pagePoint) }) else {
            return false
        }
        recolorHighlight(id: target.id, onPage: index, to: PenColor.nextHighlighter(after: target.color))
        lastEditedPage = index
        return true
    }

    /// Recolour one highlight and register the inverse, so a tap-to-rotate steps
    /// back a colour at a time on undo — and never touches the tool's own colour.
    private func recolorHighlight(id: TextHighlight.ID, onPage index: Int, to color: PenColor) {
        guard let current = drawings?.highlights(forPage: index).first(where: { $0.id == id }) else { return }
        let previous = current.color
        drawings?.setHighlightColor(id: id, onPage: index, to: color)
        renderHighlights(onPage: index)
        liveCanvases[index]?.undoManager?.registerUndo(withTarget: self) { provider in
            provider.recolorHighlight(id: id, onPage: index, to: previous)
        }
    }

    /// Restore a document's saved highlights as annotations when it loads.
    func applyStoredHighlights() {
        guard let drawings else { return }
        for index in drawings.highlights.keys {
            renderHighlights(onPage: index)
        }
    }
}

extension PageCanvasProvider: PKCanvasViewDelegate {
    func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
        let index = canvasView.tag
        drawings?.update(canvasView.drawing, forPage: index)
        if !canvasView.drawing.strokes.isEmpty { lastEditedPage = index }
        if !canvasView.drawing.strokes.isEmpty {
            diagnostics?.record("drawing changed — page \(index), \(canvasView.drawing.strokes.count) stroke(s)")
        }
    }
}
