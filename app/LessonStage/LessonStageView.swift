import SwiftUI
import UniformTypeIdentifiers

/// The shell: a tab strip above the reading area, with an optional thumbnail
/// sidebar and a presentation mode that strips both away.
struct LessonStageView: View {
    @Environment(LessonSession.self) private var session
    @Environment(LibraryManager.self) private var library

    // `-popout` opens the sheet straight from launch, so the popout can be
    // driven from a script without a tap. Also the hook UI tests will want.
    @State private var showPopout = ProcessInfo.processInfo.arguments.contains("-popout")
    @State private var isImporting = false
    @State private var showGrid = false
    @State private var showSettings = false
    @State private var showLibrary = false
    @State private var pdfHost = PDFViewHost()

    // Auto-hide chrome. The tab strip and controls fade out after a few idle
    // seconds so the projector shows a clean page; a finger tap on the page
    // brings them back. A Pencil stroke goes to the canvas, not this gesture,
    // so annotating never reveals the chrome — students see a clean,
    // live-annotated page, which is the point.
    @State private var chromeVisible = true
    @State private var hideTask: Task<Void, Never>?

    /// How long the chrome lingers after the last reveal. Short under a test
    /// flag so the behaviour can be exercised without a real wait.
    private var chromeIdleHide: Duration {
        // 4s under the test flag: long enough that a test can reveal the chrome,
        // find a control, and tap it before the idle fade races in — but short
        // enough to keep the auto-hide test quick.
        ProcessInfo.processInfo.arguments.contains("-fastChrome") ? .seconds(4) : .seconds(5)
    }

    /// Tests that aren't about chrome pin it open, so nothing — idle fade or an
    /// explicit dismiss — can pull a tab or tool out from under an assertion.
    private var chromeFrozen: Bool {
        ProcessInfo.processInfo.arguments.contains("-noAutoHide")
    }

    /// Chrome is shown only when revealed and not in the explicit presentation
    /// mode. When hidden either way, the page goes edge-to-edge with the status
    /// bar tucked away — the same clean look on the projector.
    private var showChrome: Bool { chromeVisible && !session.isPresenting }

