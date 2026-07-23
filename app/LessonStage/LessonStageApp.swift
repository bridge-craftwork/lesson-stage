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
                .task {
                    #if DEBUG
                    if ProcessInfo.processInfo.arguments.contains("-reset") {
                        session.discardSavedSession()
                    }
                    #endif
                    session.restore()
                    openLaunchArgumentFiles()
                }
        }
    }

    /// Debug launch arguments, so the app can be driven without a tap:
    ///
    ///   -reset          discard any saved session before restoring
    ///   -open <path>…   open files directly, bypassing the document picker
    ///   -page <n>       start the active tab on 1-based page `n`
    ///   -thumbnails     open with the page sidebar showing
    ///   -present        open in presentation mode
    ///
    /// None of this exists in a shipping build. It is here because neither the
    /// document picker nor a tap can be scripted, and a reading surface that
    /// is never exercised is a reading surface that is never verified.
    private func openLaunchArgumentFiles() {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments

        if let flag = arguments.firstIndex(of: "-open") {
            let paths = arguments[(flag + 1)...].prefix { !$0.hasPrefix("-") }
            session.open(urls: paths.map { URL(fileURLWithPath: $0) })
        }

        if let flag = arguments.firstIndex(of: "-page"),
           let page = arguments[safe: flag + 1].flatMap(Int.init),
           let tab = session.selectedTab {
            // Goes through the same path a reader's scroll takes, so the
            // position is persisted rather than only displayed.
            session.recordPage(max(0, page - 1), for: tab.id)
        }

        session.showsThumbnails = arguments.contains("-thumbnails")
        session.isPresenting = arguments.contains("-present")
        #endif
    }
}
