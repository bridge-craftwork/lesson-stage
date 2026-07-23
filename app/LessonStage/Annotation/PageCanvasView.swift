import PencilKit
import UIKit

/// The per-page canvas, with a touch probe.
///
/// The probe answers the one question the outside cannot: does the Pencil
/// touch reach the canvas at all? "Nothing is drawn" has two very different
/// causes — the touch never arrives (hit-testing, or another recognizer
/// claiming and cancelling it) or it arrives and PencilKit declines to make a
/// stroke from it. They need opposite fixes, and only the canvas can tell them
/// apart.
final class PageCanvasView: PKCanvasView {
    /// Set in debug builds only; nil in a shipping build, where the overrides
    /// below reduce to a plain `super` call.
    weak var diagnostics: CanvasDiagnostics?

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        report(touches, phase: "began")
        super.touchesBegan(touches, with: event)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        report(touches, phase: "moved")
        super.touchesMoved(touches, with: event)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        // The interesting one: a cancel means something upstream claimed the
        // touch after the canvas had already started receiving it.
        report(touches, phase: "CANCELLED")
        super.touchesCancelled(touches, with: event)
    }

    private func report(_ touches: Set<UITouch>, phase: String) {
        guard let diagnostics, let touch = touches.first else { return }
        let kind = switch touch.type {
        case .direct: "finger"
        case .pencil: "pencil"
        case .indirectPointer: "pointer"
        default: "other(\(touch.type.rawValue))"
        }
        MainActor.assumeIsolated {
            diagnostics.recordCoalesced("touch \(phase) — \(kind), page \(tag)")
        }
    }
}
