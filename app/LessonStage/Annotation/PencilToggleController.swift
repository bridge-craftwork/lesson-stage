import UIKit

/// Bridges the Apple Pencil double-tap to a plain closure.
///
/// The gesture is on the pencil, not the screen, and only Apple Pencil 2nd
/// gen and Pencil Pro report it — and only when the user has left the gesture
/// enabled in Settings (its default there is already "switch to eraser", which
/// is exactly this). A USB-C pencil or 1st gen never fires it, so the feature
/// is simply absent on that hardware rather than broken.
@MainActor
final class PencilToggleController: NSObject, UIPencilInteractionDelegate {
    var onTap: () -> Void = {}

    // iPadOS 17.5 replaced `pencilInteractionDidTap` with a Tap-carrying
    // variant. Implement the new one where available and the old one for the
    // 17.0–17.4 floor; the system calls whichever is newest, so the toggle
    // never fires twice.
    @available(iOS 17.5, *)
    func pencilInteraction(_ interaction: UIPencilInteraction, didReceiveTap tap: UIPencilInteraction.Tap) {
        onTap()
    }

    func pencilInteractionDidTap(_ interaction: UIPencilInteraction) {
        onTap()
    }
}
