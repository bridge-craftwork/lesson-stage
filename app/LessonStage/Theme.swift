import SwiftUI

extension Color {
    /// The area around the page. Deliberately dark: on a projector, a bright
    /// surround washes out the page it frames.
    static let presentationSurround = Color(white: 0.12)

    static let sidebarSurface = Color(white: 0.16)

    static let tabStripSurface = Color(white: 0.18)

    static let selectedTab = Color.primary.opacity(0.12)

    static let selectedTool = Color.accentColor.opacity(0.28)
}

#if DEBUG
extension LessonSession {
    /// An empty session for previews. Previews cannot open real documents —
    /// the picker and the security scope both need a running app — so this
    /// deliberately has no tabs rather than fake ones that would render as
    /// broken.
    @MainActor
    static var preview: LessonSession { LessonSession() }
}
#endif
