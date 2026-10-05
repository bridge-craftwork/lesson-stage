import SwiftUI

/// A small chip in the corner saying what the Pencil will do next.
///
/// The palette already shows the live tool, but it auto-hides after a few
/// seconds, and the Apple Pencil's double-tap deliberately does *not* bring it
/// back — annotating should never pop the toolbar over a projected lesson. So
/// between the toolbar fading and the next stroke there was nothing at all
/// saying which tool was live, and a double-tap that failed to register (the
/// Pencil's own detection is not reliable) was discovered several strokes
/// later, by erasing something.
///
/// It flares to full strength whenever the tool changes — that flare is the
/// signal a double-tap landed — then settles back quickly so it is not sitting
/// over the lesson.
struct ToolModeBadge: View {
    let tool: DrawingTool

    @State private var flaring = false
    @State private var settle: Task<Void, Never>?

    /// How long the flare holds before settling back.
    private let flareHold: Duration = .seconds(1.1)

    /// The eraser settles brighter than the drawing tools: it is the mode that
    /// destroys work, so it is the one worth still catching your eye later.
    private var restingOpacity: Double { tool == .eraser ? 0.9 : 0.72 }

    var body: some View {
        Image(systemName: tool.symbolName)
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(tool.badgeInk)
            .frame(width: 34, height: 34)
            .background(tool.badgeFill, in: .rect(cornerRadius: 9))
            .overlay {
                // A pale ring and a soft shadow between them cover both grounds
                // this can land on: the ring separates a dark chip from the
                // dark surround, the shadow separates a pale one from the page.
                RoundedRectangle(cornerRadius: 9)
                    .strokeBorder(.white.opacity(0.9), lineWidth: 1.5)
            }
            .shadow(color: .black.opacity(flaring ? 0.45 : 0.3), radius: flaring ? 6 : 3, y: 1)
            // Settling is a change of *size and weight*, never of colour.
            // Fading the chip towards transparent was the first attempt and it
            // threw away the one thing the badge is for: over a white page a
            // dimmed black pen reads as light grey, so the colour — the whole
            // signal — went first.
            .scaleEffect(flaring ? 1.18 : 1)
            .opacity(flaring ? 1 : restingOpacity)
            .accessibilityLabel("Pencil is set to \(tool.accessibilityName)")
            .accessibilityIdentifier("toolModeBadge")
            // Deliberately not `initial: true`. The flare is for confirming a
            // change you just made; firing one as the badge first appears says
            // nothing, and it left an animation in flight through launch, which
            // is enough to push out XCUITest's wait-for-idle and eat the
            // auto-hide window the chrome tests measure against.
            .onChange(of: tool) { _, _ in flare() }
            .onDisappear { settle?.cancel() }
    }

    private func flare() {
        settle?.cancel()
        withAnimation(.spring(duration: 0.22)) { flaring = true }
        settle = Task { @MainActor in
            try? await Task.sleep(for: flareHold)
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.45)) { flaring = false }
        }
    }
}
