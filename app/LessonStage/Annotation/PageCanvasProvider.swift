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
            for canvas in liveCanvases.values { apply(tool, to: canvas) }
        }
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

    /// The highlight annotation shown while a selection is being dragged, and
    /// the page it sits on. Removed and rebuilt on each move; the same colour
    /// as the committed highlight, so what you drag is what you get.
    private var liveAnnotation: PDFAnnotation?
    private weak var livePage: PDFPage?


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
        if let document = pdfView?.document {
            let touched = Set(previous.highlights.keys).union(contents.highlights.keys)
            for index in touched {
                if let page = document.page(at: index) { rerenderHighlights(on: page, index: index) }
            }
        }

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
        applyTouchRouting()

        #if DEBUG
        if let canvas = overlayView as? PKCanvasView { logCanvasPlacement(canvas) }
        #endif
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
            recognizer.allowedTouchTypes = allowed
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

        // The full placement dump only when something is wrong. Emitting it
        // per page buries the touch and stroke lines — which are what you are
        // usually watching — under repetitions of identical, healthy state.
        let message: String
        if let blocked {
            message = """
                canvas placement: page \(canvas.tag) BLOCKED BY \(blocked) \
                policy=\(canvas.drawingPolicy.rawValue) \
                enabled=\(canvas.isUserInteractionEnabled) \
                frame=\(canvas.frame) \
                hidden=\(canvas.isHidden) alpha=\(canvas.alpha) \
                ancestry=\(ancestry.joined(separator: " < "))
                """
        } else {
            message = "canvas attached — page \(canvas.tag), interaction ok, policy=\(canvas.drawingPolicy.rawValue)"
        }

        Self.logger.debug("\(message, privacy: .public)")
        diagnostics?.recordCoalesced(message)
    }
    #endif

    func pdfView(_ pdfView: PDFView, willEndDisplayingOverlayView overlayView: UIView, for page: PDFPage) {
        guard let canvas = overlayView as? PKCanvasView else { return }
        let index = canvas.tag

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
        return canvas
    }
}

extension PageCanvasProvider: CopyModeRouter {
    var isCopyModeActive: Bool {
        if case .highlighter = tool { return true }
        return false
    }

    var isEraserActive: Bool { tool == .eraser }

    func eraseHighlight(at viewPoint: CGPoint) -> Bool {
        guard let pdfView, let page = pdfView.page(for: viewPoint, nearest: true),
              let index = pdfView.document?.index(for: page) else { return false }
        let pagePoint = pdfView.convert(viewPoint, to: page)

        guard drawings?.removeHighlight(atPage: index, containing: pagePoint) == true else { return false }
        rerenderHighlights(on: page, index: index)
        lastEditedPage = index
        return true
    }

    /// Remove only the highlight annotations this app added, leaving any the
    /// lesson shipped with — Contract 5's `lesson-block:` links included.
    private func removeOwnedHighlightAnnotations(from page: PDFPage) {
        for annotation in page.annotations where annotation.userName == HighlightFactory.ownerTag {
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
        guard let selection, !(selection.string ?? "").isEmpty,
              case .highlighter(let color) = tool,
              let page = selection.pages.first,
              let highlight = HighlightFactory.make(from: selection, on: page, color: color)
        else {
            clearLiveSelection()
            return
        }

        // Add the new annotation *before* removing the previous, so the page is
        // never empty for a frame. Remove-then-add can flash: PDFKit may paint
        // the removal and the addition on separate frames, showing a bare gap
        // between. This keeps a highlight on screen throughout.
        let previous = liveAnnotation
        let previousPage = livePage

        let annotation = HighlightFactory.annotation(for: highlight)
        page.addAnnotation(annotation)
        liveAnnotation = annotation
        livePage = page

        if let previous, let previousPage { previousPage.removeAnnotation(previous) }
    }

    func clearLiveSelection() {
        if let liveAnnotation, let livePage { livePage.removeAnnotation(liveAnnotation) }
        liveAnnotation = nil
        livePage = nil
    }

    func commitHighlight(_ selection: PDFSelection, onPage index: Int) {
        guard let page = pdfView?.document?.page(at: index),
              case .highlighter(let color) = tool,
              let highlight = HighlightFactory.make(from: selection, on: page, color: color)
        else { return }
        applyHighlight(highlight, onPage: index)
        lastEditedPage = index
    }

    /// Add a highlight and register its removal as the undo. Paired with
    /// `revertHighlight`, which registers this back as the redo — the standard
    /// symmetric undo pattern.
    ///
    /// Registered on the committing canvas's undo manager, the same one
    /// PencilKit uses for ink, so the single undo button steps back through ink
    /// and highlights together in the order they were made.
    private func applyHighlight(_ highlight: TextHighlight, onPage index: Int) {
        guard let page = pdfView?.document?.page(at: index) else { return }
        drawings?.addHighlight(highlight, toPage: index)
        addAnnotations(for: highlight, to: page)
        liveCanvases[index]?.undoManager?.registerUndo(withTarget: self) { provider in
            provider.revertHighlight(highlight, onPage: index)
        }
    }

    private func revertHighlight(_ highlight: TextHighlight, onPage index: Int) {
        guard let page = pdfView?.document?.page(at: index) else { return }
        drawings?.removeHighlight(id: highlight.id, fromPage: index)
        rerenderHighlights(on: page, index: index)
        liveCanvases[index]?.undoManager?.registerUndo(withTarget: self) { provider in
            provider.applyHighlight(highlight, onPage: index)
        }
    }

    private func addAnnotations(for highlight: TextHighlight, to page: PDFPage) {
        page.addAnnotation(HighlightFactory.annotation(for: highlight))
    }

    /// Redraw a page's highlight annotations from the model — the model is the
    /// source of truth.
    private func rerenderHighlights(on page: PDFPage, index: Int) {
        removeOwnedHighlightAnnotations(from: page)
        for highlight in drawings?.highlights(forPage: index) ?? [] {
            addAnnotations(for: highlight, to: page)
        }
    }

    /// Restore a document's saved highlights as annotations when it loads.
    func applyStoredHighlights() {
        guard let document = pdfView?.document, let drawings else { return }
        for (index, highlights) in drawings.highlights {
            guard let page = document.page(at: index) else { continue }
            for highlight in highlights {
                addAnnotations(for: highlight, to: page)
            }
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
