import SwiftUI

/// The strip of open lessons. Sized for six to eight tabs — the working set
/// for a class — so tabs stay readable rather than collapsing to slivers.
struct TabStrip: View {
    @Environment(LessonSession.self) private var session

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 1) {
                ForEach(session.tabs) { tab in
                    TabButton(
                        tab: tab,
                        isSelected: tab.id == session.selectedTabID,
                        select: { session.selectedTabID = tab.id },
                        close: { session.close(tab.id) }
                    )
                }
                Spacer(minLength: 0)
            }
        }
        .frame(height: 44)
        .background(.bar)
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
    TabStrip()
        .environment(LessonSession.preview)
}
