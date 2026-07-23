import SwiftUI
import UniformTypeIdentifiers

/// The shell: a tab strip above the reading area, with an optional thumbnail
/// sidebar and a presentation mode that strips both away.
struct LessonStageView: View {
    @Environment(LessonSession.self) private var session

    // `-popout` opens the sheet straight from launch, so the popout can be
    // driven from a script without a tap. Also the hook UI tests will want.
    @State private var showPopout = ProcessInfo.processInfo.arguments.contains("-popout")
    @State private var isImporting = false
    @State private var showGrid = false
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
        // 2.5s under the test flag: long enough for XCUITest to observe the
        // revealed state before it fades, short enough to keep the test quick.
        ProcessInfo.processInfo.arguments.contains("-fastChrome") ? .milliseconds(2500) : .seconds(5)
    }

    /// The shorter delay after acting on a control — you picked a tool, so the
    /// chrome should get out of the way promptly rather than lingering the full
    /// idle spell.
    private var chromeQuickHide: Duration {
        ProcessInfo.processInfo.arguments.contains("-fastChrome") ? .milliseconds(2500) : .seconds(1.5)
    }

    /// Chrome is shown only when revealed and not in the explicit presentation
    /// mode. When hidden either way, the page goes edge-to-edge with the status
    /// bar tucked away — the same clean look on the projector.
    private var showChrome: Bool { chromeVisible && !session.isPresenting }

    private func scheduleChromeHide(after delay: Duration? = nil) {
        hideTask?.cancel()
        // Nothing to clean up with no lesson open — the empty state keeps its
        // buttons.
        guard session.selectedTab != nil else { return }
        // Tests that aren't about auto-hide pin the chrome open, so an idle
        // fade cannot pull a tab or tool out from under them.
        if ProcessInfo.processInfo.arguments.contains("-noAutoHide") { return }
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

    /// Hand the canvases somewhere to report input problems. Debug builds
    /// only; in a shipping build nothing is listening.
    private func attachDiagnostics() {
        #if DEBUG
        pdfHost.canvases.diagnostics = session.diagnostics
        #endif
    }

    var body: some View {
        VStack(spacing: 0) {
            if showChrome {
                TabStrip(
                    openGrid: { showGrid = true },
                    openDocuments: { isImporting = true }
                )
                .transition(.move(edge: .top).combined(with: .opacity))
                Divider()
            }
            readingArea
        }
        // Dark surround: the projector shows this behind every page.
        .background(Color.presentationSurround)
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
        .sheet(isPresented: $showGrid) {
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
        // Picking a tool means you're about to draw — hide the chrome promptly
        // rather than lingering the full idle spell. Also keep the canvases'
        // tool in sync with the session, so a Pencil double-tap that changes
        // the tool reaches the pages too.
        .onChange(of: session.tool) { _, _ in
            pdfHost.canvases.tool = session.tool
            if showChrome { scheduleChromeHide(after: chromeQuickHide) }
        }
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
                    PDFDocumentView(host: pdfHost, tab: tab) { pageIndex in
                        session.recordPage(pageIndex, for: tab.id)
                    }
                    .ignoresSafeArea(edges: showChrome ? [] : .all)
                    // A finger tap reveals the chrome; runs alongside the PDF's
                    // own scroll/zoom/draw rather than blocking them.
                    .simultaneousGesture(TapGesture().onEnded { revealChrome() })

                    if let failure = tab.loadFailure {
                        Text(failure)
                            .font(.callout)
                            .padding()
                            .background(.thinMaterial, in: .rect(cornerRadius: 10))
                            .padding()
                    } else if showChrome {
                        VStack(spacing: 10) {
                            DrawingPalette(host: pdfHost, drawings: tab.drawings)
                            ReadingControls(tab: tab)
                        }
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
            }
            // A tab that was restored but never shown has no document yet.
            .task(id: tab.id) { tab.load() }
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
        .preferredColorScheme(.dark)
}
