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
    private var liveCanvases: [Int: PageCanvasView] = [:]

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

        diagnostics?.record(
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

        let message = """
            canvas placement: policy=\(canvas.drawingPolicy.rawValue) \
            enabled=\(canvas.isUserInteractionEnabled) \
            frame=\(canvas.frame) \
            hidden=\(canvas.isHidden) alpha=\(canvas.alpha) \
            interactionBlockedBy=\(blocked ?? "none") \
            ancestry=\(ancestry.joined(separator: " < "))
            """

        Self.logger.debug("\(message, privacy: .public)")
        diagnostics?.record(message)
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
        diagnostics?.record("drawing changed — page \(index), \(canvasView.drawing.strokes.count) stroke(s)")
    }
}