    private func scheduleChromeHide(after delay: Duration? = nil) {
        hideTask?.cancel()
        // Nothing to clean up with no lesson open — the empty state keeps its
        // buttons.
        guard session.selectedTab != nil, !chromeFrozen else { return }
        let delay = delay ?? chromeIdleHide
        hideTask = Task { @MainActor in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.35)) { chromeVisible = false }
        }
    }

    private func revealChrome() {
        withAnimation(.easeInOut(duration: 0.2)) { chromeVisible = true }
        scheduleChromeHide()
    }

    /// Dismiss the chrome now — a finger tap on the page while it's up, or
    /// picking a tool. Immediate, not the idle spell: the teacher chose a tool,
    /// so the toolbar should get out of the way at once.
    private func hideChrome() {
        guard !chromeFrozen else { return }
        hideTask?.cancel()
        withAnimation(.easeInOut(duration: 0.25)) { chromeVisible = false }
    }

    /// A finger tap on the page toggles the chrome: bring it up when it's down,
    /// dismiss it when it's up. A Pencil stroke goes to the canvas, not here, so
    /// annotating never disturbs it.
    private func toggleChrome() {
        if showChrome { hideChrome() } else { revealChrome() }
    }

    /// Resolve a tapped lesson block to its body and deal, hand it to the
    /// popout, and present. A block that doesn't resolve (no payload, unknown
    /// index) is left alone — suppress the target rather than open an empty
    /// popout.
    private func openPopout(forBlock index: Int, in tab: LessonTab) {
        guard let resolved = tab.payload?.resolve(index: index) else { return }
        PopoutWebViewHost.shared.show(resolved.message)
        showPopout = true
    }

    /// Hand the canvases somewhere to report input problems. Debug builds
    /// only; in a shipping build nothing is listening.
    private func attachDiagnostics() {
        #if DEBUG
        pdfHost.canvases.diagnostics = session.diagnostics
        #endif
    }

    var body: some View {
        readingArea
            // Dark surround: the projector shows this behind every page.
            .background(Color.presentationSurround)
            // The tab strip floats over the top rather than sitting in a stack
            // that pushes the page down — so the page, and anything being
            // written on it, holds still as the chrome shows and hides. (The
            // toolbar already floats at the bottom the same way.)
            .overlay(alignment: .top) {
                if showChrome {
                    VStack(spacing: 0) {
                        TabStrip(
                            openGrid: { showGrid = true },
                            openDocuments: { isImporting = true },
                            openLibrary: { showLibrary = true },
                            openSettings: { showSettings = true }
                        )
                        Divider()
                    }
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .overlay(alignment: .topTrailing) { presentationExit }
            .statusBarHidden(!showChrome)
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: [.pdf],
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls):
                session.open(urls: urls)
                revealChrome()
            case .failure: break // Cancelling is a `.failure`; nothing to report.
            }
        }
        .sheet(isPresented: $showPopout) { PopoutSheet() }
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .environment(library)
                .preferredColorScheme(.dark)
        }
        .sheet(isPresented: $showLibrary) {
            LibraryDayListView()
                .environment(library)
                .environment(session)
                .preferredColorScheme(.dark)
        }
        // Full screen, not a sheet: a sheet on iPad is a centred card only wide
        // enough for two columns, wasting the landscape width the grid wants.
        .fullScreenCover(isPresented: $showGrid) {
            LessonGridView(openDocuments: { isImporting = true })
                .environment(session)
        }
        .onAppear {
            attachDiagnostics()
            pdfHost.pencilToggle.onTap = { session.toggleEraser() }
        }
        // `initial: true` starts the idle countdown once the first lesson is
        // open, regardless of whether that happened before or after this view
        // appeared — the fixture opens in the app's launch task, which races
        // `onAppear`. Switching tabs later reveals and restarts it.
        .onChange(of: session.selectedTabID, initial: true) { _, _ in revealChrome() }
        // Keep the canvases' tool in sync with the session, so a Pencil
        // double-tap that changes the tool reaches the pages too. Dismissing
        // the chrome on a tool pick is the palette's job (its onSelect), so a
        // Pencil double-tap — which isn't a menu selection — leaves it be.
        .onChange(of: session.tool) { _, _ in
            pdfHost.canvases.tool = session.tool
        }
        #if DEBUG
        // Toggle the Contract 5 x-ray overlay live on the current document.
        .onChange(of: session.showsBlockXray) { _, on in
            if let document = session.selectedTab?.document {
                LessonBlockXray.apply(on, to: document)
            }
        }
        #endif
    }

    @ViewBuilder
    private var readingArea: some View {
        #if DEBUG
        if session.showsDiagnostics {
            DiagnosticsView(diagnostics: session.diagnostics)
        } else {
            documentArea
        }
        #else
        documentArea
        #endif
    }

    @ViewBuilder
    private var documentArea: some View {
        if let tab = session.selectedTab {
            HStack(spacing: 0) {
                if session.showsThumbnails && showChrome {
                    ThumbnailSidebar(host: pdfHost)
                        .frame(width: 132)
                        .transition(.move(edge: .leading))
                    Divider()
                }

                ZStack(alignment: .bottom) {
                    PDFDocumentView(
                        host: pdfHost,
                        tab: tab,
                        onPageChange: { pageIndex in session.recordPage(pageIndex, for: tab.id) },
                        onBlockTap: { index in openPopout(forBlock: index, in: tab) },
                        // A finger tap toggles the chrome (Pencil taps are
                        // excluded inside the view, so an eraser tap can't).
                        onFingerTap: { toggleChrome() }
                    )
                    // Always edge-to-edge, so its frame never changes with the
                    // chrome. The floating tab strip and toolbar cover its top
                    // and bottom edges while shown; the page itself never moves.
                    .ignoresSafeArea()

                    if let failure = tab.loadFailure {
                        Text(failure)
                            .font(.callout)
                            .padding()
                            .background(.thinMaterial, in: .rect(cornerRadius: 10))
                            .padding()
                    } else if tab.document == nil {
                        // The parse runs off-main; for an iCloud handout it waits
                        // on a download. Show progress rather than a black page.
                        VStack(spacing: 12) {
                            ProgressView()
                            Text("Loading \(tab.title)…")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .accessibilityIdentifier("loadingIndicator")
                    }

                    if tab.loadFailure == nil, showChrome {
                        VStack(spacing: 10) {
                            DrawingPalette(host: pdfHost, drawings: tab.drawings, onSelect: hideChrome)
                            ReadingControls(tab: tab)
                        }
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
            }
            // A tab that was restored but never shown has no document yet.
            .task(id: tab.id) {
                let document = await tab.loaded()
                #if DEBUG
                // Honour the x-ray toggle whenever a document finishes loading,
                // so switching to a new tab re-applies (or clears) the overlay.
                if let document { LessonBlockXray.apply(session.showsBlockXray, to: document) }
                // `-tapBlock <index>` drives the whole tap→resolve→popout seam
                // without a physical tap, for a screenshot or a scripted demo.
                if document != nil,
                   let flag = ProcessInfo.processInfo.arguments.firstIndex(of: "-tapBlock"),
                   let index = ProcessInfo.processInfo.arguments[safe: flag + 1].flatMap(Int.init) {
                    openPopout(forBlock: index, in: tab)
                }
                #endif
            }
        } else {
            EmptyStateView(
                openDocuments: { isImporting = true },
                openPopout: { showPopout = true }
            )
        }
    }

    @ViewBuilder
    private var presentationExit: some View {
        if session.isPresenting {
            Button {
                withAnimation(.snappy) { session.isPresenting = false }
            } label: {
                Image(systemName: "arrow.down.right.and.arrow.up.left")
                    .padding(10)
                    .background(.ultraThinMaterial, in: .circle)
            }
            .padding()
            .accessibilityLabel("Exit presentation mode")
        }
    }
}

/// The floating page/zoom bar. Hidden in presentation mode, where the class
/// should see the lesson and nothing else.
private struct ReadingControls: View {
    @Environment(LessonSession.self) private var session
    let tab: LessonTab

    var body: some View {
        HStack(spacing: 16) {
            Button {
                withAnimation(.snappy) { session.showsThumbnails.toggle() }
            } label: {
                Image(systemName: session.showsThumbnails ? "sidebar.left" : "sidebar.squares.left")
            }
            .accessibilityLabel("Toggle page thumbnails")

            if tab.pageCount > 0 {
                Text("Page \(tab.pageIndex + 1) of \(tab.pageCount)")
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("pageIndicator")
            }

            Button {
                withAnimation(.snappy) { session.isPresenting = true }
            } label: {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
            }
            .accessibilityLabel("Enter presentation mode")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.thinMaterial, in: .capsule)
        .padding(.bottom, 16)
    }
}

private struct EmptyStateView: View {
    let openDocuments: () -> Void
    let openPopout: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.text")
                .font(.system(size: 44, weight: .light))
            Text("No lessons open")
                .font(.title3)
            Text("Open a lesson PDF to begin.")
                .font(.callout)
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                Button("Open lessons…", action: openDocuments)
                    .buttonStyle(.borderedProminent)

                // Spike affordance: Phase 3 opens this from a `lesson-block:`
                // tap on the page, not from a button.
                Button("Bridge popout", action: openPopout)
            }
            .padding(.top, 8)
        }
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct PopoutSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            PopoutWebView()
                .ignoresSafeArea(edges: .bottom)
                .navigationTitle("Bridge popout")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
        }
    }
}

#Preview {
    LessonStageView()
        .environment(LessonSession())
        .environment(LibraryManager())
        .preferredColorScheme(.dark)
}
