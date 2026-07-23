import SwiftUI

/// The diagnostics tab: what the input layer is doing, on the iPad itself.
///
/// A tab rather than an overlay on the page, because an overlay would sit in
/// front of the very canvas being diagnosed — either blocking the touches
/// under investigation or needing to be made transparent to them, which is one
/// more thing that can be wrong. Draw on the lesson, switch here, read what
/// happened.
struct DiagnosticsView: View {
    let diagnostics: CanvasDiagnostics

    @State private var copied = false

    /// Oldest first on the clipboard — the panel shows newest first for
    /// watching live, but pasted into a conversation it should read forwards.
    private func copyAll() {
        UIPasteboard.general.string = diagnostics.entries
            .reversed()
            .map(\.text)
            .joined(separator: "\n")

        copied = true
        Task {
            try? await Task.sleep(for: .seconds(2))
            copied = false
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 16) {
                Text("Input diagnostics")
                    .font(.headline)
                Spacer()
                Button(copied ? "Copied" : "Copy") { copyAll() }
                    .disabled(diagnostics.entries.isEmpty)
                    .accessibilityIdentifier("copyDiagnostics")
                Button("Clear") { diagnostics.clear() }
                    .accessibilityIdentifier("clearDiagnostics")
            }
            .padding()

            Divider()

            if diagnostics.entries.isEmpty {
                VStack(spacing: 8) {
                    Text("Nothing recorded yet")
                        .font(.callout)
                    Text("Draw on a lesson, then come back here.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        ForEach(diagnostics.entries) { entry in
                            Text(entry.text)
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Divider().opacity(0.3)
                        }
                    }
                    .padding()
                }
            }
        }
        .background(Color.presentationSurround)
        .accessibilityIdentifier("diagnosticsView")
    }
}
