import SwiftUI

/// The Load-from-Library day list: the window of class days around today. Tap a
/// populated day to replace the open tabs with its handouts. Empty (precreated
/// but unplanned) days show dimmed and can't be opened.
struct LibraryDayListView: View {
    @Environment(LibraryManager.self) private var library
    @Environment(LessonSession.self) private var session
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if library.days.isEmpty && library.isRefreshing {
                    ProgressView("Scanning lessons…")
                        .accessibilityIdentifier("libraryLoading")
                } else if library.days.isEmpty {
                    emptyState
                } else {
                    List {
                        ForEach(library.days) { day in
                            DayRow(day: day, isAnchor: day.id == library.anchorID) {
                                library.openDay(day, into: session)
                                dismiss()
                            }
                        }
                    }
                }
            }
            .navigationTitle("Load from Library")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        // Re-scan on open: a class folder filled in since last time should show
        // without a relaunch. Reading names only, so it's cheap.
        .onAppear { library.refresh() }
        .accessibilityIdentifier("librarySheet")
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No lesson days found", systemImage: "calendar")
        } description: {
            Text("No dated lesson folders under the chosen folder, or none within the current window.")
        }
    }
}

private struct DayRow: View {
    let day: LessonDay
    let isAnchor: Bool
    let open: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(Self.dateText(day.date))
                    .font(.headline)
                    .foregroundStyle(day.isPopulated ? .primary : .secondary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            if isAnchor {
                Text("Next class")
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.accentColor.opacity(0.2), in: .capsule)
                    .foregroundStyle(Color.accentColor)
            }

            if day.isPopulated {
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
        // Whole-row tap over the filled area, the same pattern the tab strip
        // uses — a plain `Button` with a combined accessibility element did not
        // forward synthesized taps to its action.
        .contentShape(.rect)
        .onTapGesture { if day.isPopulated { open() } }
        .foregroundStyle(day.isPopulated ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
        .listRowBackground(isAnchor ? Color.accentColor.opacity(0.08) : nil)
        .accessibilityElement(children: .combine)
        // A precreated-but-empty day has nothing to open; it shows dimmed so the
        // slot is visible, but only populated days carry the button trait.
        .accessibilityAddTraits(day.isPopulated ? .isButton : [])
        .accessibilityIdentifier("day-\(day.folderURL.lastPathComponent)")
    }

    private var subtitle: String {
        guard day.isPopulated else { return "Not planned" }
        let count = day.handouts.count
        return count == 1 ? "1 handout" : "\(count) handouts"
    }

    private static func dateText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.setLocalizedDateFormatFromTemplate("EEEEMMMMd")
        return formatter.string(from: date)
    }
}

#Preview {
    LibraryDayListView()
        .environment(LibraryManager())
        .environment(LessonSession.preview)
        .preferredColorScheme(.dark)
}
