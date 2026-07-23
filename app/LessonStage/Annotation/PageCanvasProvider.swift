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

    var tool: DrawingTool = .pen(.black) {
        didSet {
            guard tool != oldValue else { return }
            for canvas in liveCanvases.values { canvas.tool = tool.pkTool }
        }
    }

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
    private var liveCanvases: [Int: PKCanvasView] = [:]

    /// The page last drawn on, so undo has something to aim at. Undo is
    /// per-canvas in PencilKit; with a canvas per page there is no single
    /// undo stack to consult.
    private(set) var lastEditedPage: Int?

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
        applyTouchRouting()
    }

    /// Decide, by touch *type*, what scrolls the lesson.
    ///
    /// Stating it this way rather than with gesture failure requirements,
    /// which is what this used to do and what did not work on device. A
    /// failure requirement only defers the one recognizer it is applied to —
    /// finding "the" scroll view in PDFKit's hierarchy is guesswork, and
    /// `PKCanvasView` is itself a `UIScrollView`, so the search could just as
    /// easily have deferred a canvas's own pan and left PDFKit's untouched.
    ///
    /// Restricting allowed touch types is unambiguous: while marking is on,
    /// the PDF scrolls for fingers only, so a Pencil touch has nowhere to go
    /// but the canvas. Turn marking off and the Pencil scrolls again.
    private func applyTouchRouting() {
        guard let pdfView else { return }

        // A finger and a trackpad always scroll; only the Pencil is switched
        // between scrolling and marking.
        var scrollTouchTypes: [UITouch.TouchType] = [.direct, .indirectPointer]
        if !isDrawingEnabled { scrollTouchTypes.append(.pencil) }

        let allowed = scrollTouchTypes.map { NSNumber(value: $0.rawValue) }
        for scrollView in Self.scrollViews(in: pdfView) {
            scrollView.panGestureRecognizer.allowedTouchTypes = allowed
        }
    }

    /// Every scroll view PDFKit uses, excluding the canvases — which are
    /// themselves scroll views, and must keep their own input.
    private static func scrollViews(in view: UIView) -> [UIScrollView] {
        var found: [UIScrollView] = []
        if let scrollView = view as? UIScrollView, !(view is PKCanvasView) {
            found.append(scrollView)
        }
        for subview in view.subviews where !(subview is PKCanvasView) {
            found.append(contentsOf: scrollViews(in: subview))
        }
        return found
    }

    func pdfView(_ pdfView: PDFView, willEndDisplayingOverlayView overlayView: UIView, for page: PDFPage) {
        guard let canvas = overlayView as? PKCanvasView else { return }
        let index = canvas.tag

        // Capture before the view goes away: PDFKit recycles overlays as pages
        // leave the viewport, and a stroke made on a page scrolled off screen
        // is otherwise lost.
        drawings?.update(canvas.drawing, forPage: index)
        liveCanvases[index] = nil
    }

    private func makeCanvas(forPage index: Int) -> PKCanvasView {
        let canvas = PKCanvasView()
        canvas.tag = index
        canvas.delegate = self
        canvas.tool = tool.pkTool
        canvas.drawingPolicy = drawingPolicy
        canvas.isUserInteractionEnabled = isDrawingEnabled
        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        // The canvas must not scroll: PDFKit owns scrolling, and a canvas that
        // scrolls independently detaches the ink from the page under it.
        canvas.isScrollEnabled = false
        canvas.accessibilityIdentifier = "pageCanvas"
        return canvas
    }
}

extension PageCanvasProvider: PKCanvasViewDelegate {
    func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
        let index = canvasView.tag
        drawings?.update(canvasView.drawing, forPage: index)
        if !canvasView.drawing.strokes.isEmpty { lastEditedPage = index }
    }
}
