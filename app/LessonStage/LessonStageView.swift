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
    @State private var pdfHost = PDFViewHost()

    var body: some View {
        VStack(spacing: 0) {
            if !session.isPresenting {
                TabStrip(openDocuments: { isImporting = true })
                Divider()
            }
            readingArea
        }
        // Dark surround: the projector shows this behind every page.
        .background(Color.presentationSurround)
        .overlay(alignment: .topTrailing) { presentationExit }
        .statusBarHidden(session.isPresenting)
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: [.pdf],
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls): session.open(urls: urls)
            case .failure: break // Cancelling is a `.failure`; nothing to report.
            }
        }
        .sheet(isPresented: $showPopout) { PopoutSheet() }
    }

    @ViewBuilder
    private var readingArea: some View {
        if let tab = session.selectedTab {
            HStack(spacing: 0) {
                if session.showsThumbnails && !session.isPresenting {
                    ThumbnailSidebar(host: pdfHost)
                        .frame(width: 132)
                        .transition(.move(edge: .leading))
                    Divider()
                }

                ZStack(alignment: .bottom) {
                    PDFDocumentView(host: pdfHost, tab: tab) { pageIndex in
                        session.recordPage(pageIndex, for: tab.id)
                    }
                    .ignoresSafeArea(edges: session.isPresenting ? .all : [])

                    if let failure = tab.loadFailure {
                        Text(failure)
                            .font(.callout)
                            .padding()
                            .background(.thinMaterial, in: .rect(cornerRadius: 10))
                            .padding()
                    } else if !session.isPresenting {
                        VStack(spacing: 10) {
                            DrawingPalette(host: pdfHost, drawings: tab.drawings)
                            ReadingControls(tab: tab)
                        }
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
