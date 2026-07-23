import SwiftUI

extension Color {
    /// The area around the page. Deliberately dark: on a projector, a bright
    /// surround washes out the page it frames.
    static let presentationSurround = Color(white: 0.12)

    static let selectedTab = Color.primary.opacity(0.12)
}

#if DEBUG
extension LessonSession {
    /// A session with a few lessons open, for previews.
    static var preview: LessonSession {
        let session = LessonSession()
        session.open(LessonTab(title: "New Minor Forcing"))
        session.open(LessonTab(title: "Weak Two Bids"))
        session.open(LessonTab(title: "Splinter Raises"))
        return session
    }
}
#endif
