import PDFKit
import SwiftUI
import os

/// Owns the single `PDFView` the reader and the thumbnail strip share.
///
/// One view reused across tabs rather than one per tab: eight open lessons
/// means eight rendered documents, and the plan already flags a performance
/// pass at that size. The cost of reuse is having to restore each tab's page
/// on every switch, which `PDFDocumentView` does.
///
/// `PDFThumbnailView` is driven by a `PDFView` instance, not by a document,
/// so the sidebar needs this same object — which is why it lives here rather
/// than inside the representable.
@MainActor
final class PDFViewHost {
    let pdfView: PDFView

    /// Supplies the per-page PencilKit canvases. Held here because it must
    /// outlive any single `updateUIView`, and because the toolbar drives it.
    let canvases = PageCanvasProvider()

    /// Receives the Apple Pencil double-tap. Its `onTap` is wired to the
    /// session's eraser toggle once the view is up.
    let pencilToggle = PencilToggleController()

    init() {
        let view = PDFView()

        // Continuous vertical scroll: a lesson is read as a strip, not paged
        // through like a book.
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.autoScales = true
        view.pageShadowsEnabled = true

        // The surround the page floats in — dark, so a projector doesn't wash
        // the page out with a bright frame around it.
        view.backgroundColor = UIColor(Color.presentationSurround)
        view.accessibilityIdentifier = "pdfView"

        self.pdfView = view
        // `pageOverlayViewProvider` is a weak property, so the provider must be
        // owned here — a locally-created one is released before PDFKit asks
        // it for anything.
        view.pageOverlayViewProvider = canvases

        // The Apple Pencil double-tap. The interaction is not location-based —
        // the tap is on the pencil itself — so any view in the hierarchy will
        // receive it; the reading surface is the natural home.
        let pencilInteraction = UIPencilInteraction()
        pencilInteraction.delegate = pencilToggle
        view.addInteraction(pencilInteraction)

        #if DEBUG
        // The simulator has no Pencil, so `.pencilOnly` would make every
        // drawing path untestable. This is the only way a stroke gets
        // exercised outside a physical iPad.
        if ProcessInfo.processInfo.arguments.contains("-fingerDrawing") {
            canvases.drawingPolicy = .anyInput
        }
        #endif
    }
}

/// The reading surface for one tab.
///
/// PDFView is UIKit and has no SwiftUI equivalent — this is the wrap-once
/// boundary the plan calls for. Everything outside it stays SwiftUI.
struct PDFDocumentView: UIViewRepresentable {
    let host: PDFViewHost
    let tab: LessonTab
    /// Reports the page the reader is actually on, for session restore.
    var onPageChange: (Int) -> Void

    func makeUIView(context: Context) -> PDFView {
        context.coordinator.observe(host.pdfView)
        return host.pdfView
    }

    func updateUIView(_ view: PDFView, context: Context) {
        context.coordinator.onPageChange = onPageChange

        // Swapping tabs reuses this view, so the document may be new. Compare
        // by tab rather than by document: two tabs could be the same file, and
        // a tab whose document failed to load has none to compare.
        guard context.coordinator.currentTabID != tab.id || view.document !== tab.document else {
            return
        }
        context.coordinator.currentTabID = tab.id

        // Point the canvases at this document's annotations before the pages
        // lay out, or the first overlays attach to the previous tab's set.
        host.canvases.reset()
        host.canvases.drawings = tab.drawings

        // Recording is suppressed from here until the restore has settled.
        // Setting a document makes PDFKit lay out from page 1 and report that
        // as a page change; recorded, it overwrites the very position being
        // restored — the restore then "works" and is immediately undone.
        context.coordinator.beginRestoring()
        view.document = tab.document

        // A document set this frame has no layout yet, and both of the things
        // that follow need one:
        //   - the fit scale, which `autoScales` computes from the view bounds.
        //     Assigned against zero bounds it yields a scale that renders
        //     nothing at all — a blank surround with a correct page count.
        //   - `go(to:)`, which silently does nothing before layout.
        let coordinator = context.coordinator
        let pageIndex = tab.pageIndex
        let canvases = host.canvases
        Task { @MainActor in
            view.layoutIfNeeded()
            view.autoScales = true
            coordinator.restore(pageIndex: pageIndex, in: view)
            // Draw the saved highlights back onto the pages. Deferred with the
            // rest until layout, since it addresses pages by index.
            canvases.applyStoredHighlights()
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onPageChange: onPageChange)
    }

    @MainActor
    final class Coordinator {
        static let logger = Logger(subsystem: "com.popperbiz.LessonStage", category: "pdf")

        var onPageChange: (Int) -> Void
        var currentTabID: LessonTab.ID?
        private var isRestoring = false
        private var observer: (any NSObjectProtocol)?

        init(onPageChange: @escaping (Int) -> Void) {
            self.onPageChange = onPageChange
        }

        func observe(_ view: PDFView) {
            guard observer == nil else { return }
            observer = NotificationCenter.default.addObserver(
                forName: .PDFViewPageChanged,
                object: view,
                queue: .main
            ) { [weak self] note in
                MainActor.assumeIsolated {
                    self?.pageChanged(note)
                }
            }
        }

        func beginRestoring() { isRestoring = true }

        func restore(pageIndex: Int, in view: PDFView, attempt: Int = 0) {
            guard let document = view.document else {
                isRestoring = false
                return
            }
            guard pageIndex > 0,
                  pageIndex < document.pageCount,
                  let page = document.page(at: pageIndex) else {
                isRestoring = false
                return
            }

            // In `.singlePageContinuous`, `go(to:)` scrolls the strip — but it
            // is a no-op while the scroll view is still sizing its content, and
            // it reports no failure when it does nothing. So: apply, read back,
            // and retry a bounded number of times before giving up.
            view.go(to: page)

            let landed = view.currentPage.map { document.index(for: $0) }
            if landed == pageIndex || attempt >= 4 {
                if landed != pageIndex {
                    Self.logger.warning(
                        "Page restore gave up: wanted \(pageIndex), landed on \(landed ?? -1)"
                    )
                }
                // Only now may the reader's own scrolling be recorded again.
                isRestoring = false
                return
            }

            Task { @MainActor in
                self.restore(pageIndex: pageIndex, in: view, attempt: attempt + 1)
            }
        }

        private func pageChanged(_ note: Notification) {
            guard !isRestoring,
                  let view = note.object as? PDFView,
                  let current = view.currentPage,
                  let index = view.document?.index(for: current) else { return }
            onPageChange(index)
        }

        deinit {
            if let observer { NotificationCenter.default.removeObserver(observer) }
        }
    }
}
