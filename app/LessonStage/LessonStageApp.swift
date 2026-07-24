import SwiftUI

@main
struct LessonStageApp: App {
    @State private var session = LessonSession()
    @State private var library = LibraryManager()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            LessonStageView()
                .environment(session)
                .environment(library)
                // The surround is dark by design, so the whole shell is dark:
                // system text and materials must resolve against it, not
                // against a light scheme that renders them dark-on-dark.
                .preferredColorScheme(.dark)
                .task {
                    #if DEBUG
                    if ProcessInfo.processInfo.arguments.contains("-reset") {
                        session.discardSavedSession()
                        library.discardSettings()
                    }
                    #endif
                    session.restore()
                    openLaunchArgumentFiles()
                }
                .onChange(of: scenePhase) { _, phase in
                    // Suspension can follow immediately; do not let the save
                    // debounce be holding the last strokes when it does.
                    if phase != .active { session.flushDrawings() }
                }
        }
    }

    /// Debug launch arguments, so the app can be driven without a tap:
    ///
    ///   -reset            discard any saved session before restoring
    ///   -open <path>…     open files directly, bypassing the document picker
    ///   -page <n>         start the active tab on 1-based page `n`
    ///   -thumbnails       open with the page sidebar showing
    ///   -present          open in presentation mode
    ///   -libraryEnabled   turn on Load from Library
    ///   -libraryRoot <p>  configure the library root to path `p`, no picker
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

        // The directory picker is a system UI a test cannot drive, so the
        // library root arrives by path — the same reason `-open` exists.
        if arguments.contains("-libraryEnabled") { library.setEnabled(true) }
        if let flag = arguments.firstIndex(of: "-libraryRoot"),
           let path = arguments[safe: flag + 1], !path.hasPrefix("-") {
            library.configure(rootURL: URL(fileURLWithPath: path))
        }
        #endif
    }
}
