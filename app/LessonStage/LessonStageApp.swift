import SwiftUI

@main
struct LessonStageApp: App {
    @State private var session = LessonSession()

    var body: some Scene {
        WindowGroup {
            LessonStageView()
                .environment(session)
                // The surround is dark by design, so the whole shell is dark:
                // system text and materials must resolve against it, not
                // against a light scheme that renders them dark-on-dark.
                .preferredColorScheme(.dark)
        }
    }
}
