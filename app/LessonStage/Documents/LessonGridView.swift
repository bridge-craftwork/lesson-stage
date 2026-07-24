import PDFKit
import SwiftUI

/// A grid of the open lessons, each shown with a page-one thumbnail and its
/// *full* name — the answer to tab titles that truncate long filenames to an
/// unrecognisable snippet. Tap a lesson to open it.
///
/// Today this covers the open documents. When Phase 5 adds a lessons folder,
/// the same grid is the natural place to browse the whole library.
struct LessonGridView: View {
    @Environment(LessonSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    let openDocuments: () -> Void

    // ~240pt cells: about five across in landscape, three or four in portrait,
    // at the size that read well already.
    private let columns = [GridItem(.adaptive(minimum: 240, maximum: 300), spacing: 20)]

    var body: some View {
        NavigationStack {
            Group {
                if session.tabs.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 20) {
                            ForEach(session.tabs) { tab in
                                LessonGridCell(
                                    tab: tab,
                                    isSelected: tab.id == session.selectedTabID,
                                    open: {
                                        session.selectedTabID = tab.id
                                        dismiss()
                                    },
                                    close: { session.close(tab.id) }
                                )
                            }
                        }
                        .padding(20)
                    }
                }
            }
            .navigationTitle("Lessons")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        openDocuments()
                        dismiss()
                    } label: {
                        Label("Open lessons", systemImage: "plus")
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .accessibilityIdentifier("lessonGrid")
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No lessons open", systemImage: "doc.text")
        } description: {
            Text("Open a lesson PDF to begin.")
        } actions: {
            Button("Open lessons…") {
                openDocuments()
                dismiss()
            }
            .buttonStyle(.borderedProminent)
        }
    }
}

private struct LessonGridCell: View {
    let tab: LessonTab
    let isSelected: Bool
    let open: () -> Void
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: open) {
                LessonThumbnail(tab: tab)
                    .frame(maxWidth: .infinity)
                    .frame(height: 220)
                    .background(Color.sidebarSurface)
                    .clipShape(.rect(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 3)
                    )
            }
            .buttonStyle(.plain)
            .overlay(alignment: .topTrailing) { closeButton }

            // The whole point: the full name, wrapped, not a snippet.
            Text(tab.title)
                .font(.callout)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
                .foregroundStyle(isSelected ? .primary : .secondary)

            if tab.pageCount > 0 {
                Text("\(tab.pageCount) pages")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("gridCell-\(tab.title)")
    }

    private var closeButton: some View {
        Button(action: close) {
            Image(systemName: "xmark.circle.fill")
                .symbolRenderingMode(.palette)
                .foregroundStyle(.white, .black.opacity(0.5))
                .font(.title3)
                .padding(6)
        }
        .accessibilityLabel("Close \(tab.title)")
        // Distinct from the tab strip's close button, which shares the label.
        .accessibilityIdentifier("gridClose-\(tab.title)")
    }
}

/// A page-one thumbnail for a lesson, rendered off the main path and cached
/// for the life of the view.
private struct LessonThumbnail: View {
    let tab: LessonTab
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else if tab.loadFailure != nil {
                Image(systemName: "exclamationmark.triangle")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
            } else {
                ProgressView()
            }
        }
        .task(id: tab.id) {
            // Loading is a no-op if already loaded; needed for tabs restored
            // but never shown, whose document is not yet parsed.
            tab.load()
            guard let page = tab.document?.page(at: 0) else { return }
            let size = CGSize(width: 240, height: 240)
            image = page.thumbnail(of: size, for: .cropBox)
        }
    }
}
