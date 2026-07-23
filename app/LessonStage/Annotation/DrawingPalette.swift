import SwiftUI

/// The marking palette: a draw toggle, the tools, and undo.
///
/// Hidden in presentation mode along with the rest of the chrome — the class
/// should see the lesson, not the teacher's toolbar.
struct DrawingPalette: View {
    @Environment(LessonSession.self) private var session
    let host: PDFViewHost
    let drawings: DrawingSet?

    var body: some View {
        HStack(spacing: 10) {
            Toggle(isOn: drawingEnabled) {
                Image(systemName: "hand.draw")
            }
            .toggleStyle(.button)
            .accessibilityLabel("Pencil marks the page")
            .accessibilityIdentifier("drawToggle")

            if session.isDrawingEnabled {
                Divider().frame(height: 22)

                ForEach(DrawingTool.allCases, id: \.self) { tool in
                    toolButton(tool)
                }

                Divider().frame(height: 22)

                Button {
                    host.canvases.undo()
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                }
                .accessibilityLabel("Undo")
                .accessibilityIdentifier("undo")

                Button {
                    host.canvases.clearAllMarks()
                } label: {
                    Image(systemName: "trash")
                }
                // No confirmation, by design: it is one undo away from being
                // restored, which is faster than a dialog and just as safe.
                .disabled(!(drawings?.hasAnnotations ?? false))
                .accessibilityLabel("Clear all marks")
                .accessibilityIdentifier("clearAllMarks")
            }

            #if DEBUG
            // A PKDrawing is invisible to the accessibility tree, so the app
            // has to report its own state for a UI test to assert on.
            Text("\(drawings?.annotatedPageCount ?? 0)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.tertiary)
                .accessibilityIdentifier("annotatedPageCount")
            #endif
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.thinMaterial, in: .capsule)
    }

    private var drawingEnabled: Binding<Bool> {
        Binding(
            get: { session.isDrawingEnabled },
            set: { newValue in
                session.isDrawingEnabled = newValue
                host.canvases.isDrawingEnabled = newValue
            }
        )
    }

    private func toolButton(_ tool: DrawingTool) -> some View {
        Button {
            session.tool = tool
            host.canvases.tool = tool
        } label: {
            Image(systemName: tool.symbolName)
                .foregroundStyle(tool.tint ?? .primary)
                .padding(6)
                .background(
                    session.tool == tool ? Color.selectedTool : .clear,
                    in: .rect(cornerRadius: 7)
                )
        }
        .accessibilityLabel(tool.accessibilityName)
        .accessibilityIdentifier("tool-\(tool.accessibilityName)")
        .accessibilityAddTraits(session.tool == tool ? [.isSelected] : [])
    }
}
