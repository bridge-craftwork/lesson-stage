import SwiftUI
import UniformTypeIdentifiers

/// The strip of open lessons. Sized for six to eight tabs — the working set
/// for a class — so tabs stay readable rather than collapsing to slivers.
struct TabStrip: View {
    @Environment(LessonSession.self) private var session
    let openDocuments: () -> Void

    @State private var draggingID: LessonTab.ID?

    var body: some View {
        HStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 1) {
                    ForEach(session.tabs) { tab in
                        TabButton(
                            tab: tab,
                            isSelected: tab.id == session.selectedTabID,
                            select: { session.selectedTabID = tab.id },
                            close: { session.close(tab.id) }
                        )
                        .onDrag {
                            draggingID = tab.id
                            // The provider is required; the reorder is driven
                            // by the drop target, not by what's carried.
                            return NSItemProvider(object: tab.id.uuidString as NSString)
                        }
                        .onDrop(
                            of: [UTType.text],
                            delegate: TabDropDelegate(
                                targetID: tab.id,
                                draggingID: $draggingID,
                                session: session
                            )
                        )
                    }
                    Spacer(minLength: 0)
                }
            }

            Divider()

            Button(action: openDocuments) {
                Image(systemName: "plus")
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Open lessons")
        }
        .frame(height: 44)
        // Opaque, not `.bar`: a glass/material strip samples the content
        // behind the window and ghosts the floating reading controls into the
        // tab row. An opaque strip also keeps tab titles legible over a white
        // page, which is what is actually behind it.
        .background(Color.tabStripSurface)
    }
}

private struct TabDropDelegate: DropDelegate {
    let targetID: LessonTab.ID
    @Binding var draggingID: LessonTab.ID?
    let session: LessonSession

    func dropEntered(info: DropInfo) {
        guard let draggingID, draggingID != targetID else { return }
        withAnimation(.snappy(duration: 0.18)) {
            session.move(id: draggingID, before: targetID)
        }
    }

    func performDrop(info: DropInfo) -> Bool {
        draggingID = nil
        return true
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }
}

private struct TabButton: View {
    let tab: LessonTab
    let isSelected: Bool
    let select: () -> Void
    let close: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Text(tab.title)
                .lineLimit(1)
                .font(.subheadline)
                .foregroundStyle(isSelected ? .primary : .secondary)

            Button(action: close) {
                Image(systemName: "xmark")
                    .font(.caption2.weight(.semibold))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close \(tab.title)")
        }
        .padding(.horizontal, 12)
        .frame(maxHeight: .infinity)
        .frame(minWidth: 120, maxWidth: 220)
        .background(isSelected ? Color.selectedTab : Color.clear)
        .contentShape(.rect)
        .onTapGesture(perform: select)
    }
}

#Preview {
    TabStrip(openDocuments: {})
        .environment(LessonSession.preview)
        .preferredColorScheme(.dark)
}
