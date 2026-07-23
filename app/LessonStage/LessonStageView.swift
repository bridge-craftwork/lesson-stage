import SwiftUI

/// The shell: a tab strip above the presentation area.
///
/// Phase 0 exit criterion is this view, empty, on the iPad. The presentation
/// area becomes a `PDFView` per tab in Phase 1.
struct LessonStageView: View {
    @Environment(LessonSession.self) private var session
    // `-popout` opens the sheet straight from launch, so the popout can be
    // driven from a script without a tap. Also the hook UI tests will want.
    @State private var showPopout = ProcessInfo.processInfo.arguments.contains("-popout")

    var body: some View {
        VStack(spacing: 0) {
            TabStrip()
            Divider()
            presentationArea
        }
        // Dark surround: the projector shows this behind every page.
        .background(Color.presentationSurround)
        .sheet(isPresented: $showPopout) {
            PopoutSheet()
        }
    }

    @ViewBuilder
    private var presentationArea: some View {
        if session.selectedTab == nil {
            EmptyStateView(openPopout: { showPopout = true })
        } else {
            // Phase 1: PDFView per tab.
            Color.presentationSurround
        }
    }
}

private struct EmptyStateView: View {
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

            // Spike affordance: Phase 3 opens this from a `lesson-block:` tap
            // on the page, not from a button.
            Button("Bridge popout", action: openPopout)
                .buttonStyle(.borderedProminent)
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
